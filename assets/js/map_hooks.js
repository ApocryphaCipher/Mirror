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

const MapCanvas = {
  mounted() {
    this.tileSize = parseInt(this.el.dataset.tileSize || "12", 10)
    this.mapWidth = parseInt(this.el.dataset.mapWidth || "60", 10)
    this.mapHeight = parseInt(this.el.dataset.mapHeight || "40", 10)
    this.layerType = this.el.dataset.layerType || "u8"
    this.renderMode = this.el.dataset.renderMode || "values"
    this.activeLayer = this.el.dataset.layer || "terrain"
    this.phaseIndex = this.normalizePhaseIndex(this.el.dataset.phaseIndex)
    this.snapshotMode = this.parseBool(this.el.dataset.snapshotMode, true)
    this.values = this.decodeTiles(this.el.dataset.tiles || "", this.layerType)
    this.terrainValues = this.decodeTiles(this.el.dataset.terrain || "", "u16")
    this.terrainFlags = this.decodeTiles(this.el.dataset.terrainFlags || "", "u8")
    this.mineralsValues = this.decodeTiles(this.el.dataset.minerals || "", "u8")
    this.tileImages = {}
    this.terrainGroups = {}
    this.overlayGroups = {}
    this.terrainNames = {}
    this.terrainWaterValues = [0]
    this.terrainWaterValueSet = new Set(this.terrainWaterValues)
    this.terrainFlagNames = {}
    this.terrainKindOverrides = {}
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
      if (payload.layer) {
        this.activeLayer = payload.layer
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
      if (payload.render_mode) {
        this.renderMode = payload.render_mode
      }
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

        if (
          layer === "terrain" &&
          this.activeLayer === "terrain" &&
          this.renderMode === "tiles" &&
          this.hasTileAssets()
        ) {
          this.redrawNeighborhood(x, y)
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
        if (this.activeLayer === "terrain" && this.renderMode === "tiles" && this.hasTileAssets()) {
          this.redrawNeighborhood(update.x, update.y)
        } else {
          this.drawTile(update.x, update.y, update.value)
        }
      })
    })

    this.handleEvent("tile_assets", payload => {
      if (!payload) return
      this.terrainGroups = payload.terrain_groups || {}
      this.overlayGroups = payload.overlay_groups || {}
      this.terrainNames = payload.terrain_names || {}
      this.terrainFlagNames = payload.terrain_flag_names || {}
      this.terrainKindOverrides = payload.terrain_kind_overrides || {}
      if (Array.isArray(payload.terrain_water_values)) {
        this.terrainWaterValues = payload.terrain_water_values
        this.terrainWaterValueSet = new Set(this.terrainWaterValues)
      }
      this.tileImages = this.buildTileImages(payload.images || {})
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

  drawTile(x, y, value) {
    if (this.renderMode === "tiles" && this.hasTileAssets()) {
      this.drawTileForLayer(x, y, value)
    } else {
      this.drawValueTile(x, y, value)
    }
  },
  drawTileForLayer(x, y, value) {
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

  drawValueTile(x, y, value, render) {
    const {ctx, size} = this.resolveRender(render)
    ctx.fillStyle = this.colorForValue(value)
    ctx.fillRect(
      x * size,
      y * size,
      size,
      size
    )
  },

  renderTilesForLayer() {
    if (this.activeLayer === "terrain") {
      this.renderTerrainTiles()
      return
    }

    if (this.activeLayer === "minerals") {
      this.renderMineralTiles()
      return
    }

    if (this.activeLayer === "terrain_flags") {
      this.renderFlagTiles()
      return
    }

    this.renderValues()
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

  drawTileArt(x, y, options = {}) {
    const render = this.resolveRender(options.render)
    const includeOverlays = options.includeOverlays !== false
    const idx = y * this.mapWidth + x
    const terrainValue = this.terrainValues[idx] || 0
    const kind = this.terrainKindAt(x, y, terrainValue)
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
    const mask = this.adjMaskForKind(kind, x, y)
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
    for (let y = 0; y < this.mapHeight; y++) {
      for (let x = 0; x < this.mapWidth; x++) {
        this.drawTileArt(x, y, {includeOverlays: true, render})
      }
    }
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

  terrainBaseKindAt(x, y) {
    const idx = y * this.mapWidth + x
    const value = this.terrainValues[idx] ?? 0
    return this.terrainBaseKindForValue(value)
  },

  terrainBaseKindForValue(value) {
    if (!Number.isFinite(value)) return "unknown"
    const base = value & 0xff
    const override = this.terrainKindOverrides?.[String(base)]
    if (override) return this.normalizeKind(override)
    if (this.terrainWaterValueSet && this.terrainWaterValueSet.has(base)) return "ocean"

    const name = String(this.terrainNames?.[String(base)] || "").toLowerCase()
    if (name) {
      if (this.matchesKeyword(name, ["ocean", "sea", "water"])) return "ocean"
      if (this.matchesKeyword(name, ["shore", "coast", "beach"])) return "shore"
      if (this.matchesKeyword(name, ["desert", "dune", "sand", "waste"])) return "desert"
      if (this.matchesKeyword(name, ["tundra", "snow", "ice"])) return "tundra"
      if (this.matchesKeyword(name, ["swamp", "marsh", "bog"])) return "swamp"
      if (this.matchesKeyword(name, ["hill", "hills", "highland"])) return "hill"
      if (this.matchesKeyword(name, ["mountain", "peak", "volcano", "crater"])) {
        return "mountain"
      }
      if (this.matchesKeyword(name, ["grass", "plain", "prairie"])) return "grass"
    }

    return "grass"
  },

  normalizeKind(value) {
    const normalized = String(value || "").trim().toLowerCase()
    if (normalized === "") return "unknown"
    if (
      [
        "ocean",
        "shore",
        "grass",
        "desert",
        "tundra",
        "swamp",
        "hill",
        "mountain",
      ].includes(normalized)
    ) {
      return normalized
    }
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

    return mask
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
    const embedded = (terrainValue >> 8) & 0xff
    if (embedded <= 0) return

    const groupNames = this.overlayGroupNames(`special_${embedded}`, "interior").concat(
      this.overlayGroupNames("special", "interior")
    )
    const overlayEntry = this.pickOverlayEntry(groupNames, "interior", idx, resolved)
    if (overlayEntry) {
      this.drawImageEntry(overlayEntry, x, y, resolved)
    }
  },

  redrawNeighborhood(x, y) {
    for (let dy = -1; dy <= 1; dy++) {
      for (let dx = -1; dx <= 1; dx++) {
        let nx = x + dx
        let ny = y + dy
        if (ny < 0 || ny >= this.mapHeight) continue
        if (nx < 0) nx += this.mapWidth
        if (nx >= this.mapWidth) nx -= this.mapWidth
        this.drawTerrainTile(nx, ny)
      }
    }
  },

  colorForValue(value) {
    const hue = (value * 37) % 360
    const lightness = this.layerType === "u16" ? 28 + (value % 32) : 30 + (value % 64) / 2
    const saturation = this.layerType === "u16" ? 48 : 62
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
