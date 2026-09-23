#!/usr/bin/env bash
# Game files come from your own copy of Master of Magic, imported once with
#   mix mirror.import_game <your install folder or zip>
# which copies what Mirror needs (and your saves) into ~/.mirror/game.
# Set MIRROR_MOM_PATH to use a different folder.
export MIRROR_MOM_PATH="${MIRROR_MOM_PATH:-$HOME/.mirror/game}"
export MIRROR_TERRAIN_OFFSET="0x002698"
export MIRROR_LANDMASS_OFFSET="0x004d98"
export MIRROR_MINERALS_OFFSET="0x013554"
export MIRROR_EXPLORATION_OFFSET="0x014814"
export MIRROR_TERRAIN_FLAGS_OFFSET="0x01cbb8"
cd "$(dirname "$0")/.."
exec mix phx.server
