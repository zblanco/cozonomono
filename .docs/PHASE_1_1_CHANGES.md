# Phase 1.1: DataValue Encoding/Decoding — What Changed and Why

## Summary

Phase 1.1 fixed how CozoDB's `DataValue` type converts between Rust and Elixir. The core file changed is `native/cozonomono_cozo/src/datatypes.rs`. Two new Rust dependencies were added (`serde_json`, `uuid`) and 20 new tests cover the changes.

---

## How NIF Data Conversion Works (The Big Picture)

When you call `Cozonomono.query(instance, "?[] <- [[null, 42, 'hello']]")` from Elixir, here's what happens at the Rust boundary:

1. **Elixir → Rust (Decoding)**: Rustler takes the Elixir terms you passed and calls the `Decoder` trait implementation to convert them into Rust types. This is how your `%Cozonomono.Instance{}` struct becomes an `ExDbInstance` in Rust, and how query params like `%{"name" => "Alice"}` become a `HashMap<String, ExDataValue>`.

2. **Rust → Elixir (Encoding)**: After CozoDB runs the query, Rustler takes the Rust return value and calls the `Encoder` trait implementation to convert it back into Elixir terms. This is how query results become `{:ok, %{"headers" => [...], "rows" => [...]}}`.

`ExDataValue` is our bridge type — it wraps CozoDB's `DataValue` enum and implements both `Encoder` (Rust → Elixir) and `Decoder` (Elixir → Rust).

---

## What Was Fixed

### 1. Null Encoding: `"nil"` → `nil`

**Before**: `DataValue::Null` was encoded as the *string* `"nil"` (a binary containing the three characters n-i-l).

```rust
// OLD — wrong
DataValue::Null => "nil".encode(env),
```

**After**: Uses a proper BEAM atom `nil`, which is what Elixir's `nil` actually is.

```rust
// NEW — correct
DataValue::Null => atoms::nil().encode(env),
```

**Why this matters**: In Elixir, `nil` is the atom `:nil`. The string `"nil"` is a completely different value — you'd fail pattern matches like `if result == nil`.

**The `rustler::atoms!` macro**: We added an `atoms` module at the top of the file:

```rust
mod atoms {
    rustler::atoms! {
        nil,
        ok,
        error,
        validity,
        json,
    }
}
```

This macro creates functions that return BEAM atom handles. The first time `atoms::nil()` is called, it looks up (or creates) the atom in the BEAM's global atom table. After that, it's just an integer comparison — extremely fast. This is the same pattern Explorer uses for its commonly-referenced atoms.

### 2. Set Encoding

**Before**: The `DataValue::Set` variant hit the catch-all `_ => "nil"` branch and was silently dropped.

**After**: Sets are encoded as Elixir lists (the BEAM has no built-in set type):

```rust
DataValue::Set(set) => set
    .iter()
    .map(|data_value| ExDataValue(data_value.clone()))
    .collect::<Vec<ExDataValue>>()
    .encode(env),
```

**Rust detail — `BTreeSet`**: CozoDB uses `BTreeSet<DataValue>` for sets, which is a sorted set backed by a B-tree. The `.iter()` method yields items in sorted order, so the resulting Elixir list will be consistently ordered.

### 3. Validity Encoding

**Before**: `DataValue::Validity` hit the catch-all and became `nil`.

**After**: Encoded as a tagged 3-tuple `{:validity, timestamp, is_assert}`:

```rust
DataValue::Validity(validity) => {
    let timestamp = validity.timestamp.0.0;
    let is_assert = validity.is_assert.0;
    (atoms::validity(), timestamp, is_assert).encode(env)
}
```

**Why `.0.0`?**: CozoDB wraps the timestamp in two layers:
- `validity.timestamp` is a `ValidityTs`
- `ValidityTs` contains `Reverse<i64>` (from `std::cmp::Reverse`, used so timestamps sort descending in the B-tree)
- `Reverse<i64>` contains the actual `i64`

So `.timestamp.0` unwraps `ValidityTs` → `.0` again unwraps `Reverse` → you get the raw `i64`.

### 4. JSON Encoding: Strings → Native Maps

**Before**: `DataValue::Json` was encoded as a JSON string (`json.to_string()`), so Elixir received `"{\"key\":\"value\"}"` — a string you'd have to parse.

**After**: JSON is recursively converted to native Elixir terms:

```rust
DataValue::Json(cozo::JsonData(json)) => encode_json_value(json, env),
```

The `encode_json_value` function walks the `serde_json::Value` tree and maps each variant to the corresponding Elixir term:

| JSON | Elixir |
|------|--------|
| `null` | `nil` |
| `true`/`false` | `true`/`false` |
| `42` (integer) | `42` |
| `3.14` (float) | `3.14` |
| `"hello"` | `"hello"` |
| `[1, 2]` | `[1, 2]` |
| `{"a": 1}` | `%{"a" => 1}` |

