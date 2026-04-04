# Lazy Rows and Types

Official docs:

- [Types](https://docs.cozodb.org/en/latest/types.html)
- [Functions and operators](https://docs.cozodb.org/en/latest/functions.html)

See also:

- [CozoScript Basics](cozoscript-basics.md)
- [Transactions and System Ops](transactions-and-system-ops.md)

## Eager results: `%Cozonomono.NamedRows{}`

`Cozonomono.query/3` returns an eager result:

```elixir
{:ok, rows} = Cozonomono.query(db, "?[] <- [['hello', 42, true]]")

rows.headers
rows.rows
rows.next
```

Use eager results when the full response is reasonably sized or you want to pass plain Elixir data around immediately.

## Lazy results: `%Cozonomono.LazyRows{}`

`Cozonomono.query_lazy/3` keeps the result on the Rust heap until you ask for slices or cells.

```elixir
{:ok, lazy} =
  Cozonomono.query_lazy(
    db,
    "?[id, name] := *users{id, name} :sort id"
  )

lazy.headers
lazy.row_count
lazy.column_count
```

Useful accessors:

```elixir
{:ok, row} = Cozonomono.LazyRows.row_at(lazy, 0)
{:ok, cell} = Cozonomono.LazyRows.cell_at(lazy, 0, 1)
{:ok, names} = Cozonomono.LazyRows.column(lazy, "name")
{:ok, batch} = Cozonomono.LazyRows.slice(lazy, 0, 50)
materialized = Cozonomono.LazyRows.to_named_rows(lazy)
```

## Enumerate without loading everything at once

```elixir
first_ten =
  lazy
  |> Cozonomono.LazyRows.to_enum()
  |> Enum.take(10)

streamed_names =
  lazy
  |> Cozonomono.LazyRows.to_stream(chunk_size: 500)
  |> Stream.map(fn [_id, name] -> name end)
  |> Enum.take(10)
```

## Elixir value mapping

Common Cozo values come back as ordinary Elixir terms:

- `null` -> `nil`
- `Bool` -> `true` / `false`
- numbers -> integers or floats
- strings -> binaries
- lists -> Elixir lists
- JSON values -> Elixir maps / lists
- vectors -> Elixir lists of numbers
- UUIDs -> strings

Representative example:

```elixir
{:ok, rows} =
  Cozonomono.query(
    db,
    "?[] <- [[$payload, $tags, $enabled]]",
    params: %{
      "payload" => %{"name" => "Alice", "roles" => ["admin"]},
      "tags" => ["a", "b", "c"],
      "enabled" => true
    }
  )
```

## Params must use string keys

```elixir
{:ok, rows} =
  Cozonomono.query(
    db,
    "?[] <- [[$name, $score]]",
    params: %{"name" => "Alice", "score" => 95.5}
  )
```

If you use atom keys, Cozo variables will not bind as expected.

## When to choose eager vs lazy

Choose eager results when:

- the result is small
- you want plain Elixir data immediately
- you will likely read every row anyway

Choose lazy results when:

- the result is large
- you only need a small subset of rows or columns
- you want stream-like processing with bounded memory
