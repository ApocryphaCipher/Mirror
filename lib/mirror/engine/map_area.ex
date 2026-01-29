# SPDX-License-Identifier: GPL-2.0-only
# This file is part of Mirror.
# Adapted from MOMIME (Master of Magic - IME) map sources.
# See NOTICE.md for attribution details.

defmodule Mirror.Engine.MapArea do
  @moduledoc """
  Storage interface for 2D map layers.

  MOMIME references:
  - `com.ndg.map.areas.storage.MapArea`
  - `com.ndg.map.areas.storage.MapArea2D`
  """

  @callback get(ref :: term(), x :: non_neg_integer(), y :: non_neg_integer()) :: integer()
  @callback put(ref :: term(), x :: non_neg_integer(), y :: non_neg_integer(), value :: integer()) ::
              term()
  @callback dims(ref :: term()) :: {pos_integer(), pos_integer()}

  @spec get(term(), non_neg_integer(), non_neg_integer()) :: integer()
  def get(ref, x, y) do
    ref.__struct__.get(ref, x, y)
  end

  @spec put(term(), non_neg_integer(), non_neg_integer(), integer()) :: term()
  def put(ref, x, y, value) do
    ref.__struct__.put(ref, x, y, value)
  end

  @spec dims(term()) :: {pos_integer(), pos_integer()}
  def dims(ref) do
    ref.__struct__.dims(ref)
  end
end
