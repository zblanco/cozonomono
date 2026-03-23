# Phase 3.1: Change Callbacks — How Rust Threads Bridge to BEAM Processes

## What We Built

CozoDB has a built-in change notification system: you register a callback on a stored relation, and whenever a `:put` or `:rm` mutation commits, CozoDB sends the old and new rows through a crossbeam channel. We needed to bridge this into Elixir, so that an Elixir process receives `{:cozo_callback, :put | :rm, %NamedRows{}, %NamedRows{}}` messages in its mailbox.

## The Core Problem

The BEAM VM runs Elixir/Erlang code on **scheduler threads** it controls. NIFs are called on these threads. But CozoDB's callback system uses crossbeam channels that block on `recv()` — you can't block a BEAM scheduler thread. We need a plain OS thread that reads from the CozoDB channel and forwards messages into the BEAM's process mailbox system.

## Key Rust Concepts (Elixir Analogies)

### `LocalPid` — A Handle to a BEAM Process

Think of this as the Rust equivalent of a PID you get from `self()` in Elixir. When the Elixir side passes `self()` to the NIF, Rustler decodes it into a `LocalPid` struct. This struct is `Copy` (like a simple integer — no ownership concerns), so we can move it freely into closures and threads.

```rust
fn register_callback(instance: ExDbInstance, relation: String, pid: LocalPid, ...) -> u32
//                                                                  ^^^^^^^^^^
//                                         Elixir's self() becomes this Rust value
```

### `OwnedEnv` — A Scratch Heap for Building Terms Off-Scheduler

In a normal NIF call, Rustler gives you an `Env<'a>` — a handle to the calling process's term heap. You can only use it during that NIF call. But our forwarding thread lives long after the NIF returns, so we need our own heap.

`OwnedEnv::new()` allocates a process-independent heap — think of it as a temporary workspace for constructing Elixir terms that aren't yet owned by any process. It's `Send`, so it can move into a `std::thread::spawn` closure.

**Elixir analogy**: Imagine if you could create a throwaway process just to build a message, then send that message to another process and discard the throwaway. That's what `OwnedEnv` does at the C NIF level.

### `send_and_clear` — The Bridge

```rust
msg_env.send_and_clear(&pid, |env| {
    // Build the Elixir term here using `env`
    (atoms::cozo_callback(), op_atom, ExNamedRows(new_rows).encode(env), ExNamedRows(old_rows).encode(env)).encode(env)
});
```

This method:
1. Runs your closure to build a term on the `OwnedEnv`'s heap
2. Calls `enif_send()` with the BEAM's C API — this atomically transfers the term into the target process's mailbox
3. Clears the heap for reuse (so you don't leak memory in a loop)

**Critical constraint**: `send_and_clear` **panics** if called from a BEAM scheduler thread (including dirty schedulers). That's why we use `std::thread::spawn` — it creates a plain OS thread that the BEAM doesn't manage.

## Architecture Flow

```
Elixir Process                          Rust NIF (DirtyCpu scheduler)
     │                                       │
     │ register_callback(instance,           │
     │   "users", self())                    │
     │ ─────────────────────────────────────►│
     │                                       │
     │                                       ├─ CozoDB: register_callback("users", capacity)
     │                                       │    returns (id=42, Receiver)
     │                                       │
     │                                       ├─ std::thread::spawn ──────────────────────┐
     │                                       │                                            │
     │    {:ok, 42}                          │                            Forwarder Thread │
     │ ◄─────────────────────────────────────│                                            │
     │                                       │                    receiver.recv() [blocks] │
     │                                                                                    │
     │ query("... :put users ...")                                                        │
     │ ───────────────────────────────────────────► CozoDB sends on channel ──────────────►│
     │                                                                                    │
     │                                                              OwnedEnv.send_and_clear
     │ {:cozo_callback, :put, new_rows, old_rows}                          │
     │ ◄───────────────────────────────────────────────────────────────────┘
```

## Why `std::thread::spawn` and Not Dirty Scheduler

- **Dirty schedulers** (`#[rustler::nif(schedule = "DirtyCpu")]`) are still managed by the BEAM — `send_and_clear` panics on them.
- The `register_callback` NIF itself runs on DirtyCpu because it calls CozoDB's registration (which acquires locks), but the **forwarding thread** must be a plain OS thread.
- The thread naturally terminates when: (a) the crossbeam `Receiver` is disconnected (CozoDB dropped the `Sender`, e.g., on unregister), or (b) `send_and_clear` returns `Err` (target process is dead).

## Zero-Copy Considerations

Currently, each callback message copies the `NamedRows` data when encoding it into the `OwnedEnv`. This is the same encoding path used for query results. In Phase 4, we could explore:

- Wrapping callback `NamedRows` in a `ResourceArc` and sending only the opaque reference (zero-copy for the row data)
- Lazy encoding: send a resource ref, let Elixir call a NIF to extract specific columns on demand

For now, the copy-per-message approach is correct and matches the semantics of CozoDB's callback system (which already clones the rows internally for the last subscriber).

## Files Changed

| File | What Changed |
|------|-------------|
| `native/.../datatypes.rs` | Made `atoms` module `pub(crate)`, added `cozo_callback`, `put`, `rm` atoms |
| `native/.../lib.rs` | Added `register_callback` and `unregister_callback` NIF functions |
| `lib/cozonomono/native.ex` | Added NIF stubs for `register_callback/4` and `unregister_callback/2` |
| `lib/cozonomono.ex` | Added public `register_callback/3` and `unregister_callback/2` with docs |
| `test/callback_test.exs` | 9 tests: put/rm, multiple fires, unregistration, custom pid, bounded capacity |

## Test Count: 72 (was 63)
