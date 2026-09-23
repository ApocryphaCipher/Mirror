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
// are drawn in green shades 3-5 (216-218); *guess*: the game recolours them
// to the owner's ramp. Neutral cities (no wizard ramp) get the neutral
// plaque's browns (53-55), also a guess. See the sprite catalog.
const FLAG = [216, 217, 218]
const RAMP_START = {red: 199, purple: 204, yellow: 209, green: 214, blue: 219}
const NEUTRAL_FLAG = [53, 54, 55]

function flagRemap(banner) {
  const start = RAMP_START[banner]
  const to = start === undefined ? NEUTRAL_FLAG : FLAG.map(i => i - RAMP_START.green + start)
  return new Map(FLAG.map((from, i) => [from, to[i]]))
}

// One draw function per layer, filled in by the stories that decode the
// data (STORY-013 roads/specials, 008 auras, 011 sites, 010 cities, 012
// units). Each receives (ctx, items, geometry) and draws every item.
const DRAWERS = {
  // STORY-010. Frame = the city's size class (clamped); walled cities
  // (MAPBACK #20) are a follow-up, so every city uses the unwalled sprite.
  cities(ctx, items, {tileSize, sprites}) {
    const sprite = sprites?.cities?.unwalled
    if (!sprite) return
    const w = Math.round((sprite.width * tileSize) / TILE_ART_W)
    const h = Math.round((sprite.height * tileSize) / TILE_ART_H)

    for (const city of items) {
      const frame = Math.max(0, Math.min(city.size, sprite.frames.length - 1))
      const image = sprites.image("cities.unwalled", sprite, frame, city.banner)
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

  // All layers on by default; storage can be unavailable (private windows,
  // blocked site data), so every access is guarded.
  loadVisibility() {
    const visible = Object.fromEntries(this.layers.map(layer => [layer, true]))
    try {
      const saved = JSON.parse(window.localStorage.getItem(STORAGE_KEY) || "{}")
      for (const layer of this.layers) {
        if (typeof saved[layer] === "boolean") visible[layer] = saved[layer]
      }
    } catch (_error) {
      // Ignore: fall back to all layers on.
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
