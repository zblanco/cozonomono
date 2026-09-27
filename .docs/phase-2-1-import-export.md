# Phase 2.1: Import / Export — Implementation Notes

## What was added

Two new NIF functions and their Elixir wrappers for bulk data import/export of stored relations:

- `Cozonomono.export_relations(instance, ["rel_a", "rel_b"])` → `{:ok, %{"rel_a" => %NamedRows{}, ...}}`
- `Cozonomono.import_relations(instance, %{"rel_a" => %NamedRows{...}})` → `:ok | {:error, term()}`

## The key Rust change: `Decoder` for `ExNamedRows`

Previously, `ExNamedRows` only had an `Encoder` (Rust → Elixir). For `import_relations`, data flows the other direction (Elixir → Rust), so we needed a `Decoder` implementation.

### How the Decoder works

When Elixir calls `import_relations(instance, %{"users" => %NamedRows{...}})`, Rustler needs to convert that Elixir map into Rust types. The NIF signature is:

```rust
fn import_relations(
    instance: ExDbInstance,
    data: HashMap<String, ExNamedRows>,
) -> Result<rustler::Atom, ExError>
```

Rustler knows how to decode `HashMap<String, T>` from an Elixir map automatically — but only if `T` (here `ExNamedRows`) implements the `Decoder` trait. So we implemented:

```rust
impl<'a> Decoder<'a> for ExNamedRows {
    fn decode(term: Term<'a>) -> NifResult<Self> { ... }
}
```

This pulls out the three fields from the Elixir `%NamedRows{}` struct by looking up the `:headers`, `:rows`, and `:next` keys in the map. Each row is a list of `ExDataValue` terms, which already had a `Decoder` from Phase 1. The `next` field is either `nil` (atom → `None`) or another `%NamedRows{}` struct (decoded recursively → `Some(Box<NamedRows>)`).

### Why `map_get` with atom keys?

Elixir structs are maps with atom keys. On the Rust/NIF side, we use the same `atoms!` macro atoms defined for encoding:

```rust
let headers_term = term.map_get(atoms::headers().encode(term.get_env()))?;
```

This looks up the `:headers` atom key in the Elixir map — the same atom we use when *building* the struct in the `Encoder`. Reusing the `atoms!` block keeps encoding and decoding symmetrical.

### Why `HashMap` and not `BTreeMap` for the NIF parameter?

Rustler's built-in `Decoder` for maps supports `HashMap` out of the box. CozoDB's `import_relations` method wants a `BTreeMap`, so we do a simple `.collect()` conversion inside the NIF:

```rust
let data: BTreeMap<String, cozo::NamedRows> =
    data.into_iter().map(|(k, v)| (k, v.0)).collect();
instance.import_relations(data)?;
```

The `v.0` unwraps `ExNamedRows(NamedRows)` to get the inner `NamedRows`.

## The export side

`export_relations` is simpler — CozoDB returns `BTreeMap<String, NamedRows>`, and we wrap each value in `ExNamedRows` so the existing `Encoder` converts them to `%NamedRows{}` structs:

```rust
let result = instance.export_relations(relations.iter().map(|s| s.as_str()))?;
Ok(result.into_iter().map(|(k, v)| (k, ExNamedRows(v))).collect())
```

The return type `HashMap<String, ExNamedRows>` is encoded by Rustler as an Elixir map `%{String.t() => %NamedRows{}}` automatically, since both `String` and `ExNamedRows` implement `Encoder`.

## Design decision: NamedRows structs for import payload

We chose to use `%NamedRows{}` structs (not raw maps) as the import data format. This means:

1. **Export returns what import accepts** — you can pipe `export_relations` output directly into `import_relations`
2. **Type safety** — the Rust `Decoder` validates the structure at the NIF boundary
3. **Consistency** — the same struct is used for query results, exports, and imports

## Files changed

| File | Change |
|------|--------|
| `native/.../datatypes.rs` | Added `Decoder` impl for `ExNamedRows` |
| `native/.../lib.rs` | Added `export_relations` and `import_relations` NIF functions, registered in `rustler::init!` |
| `lib/cozonomono.ex` | Added `export_relations/2` and `import_relations/2` public API |
| `lib/cozonomono/native.ex` | Added NIF stubs |
| `test/import_export_test.exs` | 8 tests covering export, import, errors, and round-trip |
