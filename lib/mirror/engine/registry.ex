defmodule Mirror.Engine.Registry do
  @moduledoc """
  Registry for engine sessions.
  """

  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end
end
