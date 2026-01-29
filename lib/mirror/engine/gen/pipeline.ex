# SPDX-License-Identifier: GPL-2.0-only
# This file is part of Mirror.
# Adapted from MOMIME (Master of Magic - IME) map sources.
# See NOTICE.md for attribution details.

defmodule Mirror.Engine.Gen.Pipeline do
  @moduledoc """
  Deterministic, staged map generation pipeline scaffold.

  MOMIME references:
  - `com.ndg.map.generator.HeightMapGenerator`
  - `com.ndg.map.MapConstants`
  """

  alias Mirror.Engine.{Delta, Rng, Topology, World}
  alias Mirror.Engine.Gen.Heightmap

  @type stage :: :heightmap | :thresholds | :biomes | :rivers | :roads | :specials | :polish

  @default_stages [:heightmap, :thresholds, :biomes, :rivers, :roads, :specials, :polish]

  @spec run(integer(), map()) :: {:ok, World.t(), [Delta.t()]}
  def run(seed, opts \\ %{}) do
    topo = Map.get(opts, :topology, Topology.new())
    stages = Map.get(opts, :stages, @default_stages)

    world = %World{
      topology: topo,
      planes: [:arcanus, :myrror],
      layers: %{},
      meta: %{seed: seed, source: :generated, version: 1}
    }

    rng = Rng.new(seed)

    {world, _rng, deltas} =
      Enum.reduce(stages, {world, rng, []}, fn stage, {world, rng, deltas} ->
        {:ok, world, rng, stage_deltas} = run_stage(stage, world, rng, opts)
        {world, rng, deltas ++ stage_deltas}
      end)

    {:ok, world, deltas}
  end

  @spec run_stage(stage(), World.t(), Rng.t(), map()) :: {:ok, World.t(), Rng.t(), [Delta.t()]}
  def run_stage(:heightmap, %World{} = world, %Rng{} = rng, opts) do
    {heightmap, rng} = Heightmap.generate(world.topology, rng, Map.get(opts, :heightmap, []))

    {layers, deltas} =
      Enum.reduce(world.planes, {world.layers, []}, fn plane, {layers, deltas} ->
        key = {plane, :height_u16}
        layers = Map.put(layers, key, heightmap)

        delta = %Delta{
          type: :gen_stage,
          plane: plane,
          layer: :height_u16,
          changes: [],
          meta: %{stage: :heightmap}
        }

        {layers, [delta | deltas]}
      end)

    {:ok, %{world | layers: layers}, rng, Enum.reverse(deltas)}
  end

  def run_stage(_stage, %World{} = world, %Rng{} = rng, _opts) do
    {:ok, world, rng, []}
  end
end
