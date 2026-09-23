defmodule Mix.Tasks.Mirror.ImportGame do
  @shortdoc "Copy the game files Mirror needs from your Master of Magic install"

  @moduledoc """
  Copies the game files Mirror needs out of your own copy of *Master of
  Magic* into Mirror's game directory.

      mix mirror.import_game SOURCE [--to DIR] [--no-saves] [--force]

  `SOURCE` is an unpacked install, a `.zip` of one, or a folder holding
  either (e.g. the GOG install folder, or wherever you keep the zip). Only
  the files Mirror uses are copied (`TERRAIN.LBX`, `FONTS.LBX`,
  `MAPBACK.LBX`, `UNITS1.LBX`, `UNITS2.LBX`) plus your `SAVE1..9.GAM`.

  Options:

    * `--to DIR`: destination (default `$MIRROR_HOME/game`, i.e.
      `~/.mirror/game`). Point `MIRROR_MOM_PATH` at it; `scripts/dev_server.sh`
      and `compose.yaml` do.
    * `--no-saves`: don't copy `SAVEn.GAM` files.
    * `--force`: overwrite files in DIR that differ from the source. Without
      it an existing, different file (e.g. an edited save) is kept.

  Exits non-zero when a required file is still missing afterwards.
  """

  use Mix.Task

  alias Mirror.GameFiles

  @switches [to: :string, saves: :boolean, force: :boolean]

  @impl Mix.Task
  def run(args) do
    case OptionParser.parse(args, strict: @switches) do
      {opts, [source], []} ->
        target = Path.expand(opts[:to] || GameFiles.default_target())
        source = Path.expand(source)
        Mix.shell().info("Importing from #{source}\n          into #{target}\n")

        case GameFiles.import(source, target,
               saves: Keyword.get(opts, :saves, true),
               force: Keyword.get(opts, :force, false)
             ) do
          {:ok, results} ->
            report(results)
            Mix.shell().info("\nDone. Use it with: export MIRROR_MOM_PATH=#{target}")

          {:error, {:missing_required, names, results}} ->
            report(results)
            Mix.raise("Required files not found in #{source}: #{Enum.join(names, ", ")}")

          {:error, {:not_found, _}} ->
            Mix.raise("No such file or folder: #{source}")

          {:error, reason} ->
            Mix.raise("Can't read #{source}: #{inspect(reason)}")
        end

      _ ->
        Mix.raise("Usage: mix mirror.import_game SOURCE [--to DIR] [--no-saves] [--force]")
    end
  end

  defp report(results) do
    for result <- results do
      Mix.shell().info("  #{String.pad_trailing(result.name, 12)} #{describe(result)}")
    end
  end

  defp describe(%{status: :copied} = r), do: "copied" <> check(r)
  defp describe(%{status: :unchanged}), do: "already up to date"
  defp describe(%{status: :kept_existing}), do: "differs from source; kept existing (use --force)"
  defp describe(%{status: :missing}), do: "not found"
  defp describe(%{status: {:invalid, reason}}), do: "skipped, not valid: #{inspect(reason)}"

  defp check(%{verified: true}), do: " (matches GOG release)"
  defp check(%{verified: false}), do: " (not the GOG release's version; may still work)"
  defp check(_), do: ""
end
