defmodule Mirror.Engine.Delta do
  @moduledoc """
  Delta payload for incremental world updates.
  """

  defstruct type: nil,
            plane: nil,
            layer: nil,
            changes: [],
            meta: %{}

  @type t :: %__MODULE__{
          type: atom() | nil,
          plane: atom() | nil,
          layer: atom() | nil,
          changes: list(),
          meta: map()
        }
end
