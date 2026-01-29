# SPDX-License-Identifier: GPL-2.0-only
# This file is part of Mirror.
# Adapted from MOMIME (Master of Magic - IME) map sources.
# See NOTICE.md for attribution details.

defmodule Mirror.Engine.Gen.Heightmap do
  @moduledoc """
  Deterministic heightmap generator scaffold.

  MOMIME references:
  - `com.ndg.map.generator.HeightMapGenerator`
  - `com.ndg.map.generator.HeightMapGeneratorImpl`
  """

  alias Mirror.Engine.{Rng, Topology}

  @spec generate(Topology.t(), Rng.t(), Keyword.t()) :: {binary(), Rng.t()}
  def generate(%Topology{} = topo, %Rng{} = rng, opts \\ []) do
    max_height = Keyword.get(opts, :max_height, 255)
    count = topo.w * topo.h

    {values, rng} =
      Enum.map_reduce(1..count, rng, fn _step, rng ->
        {value, rng} = Rng.uniform(rng, max_height + 1)
        {value, rng}
      end)

    bin =
      Enum.reduce(values, <<>>, fn value, acc ->
        <<acc::binary, value::little-unsigned-integer-size(16)>>
      end)

    {bin, rng}
  end

  @spec zero_base(binary()) :: binary()
  def zero_base(bin) do
    values = values_from_bin(bin)
    min = Enum.min(values, fn -> 0 end)

    Enum.reduce(values, <<>>, fn value, acc ->
      adjusted = value - min
      <<acc::binary, adjusted::little-unsigned-integer-size(16)>>
    end)
  end

  @spec count_tiles_at_each_height(binary()) :: map()
  def count_tiles_at_each_height(bin) do
    values_from_bin(bin)
    |> Enum.reduce(%{}, fn value, acc ->
      Map.update(acc, value, 1, &(&1 + 1))
    end)
  end

  @spec count_tiles_above_threshold(binary(), non_neg_integer()) :: non_neg_integer()
  def count_tiles_above_threshold(bin, threshold) do
    Enum.count(values_from_bin(bin), fn value -> value >= threshold end)
  end

  @spec count_tiles_below_threshold(binary(), non_neg_integer()) :: non_neg_integer()
  def count_tiles_below_threshold(bin, threshold) do
    Enum.count(values_from_bin(bin), fn value -> value <= threshold end)
  end

  @spec find_height_with_specified_tile_count_above(binary(), non_neg_integer()) ::
          non_neg_integer()
  def find_height_with_specified_tile_count_above(bin, desired_tile_count) do
    counts = count_tiles_at_each_height(bin)

    counts
    |> Map.keys()
    |> Enum.sort(:desc)
    |> Enum.reduce_while(0, fn height, acc ->
      acc = acc + Map.fetch!(counts, height)

      if acc >= desired_tile_count do
        {:halt, height}
      else
        {:cont, acc}
      end
    end)
    |> normalize_height_result()
  end

  @spec find_height_with_specified_tile_count_below(binary(), non_neg_integer()) ::
          non_neg_integer()
  def find_height_with_specified_tile_count_below(bin, desired_tile_count) do
    counts = count_tiles_at_each_height(bin)

    counts
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reduce_while(0, fn height, acc ->
      acc = acc + Map.fetch!(counts, height)

      if acc >= desired_tile_count do
        {:halt, height}
      else
        {:cont, acc}
      end
    end)
    |> normalize_height_result()
  end

  defp values_from_bin(bin) do
    for <<value::little-unsigned-integer-size(16) <- bin>> do
      value
    end
  end

  defp normalize_height_result(result) when is_integer(result), do: result
  defp normalize_height_result(_), do: 0
end
