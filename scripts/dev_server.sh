#!/usr/bin/env bash
# The GOG install (all LBX art + SAVEn.GAM copies); needs at least TERRAIN.LBX +
# FONTS.LBX for terrain, MAPBACK/UNITS1/UNITS2.LBX for overland sprites.
export MIRROR_MOM_PATH="$HOME/.mirror_assets/GOG"
export MIRROR_TERRAIN_OFFSET="0x002698"
export MIRROR_LANDMASS_OFFSET="0x004d98"
export MIRROR_MINERALS_OFFSET="0x013554"
export MIRROR_EXPLORATION_OFFSET="0x014814"
export MIRROR_TERRAIN_FLAGS_OFFSET="0x01cbb8"
cd "$(dirname "$0")/.."
exec mix phx.server
