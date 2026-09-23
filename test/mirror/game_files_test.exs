defmodule Mirror.GameFilesTest do
  use ExUnit.Case, async: true

  alias Mirror.GameFiles

  # Smallest valid LBX: one 1-byte entry. Not the real game data, so the
  # GOG hash check reports `verified: false`.
  @lbx <<1::little-16, 0xFEAD::little-16, 0::32, 16::little-32, 17::little-32, 0>>
  @required ~w(TERRAIN.LBX FONTS.LBX)

  defp put!(dir, relative, data) do
    path = Path.join(dir, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, data)
    path
  end

  defp statuses(results), do: Map.new(results, &{&1.name, &1.status})

  @tag :tmp_dir
  test "copies only the needed files from a nested install, case-insensitively",
       %{tmp_dir: dir} do
    src = Path.join(dir, "install")
    put!(src, "MOM/terrain.lbx", @lbx)
    put!(src, "MOM/Fonts.Lbx", @lbx)
    put!(src, "MOM/DATA/MAPBACK.LBX", @lbx)
    put!(src, "MOM/SPELLS.LBX", @lbx)
    put!(src, "MOM/save2.gam", "save")
    target = Path.join(dir, "game")

    assert {:ok, results} = GameFiles.import(src, target)

    assert %{
             "TERRAIN.LBX" => :copied,
             "FONTS.LBX" => :copied,
             "MAPBACK.LBX" => :copied,
             "UNITS1.LBX" => :missing,
             "SAVE2.GAM" => :copied
           } = statuses(results)

    assert File.ls!(target) |> Enum.sort() ==
             ~w(FONTS.LBX MAPBACK.LBX SAVE2.GAM TERRAIN.LBX)

    assert Enum.find(results, &(&1.name == "TERRAIN.LBX")).verified == false
  end

  @tag :tmp_dir
  test "reads from a zip, and from a folder holding one", %{tmp_dir: dir} do
    files = for name <- @required, do: {~c"MOM/#{String.downcase(name)}", @lbx}

    File.mkdir_p!(Path.join(dir, "holder"))
    {:ok, zip} = :zip.create(~c"#{dir}/holder/mom.zip", files)

    assert {:ok, _} = GameFiles.import(to_string(zip), Path.join(dir, "a"))
    assert {:ok, _} = GameFiles.import(Path.join(dir, "holder"), Path.join(dir, "b"))
    assert File.read!(Path.join([dir, "b", "TERRAIN.LBX"])) == @lbx
  end

  @tag :tmp_dir
  test "keeps an existing different save unless forced; re-runs are no-ops",
       %{tmp_dir: dir} do
    src = Path.join(dir, "src")
    for name <- @required, do: put!(src, name, @lbx)
    put!(src, "SAVE1.GAM", "original")
    target = Path.join(dir, "game")
    put!(target, "SAVE1.GAM", "edited")

    {:ok, results} = GameFiles.import(src, target)
    assert statuses(results)["SAVE1.GAM"] == :kept_existing
    assert statuses(results)["TERRAIN.LBX"] == :copied
    assert File.read!(Path.join(target, "SAVE1.GAM")) == "edited"

    {:ok, again} = GameFiles.import(src, target)
    assert statuses(again)["TERRAIN.LBX"] == :unchanged

    {:ok, forced} = GameFiles.import(src, target, force: true)
    assert statuses(forced)["SAVE1.GAM"] == :copied
    assert File.read!(Path.join(target, "SAVE1.GAM")) == "original"
  end

  @tag :tmp_dir
  test "saves: false skips saves", %{tmp_dir: dir} do
    src = Path.join(dir, "src")
    for name <- @required, do: put!(src, name, @lbx)
    put!(src, "SAVE3.GAM", "save")

    {:ok, results} = GameFiles.import(src, Path.join(dir, "game"), saves: false)
    refute Map.has_key?(statuses(results), "SAVE3.GAM")
  end

  @tag :tmp_dir
  test "a file that isn't an LBX is skipped, and a missing required file is an error",
       %{tmp_dir: dir} do
    src = Path.join(dir, "src")
    put!(src, "TERRAIN.LBX", "not an lbx at all")
    put!(src, "FONTS.LBX", @lbx)

    assert {:error, {:missing_required, ["TERRAIN.LBX"], results}} =
             GameFiles.import(src, Path.join(dir, "game"))

    assert {:invalid, {:not_an_lbx, _}} = statuses(results)["TERRAIN.LBX"]
  end

  @tag :tmp_dir
  test "a source that doesn't exist is an error", %{tmp_dir: dir} do
    assert {:error, {:not_found, _}} = GameFiles.import(Path.join(dir, "nope"), dir)
  end
end
