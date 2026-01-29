const MapCanvas = {
  mounted() {
    this.tileSize = parseInt(this.el.dataset.tileSize || "12", 10)
    this.mapWidth = parseInt(this.el.dataset.mapWidth || "60", 10)
    this.mapHeight = parseInt(this.el.dataset.mapHeight || "40", 10)
    this.layerType = this.el.dataset.layerType || "u8"
    this.renderMode = this.el.dataset.renderMode || "values"
    this.activeLayer = this.el.dataset.layer || "terrain"
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

  drawValueTile(x, y, value) {
    this.ctx.fillStyle = this.colorForValue(value)
    const size = this.deviceTileSize
    this.ctx.fillRect(
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

  renderTerrainTiles() {
    for (let y = 0; y < this.mapHeight; y++) {
      for (let x = 0; x < this.mapWidth; x++) {
        this.drawTerrainTile(x, y)
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

  renderMineralTiles() {
    this.fillBackground()

    for (let y = 0; y < this.mapHeight; y++) {
      for (let x = 0; x < this.mapWidth; x++) {
        this.drawMineralTile(x, y)
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

  fillBackground() {
    this.ctx.fillStyle = "#020617"
    this.ctx.fillRect(0, 0, this.el.width, this.el.height)
  },

  fillTileBackground(x, y) {
    const size = this.deviceTileSize
    this.ctx.fillStyle = "#020617"
    this.ctx.fillRect(x * size, y * size, size, size)
  },

  drawTerrainTile(x, y) {
    this.drawTileArt(x, y, {includeMinerals: false})
  },

  drawTileArt(x, y, options = {}) {
    const includeMinerals = options.includeMinerals !== false
    const idx = y * this.mapWidth + x
    const terrainValue = this.terrainValues[idx] || 0
    const terrainType = terrainValue & 0xff
    const name = this.terrainNames[String(terrainType)]
    const groupName = name || `terrain_${terrainType}`
    const entries = this.terrainGroups[groupName] || []
    const mask = this.adjMaskAt(x, y)
    const entry = this.pickEntry(entries, mask, idx)

    if (!entry || !this.drawImageEntry(entry, x, y)) {
      this.drawValueTile(x, y, this.values[idx])
      return
    }

    if (includeMinerals) {
      this.drawMineralOverlay(x, y)
    }
  },

  drawMineralTile(x, y) {
    this.fillTileBackground(x, y)
    this.drawMineralOverlay(x, y)
  },

  drawMineralOverlay(x, y) {
    const idx = y * this.mapWidth + x
    const mineral = this.mineralsValues[idx] || 0
    if (mineral <= 0) return

    const overlayEntries =
      this.overlayGroups[`resource_${mineral}`] || this.overlayGroups["resource"] || []
    const overlayEntry = this.pickEntry(overlayEntries, 0, idx)
    if (overlayEntry) {
      this.drawImageEntry(overlayEntry, x, y)
    }
  },

  pickEntry(entries, mask, seed) {
    if (!entries || entries.length === 0) return null
    const maskKey = `mask_${mask}`
    const variant = entries.find(entry => entry.variant === maskKey || entry.variant === `${mask}`)
    if (variant) return variant

    const baseEntries = entries.filter(entry => !entry.variant)
    const pool = baseEntries.length ? baseEntries : entries
    return pool[seed % pool.length]
  },

  drawImageEntry(entry, x, y) {
    const image = this.tileImages[entry.key]
    if (!image) return false
    const size = this.deviceTileSize
    this.ctx.drawImage(
      image.canvas,
      x * size,
      y * size,
      size,
      size
    )
    return true
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
