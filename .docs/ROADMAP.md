# Cozonomono Roadmap

## Current State (PoC)

The library currently exposes a minimal working surface:

- **Database lifecycle**: `Cozonomono.new/2` — create an in-memory, SQLite, or RocksDB instance; `Cozonomono.close/1` — explicitly release resources
- **Query execution**: `Cozonomono.query/3` — run CozoScript with optional params and immutability flag
- **Data encoding**: Manual `Encoder`/`Decoder` for `DataValue` (handles null, bool, int, float, string, bytes, uuid, list, vec, json) and manual `Encoder` for `NamedRows` (returns a proper `%Cozonomono.NamedRows{}` struct)

---

## Phase 1: Solidify Core & Fix PoC Issues ✅

### 1.1 Fix DataValue Encoding/Decoding ✅
- [x] Encode `DataValue::Null` as atom `nil` not string `"nil"`
- [x] Add `Decoder` support for binary/bytes (Elixir binary → `DataValue::Bytes`)
- [x] Add `Decoder` support for UUID (string or structured → `DataValue::Uuid`)
- [x] Add `Decoder` support for JSON (map → `DataValue::Json`)
- [x] Handle `DataValue::Set` and `DataValue::Validity` encoding to Elixir terms
- [x] Using `rustler::atoms!` for commonly used atoms (`nil`, `ok`, `error`, `validity`, etc.)

### 1.2 Proper NamedRows Struct ✅
- [x] Created `Cozonomono.NamedRows` Elixir struct with typed fields (`headers`, `rows`, `next`)
- [x] Rust `ExNamedRows` encoder builds a proper `%Cozonomono.NamedRows{}` struct via `__struct__` key in the encoded map
- [x] Supports the `next` chain for multi-statement script results (recursive encoding)
- [x] All query results now return `{:ok, %Cozonomono.NamedRows{}}` instead of `{:ok, %{"headers" => ...}}`

### 1.3 Instance Lifecycle ✅
- [x] Added `Cozonomono.close/1` NIF for explicit resource release
- [x] Verified resource cleanup behavior — `ResourceArc` reference counting handles GC cleanup automatically
- [x] Tested with file-backed SQLite engine
- [x] Documented that `close/1` is optional but useful for deterministic cleanup of file-backed engines

---

## Phase 2: Complete CozoDB API Surface

### 2.1 Import / Export ✅
- [x] `export_relations/2` — `fn export_relations(instance, relation_names) -> {:ok, %{String.t() => NamedRows.t()}}`
- [x] `import_relations/2` — `fn import_relations(instance, data) -> :ok | {:error, term()}`
- [x] Decide on data format: use NamedRows structs or raw maps for the import payload — **chose NamedRows structs** for type safety and consistency with query results
- [x] NIF: `export_relations` wrapping `DbInstance::export_relations`
- [x] NIF: `import_relations` wrapping `DbInstance::import_relations`

### 2.2 Backup / Restore ✅
- [x] `backup/2` — `fn backup(instance, path) -> :ok | {:error, term()}`
- [x] `restore/2` — `fn restore(instance, path) -> :ok | {:error, term()}`
- [x] `import_from_backup/3` — selective relation import from a SQLite backup file
- [x] All three wrap the corresponding `DbInstance` methods

### 2.3 Multi-Statement Transactions ✅
- [x] `multi_transaction/2` — create a transaction handle (write or read-only)
- [x] `tx_query/3` — run a script within the transaction (named `tx_query` for consistency with `query/3`)
- [x] `tx_commit/1` — commit the transaction
- [x] `tx_abort/1` — abort the transaction
- [x] Rust side: wrap `DbInstance::multi_transaction` which returns a `MultiTransaction` — uses `ExMultiTransactionRef` / `ExMultiTransaction` resource types following the two-type pattern
- [x] Ownership model: `MultiTransaction` uses crossbeam bounded channels internally — CozoDB spawns a dedicated thread that holds the actual transaction lock, and the NIF communicates via send/recv, so the BEAM scheduler is not blocked and concurrent access is serialized by the channel

