defmodule Mirror.Engine.Fog do
  @moduledoc """
  Fog-of-war helpers for visible/explored bitsets.
  """

  import Bitwise

  alias Mirror.Engine.{MapOps, Session, World}

  @spec visible_bitset_for_player(term(), term(), World.plane()) :: bitstring()
  def visible_bitset_for_player(session_id, player_id, plane) do
    case Session.query_by_id(session_id, fn state ->
           fetch_visible_from_state(state, player_id, plane)
         end) do
      {:ok, bitset} -> bitset
      {:error, _} -> <<>>
    end
  end

  @spec recompute_visible_delta(World.t(), term(), World.plane(), list(), bitstring() | nil) ::
          {bitstring(), list()}
  def recompute_visible_delta(%World{} = world, _player_id, _plane, sources, prev_bitset) do
    topo = world.topology
    bits = topo.w * topo.h
    prev = normalize_bitset(prev_bitset, bits)

    idx_set =
      Enum.reduce(sources, MapSet.new(), fn {x, y, radius}, acc ->
        MapOps.reduce_coords_in_radius(topo, x, y, radius, acc, fn sx, sy, acc ->
          idx = sy * topo.w + sx
          MapSet.put(acc, idx)
        end)
      end)

    new_bitset =
      Enum.reduce(idx_set, empty_bitset(bits), fn idx, acc ->
        set_bit(acc, idx, 1)
      end)

    {new_bitset, diff_bitsets(prev, new_bitset, bits)}
  end

  @spec apply_exploration(bitstring() | nil, bitstring() | nil) :: bitstring()
  def apply_exploration(explored, visible) do
    bits = max(bit_size(explored || <<>>), bit_size(visible || <<>>))
    explored = normalize_bitset(explored, bits)
    visible = normalize_bitset(visible, bits)

    bor_bitsets(explored, visible)
  end

  defp fetch_visible_from_state(state, player_id, plane) do
    visibility = Map.get(state, :visibility, %Mirror.Engine.Visibility{})

    case visibility.visible do
      %{^player_id => per_player} ->
        Map.get(per_player, plane, <<>>)

      _ ->
        <<>>
    end
  end

  defp empty_bitset(bits) when bits >= 0 do
    <<0::size(bits)>>
  end

  defp normalize_bitset(nil, bits), do: empty_bitset(bits)

  defp normalize_bitset(bitset, bits) when is_bitstring(bitset) and bit_size(bitset) == bits do
    bitset
  end

  defp normalize_bitset(bitset, bits) when is_bitstring(bitset) do
    raise ArgumentError,
          "bitset size mismatch: expected #{bits} bits, got #{bit_size(bitset)} bits"
  end

  defp set_bit(bitset, idx, value) when value in [0, 1] do
    byte_index = div(idx, 8)
    bit_offset = rem(idx, 8)
    <<head::binary-size(byte_index), byte, tail::binary>> = bitset

    mask = 1 <<< bit_offset

    updated =
      if value == 1 do
        byte ||| mask
      else
        byte &&& bnot(mask)
      end

    <<head::binary, updated, tail::binary>>
  end

  defp bor_bitsets(left, right) do
    if byte_size(left) != byte_size(right) do
      raise ArgumentError, "bitset sizes do not match"
    end

    left_bytes = :binary.bin_to_list(left)
    right_bytes = :binary.bin_to_list(right)

    Enum.zip_with(left_bytes, right_bytes, fn l, r -> l ||| r end)
    |> :erlang.list_to_binary()
  end

  defp diff_bitsets(prev, next, bits) do
    if byte_size(prev) != byte_size(next) do
      raise ArgumentError, "bitset sizes do not match"
    end

    byte_count = byte_size(prev)

    Enum.reduce(0..(byte_count - 1), [], fn byte_index, acc ->
      old_byte = :binary.at(prev, byte_index)
      new_byte = :binary.at(next, byte_index)

      if old_byte == new_byte do
        acc
      else
        Enum.reduce(0..7, acc, fn bit_offset, acc ->
          idx = byte_index * 8 + bit_offset

          if idx < bits do
            old_bit = old_byte >>> bit_offset &&& 1
            new_bit = new_byte >>> bit_offset &&& 1

            if old_bit == new_bit do
              acc
            else
              [{idx, old_bit, new_bit} | acc]
            end
          else
            acc
          end
        end)
      end
    end)
    |> Enum.reverse()
  end
end
