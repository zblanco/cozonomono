defmodule Cozonomono.NamedRows do
  @moduledoc """
  Represents the result of a CozoDB query.

  ## Fields

    * `headers` - list of column name strings
    * `rows` - list of rows, where each row is a list of values
    * `next` - the next `NamedRows` in a multi-statement result chain, or `nil`
  """

  defstruct headers: [], rows: [], next: nil

  @type t :: %__MODULE__{
          headers: [String.t()],
          rows: [[term()]],
          next: t() | nil
        }
end
