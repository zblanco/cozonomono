# Phase 4.1: Zero-Copy Query Results

## Problem

When you called `Cozonomono.query/3`, the Rust NIF would:

1. Execute the CozoDB query → get a `NamedRows` struct on the Rust heap
2. **Immediately encode every row, every cell, every string** into BEAM terms
3. Return the fully-materialized `%Cozonomono.NamedRows{}` Elixir struct

For a 10,000-row result with 5 columns, this meant encoding 50,000 values on every query call — even if you only needed the first row or a single column. For 100k rows, the encoding alone took ~680ms.

## Solution: Lazy Results via ResourceArc

The fix follows Explorer's pattern: **keep query results on the Rust heap** and only copy data to the BEAM when explicitly accessed.

### Architecture

```
query_lazy/3
  → Rust runs CozoDB query → gets NamedRows
  → Wraps in ResourceArc<ExLazyRowsRef>  (stays on Rust heap)
  → Returns %LazyRows{} with metadata only (headers, row_count, etc.)

LazyRows.row_at(lazy, 0)
  → NIF reads row[0] from Rust heap
  → Encodes only that one row into BEAM terms
  → Returns {:ok, [1, "Alice", 95.5]}
```

### What Changed on the Rust Side

#### 1. Borrow-Based Encoding Helpers (eliminates clones)

**Before:** The `Encoder` implementations for `ExDataValue` and `ExNamedRows` cloned data unnecessarily:

```rust
// OLD: cloned every DataValue just to encode it
DataValue::List(list) => list
    .iter()
    .map(|data_value| ExDataValue(data_value.clone()))  // clone!
    .collect::<Vec<ExDataValue>>()
    .encode(env),

// OLD: cloned entire next chain
Some(boxed_next) => ExNamedRows((**boxed_next).clone()).encode(env),  // deep clone!
```

**After:** New standalone functions take `&DataValue` and `&NamedRows` references:

```rust
// NEW: borrows, no clone
pub(crate) fn encode_data_value<'a>(value: &DataValue, env: Env<'a>) -> Term<'a> {
    // works directly with the reference
}

pub(crate) fn encode_named_rows<'a>(named_rows: &NamedRows, env: Env<'a>) -> Term<'a> {
    // recursive on &NamedRows, no clone
}
```

**Rust concept for Elixir devs:** In Rust, `&` means "borrow" — you're reading data without taking ownership or copying it. Think of it like passing a reference in Elixir, except Rust's compiler guarantees at compile time that the data won't be freed while you're still reading it. The old code was calling `.clone()` which is like `Kernel.deep_copy` — it duplicates the entire data structure in memory just so the `Encoder` trait can own it temporarily.

The `Encoder` trait impls now delegate to these helpers:

```rust
impl Encoder for ExDataValue {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        encode_data_value(&self.0, env)  // borrow self.0
    }
}
```

This means the existing eager path also got faster (no more unnecessary clones).

#### 2. LazyRows Resource Type

```rust
/// Owns the flattened chain of query results on the Rust heap.
pub struct ExLazyRowsRef(pub Vec<NamedRows>);
```

**Why `Vec<NamedRows>` instead of just `NamedRows`?** CozoDB's `NamedRows` uses a linked-list `next` field for multi-statement results. We flatten it into a `Vec` at construction time so we can index into any statement's result in O(1). The flatten is zero-copy — it uses `.take()` to move ownership:

```rust
pub fn flatten_named_rows(mut current: NamedRows) -> Vec<NamedRows> {
    let mut out = Vec::new();
    loop {
        let next = current.next.take().map(|boxed| *boxed);
        out.push(current);
        match next {
            Some(n) => current = n,
            None => break,
        }
    }
    out
}
```

**Rust concept:** `.take()` on an `Option<Box<T>>` replaces the value with `None` and gives you ownership of the `Box<T>`. Then `*boxed` moves the `T` out of the `Box`. No data is copied — ownership just transfers. Think of it like Elixir's pattern matching where you destructure a tuple and the original variable becomes unusable.

#### 3. NifStruct with Metadata

