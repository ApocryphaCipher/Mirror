#!/usr/bin/env bash
# Run `mix test` with the same game-file env as scripts/dev_server.sh, so the
# tests that need real LBX/save files (tagged to skip otherwise) run too.
#   bash scripts/test_game.sh                 # whole suite
#   bash scripts/test_game.sh test/mirror_web # a path, plus any mix test args
set -euo pipefail
cd "$(dirname "$0")/.."
eval "$(grep '^export ' scripts/dev_server.sh)"
exec mix test "$@"
