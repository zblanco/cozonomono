# Getting Started

Official docs: [Tutorial](https://docs.cozodb.org/en/latest/tutorial.html), [Queries](https://docs.cozodb.org/en/latest/queries.html)

See also:

- [CozoScript Basics](cozoscript-basics.md)
- [Stored Relations and Mutations](stored-relations-and-mutations.md)
- [Integration APIs](integration-apis.md)

## Create a database instance

```elixir
{:ok, db} = Cozonomono.new()
{:ok, sqlite_db} = Cozonomono.new(:sqlite, "/tmp/cozonomono-demo.db")
```

Use `:mem` for ephemeral development and tests. Use `:sqlite` or `:rocksdb` when you want on-disk storage.

## Run your first query

```elixir
{:ok, result} =
  Cozonomono.query(db, "?[greeting, target] <- [['hello', 'world']]")

result.headers
#=> ["greeting", "target"]

result.rows
#=> [["hello", "world"]]
```

`Cozonomono.query/3` returns `%Cozonomono.NamedRows{}` with `headers`, `rows`, and `next`.

## Create a stored relation

```elixir
{:ok, _} =
  Cozonomono.query(
    db,
    ":create users {id: Int => name: String, email: String?}"
  )
```

The last key columns go before `=>`. Value columns go after it.

## Insert data

```elixir
{:ok, _} =
  Cozonomono.query(
    db,
    """
    ?[id, name, email] <- [
      [1, 'Alice', 'alice@example.com'],
      [2, 'Bob', null]
    ]
    :put users {id => name, email}
    """
  )
```

## Read data back

```elixir
{:ok, users} =
  Cozonomono.query(
    db,
    "?[id, name, email] := *users{id, name, email} :sort id"
  )
```

Named bindings like `*users{id, name, email}` are usually easier to maintain than positional bindings.

## Use params

```elixir
{:ok, one_user} =
  Cozonomono.query(
    db,
    "?[id, name] := *users{id, name}, id == $id",
    params: %{"id" => 1}
  )
```

Params must use string keys because Cozo variables are bound by name.

## Close explicitly when you need deterministic cleanup

```elixir
:ok = Cozonomono.close(sqlite_db)
```

Closing is optional for in-memory databases, but useful for file-backed engines where you want to release file handles and locks immediately.
