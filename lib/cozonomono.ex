defmodule Cozonomono do
  @moduledoc """
  Documentation for `Cozonomono`.
  """

  alias Cozonomono.Instance
  alias Cozonomono.Native

  @type engine :: :mem | :sqlite | :rocksb
  @type named_rows :: %{
          String.t() => [String.t()],
          String.t() => named_rows(),
          String.t() => [list()]
        }

  @doc """
  Creates a new Cozo database instance.
  """
  @spec new(engine :: engine(), path :: String.t()) :: Instance.t()
  def new(engine \\ :mem, path \\ ""),
    do: engine |> Atom.to_string() |> Native.create_instance(path)

  @default_query_opts [params: nil, immutable?: false]

  @doc """
  Runs a query against the given db instance.

  Params must be passed as a map with string keys.
  """
  @spec query(
          instance :: Instance.t(),
          query :: String.t(),
          opts :: Keyword.t()
        ) :: {:ok, named_rows()} | {:error, term()}
  def query(instance, query, opts \\ []) do
    opts = Keyword.validate!(opts, @default_query_opts)

    if Keyword.equal?(opts, @default_query_opts) do
      Native.run_default(instance, query)
    else
      Native.run_script(instance, query, opts[:params], opts[:immutable?])
    end
  end
end
