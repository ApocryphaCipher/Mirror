defmodule Mirror.SaveFile.Cities do
  @moduledoc """
  The cities block of a classic save: up to 100 records of 114 bytes at
  `0x8aac`, the live count a u16 at `0x9e0`.

  Record layout, per momedit's `City.cs` and the Save Game Format wiki
  (see docs/reference/momedit-source/), checked against SAVE1.GAM's 27
  cities (readable names, coordinates on the map, owners 0–5):

    * `+0`  name, NUL-terminated (14 bytes)
    * `+14` race
    * `+15` x, `+16` y (tiles), `+17` plane (0 Arcanus, 1 Myrror)
    * `+18` owner: wizard record 0–4, or 5 for the neutral cities
    * `+19` size class (*guess*: 0 hamlet … 4 capital; it tracks
      population in SAVE1: pop 2–3 → 0, 4–6 → 1, 8–9 → 2)
    * `+20` population (thousands)
  """

  @offset 0x8AAC
  @record 114
  @max 100
  @count_offset 0x9E0

  @type city :: %{
          index: non_neg_integer(),
          name: String.t(),
          race: non_neg_integer(),
          x: non_neg_integer(),
          y: non_neg_integer(),
          plane: :arcanus | :myrror,
          owner: non_neg_integer(),
          size: non_neg_integer(),
          population: non_neg_integer()
        }

  @doc "The live cities in a save's raw bytes."
  @spec parse(binary()) :: {:ok, [city()]} | {:error, term()}
  def parse(<<_::binary-size(@count_offset), count::little-16, _::binary>> = raw)
      when count <= @max and byte_size(raw) >= @offset + count * @record do
    cities =
      for index <- 0..(count - 1)//1,
          city = record(binary_part(raw, @offset + index * @record, @record), index),
          do: city

    {:ok, cities}
  end

  def parse(_raw), do: {:error, :no_cities_block}

  defp record(
         <<name::binary-size(14), race, x, y, plane, owner, size, population, _::binary>>,
         index
       )
       when x < 60 and y < 40 and plane in [0, 1] do
    %{
      index: index,
      name: name |> :binary.split(<<0>>) |> hd() |> String.trim(),
      race: race,
      x: x,
      y: y,
      plane: if(plane == 0, do: :arcanus, else: :myrror),
      owner: owner,
      size: size,
      population: population
    }
  end

  defp record(_bytes, _index), do: nil
end
