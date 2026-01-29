const RgbaCanvas = {
  mounted() {
    this.draw()
  },
  updated() {
    this.draw()
  },
  draw() {
    const encoded = this.el.dataset.rgba
    const width = parseInt(this.el.dataset.width || "0", 10)
    const height = parseInt(this.el.dataset.height || "0", 10)
    if (!encoded || !width || !height) return

    const bytes = Uint8ClampedArray.from(atob(encoded), char => char.charCodeAt(0))
    const ctx = this.el.getContext("2d")
    this.el.width = width
    this.el.height = height
    const imageData = new ImageData(bytes, width, height)
    ctx.putImageData(imageData, 0, 0)
  },
}

export {RgbaCanvas}
