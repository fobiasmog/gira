import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { contrastRatio, parseHex, readTokens } from "./contrast.ts"

// Spec web-client, "Colour contrast": text at least 4.5:1, focus indicators,
// control boundaries and meaningful markers at least 3:1.
const tokens = readTokens(readFileSync(new URL("./tokens.css", import.meta.url), "utf8"))
const color = (value: string) => (value.startsWith("--") ? tokens.get(value) ?? assert.fail(`unknown token ${value}`) : value)

const TEXT = 4.5
const MARKER = 3
const tones = [1, 2, 3, 4, 5, 6]

const pairs: [description: string, foreground: string, background: string, minimum: number][] = [
  ["primary button label", "#fff", "--color-primary", TEXT],
  ["primary button label on hover", "#fff", "--color-primary-hover", TEXT],
  ["body text on a surface", "--color-text", "--color-surface", TEXT],
  ["body text on the background", "--color-text", "--color-background", TEXT],
  ["muted text on a surface", "--color-muted", "--color-surface", TEXT],
  ["muted text on a raised surface", "--color-muted", "--color-surface-raised", TEXT],
  ["muted text on the background", "--color-muted", "--color-background", TEXT],
  ["link and secondary button text on a surface", "--color-main-dark", "--color-surface", TEXT],
  ["link text on the background", "--color-main-dark", "--color-background", TEXT],
  ["primary-coloured text on a surface", "--color-primary", "--color-surface", TEXT],
  ["error text on a surface", "--color-danger", "--color-surface", TEXT],
  ["navigation link on the sidebar", "--color-nav-text", "--color-nav-bg", TEXT],
  ["navigation link on a raised sidebar control", "--color-nav-text", "--color-nav-raised", TEXT],
  ["current navigation link", "--color-nav-strong", "--color-nav-active", TEXT],
  ["muted navigation text", "--color-nav-muted", "--color-nav-bg", TEXT],
  ["navigation section heading", "--color-nav-heading", "--color-nav-bg", TEXT],
  ["count badge", "--color-badge-text", "--color-badge", TEXT],
  ["plain chip", "--color-main-darker", "--color-main-lighter", TEXT],
  ...tones.map((n): [string, string, string, number] => [`label tone ${n}`, `--tone-${n}-text`, `--tone-${n}-bg`, TEXT]),
  ["overdue deadline on its highlight", "--color-overdue", "--color-overdue-bg", TEXT],
  ["“Important” on a surface", "--color-important", "--color-surface", TEXT],
  ["done status text on a surface", "--color-success", "--color-surface", TEXT],
  ["focus ring on a surface", "--color-focus", "--color-surface", MARKER],
  ["focus ring on the background", "--color-focus", "--color-background", MARKER],
  ["focus ring on the sidebar", "--color-nav-text", "--color-nav-bg", MARKER],
  ["text field boundary on a surface", "--color-control-border", "--color-surface", MARKER],
  ["text field boundary on the background", "--color-control-border", "--color-background", MARKER],
  ["done marker on a surface", "--color-success", "--color-surface", MARKER],
  ["importance marker on a surface", "--color-important", "--color-surface", MARKER],
  ["progress fill on its track", "--color-primary", "--color-border", MARKER],
]

for (const [description, foreground, background, minimum] of pairs) {
  test(`contrast: ${description} is at least ${minimum}:1`, () => {
    const ratio = contrastRatio(color(foreground), color(background))
    assert.ok(ratio >= minimum, `${foreground} on ${background}: ${ratio.toFixed(2)}:1`)
  })
}

test("contrast ratios match known WCAG values", () => {
  assert.equal(contrastRatio("#000", "#fff"), 21)
  assert.equal(contrastRatio("#fff", "#fff"), 1)
  assert.equal(contrastRatio("#7c3fd0", "#fff").toFixed(1), "6.0")
  assert.equal(contrastRatio("#fff", "#9859e8").toFixed(1), "4.3")
})

test("tokens resolve var() references", () => {
  assert.deepEqual(readTokens(":root { --a: #123; --b: var(--a); --c: var( --b ); }"), new Map([["--a", "#123"], ["--b", "#123"], ["--c", "#123"]]))
  assert.throws(() => readTokens(":root { --a: var(--b); --b: var(--a); }"), /circular/)
  assert.throws(() => readTokens(":root { --a: var(--missing); }"), /unknown token/)
})

test("hex colours parse in short and long form, and nothing else does", () => {
  assert.deepEqual(parseHex("#fff"), [255, 255, 255])
  assert.deepEqual(parseHex("#7C3FD0"), [124, 63, 208])
  assert.throws(() => parseHex("purple"))
  assert.throws(() => parseHex("#12345"))
})
