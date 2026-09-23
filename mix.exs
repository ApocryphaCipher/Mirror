defmodule Mirror.MixProject do
  use Mix.Project

  def project do
    [
      app: :mirror,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Mirror.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.3"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  # Tailwind's standalone macOS binary ships with a broken ad-hoc signature
  # (verified identical to the official release), which macOS 27 enforces:
  # the process is SIGKILLed with "Code Signature Invalid". Re-sign it
  # ad-hoc after install. Still broken upstream as of tailwindcss v4.3.3 and
  # the tailwind hex package v0.5.1.
  defp resign_tailwind(_args) do
    Mix.Task.run("loadpaths")
    path = Tailwind.bin_path()

    with {:unix, :darwin} <- :os.type(),
         true <- File.exists?(path),
         {_, status} when status != 0 <-
           System.cmd("codesign", ["--verify", "--strict", path], stderr_to_stdout: true) do
      Mix.shell().info("Re-signing #{path} (upstream signature is invalid)")
      {_, 0} = System.cmd("codesign", ["--force", "--sign", "-", path], stderr_to_stdout: true)
    end

    :ok
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": [
        "tailwind.install --if-missing",
        &resign_tailwind/1,
        "esbuild.install --if-missing"
      ],
      "assets.build": ["compile", &resign_tailwind/1, "tailwind mirror", "esbuild mirror"],
      "assets.deploy": [
        &resign_tailwind/1,
        "tailwind mirror --minify",
        "esbuild mirror --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
