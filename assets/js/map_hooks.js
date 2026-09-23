const LAYER_STACK = [
  "terrain",
  "terrain_flags",
  "minerals",
  "exploration",
  "landmass",
  "computed_adj_mask",
]

// Map canvas hook. Terrain art comes straight from TERRAIN.LBX: a save's
// terrain value is a tile number (docs/reference/classic-terrain-format.md).
const MapCanvas = {
  mounted() {
    this.tileSize = parseInt(this.el.dataset.tileSize || "12", 10)
    this.mapWidth = parseInt(this.el.dataset.mapWidth || "60", 10)
    this.mapHeight = parseInt(this.el.dataset.mapHeight || "40", 10)
    this.layerType = this.el.dataset.layerType || "u8"
    this.renderMode = this.el.dataset.renderMode || "values"
    this.activeLayer = this.el.dataset.layer || "terrain"
    this.phaseIndex = this.normalizePhaseIndex(this.el.dataset.phaseIndex)
    this.plane = this.el.dataset.plane || "arcanus"
    this.snapshotMode = this.parseBool(this.el.dataset.snapshotMode, true)
    this.values = this.decodeTiles(this.el.dataset.tiles || "", this.layerType)
    this.terrainValues = this.decodeTiles(this.el.dataset.terrain || "", "u16")
    this.terrainFlags = this.decodeTiles(this.el.dataset.terrainFlags || "", "u8")
    this.mineralsValues = this.decodeTiles(this.el.dataset.minerals || "", "u8")
    this.explorationValues = this.decodeTiles(this.el.dataset.exploration || "", "u8")
    this.landmassValues = this.decodeTiles(this.el.dataset.landmass || "", "u8")
    this.computedAdjMaskValues = this.decodeTiles(this.el.dataset.computedAdjMask || "", "u8")
    this.terrainLbx = null
    this.layerVisibility = {}
    this.layerOpacity = {}
    this.lastTileKey = null
    this.isPointerDown = false
    this.pointerButton = 0
    this.phaseLoopDetecting = false
    this.phaseLoopCanvas = null
    this.phaseLoopCtx = null

    this.ctx = this.el.getContext("2d", {alpha: false})
    this.ctx.imageSmoothingEnabled = false
    this.resizeCanvas()
    this.renderAll()

    this.handleResize = () => {
      const nextDpr = window.devicePixelRatio || 1
      const nextDeviceTile = Math.max(1, Math.round(this.tileSize * nextDpr))
      if (nextDeviceTile !== this.deviceTileSize) {
        this.resizeCanvas()
        this.renderAll()
      }
    }
    window.addEventListener("resize", this.handleResize)

    this.el.addEventListener("contextmenu", event => event.preventDefault())
    this.el.addEventListener("pointerdown", this.onPointerDown.bind(this))
    this.el.addEventListener("pointermove", this.onPointerMove.bind(this))
    this.el.addEventListener("pointerup", this.onPointerUp.bind(this))
    this.el.addEventListener("pointerleave", this.onPointerLeave.bind(this))
    this.el.addEventListener("wheel", this.onWheel.bind(this), {passive: false})

    this.handleEvent("map_state", payload => {
      let needsRender = false
      if (payload.layer && payload.layer !== this.activeLayer) {
        this.activeLayer = payload.layer
        needsRender = true
      }
      if (payload.layer_type) {
        this.layerType = payload.layer_type
        needsRender = true
      }
      if (payload.render_mode) {
        this.renderMode = payload.render_mode
        needsRender = true
      }
      if (payload.layer_visibility) {
        this.layerVisibility = payload.layer_visibility
        needsRender = true
      }
      if (payload.layer_opacity) {
        this.layerOpacity = payload.layer_opacity
        needsRender = true
      }
      if (Object.prototype.hasOwnProperty.call(payload, "phase_index")) {
        this.phaseIndex = this.normalizePhaseIndex(payload.phase_index)
        needsRender = true
      }
      if (Object.prototype.hasOwnProperty.call(payload, "snapshot_mode")) {
        this.snapshotMode = this.parseBool(payload.snapshot_mode, this.snapshotMode)
        needsRender = true
      }
      if (needsRender) {
        this.renderAll()
      }
    })

    this.handleEvent("map_reload", payload => {
      if (payload.layer) this.activeLayer = payload.layer
      if (payload.plane) this.plane = payload.plane
      this.layerType = payload.layer_type || this.layerType
      this.values = this.decodeTiles(payload.values || "", this.layerType)
      if (payload.terrain) this.terrainValues = this.decodeTiles(payload.terrain, "u16")
      if (payload.terrain_flags) this.terrainFlags = this.decodeTiles(payload.terrain_flags, "u8")
      if (payload.minerals) this.mineralsValues = this.decodeTiles(payload.minerals, "u8")
      if (payload.exploration) this.explorationValues = this.decodeTiles(payload.exploration, "u8")
      if (payload.landmass) this.landmassValues = this.decodeTiles(payload.landmass, "u8")
      if (payload.computed_adj_mask) {
        this.computedAdjMaskValues = this.decodeTiles(payload.computed_adj_mask, "u8")
      }
      if (payload.render_mode) this.renderMode = payload.render_mode
      if (payload.layer_visibility) this.layerVisibility = payload.layer_visibility
      if (payload.layer_opacity) this.layerOpacity = payload.layer_opacity
      if (Object.prototype.hasOwnProperty.call(payload, "phase_index")) {
        this.phaseIndex = this.normalizePhaseIndex(payload.phase_index)
      }
      if (Object.prototype.hasOwnProperty.call(payload, "snapshot_mode")) {
        this.snapshotMode = this.parseBool(payload.snapshot_mode, this.snapshotMode)
      }
      this.renderAll()
    })

    this.handleEvent("engine_delta", payload => {
      if (!payload || !Array.isArray(payload.changes)) return
      if (payload.delta_type && payload.delta_type !== "tile_set") return
      if (payload.layer_type) this.layerType = payload.layer_type
      const layer = payload.layer || this.activeLayer

      payload.changes.forEach(change => {
        const value = change.new ?? change.value
        if (!Number.isFinite(change.x) || !Number.isFinite(change.y) || !Number.isFinite(value)) return
        this.applyTileValue(layer, change.x, change.y, value)
      })
    })

    this.handleEvent("tile_updates", payload => {
      if (!payload || !Array.isArray(payload.updates)) return
      this.layerType = payload.layer_type || this.layerType
      payload.updates.forEach(update => {
        this.applyTileValue(payload.layer, update.x, update.y, update.value)
      })
    })

    this.handleEvent("tile_assets", payload => {
      if (!payload) return
      this.terrainLbx = payload.terrain_lbx ? this.buildTerrainLbxAtlas(payload.terrain_lbx) : null
      this.renderAll()
    })

    this.handleEvent("map_render_mode", payload => {
      if (!payload || !payload.mode) return
      this.renderMode = payload.mode
      this.renderAll()
    })

    this.handleEvent("snapshot_export", payload => {
      this.exportSnapshot(payload || {})
    })

    this.handleEvent("phase_loop_detect", payload => {
      this.detectPhaseLoop(payload || {})
    })

    this.handleEvent("stats_export", payload => {
      if (!payload || !payload.content) return
      const blob = new Blob([payload.content], {type: "application/json"})
      const url = URL.createObjectURL(blob)
      const link = document.createElement("a")
      link.href = url
      link.download = payload.filename || "mirror-stats.json"
      document.body.appendChild(link)
      link.click()
      link.remove()
      URL.revokeObjectURL(url)
    })
  },

  destroyed() {
    if (this.handleResize) {
      window.removeEventListener("resize", this.handleResize)
    }
  },

  resizeCanvas() {
    const dpr = window.devicePixelRatio || 1
    const deviceTileSize = Math.max(1, Math.round(this.tileSize * dpr))
    const cssWidth = this.mapWidth * this.tileSize
    const cssHeight = this.mapHeight * this.tileSize
    const deviceWidth = this.mapWidth * deviceTileSize
    const deviceHeight = this.mapHeight * deviceTileSize

    this.deviceTileSize = deviceTileSize
    this.dpr = deviceTileSize / this.tileSize
    this.el.style.width = `${cssWidth}px`
    this.el.style.height = `${cssHeight}px`

    if (this.el.width !== deviceWidth) {
      this.el.width = deviceWidth
    }
    if (this.el.height !== deviceHeight) {
      this.el.height = deviceHeight
    }

    this.ctx.imageSmoothingEnabled = false
  },

  decodeTiles(encoded, layerType) {
    if (!encoded) {
      return layerType === "u16"
        ? new Uint16Array(this.mapWidth * this.mapHeight)
        : new Uint8Array(this.mapWidth * this.mapHeight)
    }

    const bytes = Uint8Array.from(atob(encoded), char => char.charCodeAt(0))

    if (layerType === "u16") {
      const view = new DataView(bytes.buffer)
      const values = new Uint16Array(this.mapWidth * this.mapHeight)
      for (let i = 0; i < values.length; i++) {
        values[i] = view.getUint16(i * 2, true)
      }
      return values
    }

    return bytes
  },

  parseBool(value, fallback = false) {
    if (value === undefined || value === null) return fallback
    if (value === true || value === "true" || value === 1 || value === "1") return true
    if (value === false || value === "false" || value === 0 || value === "0") return false
    return fallback
  },

  parsePositiveInt(value, fallback) {
    const parsed = parseInt(value ?? fallback, 10)
    if (!Number.isFinite(parsed) || parsed < 1) return fallback
    return parsed
  },

  parseNonNegativeInt(value, fallback) {
    const parsed = parseInt(value ?? fallback, 10)
    if (!Number.isFinite(parsed) || parsed < 0) return fallback
    return parsed
  },

  normalizePhaseIndex(value) {
    const parsed = parseInt(value ?? "0", 10)
    if (!Number.isFinite(parsed) || parsed < 0) return 0
    return parsed
  },

  resolveRender(render) {
    const ctx = render?.ctx || this.ctx
    const size = render?.size || this.deviceTileSize
    const phaseIndex = this.normalizePhaseIndex(render?.phaseIndex ?? this.phaseIndex)
    const usePhase = render?.usePhase ?? this.snapshotMode
    return {ctx, size, phaseIndex, usePhase}
  },

  // Store an edited tile value and redraw just that tile. On the TERRAIN.LBX
  // path a tile's art depends only on its own value, so no neighbours change.
  applyTileValue(layer, x, y, value) {
    const idx = y * this.mapWidth + x
    if (idx < 0 || idx >= this.values.length) return

    if (layer === this.activeLayer) this.values[idx] = value
    const values = this.layerValues(layer)
    if (values) values[idx] = value

    if (this.renderMode === "tiles" && this.hasTileAssets()) {
      if (layer === "terrain" || this.isLayerVisible(layer)) this.drawStackedTile(x, y)
    } else if (layer === this.activeLayer) {
      this.drawTile(x, y, value)
    }
  },

  drawTile(x, y, value) {
    if (this.renderMode === "tiles" && this.hasTileAssets()) {
      this.drawStackedTile(x, y)
    } else {
      this.drawValueTile(x, y, value)
    }
  },

  renderAll() {
    this.ctx.setTransform(1, 0, 0, 1, 0, 0)
    if (this.renderMode === "tiles" && this.hasTileAssets()) {
      this.renderLayerStack()
    } else {
      this.renderValues()
    }
  },

  drawValueTile(x, y, value, render, layerType) {
    const {ctx, size} = this.resolveRender(render)
    ctx.fillStyle = this.colorForValue(value, layerType)
    ctx.fillRect(
      x * size,
      y * size,
      size,
      size
    )
  },

  renderValues() {
    for (let y = 0; y < this.mapHeight; y++) {
      for (let x = 0; x < this.mapWidth; x++) {
        const idx = y * this.mapWidth + x
        this.drawValueTile(x, y, this.values[idx])
      }
    }
  },

  renderLayerStack(render) {
    const resolved = this.resolveRender(render)
    this.fillBackground(resolved.ctx, resolved.size)

    for (let y = 0; y < this.mapHeight; y++) {
      for (let x = 0; x < this.mapWidth; x++) {
        this.drawTerrainBase(x, y, resolved)
      }
    }

    const layers = this.layerStack()
    for (let i = 0; i < layers.length; i++) {
      const layer = layers[i]
      if (layer === "terrain") continue
      if (!this.isLayerVisible(layer)) continue
      const opacity = this.layerOpacityValue(layer)
      if (opacity <= 0) continue

      resolved.ctx.save()
      resolved.ctx.globalAlpha = opacity
      for (let y = 0; y < this.mapHeight; y++) {
        for (let x = 0; x < this.mapWidth; x++) {
          this.drawLayerOverlay(layer, x, y, resolved)
        }
      }
      resolved.ctx.restore()
    }
  },

  hasTileAssets() {
    return !!this.terrainLbx
  },

  buildTerrainLbxAtlas(data) {
    const tileW = data.tile_width
    const tileH = data.tile_height
    const count = data.tile_count
    const pixels = Uint8Array.from(atob(data.pixels), char => char.charCodeAt(0))
    const palette = Uint8Array.from(atob(data.palette), char => char.charCodeAt(0))
    const columns = 64
    const rows = Math.ceil(count / columns)
    const canvas = document.createElement("canvas")
    canvas.width = columns * tileW
    canvas.height = rows * tileH
    const ctx = canvas.getContext("2d")
    const image = ctx.createImageData(canvas.width, canvas.height)
    const out = image.data
    const tilePx = tileW * tileH

    for (let t = 0; t < count; t++) {
      const originX = (t % columns) * tileW
      const originY = Math.floor(t / columns) * tileH
      for (let p = 0; p < tilePx; p++) {
        const color = pixels[t * tilePx + p] * 4
        const dst = ((originY + Math.floor(p / tileW)) * canvas.width + originX + (p % tileW)) * 4
        out[dst] = palette[color]
        out[dst + 1] = palette[color + 1]
        out[dst + 2] = palette[color + 2]
        out[dst + 3] = 255
      }
    }
    ctx.putImageData(image, 0, 0)

    return {canvas, columns, tileW, tileH, tiles: data.tiles || {}}
  },

  drawTerrainLbxTile(x, y, render) {
    const atlas = this.terrainLbx
    if (!atlas) return false
    const planeTiles = atlas.tiles[this.plane]
    if (!planeTiles) return false
    const value = this.terrainValues[y * this.mapWidth + x] || 0
    const tile = planeTiles[value]
    if (!tile || tile[0] < 0) return false

    const [index, frames] = tile
    const frame = frames > 1 && render.usePhase ? render.phaseIndex % frames : 0
    const t = index + frame
    const {ctx, size} = render
    ctx.drawImage(
      atlas.canvas,
      (t % atlas.columns) * atlas.tileW,
      Math.floor(t / atlas.columns) * atlas.tileH,
      atlas.tileW,
      atlas.tileH,
      x * size,
      y * size,
      size,
      size
    )
    return true
  },

  fillBackground(ctx = this.ctx, size = this.deviceTileSize) {
    const width = this.mapWidth * size
    const height = this.mapHeight * size
    ctx.fillStyle = "#020617"
    ctx.fillRect(0, 0, width, height)
  },

  fillTileBackground(x, y, render) {
    const {ctx, size} = this.resolveRender(render)
    ctx.fillStyle = "#020617"
    ctx.fillRect(x * size, y * size, size, size)
  },

  drawTerrainBase(x, y, render) {
    const resolved = this.resolveRender(render)
    if (!this.drawTerrainLbxTile(x, y, resolved)) {
      this.drawMissingTile(x, y, resolved, "missing")
    }
  },

  drawStackedTile(x, y, render) {
    const resolved = this.resolveRender(render)
    this.fillTileBackground(x, y, resolved)
    this.drawTerrainBase(x, y, resolved)

    const layers = this.layerStack()
    for (let i = 0; i < layers.length; i++) {
      const layer = layers[i]
      if (layer === "terrain") continue
      if (!this.isLayerVisible(layer)) continue
      const opacity = this.layerOpacityValue(layer)
      if (opacity <= 0) continue

      resolved.ctx.save()
      resolved.ctx.globalAlpha = opacity
      this.drawLayerOverlay(layer, x, y, resolved)
      resolved.ctx.restore()
    }
  },

  layerStack() {
    return LAYER_STACK
  },

  isLayerVisible(layer) {
    if (layer === "terrain") return true
    if (this.layerVisibility && Object.prototype.hasOwnProperty.call(this.layerVisibility, layer)) {
      return !!this.layerVisibility[layer]
    }
    return layer === this.activeLayer
  },

  layerOpacityValue(layer) {
    const fallback = layer === "terrain" ? 100 : 70
    const raw = this.layerOpacity?.[layer]
    const value = Number.isFinite(raw) ? raw : parseFloat(raw ?? fallback)
    if (!Number.isFinite(value)) return fallback / 100
    return Math.max(0, Math.min(100, value)) / 100
  },

  layerTypeFor(layer) {
    return layer === "terrain" ? "u16" : "u8"
  },

  layerValues(layer) {
    switch (layer) {
      case "terrain":
        return this.terrainValues
      case "terrain_flags":
        return this.terrainFlags
      case "minerals":
        return this.mineralsValues
      case "exploration":
        return this.explorationValues
      case "landmass":
        return this.landmassValues
      case "computed_adj_mask":
        return this.computedAdjMaskValues
      default:
        return null
    }
  },

  // Research layers (Lab) draw as value colours over the terrain. Sprite
  // overlays for flags/minerals come back once their bits are decoded
  // (STORY-013).
  drawLayerOverlay(layer, x, y, render) {
    const values = this.layerValues(layer)
    if (!values) return
    const value = values[y * this.mapWidth + x] || 0
    if (value === 0 && (layer === "terrain_flags" || layer === "minerals")) return
    this.drawValueTile(x, y, value, render, this.layerTypeFor(layer))
  },

  drawMissingTile(x, y, render, label) {
    const {ctx, size} = this.resolveRender(render)
    ctx.fillStyle = "#ff00ff"
    ctx.fillRect(x * size, y * size, size, size)
    if (size >= 12) {
      ctx.fillStyle = "#0f172a"
      ctx.font = `${Math.max(8, Math.floor(size / 3))}px sans-serif`
      ctx.fillText(label || "?", x * size + 2, y * size + size - 2)
    }
  },

  exportSnapshot(payload) {
    if (!this.hasTileAssets()) return
    const phaseIndex = this.normalizePhaseIndex(
      payload.effective_phase ?? payload.phase_index ?? payload.phaseIndex
    )
    const filename = payload.filename || `mirror-snapshot-phase-${phaseIndex}.png`
    const canvas = document.createElement("canvas")
    const size = this.tileSize
    canvas.width = this.mapWidth * size
    canvas.height = this.mapHeight * size
    const ctx = canvas.getContext("2d", {alpha: false})
    ctx.imageSmoothingEnabled = false

    this.renderSnapshotTiles(ctx, size, phaseIndex)

    canvas.toBlob(blob => {
      if (!blob) return
      const url = URL.createObjectURL(blob)
      const link = document.createElement("a")
      link.href = url
      link.download = filename
      document.body.appendChild(link)
      link.click()
      link.remove()
      URL.revokeObjectURL(url)
    }, "image/png")
  },

  renderSnapshotTiles(ctx, size, phaseIndex) {
    const render = {ctx, size, phaseIndex, usePhase: true}
    this.renderLayerStack(render)
  },

  detectPhaseLoop(payload) {
    if (this.phaseLoopDetecting) return
    if (!this.hasTileAssets()) {
      this.pushEvent("phase_loop_detected", {
        status: "error",
        reason: "missing_assets",
      })
      return
    }

    this.phaseLoopDetecting = true
    try {
      const maxPhases = this.parsePositiveInt(payload.max_phases, 32)
      const threshold = this.parseNonNegativeInt(payload.threshold, 0)
      const fallback = this.parsePositiveInt(payload.fallback, 8)

      const baseline = this.renderPhaseImageData(0)
      let detected = null

      for (let phase = 1; phase <= maxPhases; phase++) {
        const image = this.renderPhaseImageData(phase)
        const diff = this.diffImageData(baseline, image, threshold)
        if (diff <= threshold) {
          detected = {loop_len: phase, diff}
          break
        }
      }

      const status = detected ? "detected" : "assumed"
      const loopLen = detected ? detected.loop_len : fallback
      const diff = detected ? detected.diff : null

      this.phaseLoopDetecting = false
      this.pushEvent("phase_loop_detected", {
        status,
        loop_len: loopLen,
        diff,
        max_phases: maxPhases,
        threshold,
      })
    } catch (_error) {
      this.phaseLoopDetecting = false
      this.pushEvent("phase_loop_detected", {
        status: "error",
        reason: "exception",
      })
    }
  },

  renderPhaseImageData(phaseIndex) {
    const size = this.tileSize
    const width = this.mapWidth * size
    const height = this.mapHeight * size

    if (!this.phaseLoopCanvas) {
      this.phaseLoopCanvas = document.createElement("canvas")
    }

    const canvas = this.phaseLoopCanvas
    if (canvas.width !== width) canvas.width = width
    if (canvas.height !== height) canvas.height = height

    if (!this.phaseLoopCtx) {
      this.phaseLoopCtx = canvas.getContext("2d", {alpha: false})
    }

    const ctx = this.phaseLoopCtx
    ctx.imageSmoothingEnabled = false
    this.fillBackground(ctx, size)
    this.renderSnapshotTiles(ctx, size, phaseIndex)
    return ctx.getImageData(0, 0, width, height)
  },

  diffImageData(base, current, threshold) {
    if (!base || !current || base.data.length !== current.data.length) {
      return Number.POSITIVE_INFINITY
    }

    const baseData = base.data
    const currentData = current.data
    let diff = 0

    if (threshold <= 0) {
      for (let i = 0; i < baseData.length; i++) {
        if (baseData[i] !== currentData[i]) return 1
      }
      return 0
    }

    for (let i = 0; i < baseData.length; i++) {
      diff += Math.abs(baseData[i] - currentData[i])
      if (diff > threshold) return diff
    }

    return diff
  },

  colorForValue(value, layerType) {
    const hue = (value * 37) % 360
    const type = layerType || this.layerType
    const lightness = type === "u16" ? 28 + (value % 32) : 30 + (value % 64) / 2
    const saturation = type === "u16" ? 48 : 62
    return `hsl(${hue}, ${saturation}%, ${lightness}%)`
  },

  tileFromEvent(event) {
    const rect = this.el.getBoundingClientRect()
    const scaleX = this.el.width / rect.width
    const scaleY = this.el.height / rect.height
    const px = (event.clientX - rect.left) * scaleX
    const py = (event.clientY - rect.top) * scaleY
    const x = Math.floor(px / this.deviceTileSize)
    const y = Math.floor(py / this.deviceTileSize)

    if (x < 0 || y < 0 || x >= this.mapWidth || y >= this.mapHeight) {
      return null
    }

    return {x, y}
  },

  buildMods(event) {
    return {
      alt: event.altKey,
      ctrl: event.ctrlKey,
      shift: event.shiftKey,
    }
  },

  onPointerDown(event) {
    const tile = this.tileFromEvent(event)
    if (!tile) return

    this.isPointerDown = true
    this.pointerButton = event.button
    this.el.setPointerCapture(event.pointerId)
    this.pushEvent("map_pointer", {
      action: "start",
      x: tile.x,
      y: tile.y,
      button: event.button,
      mods: this.buildMods(event),
    })
  },

  onPointerMove(event) {
    const tile = this.tileFromEvent(event)
    if (!tile) return

    const tileKey = `${tile.x}:${tile.y}`
    if (this.lastTileKey === tileKey && !this.isPointerDown) return
    this.lastTileKey = tileKey

    this.pushEvent("map_pointer", {
      action: this.isPointerDown ? "drag" : "hover",
      x: tile.x,
      y: tile.y,
      button: this.pointerButton,
      mods: this.buildMods(event),
    })
  },

  onPointerUp(event) {
    if (!this.isPointerDown) return
    this.isPointerDown = false
    this.el.releasePointerCapture(event.pointerId)
    this.pushEvent("map_pointer", {action: "end"})
  },

  onPointerLeave() {
    if (!this.isPointerDown) return
    this.isPointerDown = false
    this.pushEvent("map_pointer", {action: "end"})
  },

  onWheel(event) {
    event.preventDefault()
    this.pushEvent("map_pointer", {
      action: "wheel",
      delta: event.deltaY,
      mods: this.buildMods(event),
    })
  },
}

export {MapCanvas}
