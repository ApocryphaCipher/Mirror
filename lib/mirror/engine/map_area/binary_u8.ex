# SPDX-License-Identifier: GPL-2.0-only
# This file is part of Mirror.
# Adapted from MOMIME (Master of Magic - IME) map sources.
# See NOTICE.md for attribution details.

defmodule Mirror.Engine.MapArea.BinaryU8 do
  @moduledoc """
  Binary-backed u8 map layer storage.

  MOMIME references:
  - `com.ndg.map.areas.storage.MapArea2DArrayListImpl`
  """

  @behaviour Mirror.Engine.MapArea

  @enforce_keys [:data, :w, :h]
  defstruct data: <<>>, w: 0, h: 0

  @type t :: %__MODULE__{data: binary(), w: pos_integer(), h: pos_integer()}

  @spec new(pos_integer(), pos_integer(), non_neg_integer()) :: t()
  def new(w, h, default \\ 0) when w > 0 and h > 0 do
    data = :binary.copy(<<default::unsigned-integer-size(8)>>, w * h)
    %__MODULE__{data: data, w: w, h: h}
  end

  @spec from_binary(binary(), pos_integer(), pos_integer()) :: t()
  def from_binary(data, w, h) when w > 0 and h > 0 do
    expected = w * h

    if byte_size(data) != expected do
      raise ArgumentError, "binary size mismatch for u8 layer"
    end

    %__MODULE__{data: data, w: w, h: h}
  end

  @spec to_binary(t()) :: binary()
  def to_binary(%__MODULE__{} = ref), do: ref.data

  @impl true
  def get(%__MODULE__{} = ref, x, y) when x >= 0 and y >= 0 and x < ref.w and y < ref.h do
    index = y * ref.w + x
    <<_::binary-size(index), value::unsigned-integer-size(8), _::binary>> = ref.data
    value
  end

  @impl true
  def put(%__MODULE__{} = ref, x, y, value) when x >= 0 and y >= 0 and x < ref.w and y < ref.h do
    index = y * ref.w + x
    <<head::binary-size(index), _::unsigned-integer-size(8), tail::binary>> = ref.data
    %{ref | data: <<head::binary, value::unsigned-integer-size(8), tail::binary>>}
  end

  @impl true
  def dims(%__MODULE__{} = ref), do: {ref.w, ref.h}
end
