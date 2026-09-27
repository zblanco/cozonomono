# Transactions and System Ops

Official docs:

- [Stored relations and transactions](https://docs.cozodb.org/en/latest/stored.html)
- [System ops](https://docs.cozodb.org/en/latest/sysops.html)
- [Query execution](https://docs.cozodb.org/en/latest/execution.html)

See also:

- [Stored Relations and Mutations](stored-relations-and-mutations.md)
- [Integration APIs](integration-apis.md)

## Multi-statement transactions

```elixir
{:ok, tx} = Cozonomono.multi_transaction(db)

{:ok, _} =
  Cozonomono.tx_query(
    tx,
    "?[id, name] <- [[1, 'Alice']] :put users {id => name}"
  )

{:ok, _} =
  Cozonomono.tx_query(
    tx,
    "?[id, name] := *users{id, name}"
  )

:ok = Cozonomono.tx_commit(tx)
```

Abort instead of committing when you want to discard all changes:

```elixir
:ok = Cozonomono.tx_abort(tx)
```

## Read-only transactions

```elixir
{:ok, tx} = Cozonomono.multi_transaction(db, false)
{:ok, rows} = Cozonomono.tx_query(tx, "?[id, name] := *users{id, name}")
:ok = Cozonomono.tx_commit(tx)
```

## Lazy results inside transactions

```elixir
{:ok, tx} = Cozonomono.multi_transaction(db)

{:ok, lazy} =
  Cozonomono.tx_query_lazy(
    tx,
    "?[id, name] := *users{id, name} :sort id"
  )

{:ok, first_row} = Cozonomono.LazyRows.row_at(lazy, 0)
:ok = Cozonomono.tx_abort(tx)
```

## Schema and relation inspection

```elixir
{:ok, rels} = Cozonomono.list_relations(db)
{:ok, cols} = Cozonomono.list_columns(db, "users")
{:ok, idxs} = Cozonomono.list_indices(db, "users")
```

## Operational helpers

```elixir
{:ok, plan} = Cozonomono.explain(db, "?[id] := *users{id}")
{:ok, running} = Cozonomono.list_running(db)
{:ok, _} = Cozonomono.kill_running(db, 999)
{:ok, _} = Cozonomono.compact(db)
```

## Use `explain/2` when tuning query shape

The [Query execution](https://docs.cozodb.org/en/latest/execution.html) chapter covers magic sets, stratification, and atom reordering. In day-to-day Cozonomono usage, the practical loop is:

1. write the query in ordinary CozoScript
2. run `Cozonomono.explain/2`
3. check for full scans, sort-heavy plans, or poor key usage
4. adjust relation keys, index selection, or rule ordering

Keep the local guide short and task-oriented. Link out to the full execution chapter for the compiler internals.
