#!/usr/bin/env bash
# Regenerates resources/momime.client.graphics/overland/resources-map.txt from
# whatever PNGs are under resources/momime.client.graphics/overland/terrain.
#
# Mirror doesn't ship this index (or the PNGs — they're gitignored, drop your
# own copy from the MOMIME client graphics resources at
# resources/momime.client.graphics/overland/terrain/<plane>/<kind>/*.png).
# Run this after adding/updating those files.
set -euo pipefail
cd "$(dirname "$0")/../resources/momime.client.graphics/overland"
find terrain -type f -name "*.png" | sort > resources-map.txt
echo "Wrote $(wc -l < resources-map.txt) entries to resources-map.txt"
