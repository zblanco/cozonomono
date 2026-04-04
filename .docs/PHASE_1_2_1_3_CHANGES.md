# Phase 1.2 & 1.3: NamedRows Struct & Instance Lifecycle

## Phase 1.2: Proper NamedRows Struct

### The Problem

Query results were returned as plain Elixir maps with string keys:

```elixir
{:ok, %{"headers" => ["_0"], "rows" => [["hello"]], "next" => nil}}
```

This works but has downsides: no compile-time field access checks, no pattern matching on struct type, and no place to hang documentation or typespecs.

### The Solution

**Elixir side** — new `Cozonomono.NamedRows` struct (`lib/cozonomono/named_rows.ex`):

```elixir
defstruct headers: [], rows: [], next: nil
```

Three fields, matching exactly what CozoDB's `NamedRows` provides. The `next` field is either `nil` or another `%NamedRows{}` (for chained multi-statement results).

**Rust side** — the change is in how `ExNamedRows` builds the map it returns.

### How Elixir Structs Work Under the Hood

An Elixir struct like `%Cozonomono.NamedRows{headers: ["a"], rows: [[1]], next: nil}` is really just a map with a special `__struct__` key:

```elixir
%{
  __struct__: Cozonomono.NamedRows,
  headers: ["a"],
  rows: [[1]],
  next: nil
}
```

The value of `__struct__` is the module atom `Elixir.Cozonomono.NamedRows` (Elixir modules are atoms prefixed with `Elixir.` internally). The keys are atoms, not strings.

### What Changed in Rust

The old encoder used string keys to build a plain map:

```rust
// OLD — returns a plain map with string keys
let map = rustler::Term::map_new(env)
    .map_put("headers".encode(env), headers)  // string key "headers"
    .map_put("rows".encode(env), rows_term)
    .map_put("next".encode(env), next);
```

The new encoder uses atom keys and includes the `__struct__` key:

```rust
// NEW — returns a %Cozonomono.NamedRows{} struct
let map = rustler::Term::map_new(env)
    .map_put(atoms::__struct__().encode(env), atoms::named_rows_struct().encode(env))
    .map_put(atoms::headers().encode(env), headers)    // atom key :headers
    .map_put(atoms::rows().encode(env), rows_term)
    .map_put(atoms::next().encode(env), next);
```

### The Atoms Module

We expanded the `rustler::atoms!` block with the atoms needed for the struct:

```rust
mod atoms {
    rustler::atoms! {
        // ...existing atoms...
        named_rows_struct = "Elixir.Cozonomono.NamedRows",  // the module atom
        __struct__,   // the literal atom :__struct__
        headers,      // the literal atom :headers
        rows,         // the literal atom :rows
        next,         // the literal atom :next
    }
}
```

**Why two separate entries for the struct?** The `rustler::atoms!` macro maps Rust identifiers to BEAM atom strings. We need two different atoms:

1. `__struct__` → the atom `:__struct__` (used as the **key** in the map)
2. `named_rows_struct` → the atom `:"Elixir.Cozonomono.NamedRows"` (used as the **value** — this is how BEAM represents the module name)

We can't name both `__struct__` in Rust, so the value atom gets a different Rust name (`named_rows_struct`) with the `= "Elixir.Cozonomono.NamedRows"` syntax telling the macro what actual atom string to intern.

### Why Not Use `#[derive(NifStruct)]`?

Rustler's `#[derive(NifStruct)]` macro (which we use for `ExDbInstance`) automatically handles the `__struct__` key mapping. But it requires all fields to implement Rustler's `Encoder`/`Decoder` derives. Our `ExNamedRows` has two complications:

1. **`rows`** contains `Vec<Vec<DataValue>>` where `DataValue` uses our custom `ExDataValue` encoder — not a Rustler-derivable type
2. **`next`** is `Option<Box<NamedRows>>` — a recursive type that would need custom handling anyway

So we keep the manual `Encoder` impl, but now it builds a proper struct map instead of a plain map. This is exactly the same pattern Explorer uses for performance-critical encoding paths.

