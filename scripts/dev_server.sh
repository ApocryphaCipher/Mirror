#!/usr/bin/env bash
# Needs TERRAIN.LBX + FONTS.LBX (from a full install, e.g. GOG) for terrain art.
export MIRROR_MOM_PATH="$HOME/.mirror_assets/MAGIC"
export MIRROR_TERRAIN_OFFSET="0x002698"
export MIRROR_LANDMASS_OFFSET="0x004d98"
export MIRROR_MINERALS_OFFSET="0x013554"
export MIRROR_EXPLORATION_OFFSET="0x014814"
export MIRROR_TERRAIN_FLAGS_OFFSET="0x01cbb8"
cd "$(dirname "$0")/.."
exec mix phx.server
