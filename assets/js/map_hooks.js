const MapCanvas = {
  mounted() {
    this.tileSize = parseInt(this.el.dataset.tileSize || "12", 10)
    this.mapWidth = parseInt(this.el.dataset.mapWidth || "60", 10)
    this.mapHeight = parseInt(this.el.dataset.mapHeight || "40", 10)
    this.layerType = this.el.dataset.layerType || "u8"
    this.values = this.decodeTiles(this.el.dataset.tiles || "")
    this.lastTileKey = null
    this.isPointerDown = false
    this.pointerButton = 0

    this.ctx = this.el.getContext("2d", {alpha: false})
    this.ctx.imageSmoothingEnabled = false
    this.resizeCanvas()
    this.renderAll()

    this.el.addEventListener("contextmenu", event => event.preventDefault())
    this.el.addEventListener("pointerdown", this.onPointerDown.bind(this))
    this.el.addEventListener("pointermove", this.onPointerMove.bind(this))
    this.el.addEventListener("pointerup", this.onPointerUp.bind(this))
    this.el.addEventListener("pointerleave", this.onPointerLeave.bind(this))
    this.el.addEventListener("wheel", this.onWheel.bind(this), {passive: false})

    this.handleEvent("map_state", payload => {
      if (payload.layer_type) {
        this.layerType = payload.layer_type
      }
    })

    this.handleEvent("map_reload", payload => {
      this.layerType = payload.layer_type || this.layerType
      this.values = this.decodeTiles(payload.values || "")
      this.renderAll()
    })

    this.handleEvent("tile_updates", payload => {
      if (!payload || !Array.isArray(payload.updates)) return
      this.layerType = payload.layer_type || this.layerType
      payload.updates.forEach(update => {
        const idx = update.y * this.mapWidth + update.x
        if (idx < 0 || idx >= this.values.length) return
        this.values[idx] = update.value
        this.drawTile(update.x, update.y, update.value)
      })
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

  resizeCanvas() {
    this.el.width = this.mapWidth * this.tileSize
    this.el.height = this.mapHeight * this.tileSize
  },

  decodeTiles(encoded) {
    if (!encoded) {
      return this.layerType === "u16"
        ? new Uint16Array(this.mapWidth * this.mapHeight)
        : new Uint8Array(this.mapWidth * this.mapHeight)
    }

    const bytes = Uint8Array.from(atob(encoded), char => char.charCodeAt(0))

    if (this.layerType === "u16") {
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
    this.ctx.fillStyle = this.colorForValue(value)
    this.ctx.fillRect(
      x * this.tileSize,
      y * this.tileSize,
      this.tileSize,
      this.tileSize
    )
  },

  renderAll() {
    for (let y = 0; y < this.mapHeight; y++) {
      for (let x = 0; x < this.mapWidth; x++) {
        const idx = y * this.mapWidth + x
        this.drawTile(x, y, this.values[idx])
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
    const x = Math.floor(px / this.tileSize)
    const y = Math.floor(py / this.tileSize)

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
