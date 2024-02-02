defmodule Cozonomono do
  @moduledoc """
  Documentation for `Cozonomono`.
  """

  alias Cozonomono.Instance
  alias Cozonomono.Native

  @type engine :: :mem | :sqlite | :rocksb

  @doc """
  Creates a new Cozo database instance.
  """
  @spec new(engine :: engine(), path :: String.t()) :: Instance.t()
  def new(engine \\ :mem, path \\ ""),
    do: engine |> Atom.to_string() |> Native.create_instance(path)

  @spec simple_query(instance :: Instance.t(), query :: String.t()) ::
          {:ok, [map()]} | {:error, term()}
  def simple_query(instance, query), do: Native.run_default(instance, query)
end
