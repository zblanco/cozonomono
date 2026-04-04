defmodule Cozonomono do
  @moduledoc """
  Elixir bindings for CozoDB.

  Cozonomono is intentionally thin around the core Cozo query model:

  - use `query/3` for most CozoScript
  - use `query_lazy/3` when you want zero-copy result access
  - use the wrapper helpers in this module for lifecycle, transactions, system
    ops, data movement, callbacks, fixed rules, and index management

  See also:

  - `README.md` for the quick start
  - `CHEATSHEET.md` for the API map
  - the guides in `guides/` for concept-oriented examples
  """

  alias Cozonomono.FixedRuleBridge
  alias Cozonomono.Instance
  alias Cozonomono.LazyRows
  alias Cozonomono.NamedRows
  alias Cozonomono.Native
  alias Cozonomono.Transaction

  @type engine :: :mem | :sqlite | :rocksdb

  @doc """
  Creates a new Cozo database instance.
  """
  @spec new(engine :: engine(), path :: String.t()) :: {:ok, Instance.t()} | {:error, term()}
  def new(engine \\ :mem, path \\ ""),
    do: engine |> Atom.to_string() |> Native.create_instance(path)

  @doc """
  Closes a database instance, releasing the underlying resources.

  This is optional — instances are automatically cleaned up when garbage collected.
  Explicit closing is useful for file-backed engines (`:sqlite`, `:rocksdb`) where
  you want deterministic release of file handles and locks.

  After closing, the instance should not be used for further queries.
  """
  @spec close(Instance.t()) :: :ok | {:error, term()}
  def close(instance) do
    case Native.close_instance(instance) do
      {:ok, :ok} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Exports the specified stored relations from the database.

  Returns a map of relation names to `%NamedRows{}` structs containing the data.

  ## Examples

      {:ok, data} = Cozonomono.export_relations(instance, ["users", "posts"])
      # => {:ok, %{"users" => %NamedRows{...}, "posts" => %NamedRows{...}}}
  """
  @spec export_relations(Instance.t(), [String.t()]) ::
          {:ok, %{String.t() => NamedRows.t()}} | {:error, term()}
  def export_relations(instance, relations) when is_list(relations) do
    Native.export_relations(instance, relations)
  end

  @doc """
  Imports data into stored relations.

  The data must be a map where keys are relation names (strings) and values are
  `%NamedRows{}` structs. The relations must already exist with matching schemas.

  ## Examples

      :ok = Cozonomono.import_relations(instance, %{
        "users" => %NamedRows{headers: ["id", "name"], rows: [[1, "Alice"]]}
      })
  """
  @spec import_relations(Instance.t(), %{String.t() => NamedRows.t()}) ::
          :ok | {:error, term()}
  def import_relations(instance, data) when is_map(data) do
    case Native.import_relations(instance, data) do
      {:ok, :ok} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Backs up the database to a SQLite file at the given path.

  The backup file can be restored with `restore/2` or selectively imported
  with `import_from_backup/3`.
  """
  @spec backup(Instance.t(), String.t()) :: :ok | {:error, term()}
  def backup(instance, path) do
    case Native.backup_db(instance, path) do
      {:ok, :ok} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Restores all relations from a SQLite backup file into the database.

  This replaces existing data in the target relations.
  """
  @spec restore(Instance.t(), String.t()) :: :ok | {:error, term()}
  def restore(instance, path) do
    case Native.restore_backup(instance, path) do
      {:ok, :ok} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Selectively imports specific relations from a SQLite backup file.

  Only the named relations are imported; other relations in the backup are ignored.
  """
  @spec import_from_backup(Instance.t(), String.t(), [String.t()]) :: :ok | {:error, term()}
  def import_from_backup(instance, path, relations) when is_list(relations) do
    case Native.import_from_backup(instance, path, relations) do
      {:ok, :ok} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Creates a multi-statement transaction handle.

  Use `tx_query/3` to run queries within the transaction, then `tx_commit/1`
  or `tx_abort/1` to finalize.

  ## Options

    * `write` - whether the transaction can write (default: `true`).
      Pass `false` for a read-only transaction.

  ## Examples

      {:ok, tx} = Cozonomono.multi_transaction(instance)
      {:ok, _} = Cozonomono.tx_query(tx, "?[id, name] <- [[1, 'Alice']] :put users {id => name}")
      :ok = Cozonomono.tx_commit(tx)
  """
  @spec multi_transaction(Instance.t(), boolean()) :: {:ok, Transaction.t()}
  def multi_transaction(instance, write \\ true) do
    {:ok, Native.multi_transaction(instance, write)}
  end

  @doc """
  Runs a query within a multi-statement transaction.
  """
  @spec tx_query(Transaction.t(), String.t(), map() | nil) ::
          {:ok, NamedRows.t()} | {:error, term()}
  def tx_query(tx, query, params \\ nil) do
    params = params || %{}
    Native.tx_run_script(tx, query, params)
  end

  @doc """
  Commits the multi-statement transaction, making all changes permanent.
  """
  @spec tx_commit(Transaction.t()) :: :ok | {:error, term()}
  def tx_commit(tx) do
    case Native.tx_commit(tx) do
      {:ok, :ok} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Aborts the multi-statement transaction, discarding all changes.
  """
  @spec tx_abort(Transaction.t()) :: :ok | {:error, term()}
  def tx_abort(tx) do
    case Native.tx_abort(tx) do
      {:ok, :ok} -> :ok
      {:error, _} = error -> error
    end
  end

  # --- System Operations (Schema Introspection) ---

  @doc """
  Lists all stored relations in the database.

  Returns headers: `["name", "arity", "access_level", "n_keys", "n_non_keys",
  "n_put_triggers", "n_rm_triggers", "n_replace_triggers", "description"]`
  """
  @spec list_relations(Instance.t()) :: {:ok, NamedRows.t()} | {:error, term()}
  def list_relations(instance), do: query(instance, "::relations")

  @doc """
  Lists all columns for the given stored relation.

  Returns headers: `["column", "is_key", "index", "type", "has_default"]`
  """
  @spec list_columns(Instance.t(), String.t()) :: {:ok, NamedRows.t()} | {:error, term()}
  def list_columns(instance, relation), do: query(instance, "::columns #{relation}")

  @doc """
  Lists all indices for the given stored relation.

  Returns headers: `["name", "type", "relations", "config"]`
  """
  @spec list_indices(Instance.t(), String.t()) :: {:ok, NamedRows.t()} | {:error, term()}
  def list_indices(instance, relation), do: query(instance, "::indices #{relation}")

  @doc """
  Removes one or more stored relations from the database.

  Accepts a single relation name or a list of names.
  """
  @spec remove_relation(Instance.t(), String.t() | [String.t()]) ::
          {:ok, NamedRows.t()} | {:error, term()}
  def remove_relation(instance, relations) when is_list(relations) do
    query(instance, "::remove #{Enum.join(relations, ", ")}")
  end

  def remove_relation(instance, relation), do: query(instance, "::remove #{relation}")

  @doc """
  Renames a stored relation.
  """
  @spec rename_relation(Instance.t(), String.t(), String.t()) ::
          {:ok, NamedRows.t()} | {:error, term()}
  def rename_relation(instance, old_name, new_name) do
    query(instance, "::rename #{old_name} -> #{new_name}")
  end

  @doc """
  Returns the query execution plan for the given query without executing it.

  The query must be wrapped in curly braces by the caller if using raw CozoScript,
  but this function handles that automatically.
  """
  @spec explain(Instance.t(), String.t()) :: {:ok, NamedRows.t()} | {:error, term()}
  def explain(instance, query_str), do: query(instance, "::explain { #{query_str} }")

  @doc """
  Lists currently running queries and their IDs.

  Returns headers: `["id", "started_at"]`
  """
  @spec list_running(Instance.t()) :: {:ok, NamedRows.t()} | {:error, term()}
  def list_running(instance), do: query(instance, "::running")

  @doc """
  Kills a running query by its ID.

  The ID can be obtained from `list_running/1`.
  """
  @spec kill_running(Instance.t(), integer()) :: {:ok, NamedRows.t()} | {:error, term()}
  def kill_running(instance, id), do: query(instance, "::kill #{id}")

  @doc """
  Triggers a compaction of the database.

  Compaction makes the database smaller on disk and faster for read queries.
  """
  @spec compact(Instance.t()) :: {:ok, NamedRows.t()} | {:error, term()}
  def compact(instance), do: query(instance, "::compact")

  @doc """
  Sets the access level for one or more stored relations.

  Access levels control what operations are allowed on the relation:

    * `:normal` — full read/write access (default)
    * `:protected` — cannot be removed with `::remove`
    * `:read_only` — no writes allowed
    * `:hidden` — not visible in `::relations`, no writes allowed

  Accepts a single relation name or a list.

  ## Examples

      Cozonomono.set_access_level(instance, "users", :read_only)
      Cozonomono.set_access_level(instance, ["users", "logs"], :protected)
  """
  @spec set_access_level(Instance.t(), String.t() | [String.t()], atom()) ::
          {:ok, NamedRows.t()} | {:error, term()}
  def set_access_level(instance, relations, level)
      when level in [:normal, :protected, :read_only, :hidden] do
    level_str = Atom.to_string(level)

    rel_str =
      case relations do
        list when is_list(list) -> Enum.join(list, ", ")
        name when is_binary(name) -> name
      end

    query(instance, "::access_level #{level_str} #{rel_str}")
  end

  # --- Change Callbacks ---

  @doc """
  Registers a callback that fires when the given relation is modified.

  The calling process (or the process specified by `pid`) will receive messages
  of the form `{:cozo_callback, op, new_rows, old_rows}` where:

    * `op` is `:put` or `:rm`
    * `new_rows` is a `%NamedRows{}` with the new data
    * `old_rows` is a `%NamedRows{}` with the old data

  Returns `{:ok, callback_id}` where the ID can be used with `unregister_callback/2`.

  ## Options

    * `capacity` - optional channel capacity (default: unbounded). Set to limit
      backpressure if the subscriber is slower than the writer.

  ## Examples

      {:ok, cb_id} = Cozonomono.register_callback(instance, "users")
      Cozonomono.query(instance, "?[id, name] <- [[1, 'Alice']] :put users {id => name}")
      receive do
        {:cozo_callback, :put, new_rows, old_rows} -> handle_change(new_rows, old_rows)
      end
      Cozonomono.unregister_callback(instance, cb_id)
  """
  @spec register_callback(Instance.t(), String.t(), keyword()) ::
          {:ok, non_neg_integer()}
  def register_callback(instance, relation, opts \\ []) do
    pid = Keyword.get(opts, :pid, self())
    capacity = Keyword.get(opts, :capacity)
    {:ok, Native.register_callback(instance, relation, pid, capacity)}
  end

  @doc """
  Unregisters a previously registered callback.

  Returns `true` if the callback was found and removed, `false` if it was
  already unregistered or did not exist.
  """
  @spec unregister_callback(Instance.t(), non_neg_integer()) :: boolean()
  def unregister_callback(instance, id) do
    Native.unregister_callback(instance, id)
  end

  # --- Custom Fixed Rules ---

  @doc """
  Registers a custom fixed rule that can be invoked in CozoScript via `<~`.

  The handler process receives messages of the form:

      {:cozo_fixed_rule, request_id, inputs, options}

  where:
    * `request_id` is an integer identifying this invocation
    * `inputs` is a list of `%NamedRows{}` (the input relations)
    * `options` is a map of option name strings to values

  The handler **must** respond by calling `respond_fixed_rule/3` with the
  result `%NamedRows{}`, otherwise the query will hang.

  ## Options

    * `pid` - the process to receive rule invocations (default: `self()`)

  ## Examples

      {:ok, bridge} = Cozonomono.register_fixed_rule(instance, "MyRule", 2)

      # In the handler process:
      receive do
        {:cozo_fixed_rule, request_id, inputs, options} ->
          result = %NamedRows{headers: ["a", "b"], rows: [[1, 2]]}
          Cozonomono.respond_fixed_rule(bridge, request_id, result)
      end

      # Use in CozoScript:
      Cozonomono.query(instance, "?[a, b] <~ MyRule()")
  """
  @spec register_fixed_rule(Instance.t(), String.t(), pos_integer(), keyword()) ::
          {:ok, FixedRuleBridge.t()} | {:error, term()}
  def register_fixed_rule(instance, name, return_arity, opts \\ []) do
    pid = Keyword.get(opts, :pid, self())
    Native.register_fixed_rule(instance, name, return_arity, pid)
  end

  @doc """
  Responds to a fixed rule invocation with the computed result.

  Must be called by the handler process after receiving a
  `{:cozo_fixed_rule, request_id, inputs, options}` message.
  """
  @spec respond_fixed_rule(FixedRuleBridge.t(), non_neg_integer(), NamedRows.t()) ::
          :ok | {:error, term()}
  def respond_fixed_rule(bridge, request_id, %NamedRows{} = result) do
    case Native.respond_fixed_rule(bridge, request_id, result) do
      {:ok, :ok} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Unregisters a previously registered custom fixed rule.

  Returns `true` if the rule was found and removed, `false` otherwise.
  """
  @spec unregister_fixed_rule(Instance.t(), String.t()) :: {:ok, boolean()} | {:error, term()}
  def unregister_fixed_rule(instance, name) do
    Native.unregister_fixed_rule(instance, name)
  end

  # --- Index Management ---

  @doc """
  Creates a standard index on a stored relation.

  ## Examples

      :ok = Cozonomono.create_index(instance, "users", "users_by_name", ["name"])
  """
  @spec create_index(Instance.t(), String.t(), String.t(), [String.t()]) ::
          {:ok, NamedRows.t()} | {:error, term()}
  def create_index(instance, relation, index_name, columns) when is_list(columns) do
    cols = Enum.join(columns, ", ")
    query(instance, "::index create #{relation}:#{index_name} {#{cols}}")
  end

  @doc """
  Creates an HNSW (vector) index on a stored relation.

  The `opts_string` is the raw CozoScript options body (without outer braces).

  ## Examples

      Cozonomono.create_hnsw_index(instance, "docs", "docs_vec",
        "dim: 128, dtype: F32, fields: [embedding], distance: Cosine")
  """
  @spec create_hnsw_index(Instance.t(), String.t(), String.t(), String.t()) ::
          {:ok, NamedRows.t()} | {:error, term()}
  def create_hnsw_index(instance, relation, index_name, opts_string) do
    query(instance, "::hnsw create #{relation}:#{index_name} {#{opts_string}}")
  end

  @doc """
  Creates a full-text search index on a stored relation.

  The `opts_string` is the raw CozoScript options body (without outer braces).

  ## Examples

      Cozonomono.create_fts_index(instance, "docs", "docs_fts",
        "extractor: content, tokenizer: Simple")
  """
  @spec create_fts_index(Instance.t(), String.t(), String.t(), String.t()) ::
          {:ok, NamedRows.t()} | {:error, term()}
  def create_fts_index(instance, relation, index_name, opts_string) do
    query(instance, "::fts create #{relation}:#{index_name} {#{opts_string}}")
  end

  @doc """
  Creates a MinHash LSH index on a stored relation.

  The `opts_string` is the raw CozoScript options body (without outer braces).

  ## Examples

      Cozonomono.create_lsh_index(instance, "docs", "docs_lsh",
        "extractor: content, tokenizer: Simple, n_gram: 3, n_perm: 200")
  """
  @spec create_lsh_index(Instance.t(), String.t(), String.t(), String.t()) ::
          {:ok, NamedRows.t()} | {:error, term()}
  def create_lsh_index(instance, relation, index_name, opts_string) do
    query(instance, "::lsh create #{relation}:#{index_name} {#{opts_string}}")
  end

  @doc """
  Drops an index from a stored relation.

  Works for standard, HNSW, FTS, and LSH indices.

  ## Examples

      Cozonomono.drop_index(instance, "users", "users_by_name")
  """
  @spec drop_index(Instance.t(), String.t(), String.t()) ::
          {:ok, NamedRows.t()} | {:error, term()}
  def drop_index(instance, relation, index_name) do
    query(instance, "::index drop #{relation}:#{index_name}")
  end

  @default_query_opts [params: nil, immutable?: false]

  @doc """
  Runs a query against the given db instance.

  Params must be passed as a map with string keys.
  """
  @spec query(
          instance :: Instance.t(),
          query :: String.t(),
          opts :: Keyword.t()
        ) :: {:ok, NamedRows.t()} | {:error, term()}
  def query(instance, query, opts \\ []) do
    opts = Keyword.validate!(opts, @default_query_opts)

    if Keyword.equal?(opts, @default_query_opts) do
      Native.run_default(instance, query)
    else
      Native.run_script(instance, query, opts[:params], opts[:immutable?])
    end
  end

  @doc """
  Runs a query and returns a lazy, zero-copy reference to the results.

  Unlike `query/3`, the results stay on the Rust heap and are only copied
  to the BEAM when accessed via `Cozonomono.LazyRows` accessor functions.

  This is ideal for large result sets where you only need a subset of data.

  ## Examples

      {:ok, lazy} = Cozonomono.query_lazy(instance, "?[id, name] := *users{id, name}")
      lazy.row_count  #=> 10000
      {:ok, first_row} = Cozonomono.LazyRows.row_at(lazy, 0)
  """
  @spec query_lazy(
          instance :: Instance.t(),
          query :: String.t(),
          opts :: Keyword.t()
        ) :: {:ok, LazyRows.t()} | {:error, term()}
  def query_lazy(instance, query, opts \\ []) do
    opts = Keyword.validate!(opts, @default_query_opts)

    if Keyword.equal?(opts, @default_query_opts) do
      Native.run_default_lazy(instance, query)
    else
      Native.run_script_lazy(instance, query, opts[:params], opts[:immutable?])
    end
  end

  @doc """
  Runs a query within a multi-statement transaction and returns a lazy result.

  See `query_lazy/3` for details on lazy results.
  """
  @spec tx_query_lazy(Transaction.t(), String.t(), map() | nil) ::
          {:ok, LazyRows.t()} | {:error, term()}
  def tx_query_lazy(tx, query, params \\ nil) do
    params = params || %{}
    Native.tx_run_script_lazy(tx, query, params)
  end
end
