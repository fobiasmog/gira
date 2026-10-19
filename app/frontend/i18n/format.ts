import type { Language } from "../api/types.ts"
import type { Plural } from "./en.ts"

const cache = new Map<string, Intl.DateTimeFormat | Intl.RelativeTimeFormat | Intl.PluralRules | Intl.NumberFormat>()

function cached<T extends Intl.DateTimeFormat | Intl.RelativeTimeFormat | Intl.PluralRules | Intl.NumberFormat>(key: string, make: () => T): T {
  let value = cache.get(key)
  if (!value) cache.set(key, value = make())
  return value as T
}

const DAY_MS = 86_400_000

// Whole calendar days from today to the date, in local time.
export function calendarDaysFrom(now: Date, date: Date): number {
  const day = (d: Date) => Date.UTC(d.getFullYear(), d.getMonth(), d.getDate())
  return Math.round((day(date) - day(now)) / DAY_MS)
}

export function formatDate(lang: Language, value: string | Date, now = new Date()): string {
  const date = new Date(value)
  const options: Intl.DateTimeFormatOptions = { day: "numeric", month: "short" }
  if (date.getFullYear() !== now.getFullYear()) options.year = "numeric"
  return cached(`date:${lang}:${options.year ?? ""}`, () => new Intl.DateTimeFormat(lang, options)).format(date)
}

export function formatDateTime(lang: Language, value: string | Date): string {
  return cached(`datetime:${lang}`, () => new Intl.DateTimeFormat(lang, { dateStyle: "medium", timeStyle: "short" }))
    .format(new Date(value))
}

// "yesterday", "today", "tomorrow" (or the language's equivalents) within a
// day of now; otherwise the date.
export function formatRelativeDay(lang: Language, value: string | Date, now = new Date()): string {
  const days = calendarDaysFrom(now, new Date(value))
  if (Math.abs(days) > 1) return formatDate(lang, value, now)
  return cached(`relative:${lang}`, () => new Intl.RelativeTimeFormat(lang, { numeric: "auto" })).format(days, "day")
}

export function formatNumber(lang: Language, value: number): string {
  return cached(`number:${lang}`, () => new Intl.NumberFormat(lang)).format(value)
}

export function pluralize(lang: Language, count: number, forms: Plural): string {
  const rule = cached(`plural:${lang}`, () => new Intl.PluralRules(lang)).select(count)
  return (forms[rule] ?? forms.other).replaceAll("{count}", formatNumber(lang, count))
}

// <input type="datetime-local"> works in local time without a zone.
export function toDateTimeInput(value: string | null): string {
  if (!value) return ""
  const date = new Date(value)
  const pad = (n: number) => String(n).padStart(2, "0")
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`
}

export function fromDateTimeInput(value: string): string | null {
  return value ? new Date(value).toISOString() : null
}
