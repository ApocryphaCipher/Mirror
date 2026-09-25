// Overlay layers drawn above the terrain on the map pages (STORY-009).
//
// Overlays live on their own transparent canvas, stacked exactly over the
// terrain canvas inside the MapViewport stage, so:
//   * sprites can overhang their tile (cities are 32x30 on a 20x18 tile)
//     without being clipped when the terrain redraws a single edited tile;
//   * toggling a layer only redraws this canvas; the terrain canvas is never
//     touched, so the terrain-only view is unchanged.
//
// The layer list and draw order come from the Layers panel's checkboxes,
// which MapLive renders top layer first (like a paint program's layer
// list). Each layer's items arrive with the "overlay_data" event;
// visibility is remembered per browser.

const STORAGE_KEY = "mirror.overlayLayers.v1"

// Terrain tiles are 20x18 art pixels drawn into a square cell, so overlay
// art is scaled the same way per axis.
const TILE_ART_W = 20
const TILE_ART_H = 18

// Banner colours are 5-shade ramps in the game palette (199-223). City flags
// are drawn in 216-218; the game shows them as the owner's ramp shades 2-4
// (start + 1..3: 210-212 for yellow) and neutral cities in browns 53-55.
// Both checked pixel-for-pixel in DOSBox screenshots (STORY-032); the other
// wizard colours are assumed to follow the yellow rule. See the sprite
// catalog.
const FLAG = [216, 217, 218]
const RAMP_START = {red: 199, purple: 204, yellow: 209, green: 214, blue: 219}
const NEUTRAL_FLAG = [53, 54, 55]

function flagRemap(banner) {
  const start = RAMP_START[banner]
  const to = start === undefined ? NEUTRAL_FLAG : FLAG.map((_, i) => start + 1 + i)
  return new Map(FLAG.map((from, i) => [from, to[i]]))
}

// A 4x4 ordered-dither (Bayer) pattern of black "fog pixels", `coverage`
// (0..1) of them set, each `pixel` device pixels square. Patterns anchor to
// the canvas origin, so the dither runs seamlessly across tiles.
const BAYER_4 = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

function ditherPattern(ctx, coverage, pixel) {
  const canvas = document.createElement("canvas")
  canvas.width = canvas.height = 4 * pixel
  const c = canvas.getContext("2d")
  c.fillStyle = "#000"
  BAYER_4.forEach((threshold, i) => {
    if (threshold < coverage * 16) c.fillRect((i % 4) * pixel, Math.floor(i / 4) * pixel, pixel, pixel)
  })
  return ctx.createPattern(canvas, "repeat")
}

function bitCount(n) {
  let count = 0
  for (; n; n >>= 1) count += n & 1
  return count
}

// One draw function per layer, filled in by the stories that decode the
// data (STORY-013 roads/specials, 008 auras, 011 sites, 010 cities, 012
// units). Each receives (ctx, items, geometry) and draws every item.
const DRAWERS = {
  // STORY-035: where a new city could go, greener where its Maximum Pop
  // would be higher (the cap is 25).
  settleable(ctx, items, {tileSize}) {
    for (const {x, y, max_pop} of items) {
      ctx.fillStyle = `rgba(52, 211, 153, ${0.12 + (0.5 * max_pop) / 25})`
      ctx.fillRect(x * tileSize, y * tileSize, tileSize, tileSize)
    }
  },

  // STORY-036: black over unexplored tiles (0). A partly explored tile
  // (1-14, four bits) gets Mirror's own soft edge, not the game's: a light
  // veil plus a dither, both heavier the more bits are missing.
  fog(ctx, items, {tileSize}) {
    const pixel = Math.max(1, Math.round(tileSize / 10))
    const patterns = new Map()

    for (const {x, y, explored} of items) {
      const left = x * tileSize
      const top = y * tileSize
      if (explored === 0) {
        ctx.fillStyle = "#000"
        ctx.fillRect(left, top, tileSize, tileSize)
        continue
      }
      const missing = (4 - bitCount(explored)) / 4
      if (!patterns.has(missing)) patterns.set(missing, ditherPattern(ctx, missing, pixel))
      ctx.fillStyle = `rgba(0, 0, 0, ${0.15 + 0.35 * missing})`
      ctx.fillRect(left, top, tileSize, tileSize)
      ctx.fillStyle = patterns.get(missing)
      ctx.fillRect(left, top, tileSize, tileSize)
    }
  },

  // STORY-010/032. The game draws MAPBACK #20 at frame size - 1, walls or
  // not: outposts (size 0) and hamlets (1) show frame 0, villages (2) frame
  // 1, all with a flag, centred on the tile. Checked in DOSBox; Town and up
  // (frames 2-4) haven't been seen in-game yet.
  cities(ctx, items, {tileSize, sprites}) {
    const sprite = sprites?.cities?.city
    if (!sprite) return
    const w = Math.round((sprite.width * tileSize) / TILE_ART_W)
    const h = Math.round((sprite.height * tileSize) / TILE_ART_H)

    for (const city of items) {
      const frame = Math.max(0, Math.min(city.size - 1, sprite.frames.length - 1))
      const image = sprites.image("cities.city", sprite, frame, city.banner)
      const left = Math.round((city.x + 0.5) * tileSize - w / 2)
      const top = Math.round((city.y + 0.5) * tileSize - h / 2)
      ctx.drawImage(image, left, top, w, h)
    }
  },
}

