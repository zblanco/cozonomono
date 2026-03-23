defmodule Cozonomono do
  @moduledoc """
  Documentation for `Cozonomono`.
  """

  alias Cozonomono.Instance
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
end
