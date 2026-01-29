defmodule Mirror.Engine.View do
  @moduledoc """
  Player-filtered world queries against session state.
  """

  import Bitwise

  alias Mirror.Engine.{Session, Visibility}

  @type plane :: :arcanus | :myrror

  @spec tile_truth(term(), plane(), non_neg_integer(), non_neg_integer()) :: map()
  def tile_truth(session_id, plane, x, y) do
    case Session.query_by_id(session_id, fn state ->
           Session.tile_truth_from_state(state, plane, x, y)
         end) do
      {:ok, tile} -> tile
      {:error, _} -> %{}
    end
  end

  @spec tile_for_player(term(), term(), plane(), non_neg_integer(), non_neg_integer()) :: map()
  def tile_for_player(session_id, player_id, plane, x, y) do
    result =
      Session.query_by_id(session_id, fn state ->
        world = Map.get(state, :world)
        visibility = Map.get(state, :visibility, %Visibility{})
        tile = Session.tile_truth_from_state(state, plane, x, y)

        if is_nil(world) do
          {:unknown, %{}}
        else
          idx = y * world.topology.w + x
          visible = bitset_has?(visibility.visible, player_id, plane, idx)
          explored = bitset_has?(visibility.explored, player_id, plane, idx)

          cond do
            visible -> {:visible, tile}
            explored -> {:remembered, Map.take(tile, [:terrain_base_u8, :terrain_flags_u8])}
            true -> {:unknown, %{}}
          end
        end
      end)

    case result do
      {:ok, {state, tile}} -> Map.put(tile, :fog_state, state)
      _ -> %{fog_state: :unknown}
    end
  end

  defp bitset_has?(map, player_id, plane, idx) do
    case Map.get(map, player_id) do
      nil ->
        false

      per_player ->
        bitset = Map.get(per_player, plane)

        if is_bitstring(bitset) and bit_size(bitset) > idx do
          get_bit(bitset, idx) == 1
        else
          false
        end
    end
  end

  defp get_bit(bitset, idx) do
    byte_index = div(idx, 8)
    bit_offset = rem(idx, 8)
    <<_::binary-size(byte_index), byte, _::binary>> = bitset
    byte >>> bit_offset &&& 1
  end
end
