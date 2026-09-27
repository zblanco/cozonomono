# Phase 2.2: Backup / Restore — Implementation Notes

## What was added

Three NIF functions and their Elixir wrappers for SQLite-based backup and restore:

- `Cozonomono.backup(instance, path)` → `:ok` — saves the entire database to a SQLite file
- `Cozonomono.restore(instance, path)` → `:ok` — restores all relations from a SQLite backup
- `Cozonomono.import_from_backup(instance, path, ["rel_a"])` → `:ok` — selectively imports named relations from a backup

## Rust implementation

These are the simplest NIFs in the project — each one calls a single `DbInstance` method and returns `:ok`:

```rust
#[rustler::nif(schedule = "DirtyCpu")]
fn backup_db(instance: ExDbInstance, path: String) -> Result<rustler::Atom, ExError> {
    instance.backup_db(&path)?;
    Ok(rustler::types::atom::ok())
}
```

The `Deref` impl on `ExDbInstance` means `instance.backup_db(...)` calls through to the inner `cozo::DbInstance` directly. The `?` operator converts `cozo::Error` into `ExError` via the `From` impl, which Rustler then returns as `{:error, message}`.

All three use `#[rustler::nif(schedule = "DirtyCpu")]` because they involve file I/O.

## CozoDB backup format

CozoDB always backs up to SQLite format, regardless of the running engine. This means:
- A `:mem` instance can be backed up to disk and restored later
- A `:rocksdb` instance's backup is a portable SQLite file
- `import_from_backup` lets you cherry-pick which relations to restore from a backup

## Behavioral notes discovered during testing

- **`restore_backup` with a non-existent path** does not error — CozoDB creates a new empty SQLite database at that path and "restores" from it (which is essentially empty). This is documented in the tests.
- **`import_from_backup` requires the target relation to already exist** in the destination database with a matching schema. CozoDB errors with "Cannot find requested stored relation" if it doesn't.

## Files changed

| File | Change |
|------|--------|
| `native/.../lib.rs` | Added `backup_db`, `restore_backup`, `import_from_backup` NIF functions |
| `lib/cozonomono.ex` | Added `backup/2`, `restore/2`, `import_from_backup/3` public API |
| `lib/cozonomono/native.ex` | Added NIF stubs |
| `test/backup_restore_test.exs` | 5 tests covering backup, restore, selective import, and round-trip |
