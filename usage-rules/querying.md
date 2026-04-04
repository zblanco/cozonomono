# Querying Rules

- Params passed into CozoScript must use string keys.
- Favor named field bindings for stored relations, for example `*users{id, name}`.
- Use `query/3` for eager results and `query_lazy/3` for large or partial reads.
- Explain queries with `Cozonomono.explain/2` when changing recursion, joins, or index usage.
- Remember that most advanced Cozo features still use raw CozoScript syntax even when Cozonomono provides setup helpers:
  - HNSW / FTS / LSH search queries
  - triggers
  - time-travel queries
  - built-in fixed-rule algorithms
- Prefer examples that show both the schema setup and the query that reads it back.
- Keep the official Cozo manual nearby for language details:
  - Queries: https://docs.cozodb.org/en/latest/queries.html
  - Stored relations: https://docs.cozodb.org/en/latest/stored.html
  - Types: https://docs.cozodb.org/en/latest/types.html
  - Functions/operators: https://docs.cozodb.org/en/latest/functions.html
