# Cozonomono Roadmap

## Current State (PoC)

The library currently exposes a minimal working surface:

- **Database lifecycle**: `Cozonomono.new/2` — create an in-memory, SQLite, or RocksDB instance
- **Query execution**: `Cozonomono.query/3` — run CozoScript with optional params and immutability flag
- **Data encoding**: Manual `Encoder`/`Decoder` for `DataValue` (handles null, bool, int, float, string, bytes, uuid, list, vec, json) and manual `Encoder` for `NamedRows` (returns a plain map with string keys)

### Known Gaps in the PoC
- `ExNamedRows` returns a plain map with string keys (`%{"headers" => ..., "rows" => ..., "next" => ...}`) — should return a proper Elixir struct
- `ExDataValue` decoder doesn't handle bytes, uuid, or json input from Elixir
- `ExDataValue` encoder maps `Null` to the string `"nil"` instead of the atom `nil`
- No resource cleanup / explicit close for database instances
- No support for multi-statement transactions, import/export, backup/restore, callbacks, or custom fixed rules

---

## Phase 1: Solidify Core & Fix PoC Issues

### 1.1 Fix DataValue Encoding/Decoding
- [ ] Encode `DataValue::Null` as atom `nil` not string `"nil"`
- [ ] Add `Decoder` support for binary/bytes (Elixir binary → `DataValue::Bytes`)
- [ ] Add `Decoder` support for UUID (string or structured → `DataValue::Uuid`)
- [ ] Add `Decoder` support for JSON (map → `DataValue::Json`)
- [ ] Handle `DataValue::Set` and `DataValue::Validity` encoding to Elixir terms
- [ ] Consider using `rustler::atoms!` for commonly used atoms (`nil`, `true`, `false`, `ok`, `error`)

### 1.2 Proper NamedRows Struct
- [ ] Create `Cozonomono.NamedRows` Elixir struct with typed fields
- [ ] Option A: Use `#[derive(NifStruct)]` on a new `ExNamedRows` struct (requires `next` to be encodable)
- [ ] Option B: Keep manual `Encoder` but return a proper `%Cozonomono.NamedRows{}` struct via NifStruct-compatible map construction
- [ ] Support the `next` chain for multi-statement script results as a linked list of NamedRows

### 1.3 Instance Lifecycle
- [ ] Add `Cozonomono.close/1` NIF to explicitly drop the `DbInstance` (or document reliance on GC)
- [ ] Verify resource cleanup behavior — when the Elixir reference is garbage collected, the Rust `ResourceArc` should drop the `DbInstance`

---

## Phase 2: Complete CozoDB API Surface

### 2.1 Import / Export
- [ ] `export_relations/2` — `fn export_relations(instance, relation_names) -> {:ok, %{String.t() => NamedRows.t()}}`
- [ ] `import_relations/2` — `fn import_relations(instance, data) -> :ok | {:error, term()}`
- [ ] Decide on data format: use NamedRows structs or raw maps for the import payload
- [ ] NIF: `export_relations` wrapping `DbInstance::export_relations`
- [ ] NIF: `import_relations` wrapping `DbInstance::import_relations`

### 2.2 Backup / Restore
- [ ] `backup/2` — `fn backup(instance, path) -> :ok | {:error, term()}`
- [ ] `restore/2` — `fn restore(instance, path) -> :ok | {:error, term()}`
- [ ] `import_from_backup/3` — selective relation import from a SQLite backup file
- [ ] All three wrap the corresponding `DbInstance` methods

### 2.3 Multi-Statement Transactions
- [ ] `multi_transaction/2` — create a transaction handle (write or read-only)
- [ ] `tx_run/3` — run a script within the transaction
- [ ] `tx_commit/1` — commit the transaction
- [ ] `tx_abort/1` — abort the transaction
- [ ] Rust side: wrap `DbInstance::multi_transaction` which returns a `MultiTransaction` — this needs its own resource type (`ExMultiTransactionRef` / `ExMultiTransaction`)
- [ ] Consider ownership model: the `MultiTransaction` holds a mutable borrow, so concurrent access must be prevented or serialized

### 2.4 System Operations (Schema Introspection)
These are all just CozoScript queries run via `run_script`, but we should provide convenience functions:
- [ ] `list_relations/1` — `::relations`
- [ ] `list_columns/2` — `::columns <relation>`
- [ ] `list_indices/2` — `::indices <relation>`
- [ ] `remove_relation/2` — `::remove <relation>`
- [ ] `rename_relation/3` — `::rename <relation> <new_name>`
- [ ] `describe_relation/3` — `::describe <relation> '<description>'`
- [ ] `explain/2` — `::explain { <query> }`
- [ ] `list_running/1` — `::running`
- [ ] `kill_running/2` — `::kill <id>`
- [ ] `compact/1` — `::compact`

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
