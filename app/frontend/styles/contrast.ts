// WCAG 2 contrast between two colours, and reading colour tokens out of a
// stylesheet so tokens.test.ts can check them.

export type Rgb = [number, number, number]

export function parseHex(value: string): Rgb {
  const hex = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(value.trim())?.[1]
  if (!hex) throw new Error(`not a hex colour: ${value}`)
  const full = hex.length === 3 ? [...hex].map((digit) => digit + digit).join("") : hex
  return [0, 2, 4].map((i) => parseInt(full.slice(i, i + 2), 16)) as Rgb
}

// https://www.w3.org/TR/WCAG22/#dfn-relative-luminance
export function relativeLuminance([r, g, b]: Rgb): number {
  const linear = (channel: number) => {
    const c = channel / 255
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
  }
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
}

export function contrastRatio(a: string, b: string): number {
  const [x, y] = [relativeLuminance(parseHex(a)), relativeLuminance(parseHex(b))]
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05)
}

// The custom properties declared in a stylesheet, with var() references to
// other properties resolved. Later declarations win, as in the cascade of a
// single :root rule.
export function readTokens(css: string): Map<string, string> {
  const raw = new Map<string, string>()
  const withoutComments = css.replace(/\/\*[\s\S]*?\*\//g, "")
  for (const [, name, value] of withoutComments.matchAll(/(--[\w-]+)\s*:\s*([^;}]+)/g)) raw.set(name!, value!.trim())

  const resolve = (name: string, seen: string[] = []): string => {
    if (seen.includes(name)) throw new Error(`circular token: ${[...seen, name].join(" → ")}`)
    const value = raw.get(name)
    if (value === undefined) throw new Error(`unknown token: ${name}`)
    return value.replace(/var\(\s*(--[\w-]+)\s*\)/g, (_, ref: string) => resolve(ref, [...seen, name]))
  }
  return new Map([...raw.keys()].map((name) => [name, resolve(name)]))
}
