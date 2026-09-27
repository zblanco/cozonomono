# API map

- `Cozonomono.new/2` and `Cozonomono.close/1` manage database instances.
- `Cozonomono.query/3` is the main entry point for CozoScript.
- `Cozonomono.query_lazy/3` and `Cozonomono.LazyRows` cover zero-copy reads.
- `Cozonomono.multi_transaction/2`, `tx_query/3`, `tx_query_lazy/3`,
  `tx_commit/1`, and `tx_abort/1` cover host-managed transactions.
- `export_relations/2`, `import_relations/2`, `backup/2`, `restore/2`, and
  `import_from_backup/3` cover data movement and backups.
- `register_callback/3` and `unregister_callback/2` cover change subscriptions.
- `register_fixed_rule/4`, `respond_fixed_rule/3`, and
  `unregister_fixed_rule/2` bridge custom fixed rules into Elixir.
- `create_index/4`, `create_hnsw_index/4`, `create_fts_index/4`,
  `create_lsh_index/4`, and `drop_index/3` manage index lifecycle.
- `list_relations/1`, `list_columns/2`, `list_indices/2`, `remove_relation/2`,
  `rename_relation/3`, `explain/2`, `list_running/1`, `kill_running/2`,
  `compact/1`, and `set_access_level/3` wrap common system ops.
