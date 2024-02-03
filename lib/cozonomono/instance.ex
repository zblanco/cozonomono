defmodule Cozonomono.Instance do
  @moduledoc """
  A Cozo database instance.
  """

  defstruct resource: nil, engine: :mem, path: ""

  @type t :: %{resource: reference(), engine: engine(), path: String.t() | nil}
  @type engine :: :mem | :sqlite | :rocksdb
end
