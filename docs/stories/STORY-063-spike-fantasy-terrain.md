# STORY-063: Spike: a high-resolution terrain set of Kevin's own art

**Parent:** none (a spike; if it works it becomes its own epic)
**Status:** open (2026-10-15), a spike: time-boxed, ends in a write-up and a go or no-go
**Size:** medium
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-15

## The question

Can Mirror draw the map's terrain from **Kevin's own high-resolution art** (made with an image generator such as DALL-E, picked from contact sheets) instead of the game's 20 x 18 pixel tiles, and does it look good enough to keep?

**Goal: no game assets.** The game's art is not extracted, shown to the generator or used as a reference. The new tiles come from text descriptions only. (Reasons: the originals are tiny and a poor reference anyway, and
art that is not derived from the game can ship in the repo and let the map draw without game files.) Only the *meaning* of the tile numbers is reused, and that is data, not art.

## Out of scope (a follow-up after the spike, Kevin 2026-10-15)

Units, city and tower sprites, lairs, node sparkles, roads, specials (ore, gems, wild game, nightshade), corruption, fog of war, plaques, flags. These stay the game's sprites for now. If the terrain works, replacing them is its own decision.

## What is reused (data, not art)

A save stores one tile number (0 to 761 per plane) per square. `priv/kazzmir_terrain_table.json` (from kazzmir/master-of-magic, checked against the real game, see
[classic-terrain-format.md](../reference/classic-terrain-format.md)) says what each number means: a terrain type and which neighbours it expects. Counted 2026-10-15, **15 terrain types**; tile numbers per type:
Shore 335, Desert 164, Tundra 163, River 43, Hill 18, Mountain 17, Grass 5, Lake 5, Forest 3, Swamp 3, Ocean 2, Sorcery Node 1, Nature Node 1, Chaos Node 1, Volcano 1. The many variants are the same terrain with different edges, which
the new renderer would **blend** from a few base textures instead of drawing each one.

## What to make (Kevin, with a generator)

A seamless, top-down, tileable texture per terrain, several variants each so large areas do not repeat:

- **Needed for the spike:** Grass, Forest, Ocean, Shore (the sand or surf band), Hill, Mountain, Desert.
- **Needed for a full set:** Tundra, Swamp, Lake, River (a strip that bends and joins), Volcano, and the three nodes (Sorcery, Nature, Chaos).
- *Animated water* (four frames in the game): *guess:* a slow scroll or ripple done in the renderer, not four drawn frames.

Prompt template (adjust per terrain): *"Seamless tileable top-down texture of [terrain], flat even lighting, no shadows, no perspective, no objects at the edges, high fantasy painted style, [palette]"*. Ask for three to six variants per sheet.

## What to build

1. **A seam check** (a script, no dependency; or in the lab page): tile a texture 3 x 3 and show it offset by half, so a seam is obvious at a glance.
2. **A "Fantasy" tile mode on a lab page** (for example `/lab/fantasy`): a real save region drawn from the textures, next to the same region in the classic art. The renderer picks a base texture per terrain type from the table and
   **blends across tile edges** with the neighbour rules the table already has. Coasts, rivers and the edges of desert, tundra, hills and mountains are the hard cases.
3. **Size check:** at 128 px per tile the whole map is 7680 x 5120 px per plane. Test zoom to 400% and pan on a laptop; decide on one canvas, tiles drawn on demand, or a few zoom levels.
4. **Where the textures live and how they are licensed** (they are Kevin's, so they can be in the repo, small enough not to bloat it; the repo is GPL-2.0, so say what licence the art has).

## Decision at the end

A short write-up in `docs/reference/` (what worked, what did not, screenshots) with a go or no-go. **Go means:** coasts and rivers look good with blended edges, the map stays smooth at 150 to 400% zoom, and Kevin likes it.
If go: an epic for the full set, a theme switch (Classic or Fantasy, so the original look stays for anyone who wants it), and the follow-up question about units and the other sprites.

## Not known yet

- Whether blended edges look good enough for coasts and rivers (*guess:* yes for land types, harder for the shore and river strips).
- How well a generator keeps one terrain's style consistent across sheets (it tends to drift: a fixed prompt and a fixed palette help).
- Whether the animated water can be done acceptably in the renderer.
