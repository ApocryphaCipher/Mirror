defmodule Mirror.TerrainLbxTest do
  use ExUnit.Case, async: true

  alias Mirror.TerrainLbx

  describe "decode_pointer/1" do
    test "bank 0: high byte is the record" do
      assert TerrainLbx.decode_pointer(0x0200) == {2, 1}
      assert TerrainLbx.decode_pointer(0x7800) == {0x78, 1}
    end

    test "low 7 bits / 3 select a 128-record bank" do
      assert TerrainLbx.decode_pointer(0x0003) == {128, 1}
      assert TerrainLbx.decode_pointer(0x0B06) == {2 * 128 + 0x0B, 1}
    end

    test "bit 0x80 marks a 4-frame animated tile" do
      assert TerrainLbx.decode_pointer(0x1480) == {0x14, 4}
      assert TerrainLbx.decode_pointer(0x7F83) == {128 + 0x7F, 4}
    end
  end

  describe "check_minimap/1 (STORY-040)" do
    test "a minimap table shorter than both planes is an error, not a later crash" do
      assert TerrainLbx.check_minimap(:binary.copy(<<0>>, 2 * 762)) == :ok

      assert TerrainLbx.check_minimap(:binary.copy(<<0>>, 2 * 762 - 1)) ==
               {:error, :short_minimap}
    end
  end

  describe "record_pixels/2" do
    test "transposes column-major record pixels to row-major" do
      # Record 1 starts at byte 384; pixel byte = x * 18 + y (column-major).
      column_major = for x <- 0..19, y <- 0..17, into: <<>>, do: <<rem(x * 18 + y, 256)>>
      raw = :binary.copy(<<0>>, 384 + 16) <> column_major <> :binary.copy(<<0>>, 8)

      row_major = TerrainLbx.record_pixels(raw, 1)

      assert byte_size(row_major) == 360
      # Row 0 walks x across columns: values 0, 18, 36, ...
      assert :binary.bin_to_list(row_major, 0, 3) == [0, 18, 36]
      # (x=1, y=2) is row-major offset 2*20 + 1 and column-major value 1*18 + 2.
      assert :binary.at(row_major, 2 * 20 + 1) == 20
    end

    test "returns nil for records past the end of the file" do
      assert TerrainLbx.record_pixels(<<0::size(8 * 384)>>, 1) == nil
    end
  end

  describe "with real game files" do
    @mom_path System.get_env("MIRROR_MOM_PATH")
    @has_terrain @mom_path &&
                   match?({:ok, files} when is_list(files), File.ls(@mom_path)) &&
                   Enum.any?(File.ls!(@mom_path), &(String.upcase(&1) == "TERRAIN.LBX"))

    @tag skip: !@has_terrain && "MIRROR_MOM_PATH has no TERRAIN.LBX"
    test "every pointer on both planes resolves to an atlas tile" do
      {:ok, terrain} = TerrainLbx.load(@mom_path)
      payload = TerrainLbx.payload(terrain)

      for plane <- [:arcanus, :myrror] do
        tiles = payload.tiles[plane]
        assert length(tiles) == TerrainLbx.tiles_per_plane()
        assert Enum.all?(tiles, fn [index, frames] -> index >= 0 and frames in [1, 4] end)
      end

      assert byte_size(Base.decode64!(payload.pixels)) == payload.tile_count * 20 * 18
      assert byte_size(Base.decode64!(payload.palette)) == 256 * 4
    end
  end
end
