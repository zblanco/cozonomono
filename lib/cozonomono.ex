defmodule Cozonomono do
  @moduledoc """
  Documentation for `Cozonomono`.
  """

  alias Cozonomono.Instance
  alias Cozonomono.NamedRows
  alias Cozonomono.Native

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
