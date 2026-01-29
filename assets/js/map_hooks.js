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
    this.drawTileArt(x, y, {includeMinerals: false, render})
  },

  drawTileArt(x, y, options = {}) {
    const render = this.resolveRender(options.render)
    const includeMinerals = options.includeMinerals !== false
    const idx = y * this.mapWidth + x
    const terrainValue = this.terrainValues[idx] || 0
    const terrainType = terrainValue & 0xff
    const name = this.terrainNames[String(terrainType)]
    const groupName = name || `terrain_${terrainType}`
    const entries = this.terrainGroups[groupName] || []
    const mask = this.adjMaskAt(x, y)
    const entry = this.pickEntry(entries, mask, idx, render)

    if (!entry || !this.drawImageEntry(entry, x, y, render)) {
      this.drawValueTile(x, y, this.values[idx], render)
      return
    }

    if (includeMinerals) {
      this.drawMineralOverlay(x, y, render)
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

    const overlayEntries =
      this.overlayGroups[`resource_${mineral}`] || this.overlayGroups["resource"] || []
    const overlayEntry = this.pickEntry(overlayEntries, 0, idx, resolved)
    if (overlayEntry) {
      this.drawImageEntry(overlayEntry, x, y, resolved)
    }
  },

  pickEntry(entries, mask, seed, render) {
    if (!entries || entries.length === 0) return null
    const resolved = this.resolveRender(render)
    const maskEntries = this.entriesForMask(entries, mask)
    const baseEntries = entries.filter(entry => !entry.variant)
    const pool = maskEntries.length ? maskEntries : (baseEntries.length ? baseEntries : entries)

    if (resolved.usePhase) {
      const phaseEntry = this.pickPhaseEntry(pool, resolved.phaseIndex)
      if (phaseEntry) return phaseEntry
    }

    return pool[seed % pool.length]
  },

  entriesForMask(entries, mask) {
    return entries.filter(entry => this.variantMatchesMask(entry.variant, mask))
  },

  variantMatchesMask(variant, mask) {
    if (!variant) return false
    const text = String(variant).toLowerCase()
    const maskText = String(mask)
    if (text === maskText || text === `mask_${maskText}`) return true
    const regex = new RegExp(`(^|\\D)mask[_:-]?${maskText}(\\D|$)`)
    return regex.test(text)
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
        this.drawTileArt(x, y, {includeMinerals: false, render})
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

  adjMaskAt(x, y) {
    const dirs = [
      [0, -1],
      [1, -1],
      [1, 0],
      [1, 1],
      [0, 1],
      [-1, 1],
      [-1, 0],
      [-1, -1],
    ]

    const center = (this.terrainValues[y * this.mapWidth + x] || 0) & 0xff
    let mask = 0

    dirs.forEach(([dx, dy], index) => {
      let nx = x + dx
      let ny = y + dy
      if (ny < 0 || ny >= this.mapHeight) return
      if (nx < 0) nx += this.mapWidth
      if (nx >= this.mapWidth) nx -= this.mapWidth
      const neighbor = (this.terrainValues[ny * this.mapWidth + nx] || 0) & 0xff
      if (neighbor === center) {
        mask |= 1 << index
      }
    })

    return mask
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
