defmodule Mirror.Engine.Session do
  @moduledoc """
  Per-session authoritative world state process.
  """

  use GenServer

  import Bitwise

  alias Mirror.Engine.{Delta, Rng, Topology, Visibility, World}
  alias Mirror.SaveFile
  alias Mirror.SaveFile.Blocks

  @layer_map %{
    terrain: {:terrain_u16, :u16},
    terrain_flags: {:terrain_flags_u8, :u8},
    minerals: {:minerals_u8, :u8},
    exploration: {:exploration_u8, :u8},
    landmass: {:landmass_u8, :u8}
  }

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    opts = Keyword.put_new(opts, :session_id, generate_session_id())
    session_id = Keyword.fetch!(opts, :session_id)

    GenServer.start_link(__MODULE__, opts, name: via(session_id))
  end

  @spec load_save(pid(), String.t()) :: {:ok, term()} | {:error, term()}
  def load_save(pid, path) do
    GenServer.call(pid, {:load_save, path})
  end

  @spec apply_delta(pid(), Delta.t()) :: :ok
  def apply_delta(pid, %Delta{} = delta) do
    GenServer.cast(pid, {:apply_delta, delta})
  end

  @spec query(pid(), (map() -> any())) :: any()
  def query(pid, fun) when is_function(fun, 1) do
    GenServer.call(pid, {:query, fun})
  end

  @spec query_by_id(term(), (map() -> any())) :: {:ok, any()} | {:error, :not_found}
  def query_by_id(session_id, fun) when is_function(fun, 1) do
    case whereis(session_id) do
      nil -> {:error, :not_found}
      pid -> {:ok, query(pid, fun)}
    end
  end

  @spec whereis(term()) :: pid() | nil
  def whereis(session_id) do
    case Registry.lookup(Mirror.Engine.Registry, session_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    seed = Keyword.get(opts, :seed, System.unique_integer([:positive]))
    rng = Rng.new(seed)

    {:ok,
     %{
       session_id: session_id,
       rng: rng,
       map_table: nil,
       layer_types: %{},
       world: nil,
       visibility: %Visibility{},
       deltas: [],
       save: nil
     }}
  end

  @impl true
  def handle_call({:load_save, path}, _from, state) do
    case SaveFile.load(path) do
      {:ok, save} ->
        topo =
          Topology.new(w: Blocks.map_width(), h: Blocks.map_height(), wrap_x: true, wrap_y: false)

        map_table =
          :ets.new(:mirror_map, [
            :set,
            :protected,
            read_concurrency: true,
            write_concurrency: true
          ])

        layer_types =
          Enum.reduce(@layer_map, %{}, fn {_source, {layer, type}}, acc ->
            Map.put(acc, layer, type)
          end)

        layers =
          Enum.reduce(save.planes, %{}, fn {plane, plane_layers}, acc ->
            Enum.reduce(@layer_map, acc, fn {source_layer, {engine_layer, _type}}, acc ->
              bin = Map.fetch!(plane_layers, source_layer)
              key = {plane, engine_layer}
              :ets.insert(map_table, {key, bin})
              Map.put(acc, key, {:ets, map_table, key})
            end)
          end)

        rng = Map.fetch!(state, :rng)

        world = %World{
          topology: topo,
          planes: [:arcanus, :myrror],
          layers: layers,
          meta: %{seed: rng.seed, source: :save, version: 1}
        }

        session_id = Map.fetch!(state, :session_id)

        {:reply, {:ok, session_id},
         %{
           state
           | map_table: map_table,
             layer_types: layer_types,
             world: world,
             save: save
         }}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:query, fun}, _from, state) do
    result = fun.(state)
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:apply_delta, %Delta{} = delta}, state) do
    {state, delta} =
      case delta.type do
        :tile_set -> apply_tile_set_delta(state, delta)
        :vis_update -> apply_visibility_delta(state, delta)
        _ -> {state, delta}
      end

    deltas = Map.get(state, :deltas, [])
    {:noreply, %{state | deltas: [delta | deltas]}}
  end

  @spec tile_truth_from_state(map(), World.plane(), non_neg_integer(), non_neg_integer()) :: map()
  def tile_truth_from_state(state, plane, x, y) do
    case state do
      %{world: %World{} = world, map_table: map_table} when is_reference(map_table) ->
        topo = world.topology

        if Topology.in_bounds?(topo, x, y) do
          layer_types = Map.get(state, :layer_types, %{})

          Enum.reduce(layer_types, %{}, fn {layer, type}, acc ->
            case :ets.lookup(map_table, {plane, layer}) do
              [{_key, bin}] ->
                value = read_value(type, bin, x, y, topo)
                Map.put(acc, layer, value)

              [] ->
                acc
            end
          end)
          |> maybe_add_terrain_derivatives()
        else
          %{}
        end

      _ ->
        %{}
    end
  end

  defp apply_tile_set_delta(state, %Delta{} = delta) do
    with %{map_table: map_table, world: %World{} = world} <- state,
         true <- is_reference(map_table),
         {:ok, type} <- Map.fetch(Map.get(state, :layer_types, %{}), delta.layer),
         [{_key, bin}] <- :ets.lookup(map_table, {delta.plane, delta.layer}) do
      {updated, changes} = apply_changes(type, bin, delta.changes, world.topology)
      :ets.insert(map_table, {{delta.plane, delta.layer}, updated})
      {%{state | map_table: map_table}, %{delta | changes: changes}}
    else
      _ -> {state, delta}
    end
  end

  defp apply_visibility_delta(state, %Delta{} = delta) do
    player_id = Map.get(delta.meta, :player_id)
    plane = delta.plane

    if is_nil(player_id) or is_nil(plane) do
      {state, delta}
    else
      visibility = Map.get(state, :visibility, %Visibility{})
      world = Map.get(state, :world)
      topo = if world, do: world.topology, else: nil

      bits =
        if topo do
          topo.w * topo.h
        else
          0
        end

      current = get_visible_bitset(visibility, player_id, plane, bits)

      updated =
        Enum.reduce(delta.changes, current, fn change, acc ->
          {idx, _old, new_val} = normalize_vis_change(change)
          set_bit(acc, idx, new_val)
        end)

      visibility = put_visible_bitset(visibility, player_id, plane, updated)

      {%{state | visibility: visibility}, delta}
    end
  end

  defp get_visible_bitset(%Visibility{} = visibility, player_id, plane, bits) do
    case Map.get(visibility.visible, player_id) do
      nil -> empty_bitset(bits)
      per_player -> Map.get(per_player, plane, empty_bitset(bits))
    end
  end

  defp put_visible_bitset(%Visibility{} = visibility, player_id, plane, bitset) do
    per_player = Map.get(visibility.visible, player_id, %{})
    updated = Map.put(per_player, plane, bitset)
    %{visibility | visible: Map.put(visibility.visible, player_id, updated)}
  end

  defp empty_bitset(bits) when bits >= 0, do: <<0::size(bits)>>

  defp normalize_vis_change({idx, old, new}) when is_integer(idx), do: {idx, old, new}
  defp normalize_vis_change({idx, new}) when is_integer(idx), do: {idx, nil, new}

  defp apply_changes(:u8, bin, changes, %Topology{} = topo) do
    Enum.reduce(changes, {bin, []}, fn change, {acc, updates} ->
      {x, y, new} = normalize_change(change, topo)
      index = y * topo.w + x
      <<head::binary-size(index), old::unsigned-integer-size(8), tail::binary>> = acc
      updated = <<head::binary, new::unsigned-integer-size(8), tail::binary>>
      {updated, [{x, y, old, new} | updates]}
    end)
    |> finalize_updates()
  end

  defp apply_changes(:u16, bin, changes, %Topology{} = topo) do
    Enum.reduce(changes, {bin, []}, fn change, {acc, updates} ->
      {x, y, new} = normalize_change(change, topo)
      index = (y * topo.w + x) * 2

      <<head::binary-size(index), old::little-unsigned-integer-size(16), tail::binary>> = acc
      updated = <<head::binary, new::little-unsigned-integer-size(16), tail::binary>>
      {updated, [{x, y, old, new} | updates]}
    end)
    |> finalize_updates()
  end

  defp finalize_updates({bin, updates}) do
    {bin, Enum.reverse(updates)}
  end

  defp normalize_change({x, y, new}, _topo), do: {x, y, new}
  defp normalize_change({x, y, _old, new}, _topo), do: {x, y, new}

  defp normalize_change({idx, new}, %Topology{} = topo) when is_integer(idx) do
    x = rem(idx, topo.w)
    y = div(idx, topo.w)
    {x, y, new}
  end

  defp read_value(:u8, bin, x, y, %Topology{} = topo) do
    index = y * topo.w + x
    <<_::binary-size(index), value::unsigned-integer-size(8), _::binary>> = bin
    value
  end

  defp read_value(:u16, bin, x, y, %Topology{} = topo) do
    index = (y * topo.w + x) * 2
    <<_::binary-size(index), value::little-unsigned-integer-size(16), _::binary>> = bin
    value
  end

  defp maybe_add_terrain_derivatives(map) do
    case Map.fetch(map, :terrain_u16) do
      {:ok, value} when is_integer(value) ->
        base = value &&& 0xFF
        embedded = value >>> 8 &&& 0xFF

        map
        |> Map.put(:terrain_base_u8, base)
        |> Map.put(:terrain_embedded_special_u8, embedded)

      _ ->
        map
    end
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

  defp via(session_id), do: {:via, Registry, {Mirror.Engine.Registry, session_id}}

  defp generate_session_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end
end
