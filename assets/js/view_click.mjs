// Which map tile a click in the pan/zoom viewport landed on (view mode inspector,
// STORY-020). Pure, so it is tested with Node (assets/test/view_click.test.mjs).
//
// The viewport moves the stage with a CSS transform: a point `p` inside the stage
// shows at `translate + p * scale` in viewport coordinates. `tileSize` is the CSS
// size of one tile at scale 1. Returns `{x, y}` or `null` outside the map.
export function tileAtViewportPoint({clientX, clientY, rect, tx, ty, scale, tileSize, mapWidth, mapHeight}) {
  if (!scale || !tileSize) return null
  const x = Math.floor((clientX - rect.left - tx) / scale / tileSize)
  const y = Math.floor((clientY - rect.top - ty) / scale / tileSize)
  if (x < 0 || y < 0 || x >= mapWidth || y >= mapHeight) return null
  return {x, y}
}

// Where to put the stage so tile `(x, y)` sits in the middle of the viewport at `scale`
// (the "centre on this tile" link from the wizard page). Returns `{tx, ty}`.
export function centerOnTile({x, y, scale, tileSize, viewWidth, viewHeight}) {
  return {
    tx: viewWidth / 2 - (x + 0.5) * tileSize * scale,
    ty: viewHeight / 2 - (y + 0.5) * tileSize * scale,
  }
}
