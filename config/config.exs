# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :mirror,
  generators: [timestamp_type: :utc_datetime],
  terrain_water_values: [0],
  mom_path: nil,
  momime_resources_dir: Path.expand("../resources", __DIR__),
  asset_map_dir: Path.expand("../priv/asset_map", __DIR__),
  tile_cache_dir: Path.expand("../priv/tile_cache", __DIR__)

# Configure the endpoint
config :mirror, MirrorWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MirrorWeb.ErrorHTML, json: MirrorWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Mirror.PubSub,
  live_view: [signing_salt: "bwCmSnKm"]

# Classic save offsets (hard-coded defaults).
config :mirror, Mirror.SaveFile.Blocks,
  terrain: 0x002698,
  landmass: 0x004D98,
  minerals: 0x013554,
  exploration: 0x014814,
  terrain_flags: 0x01CBB8

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  mirror: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  mirror: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
