# Documentation Rules

- Organize docs around user tasks and Cozo concepts, not around NIF internals.
- Keep the distinction clear between wrapper helpers and raw CozoScript.
- Cross-link local guides when a concept builds on another guide.
- Link back to the official Cozo documentation for exhaustive language reference:
  - https://docs.cozodb.org/en/latest/
- Prefer examples that fit one of these entrypoints:
  - `Cozonomono.query/3`
  - `Cozonomono.query_lazy/3`
  - `Cozonomono.tx_query/3`
  - `Cozonomono.tx_query_lazy/3`
- Document the Elixir-facing result type in examples:
  - `%Cozonomono.NamedRows{}`
  - `%Cozonomono.LazyRows{}`
- When documenting agent workflows, point agents at `CHEATSHEET.md` first and then to the relevant guide under `guides/`.
