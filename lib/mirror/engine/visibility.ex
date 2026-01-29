defmodule Mirror.Engine.Visibility do
  @moduledoc """
  Per-player exploration and visibility state.
  """

  defstruct explored: %{},
            visible: %{},
            last_seen: %{}

  @type t :: %__MODULE__{
          explored: %{optional(term()) => bitstring()},
          visible: %{optional(term()) => bitstring()},
          last_seen: %{optional(term()) => map()}
        }
end
