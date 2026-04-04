# Stored Relations and Mutations

Official docs: [Stored relations and transactions](https://docs.cozodb.org/en/latest/stored.html)

See also:

- [Getting Started](getting-started.md)
- [Transactions and System Ops](transactions-and-system-ops.md)
- [Indexes and Search](indexes-and-search.md)

## Create relations with explicit schema

```elixir
{:ok, _} =
  Cozonomono.query(
    db,
    ":create users {id: Int => name: String, email: String?, active: Bool}"
  )
```

## Insert and replace rows

```elixir
{:ok, _} =
  Cozonomono.query(
    db,
    """
    ?[id, name, email, active] <- [
      [1, 'Alice', 'alice@example.com', true],
      [2, 'Bob', null, false]
    ]
    :put users {id => name, email, active}
    """
  )
```

`:put` upserts rows into the relation according to the relation key.

## Remove rows

```elixir
{:ok, _} =
  Cozonomono.query(
    db,
    """
    ?[id, name] <- [[2, 'Bob']]
    :rm users {id => name}
    """
  )
```

## Query relations by field name

```elixir
{:ok, active_users} =
  Cozonomono.query(
    db,
    """
    ?[id, name] := *users{id, name, active}, active == true
    :sort id
    """
  )
```

## Manage relations through wrapper helpers

```elixir
{:ok, _} = Cozonomono.rename_relation(db, "users", "accounts")
{:ok, _} = Cozonomono.set_access_level(db, "accounts", :read_only)
{:ok, _} = Cozonomono.remove_relation(db, "accounts")
```

Access levels available through `set_access_level/3`:

- `:normal`
- `:protected`
- `:read_only`
- `:hidden`

## Standard indexes

```elixir
{:ok, _} = Cozonomono.create_index(db, "users", "users_by_email", ["email"])

{:ok, found} =
  Cozonomono.query(
    db,
    "?[id, name] := *users{id, name, email: $email}",
    params: %{"email" => "alice@example.com"}
  )
```

The helper creates the index. Querying still uses normal CozoScript, and the planner may choose the index automatically when it helps. If you want to inspect what Cozo created, use `Cozonomono.list_indices/2` or `Cozonomono.list_columns/2` on the index relation.

## Triggers are still raw CozoScript

Cozonomono does not wrap trigger creation in a dedicated helper. When you need triggers, submit the corresponding `::set_triggers` system op with `Cozonomono.query/3` and lean on the official trigger docs for the full syntax:

- https://docs.cozodb.org/en/latest/stored.html#triggers
