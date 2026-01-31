defmodule Mirror.MomimePngIndex do
  @moduledoc false

  @cache_key {__MODULE__, :assets}

  def load_assets do
    case :persistent_term.get(@cache_key, nil) do
      nil ->
        case build_assets() do
          {:ok, assets} ->
            :persistent_term.put(@cache_key, assets)
            {:ok, assets}

          :error ->
            :error
        end

      assets ->
        {:ok, assets}
    end
  end

  def reset do
    :persistent_term.erase(@cache_key)
    :ok
  end

  def resources_available? do
    File.exists?(resources_map_path())
  end

  def resources_map_path do
    Path.join([resources_dir(), "momime.client.graphics", "overland", "resources-map.txt"])
  end

  def resources_dir do
    Mirror.Paths.momime_resources_dir()
  end

  def base_url do
    "/momime/momime.client.graphics/overland"
  end

  defp build_assets do
    with true <- resources_available?(),
         {:ok, {index, frames}} <- build_index() do
      {:ok,
       %{
         backend: :momime_png,
         images: %{},
         terrain_groups: %{},
         overlay_groups: %{},
         momime: %{
           base_url: base_url(),
           index: index,
           frames: frames
         }
       }}
    else
      _ -> :error
    end
  end

  defp build_index do
    case File.read(resources_map_path()) do
      {:ok, content} ->
        {index, frames} =
          content
          |> String.split(~r/\R/, trim: true)
          |> Enum.reduce({%{}, %{}}, fn line, {index_acc, frames_acc} ->
            case parse_line(line) do
              nil ->
                {index_acc, frames_acc}

              {plane, kind, mask, frame, path} ->
                index_key = key_for(plane, kind, mask, frame)
                base_key = base_key_for(plane, kind, mask)

                frames_acc =
                  Map.update(frames_acc, base_key, MapSet.new([frame]), fn set ->
                    MapSet.put(set, frame)
                  end)

                {Map.put(index_acc, index_key, path), frames_acc}
            end
          end)

        frames =
          Enum.into(frames, %{}, fn {key, set} ->
            tokens = set |> MapSet.to_list() |> Enum.map(&String.downcase/1)
            {key, normalize_frames(tokens)}
          end)

        {:ok, {index, frames}}

      _ ->
        :error
    end
  end

  defp parse_line(line) do
    normalized = line |> String.trim() |> String.replace("\\", "/")

    case String.split(normalized, "/") do
      ["terrain", plane, terrain_kind, filename] ->
        with {:ok, {mask, frame}} <- parse_filename(filename) do
          kind = normalize_kind(terrain_kind)
          {String.downcase(plane), kind, mask, frame, normalized}
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_filename(filename) do
    base = Path.rootname(filename)

    cond do
      match = Regex.run(~r/^([0-2]{8})-frame(\d+)$/i, base) ->
        [_, mask, frame] = match
        {:ok, {mask, frame}}

      match = Regex.run(~r/^([0-2]{8})([a-z])$/i, base) ->
        [_, mask, frame] = match
        {:ok, {mask, String.downcase(frame)}}

      match = Regex.run(~r/^([0-2]{8})$/i, base) ->
        [_, mask] = match
        {:ok, {mask, "0"}}

      true ->
        :error
    end
  end

  defp normalize_kind(kind) do
    case String.downcase(kind) do
      "grasslands" -> "grass"
      "hills" -> "hill"
      "mountains" -> "mountain"
      other -> other
    end
  end

  defp normalize_frames(tokens) do
    filtered = Enum.reject(tokens, &(&1 == "0"))
    tokens = if filtered == [], do: ["0"], else: filtered

    {numeric, rest} = Enum.split_with(tokens, &Regex.match?(~r/^\d+$/, &1))
    {letters, other} = Enum.split_with(rest, &Regex.match?(~r/^[a-z]$/, &1))

    numeric_sorted = Enum.sort_by(numeric, &String.to_integer/1)
    letters_sorted = Enum.sort(letters)
    other_sorted = Enum.sort(other)

    numeric_sorted ++ letters_sorted ++ other_sorted
  end

  defp key_for(plane, kind, mask, frame) do
    Enum.join([plane, kind, mask, frame], "|")
  end

  defp base_key_for(plane, kind, mask) do
    Enum.join([plane, kind, mask], "|")
  end
end
