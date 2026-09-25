defmodule Mirror.SaveFileWriteTest do
  use ExUnit.Case, async: true

  # STORY-038: Save as must never overwrite the loaded save.
  @moduletag :tmp_dir

  defp make_save(tmp_dir) do
    path = Path.join(tmp_dir, "original.sav")
    File.write!(path, :binary.copy(<<0>>, 123_300))
    {:ok, save} = Mirror.SaveFile.load(path)
    save
  end

  test "nil target returns :no_destination and leaves loaded file unchanged", %{tmp_dir: tmp_dir} do
    save = make_save(tmp_dir)
    original = File.read!(save.path)

    assert {:error, :no_destination} = Mirror.SaveFile.write(save, nil)
    assert File.read!(save.path) == original
  end

  test "empty-string target returns :no_destination and leaves loaded file unchanged", %{
    tmp_dir: tmp_dir
  } do
    save = make_save(tmp_dir)
    original = File.read!(save.path)

    assert {:error, :no_destination} = Mirror.SaveFile.write(save, "")
    assert File.read!(save.path) == original
  end

  test "target equal to loaded path returns :would_overwrite_original", %{tmp_dir: tmp_dir} do
    save = make_save(tmp_dir)

    assert {:error, :would_overwrite_original} = Mirror.SaveFile.write(save, save.path)
  end

  test "symlink pointing to loaded path returns :would_overwrite_original", %{tmp_dir: tmp_dir} do
    save = make_save(tmp_dir)
    link = Path.join(tmp_dir, "link.sav")
    File.ln_s(save.path, link)

    assert {:error, :would_overwrite_original} = Mirror.SaveFile.write(save, link)
  end

  test "writing to a new file succeeds and content matches serialize/1", %{tmp_dir: tmp_dir} do
    save = make_save(tmp_dir)
    target = Path.join(tmp_dir, "new.sav")
    {:ok, serialized} = Mirror.SaveFile.serialize(save)

    assert {:ok, ^target} = Mirror.SaveFile.write(save, target)
    assert File.read!(target) == serialized
  end

  test "writing over an existing different file backs up its original bytes", %{tmp_dir: tmp_dir} do
    save = make_save(tmp_dir)
    target = Path.join(tmp_dir, "existing.sav")
    original_bytes = :binary.copy(<<1>>, 500)
    File.write!(target, original_bytes)

    assert {:ok, ^target} = Mirror.SaveFile.write(save, target)
    assert File.read!(target <> ".bak") == original_bytes
  end

  test "no *.tmp-* files remain after a successful write", %{tmp_dir: tmp_dir} do
    save = make_save(tmp_dir)
    target = Path.join(tmp_dir, "output.sav")

    assert {:ok, _} = Mirror.SaveFile.write(save, target)

    tmp_files =
      tmp_dir
      |> File.ls!()
      |> Enum.filter(&String.contains?(&1, ".tmp-"))

    assert tmp_files == []
  end
end
