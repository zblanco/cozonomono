# Cozonomono Usage Rules

Cozonomono is an Elixir wrapper around CozoDB's Rust interface. Most database behavior is expressed through raw CozoScript strings submitted via `Cozonomono.query/3` or `Cozonomono.tx_query/3`.

## Core rules

- Treat `Cozonomono.query/3` as the default entrypoint. Reach for specialized helpers only for lifecycle, transactions, lazy rows, import/export, backups, callbacks, fixed rules, and index creation.
- Pass query params as maps with string keys, for example `%{"id" => 1}`.
- Prefer named field bindings like `*users{id, name}` when querying stored relations. This is easier to read and less brittle than positional bindings.
- Use `Cozonomono.LazyRows` only when you want partial access to large result sets. If you need the whole result, use `query/3` or `LazyRows.to_named_rows/1`.
- Use `Cozonomono.explain/2` when changing query shape, indexes, or recursion.
- Keep examples faithful to the wrapper's actual API. If a Cozo feature is not wrapped directly, show it as raw CozoScript submitted through `query/3`.

## Docs layout

- Start with `CHEATSHEET.md` for the public API surface.
- Use the `guides/` directory for concept-level walkthroughs organized around Cozo topics.
- Prefer linking to the official Cozo manual for exhaustive operator, function, and algorithm reference instead of copying large reference tables into local docs.

## Verifying examples

- Verify examples in the project with Tidewave or project eval before treating them as correct.
- Prefer examples that already match tested library behavior when possible.
- If a feature is awkward to verify locally, state that the example is raw CozoScript and link to the relevant official Cozo page.

## Sub-rules

- `cozonomono:docs` for writing or reorganizing user-facing documentation
- `cozonomono:querying` for query patterns, params, and result handling
