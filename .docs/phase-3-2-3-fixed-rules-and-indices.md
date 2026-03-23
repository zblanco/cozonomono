# Phases 3.2 & 3.3: Custom Fixed Rules & Index Management

## Phase 3.2: Custom Fixed Rules

### What We Built

CozoDB lets you register custom algorithms ("fixed rules") that can be invoked in CozoScript with the `<~` operator. For example, after registering a rule called `MyTransform`, you can write:

```cozoscript
?[a, b] <~ MyTransform(input_relation[], multiplier: 3)
```

We bridged this from Rust into Elixir so that an Elixir process can implement the rule logic and respond dynamically.

### The Key Challenge: Synchronous Request-Response Across NIF/BEAM

Unlike callbacks (Phase 3.1) which are fire-and-forget, fixed rules are **synchronous** — CozoDB blocks the query thread waiting for the rule result. This means our NIF must:

1. Receive the rule invocation from CozoDB (on a Rust thread)
2. Forward it to an Elixir process
3. **Wait** for the Elixir process to compute and return the result
4. Send the result back to CozoDB so the query can continue

### CozoDB's `SimpleFixedRule::rule_with_channel`

CozoDB provides `SimpleFixedRule::rule_with_channel(arity)` which returns a tuple:

```rust
(SimpleFixedRule, Receiver<(Vec<NamedRows>, BTreeMap<String, DataValue>, Sender<Result<NamedRows>>)>)
```

**Elixir analogy**: Think of this as CozoDB giving you a GenServer-like mailbox. When a query invokes your rule:
- CozoDB sends `(inputs, options, response_mailbox)` through the channel
- Your code reads it, computes the answer, and sends the result back via `response_mailbox`
- CozoDB's query thread blocks on `response_mailbox.recv()` until you respond

The third element (`Sender<Result<NamedRows>>`) is a **one-shot response channel** — each invocation gets its own.

### The Bridge Resource Pattern

Since fixed rules can be invoked **concurrently** (the rule is `Arc<Box<dyn FixedRule>>` and `run()` takes `&self`), we can't use a single response channel. Instead, we use a **pending request map**:

```
ExFixedRuleBridgeRef {
    pid: LocalPid,              // target Elixir process
    name: String,               // rule name
    next_request_id: AtomicU64, // monotonic counter
    pending: Mutex<HashMap<u64, Sender<Result<NamedRows>>>>,
    closed: AtomicBool,
}
```

**Flow**:

```
CozoDB Query Thread                Forwarding Thread           Elixir Process
       |                                  |                         |
       |-- (inputs, opts, resp_sender) -->|                         |
       |                                  |                         |
       |                     insert(req_id=7, resp_sender)          |
       |                     into pending map                       |
       |                                  |                         |
       |                                  |-- OwnedEnv.send -->     |
       |                                  |   {:cozo_fixed_rule,    |
       |                                  |    7, inputs, opts}     |
       |                                  |                         |
       |                                  |              compute result
       |                                  |                         |
       |                                  |    <-- respond_fixed_rule(bridge, 7, result)
       |                                  |         (NIF on DirtyCpu scheduler)
       |                                  |                         |
       |              remove(req_id=7)    |                         |
       |              from pending map    |                         |
       |                                  |                         |
       |    <-- resp_sender.send(Ok(result))                        |
       |                                  |                         |
       | query continues...               |                         |
```

### Why Not a Simpler Design?

**Q: Can we use a single bounded(0) channel for responses?**
No — multiple queries can invoke the same rule concurrently. A single channel would mix up responses.

**Q: Can we use a mutex/condvar?**
Unnecessary complexity. The pending map + per-invocation `Sender` is cleaner and directly maps to CozoDB's API.

**Q: Why not have the forwarding thread block waiting for the Elixir response?**
The forwarding thread must stay free to handle the next invocation request from CozoDB. With the pending map approach, it sends to Elixir and immediately loops back to `recv()` for the next request.

### Cleanup

When the rule is unregistered or the bridge is dropped:
- `fail_all_pending()` drains the pending map and sends errors to all blocked CozoDB query threads
- This prevents queries from hanging forever if the handler disappears

### New Rust Types

| Type | Purpose |
|------|---------|
| `ExFixedRuleBridgeRef` | Inner resource: holds PID, pending map, request counter |
| `ExFixedRuleBridge` | NifStruct wrapping `ResourceArc<ExFixedRuleBridgeRef>`, maps to `%Cozonomono.FixedRuleBridge{}` |

### New NIF Functions

| NIF | Schedule | Purpose |
|-----|----------|---------|
| `register_fixed_rule` | DirtyCpu | Register rule, spawn forwarding thread, return bridge |
| `respond_fixed_rule` | DirtyCpu | Look up pending request by ID, send result to CozoDB |
| `unregister_fixed_rule` | DirtyCpu | Remove rule from CozoDB |

---

## Phase 3.3: Index Management Helpers

These are pure Elixir convenience wrappers — no Rust changes needed. They build CozoScript system operation strings and call `query/3`.

### CozoScript Index Syntax

```
::index create relation:index_name {col1, col2}        -- standard index
::hnsw create relation:index_name {dim: N, ...}        -- vector (HNSW) index
::fts create relation:index_name {extractor: ..., ...}  -- full-text search index
::lsh create relation:index_name {extractor: ..., ...}  -- MinHash LSH index
::index drop relation:index_name                        -- drop any index type
```

### Design Decision: Options as Strings

For HNSW, FTS, and LSH indices, the configuration options are complex and CozoDB-specific (tokenizer configs, distance functions, etc.). Rather than modeling every option as Elixir types (which would be fragile and require updating when CozoDB adds new options), we accept the options as a raw CozoScript string. This keeps the wrapper thin and forward-compatible.

Standard indices take a list of column names since that's a simpler, well-defined interface.

## Files Changed

| File | Phase | What Changed |
|------|-------|-------------|
| `native/.../Cargo.toml` | 3.2 | Added `crossbeam` and `miette` as direct dependencies |
| `native/.../datatypes.rs` | 3.2 | Added `cozo_fixed_rule` atom, `ExFixedRuleBridgeRef`, `ExFixedRuleBridge` |
| `native/.../error.rs` | 3.2 | Added `ExError::FixedRule` variant |
| `native/.../lib.rs` | 3.2 | Added `register_fixed_rule`, `respond_fixed_rule`, `unregister_fixed_rule` NIFs |
| `lib/cozonomono/fixed_rule_bridge.ex` | 3.2 | New struct for `%Cozonomono.FixedRuleBridge{}` |
| `lib/cozonomono/native.ex` | 3.2 | Added NIF stubs |
| `lib/cozonomono.ex` | 3.2+3.3 | Added public API for fixed rules and index management |
| `test/fixed_rule_test.exs` | 3.2 | 5 tests |
| `test/index_test.exs` | 3.3 | 8 tests |

## Test Count: 85 (was 72)
