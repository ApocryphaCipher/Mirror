const ADJ_DIRS = [
  [0, -1],
  [1, -1],
  [1, 0],
  [1, 1],
  [0, 1],
  [-1, 1],
  [-1, 0],
  [-1, -1],
]

const ADJ_DIR_LABELS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const SHORE_MASK_DIRS = [
  [0, -1],  // N
  [1, -1],  // NE
  [1, 0],   // E
  [1, 1],   // SE
  [0, 1],   // S
  [-1, 1],  // SW
  [-1, 0],  // W
  [-1, -1], // NW
]

const TERRAIN_KIND_BY_BASE_ID = {
  0: "ocean",
  1: "shore",
  2: "grass",
  3: "forest",
  4: "hill",
  5: "mountain",
  6: "tundra",
  7: "swamp",
  8: "desert",
  9: "grass",
  10: "forest",
  11: "hill",
  12: "mountain",
  13: "tundra",
  14: "swamp",
  15: "desert",
}

const TERRAIN_KIND_DEBUG_COLORS = {
  ocean: "#0ea5e9",
  shore: "#38bdf8",
  grass: "#84cc16",
  forest: "#22c55e",
  hill: "#f97316",
  mountain: "#94a3b8",
  desert: "#f59e0b",
  tundra: "#e2e8f0",
  swamp: "#10b981",
  unknown: "#ff00ff",
}

const SHORE_SEMANTIC_COLORS = {
  straight_edge: "#38bdf8",
  convex_corner: "#f59e0b",
  concave_inlet: "#f472b6",
  peninsula: "#a3e635",
  island_tip: "#22d3ee",
  channel: "#cbd5f5",
  unknown: "#facc15",
}

const SHORE_SEMANTIC_LABELS = {
  straight_edge: "edge",
  convex_corner: "convex",
  concave_inlet: "inlet",
  peninsula: "pen",
  island_tip: "tip",
  channel: "chan",
  unknown: "shore",
}

