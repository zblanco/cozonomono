# Cozonomono

Cozonomono is an Elixir wrapper around the Rust [CozoDB](https://github.com/cozodb/cozo) interface. It exposes CozoScript queries, stored relations, transactions, lazy result access, search indexes, backup/import APIs, callbacks, and custom fixed rules through a small Elixir-first surface.

## Install

```elixir
def deps do
  [
    {:cozonomono, git: "https://github.com/zblanco/cozonomono.git", branch: "main"}
  ]
end
```

If you want to force a local Rust build instead of using precompiled NIFs:

```bash
COZONOMONO_BUILD=true mix deps.get
```

## Docs

The ExDoc set is organized for both quick lookup and deeper walkthroughs:

- [CHEATSHEET.md](CHEATSHEET.md) for the primary API surface
- [Getting Started](guides/getting-started.md) for the shortest path from `Cozonomono.new/2` to useful queries
- [CozoScript Basics](guides/cozoscript-basics.md) for queries, params, aggregations, and query options
- [Stored Relations and Mutations](guides/stored-relations-and-mutations.md) for schema changes and writes
- [Lazy Rows and Types](guides/lazy-rows-and-types.md) for large reads and value mapping
- [Transactions and System Ops](guides/transactions-and-system-ops.md) for transactional work and schema inspection
- [Indexes and Search](guides/indexes-and-search.md) for standard, HNSW, FTS, and LSH indexes
- [Time Travel](guides/time-travel.md) for `Validity`-based historical queries
- [Graph Algorithms and Fixed Rules](guides/graph-algorithms-and-fixed-rules.md) for built-in algorithms and custom fixed rules
- [Integration APIs](guides/integration-apis.md) for import/export, backups, callbacks, and lifecycle helpers

To build the docs locally:

```bash
mix deps.get
mix docs
```

## Agent Support

This package ships `usage-rules.md` and sub-rules so downstream coding agents can pull in Cozonomono-specific guidance through [`usage_rules`](https://github.com/ash-project/usage_rules).

Typical downstream setup:

```elixir
def deps do
  [
    {:usage_rules, "~> 1.2", only: :dev, runtime: false},
    {:cozonomono, "~> 0.1.0"}
  ]
end
```

Then sync the rules in the consuming project:

```bash
mix usage_rules.sync
```

## Official CozoDB Manual

These guides intentionally stay focused on using Cozo through this Elixir wrapper. For the full Cozo language and engine reference, use the official manual:

- https://docs.cozodb.org/en/latest/
