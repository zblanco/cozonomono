# Phase 2.3: Multi-Statement Transactions — Implementation Notes

## What was added

A new resource type and four NIF functions for atomic multi-statement transactions:

- `Cozonomono.multi_transaction(instance, write \\ true)` → `{:ok, %Transaction{}}`
- `Cozonomono.tx_query(tx, query, params \\ nil)` → `{:ok, %NamedRows{}}` | `{:error, term()}`
- `Cozonomono.tx_commit(tx)` → `:ok`
- `Cozonomono.tx_abort(tx)` → `:ok`

## New resource type: `ExMultiTransaction`

This follows the same two-type resource pattern as `ExDbInstance`:

```
Elixir:  %Cozonomono.Transaction{resource: ref, write: true}
             │
             ▼  (NifStruct mapping)
Rust:    ExMultiTransaction { resource: ResourceArc<ExMultiTransactionRef>, write: bool }
             │
             ▼  (Deref)
Rust:    cozo::MultiTransaction { sender: Sender<...>, receiver: Receiver<...> }
```

- **`ExMultiTransactionRef`** — wraps `cozo::MultiTransaction` as a BEAM resource type (registered via `rustler::resource!` in `on_load`)
- **`ExMultiTransaction`** — a `#[derive(NifStruct)]` with `#[module = "Cozonomono.Transaction"]` containing a `ResourceArc<ExMultiTransactionRef>` plus a `write` flag
- **`Deref` impl** — lets NIF functions call `tx.run_script(...)`, `tx.commit()`, `tx.abort()` directly

## How CozoDB transactions work internally

Understanding this is important for knowing why the NIF implementation is safe:

```
┌─────────────────────┐         bounded(1)          ┌──────────────────────┐
│   NIF thread        │  ──── TransactionPayload ──▶ │  CozoDB worker       │
│   (BEAM DirtyCpu)   │                              │  thread (rayon)      │
│                     │  ◀──── Result<NamedRows> ─── │                      │
└─────────────────────┘         bounded(1)          └──────────────────────┘
```

When you call `DbInstance::multi_transaction(write)`, CozoDB:
1. Creates two **crossbeam bounded channels** with capacity 1
2. Spawns a **rayon thread** that holds the actual database transaction lock
3. Returns a `MultiTransaction` struct containing the send/receive ends

Each call to `tx.run_script(...)` sends a `TransactionPayload::Query(...)` through the channel and blocks waiting for the result. Because we use `#[rustler::nif(schedule = "DirtyCpu")]`, this blocking happens on a dirty scheduler and doesn't interfere with the BEAM's normal schedulers.

The bounded(1) channels naturally serialize access — if two BEAM processes somehow shared the same transaction handle and called `tx_query` simultaneously, one would block until the other's query completes.

`tx.commit()` sends `TransactionPayload::Commit` and `tx.abort()` sends `TransactionPayload::Abort`, both of which cause the worker thread to finalize and exit.

## Why `multi_transaction` returns directly (not `Result`)

The NIF function signature is:

```rust
fn multi_transaction(instance: ExDbInstance, write: bool) -> ExMultiTransaction
```

Note: no `Result` wrapper. `DbInstance::multi_transaction()` never fails — it always succeeds in creating the channel pair and spawning the worker. Errors only happen later when running queries or committing/aborting. So the Elixir wrapper wraps it in `{:ok, tx}` itself.

## Elixir API design choices

- **`tx_query` instead of `tx_run`** — named to mirror `Cozonomono.query/3` for familiarity
- **`params` defaults to `nil`** — converted to `%{}` before passing to the NIF, matching the existing `query/3` pattern
- **Write defaults to `true`** — most transactions need writes; pass `false` explicitly for read-only

## Files changed

| File | Change |
|------|--------|
| `native/.../datatypes.rs` | Added `ExMultiTransactionRef`, `ExMultiTransaction` (NifStruct), `Deref` impl |
| `native/.../lib.rs` | Added `multi_transaction`, `tx_run_script`, `tx_commit`, `tx_abort` NIF functions; registered `ExMultiTransactionRef` resource |
| `lib/cozonomono/transaction.ex` | New Elixir struct matching the Rust NifStruct |
| `lib/cozonomono.ex` | Added `multi_transaction/2`, `tx_query/3`, `tx_commit/1`, `tx_abort/1` public API |
| `lib/cozonomono/native.ex` | Added NIF stubs |
| `test/transaction_test.exs` | 7 tests covering create, query, params, commit, abort, and read-only transactions |
