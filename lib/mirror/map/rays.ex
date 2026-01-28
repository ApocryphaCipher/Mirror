defmodule Mirror.Map.Rays do
  @moduledoc """
  Ray vision feature extraction for terrain.
  """

  alias Mirror.Map, as: MirrorMap

  @directions [
    {:n, {0, -1}},
    {:ne, {1, -1}},
    {:e, {1, 0}},
    {:se, {1, 1}},
    {:s, {0, 1}},
    {:sw, {-1, 1}},
    {:w, {-1, 0}},
    {:nw, {-1, -1}}
  ]

  def observe_plane(dataset_id, terrain_bin) do
    for y <- 0..(MirrorMap.height() - 1), x <- 0..(MirrorMap.width() - 1) do
      observe_tile(dataset_id, terrain_bin, x, y)
    end

    :ok
  end

  def observe_tile(dataset_id, terrain_bin, x, y) do
    center_value = MirrorMap.get_tile_u16_le(terrain_bin, x, y)
    center_class = MirrorMap.terrain_class(center_value)

    rays = ray_observations(terrain_bin, x, y, center_class)

    Enum.each(rays, fn {dir, hit_class, dist} ->
      Mirror.Stats.bump_ray(dataset_id, center_class, dir, hit_class, dist)
    end)

    pairings(rays)
    |> Enum.each(fn {left, right} ->
      Mirror.Stats.bump_ray_pair(dataset_id, center_class, left, right)
    end)
  end

  def ray_observations(terrain_bin, x, y, center_class \\ nil) do
    center_class =
      center_class || MirrorMap.terrain_class(MirrorMap.get_tile_u16_le(terrain_bin, x, y))

    Enum.map(@directions, fn {dir, {dx, dy}} ->
      {hit_class, dist} = first_hit(terrain_bin, x, y, dx, dy, center_class, 2)
      {dir, hit_class, dist}
    end)
  end

  defp first_hit(_terrain_bin, _x, _y, _dx, _dy, _center_class, 0), do: {:none, 0}

  defp first_hit(terrain_bin, x, y, dx, dy, center_class, remaining) do
    step = 3 - remaining
    nx = MirrorMap.wrap_x(x + dx * step)
    ny = MirrorMap.clamp_y(y + dy * step)

    case ny do
      :off ->
        {:none, step}

      _ ->
        neighbor_class = MirrorMap.terrain_class(MirrorMap.get_tile_u16_le(terrain_bin, nx, ny))

        if neighbor_class == center_class do
          first_hit(terrain_bin, x, y, dx, dy, center_class, remaining - 1)
        else
          {neighbor_class, step}
        end
    end
  end

  defp pairings(rays) do
    by_dir = Map.new(rays, fn {dir, hit, dist} -> {dir, {dir, hit, dist}} end)

    [
      {by_dir[:n], by_dir[:s]},
      {by_dir[:e], by_dir[:w]},
      {by_dir[:ne], by_dir[:sw]},
      {by_dir[:nw], by_dir[:se]}
    ]
    |> Enum.reject(fn {left, right} -> is_nil(left) or is_nil(right) end)
  end
end
