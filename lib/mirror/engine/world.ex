defmodule Mirror.Engine.World do
  @moduledoc """
  Canonical world state descriptor for a Mirror engine session.
  """

  alias Mirror.Engine.Topology

  @enforce_keys [:topology, :planes, :layers, :meta]
  defstruct topology: nil,
            planes: [:arcanus, :myrror],
            layers: %{},
            meta: %{}

  @type plane :: :arcanus | :myrror
  @type t :: %__MODULE__{
          topology: Topology.t(),
          planes: [plane()],
          layers: %{optional({plane(), atom()}) => term()},
          meta: map()
        }
end