**Rust detail — `serde_json::Value`**: This is Rust's standard JSON representation (from the `serde_json` crate). It's an enum similar to CozoDB's `DataValue` but specifically for JSON. CozoDB re-exports it as `JsonData(JsonValue)` where `JsonValue = serde_json::Value`. We added `serde_json` to `Cargo.toml` so we can work with it directly.

### 5. UUID Decoding (Elixir → Rust)

**Before**: All strings from Elixir became `DataValue::Str`. There was no way to pass a UUID as a parameter.

**After**: When a string arrives from Elixir, we check if it's a valid UUID:

```rust
rustler::TermType::Binary => {
    if let Ok(s) = term.decode::<String>() {
        if let Ok(uuid) = uuid::Uuid::parse_str(&s) {
            Ok(ExDataValue(DataValue::Uuid(cozo::UuidWrapper(uuid))))
        } else {
            Ok(ExDataValue(DataValue::Str(s.into())))
        }
    } else {
        // Not valid UTF-8 — treat as raw bytes
        let bytes = term.decode::<Vec<u8>>()?;
        Ok(ExDataValue(DataValue::Bytes(bytes)))
    }
}
```

**Why `TermType::Binary`?**: In the BEAM, both Elixir strings (`"hello"`) and raw binaries (`<<1, 2, 3>>`) are the same term type: `Binary`. The difference is whether the bytes are valid UTF-8. We try `decode::<String>()` first (which requires valid UTF-8), and fall back to `decode::<Vec<u8>>()` for raw bytes.

**Rust detail — `if let Ok(x) = expr`**: This is Rust's pattern-matching `if`. `uuid::Uuid::parse_str(&s)` returns a `Result` — if parsing succeeds, we get the UUID; if not, we treat it as a plain string. No exceptions, no panics.

### 6. JSON Decoding (Elixir → Rust)

**Before**: Maps from Elixir couldn't be passed as parameters at all (they'd hit `unsupported_type`).

**After**: Elixir maps are decoded as `DataValue::Json`:

```rust
rustler::TermType::Map => {
    let json_value = decode_map_to_json(term)?;
    Ok(ExDataValue(DataValue::Json(cozo::JsonData(json_value))))
}
```

The helper functions `decode_map_to_json` and `decode_term_to_json` recursively walk the Elixir map and convert it to a `serde_json::Value::Object`. This means you can now do:

```elixir
Cozonomono.query(instance, "?[] <- [[$data]]",
  params: %{"data" => %{"name" => "Alice", "scores" => [1, 2, 3]}}
)
# Returns: {:ok, %{"rows" => [[%{"name" => "Alice", "scores" => [1, 2, 3]}]]}}
```

**Rust detail — `MapIterator`**: Rustler provides `MapIterator::new(term)` to iterate over an Elixir map's key-value pairs from Rust. It returns `Option<MapIterator>` (not `Result`) because map creation can't fail with an error message — the term either is a map or it isn't. We use `.ok_or(...)` to convert the `Option` into a `Result` for the `?` operator.

### 7. Bytes Decoding (Elixir → Rust)

**Before**: Raw binaries from Elixir would fail with `unsupported_type`.

**After**: Non-UTF-8 binaries are decoded as `DataValue::Bytes` (covered in the UUID section above — it's the fallback when `decode::<String>()` fails).

---

## Rust Concepts Quick Reference

| Concept | What It Means |
|---------|--------------|
| `impl Encoder for T` | Defines how to convert a Rust type `T` into a BEAM term (Rust → Elixir) |
| `impl Decoder for T` | Defines how to convert a BEAM term into Rust type `T` (Elixir → Rust) |
| `Term<'a>` | A reference to a BEAM term, valid for lifetime `'a` (the NIF call duration) |
| `Env<'a>` | A reference to the BEAM environment for the current NIF call |
| `term.encode(env)` | Convert a Rust value into a BEAM term |
| `term.decode::<T>()` | Try to convert a BEAM term into Rust type `T`, returns `Result` |
| `match &self.0 { ... }` | Pattern matching on the inner value of a newtype wrapper |
| `.clone()` | Make an owned copy (needed because `ResourceArc` only gives `&T` references) |
| `into()` | Type conversion via the `Into` trait (e.g., `String` → `SmartString`) |
| `?` operator | Early-return on `Err` — like `with` in Elixir but for `Result` types |
| `Term<'_>` | Anonymous lifetime — tells the compiler "there's a lifetime here but I don't need to name it" |

## Files Changed

- `native/cozonomono_cozo/Cargo.toml` — Added `serde_json` and `uuid` dependencies
- `native/cozonomono_cozo/src/datatypes.rs` — All encoding/decoding fixes
- `test/data_value_test.exs` — 20 new tests covering all data type conversions
