defmodule Mirror.GameFiles do
  @moduledoc """
  Import the game files Mirror needs from the user's own copy of *Master of
  Magic* into Mirror's game directory (`~/.mirror/game` by default).

  The source can be an unpacked install, a `.zip` of one, or a folder
  holding either. Files are found by name, case-insensitively and at any
  depth. Only the files in `manifest/0` (plus `SAVEn.GAM` saves) are copied.
  Each LBX must parse as one, and is checked against the GOG release's
  SHA-256 (a mismatch is a warning, e.g. a CD version; not an error).

  The game files are copyrighted: they come from the user's own purchase and
  never go into the repo or an image.
  """

  alias Mirror.LBX

  # Hashes are of the GOG release's files (Kevin's copy, 2026-09-23).
  @manifest [
    %{
      name: "TERRAIN.LBX",
      required: true,
      used_for: "terrain tiles",
      sha256: "86e3da19cd070bb49e126e2697e95bb64f64c0cbbdb24f185eca3bf99a0fa707"
    },
    %{
      name: "FONTS.LBX",
      required: true,
      used_for: "game palette (entry 2)",
      sha256: "35e61719558943ea8953fa1375abde6e41b9169e86b1e5dbf66c4c8fdf2c9695"
    },
    %{
      name: "MAPBACK.LBX",
      required: false,
      used_for: "overland sprites: cities, plaques, sites, specials, roads",
      sha256: "3ed3fe10519156bdd613ef6300c6b393b8a1a44d87b2bad003c38074e741c5fb"
    },
    %{
      name: "UNITS1.LBX",
      required: false,
      used_for: "unit figures, types 0-119",
      sha256: "9bab1fdb23c81328c46b365bea716f26aee36b2b3a493feedd5790f52fe42adc"
    },
    %{
      name: "UNITS2.LBX",
      required: false,
      used_for: "unit figures, types 120-197",
      sha256: "d94bd85267ffb7fe8fa9eb1cf9753a6eda7e592cf0f27d7574a50b9d8fd72dd8"
    }
  ]

  @save ~r/^SAVE[1-9]\.GAM$/

  @type result :: %{
          name: String.t(),
          status: :copied | :unchanged | :kept_existing | :missing | {:invalid, term()},
          from: String.t() | nil,
          verified: boolean() | nil
        }

  @doc "The files Mirror uses, in the order they matter."
  def manifest, do: @manifest

  @doc """
  Mirror's game directory: `$MIRROR_HOME/game`, where `MIRROR_HOME`
  defaults to `~/.mirror`.
  """
  def default_target do
    System.get_env("MIRROR_HOME", Path.expand("~/.mirror")) |> Path.join("game")
  end

  @doc """
  Copy the needed files from `source` into `target`.

  Options:
    * `:saves` (default `true`): also copy `SAVE1..9.GAM`
    * `:force` (default `false`): overwrite a *different* existing file in
      `target`. Without it, an existing save that differs is kept (it may
      hold edits), and so is a differing LBX.

  Returns `{:ok, results}` when every required file is present afterwards,
  `{:error, {:missing_required, names, results}}` when not, or
  `{:error, reason}` when the source can't be read.
  """
  def import(source, target, opts \\ []) do
    with {:ok, found} <- scan(source),
         :ok <- File.mkdir_p(target) do
      force? = Keyword.get(opts, :force, false)

      lbx_results =
        for %{name: name, sha256: sha} <- @manifest do
          place(name, Map.get(found, name), target, force?, &validate_lbx(&1, sha))
        end

      save_results =
        if Keyword.get(opts, :saves, true) do
          for name <- found |> Map.keys() |> Enum.filter(&Regex.match?(@save, &1)) |> Enum.sort() do
            place(name, Map.fetch!(found, name), target, force?, fn _ -> {:ok, nil} end)
          end
        else
          []
        end

      results = lbx_results ++ save_results

      case missing_required(target) do
        [] -> {:ok, results}
        names -> {:error, {:missing_required, names, results}}
      end
    end
  end

  @doc "Required manifest files not present in `dir`."
  def missing_required(dir) do
    for %{name: name, required: true} <- @manifest,
        not File.exists?(Path.join(dir, name)),
        do: name
  end

  # Finds every wanted file in `source`: a map of NAME => source, where a
  # source is `{:file, path}` or `{:zip, zip_path, entry}`. Loose files win
  # over zip entries; shallower paths win over deeper ones.
  defp scan(source) do
    cond do
      File.dir?(source) -> {:ok, scan_dir(source)}
      zip?(source) -> scan_zip(source)
      File.exists?(source) -> {:error, {:not_a_zip_or_folder, source}}
      true -> {:error, {:not_found, source}}
    end
  end

  defp scan_dir(dir) do
    paths =
      dir
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.sort_by(&{length(Path.split(&1)), &1})

    loose =
      for path <- paths, wanted?(Path.basename(path)), File.regular?(path), reduce: %{} do
        acc -> Map.put_new(acc, upcase(path), {:file, path})
      end

    zipped =
      for path <- paths, zip?(path), reduce: %{} do
        acc ->
          case scan_zip(path) do
            {:ok, found} -> Map.merge(found, acc)
            {:error, _} -> acc
          end
      end

    Map.merge(zipped, loose)
  end

  defp scan_zip(zip) do
    case :zip.list_dir(String.to_charlist(zip)) do
      {:ok, [_comment | entries]} ->
        found =
          entries
          |> Enum.flat_map(fn
            {:zip_file, entry, _info, _comment, _offset, _size} -> [to_string(entry)]
            _ -> []
          end)
          |> Enum.filter(&wanted?(Path.basename(&1)))
          |> Enum.sort_by(&{length(Path.split(&1)), &1})
          |> Enum.reduce(%{}, &Map.put_new(&2, upcase(&1), {:zip, zip, &1}))

        {:ok, found}

      {:error, reason} ->
        {:error, {:bad_zip, zip, reason}}
    end
  end

  defp place(name, nil, target, _force?, _validate) do
    status = if File.exists?(Path.join(target, name)), do: :unchanged, else: :missing
    %{name: name, status: status, from: nil, verified: nil}
  end

  defp place(name, source, target, force?, validate) do
    dest = Path.join(target, name)

    with {:ok, data} <- read(source),
         {:ok, verified} <- validate.(data) do
      status =
        case File.read(dest) do
          {:ok, ^data} ->
            :unchanged

          {:ok, _different} when not force? ->
            :kept_existing

          _ ->
            File.write!(dest, data)
            :copied
        end

      %{name: name, status: status, from: describe(source), verified: verified}
    else
      {:error, reason} ->
        %{name: name, status: {:invalid, reason}, from: describe(source), verified: false}
    end
  end

  defp validate_lbx(data, sha256) do
    case LBX.from_binary(data) do
      {:ok, _lbx} -> {:ok, hash(data) == sha256}
      {:error, reason} -> {:error, {:not_an_lbx, reason}}
    end
  end

  defp read({:file, path}), do: File.read(path)

  defp read({:zip, zip, entry}) do
    case :zip.unzip(String.to_charlist(zip), [:memory, file_list: [String.to_charlist(entry)]]) do
      {:ok, [{_name, data}]} -> {:ok, data}
      {:ok, []} -> {:error, {:not_in_zip, entry}}
      {:error, reason} -> {:error, {:bad_zip, zip, reason}}
    end
  end

  defp describe({:file, path}), do: path
  defp describe({:zip, zip, entry}), do: "#{zip}:#{entry}"

  defp wanted?(basename) do
    name = String.upcase(basename)
    Regex.match?(@save, name) or Enum.any?(@manifest, &(&1.name == name))
  end

  defp zip?(path), do: String.downcase(Path.extname(path)) == ".zip" and File.regular?(path)
  defp upcase(path), do: path |> Path.basename() |> String.upcase()
  defp hash(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
end
