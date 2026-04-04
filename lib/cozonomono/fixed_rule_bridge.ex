defmodule Cozonomono.FixedRuleBridge do
  @moduledoc """
  A bridge handle for a registered custom fixed rule.

  Created via `Cozonomono.register_fixed_rule/4`. The bridge holds an opaque
  reference to the Rust-side forwarding infrastructure that connects CozoDB
  rule invocations to an Elixir handler process.

  ## Fields

    * `resource` - opaque NIF reference to the Rust bridge
    * `name` - the name of the registered fixed rule
  """

  defstruct resource: nil, name: ""

  @type t :: %__MODULE__{
          resource: reference(),
          name: String.t()
        }
end
