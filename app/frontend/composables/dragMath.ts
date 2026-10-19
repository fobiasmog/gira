// Pure geometry for drag and drop, unit-tested with node --test.

// Index at which a dragged item lands among the other items of a container
// (the dragged item itself excluded), given the pointer position and those
// items' midpoints along the container's axis, in order.
export function dropIndex(pointer: number, midpoints: readonly number[]): number {
  let index = 0
  while (index < midpoints.length && pointer > midpoints[index]!) index++
  return index
}

// True when dropping would leave the item where it started.
export function isNoop(fromContainer: unknown, fromIndex: number, toContainer: unknown, toIndex: number): boolean {
  return fromContainer === toContainer && fromIndex === toIndex
}

// Scroll speed (px per frame) when the pointer is within `edge` px of either
// end of a scrollable area: faster closer to the edge, negative towards the start.
export function edgeScrollDelta(pointer: number, start: number, end: number, edge = 48, maxSpeed = 18): number {
  if (end - start <= 2 * edge) return 0
  if (pointer < start + edge) return -Math.ceil(maxSpeed * (1 - Math.max(0, pointer - start) / edge))
  if (pointer > end - edge) return Math.ceil(maxSpeed * (1 - Math.max(0, end - pointer) / edge))
  return 0
}
