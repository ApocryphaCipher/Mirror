defmodule Mirror.SaveFile.RoundTripTest do
  use ExUnit.Case, async: true

  alias Mirror.SaveFile
  alias Mirror.SaveBlockDiff
  alias Mirror.SaveFile.Blocks

  @mom_path System.get_env("MIRROR_MOM_PATH", "")
  @template_path System.get_env(
                   "MIRROR_TEMPLATE_SAVE",
                   Path.expand("~/.mirror_assets/MAGIC/TEMPLATE.GAM")
                 )

  describe "golden byte-identical round-trip test" do
    for save_name <- ["SAVE1.GAM", "SAVE2.GAM", "SAVE9.GAM"] do
      path = Path.join(@mom_path, save_name)

      @tag skip: !File.exists?(path) && "needs #{save_name}"
      test "round-trips #{save_name} identically" do
        path = unquote(path)
        original = File.read!(path)
        assert {:ok, save} = SaveFile.load(path)
        assert {:ok, ^original} = SaveFile.serialize(save)
      end
    end

    @tag skip: !File.exists?(@template_path) && "needs TEMPLATE.GAM"
    test "round-trips TEMPLATE.GAM identically" do
      original = File.read!(@template_path)
      assert {:ok, save} = SaveFile.load(@template_path)
      assert {:ok, ^original} = SaveFile.serialize(save)
    end
  end

  @moduletag :tmp_dir

  describe "minimal diff test" do
    test "editing one terrain tile modifies exactly two bytes in the expected block", %{
      tmp_dir: tmp_dir
    } do
      original = :binary.copy(<<0>>, 123_300)
      path = Path.join(tmp_dir, "synthetic.gam")
      File.write!(path, original)

      assert {:ok, save} = SaveFile.load(path)

      plane = :arcanus
      x = 5
      y = 5

      width = Blocks.map_width()
      tile_index = y * width + x
      word_offset = tile_index * 2

      terrain_slice = save.planes[plane][:terrain]

      <<before::binary-size(^word_offset), _old_word::binary-size(2), rest::binary>> =
        terrain_slice

      mutated_slice = before <> <<0x01, 0x01>> <> rest

      mutated_save = put_in(save.planes[plane][:terrain], mutated_slice)

      assert {:ok, mutated_binary} = SaveFile.serialize(mutated_save)

      diff = SaveBlockDiff.diff(original, mutated_binary)

      assert Map.keys(diff) == [{:terrain, plane}]

      # plane_slice_offset expects layer and plane index (0 or 1)
      plane_index = if plane == :arcanus, do: 0, else: 1
      assert {:ok, plane_offset} = Blocks.plane_slice_offset(:terrain, plane_index)
      expected_offsets = [plane_offset + word_offset, plane_offset + word_offset + 1]

      assert diff[{:terrain, plane}] == expected_offsets
    end
  end
end
