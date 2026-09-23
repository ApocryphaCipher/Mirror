defmodule Mirror.LBXTest do
  use ExUnit.Case, async: true

  alias Mirror.LBX
  alias Mirror.LBX.Palette

  # A 2x3, two-frame image:
  #   frame 0 (fresh): col 0 copy-mode run of [5, 6] one row down,
  #                    col 1 RLE run `0xE2, 7` = three 7s (0xE2 - 0xDF)
  #   frame 1 (delta): col 0 empty (kept), col 1 run of [9] two rows down
  # Plus an embedded palette patch: colour 7 := 6-bit (63, 0, 0).
  defp image_entry do
    frame0 = <<1, 0x00, 4, 2, 1, 5, 6, 0x80, 4, 2, 0, 0xE2, 7>>
    frame1 = <<0, 0xFF, 0x00, 3, 1, 2, 9>>
    table_end = 0x12 + 3 * 4
    f0 = table_end
    f1 = f0 + byte_size(frame0)
    f_end = f1 + byte_size(frame1)
    palette_info = f_end
    palette_data = palette_info + 8

    <<2::little-16, 3::little-16, 0::little-16, 2::little-16, 0::little-16, 0::32,
      palette_info::little-16, 0::little-16, f0::little-32, f1::little-32, f_end::little-32,
      frame0::binary, frame1::binary, palette_data::little-16, 7::little-16, 1::little-16,
      0::little-16, 63, 0, 0>>
  end

  defp lbx_binary(entries, names \\ nil) do
    count = length(entries)
    data_start = if names, do: 0x200 + count * 32, else: 8 + (count + 1) * 4

    offsets =
      Enum.scan(entries, data_start, fn entry, acc -> acc + byte_size(entry) end)

    table = for o <- [data_start | offsets], into: <<>>, do: <<o::little-32>>
    header = <<count::little-16, 0xFEAD::little-16, 0::32, table::binary>>

    header =
      if names do
        rows =
          for {name, description} <- names, into: <<>> do
            row = String.pad_trailing(name, 9, <<0>>) <> description
            row <> :binary.copy(<<0>>, 32 - byte_size(row))
          end

        header <> :binary.copy(<<0>>, 0x200 - byte_size(header)) <> rows
      else
        header
      end

    header <> IO.iodata_to_binary(entries)
  end

  defp write!(dir, name, bin) do
    path = Path.join(dir, name)
    File.write!(path, bin)
    path
  end

  describe "container" do
    @tag :tmp_dir
    test "offsets start at byte 8 even when bytes 4-7 are zero", %{tmp_dir: dir} do
      path = write!(dir, "T.LBX", lbx_binary([<<1, 2, 3>>, <<4>>]))
      {:ok, lbx} = LBX.open(path)

      assert {:ok, <<1, 2, 3>>} = LBX.read_entry(lbx, 0)
      assert {:ok, <<4>>} = LBX.read_entry(lbx, 1)
    end

    @tag :tmp_dir
    test "rejects files without the 0xFEAD magic", %{tmp_dir: dir} do
      path = write!(dir, "BAD.LBX", <<1::little-16, 0::16, 0::32, 12::little-32, 12::little-32>>)
      assert {:error, :invalid_header} = LBX.open(path)
    end

    @tag :tmp_dir
    test "names/1 reads the 32-byte rows at 0x200", %{tmp_dir: dir} do
      path =
        write!(dir, "N.LBX", lbx_binary([<<0>>, <<0>>], [{"SITES", "blue"}, {"MAPCITY", ""}]))

      {:ok, lbx} = LBX.open(path)

      assert LBX.names(lbx) == [
               %{name: "SITES", description: "blue"},
               %{name: "MAPCITY", description: ""}
             ]

      assert [%{name: "SITES", description: "blue"} | _] = LBX.entries(lbx)
    end

    @tag :tmp_dir
    test "names/1 gives nils when there is no table", %{tmp_dir: dir} do
      {:ok, lbx} = LBX.open(write!(dir, "S.LBX", lbx_binary([<<0>>, <<0>>])))
      assert LBX.names(lbx) == [nil, nil]
    end
  end

  describe "decode_image/3" do
    setup %{tmp_dir: dir} do
      {:ok, lbx} = LBX.open(write!(dir, "IMG.LBX", lbx_binary([image_entry()])))
      %{lbx: lbx}
    end

    @tag :tmp_dir
    test "decodes column-major RLE frames to row-major indices, deltas on top", %{lbx: lbx} do
      assert [%{type: :image}] = LBX.entries(lbx)
      {:ok, image} = LBX.decode_image(lbx, 0, palette: :grayscale)

      assert {image.width, image.height, image.frame_count} == {2, 3, 2}
      assert [f0, f1] = Enum.map(image.frames, & &1.indices)
      assert f0 == <<0, 7, 5, 7, 6, 7>>
      assert f1 == <<0, 7, 5, 7, 6, 9>>
    end

    @tag :tmp_dir
    test "applies the embedded palette patch over the base palette", %{lbx: lbx} do
      base = Palette.default()
      assert {:ok, palette, :explicit_embedded} = LBX.resolve_palette(lbx, 0, palette: base)
      assert Enum.at(palette, 7) == {255, 0, 0, 255}
      assert Enum.at(palette, 6) == {6, 6, 6, 255}

      {:ok, image} = LBX.decode_image(lbx, 0, palette: base)
      # Pixel (1, 0) is index 7 -> RGBA red.
      assert binary_part(image.rgba, 4, 4) == <<255, 0, 0, 255>>
    end

    @tag :tmp_dir
    test ":auto uses FONTS.LBX entry 2 from the same directory, index 0 transparent",
         %{lbx: lbx, tmp_dir: dir} do
      vga = for i <- 0..255, into: <<>>, do: <<rem(i, 64), 0, 0>>
      write!(dir, "FONTS.LBX", lbx_binary([<<0>>, <<0>>, vga <> <<1, 2, 3>>]))

      assert {:ok, [first | _], :game_embedded} = LBX.resolve_palette(lbx, 0)
      assert first == {0, 0, 0, 0}

      {:ok, image} = LBX.decode_image(lbx, 0)
      assert binary_part(hd(image.frames).rgba, 0, 4) == <<0, 0, 0, 0>>
    end

    @tag :tmp_dir
    test "non-image entries are an error, not noise", %{tmp_dir: dir} do
      {:ok, lbx} = LBX.open(write!(dir, "RAW.LBX", lbx_binary([:binary.copy(<<7>>, 64)])))
      assert [%{type: :binary}] = LBX.entries(lbx)
      assert {:error, :not_an_image} = LBX.decode_image(lbx, 0)
    end
  end

  describe "real GOG files" do
    @mom_path System.get_env("MIRROR_MOM_PATH", "")
    @has_mapback @mom_path != "" and File.exists?(Path.join(@mom_path, "MAPBACK.LBX"))

    @tag skip: !@has_mapback && "MIRROR_MOM_PATH has no MAPBACK.LBX"
    test "MAPBACK.LBX: names line up with entries and every image decodes" do
      {:ok, lbx} = LBX.open(Path.join(@mom_path, "MAPBACK.LBX"))
      names = LBX.names(lbx)

      assert length(names) == 94
      assert Enum.at(names, 14) == %{name: "SITES", description: "blue"}
      assert Enum.at(names, 20) == %{name: "MAPCITY", description: ""}
      assert Enum.at(names, 45) == %{name: "ROADS", description: "no road"}
      assert Enum.at(names, 93) == %{name: "WARPED", description: "warped mask"}

      for %{type: :image, index: i} <- LBX.entries(lbx) do
        assert {:ok, _} = LBX.decode_image(lbx, i), "entry #{i}"
      end

      {:ok, city} = LBX.decode_image(lbx, 20)
      assert {city.width, city.height, city.frame_count} == {32, 30, 5}
      # Corners are transparent; index 0 decodes to alpha 0.
      assert binary_part(hd(city.frames).rgba, 0, 4) == <<0, 0, 0, 0>>
    end
  end
end
