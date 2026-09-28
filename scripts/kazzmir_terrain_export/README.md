# kazzmir terrain table export

One-off tool that dumps [kazzmir/master-of-magic](https://github.com/kazzmir/master-of-magic)'s
terrain tile table (`game/magic/terrain`: the neighbour-compatibility
rules the original game's `TERRTYPE.LBX` encodes) to JSON, so it can be
ported into `Mirror.TerrainType` (`lib/mirror/terrain_type.ex`) with
attribution, instead of reverse-engineering the binary LBX file from
scratch. BSD-3 licensed; read at commit `e824e98`.

Not part of Mirror's build — this is a dev-time reference tool, the same
spirit as `scripts/mom_map_render.py`. `main.go` here is not a runnable
Go module on its own (it depends on kazzmir's full package tree,
including graphics dependencies unrelated to this export); to regenerate
`priv/kazzmir_terrain_table.json`:

```bash
git clone --depth 50 https://github.com/kazzmir/master-of-magic.git /tmp/kazzmir-mom
mkdir -p /tmp/kazzmir-mom/cmd/terrainexport
cp main.go /tmp/kazzmir-mom/cmd/terrainexport/
cd /tmp/kazzmir-mom
go build ./cmd/terrainexport/
./terrainexport > /path/to/Mirror/priv/kazzmir_terrain_table.json
```

Output: a JSON array, one entry per Arcanus tile index `0..0x2F9` (761),
each `{index, terrain_type, compatibilities}` where `compatibilities` is
keyed by direction (`Center`, `North`, `NorthEast`, `East`, `SouthEast`,
`South`, `SouthWest`, `West`, `NorthWest`) and holds `{type: "any_of" |
"none_of", terrains: [...]}`. Myrror tiles reuse this same table, offset
by `0x2FA` (`Mirror.TerrainType` handles that).
