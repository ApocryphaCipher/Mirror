Mirror includes concepts adapted from MOMIME (Master of Magic - IME) map code.

MOMIME source references (non-exhaustive):
- momime-map/src/main/java/com/ndg/map/CoordinateSystemUtilsImpl.java
- momime-map/src/main/java/com/ndg/map/SquareMapDirection.java
- momime-map/src/main/java/com/ndg/map/areas/storage/MapArea.java
- momime-map/src/main/java/com/ndg/map/areas/storage/MapArea2DArrayListImpl.java
- momime-map/src/main/java/com/ndg/map/areas/operations/MapAreaOperations2DImpl.java
- momime-map/src/main/java/com/ndg/map/areas/operations/ProcessRadialMapCoordinates.java
- momime-map/src/main/java/com/ndg/map/generator/HeightMapGenerator.java
- momime-map/src/main/java/com/ndg/map/generator/HeightMapGeneratorImpl.java
- Client/src/main/java/momime/client/calculations/TileSetBitmaskGeneratorImpl.java
- Common/src/main/java/momime/common/database/SmoothingSystemEx.java
- Common/src/main/java/momime/common/database/SmoothedTileTypeEx.java

Copies of the above (and the map coordinate library) are kept for reference
under `docs/reference/momime-source/`. MOMIME's canonical repos are hosted on
SourceForge, not GitHub: `git clone https://git.code.sf.net/p/momime/momime`
and `git clone https://git.code.sf.net/p/momime/map`.

See module headers for GPLv2 license notices and per-module attribution.

## kazzmir/master-of-magic (terrain tile table)

`Mirror.TerrainType` (`lib/mirror/terrain_type.ex`) ports the terrain
neighbour-compatibility table and resolve algorithm from
[kazzmir/master-of-magic](https://github.com/kazzmir/master-of-magic)
(`game/magic/terrain/terrain.go` and `game/magic/terrain/map.go`, read at
commit `e824e98`), a Go remake of the game. `priv/kazzmir_terrain_table.json`
is exported directly from that project's own code
(`scripts/kazzmir_terrain_export/`), not hand-transcribed.

BSD 3-Clause License

Copyright (c) 2025, Jon Rafkind
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
