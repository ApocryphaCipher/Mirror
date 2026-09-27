#!/usr/bin/env bash
# Game files come from your own copy of Master of Magic, imported once with
#   mix mirror.import_game <your install folder or zip>
# which copies what Mirror needs (and your saves) into ~/.mirror/game.
# Set MIRROR_MOM_PATH to use a different folder.
export MIRROR_MOM_PATH="${MIRROR_MOM_PATH:-$HOME/.mirror/game}"
cd "$(dirname "$0")/.."
exec mix phx.server