const LAYER_STACK = [
  "terrain",
  "terrain_flags",
  "minerals",
  "exploration",
  "landmass",
  "computed_adj_mask",
]

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
    this.tileBackend = "lbx"
    this.tileImages = {}
    this.terrainGroups = {}
    this.overlayGroups = {}
    this.momimeIndex = {}
    this.momimeFrames = {}
    this.momimeBaseUrl = ""
    this.momimeImageCache = {}
    this.momimeMaskWhitelist = {}
    this.terrainNames = {}
    this.terrainWaterValues = [0]
    this.terrainWaterValueSet = new Set(this.terrainWaterValues)
    this.terrainFlagNames = {}
    this.terrainKindOverrides = {}
    this.debugTerrainKinds = this.parseBool(this.el.dataset.debugTerrainKinds, false)
    this.debugTerrainSamples = this.parseBool(this.el.dataset.debugTerrainSamples, false)
    this.debugCoastAudit = this.parseBool(this.el.dataset.debugCoastAudit, false)
    this.debugMomimeMask = this.parseBool(this.el.dataset.debugMomimeMask, this.debugCoastAudit)
    this.debugShoreSemantics = this.parseBool(this.el.dataset.debugShoreSemantics, false)
    this.coastDiagonalReduction = this.parseBool(this.el.dataset.coastDiagonalReduction, true)
    this.terrainSampleLogged = false
    this.terrainBaseSource = "lo"
    this.terrainBaseSourceStats = null
    this.momimeMaskSampleCount = 0
    this.momimeMaskSampleLimit = 12
    this.momimeMaskRotationStats = {0: 0, 90: 0, 180: 0, 270: 0}
    this.momimeMaskRotationLogEvery = 100
    this.coastAuditMissingStats = {}
    this.coastAuditMissingLogEvery = 50
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
      if (payload.layer) {
        if (payload.layer !== this.activeLayer) {
          this.activeLayer = payload.layer
          needsRender = true
        }
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
      if (Object.prototype.hasOwnProperty.call(payload, "debug_terrain_kinds")) {
        this.debugTerrainKinds = this.parseBool(payload.debug_terrain_kinds, this.debugTerrainKinds)
        this.maybeLogTerrainSamples()
        needsRender = true
      }
      if (Object.prototype.hasOwnProperty.call(payload, "debug_coast_audit")) {
        this.debugCoastAudit = this.parseBool(payload.debug_coast_audit, this.debugCoastAudit)
        this.debugMomimeMask = this.debugCoastAudit
      }
      if (Object.prototype.hasOwnProperty.call(payload, "debug_shore_semantics")) {
        this.debugShoreSemantics = this.parseBool(payload.debug_shore_semantics, this.debugShoreSemantics)
        needsRender = true
      }
      if (Object.prototype.hasOwnProperty.call(payload, "debug_terrain_samples")) {
        this.debugTerrainSamples = this.parseBool(payload.debug_terrain_samples, this.debugTerrainSamples)
        this.maybeLogTerrainSamples()
      }
      if (Object.prototype.hasOwnProperty.call(payload, "debug_momime_mask")) {
        this.debugMomimeMask = this.parseBool(payload.debug_momime_mask, this.debugMomimeMask)
        this.debugCoastAudit = this.debugMomimeMask
      }
      if (needsRender) {
        this.renderAll()
      }
    })

    this.handleEvent("map_reload", payload => {
      if (payload.layer) {
        this.activeLayer = payload.layer
      }
      if (payload.plane) {
        this.plane = payload.plane
      }
      this.layerType = payload.layer_type || this.layerType
      this.values = this.decodeTiles(payload.values || "", this.layerType)
      if (payload.terrain) {
        this.terrainValues = this.decodeTiles(payload.terrain, "u16")
      }
      if (payload.terrain_flags) {
        this.terrainFlags = this.decodeTiles(payload.terrain_flags, "u8")
      }
      if (payload.minerals) {
        this.mineralsValues = this.decodeTiles(payload.minerals, "u8")
      }
      if (payload.exploration) {
        this.explorationValues = this.decodeTiles(payload.exploration, "u8")
      }
      if (payload.landmass) {
        this.landmassValues = this.decodeTiles(payload.landmass, "u8")
      }
      if (payload.computed_adj_mask) {
        this.computedAdjMaskValues = this.decodeTiles(payload.computed_adj_mask, "u8")
      }
      if (payload.render_mode) {
        this.renderMode = payload.render_mode
      }
      if (payload.layer_visibility) {
        this.layerVisibility = payload.layer_visibility
      }
      if (payload.layer_opacity) {
        this.layerOpacity = payload.layer_opacity
      }
      if (Object.prototype.hasOwnProperty.call(payload, "phase_index")) {
        this.phaseIndex = this.normalizePhaseIndex(payload.phase_index)
      }
      if (Object.prototype.hasOwnProperty.call(payload, "snapshot_mode")) {
        this.snapshotMode = this.parseBool(payload.snapshot_mode, this.snapshotMode)
      }
      if (Object.prototype.hasOwnProperty.call(payload, "debug_terrain_kinds")) {
        this.debugTerrainKinds = this.parseBool(payload.debug_terrain_kinds, this.debugTerrainKinds)
      }
      if (Object.prototype.hasOwnProperty.call(payload, "debug_coast_audit")) {
        this.debugCoastAudit = this.parseBool(payload.debug_coast_audit, this.debugCoastAudit)
        this.debugMomimeMask = this.debugCoastAudit
      }
      if (Object.prototype.hasOwnProperty.call(payload, "debug_shore_semantics")) {
        this.debugShoreSemantics = this.parseBool(payload.debug_shore_semantics, this.debugShoreSemantics)
      }
      if (Object.prototype.hasOwnProperty.call(payload, "debug_terrain_samples")) {
        this.debugTerrainSamples = this.parseBool(payload.debug_terrain_samples, this.debugTerrainSamples)
      }
      if (Object.prototype.hasOwnProperty.call(payload, "debug_momime_mask")) {
        this.debugMomimeMask = this.parseBool(payload.debug_momime_mask, this.debugMomimeMask)
        this.debugCoastAudit = this.debugMomimeMask
      }
      if (payload.terrain) {
        this.detectTerrainBaseSource()
      }
      this.maybeLogTerrainSamples()
      this.renderAll()
    })

    this.handleEvent("engine_delta", payload => {
      if (!payload || !Array.isArray(payload.changes)) return
      if (payload.delta_type && payload.delta_type !== "tile_set") return

      const layer = payload.layer || this.activeLayer
      if (payload.layer_type) {
        this.layerType = payload.layer_type
      }

      payload.changes.forEach(change => {
        const x = change.x
        const y = change.y
        const value = change.new ?? change.value
        if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(value)) return

        const idx = y * this.mapWidth + x
        if (idx < 0 || idx >= this.values.length) return

        if (layer === this.activeLayer) {
          this.values[idx] = value
        }
        if (layer === "terrain") {
          this.terrainValues[idx] = value
        }
        if (layer === "terrain_flags") {
          this.terrainFlags[idx] = value
        }
        if (layer === "minerals") {
          this.mineralsValues[idx] = value
        }
        if (layer === "exploration") {
          this.explorationValues[idx] = value
        }
        if (layer === "landmass") {
          this.landmassValues[idx] = value
        }
        if (layer === "computed_adj_mask") {
          this.computedAdjMaskValues[idx] = value
        }

        if (this.renderMode === "tiles" && this.hasTileAssets()) {
          if (layer === "terrain") {
            this.redrawNeighborhood(x, y)
          } else if (this.isLayerVisible(layer)) {
            this.drawStackedTile(x, y)
          }
        } else if (layer === this.activeLayer) {
          this.drawTile(x, y, value)
        }
      })
    })

    this.handleEvent("tile_updates", payload => {
      if (!payload || !Array.isArray(payload.updates)) return
      this.layerType = payload.layer_type || this.layerType
      payload.updates.forEach(update => {
        const idx = update.y * this.mapWidth + update.x
        if (idx < 0 || idx >= this.values.length) return
        this.values[idx] = update.value
        if (payload.layer === "terrain") {
          this.terrainValues[idx] = update.value
        }
        if (payload.layer === "terrain_flags") {
          this.terrainFlags[idx] = update.value
        }
        if (payload.layer === "minerals") {
          this.mineralsValues[idx] = update.value
        }
        if (payload.layer === "exploration") {
          this.explorationValues[idx] = update.value
        }
        if (payload.layer === "landmass") {
          this.landmassValues[idx] = update.value
        }
        if (payload.layer === "computed_adj_mask") {
          this.computedAdjMaskValues[idx] = update.value
        }
        if (this.renderMode === "tiles" && this.hasTileAssets()) {
          if (payload.layer === "terrain") {
            this.redrawNeighborhood(update.x, update.y)
          } else if (this.isLayerVisible(payload.layer)) {
            this.drawStackedTile(update.x, update.y)
          }
        } else {
          this.drawTile(update.x, update.y, update.value)
        }
      })
    })

    this.handleEvent("tile_assets", payload => {
      if (!payload) return
      const prevBackend = this.tileBackend
      const prevBaseUrl = this.momimeBaseUrl
      const prevCache = this.momimeImageCache || {}
      this.tileBackend = payload.backend || this.tileBackend || "lbx"
      this.terrainGroups = payload.terrain_groups || {}
      this.overlayGroups = payload.overlay_groups || {}
      this.terrainNames = payload.terrain_names || {}
      this.terrainFlagNames = payload.terrain_flag_names || {}
      this.terrainKindOverrides = payload.terrain_kind_overrides || {}
      const momime = payload.momime || {}
      this.momimeIndex = momime.index || {}
      this.momimeFrames = momime.frames || {}
      this.momimeBaseUrl = momime.base_url || ""
      this.buildMomimeMaskWhitelist()
      const shouldClearCache =
        payload.clear_cache === true ||
        prevBackend !== this.tileBackend ||
        (this.tileBackend === "momime_png" && prevBaseUrl && prevBaseUrl !== this.momimeBaseUrl)
      this.momimeImageCache = shouldClearCache ? {} : prevCache
      if (Array.isArray(payload.terrain_water_values)) {
        this.terrainWaterValues = payload.terrain_water_values
        this.terrainWaterValueSet = new Set(this.terrainWaterValues)
      }
      this.tileImages = this.buildTileImages(payload.images || {})
      this.momimeMaskRotationStats = {0: 0, 90: 0, 180: 0, 270: 0}
      this.detectTerrainBaseSource()
      this.maybeLogTerrainSamples()
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

  maybeLogTerrainSamples() {
    if (!(this.debugTerrainSamples || this.debugTerrainKinds) || this.terrainSampleLogged) {
      return
    }
    if (!this.terrainValues || this.terrainValues.length === 0) return
    this.logTerrainSamples()
  },

  logTerrainSamples() {
    const samples = []
    const maxSamples = 50
    const total = this.mapWidth * this.mapHeight
    let attempts = 0
    const maxAttempts = maxSamples * 20

    this.detectTerrainBaseSource()

    while (samples.length < maxSamples && attempts < maxAttempts) {
      const idx = Math.floor(Math.random() * total)
      const x = idx % this.mapWidth
      const y = Math.floor(idx / this.mapWidth)
      const value = this.terrainValues[idx] || 0
      const baseKind = this.terrainBaseKindForValue(value)
      if (baseKind === "ocean") {
        attempts++
        continue
      }
      const lo = value & 0xff
      const hi = (value >> 8) & 0xff
      const baseValue = this.terrainBaseValue(value)
      const kind = this.terrainKindAt(x, y, value)
      samples.push({
        x,
        y,
        value,
        lo,
        hi,
        base_value: baseValue,
        kind,
        base_kind: baseKind,
        base_source: this.terrainBaseSourceForValue(value),
      })
      attempts++
    }

    if (samples.length > 0) {
      console.info("[mirror] terrain u16 samples", samples)
      if (this.terrainBaseSourceStats) {
        console.info("[mirror] terrain base source", this.terrainBaseSourceStats)
      }
    }

    this.terrainSampleLogged = true
  },

  detectTerrainBaseSource() {
    if (!this.terrainValues || this.terrainValues.length === 0) return

    const maxSamples = Math.min(800, this.terrainValues.length)
    const sampleCount = Math.max(200, Math.floor(maxSamples))
    const candidates = this.terrainBaseCandidates()
    const results = candidates.map(candidate => {
      return this.sampleTerrainBaseCandidate(candidate, sampleCount)
    })

    results.sort((a, b) => b.score - a.score)
    const best = results[0] || {label: "lo"}

    this.terrainBaseSource = best.label
    this.terrainBaseSourceStats = {
      source: best.label,
      sampleCount,
      candidates: results,
    }
  },

  byteStats(map, total) {
    let top = {value: null, count: 0}
    let unique = 0
    map.forEach((count, value) => {
      unique += 1
      if (count > top.count) top = {value, count}
    })
    const topRatio = total > 0 ? top.count / total : 0
    return {
      uniqueCount: unique,
      topValue: top.value,
      topCount: top.count,
      topRatio: Number.isFinite(topRatio) ? Math.round(topRatio * 1000) / 1000 : 0,
    }
  },

  terrainBaseCandidates() {
    return [
      {label: "lo", extract: value => value & 0xff},
      {label: "hi", extract: value => (value >> 8) & 0xff},
      {label: "lo_nibble", extract: value => value & 0x0f},
      {label: "hi_nibble", extract: value => (value >> 8) & 0x0f},
    ]
  },

  sampleTerrainBaseCandidate(candidate, sampleCount) {
    const baseCounts = new Map()
    const kindCounts = new Map()
    let knownCount = 0
    let unknownCount = 0

    for (let i = 0; i < sampleCount; i++) {
      const idx = Math.floor(Math.random() * this.terrainValues.length)
      const value = this.terrainValues[idx] || 0
      const base = candidate.extract(value)
      baseCounts.set(base, (baseCounts.get(base) || 0) + 1)
      const kind = this.terrainKindForBaseId(base, {allowWater: true})
      if (kind) {
        knownCount += 1
        kindCounts.set(kind, (kindCounts.get(kind) || 0) + 1)
      } else {
        unknownCount += 1
      }
    }

    const total = Math.max(1, sampleCount)
    const knownRatio = knownCount / total
    const baseStats = this.byteStats(baseCounts, total)
    const distinctKinds = kindCounts.size
    const score = knownRatio * 100 + distinctKinds * 8 - baseStats.topRatio * 30

    return {
      label: candidate.label,
      score: Math.round(score * 100) / 100,
      knownCount,
      unknownCount,
      knownRatio: Math.round(knownRatio * 1000) / 1000,
      distinctKindCount: distinctKinds,
      baseStats,
    }
  },

  drawTile(x, y, value) {
    if (this.renderMode === "tiles" && this.hasTileAssets()) {
      this.drawStackedTile(x, y)
    } else {
      this.drawValueTile(x, y, value)
    }
  },
  drawTileForLayer(x, y, value) {
    if (this.renderMode === "tiles" && this.hasTileAssets()) {
      this.drawStackedTile(x, y)
      return
    }

    if (this.activeLayer === "terrain") {
      this.drawTerrainTile(x, y)
      return
    }

    if (this.activeLayer === "minerals") {
      this.drawMineralTile(x, y)
      return
    }

    if (this.activeLayer === "terrain_flags") {
      this.drawValueTile(x, y, value)
      return
    }

    this.drawValueTile(x, y, value)
  },

  renderAll() {
    this.ctx.setTransform(1, 0, 0, 1, 0, 0)
    if (this.renderMode === "tiles" && this.hasTileAssets()) {
      this.renderTilesForLayer()
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

  renderTilesForLayer() {
    this.renderLayerStack()
  },

  renderValues() {
    for (let y = 0; y < this.mapHeight; y++) {
      for (let x = 0; x < this.mapWidth; x++) {
        const idx = y * this.mapWidth + x
        this.drawValueTile(x, y, this.values[idx])
      }
    }
  },

  renderTerrainTiles(render) {
    for (let y = 0; y < this.mapHeight; y++) {
      for (let x = 0; x < this.mapWidth; x++) {
        this.drawTerrainTile(x, y, render)
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

  renderTiles() {
    for (let y = 0; y < this.mapHeight; y++) {
      for (let x = 0; x < this.mapWidth; x++) {
        this.drawTileArt(x, y)
      }
    }
  },

  renderFlagTiles() {
    this.renderValues()
  },

  renderMineralTiles(render) {
    const resolved = this.resolveRender(render)
    this.fillBackground(resolved.ctx, resolved.size)

    for (let y = 0; y < this.mapHeight; y++) {
      for (let x = 0; x < this.mapWidth; x++) {
        this.drawMineralTile(x, y, resolved)
      }
    }
  },

  hasTileAssets() {
    if (this.tileBackend === "momime_png") {
      return this.momimeIndex && Object.keys(this.momimeIndex).length > 0
    }
    return this.tileImages && Object.keys(this.tileImages).length > 0
  },

  buildTileImages(images) {
    const result = {}
    Object.entries(images).forEach(([key, image]) => {
      const width = image.width
      const height = image.height
      const bytes = Uint8ClampedArray.from(atob(image.rgba), char => char.charCodeAt(0))
      const canvas = document.createElement("canvas")
      canvas.width = width
      canvas.height = height
      const ctx = canvas.getContext("2d")
      const imageData = new ImageData(bytes, width, height)
      ctx.putImageData(imageData, 0, 0)
      result[key] = {canvas, width, height}
    })
    return result
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

  drawTerrainTile(x, y, render) {
    this.drawTileArt(x, y, {includeOverlays: true, render})
  },

  drawTerrainBase(x, y, render) {
    const resolved = this.resolveRender(render)
    this.drawTileArt(x, y, {includeOverlays: false, render: resolved})
    this.drawFeatureOverlays(x, y, resolved)
    this.drawEmbeddedSpecialOverlay(x, y, resolved)
    if (this.debugTerrainKinds || this.debugShoreSemantics) {
      const kind = this.terrainKindAt(x, y)
      if (this.debugTerrainKinds) {
        this.drawTerrainKindDebug(x, y, kind, resolved)
      }
      if (this.debugShoreSemantics && kind === "shore") {
        const shoreDigits = this.shoreMaskDigits(x, y)
        this.drawShoreSemanticsDebug(x, y, shoreDigits, resolved)
      }
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

  drawTileArt(x, y, options = {}) {
    const render = this.resolveRender(options.render)
    const includeOverlays = options.includeOverlays !== false
    if (this.tileBackend === "momime_png") {
      const drawn = this.drawMomimeBaseTile(x, y, render)
      if (!drawn) {
        this.drawMissingTile(x, y, render, "missing")
      }
      if (includeOverlays) {
        this.drawOverlays(x, y, render)
      }
      return
    }

    const idx = y * this.mapWidth + x
    const terrainValue = this.terrainValues[idx] || 0
    const kind = this.terrainKindAt(x, y, terrainValue)
    if (!kind || kind === "unknown") {
      this.drawMissingTile(x, y, render, "unknown")
      if (includeOverlays) {
        this.drawOverlays(x, y, render)
      }
      return
    }
    const entry = this.terrainSpriteRef(kind, x, y, idx, render)

    if (!entry || !this.drawImageEntry(entry, x, y, render)) {
      this.drawValueTile(x, y, this.values[idx], render)
    }

    if (includeOverlays) {
      this.drawOverlays(x, y, render)
    }
  },

  drawOverlays(x, y, render) {
    const resolved = this.resolveRender(render)
    this.drawFeatureOverlays(x, y, resolved)
    this.drawFlagOverlays(x, y, resolved)
    this.drawSpecialOverlays(x, y, resolved)
  },

  drawFeatureOverlays(x, y, render) {
    const kind = this.terrainKindAt(x, y)
    const idx = y * this.mapWidth + x
    const groupNames = this.featureGroupNames(kind)
    const entry = this.pickOverlayEntry(groupNames, "interior", idx, render)
    if (entry) {
      this.drawImageEntry(entry, x, y, render)
    }
  },

  drawFlagOverlays(x, y, render) {
    const idx = y * this.mapWidth + x
    const flags = this.terrainFlags[idx] || 0
    if (!flags) return

    for (let bit = 0; bit < 8; bit++) {
      if ((flags & (1 << bit)) === 0) continue
      const baseGroup = this.flagBaseGroup(bit)
      const mask = this.adjMaskForFlag(bit, x, y)
      const edgeClass = this.edgeClassFromMask(mask, {mode: "same"})
      const groupNames = this.overlayGroupNames(baseGroup, edgeClass)
      const entry = this.pickOverlayEntry(groupNames, edgeClass, idx, render)
      if (entry) {
        this.drawImageEntry(entry, x, y, render)
      }
    }
  },

  drawSpecialOverlays(x, y, render) {
    this.drawMineralOverlay(x, y, render)
    this.drawEmbeddedSpecialOverlay(x, y, render)
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

  drawLayerOverlay(layer, x, y, render) {
    switch (layer) {
      case "terrain_flags":
        this.drawFlagOverlays(x, y, render)
        break
      case "minerals":
        this.drawMineralOverlay(x, y, render)
        break
      case "exploration":
      case "landmass":
      case "computed_adj_mask": {
        const values = this.layerValues(layer)
        if (!values) return
        const idx = y * this.mapWidth + x
        const value = values[idx] || 0
        this.drawValueTile(x, y, value, render, this.layerTypeFor(layer))
        break
      }
      default:
        break
    }
  },

  drawMineralTile(x, y, render) {
    this.fillTileBackground(x, y, render)
    this.drawMineralOverlay(x, y, render)
  },

  drawMineralOverlay(x, y, render) {
    const resolved = this.resolveRender(render)
    const idx = y * this.mapWidth + x
    const mineral = this.mineralsValues[idx] || 0
    if (mineral <= 0) return

    const groupNames = this.overlayGroupNames(`resource_${mineral}`, "interior").concat(
      this.overlayGroupNames("resource", "interior")
    )
    const overlayEntry = this.pickOverlayEntry(groupNames, "interior", idx, resolved)
    if (overlayEntry) {
      this.drawImageEntry(overlayEntry, x, y, resolved)
    }
  },

  terrainSpriteRef(kind, x, y, seed, render) {
    if (!kind || kind === "unknown") return null
    const mask = kind === "ocean" ? 0 : this.adjMaskForKind(kind, x, y)
    const edgeClass = this.edgeClassForKind(kind, mask)
    return this.pickTerrainEntry(kind, edgeClass, seed, render)
  },

  pickTerrainEntry(kind, edgeClass, seed, render) {
    const groupNames = this.groupNamesForKind(kind, edgeClass)
    return this.pickEntryFromGroups(this.terrainGroups, groupNames, edgeClass, seed, render)
  },

  pickOverlayEntry(groupNames, edgeClass, seed, render) {
    return this.pickEntryFromGroups(this.overlayGroups, groupNames, edgeClass, seed, render)
  },

  pickEntryFromGroups(groups, groupNames, edgeClass, seed, render) {
    if (!groups || !groupNames || groupNames.length === 0) return null
    const uniqueNames = this.uniqueGroupNames(groupNames)

    for (let i = 0; i < uniqueNames.length; i++) {
      const group = uniqueNames[i]
      const entries = groups[group] || []
      if (entries.length === 0) continue
      const edgeEntries = edgeClass ? this.entriesForEdgeClass(entries, edgeClass) : []
      const pool = edgeEntries.length ? edgeEntries : entries
      const entry = this.pickEntryFromPool(pool, seed, render)
      if (entry) return entry
    }

    return null
  },

  pickEntryFromPool(entries, seed, render) {
    if (!entries || entries.length === 0) return null
    const resolved = this.resolveRender(render)

    if (resolved.usePhase) {
      const phaseEntry = this.pickPhaseEntry(entries, resolved.phaseIndex)
      if (phaseEntry) return phaseEntry
    }

    return entries[seed % entries.length]
  },

  entriesForEdgeClass(entries, edgeClass) {
    if (!edgeClass) return []
    return entries.filter(entry => this.variantMatchesEdge(entry.variant, edgeClass))
  },

  variantMatchesEdge(variant, edgeClass) {
    if (!variant || !edgeClass) return false
    const text = String(variant).toLowerCase()
    const edgeText = String(edgeClass).toLowerCase()
    if (text === edgeText) return true
    if (text.includes(edgeText)) return true
    const alias = this.edgeClassAlias(edgeClass)
    if (alias) {
      const aliasText = alias.toLowerCase()
      if (text === aliasText) return true
      const regex = new RegExp(`(^|\\D)${aliasText}(\\D|$)`)
      return regex.test(text)
    }
    return false
  },

  edgeClassAlias(edgeClass) {
    switch (edgeClass) {
      case "edge_n":
        return "N"
      case "edge_e":
        return "E"
      case "edge_s":
        return "S"
      case "edge_w":
        return "W"
      case "corner_ne":
        return "NE"
      case "corner_nw":
        return "NW"
      case "corner_se":
        return "SE"
      case "corner_sw":
        return "SW"
      case "edge_ns":
        return "NS"
      case "edge_ew":
        return "EW"
      case "peninsula_n":
        return "PEN_N"
      case "peninsula_e":
        return "PEN_E"
      case "peninsula_s":
        return "PEN_S"
      case "peninsula_w":
        return "PEN_W"
      default:
        return null
    }
  },

  normalizeGroupToken(value) {
    return String(value || "")
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "_")
      .replace(/^_+|_+$/g, "")
  },

  featureGroupNames(kind) {
    if (!kind || kind === "unknown") return []
    const token = this.normalizeGroupToken(kind)
    return this.uniqueGroupNames([
      `feature_${token}`,
      `${token}_feature`,
      "feature"
    ])
  },

  flagBaseGroup(bit) {
    const name = this.normalizeGroupToken(this.terrainFlagNames?.[String(bit)])
    if (name) return `flag_${name}`
    return `flag_${bit}`
  },

  overlayGroupNames(baseGroup, edgeClass) {
    if (!baseGroup) return []
    const names = []
    const normalized = this.normalizeGroupToken(baseGroup)
    const edge = edgeClass && edgeClass !== "interior" ? edgeClass : null
    if (edge) {
      names.push(`${normalized}_${edge}`)
      const alias = this.edgeClassAlias(edge)
      if (alias) names.push(`${normalized}_${alias}`)
    } else {
      names.push(`${normalized}_interior`)
    }
    names.push(normalized)
    return this.uniqueGroupNames(names)
  },

  uniqueGroupNames(names) {
    const seen = new Set()
    return names.filter(name => {
      if (!name) return false
      if (seen.has(name)) return false
      seen.add(name)
      return true
    })
  },

  parsePhaseTag(variant) {
    if (!variant) return null
    const match = String(variant).match(/phase[_:-]?(\d+)/i)
    if (!match) return null
    const parsed = parseInt(match[1], 10)
    return Number.isFinite(parsed) ? parsed : null
  },

  pickPhaseEntry(entries, phaseIndex) {
    if (!entries || entries.length === 0) return null
    if (entries.length === 1) return entries[0]

    const phaseTagged = entries
      .map(entry => ({entry, phase: this.parsePhaseTag(entry.variant)}))
      .filter(item => item.phase !== null)

    if (phaseTagged.length > 0) {
      const phases = [...new Set(phaseTagged.map(item => item.phase))].sort((a, b) => a - b)
      const phase = phases[phaseIndex % phases.length]
      const match = phaseTagged.find(item => item.phase === phase)
      return match ? match.entry : phaseTagged[0].entry
    }

    return entries[phaseIndex % entries.length]
  },

  drawImageEntry(entry, x, y, render) {
    const {ctx, size} = this.resolveRender(render)
    const image = this.tileImages[entry.key]
    if (!image) return false
    ctx.drawImage(
      image.canvas,
      x * size,
      y * size,
      size,
      size
    )
    return true
  },

  maskString(mask) {
    const value = Number.isFinite(mask) ? mask : 0
    let result = ""
    for (let i = 0; i < 8; i++) {
      result += value & (1 << i) ? "1" : "0"
    }
    return result
  },

  maskStringFromDigits(digits) {
    if (!digits || digits.length !== 8) return "00000000"
    return digits.join("")
  },

  normalizeMaskString(maskString) {
    return String(maskString || "").padStart(8, "0").slice(0, 8)
  },

  rotateMaskString(maskString, shift) {
    const digits = this.normalizeMaskString(maskString).split("")
    return this.rotateMaskDigits(digits, shift).join("")
  },

  maskRotations(maskString) {
    const normalized = this.normalizeMaskString(maskString)
    const rotations = [
      {maskString: normalized, rotation: 0, shift: 0},
      {maskString: this.rotateMaskString(normalized, 2), rotation: 90, shift: 2},
      {maskString: this.rotateMaskString(normalized, 4), rotation: 180, shift: 4},
      {maskString: this.rotateMaskString(normalized, 6), rotation: 270, shift: 6},
    ]
    const seen = new Set()
    return rotations.filter(entry => {
      if (seen.has(entry.maskString)) return false
      seen.add(entry.maskString)
      return true
    })
  },

  canonicalMaskString(maskString) {
    const rotations = this.maskRotations(maskString)
    rotations.sort((a, b) => a.maskString.localeCompare(b.maskString))
    return rotations[0] || {maskString: this.normalizeMaskString(maskString), rotation: 0}
  },

  reduceDiagonalMaskString(maskString, fromDigit, toDigit) {
    const chars = this.normalizeMaskString(maskString).split("")
    const from = String(fromDigit)
    const to = String(toDigit)
    ;[1, 3, 5, 7].forEach(index => {
      if (chars[index] === from) chars[index] = to
    })
    return chars.join("")
  },

  clearDiagonalMaskString(maskString) {
    const chars = this.normalizeMaskString(maskString).split("")
    chars[1] = "0"
    chars[3] = "0"
    chars[5] = "0"
    chars[7] = "0"
    return chars.join("")
  },

  gateDiagonalMask(mask) {
    let value = Number.isFinite(mask) ? mask : 0
    const has = bit => (value & (1 << bit)) !== 0
    if (has(1) && !(has(0) && has(2))) value &= ~(1 << 1)
    if (has(3) && !(has(2) && has(4))) value &= ~(1 << 3)
    if (has(5) && !(has(4) && has(6))) value &= ~(1 << 5)
    if (has(7) && !(has(6) && has(0))) value &= ~(1 << 7)
    return value
  },

  gateDiagonalDigits(digits) {
    const next = Array.isArray(digits) ? digits.slice(0, 8) : Array(8).fill("0")
    const present = idx => (next[idx] ?? "0") !== "0"
    const rewriteDiagonal = (diag, a, b) => {
      if (!present(diag)) return
      if (!(present(a) && present(b))) {
        next[diag] = "2"
      } else if (next[diag] !== "2") {
        next[diag] = "1"
      }
    }
    rewriteDiagonal(1, 0, 2)
    rewriteDiagonal(3, 2, 4)
    rewriteDiagonal(5, 4, 6)
    rewriteDiagonal(7, 6, 0)
    return next
  },

  rotateMaskDigits(digits, shift) {
    const list = Array.isArray(digits) ? digits : []
    const offset = ((shift % 8) + 8) % 8
    if (offset === 0) return list.slice(0, 8)
    const rotated = Array(8).fill("0")
    for (let i = 0; i < 8; i++) {
      rotated[(i + offset) % 8] = list[i] ?? "0"
    }
    return rotated
  },

  shoreMaskDigits(x, y) {
    const digits = Array(8).fill("0")
    const land = Array(8).fill(false)

    for (let i = 0; i < SHORE_MASK_DIRS.length; i++) {
      const [dx, dy] = SHORE_MASK_DIRS[i]
      let nx = x + dx
      let ny = y + dy
      if (ny < 0 || ny >= this.mapHeight) continue
      if (nx < 0) nx += this.mapWidth
      if (nx >= this.mapWidth) nx -= this.mapWidth

      const baseKind = this.terrainBaseKindAt(nx, ny)
      land[i] = !this.isWaterKind(baseKind)
    }

    for (let i = 0; i < land.length; i++) {
      if (i % 2 === 0) {
        digits[i] = land[i] ? "1" : "0"
        continue
      }

      const left = (i + 7) % 8
      const right = (i + 1) % 8
      if (land[left] && land[right]) {
        digits[i] = "1"
      } else if (land[i]) {
        digits[i] = "2"
      } else {
        digits[i] = "0"
      }
    }

    return digits
  },

  normalizeShoreMaskDigits(maskDigits) {
    if (Array.isArray(maskDigits)) {
      const next = maskDigits.slice(0, 8).map(value => String(value ?? "0"))
      while (next.length < 8) next.push("0")
      return next.map(value => (value === "1" || value === "2" ? value : "0"))
    }
    const normalized = this.normalizeMaskString(maskDigits)
    return normalized.split("").map(value => (value === "1" || value === "2" ? value : "0"))
  },

  cardinalAdjacent(a, b) {
    return (a + 1) % 4 === b || (b + 1) % 4 === a
  },

  cornerDiagonalForCardinals(a, b) {
    const min = Math.min(a, b)
    const max = Math.max(a, b)
    if (min === 0 && max === 1) return 1
    if (min === 1 && max === 2) return 3
    if (min === 2 && max === 3) return 5
    if (min === 0 && max === 3) return 7
    return null
  },

  classifyShoreSemantics(maskDigits) {
    const digits = this.normalizeShoreMaskDigits(maskDigits)
    const cardinalDigits = [digits[0], digits[2], digits[4], digits[6]]
    const cardinalLand = cardinalDigits.map(value => value !== "0")
    const waterCardinals = cardinalLand.map(value => !value)
    const waterIndices = []
    waterCardinals.forEach((isWater, index) => {
      if (isWater) waterIndices.push(index)
    })
    const waterCount = waterIndices.length
    const diagonalWater = [digits[1], digits[3], digits[5], digits[7]].some(value => value === "0")
    let semantic = "straight_edge"
    let cornerDiagonal = null

    if (waterCount === 0) {
      semantic = diagonalWater ? "convex_corner" : "straight_edge"
    } else if (waterCount === 1) {
      semantic = "straight_edge"
    } else if (waterCount === 2) {
      const [a, b] = waterIndices
      if (!this.cardinalAdjacent(a, b)) {
        semantic = "channel"
      } else {
        cornerDiagonal = this.cornerDiagonalForCardinals(a, b)
        const diagDigit = cornerDiagonal === null ? "0" : digits[cornerDiagonal] ?? "0"
        semantic = diagDigit !== "0" ? "concave_inlet" : "convex_corner"
      }
    } else if (waterCount === 3) {
      semantic = "peninsula"
    } else if (waterCount === 4) {
      semantic = "island_tip"
    }

    return {
      class: semantic,
      waterCount,
      waterIndices,
      cornerDiagonal,
      digits,
    }
  },

  shoreSemanticFallbacks(maskString, semanticClass) {
    const normalized = this.normalizeMaskString(maskString)
    const baseDigits = normalized.split("")
    const seen = new Set([normalized])
    const variants = []
    const diagLabels = {1: "ne", 3: "se", 5: "sw", 7: "nw"}
    const diagOrder = [1, 3, 5, 7]

    const pushVariant = (digits, step) => {
      const candidate = digits.join("")
      if (seen.has(candidate)) return
      const candidateClass = this.classifyShoreSemantics(candidate).class
      if (candidateClass !== semanticClass) return
      variants.push({maskString: candidate, step})
      seen.add(candidate)
    }

    diagOrder.forEach(index => {
      if (baseDigits[index] === "2") {
        const next = baseDigits.slice(0)
        next[index] = "1"
        pushVariant(next, `relax_diag_2_to_1_${diagLabels[index]}`)
      }
    })

    diagOrder.forEach(index => {
      if (baseDigits[index] === "2") {
        const next = baseDigits.slice(0)
        next[index] = "0"
        pushVariant(next, `relax_diag_2_to_0_${diagLabels[index]}`)
      }
    })

    diagOrder.forEach(index => {
      if (baseDigits[index] === "1") {
        const next = baseDigits.slice(0)
        next[index] = "0"
        pushVariant(next, `relax_diag_1_to_0_${diagLabels[index]}`)
      }
    })

    const reduced2to1 = this.reduceDiagonalMaskString(normalized, "2", "1")
    if (reduced2to1 !== normalized) {
      pushVariant(reduced2to1.split(""), "relax_diagonals_2_to_1")
    }

    const reduced2to0 = this.reduceDiagonalMaskString(normalized, "2", "0")
    if (reduced2to0 !== normalized) {
      pushVariant(reduced2to0.split(""), "relax_diagonals_2_to_0")
    }

    const reduced1to0 = this.reduceDiagonalMaskString(normalized, "1", "0")
    if (reduced1to0 !== normalized) {
      pushVariant(reduced1to0.split(""), "relax_diagonals_1_to_0")
    }

    return variants
  },

  shoreSemanticLabel(semantic) {
    return SHORE_SEMANTIC_LABELS[semantic] || SHORE_SEMANTIC_LABELS.unknown
  },

  drawShoreSemanticsDebug(x, y, maskDigits, render) {
    const {ctx, size} = this.resolveRender(render)
    const semantic = this.classifyShoreSemantics(maskDigits)
    const color = SHORE_SEMANTIC_COLORS[semantic.class] || SHORE_SEMANTIC_COLORS.unknown

    ctx.save()
    ctx.globalAlpha = 0.35
    ctx.fillStyle = color
    ctx.fillRect(x * size, y * size, size, size)
    ctx.restore()

    if (size >= 18) {
      ctx.save()
      ctx.font = `${Math.max(8, Math.floor(size / 4))}px sans-serif`
      ctx.fillStyle = "#0f172a"
      ctx.fillText(this.shoreSemanticLabel(semantic.class), x * size + 2, y * size + size - 4)
      ctx.restore()
    }
  },

  shoreMaskVariants(maskString) {
    const base = String(maskString || "")
    const variants = [base]
    if (base.includes("2")) {
      variants.push(base.replace(/2/g, "1"))
      variants.push(base.replace(/2/g, "0"))
    }
    return Array.from(new Set(variants))
  },

  buildMomimeMaskWhitelist() {
    const whitelist = {}
    const frames = this.momimeFrames || {}
    Object.keys(frames).forEach(key => {
      const [plane, kind, mask] = String(key).split("|")
      if (!plane || !kind || !mask) return
      if (!whitelist[plane]) whitelist[plane] = {}
      if (!whitelist[plane][kind]) whitelist[plane][kind] = new Set()
      whitelist[plane][kind].add(mask)
    })
    this.momimeMaskWhitelist = whitelist
  },

  maskWhitelistFor(plane, kind) {
    return this.momimeMaskWhitelist?.[plane]?.[kind] || null
  },

  maskSupported(plane, kind, maskString) {
    const whitelist = this.maskWhitelistFor(plane, kind)
    if (!whitelist) return true
    return whitelist.has(this.normalizeMaskString(maskString))
  },

  momimeBaseKey(plane, kind, mask) {
    return `${plane}|${kind}|${mask}`
  },

  momimeKey(plane, kind, mask, frame) {
    return `${plane}|${kind}|${mask}|${frame}`
  },

  pickMomimeFrame(frames, phaseIndex) {
    if (!frames || frames.length === 0) return "0"
    const usable = frames.filter(frame => frame !== "0")
    if (usable.length === 0) return "0"
    return usable[phaseIndex % usable.length]
  },

  pickMomimeFallbackFrame(frames) {
    if (!frames || frames.length === 0) return "0"
    const usable = frames.filter(frame => frame !== "0")
    return usable.length ? usable[0] : frames[0]
  },

  resolveMomimePath(plane, kind, mask, phaseIndex) {
    const baseKey = this.momimeBaseKey(plane, kind, mask)
    const frames = this.momimeFrames?.[baseKey] || []
    const frame = this.pickMomimeFrame(frames, phaseIndex)
    let path = this.momimeIndex?.[this.momimeKey(plane, kind, mask, frame)]
    if (path) return {path, frame}

    path = this.momimeIndex?.[this.momimeKey(plane, kind, mask, "0")]
    if (path) return {path, frame: "0"}

    if (frames.length > 0) {
      const anyFrame = this.pickMomimeFallbackFrame(frames)
      path = this.momimeIndex?.[this.momimeKey(plane, kind, mask, anyFrame)]
      if (path) return {path, frame: anyFrame}
    }

    return null
  },

  resolveMomimePathWithFrame(plane, kind, mask, frame) {
    const path = this.momimeIndex?.[this.momimeKey(plane, kind, mask, frame)]
    return path ? {path, frame} : null
  },

  resolveMomimePathForKind(plane, kind, mask, phaseIndex) {
    if (kind === "shore") {
      return this.resolveMomimePathForShore(plane, mask, phaseIndex)
    }
    const rawMaskString = this.normalizeMaskString(this.maskString(mask))
    let resolved = this.resolveMomimePath(plane, kind, rawMaskString, phaseIndex)
    if (resolved) {
      return {...resolved, maskString: rawMaskString, rotation: 0, fallbackStep: "exact"}
    }

    const canonical = this.canonicalMaskString(rawMaskString)
    if (canonical.maskString !== rawMaskString) {
      resolved = this.resolveMomimePath(plane, kind, canonical.maskString, phaseIndex)
      if (resolved) {
        return {
          ...resolved,
          maskString: canonical.maskString,
          rotation: canonical.rotation,
          fallbackStep: "canonical",
        }
      }
    }

    const cleared = this.clearDiagonalMaskString(canonical.maskString)
    if (cleared !== canonical.maskString) {
      resolved = this.resolveMomimePath(plane, kind, cleared, phaseIndex)
      if (resolved) {
        return {
          ...resolved,
          maskString: cleared,
          rotation: canonical.rotation,
          fallbackStep: "clear_diagonals",
        }
      }
    }

    return null
  },

  resolveMomimePathForShore(plane, maskDigits, phaseIndex, opts = {}) {
    const audit = opts.audit === true
    const recordMissing = opts.recordMissing ?? this.debugCoastAudit
    const rawMaskString = this.normalizeMaskString(this.maskStringFromDigits(maskDigits))
    const semantic = this.classifyShoreSemantics(maskDigits)
    const semanticClass = semantic.class
    const canonical = this.canonicalMaskString(rawMaskString)

    const attemptMask = (maskString, rotation, step) => {
      const resolved = this.resolveMomimePath(plane, "shore", maskString, phaseIndex)
      if (!resolved) return null
      return {
        ...resolved,
        maskString,
        rotation,
        fallbackStep: step,
        fallbackApplied: step !== "exact",
      }
    }

    const attemptWithCanonical = (maskString, step) => {
      let resolved = attemptMask(maskString, 0, step)
      if (resolved) return resolved
      const canonicalVariant = this.canonicalMaskString(maskString)
      if (canonicalVariant.maskString !== maskString) {
        resolved = attemptMask(canonicalVariant.maskString, canonicalVariant.rotation, step)
      }
      return resolved
    }

    let resolved = attemptMask(rawMaskString, 0, "exact")
    if (!resolved && canonical.maskString !== rawMaskString) {
      resolved = attemptMask(canonical.maskString, canonical.rotation, "canonical")
    }

    if (!resolved && this.coastDiagonalReduction) {
      const variants = this.shoreSemanticFallbacks(rawMaskString, semanticClass)
      for (let i = 0; i < variants.length; i++) {
        const variant = variants[i]
        resolved = attemptWithCanonical(variant.maskString, variant.step)
        if (resolved) break
      }
    }

    if (!resolved) {
      const fallback = this.resolveMomimePathWithFrame(plane, "shore", "00000000", "0")
      if (fallback) {
        if (this.debugCoastAudit) {
          const fallbackClass = this.classifyShoreSemantics("00000000").class
          if (fallbackClass !== semanticClass) {
            console.info("[mirror] coast semantic fallback crossed class", {
              rawMaskString,
              semantic_class: semanticClass,
              fallback_class: fallbackClass,
            })
          }
        }
        resolved = {
          ...fallback,
          maskString: "00000000",
          rotation: 0,
          fallbackStep: "fallback_zero",
          fallbackApplied: true,
        }
      }
    }

    const auditInfo = {
      rawMaskString,
      canonicalMaskString: canonical.maskString,
      canonicalRotation: canonical.rotation,
      semanticClass,
    }

    if (!resolved) {
      if (recordMissing) {
        this.recordCoastAuditMissing(plane, "shore", rawMaskString)
      }
      if (audit) {
        return {
          path: null,
          frame: null,
          maskString: null,
          rotation: 0,
          fallbackStep: "missing",
          fallbackApplied: true,
          ...auditInfo,
        }
      }
      return null
    }

    if (recordMissing && resolved.fallbackStep !== "exact") {
      this.recordCoastAuditMissing(plane, "shore", rawMaskString)
    }

    return {...resolved, ...auditInfo}
  },

  recordMomimeMaskRotation(kind, rotation) {
    if (!this.momimeMaskRotationStats) return
    const key = Number.isFinite(rotation) ? rotation : 0
    const stats = this.momimeMaskRotationStats
    stats[key] = (stats[key] || 0) + 1

    const total = Object.values(stats).reduce((sum, value) => {
      return sum + (Number.isFinite(value) ? value : 0)
    }, 0)

    if (!this.debugMomimeMask && total % this.momimeMaskRotationLogEvery !== 0) {
      return
    }

    console.info(`[mirror] momime mask rotations (${kind})`, {...stats})
  },

  recordCoastAuditMissing(plane, kind, maskString) {
    if (!plane || !kind) return
    const normalized = this.normalizeMaskString(maskString)
    const key = `${plane}|${kind}`
    let stats = this.coastAuditMissingStats[key]
    if (!stats) {
      stats = new Map()
      this.coastAuditMissingStats[key] = stats
    }
    stats.set(normalized, (stats.get(normalized) || 0) + 1)

    if (!this.debugCoastAudit) return
    const total = Array.from(stats.values()).reduce((sum, count) => sum + count, 0)
    if (!this.coastAuditMissingLogEvery || total % this.coastAuditMissingLogEvery !== 0) {
      return
    }
    this.logCoastAuditMissingStats(plane, kind, stats)
  },

  logCoastAuditMissingStats(plane, kind, stats) {
    if (!stats) return
    const top = Array.from(stats.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, 20)
      .map(([mask, count]) => ({mask, count}))
    console.info(`[mirror] shore missing masks (${plane}/${kind})`, top)
  },

  logCoastAudit(x, y) {
    if (!this.debugCoastAudit) return
    if (!Number.isFinite(x) || !Number.isFinite(y)) return
    if (x < 0 || y < 0 || x >= this.mapWidth || y >= this.mapHeight) return

    const idx = y * this.mapWidth + x
    const terrainValue = this.terrainValues[idx] || 0
    const kind = this.terrainKindAt(x, y, terrainValue)
    const baseKind = this.terrainBaseKindAt(x, y)
    if (kind !== "shore") {
      console.info("[mirror] coast audit", {x, y, kind, base_kind: baseKind, note: "not shore"})
      return
    }

    const neighbors = ADJ_DIRS.map(([dx, dy], index) => {
      let nx = x + dx
      let ny = y + dy
      if (ny < 0 || ny >= this.mapHeight) return null
      if (nx < 0) nx += this.mapWidth
      if (nx >= this.mapWidth) nx -= this.mapWidth
      const neighborValue = this.terrainValues[ny * this.mapWidth + nx] || 0
      const neighborKind = this.terrainKindAt(nx, ny, neighborValue)
      const neighborBase = this.terrainBaseKindAt(nx, ny)
      return {
        dir: ADJ_DIR_LABELS[index],
        x: nx,
        y: ny,
        kind: neighborKind,
        base_kind: neighborBase,
        water: this.isWaterKind(neighborBase),
      }
    }).filter(Boolean)

    const shoreDigits = this.shoreMaskDigits(x, y)
    const rawMaskString = this.maskStringFromDigits(shoreDigits)
    const canonical = this.canonicalMaskString(rawMaskString)
    const semantic = this.classifyShoreSemantics(shoreDigits)
    const plane = this.plane || "arcanus"
    const resolved = this.resolveMomimePathForShore(plane, shoreDigits, this.phaseIndex, {
      audit: true,
      recordMissing: false,
    })

    console.info("[mirror] coast audit", {
      tile: {x, y, kind, base_kind: baseKind},
      neighbors,
      raw_adjacency_digits: shoreDigits,
      raw_mask: rawMaskString,
      semantic_class: semantic.class,
      canonical_mask: canonical.maskString,
      canonical_rotation: canonical.rotation,
      used_mask: resolved?.maskString ?? null,
      used_rotation: resolved?.rotation ?? null,
      fallback_step: resolved?.fallbackStep ?? "missing",
      fallback_applied: resolved?.fallbackApplied ?? true,
      path: resolved?.path ?? null,
    })
  },

  momimeUrl(path) {
    if (!path) return null
    if (!this.momimeBaseUrl) return path
    return `${this.momimeBaseUrl}/${path}`
  },

  getMomimeImage(path) {
    const url = this.momimeUrl(path)
    if (!url) return null
    let entry = this.momimeImageCache[url]
    if (!entry) {
      const img = new Image()
      entry = {img, loaded: false, failed: false}
      img.onload = () => {
        entry.loaded = true
        this.renderAll()
      }
      img.onerror = () => {
        entry.failed = true
      }
      img.src = url
      this.momimeImageCache[url] = entry
    }
    return entry
  },

  drawMomimeImage(img, x, y, render) {
    const {ctx, size} = this.resolveRender(render)
    ctx.drawImage(
      img,
      x * size,
      y * size,
      size,
      size
    )
  },

  drawMomimeBaseTile(x, y, render) {
    const resolved = this.resolveRender(render)
    const idx = y * this.mapWidth + x
    const terrainValue = this.terrainValues[idx] || 0
    const kind = this.terrainKindAt(x, y, terrainValue)
    if (!kind || kind === "unknown") {
      this.drawMissingTile(x, y, resolved, "unknown")
      return true
    }

    const mask = kind === "ocean" ? 0 : this.adjMaskForKind(kind, x, y)
    let maskInput = mask
    let shoreMaskString = null
    if (kind === "shore") {
      const shoreDigits = this.shoreMaskDigits(x, y)
      maskInput = shoreDigits
      shoreMaskString = this.maskStringFromDigits(shoreDigits)
      this.logMomimeMaskSample(x, y, kind, mask, shoreMaskString)
    }
    const plane = this.plane || "arcanus"
    const resolvedPath = this.resolveMomimePathForKind(plane, kind, maskInput, resolved.phaseIndex)
    if (!resolvedPath) return false

    const imageEntry = this.getMomimeImage(resolvedPath.path)
    if (!imageEntry) return false
    if (imageEntry.failed) {
      this.drawMissingTile(x, y, resolved, "missing")
      return true
    }
    if (!imageEntry.loaded) {
      this.drawLoadingTile(x, y, resolved)
      return true
    }
    this.drawMomimeImage(imageEntry.img, x, y, resolved)
    return true
  },

  drawTerrainKindDebug(x, y, kind, render) {
    const {ctx, size} = this.resolveRender(render)
    const label = kind || "unknown"
    const color = TERRAIN_KIND_DEBUG_COLORS[label] || TERRAIN_KIND_DEBUG_COLORS.unknown

    ctx.save()
    ctx.globalAlpha = 0.35
    ctx.fillStyle = color
    ctx.fillRect(x * size, y * size, size, size)
    ctx.restore()

    if (size >= 18) {
      ctx.save()
      ctx.font = `${Math.max(8, Math.floor(size / 4))}px sans-serif`
      ctx.fillStyle = "#0f172a"
      ctx.fillText(label, x * size + 2, y * size + size - 4)
      ctx.restore()
    }
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

  drawLoadingTile(x, y, render) {
    const {ctx, size} = this.resolveRender(render)
    ctx.fillStyle = "#1f2937"
    ctx.fillRect(x * size, y * size, size, size)
    if (size >= 12) {
      ctx.fillStyle = "#e2e8f0"
      ctx.font = `${Math.max(8, Math.floor(size / 3))}px sans-serif`
      ctx.fillText("...", x * size + 2, y * size + size - 2)
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

  terrainKindAt(x, y, terrainValue) {
    const idx = y * this.mapWidth + x
    const value = terrainValue ?? this.terrainValues[idx] ?? 0
    const baseKind = this.terrainBaseKindForValue(value)

    if (baseKind === "ocean" || baseKind === "unknown") {
      return baseKind
    }

    if (baseKind === "shore") {
      return "shore"
    }

    if (this.isAdjacentToOcean(x, y)) {
      return "shore"
    }

    return baseKind
  },

  isWaterKind(kind) {
    return kind === "ocean" || kind === "shore"
  },

  terrainBaseKindAt(x, y) {
    const idx = y * this.mapWidth + x
    const value = this.terrainValues[idx] ?? 0
    return this.terrainBaseKindForValue(value)
  },

  terrainBaseKindForValue(value) {
    if (!Number.isFinite(value)) return "unknown"
    const base = this.terrainBaseValue(value)

    const baseKind = this.terrainKindForBaseId(base, {allowWater: true})
    if (baseKind) return baseKind

    return "unknown"
  },

  terrainKindForBaseId(base, opts = {}) {
    const allowWater = opts.allowWater !== false
    const override = this.terrainKindOverrides?.[String(base)]
    if (override) return this.normalizeKind(override)
    if (allowWater && this.terrainWaterValueSet && this.terrainWaterValueSet.has(base)) {
      return "ocean"
    }

    const mapped = this.terrainKindFromBaseId(base)
    if (mapped) return mapped

    const name = String(this.terrainNames?.[String(base)] || "").toLowerCase()
    if (name) {
      if (this.matchesKeyword(name, ["ocean", "sea", "water"])) return "ocean"
      if (this.matchesKeyword(name, ["shore", "coast", "beach"])) return "shore"
      if (this.matchesKeyword(name, ["forest", "woods", "jungle"])) return "forest"
      if (this.matchesKeyword(name, ["desert", "dune", "sand", "waste"])) return "desert"
      if (this.matchesKeyword(name, ["tundra", "snow", "ice"])) return "tundra"
      if (this.matchesKeyword(name, ["swamp", "marsh", "bog"])) return "swamp"
      if (this.matchesKeyword(name, ["hill", "hills", "highland"])) return "hill"
      if (this.matchesKeyword(name, ["mountain", "peak", "volcano", "crater"])) {
        return "mountain"
      }
      if (this.matchesKeyword(name, ["grass", "plain", "prairie", "grassland"])) return "grass"
    }

    return null
  },

  terrainBaseSourceForValue(value) {
    if (!Number.isFinite(value)) return "unknown"
    return this.terrainBaseSource || "lo"
  },

  terrainBaseValue(value) {
    if (!Number.isFinite(value)) return 0
    const lo = value & 0xff
    const hi = (value >> 8) & 0xff
    const source = this.terrainBaseSource || "lo"

    switch (source) {
      case "hi":
        return hi
      case "lo_nibble":
        return lo & 0x0f
      case "hi_nibble":
        return hi & 0x0f
      default:
        return lo
    }
  },

  terrainKindFromBaseId(base) {
    const kind = TERRAIN_KIND_BY_BASE_ID[base]
    return kind ? this.normalizeKind(kind) : null
  },

  normalizeKind(value) {
    const normalized = String(value || "").trim().toLowerCase()
    if (normalized === "") return "unknown"
    if (
      [
        "ocean",
        "shore",
        "grass",
        "forest",
        "desert",
        "tundra",
        "swamp",
        "hill",
        "mountain",
      ].includes(normalized)
    ) {
      return normalized
    }
    if (["grasslands", "grassland", "plains"].includes(normalized)) return "grass"
    if (["hills"].includes(normalized)) return "hill"
    if (["mountains"].includes(normalized)) return "mountain"
    if (["woods"].includes(normalized)) return "forest"
    if (["water", "sea"].includes(normalized)) return "ocean"
    return "unknown"
  },

  matchesKeyword(name, keywords) {
    return keywords.some(keyword => name.includes(keyword))
  },

  isAdjacentToOcean(x, y) {
    for (let i = 0; i < ADJ_DIRS.length; i++) {
      const [dx, dy] = ADJ_DIRS[i]
      let nx = x + dx
      let ny = y + dy
      if (ny < 0 || ny >= this.mapHeight) continue
      if (nx < 0) nx += this.mapWidth
      if (nx >= this.mapWidth) nx -= this.mapWidth
      if (this.terrainBaseKindAt(nx, ny) === "ocean") return true
    }

    return false
  },

  adjMaskForKind(kind, x, y) {
    if (!kind || kind === "unknown") return 0
    const useOceanMask = kind === "shore"
    let mask = 0

    for (let i = 0; i < ADJ_DIRS.length; i++) {
      const [dx, dy] = ADJ_DIRS[i]
      let nx = x + dx
      let ny = y + dy
      if (ny < 0 || ny >= this.mapHeight) continue
      if (nx < 0) nx += this.mapWidth
      if (nx >= this.mapWidth) nx -= this.mapWidth

      const neighborKind = useOceanMask ? this.terrainBaseKindAt(nx, ny) : this.terrainKindAt(nx, ny)
      const match = useOceanMask ? neighborKind === "ocean" : neighborKind === kind

      if (match) {
        mask |= 1 << i
      }
    }

    return this.gateDiagonalMask(mask)
  },

  rotateMask(mask, shift) {
    const normalized = Number.isFinite(mask) ? mask : 0
    const offset = ((shift % 8) + 8) % 8
    if (offset === 0) return normalized
    let result = 0
    for (let i = 0; i < 8; i++) {
      if (normalized & (1 << i)) {
        const next = (i + offset) % 8
        result |= 1 << next
      }
    }
    return result
  },

  rotate90(mask) {
    return this.rotateMask(mask, 2)
  },

  rotate180(mask) {
    return this.rotateMask(mask, 4)
  },

  rotate270(mask) {
    return this.rotateMask(mask, 6)
  },

  logMomimeMaskSample(x, y, kind, mask, maskString) {
    if (!this.debugMomimeMask) return
    if (this.momimeMaskSampleCount >= this.momimeMaskSampleLimit) return

    const resolvedMaskString = maskString || this.maskString(mask)
    const neighbors = ADJ_DIRS.map(([dx, dy], index) => {
      let nx = x + dx
      let ny = y + dy
      if (ny < 0 || ny >= this.mapHeight) return null
      if (nx < 0) nx += this.mapWidth
      if (nx >= this.mapWidth) nx -= this.mapWidth
      const neighborKind = this.terrainBaseKindAt(nx, ny)
      return {
        dir: ADJ_DIR_LABELS[index],
        x: nx,
        y: ny,
        kind: neighborKind,
        water: this.isWaterKind(neighborKind),
      }
    }).filter(Boolean)

    console.info("[mirror] momime mask sample", {
      x,
      y,
      kind,
      mask,
      maskString: resolvedMaskString,
      neighbors,
    })

    this.momimeMaskSampleCount += 1
  },

  adjMaskForFlag(bit, x, y) {
    if (bit < 0 || bit > 7) return 0
    let mask = 0

    for (let i = 0; i < ADJ_DIRS.length; i++) {
      const [dx, dy] = ADJ_DIRS[i]
      let nx = x + dx
      let ny = y + dy
      if (ny < 0 || ny >= this.mapHeight) continue
      if (nx < 0) nx += this.mapWidth
      if (nx >= this.mapWidth) nx -= this.mapWidth

      const idx = ny * this.mapWidth + nx
      const flags = this.terrainFlags[idx] || 0
      if ((flags & (1 << bit)) !== 0) {
        mask |= 1 << i
      }
    }

    return mask
  },

  edgeClassForKind(kind, mask) {
    const mode = kind === "shore" ? "presence" : "same"
    return this.edgeClassFromMask(mask, {mode})
  },

  edgeClassFromMask(mask, opts = {}) {
    const mode = opts.mode || "same"
    const card = this.cardinalMask(mask)
    const bits = mode === "presence" ? card : (card ^ 0b1111)
    const bitCount = this.countBits(bits)

    if (bitCount === 0 || bitCount === 4) return "interior"
    if (bitCount === 1) return `edge_${this.dirFromBits(bits)}`
    if (bitCount === 2) {
      const corner = this.cornerFromBits(bits)
      if (corner) return corner
      if (bits === 0b0101) return "edge_ns"
      if (bits === 0b1010) return "edge_ew"
    }
    if (bitCount === 3) {
      const missing = bits ^ 0b1111
      return `peninsula_${this.dirFromBits(missing)}`
    }

    return "fallback"
  },

  cardinalMask(mask) {
    let card = 0
    if (mask & (1 << 0)) card |= 0b0001
    if (mask & (1 << 2)) card |= 0b0010
    if (mask & (1 << 4)) card |= 0b0100
    if (mask & (1 << 6)) card |= 0b1000
    return card
  },

  countBits(value) {
    let count = 0
    let v = value
    while (v) {
      v &= v - 1
      count++
    }
    return count
  },

  dirFromBits(bits) {
    switch (bits) {
      case 0b0001:
        return "n"
      case 0b0010:
        return "e"
      case 0b0100:
        return "s"
      case 0b1000:
        return "w"
      default:
        return "n"
    }
  },

  cornerFromBits(bits) {
    switch (bits) {
      case 0b0011:
        return "corner_ne"
      case 0b1001:
        return "corner_nw"
      case 0b0110:
        return "corner_se"
      case 0b1100:
        return "corner_sw"
      default:
        return null
    }
  },

  groupNamesForKind(kind, edgeClass) {
    if (!kind || kind === "unknown") return []
    const base = this.normalizeGroupToken(kind)
    const names = []
    const edge = edgeClass && edgeClass !== "interior" ? edgeClass : null
    if (edge) {
      names.push(`${base}_${edge}`)
      const alias = this.edgeClassAlias(edge)
      if (alias) names.push(`${base}_${alias}`)
      names.push(`${base}_edge`)
    } else {
      names.push(`${base}_interior`)
    }
    names.push(base)
    names.push(`terrain_${base}`)
    return this.uniqueGroupNames(names)
  },

  drawEmbeddedSpecialOverlay(x, y, render) {
    const resolved = this.resolveRender(render)
    const idx = y * this.mapWidth + x
    const terrainValue = this.terrainValues[idx] || 0
    const embedded = this.terrainEmbeddedSpecialForValue(terrainValue)
    if (embedded <= 0) return

    const groupNames = this.overlayGroupNames(`special_${embedded}`, "interior").concat(
      this.overlayGroupNames("special", "interior")
    )
    const overlayEntry = this.pickOverlayEntry(groupNames, "interior", idx, resolved)
    if (overlayEntry) {
      this.drawImageEntry(overlayEntry, x, y, resolved)
    }
  },

  terrainEmbeddedSpecialForValue(value) {
    if (!Number.isFinite(value)) return 0
    const lo = value & 0xff
    const hi = (value >> 8) & 0xff
    const source = this.terrainBaseSourceForValue(value)
    return String(source).startsWith("hi") ? lo : hi
  },

  redrawNeighborhood(x, y) {
    for (let dy = -1; dy <= 1; dy++) {
      for (let dx = -1; dx <= 1; dx++) {
        let nx = x + dx
        let ny = y + dy
        if (ny < 0 || ny >= this.mapHeight) continue
        if (nx < 0) nx += this.mapWidth
        if (nx >= this.mapWidth) nx -= this.mapWidth
        this.drawStackedTile(nx, ny)
      }
    }
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

    if (!this.isPointerDown && this.debugCoastAudit) {
      this.logCoastAudit(tile.x, tile.y)
    }

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
