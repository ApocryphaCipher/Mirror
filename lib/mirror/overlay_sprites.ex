defmodule Mirror.OverlaySprites do
  @moduledoc """
  Overland sprites for the map's overlay layers, sent to the browser as
  palette indices (not RGBA) so the client can recolour banner pixels per
  owner. Entry numbers are from the sprite catalog in
  docs/reference/overland-sprites-and-save-blocks.md.
  """

  alias Mirror.LBX
  alias Mirror.LBX.Palette

  @cities %{walled: 20, unwalled: 21}

  @doc """
  `%{palette: base64 RGBA (index 0 transparent), cities: %{walled: sprite,
  unwalled: sprite}}`, each sprite `%{width, height, frames: [base64
  indices]}`, or `{:error, reason}` when `MAPBACK.LBX` isn't in `dir`.
  """
  def load(dir) when dir in [nil, ""], do: {:error, :no_mom_path}

  def load(dir) do
    with {:ok, name} <- find(dir, "MAPBACK.LBX"),
         {:ok, mapback} <- LBX.open(Path.join(dir, name)),
         {:ok, palette} <- LBX.game_palette(dir),
         {:ok, cities} <- sprites(mapback, @cities) do
      {:ok, %{palette: Base.encode64(Palette.to_binary(palette)), cities: cities}}
    end
  end

  defp sprites(lbx, entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn {key, index}, {:ok, acc} ->
      case LBX.decode_image(lbx, index, palette: :grayscale) do
        {:ok, image} ->
          sprite = %{
            width: image.width,
            height: image.height,
            frames: Enum.map(image.frames, &Base.encode64(&1.indices))
          }

          {:cont, {:ok, Map.put(acc, key, sprite)}}

        {:error, reason} ->
          {:halt, {:error, {:sprite, index, reason}}}
      end
    end)
  end

  defp find(dir, wanted) do
    case Enum.find(LBX.list_files(dir), &(String.upcase(&1) == wanted)) do
      nil -> {:error, {:missing, wanted}}
      name -> {:ok, name}
    end
  end
end