// Decoded sprite frames, recoloured per banner on first use and cached.
function spriteBank({palette, ...groups}) {
  const rgba = Uint8Array.from(atob(palette), c => c.charCodeAt(0))
  const cache = new Map()

  for (const group of Object.values(groups)) {
    for (const sprite of Object.values(group)) {
      sprite.indices = sprite.frames.map(f => Uint8Array.from(atob(f), c => c.charCodeAt(0)))
    }
  }

  return {
    ...groups,
    image(name, sprite, frame, banner) {
      const key = `${name}/${frame}/${banner}`
      if (cache.has(key)) return cache.get(key)

      const remap = flagRemap(banner)
      const canvas = document.createElement("canvas")
      canvas.width = sprite.width
      canvas.height = sprite.height
      const ctx = canvas.getContext("2d")
      const image = ctx.createImageData(sprite.width, sprite.height)
      const indices = sprite.indices[frame]
      for (let p = 0; p < indices.length; p++) {
        const index = indices[p]
        if (index === 0) continue // transparent
        const c = (remap.get(index) ?? index) * 4
        image.data.set([rgba[c], rgba[c + 1], rgba[c + 2], 255], p * 4)
      }
      ctx.putImageData(image, 0, 0)
      cache.set(key, canvas)
      return canvas
    },
  }
}

const MapOverlays = {
  mounted() {
    const d = this.el.dataset
    this.tileSize = parseInt(d.tileSize || "32", 10)
    this.mapWidth = parseInt(d.mapWidth || "60", 10)
    this.mapHeight = parseInt(d.mapHeight || "40", 10)
    this.items = {}

    this.toggles = Array.from(
      document.querySelectorAll(`[data-overlay-toggle][data-for="${this.el.id}"]`)
    )
    // Panel lists top-first; draw bottom-first.
    this.layers = this.toggles.map(input => input.value).reverse()
    this.visible = this.loadVisibility()

    for (const input of this.toggles) {
      input.checked = this.visible[input.value]
      input.addEventListener("change", () => {
        this.visible[input.value] = input.checked
        this.saveVisibility()
        this.render()
      })
    }

    // The panel sits inside MapViewport: keep its clicks and scrolls from
    // panning or zooming the map.
    const panel = document.querySelector(`[data-overlay-panel]`)
    if (panel) {
      for (const type of ["pointerdown", "wheel", "dblclick"]) {
        panel.addEventListener(type, event => event.stopPropagation())
      }
    }

    this.sprites = null
    this.handleEvent("overlay_sprites", payload => {
      this.sprites = spriteBank(payload)
      this.render()
    })

    this.handleEvent("overlay_data", ({layer, items}) => {
      this.items[layer] = items || []
      this.render()
    })

    this.onResize = () => {
      if (this.resize()) this.render()
    }
    window.addEventListener("resize", this.onResize)

    this.resize()
    this.render()
  },

  destroyed() {
    window.removeEventListener("resize", this.onResize)
  },

  // Same CSS size as the terrain canvas; backing store at device pixels.
  // Returns true when the backing store changed.
  resize() {
    const dpr = window.devicePixelRatio || 1
    this.deviceTileSize = Math.max(1, Math.round(this.tileSize * dpr))
    this.el.style.width = `${this.mapWidth * this.tileSize}px`
    this.el.style.height = `${this.mapHeight * this.tileSize}px`

    const width = this.mapWidth * this.deviceTileSize
    const height = this.mapHeight * this.deviceTileSize
    if (this.el.width === width && this.el.height === height) return false
    this.el.width = width
    this.el.height = height
    return true
  },

  render() {
    const ctx = this.el.getContext("2d")
    ctx.setTransform(1, 0, 0, 1, 0, 0)
    ctx.clearRect(0, 0, this.el.width, this.el.height)
    ctx.imageSmoothingEnabled = false

    const geometry = {tileSize: this.deviceTileSize, sprites: this.sprites}
    for (const layer of this.layers) {
      if (!this.visible[layer]) continue
      const items = this.items[layer]
      const draw = DRAWERS[layer]
      if (!items || items.length === 0 || !draw) continue
      ctx.save()
      draw(ctx, items, geometry)
      ctx.restore()
    }
  },

  // Each layer starts as its checkbox is rendered (most on; fog and
  // settleable tiles off); storage can be unavailable (private windows,
  // blocked site data), so every access is guarded.
  loadVisibility() {
    const visible = Object.fromEntries(this.toggles.map(input => [input.value, input.defaultChecked]))
    try {
      const saved = JSON.parse(window.localStorage.getItem(STORAGE_KEY) || "{}")
      for (const layer of this.layers) {
        if (typeof saved[layer] === "boolean") visible[layer] = saved[layer]
      }
    } catch (_error) {
      // Ignore: fall back to the defaults.
    }
    return visible
  },

  saveVisibility() {
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(this.visible))
    } catch (_error) {
      // Ignore: the toggle still works for this page view.
    }
  },
}

export {MapOverlays, DRAWERS as OVERLAY_DRAWERS}