```rust
#[derive(NifStruct)]
#[module = "Cozonomono.LazyRows"]
pub struct ExLazyRows {
    pub resource: ResourceArc<ExLazyRowsRef>,  // opaque ref to Rust heap
    pub statement_index: usize,                 // which statement in the chain
    pub headers: Vec<String>,                   // copied to BEAM (small)
    pub row_count: usize,                       // copied to BEAM
    pub column_count: usize,                    // copied to BEAM
    pub has_next: bool,                         // copied to BEAM
}
```

The metadata fields (headers, row_count, etc.) are small and copied eagerly so Elixir code can read them without a NIF call. The actual row data stays behind the `ResourceArc`.

**Rust concept:** `ResourceArc` is Rustler's equivalent of a BEAM resource — it's reference-counted like Erlang refs. The data (`Vec<NamedRows>`) lives on the Rust heap and is only freed when the last Elixir reference to the `%LazyRows{}` struct is garbage collected. Multiple `%LazyRows{}` structs can share the same `ResourceArc` (e.g., when you call `next/1`).

#### 4. Accessor NIFs

Each accessor NIF borrows data from the resource and encodes only what's requested:

```rust
#[rustler::nif]
fn lazy_rows_cell_at(env: Env, lazy: ExLazyRows, row_index: usize, col_index: usize)
    -> Result<Term, rustler::Atom>
{
    let nr = &lazy.resource.0[lazy.statement_index];  // borrow the NamedRows
    let row = nr.rows.get(row_index).ok_or(atoms::out_of_bounds())?;
    let cell = row.get(col_index).ok_or(atoms::out_of_bounds())?;
    Ok(encode_data_value(cell, env))  // encode just one cell
}
```

**Scheduling:** `cell_at` and `next` use bare `#[rustler::nif]` (fast — just pointer arithmetic + single value encoding). `column_at`, `slice`, `to_named_rows` use `#[rustler::nif(schedule = "DirtyCpu")]` because they may encode many values.

### What Changed on the Elixir Side

New module `Cozonomono.LazyRows` with accessor functions, plus `query_lazy/3` and `tx_query_lazy/3` on `Cozonomono`.

The existing `query/3` API is **completely unchanged** — this is additive.

### Benchmark Results (10,000 rows × 5 columns)

| Operation | Time | vs Eager Full Query |
|-----------|------|---------------------|
| `query_lazy/3` (return) | ~58ms | Same (query dominates) |
| `cell_at(0, 0)` | 2.3μs | **27,000× faster** |
| `row_at(0)` | 3.5μs | **18,000× faster** |
| `slice(0, 100)` | 41μs | **1,500× faster** |
| `column_at(0)` | 368μs | **170× faster** |
| `to_named_rows()` | 3.9ms | **16× faster** |
| `query/3` (eager, same query) | 62ms | baseline |

**Key insight:** `to_named_rows()` is 16× faster than `query/3` because it doesn't re-execute the CozoDB query — it encodes from data already on the Rust heap. This means `query_lazy |> to_named_rows` separates "query execution" from "result encoding", which is useful even when you want all the data.

### Memory Model

A `%LazyRows{}` pins the **entire** flattened result chain in Rust memory until the BEAM garbage collects the last reference. This means:

- ✅ Safe to use after `close(instance)` — the data is self-contained
- ✅ Multiple `%LazyRows{}` from `next/1` share one allocation
- ⚠️ Don't store large lazy results in long-lived GenServer state unless needed

### Files Changed

| File | Changes |
|------|---------|
| `native/.../datatypes.rs` | New atoms, borrow-based encoding helpers, `ExLazyRowsRef`, `ExLazyRows`, `flatten_named_rows` |
| `native/.../lib.rs` | New lazy query + accessor NIFs, resource registration |
| `lib/cozonomono.ex` | `query_lazy/3`, `tx_query_lazy/3` |
| `lib/cozonomono/lazy_rows.ex` | New module with accessor functions |
| `lib/cozonomono/native.ex` | 9 new NIF stubs |
| `test/lazy_rows_test.exs` | 22 new tests |
| `.bench/` | Baseline and comparison benchmarks |
