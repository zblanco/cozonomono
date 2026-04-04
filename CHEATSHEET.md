# Cozonomono Cheatsheet

High-level reference for the primary Cozonomono API surface. For runnable walkthroughs, start with [guides/getting-started.md](guides/getting-started.md).

## Create and close instances

```elixir
{:ok, db} = Cozonomono.new()
{:ok, sqlite_db} = Cozonomono.new(:sqlite, "/tmp/app.db")
{:ok, rocks_db} = Cozonomono.new(:rocksdb, "/tmp/app.rocks")

:ok = Cozonomono.close(db)
```

## Run CozoScript

```elixir
{:ok, rows} =
  Cozonomono.query(db, "?[name] <- [['alice'], ['bob']]")

{:ok, rows} =
  Cozonomono.query(
    db,
    "?[id, name] <- [[$id, $name]]",
    params: %{"id" => 1, "name" => "Alice"}
  )
```

- `query/3` returns `%Cozonomono.NamedRows{}`
- Params must use string keys
- Most Cozo features are expressed directly in raw CozoScript

## Work with stored relations

```elixir
{:ok, _} =
  Cozonomono.query(db, ":create users {id: Int => name: String, email: String?}")

{:ok, _} =
  Cozonomono.query(
    db,
    "?[id, name, email] <- [[1, 'Alice', 'alice@example.com']] :put users {id => name, email}"
  )

{:ok, users} =
  Cozonomono.query(db, "?[id, name, email] := *users{id, name, email}")
```

## Transactions

```elixir
{:ok, tx} = Cozonomono.multi_transaction(db)

{:ok, _} =
  Cozonomono.tx_query(
    tx,
    "?[id, name] <- [[2, 'Bob']] :put users {id => name}"
  )

:ok = Cozonomono.tx_commit(tx)
```

- `multi_transaction/2` creates write or read-only transactions
- `tx_query/3` and `tx_query_lazy/3` run inside the transaction
- `tx_abort/1` discards changes

## Lazy reads

```elixir
{:ok, lazy} = Cozonomono.query_lazy(db, "?[id, name] := *users{id, name} :sort id")

lazy.headers
lazy.row_count

{:ok, first_row} = Cozonomono.LazyRows.row_at(lazy, 0)
{:ok, names} = Cozonomono.LazyRows.column(lazy, "name")
{:ok, top_ten} = Cozonomono.LazyRows.slice(lazy, 0, 10)

stream = Cozonomono.LazyRows.to_stream(lazy, chunk_size: 500)
materialized = Cozonomono.LazyRows.to_named_rows(lazy)
```

Use lazy rows when result sets are large and you do not want to eagerly copy everything into the BEAM.

## System ops

```elixir
{:ok, rels} = Cozonomono.list_relations(db)
{:ok, cols} = Cozonomono.list_columns(db, "users")
{:ok, idxs} = Cozonomono.list_indices(db, "users")
{:ok, plan} = Cozonomono.explain(db, "?[id] := *users{id}")
{:ok, _} = Cozonomono.rename_relation(db, "users", "accounts")
{:ok, _} = Cozonomono.set_access_level(db, "accounts", :read_only)
```

Also available:

- `remove_relation/2`
- `list_running/1`
- `kill_running/2`
- `compact/1`

## Index helpers

```elixir
{:ok, _} = Cozonomono.create_index(db, "users", "users_by_name", ["name"])

{:ok, _} =
  Cozonomono.create_hnsw_index(
    db,
    "docs",
    "docs_hnsw",
    "dim: 3, dtype: F32, fields: [embedding], distance: Cosine, ef_construction: 50, m: 16"
  )

{:ok, _} =
  Cozonomono.create_fts_index(
    db,
    "docs",
    "docs_fts",
    "extractor: content, tokenizer: Simple, filters: []"
  )

{:ok, _} =
  Cozonomono.create_lsh_index(
    db,
    "docs",
    "docs_lsh",
    "extractor: content, tokenizer: Simple, filters: [], n_gram: 3, n_perm: 200"
  )
```

Searching those indexes still happens with raw CozoScript query syntax.

## Import, export, backup

```elixir
{:ok, export} = Cozonomono.export_relations(db, ["users"])
:ok = Cozonomono.import_relations(db, export)

:ok = Cozonomono.backup(db, "/tmp/cozo-backup.db")
:ok = Cozonomono.restore(db, "/tmp/cozo-backup.db")
:ok = Cozonomono.import_from_backup(db, "/tmp/cozo-backup.db", ["users"])
```

## Callbacks

```elixir
{:ok, callback_id} = Cozonomono.register_callback(db, "users")

receive do
  {:cozo_callback, op, new_rows, old_rows} ->
    {op, new_rows, old_rows}
end

true = Cozonomono.unregister_callback(db, callback_id)
```

## Custom fixed rules

```elixir
{:ok, bridge} = Cozonomono.register_fixed_rule(db, "MyRule", 1)

receive do
  {:cozo_fixed_rule, request_id, _inputs, _options} ->
    result = %Cozonomono.NamedRows{headers: ["value"], rows: [[42]]}
    :ok = Cozonomono.respond_fixed_rule(bridge, request_id, result)
end
```

## Result structs

`%Cozonomono.NamedRows{}`:

- `headers` is a list of column names
- `rows` is a list of row lists
- `next` is the next statement result for multi-statement chains, or `nil`

`%Cozonomono.LazyRows{}`:

- `headers`
- `row_count`
- `column_count`
- `has_next`

## Good defaults

- Use `query/3` first, and drop to helper APIs only when they add value
- Use string keys for params: `%{"id" => 1}`
- Prefer named bindings for stored relations: `*users{id, name}`
- Use `explain/2` when tuning query shape
- Use `query_lazy/3` when result size is large or only part of the result is needed
- Keep the official Cozo manual open for full CozoScript syntax: https://docs.cozodb.org/en/latest/
