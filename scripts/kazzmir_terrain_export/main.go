// terrainexport dumps kazzmir/master-of-magic's terrain tile table
// (game/magic/terrain: the neighbour-compatibility rules the original
// game's TERRTYPE.LBX encodes) to JSON, for porting into Mirror
// (github.com/ApocryphaCipher/Mirror), with attribution, at
// docs/reference/classic-terrain-format.md.
//
// Source: https://github.com/kazzmir/master-of-magic, commit e824e98,
// BSD-3 licensed.
package main

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/kazzmir/master-of-magic/game/magic/terrain"
)

type compatibility struct {
	Type     string   `json:"type"` // "any_of" | "none_of"
	Terrains []string `json:"terrains"`
}

type tileEntry struct {
	Index          int                       `json:"index"`
	TerrainType    string                    `json:"terrain_type"`
	Compatibilities map[string]compatibility `json:"compatibilities"`
}

func main() {
	const myrrorStart = 0x2FA

	entries := make([]tileEntry, 0, myrrorStart)

	for index := 0; index < myrrorStart; index++ {
		tile := terrain.GetTile(index)

		// Iterate tile.Compatibilities directly, not GetDirection: GetDirection
		// fills in a fake AnyOf{Unknown} for directions with no rule at all,
		// which would otherwise get exported as a real (and wrong) constraint.
		comps := make(map[string]compatibility)
		for dir, c := range tile.Compatibilities {
			if c.Terrains == nil || c.Terrains.Size() == 0 {
				continue
			}

			typeName := "any_of"
			if c.Type == terrain.NoneOf {
				typeName = "none_of"
			}

			var names []string
			for _, t := range c.Terrains.Values() {
				names = append(names, t.String())
			}

			comps[dir.String()] = compatibility{Type: typeName, Terrains: names}
		}

		entries = append(entries, tileEntry{
			Index:           index,
			TerrainType:     tile.TerrainType().String(),
			Compatibilities: comps,
		})
	}

	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(entries); err != nil {
		fmt.Fprintln(os.Stderr, "encode error:", err)
		os.Exit(1)
	}
}
