# Phase 2.4: System Operations (Schema Introspection) — Implementation Notes

## What was added

10 convenience functions that wrap CozoScript system ops (`::` commands). These are **pure Elixir** — no Rust/NIF changes were needed. Each function builds a CozoScript string and calls `query/3`:

| Function | CozoScript | Description |
|----------|-----------|-------------|
| `list_relations/1` | `::relations` | Lists all stored relations with metadata |
| `list_columns/2` | `::columns <rel>` | Lists columns, types, and key info |
| `list_indices/2` | `::indices <rel>` | Lists indices on a relation |
| `remove_relation/2` | `::remove <rel>, ...` | Removes one or more relations |
| `rename_relation/3` | `::rename <old> -> <new>` | Renames a relation |
| `explain/2` | `::explain { <query> }` | Returns query plan without executing |
| `list_running/1` | `::running` | Lists running queries with IDs |
| `kill_running/2` | `::kill <id>` | Kills a running query |
| `compact/1` | `::compact` | Triggers storage compaction |

## Why no Rust changes?

CozoDB system ops are just CozoScript strings that go through the same `run_script` / `run_default` path as any other query. The existing `query/3` NIF handles them perfectly. These Elixir functions are thin wrappers that save you from remembering the `::` syntax.

## The `remove_relation/2` overload

This function accepts either a single string or a list of strings:

```elixir
Cozonomono.remove_relation(instance, "users")
Cozonomono.remove_relation(instance, ["users", "posts", "comments"])
```

CozoDB's `::remove` accepts comma-separated names, so the list variant joins them with `", "`.

## Why `describe_relation` was skipped

While investigating the CozoDB 0.7.6 source, I discovered a **grammar bug**: the `describe_relation_op` rule is defined in `cozoscript.pest`:

```pest
describe_relation_op = {"describe" ~ compound_or_index_ident ~ string?}
```

But it's **never included** in the `sys_script` alternation that defines what `::` commands are valid:

```pest
sys_script = {SOI ~ "::" ~ (list_relations_op | list_columns_op | list_indices_op |
              remove_relations_op | ... | compact_op | list_fixed_rules) ~ EOI}
```

Notice `describe_relation_op` is absent from this list. So `::describe <rel> '<desc>'` always fails with a parser error in 0.7.6. This is documented in the roadmap — it can be added when a newer cozo version fixes the grammar.

## Files changed

| File | Change |
|------|--------|
| `lib/cozonomono.ex` | Added 10 system operation functions |
| `test/system_ops_test.exs` | 14 tests covering all operations |