---

## Phase 1.3: Instance Lifecycle

### The Question

When you create a `%Cozonomono.Instance{}` with `Cozonomono.new()`, a `cozo::DbInstance` is allocated on the Rust heap and wrapped in a `ResourceArc`. What happens when you're done with it?

### How ResourceArc Cleanup Works

`ResourceArc<T>` is Rustler's smart pointer that integrates with the BEAM's garbage collector:

1. When `Cozonomono.new()` is called, Rust allocates a `DbInstance` and wraps it in `ResourceArc::new(ExDbInstanceRef(instance))`
2. The `ResourceArc` registers with the BEAM as a **resource object** — the BEAM tracks a reference count for it
3. The Elixir struct `%Instance{resource: ref}` holds one reference to this resource
4. Every time the struct is passed to a NIF (like `query/3`), Rustler temporarily increments the reference count
5. When the Elixir process that holds the struct terminates, or when the variable is garbage collected, the BEAM decrements the reference count
6. When the count reaches zero, Rust's `Drop` trait runs on `ExDbInstanceRef`, which drops the inner `DbInstance`, releasing all storage engine resources (file handles, locks, memory)

**This means cleanup is automatic** — you don't need to explicitly close instances.

### Why Add `close/1` Anyway?

For in-memory instances, GC cleanup is fine. But for file-backed engines (`:sqlite`, `:rocksdb`):

- File locks are held until GC runs, which is non-deterministic
- Another process trying to open the same database file could be blocked
- In long-running GenServers, the instance might not be GC'd for a long time

`close/1` lets you deterministically release these resources.

### The close_instance NIF

```rust
#[rustler::nif]
fn close_instance(instance: ExDbInstance) -> Result<rustler::Atom, ExError> {
    drop(instance);
    Ok(rustler::types::atom::ok())
}
```

**What `drop(instance)` does**: Rust's `drop()` function consumes the value and runs its destructor. For `ExDbInstance`, this drops the `ResourceArc`, decrementing the reference count. However, the Elixir side still holds its own copy of the struct with its own reference to the `ResourceArc`, so the actual `DbInstance` won't be freed until that Elixir reference is also garbage collected.

**Important subtlety**: Because `ResourceArc` is reference-counted, calling `close/1` doesn't immediately invalidate the instance. The Elixir struct still holds a valid reference. The instance is only truly freed when *all* references are dropped. This means queries after `close/1` will still work — `close/1` is a hint to release *one* reference early, not a hard invalidation.

This is the same behavior as Explorer — there's no way to forcibly invalidate a `ResourceArc` from outside because the BEAM's GC owns the lifecycle.

### No `#[rustler::nif(schedule = "DirtyCpu")]` on close

Unlike `create_instance` and the query NIFs, `close_instance` doesn't use `schedule = "DirtyCpu"`. The `drop()` call just decrements a reference count (an atomic integer operation) — it completes in nanoseconds and doesn't block a scheduler.

---

## Files Changed

### New Files
- `lib/cozonomono/named_rows.ex` — `Cozonomono.NamedRows` struct definition
- `test/instance_test.exs` — Tests for `close/1`, engine types, and GC behavior

### Modified Files
- `lib/cozonomono.ex` — Added `close/1`, updated typespecs to use `NamedRows.t()`, fixed `engine` type (was `:rocksb`, now `:rocksdb`)
- `lib/cozonomono/native.ex` — Added `close_instance/1` NIF stub
- `native/cozonomono_cozo/src/lib.rs` — Added `close_instance` NIF function, registered in `rustler::init!`
- `native/cozonomono_cozo/src/datatypes.rs` — Added struct-related atoms, updated `ExNamedRows` encoder to produce `%Cozonomono.NamedRows{}` structs
- `test/cozonomono_test.exs` — Updated to match on `%NamedRows{}` instead of plain maps
- `test/data_value_test.exs` — Updated to match on `%NamedRows{}` instead of plain maps
