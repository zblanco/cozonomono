defmodule Cozonomono.Transaction do
  @moduledoc """
  A multi-statement transaction handle.

  Created via `Cozonomono.multi_transaction/2`. Allows running multiple queries
  atomically — either all committed or all aborted.

  ## Fields

    * `resource` - opaque NIF reference to the Rust `MultiTransaction`
    * `write` - whether this is a write transaction (`true`) or read-only (`false`)
  """

  defstruct resource: nil, write: false

  @type t :: %__MODULE__{
          resource: reference(),
          write: boolean()
        }
end
