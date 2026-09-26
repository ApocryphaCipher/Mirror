defmodule Mirror.StatsTest do
  use ExUnit.Case, async: true

  alias Mirror.Stats

  describe "format_key/1 (STORY-040)" do
    test "tuple keys become colon-joined strings, nested tuples included" do
      assert Stats.format_key({:hist, {:mom_classic, "a"}, :terrain, 5}) ==
               "hist:mom_classic:a:terrain:5"
    end

    test "formatted keys can be encoded as JSON" do
      assert {:ok, _} = Jason.encode(%{Stats.format_key({:meta, {:mom_classic, "x"}}) => 1})
    end
  end

  describe "ray statistics reversibility (STORY-039)" do
    test "edit, undo, and redo match fresh computations from the plane" do
      dataset_id = {:test, "ray_drift_#{System.unique_integer([:positive])}"}
      fresh_dataset_id = {:test, "ray_fresh_#{System.unique_integer([:positive])}"}

      ocean_plane = :binary.copy(<<0::little-16>>, Mirror.Map.width() * Mirror.Map.height())
      {edited_plane, 0} = Mirror.Map.put_tile_u16_le(ocean_plane, 5, 5, 10)

      # 1. Observe initial plane
      Mirror.Map.Rays.observe_plane(dataset_id, ocean_plane)
      initial_data = ray_data(dataset_id)

      # 2. Simulate edit at (5, 5): subtract old ray observations, add new ray observations
      coords =
        for dy <- -2..2, dx <- -2..2 do
          nx = Mirror.Map.wrap_x(5 + dx)
          ny = Mirror.Map.clamp_y(5 + dy)
          {nx, ny}
        end
        |> Enum.reject(fn {_nx, ny} -> ny == :off end)
        |> Enum.uniq()

      Enum.each(coords, fn {cx, cy} ->
        Mirror.Map.Rays.observe_tile(dataset_id, ocean_plane, cx, cy, -1)
        Mirror.Map.Rays.observe_tile(dataset_id, edited_plane, cx, cy, 1)
      end)

      # Fresh computation from edited plane
      Mirror.Map.Rays.observe_plane(fresh_dataset_id, edited_plane)
      fresh_edited_data = ray_data(fresh_dataset_id)

      edited_data = ray_data(dataset_id)
      assert edited_data == fresh_edited_data
      assert edited_data != initial_data

      # 3. Simulate undo: subtract edited observations, add ocean observations
      Enum.each(coords, fn {cx, cy} ->
        Mirror.Map.Rays.observe_tile(dataset_id, edited_plane, cx, cy, -1)
        Mirror.Map.Rays.observe_tile(dataset_id, ocean_plane, cx, cy, 1)
      end)

      undone_data = ray_data(dataset_id)
      assert undone_data == initial_data

      # 4. Simulate redo: subtract ocean observations, add edited observations
      Enum.each(coords, fn {cx, cy} ->
        Mirror.Map.Rays.observe_tile(dataset_id, ocean_plane, cx, cy, -1)
        Mirror.Map.Rays.observe_tile(dataset_id, edited_plane, cx, cy, 1)
      end)

      redone_data = ray_data(dataset_id)
      assert redone_data == fresh_edited_data
    end
  end

  defp ray_data(dataset_id) do
    prefix = Stats.format_key(dataset_id)

    Stats.export(dataset_id).data
    |> Enum.filter(fn {k, _v} ->
      String.starts_with?(k, "ray:") or String.starts_with?(k, "ray_pair:")
    end)
    |> Map.new(fn {k, v} -> {String.replace(k, prefix, "ID"), v} end)
  end
end
