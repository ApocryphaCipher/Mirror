// Which value type (u8 / u16) the canvas should remember after a tile delta.
//
// The page draws its active layer with `layerType`, so only a delta for the
// active layer may change it. A step that covers several layers (a painted type
// changes terrain and landmass) sends one delta per layer; a delta for another
// layer must leave the active layer's type alone. A payload with no layer is
// for the active layer.
export function layerTypeAfterDelta(current, activeLayer, payloadLayer, payloadType) {
  const layer = payloadLayer || activeLayer
  return payloadType && layer === activeLayer ? payloadType : current
}
