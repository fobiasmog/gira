import type { Column } from "../api/types.ts"

// Labels and projects have no stored colour: each gets one of six tones
// (tokens --tone-1-* … --tone-6-*) from its id, so the colour survives renames
// and is the same for every member. Consecutive ids get different tones.
export type Tone = 1 | 2 | 3 | 4 | 5 | 6

export function toneOf(id: number): Tone {
  return ((((Math.trunc(id) % 6) + 6) % 6) + 1) as Tone
}

const HEX_COLOR = /^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i

// A column's status dot: its own colour when that is a valid #rgb/#rrggbb
// value (the field may hold legacy data), else green for the done column,
// else the tone derived from its id.
export type ColumnDot = { kind: "color"; color: string } | { kind: "done" } | { kind: "tone"; tone: Tone }

export function columnDot(column: Pick<Column, "id" | "done"> & { color?: string | null }): ColumnDot {
  const color = column.color?.trim()
  if (color && HEX_COLOR.test(color)) return { kind: "color", color }
  if (column.done) return { kind: "done" }
  return { kind: "tone", tone: toneOf(column.id) }
}
