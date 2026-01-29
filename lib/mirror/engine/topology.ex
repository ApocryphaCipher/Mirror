# SPDX-License-Identifier: GPL-2.0-only
# This file is part of Mirror.
# Adapted from MOMIME (Master of Magic - IME) map sources.
# See NOTICE.md for attribution details.

defmodule Mirror.Engine.Topology do
  @moduledoc """
  Map topology helpers (bounds, wrapping, and neighbor traversal).

  MOMIME references:
  - `com.ndg.map.CoordinateSystemUtilsImpl`
  - `com.ndg.map.SquareMapDirection`
  """

  @type t :: %__MODULE__{
          w: pos_integer(),
          h: pos_integer(),
          wrap_x: boolean(),
          wrap_y: boolean()
        }

  defstruct w: 60, h: 40, wrap_x: true, wrap_y: false

  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    w = Keyword.get(opts, :w, 60)
    h = Keyword.get(opts, :h, 40)
    wrap_x = Keyword.get(opts, :wrap_x, true)
    wrap_y = Keyword.get(opts, :wrap_y, false)

    %__MODULE__{w: w, h: h, wrap_x: wrap_x, wrap_y: wrap_y}
  end

  @spec in_bounds?(t(), integer(), integer()) :: boolean
  def in_bounds?(%__MODULE__{} = topo, x, y) do
    x >= 0 and x < topo.w and y >= 0 and y < topo.h
  end

  @spec norm_x(t(), integer()) :: non_neg_integer()
  def norm_x(%__MODULE__{} = topo, x) do
    if topo.wrap_x do
      Integer.mod(x, topo.w)
    else
      if x < 0 or x >= topo.w do
        raise ArgumentError, "x out of bounds for non-wrapping topology"
      end

      x
    end
  end

  @spec norm_y(t(), integer()) :: {:ok, non_neg_integer()} | :oob
  def norm_y(%__MODULE__{} = topo, y) do
    cond do
      topo.wrap_y ->
        {:ok, Integer.mod(y, topo.h)}

      y < 0 or y >= topo.h ->
        :oob

      true ->
        {:ok, y}
    end
  end

  @spec neighbor(t(), integer(), integer(), 0..7) ::
          {:ok, {non_neg_integer(), non_neg_integer()}} | :oob
  def neighbor(%__MODULE__{} = topo, x, y, dir) when dir in 0..7 do
    {dx, dy} = dir_delta(dir)
    nx = x + dx
    ny = y + dy
    nx = if topo.wrap_x, do: Integer.mod(nx, topo.w), else: nx
    ny = if topo.wrap_y, do: Integer.mod(ny, topo.h), else: ny

    if in_bounds?(topo, nx, ny) do
      {:ok, {nx, ny}}
    else
      :oob
    end
  end

  @spec dir_delta(0..7) :: {integer(), integer()}
  def dir_delta(dir) when dir in 0..7 do
    case dir do
      0 -> {0, -1}
      1 -> {1, -1}
      2 -> {1, 0}
      3 -> {1, 1}
      4 -> {0, 1}
      5 -> {-1, 1}
      6 -> {-1, 0}
      7 -> {-1, -1}
    end
  end
end
