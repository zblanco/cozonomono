# Time Travel

Official docs: [Time travel](https://docs.cozodb.org/en/latest/timetravel.html)

See also:

- [Stored Relations and Mutations](stored-relations-and-mutations.md)
- [Transactions and System Ops](transactions-and-system-ops.md)

## Use `Validity` in the last key position

A stored relation becomes eligible for time-travel queries when the last part of its key has type `Validity`.

```elixir
{:ok, _} =
  Cozonomono.query(
    db,
    ":create account_status {account_id: Int, version: Validity => status: String}"
  )
```

## Insert assertions and retractions

The Cozo manual supports `ASSERT` and `RETRACT` shortcuts for current timestamps.

```elixir
{:ok, _} =
  Cozonomono.query(
    db,
    """
    ?[account_id, version, status] <- [
      [1, validity(1_000_000, true), 'trial'],
      [1, validity(2_000_000, true), 'active'],
      [1, validity(3_000_000, false), null]
    ]
    :put account_status {account_id, version => status}
    """
  )
```

## Query a historical snapshot

Attach `@` to the stored relation access:

```elixir
{:ok, at_first_snapshot} =
  Cozonomono.query(
    db,
    "?[status] := *account_status{account_id: 1, status, @ 1_500_000}"
  )

{:ok, after_retraction} =
  Cozonomono.query(
    db,
    "?[status] := *account_status{account_id: 1, status, @ 3_500_000}"
  )
```

## RFC3339 timestamps also work in Cozo

The official manual allows RFC3339 strings in validity literals and time-travel lookups. When you want calendar-oriented examples, keep the syntax in raw CozoScript and link back to the manual for the exact rules:

- `ASSERT`
- `RETRACT`
- `NOW`
- `END`
- RFC3339 strings like `'2024-01-01T00:00:00Z'`

## What to cover locally

Local Cozonomono docs should explain:

- that time travel is ordinary CozoScript submitted through `query/3`
- that the relation schema must use `Validity` in the final key position
- how to issue `@` snapshot queries from Elixir

The deeper history semantics belong in the official time-travel chapter.