### 2.4 System Operations (Schema Introspection) ✅
These are all just CozoScript queries run via `run_script`, but we provide convenience functions:
- [x] `list_relations/1` — `::relations`
- [x] `list_columns/2` — `::columns <relation>`
- [x] `list_indices/2` — `::indices <relation>`
- [x] `remove_relation/2` — `::remove <relation>` (also accepts a list)
- [x] `rename_relation/3` — `::rename <old> -> <new>`
- [ ] `describe_relation/3` — `::describe <relation> '<description>'` — **skipped: grammar bug in cozo 0.7.6** (`describe_relation_op` defined in pest grammar but not included in `sys_script` alternation, so it parses as invalid input)
- [x] `explain/2` — `::explain { <query> }`
- [x] `list_running/1` — `::running`
- [x] `kill_running/2` — `::kill <id>`
- [x] `compact/1` — `::compact`

---

## Phase 3: Advanced Features

### 3.1 Change Callbacks
- [ ] `register_callback/3` — wraps `DbInstance::register_callback`, returns `{id, pid}` where a GenServer or process receives `{:cozo_callback, op, new_rows, old_rows}` messages
- [ ] `unregister_callback/2` — wraps `DbInstance::unregister_callback`
- [ ] Rust side: spawn a thread that reads from the crossbeam `Receiver` and sends Erlang messages via `OwnedEnv` / `env.send()`
- [ ] This is the most complex NIF integration — crossbeam channels must bridge to BEAM message passing

### 3.2 Custom Fixed Rules
- [ ] `register_fixed_rule/3` — register a custom algorithm callable via `<~` in CozoScript
- [ ] Consider using `SimpleFixedRule` for the common case (closure-based)
- [ ] Rust side: the callback must call back into Elixir or accept a Rust closure — evaluate feasibility
- [ ] Alternative: accept the rule implementation as a Rust module compiled into the NIF crate (less dynamic but simpler)

### 3.3 Index Management Helpers
Convenience functions wrapping CozoScript system ops:
- [ ] `create_index/3` — `::index create <relation>:<index_name> {<columns>}`
- [ ] `create_hnsw_index/3` — `::hnsw create ...`
- [ ] `create_fts_index/3` — `::fts create ...`
- [ ] `create_lsh_index/3` — `::lsh create ...`
- [ ] `drop_index/3` — `::index drop <relation>:<index_name>`

### 3.4 Access Level Management
- [ ] `set_access_level/3` — `::set_access <relation> <level>` where level is `:normal | :protected | :read_only | :hidden`

---

## Phase 4: Ergonomics & Performance

### 4.1 Zero-Copy Opportunities
Following Explorer's patterns:
- [ ] Evaluate whether `DataValue::Vec` (F32/F64 arrays) can be returned as zero-copy BEAM binaries pointing into the Rust resource via `resource.make_binary_unsafe`
- [ ] For bulk data export, consider returning column-oriented data instead of row-oriented to enable zero-copy binary slices for numeric columns
- [ ] Profile the `ExDataValue` encoding hot path — if row counts are large, manual encoding with pre-computed atom keys (like Explorer does) will outperform the current approach

### 4.2 Query Builder (Optional)
- [ ] Consider a CozoScript query builder DSL in Elixir for type-safe query construction
- [ ] This is a nice-to-have — CozoScript strings are the primary interface and are well-documented

### 4.3 Telemetry Integration
- [ ] Emit `:telemetry` events for query execution, instance creation, backup/restore
- [ ] Follow conventions from Ecto / other Elixir database libraries

### 4.4 Documentation & Guides
- [ ] ExDoc setup with module docs
- [ ] Getting started guide
- [ ] CozoScript cheat sheet for Elixir developers
- [ ] Examples for common graph patterns (social networks, knowledge graphs, recommendation engines)

---

## Phase 5: Release Preparation

### 5.1 Precompiled Binaries
- [ ] Set up GitHub Actions CI for cross-compilation via `RustlerPrecompiled`
- [ ] Target platforms: macOS (aarch64, x86_64), Linux (x86_64 gnu/musl, aarch64 gnu/musl)
- [ ] Publish precompiled NIF artifacts as GitHub release assets
- [ ] Configure `base_url` in `Cozonomono.Native` to point to release assets

### 5.2 Hex.pm Publication
- [ ] Add package metadata to `mix.exs` (description, licenses, links, etc.)
- [ ] Publish to Hex.pm
- [ ] Version strategy: follow semver, track CozoDB upstream versions in docs

### 5.3 Testing
- [ ] Property-based tests for DataValue round-tripping (encode → decode)
- [ ] Integration tests for all storage engines (mem, sqlite, rocksdb)
- [ ] Stress tests for concurrent query execution
- [ ] Test resource cleanup / GC behavior
