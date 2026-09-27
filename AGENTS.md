# Cozonomono Agent Guide

Cozonomono is an Elixir client library for [CozoDB](https://github.com/cozodb/cozo), an embedded transactional relational database with a Datalog query engine, graph algorithms, vector search, and full-text search. The library wraps CozoDB's Rust library via [Rustler](https://github.com/rustler-erlang/rustler) NIFs, following patterns established by [Explorer](https://github.com/elixir-explorer/explorer) for efficient NIF interop.

## Build/Test Commands
- `mix test` - Run all tests
- `mix test test/specific_test.exs` - Run specific test file
- `mix test test/specific_test.exs:123` - Run specific test line
- `mix compile` - Compile the project (triggers Rust NIF compilation)
- `mix format` - Format Elixir code according to .formatter.exs
- `mix rust.fmt` - Format Rust code via cargo fmt
- `mix rust.lint` - Run clippy on the Rust NIF crate
- `mix ci` - Run format, rust.fmt, rust.lint, and test
- `mix deps.get` - Get dependencies
- Set `COZONOMONO_BUILD=true` to force local Rust compilation instead of using precompiled binaries

## Architecture

### Layers

1. **Public API** (`Cozonomono`) — High-level Elixir functions users call directly
2. **NIF Stubs** (`Cozonomono.Native`) — Elixir function stubs replaced at load time by Rustler NIF entry points; all stubs return `:erlang.nif_error(:nif_not_loaded)`
3. **Rust NIFs** (`native/cozonomono_cozo/src/`) — Rust functions annotated with `#[rustler::nif]` that call the `cozo` crate
4. **CozoDB** (`cozo` crate) — The upstream embedded database engine

### NIF Interop Pattern (Explorer-style)

The project uses the **two-type resource pattern** from Explorer:

- **`ExDbInstanceRef`** — Owns the `cozo::DbInstance` on the Rust heap, registered as a BEAM resource type via `rustler::resource!`
- **`ExDbInstance`** — A `#[derive(NifStruct)]` with `#[module = "Cozonomono.Instance"]` containing a `ResourceArc<ExDbInstanceRef>` plus metadata fields. This maps to `%Cozonomono.Instance{}` on the Elixir side
- **`Deref` impl** — `ExDbInstance` derefs to `DbInstance`, allowing direct method calls on the inner CozoDB instance without unwrapping

The Elixir struct (`%Cozonomono.Instance{resource: ref, engine: engine, path: path}`) holds only an opaque reference to the Rust-heap-allocated database. No database data is copied into the BEAM.

### Key Files
- `lib/cozonomono.ex` — Public API module
- `lib/cozonomono/native.ex` — NIF stub declarations (uses `RustlerPrecompiled`)
- `lib/cozonomono/instance.ex` — Elixir struct matching the Rust `ExDbInstance` NifStruct
- `lib/cozonomono/named_rows.ex` — Elixir struct for query results (built manually by Rust encoder via `__struct__` key)
- `native/cozonomono_cozo/src/lib.rs` — NIF function implementations and `rustler::init!`
- `native/cozonomono_cozo/src/datatypes.rs` — Resource types, `ExDbInstance`, `ExNamedRows`, `ExDataValue` encoding/decoding
- `native/cozonomono_cozo/src/error.rs` — Error type with `thiserror` and `rustler::Encoder`

### Rust NIF Conventions
- All NIF functions use `Result<T, ExError>` return types — Rustler maps `Ok(v)` to `{:ok, v}` and `Err(e)` to `{:error, message}`
- Use `#[rustler::nif(schedule = "DirtyCpu")]` for any CozoDB operation that may block (queries, instance creation, import/export)
- Use bare `#[rustler::nif]` only for fast metadata reads
- New NIF functions must be added to both `rustler::init!` in `lib.rs` AND as stubs in `Cozonomono.Native`
- Custom encoding via `Encoder`/`Decoder` impls for CozoDB types that don't map to Rustler derives (e.g., `ExDataValue`, `ExNamedRows`)

### CozoDB Concepts
- **Stored relations** — Persistent tables with key columns and value columns, created via CozoScript (`:create`, `:replace`)
- **CozoScript** — Datalog-based query language with extensions for DDL, system ops, and imperative control flow
- **Storage engines** — `mem` (in-memory), `sqlite` (persistent, also used for backup format), `rocksdb` (best throughput)
- **`DbInstance`** — The non-generic Rust entry point that dispatches to the correct storage backend; this is what we wrap
- **`NamedRows`** — Query result type mapped to `%Cozonomono.NamedRows{headers, rows, next}` where `next` chains multi-statement results
- **`DataValue`** — CozoDB's universal value enum: Null, Bool, Num, Str, Bytes, Uuid, List, Vec, Json, etc.

## Code Style & Conventions

### Elixir
- Use `mix format` for automatic formatting
- Follow Elixir naming: snake_case for variables/functions, PascalCase for modules
- Pattern matching preferred over conditionals
- Use `with` for chaining `{:ok, _}` / `{:error, _}` operations
- Module attributes for compile-time configuration

### Rust
- Use `cargo fmt` via `mix rust.fmt`
- Use `cargo clippy` via `mix rust.lint` — treat warnings as errors (`-Dwarnings`)
- Follow Rust naming: snake_case for functions/variables, PascalCase for types, SCREAMING_SNAKE for constants
- Prefix NIF-facing types with `Ex` (e.g., `ExDbInstance`, `ExDataValue`, `ExNamedRows`)

## Elixir Guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`**. **Never use `else if` or `elseif` in Elixir**, **always** use `cond` or `case` for multiple conditionals.

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`
- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`map[:field]`) on structs as they do not implement the Access behaviour by default. Access struct fields directly, e.g. `my_struct.field`
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix Guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason
