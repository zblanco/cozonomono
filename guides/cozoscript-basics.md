# CozoScript Basics

Official docs:

- [Queries](https://docs.cozodb.org/en/latest/queries.html)
- [Tips for writing queries](https://docs.cozodb.org/en/latest/tips.html)
- [Functions and operators](https://docs.cozodb.org/en/latest/functions.html)
- [Aggregations](https://docs.cozodb.org/en/latest/aggregations.html)

See also:

- [Getting Started](getting-started.md)
- [Lazy Rows and Types](lazy-rows-and-types.md)
- [Transactions and System Ops](transactions-and-system-ops.md)

## The entry rule is `?`

The result of a CozoScript query is always the relation produced by the rule named `?`.

```elixir
{:ok, result} =
  Cozonomono.query(
    db,
    """
    ids[id] <- [[1], [2]]
    ?[id] := ids[id]
    """
  )
```

## Inline rules, constant rules, and fixed rules

```elixir
{:ok, result} =
  Cozonomono.query(
    db,
    """
    users[id, name] <- [[1, 'Alice'], [2, 'Bob']]
    starts_with_a[id, name] := users[id, name], starts_with(name, 'A')
    ?[name] := starts_with_a[id, name]
    """
  )
```

- `<-` is constant data
- `:=` is an inline rule
- `<~` calls a fixed rule or algorithm

## Joins use repeated variables

```elixir
{:ok, result} =
  Cozonomono.query(
    db,
    """
    authors[id, name] <- [[1, 'Alice'], [2, 'Bob']]
    posts[id, author_id, title] <- [[10, 1, 'Intro'], [11, 1, 'Tips'], [12, 2, 'News']]
    ?[author, title] := authors[author_id, author], posts[_post_id, author_id, title]
    :sort author, title
    """
  )
```

## Use query options directly in CozoScript

```elixir
{:ok, result} =
  Cozonomono.query(
    db,
    """
    items[n] <- [[1], [2], [3], [4], [5]]
    ?[n] := items[n]
    :sort -n
    :limit 2
    :offset 1
    """
  )
```

Common options to remember:

- `:sort` or `:order`
- `:limit`
- `:offset`
- `:timeout`
- `:assert some`
- `:assert none`

## Params fit naturally into `query/3`

```elixir
{:ok, result} =
  Cozonomono.query(
    db,
    """
    ?[name] := *users{id, name}, id == $id
    """,
    params: %{"id" => 1}
  )
```

## Aggregations stay in the rule head

```elixir
{:ok, result} =
  Cozonomono.query(
    db,
    """
    ?[department, count(employee)] := *employees{department, employee}
    :sort department
    """
  )
```

For deeper aggregation semantics, especially recursive semi-lattice cases, link out to the official [Aggregations](https://docs.cozodb.org/en/latest/aggregations.html) chapter instead of duplicating it all here.

## Functions and null handling

```elixir
{:ok, result} =
  Cozonomono.query(
    db,
    """
    row[id, score] <- [[1, 10], [2, null], [3, 20]]
    ?[id, normalized] := row[id, score], normalized = (score ~ 0) / 10
    :sort id
    """
  )
```

Representative functions that map well into everyday Cozonomono examples:

- `starts_with/2`
- `lowercase/1`
- `length/1`
- `coalesce/2` via the `~` operator
- `vec/1` for vector values
- `parse_json/1`, `get/2`, and `maybe_get/2` for JSON-heavy workflows

## Practical query-writing advice

The official [Query execution](https://docs.cozodb.org/en/latest/execution.html) chapter explains the engine internals. In local docs, keep the advice practical:

- Put the most selective atoms that introduce bindings early
- Prefer key-prefix access patterns on stored relations
- Use `Cozonomono.explain/2` when you are unsure how a query will execute
- Keep local docs example-driven and link out for the lower-level compiler discussion
