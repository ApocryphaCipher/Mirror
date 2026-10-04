#!/usr/bin/env bash
# Live-RAM play session: the modified DOSBox Staging (webserver on) plus Evi/gama
# checkpoints. See docs/reference/live-ram-map.md.
#   bash scripts/live_session.sh start              # open DOSBox (Kevin runs this)
#   bash scripts/live_session.sh cp "new map 1"     # checkpoint now (memory + screenshot + registers)
#   bash scripts/live_session.sh status             # is the API up, how many checkpoints so far
set -euo pipefail

DOSBOX="$HOME/repo/c++/dosbox-staging/build/debug-macos/Debug/dosbox"
GAMA_DIR="$HOME/repo/python/gama"
export EVI_HOME="$HOME/repo/mom-evi-vault"
API="http://127.0.0.1:8086/api/v1"
LOG_DIR="$HOME/.mirror/dev/DOSbox"

case "${1:-}" in
  start)
    [ -x "$DOSBOX" ] || { echo "No DOSBox build at $DOSBOX (see live-ram-map.md, Build)"; exit 1; }
    mkdir -p "$LOG_DIR"
    # Mounts ~/DOS as C:. Then in DOSBox: cd MAGIC, then magic
    cd "$HOME/DOS"
    exec "$DOSBOX" \
      --set webserver_enabled=true \
      --set webserver_file_log="$LOG_DIR/files-$(date +%Y%m%d-%H%M).jsonl" \
      .
    ;;
  cp)
    [ -n "${2:-}" ] || { echo 'usage: live_session.sh cp "name" [note]'; exit 1; }
    cd "$GAMA_DIR"
    if [ -n "${3:-}" ]; then
      exec uv run gama checkpoint "$2" --note "$3"
    else
      exec uv run gama checkpoint "$2"
    fi
    ;;
  status)
    curl -s -m 3 "$API/cpu/state" >/dev/null && echo "DOSBox API: up" || echo "DOSBox API: down"
    cd "$GAMA_DIR"
    uv run gama sql "SELECT id, name, taken_at FROM checkpoints ORDER BY taken_at DESC LIMIT 10"
    ;;
  *)
    sed -n 2,6p "$0"
    exit 1
    ;;
esac
