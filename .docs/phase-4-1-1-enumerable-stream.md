# Phase 4.1.1: Enumerable & Stream Support for LazyRows

## The Design Question

With `%LazyRows{}` holding query results on the Rust heap, the natural question is: can we pipe it into `Enum.map`, `Stream.filter`, etc.?

The answer is yes — but *how* matters enormously. This doc explains why we chose the approach we did, what Explorer/Polars taught us, and what the tradeoffs are.

## Why Not Implement Enumerable Directly on LazyRows

Explorer deliberately does **not** implement `Enumerable` on `Explorer.Series` or `Explorer.DataFrame`. Neither do we on `%LazyRows{}`. The reasons:

### 1. NIF Boundary Cost Is Not Free

Each NIF call has ~2-3μs of overhead for the BEAM-to-Rust context switch. If `Enumerable.reduce/3` called `cell_at` or `row_at` for every single row:

| Rows | Per-row NIF calls | NIF overhead alone |
|------|-------------------|--------------------|
| 100 | 100 | ~0.25ms |
| 10,000 | 10,000 | ~25ms |
| 100,000 | 100,000 | ~250ms |

That 250ms is *just crossing overhead* — no actual data encoding. The data is right there on the Rust heap, but you're paying a toll for each row.

### 2. Implicit Enumerable Sends the Wrong Signal

If `%LazyRows{}` implemented `Enumerable` directly, users would naturally write:

```elixir
lazy |> Enum.map(fn row -> ... end)
```

This looks cheap but is deceptively expensive for large result sets. By requiring an explicit `to_enum/1` call, users acknowledge "I'm about to iterate row-by-row, and I understand the cost."

### 3. Explorer's Lesson

Explorer's `Series` has a `to_enum/1` that returns a private `Explorer.Series.Iterator` struct. That struct implements `Enumerable`. The key insight: **the iterator is a separate type** with different performance characteristics than the parent.

Explorer's iterator has:
- `count/1` → O(1) from metadata
- `slice/1` → bulk NIF call (`s_slice` + `s_to_list`, 2 NIF crossings)
- `reduce/3` → per-element `s_at` NIF calls (N crossings — the slow path)
- `member?/2` → returns `{:error, module}` to make cost visible

We improved on Explorer's `reduce` path by using **chunked fetching**.

## What We Implemented

### 1. `LazyRows.to_enum/1` → Iterator with Chunked Reduce

```elixir
{:ok, lazy} = Cozonomono.query_lazy(instance, "?[id, name] := *users{id, name}")
ids = lazy |> LazyRows.to_enum() |> Enum.map(&hd/1)
```

The returned `LazyRows.Iterator` struct implements `Enumerable` with three callbacks:

#### `count/1` — O(1), No NIF Call
Returns `row_count` from the struct metadata. `Enum.count(to_enum(lazy))` is instant.

#### `slice/1` — Bulk NIF Fetch
When `Enum` functions can use slice-based access (e.g., `Enum.take/2`, `Enum.at/2`, `Enum.slice/2`), they call the `slice` callback which does a single `lazy_rows_slice` NIF call. This means:

```elixir
# ONE NIF call, regardless of how many rows taken
lazy |> to_enum() |> Enum.take(5)

# ONE NIF call for random access
lazy |> to_enum() |> Enum.at(5000)
```

#### `reduce/3` — Chunked, Not Per-Element
Explorer's iterator does one NIF call per element in `reduce`. We batch:

```
Explorer:  [NIF] [NIF] [NIF] [NIF] [NIF] ...  (N calls for N rows)
Ours:      [NIF────────────────] [NIF─────...  (N/1000 calls for N rows)
```

Our `reduce` fetches 1000 rows per NIF call via `slice`, then iterates the in-memory chunk. For 100k rows, that's ~100 NIF crossings instead of 100k.

The implementation handles all three `Enumerable` control signals properly:
- `{:cont, acc}` — continue processing the current chunk
- `{:halt, acc}` — stop immediately (e.g., `Enum.reduce_while`, `Enum.take`)
- `{:suspend, acc}` — pause and resume (e.g., `Enum.zip`, which interleaves two enumerables)

### 2. `LazyRows.to_stream/2` — Bounded-Memory Streaming

```elixir
lazy
|> LazyRows.to_stream(chunk_size: 500)
|> Stream.filter(fn [_id, name] -> String.starts_with?(name, "A") end)
|> Enum.to_list()
```

Uses `Stream.resource/3` to pull rows in configurable chunks. At any point, only `chunk_size` rows are materialized on the BEAM heap. This is the right tool for very large result sets where you want to process data without loading it all into memory.

**How it works:**

```elixir
Stream.resource(
  fn -> 0 end,                              # initial offset
  fn offset ->
    {:ok, rows} = slice(lazy, offset, chunk_size)  # one NIF call
    {rows, offset + chunk_size}                     # yield rows, advance
  end,
  fn _offset -> :ok end                     # cleanup (nothing needed)
)
```

Each `Stream` pull fetches one chunk. `Stream.take(3)` may fetch one chunk of 1000 rows but only yields 3 — the rest are discarded. If that matters, use a smaller `chunk_size`.

## Decision Matrix: When to Use What

| Need | Use | NIF Calls | Memory |
|------|-----|-----------|--------|
| One row/cell | `row_at/2`, `cell_at/3` | 1 | Minimal |
| One column | `column_at/2` | 1 | O(rows) |
| A known slice | `slice/3` | 1 | O(slice) |
| Full materialization | `to_named_rows/1` | 1 | O(all) |
| Arbitrary `Enum` pipeline | `to_enum/1` | O(rows/1000) | O(all) |
| Memory-bounded processing | `to_stream/2` | O(rows/chunk) | O(chunk) |
| Row count | `lazy.row_count` | 0 | 0 |

## Files Changed

| File | Changes |
|------|---------|
| `lib/cozonomono/lazy_rows/iterator.ex` | New module: `Enumerable` protocol impl with chunked reduce |
| `lib/cozonomono/lazy_rows.ex` | Added `to_enum/1`, `to_stream/2`, updated moduledoc |
| `test/lazy_rows_test.exs` | 14 new tests for `to_enum` and `to_stream` |
| `.docs/ROADMAP.md` | Added 4.1.1 subsection |
