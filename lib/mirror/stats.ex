defmodule Mirror.Stats do
  @moduledoc """
  ETS accumulator with DETS persistence for map research data.
  """

  use GenServer

  @flush_interval_ms 15_000
  @table __MODULE__.ETS
  @dets_table __MODULE__.DETS

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def dataset_id_from_path(path) do
    case File.stat(path) do
      {:ok, stat} ->
        fingerprint =
          "#{stat.size}-#{stat.mtime |> NaiveDateTime.from_erl!() |> NaiveDateTime.to_iso8601()}"

        {:ok, {:mom_classic, fingerprint}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def ensure_dataset(dataset_id) do
    GenServer.call(__MODULE__, {:ensure_dataset, dataset_id})
  end

  def histogram(dataset_id, layer, scope) do
    key = {:hist, dataset_id, layer, scope}

    case :ets.lookup(@table, key) do
      [{^key, hist}] -> hist
      [] -> empty_hist()
    end
  end

  def set_histogram(dataset_id, layer, scope, hist) when is_list(hist) do
    GenServer.call(__MODULE__, {:set_histogram, dataset_id, layer, scope, hist})
  end

  def value_name(dataset_id, layer, value) do
    key = {:name, dataset_id, layer, :value, value}

    case :ets.lookup(@table, key) do
      [{^key, name}] -> name
      [] -> nil
    end
  end

  def bit_name(dataset_id, layer, bit_index) do
    key = {:name, dataset_id, layer, :bit, bit_index}

    case :ets.lookup(@table, key) do
      [{^key, name}] -> name
      [] -> nil
    end
  end

  def set_value_name(dataset_id, layer, value, name) do
    GenServer.call(__MODULE__, {:set_name, {:name, dataset_id, layer, :value, value}, name})
  end

  def set_bit_name(dataset_id, layer, bit_index, name) do
    GenServer.call(__MODULE__, {:set_name, {:name, dataset_id, layer, :bit, bit_index}, name})
  end

  def bump_hist(dataset_id, layer, scope, value, delta) do
    GenServer.cast(__MODULE__, {:bump_hist, dataset_id, layer, scope, value, delta})
  end

  def bump_ray(dataset_id, center_class, dir, hit_class, dist) do
    GenServer.cast(__MODULE__, {:bump_ray, dataset_id, center_class, dir, hit_class, dist})
  end

  def bump_ray_pair(dataset_id, center_class, left, right) do
    GenServer.cast(__MODULE__, {:bump_ray_pair, dataset_id, center_class, left, right})
  end

  def export(dataset_id) do
    GenServer.call(__MODULE__, {:export, dataset_id})
  end

  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  @impl true
  def init(state) do
    ets =
      :ets.new(@table, [
        :set,
        :named_table,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])

    dets_path = Application.app_dir(:mirror, "priv/mirror_stats.dets")
    {:ok, dets} = :dets.open_file(@dets_table, file: to_charlist(dets_path))

    load_dets_into_ets(ets, dets)
    :timer.send_interval(@flush_interval_ms, :flush)

    {:ok, Map.merge(state, %{ets: ets, dets: dets})}
  end

  @impl true
  def handle_call({:ensure_dataset, dataset_id}, _from, state) do
    key = {:meta, dataset_id}

    now = DateTime.utc_now() |> DateTime.to_unix()

    case :ets.lookup(@table, key) do
      [] ->
        :ets.insert(@table, {key, %{schema_v: 1, created_at: now, updated_at: now}})

      [{^key, meta}] ->
        :ets.insert(@table, {key, %{meta | updated_at: now}})
    end

    {:reply, :ok, state}
  end

  def handle_call({:set_name, key, name}, _from, state) do
    trimmed = String.trim(name || "")
    :ets.insert(@table, {key, trimmed})
    {:reply, :ok, state}
  end

  def handle_call({:set_histogram, dataset_id, layer, scope, hist}, _from, state) do
    key = {:hist, dataset_id, layer, scope}
    :ets.insert(@table, {key, hist})
    {:reply, :ok, state}
  end

  def handle_call(:flush, _from, state) do
    flush_ets_to_dets(state)
    {:reply, :ok, state}
  end

  def handle_call({:export, dataset_id}, _from, state) do
    data =
      :ets.tab2list(@table)
      |> Enum.filter(fn {key, _value} ->
        match?({:meta, ^dataset_id}, key) ||
          match?({:name, ^dataset_id, _, _, _}, key) ||
          match?({:hist, ^dataset_id, _, _}, key) ||
          match?({:ray, ^dataset_id, _, _, _, _}, key) ||
          match?({:ray_pair, ^dataset_id, _, _, _}, key)
      end)
      |> Enum.into(%{}, fn {key, value} -> {format_key(key), value} end)

    {:reply,
     %{
       schema_v: 1,
       dataset_id: dataset_id,
       exported_at: DateTime.utc_now() |> DateTime.to_unix(),
       data: data
     }, state}
  end

  @impl true
  def handle_cast({:bump_hist, dataset_id, layer, scope, value, delta}, state) do
    key = {:hist, dataset_id, layer, scope}
    update_hist(key, value, delta)
    {:noreply, state}
  end

  def handle_cast({:bump_ray, dataset_id, center_class, dir, hit_class, dist}, state) do
    key = {:ray, dataset_id, center_class, dir, hit_class, dist}
    bump_counter(key, 1)
    {:noreply, state}
  end

  def handle_cast({:bump_ray_pair, dataset_id, center_class, left, right}, state) do
    key = {:ray_pair, dataset_id, center_class, left, right}
    bump_counter(key, 1)
    {:noreply, state}
  end

  @impl true
  def handle_info(:flush, state) do
    flush_ets_to_dets(state)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{dets: dets}) do
    :dets.close(dets)
    :ok
  end

  defp update_hist(key, value, delta) when value in 0..255 do
    hist =
      case :ets.lookup(@table, key) do
        [{^key, existing}] -> existing
        [] -> empty_hist()
      end

    new_hist =
      List.update_at(hist, value, fn current ->
        max(current + delta, 0)
      end)

    :ets.insert(@table, {key, new_hist})
  end

  defp bump_counter(key, delta) do
    case :ets.lookup(@table, key) do
      [{^key, count}] -> :ets.insert(@table, {key, count + delta})
      [] -> :ets.insert(@table, {key, delta})
    end
  end

  defp empty_hist do
    List.duplicate(0, 256)
  end

  defp flush_ets_to_dets(%{dets: dets}) do
    :ets.tab2list(@table)
    |> Enum.each(fn entry -> :dets.insert(dets, entry) end)

    :dets.sync(dets)
  end

  defp load_dets_into_ets(ets, dets) do
    :dets.foldl(
      fn entry, _acc ->
        :ets.insert(ets, entry)
        :ok
      end,
      :ok,
      dets
    )
  end

  defp format_key(key), do: key
end
