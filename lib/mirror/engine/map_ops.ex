# SPDX-License-Identifier: GPL-2.0-only
# This file is part of Mirror.
# Adapted from MOMIME (Master of Magic - IME) map sources.
# See NOTICE.md for attribution details.

defmodule Mirror.Engine.MapOps do
  @moduledoc """
  Operations that iterate or select coordinates against a map topology.

  MOMIME references:
  - `com.ndg.map.areas.operations.MapAreaOperations2DImpl`
  - `com.ndg.map.areas.operations.ProcessRadialMapCoordinates`
  - `com.ndg.map.CoordinateSystemUtilsImpl`
  """

  alias Mirror.Engine.Topology

  @dirs [
    {0, -1},
    {1, -1},
    {1, 0},
    {1, 1},
    {0, 1},
    {-1, 1},
    {-1, 0},
    {-1, -1}
  ]

  @spec each_coord(Topology.t(), (non_neg_integer(), non_neg_integer() -> any())) :: :ok
  def each_coord(%Topology{} = topo, fun) when is_function(fun, 2) do
    for y <- 0..(topo.h - 1), x <- 0..(topo.w - 1) do
      fun.(x, y)
    end

    :ok
  end

  @spec each_coord_in_radius(
          Topology.t(),
          integer(),
          integer(),
          integer(),
          (non_neg_integer(), non_neg_integer() -> any())
        ) :: :ok
  def each_coord_in_radius(%Topology{} = _topo, _cx, _cy, radius, _fun) when radius < 0 do
    :ok
  end

  def each_coord_in_radius(%Topology{} = topo, cx, cy, radius, fun)
      when is_function(fun, 2) and is_integer(radius) do
    total = topo.w * topo.h

    {keep_going, remaining} =
      if Topology.in_bounds?(topo, cx, cy) do
        {continue?(fun.(cx, cy)), total - 1}
      else
        {true, total}
      end

    if keep_going do
      {_coords, _remaining, _keep} = traverse_rings(topo, {cx, cy}, radius, remaining, true, fun)
    end

    :ok
  end

  @spec random_coord_matching(
          Mirror.Engine.Rng.t(),
          Topology.t(),
          area_ref :: term(),
          (integer(), non_neg_integer(), non_neg_integer() -> boolean())
        ) :: {{non_neg_integer(), non_neg_integer()} | nil, Mirror.Engine.Rng.t()}
  def random_coord_matching(rng, %Topology{} = topo, area_ref, predicate)
      when is_function(predicate, 3) do
    {w, h} = Mirror.Engine.MapArea.dims(area_ref)

    if w != topo.w or h != topo.h do
      raise ArgumentError, "area dimensions do not match topology"
    end

    {picked, _count, rng} =
      Enum.reduce(0..(topo.h - 1), {nil, 0, rng}, fn y, {picked, count, rng} ->
        Enum.reduce(0..(topo.w - 1), {picked, count, rng}, fn x, {picked, count, rng} ->
          value = Mirror.Engine.MapArea.get(area_ref, x, y)

          if predicate.(value, x, y) do
            count = count + 1
            {choice, rng} = Mirror.Engine.Rng.uniform(rng, count)

            if choice == 0 do
              {{x, y}, count, rng}
            else
              {picked, count, rng}
            end
          else
            {picked, count, rng}
          end
        end)
      end)

    {picked, rng}
  end

  @spec reduce_coords_in_radius(
          Topology.t(),
          integer(),
          integer(),
          integer(),
          any(),
          (non_neg_integer(), non_neg_integer(), any() -> any())
        ) :: any()
  def reduce_coords_in_radius(%Topology{} = _topo, _cx, _cy, radius, acc, _fun) when radius < 0 do
    acc
  end

  def reduce_coords_in_radius(%Topology{} = topo, cx, cy, radius, acc, fun)
      when is_integer(radius) and is_function(fun, 3) do
    total = topo.w * topo.h

    {remaining, acc} =
      if Topology.in_bounds?(topo, cx, cy) do
        {total - 1, fun.(cx, cy, acc)}
      else
        {total, acc}
      end

    {_coords, _remaining, acc} =
      traverse_rings_reduce(topo, {cx, cy}, radius, remaining, acc, fun)

    acc
  end

  defp traverse_rings(_topo, coords, radius, remaining, keep_going, _fun)
       when radius <= 0 or remaining <= 0 or keep_going == false do
    {coords, remaining, keep_going}
  end

  defp traverse_rings(%Topology{} = topo, coords, radius, remaining, keep_going, fun) do
    Enum.reduce_while(1..radius, {coords, remaining, keep_going}, fn ring,
                                                                     {coords, remaining, keep} ->
      if remaining <= 0 or keep == false do
        {:halt, {coords, remaining, keep}}
      else
        {coords, _in_bounds?} = step_coord(topo, coords, 5)
        {coords, remaining, keep} = walk_sides(topo, coords, ring, remaining, keep, fun)
        {:cont, {coords, remaining, keep}}
      end
    end)
  end

  defp traverse_rings_reduce(_topo, coords, radius, remaining, acc, _fun)
       when radius <= 0 or remaining <= 0 do
    {coords, remaining, acc}
  end

  defp traverse_rings_reduce(%Topology{} = topo, coords, radius, remaining, acc, fun) do
    Enum.reduce_while(1..radius, {coords, remaining, acc}, fn ring, {coords, remaining, acc} ->
      if remaining <= 0 do
        {:halt, {coords, remaining, acc}}
      else
        {coords, _in_bounds?} = step_coord(topo, coords, 5)
        {coords, remaining, acc} = walk_sides_reduce(topo, coords, ring, remaining, acc, fun)
        {:cont, {coords, remaining, acc}}
      end
    end)
  end

  defp walk_sides(topo, coords, ring, remaining, keep, fun) do
    Enum.reduce_while([0, 2, 4, 6], {coords, remaining, keep}, fn dir,
                                                                  {coords, remaining, keep} ->
      if remaining <= 0 or keep == false do
        {:halt, {coords, remaining, keep}}
      else
        {coords, remaining, keep} = walk_steps(topo, coords, dir, ring * 2, remaining, keep, fun)
        {:cont, {coords, remaining, keep}}
      end
    end)
  end

  defp walk_sides_reduce(topo, coords, ring, remaining, acc, fun) do
    Enum.reduce_while([0, 2, 4, 6], {coords, remaining, acc}, fn dir, {coords, remaining, acc} ->
      if remaining <= 0 do
        {:halt, {coords, remaining, acc}}
      else
        {coords, remaining, acc} =
          walk_steps_reduce(topo, coords, dir, ring * 2, remaining, acc, fun)

        {:cont, {coords, remaining, acc}}
      end
    end)
  end

  defp walk_steps(_topo, coords, _dir, steps, remaining, keep, _fun)
       when steps <= 0 or remaining <= 0 or keep == false do
    {coords, remaining, keep}
  end

  defp walk_steps(%Topology{} = topo, coords, dir, steps, remaining, keep, fun) do
    {coords, in_bounds?} = step_coord(topo, coords, dir)

    {remaining, keep} =
      if in_bounds? do
        {remaining - 1, continue?(fun.(elem(coords, 0), elem(coords, 1)))}
      else
        {remaining, keep}
      end

    walk_steps(topo, coords, dir, steps - 1, remaining, keep, fun)
  end

  defp walk_steps_reduce(_topo, coords, _dir, steps, remaining, acc, _fun)
       when steps <= 0 or remaining <= 0 do
    {coords, remaining, acc}
  end

  defp walk_steps_reduce(%Topology{} = topo, coords, dir, steps, remaining, acc, fun) do
    {coords, in_bounds?} = step_coord(topo, coords, dir)

    {remaining, acc} =
      if in_bounds? do
        {remaining - 1, fun.(elem(coords, 0), elem(coords, 1), acc)}
      else
        {remaining, acc}
      end

    walk_steps_reduce(topo, coords, dir, steps - 1, remaining, acc, fun)
  end

  defp step_coord(%Topology{} = topo, {x, y}, dir) do
    {dx, dy} = Enum.at(@dirs, dir)
    nx = x + dx
    ny = y + dy

    nx = if topo.wrap_x, do: Integer.mod(nx, topo.w), else: nx
    ny = if topo.wrap_y, do: Integer.mod(ny, topo.h), else: ny

    {{nx, ny}, Topology.in_bounds?(topo, nx, ny)}
  end

  defp continue?(result) do
    result != false and result != :halt
  end
end
