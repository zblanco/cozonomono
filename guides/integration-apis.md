# Integration APIs

Official docs: [Beyond CozoScript](https://docs.cozodb.org/en/latest/nonscript.html)

See also:

- [Getting Started](getting-started.md)
- [Transactions and System Ops](transactions-and-system-ops.md)
- [Graph Algorithms and Fixed Rules](graph-algorithms-and-fixed-rules.md)

## Export and import relations

```elixir
{:ok, exported} = Cozonomono.export_relations(db, ["users", "articles"])

:ok =
  Cozonomono.import_relations(
    other_db,
    exported
  )
```

This is the fastest way to move relation data between Cozonomono instances when the target schema already exists.

## Backup and restore

```elixir
:ok = Cozonomono.backup(db, "/tmp/cozo-backup.db")

{:ok, restored_db} = Cozonomono.new()
:ok = Cozonomono.restore(restored_db, "/tmp/cozo-backup.db")
```

Selective restore is available through `import_from_backup/3`:

```elixir
:ok = Cozonomono.import_from_backup(restored_db, "/tmp/cozo-backup.db", ["users"])
```

## Change callbacks

Register a listener against a stored relation:

```elixir
{:ok, callback_id} = Cozonomono.register_callback(db, "users")

{:ok, _} =
  Cozonomono.query(
    db,
    "?[id, name] <- [[1, 'Alice']] :put users {id => name}"
  )

receive do
  {:cozo_callback, :put, new_rows, old_rows} ->
    {new_rows.rows, old_rows.rows}
end
```

Unregister when finished:

```elixir
true = Cozonomono.unregister_callback(db, callback_id)
```

## Custom fixed rules

For custom computation during query execution, use:

- `register_fixed_rule/4`
- `respond_fixed_rule/3`
- `unregister_fixed_rule/2`

See [Graph Algorithms and Fixed Rules](graph-algorithms-and-fixed-rules.md) for the full flow.

## Instance lifecycle

```elixir
:ok = Cozonomono.close(db)
```

Closing is especially helpful for `:sqlite` and `:rocksdb` instances when your process needs deterministic release of files and locks.
