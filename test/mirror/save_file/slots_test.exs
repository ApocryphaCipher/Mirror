defmodule Mirror.SaveFileSlotsTest do
  use ExUnit.Case, async: true
  @moduletag :tmp_dir

  test "empty dir returns SAVE1.GAM", %{tmp_dir: dir} do
    assert {:ok, path} = Mirror.SaveFile.next_free_slot(dir)
    assert path == Path.join(dir, "SAVE1.GAM")
  end

  test "SAVE1 and SAVE2 present returns SAVE3.GAM", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "SAVE1.GAM"), "")
    File.write!(Path.join(dir, "SAVE2.GAM"), "")

    assert {:ok, path} = Mirror.SaveFile.next_free_slot(dir)
    assert path == Path.join(dir, "SAVE3.GAM")
  end

  test "lowercase save1.gam counts as taken", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "save1.gam"), "")

    assert {:ok, path} = Mirror.SaveFile.next_free_slot(dir)
    assert path == Path.join(dir, "SAVE2.GAM")
  end

  test "all nine present returns :none", %{tmp_dir: dir} do
    for n <- 1..9 do
      File.write!(Path.join(dir, "SAVE#{n}.GAM"), "")
    end

    assert :none = Mirror.SaveFile.next_free_slot(dir)
  end

  test "nonexistent dir returns SAVE1.GAM", %{tmp_dir: dir} do
    missing = Path.join(dir, "does_not_exist")

    assert {:ok, path} = Mirror.SaveFile.next_free_slot(missing)
    assert path == Path.join(missing, "SAVE1.GAM")
  end

  test "game_loadable_name?/1 is true for valid names" do
    assert Mirror.SaveFile.game_loadable_name?("/x/SAVE9.GAM")
    assert Mirror.SaveFile.game_loadable_name?("save3.gam")
  end

  test "game_loadable_name?/1 is false for invalid names" do
    refute Mirror.SaveFile.game_loadable_name?("SAVE10.GAM")
    refute Mirror.SaveFile.game_loadable_name?("SAVE0.GAM")
    refute Mirror.SaveFile.game_loadable_name?("foo-edited.GAM")
    refute Mirror.SaveFile.game_loadable_name?("SAVE1.GAM.bak")
  end
end
