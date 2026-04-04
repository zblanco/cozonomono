---
name: cozonomono-docs
description: Use this skill when translating CozoDB concepts into verified Cozonomono examples or when answering questions about the library's public API and docs.
---

## Overview

Cozonomono is a thin Elixir wrapper around CozoDB. Most language features still
flow through CozoScript strings passed to `Cozonomono.query/3`.

When using this skill:

1. Start with `references/api-map.md` for the high-level surface.
2. Use `references/docs-map.md` to jump to the relevant guide.
3. Preserve upstream CozoScript structure when adapting examples.
4. Prefer verified examples and note when a feature is raw CozoScript rather
   than a dedicated wrapper API.

## What is wrapped

- instance lifecycle
- lazy result access
- host-managed transactions
- import/export and backup/restore
- callbacks
- custom fixed-rule bridges
- index creation helpers
- common system operations

## What usually stays as raw CozoScript

- joins, recursion, aggregations, and most query options
- mutation syntax like `:put`, `:update`, `:delete`, `:replace`
- proximity-search query expressions like `~table:index{...}`
- most built-in fixed rules and utilities
