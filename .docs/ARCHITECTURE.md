# Cozonomono Architecture

## Overview

```
┌─────────────────────────────────────────────────────┐
│  Elixir Application                                 │
│                                                     │
│  Cozonomono  ──→  Cozonomono.Native (NIF stubs)     │
│       ↑                    │                        │
│  Cozonomono.Instance       │ BEAM NIF call          │
│  (opaque resource ref)     ↓                        │
├─────────────────────────────────────────────────────┤
│  Rust NIF (native/cozonomono_cozo/)                 │
│                                                     │
│  ExDbInstance ──→ ResourceArc<ExDbInstanceRef>       │
│       │                    │                        │
│       │ Deref              │ owns                   │
│       ↓                    ↓                        │
│  cozo::DbInstance  ←── ExDbInstanceRef(DbInstance)  │
│       │                                             │
│       ↓                                             │
│  cozo-core (storage engine + query engine)          │
└─────────────────────────────────────────────────────┘
```

## Data Flow

### Creating an Instance

```
Cozonomono.new(:mem, "")
  → Native.create_instance("mem", "")
    → [Rust] cozo::DbInstance::new("mem", "", "")
    → [Rust] ExDbInstance { resource: ResourceArc::new(ExDbInstanceRef(instance)), engine, path }
    → [Rustler encodes as] {:ok, %Cozonomono.Instance{resource: #Ref<>, engine: "mem", path: ""}}
```

The `%Cozonomono.Instance{}` struct holds an opaque reference to the Rust-heap-allocated `DbInstance`. The BEAM never copies or inspects the database internals — it only passes the reference back to NIFs.

### Running a Query

```
Cozonomono.query(instance, "?[] <- [['hello', 'world']]")
  → Native.run_default(instance, payload)
    → [Rust] instance.run_default(&payload)  (via Deref)
    → [Rust] ExNamedRows(named_rows)
    → [Rustler encodes via manual Encoder] {:ok, %{"headers" => [...], "rows" => [...], "next" => nil}}
```

### DataValue Mapping

| CozoDB DataValue | Elixir Term |
|---|---|
| `Null` | `nil` (currently encodes as `"nil"` — needs fix) |
| `Bool(b)` | `true` / `false` |
| `Num::Int(i)` | integer |
| `Num::Float(f)` | float |
| `Str(s)` | binary string |
| `Bytes(b)` | binary |
| `Uuid(u)` | string (UUID formatted) |
| `List(l)` | list (recursive) |
| `Vec::F32(v)` | list of floats |
| `Vec::F64(v)` | list of floats |
| `Json(j)` | string (JSON formatted — consider returning a decoded map) |

## Resource Lifecycle

BEAM resources are reference-counted. When the last Elixir reference to a `%Cozonomono.Instance{}` is garbage collected, the `ResourceArc<ExDbInstanceRef>` drop runs, which drops the inner `cozo::DbInstance`, closing any open storage engine handles.

For SQLite and RocksDB engines this means file handles and locks are released. For in-memory engines the data is freed.

## Explorer Pattern Reference

This project follows the [Explorer](https://github.com/elixir-explorer/explorer) NIF interop pattern:

| Concern | Explorer | Cozonomono |
|---|---|---|
| Resource wrapper | `ExSeriesRef(Series)` | `ExDbInstanceRef(DbInstance)` |
| NIF struct | `ExSeries { resource: ResourceArc<...> }` | `ExDbInstance { resource: ResourceArc<...>, engine, path }` |
| Deref target | `Series` | `DbInstance` |
| Elixir struct | `%Explorer.PolarsBackend.Series{resource: ref}` | `%Cozonomono.Instance{resource: ref, engine: _, path: _}` |
| Error type | `ExplorerError` (thiserror + Encoder) | `ExError` (thiserror + Encoder) |
| NIF scheduling | `DirtyCpu` for computation, bare for metadata | `DirtyCpu` for all CozoDB operations |
| Result encoding | `{:ok, _}` / `{:error, _}` | `{:ok, _}` / `{:error, _}` |

### Future resource types to add

As more of the CozoDB API is exposed, new resource types will be needed:

- **`ExMultiTransaction`** — wraps `cozo::MultiTransaction` for multi-statement transactions
- **`ExNamedRows` as NifStruct** — currently uses manual encoding; could become a proper resource or NifStruct for zero-copy passing between NIF calls (e.g., query result → import)
