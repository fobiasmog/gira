import { ref } from "vue"
import type { Language } from "../api/types.ts"
import { en, type Messages, type Plural } from "./en.ts"
import { ru } from "./ru.ts"
import { pluralize } from "./format.ts"

type Keys<T, Leaf, P extends string = ""> = {
  [K in keyof T & string]: T[K] extends Leaf ? `${P}${K}` : T[K] extends string | Plural ? never : Keys<T[K], Leaf, `${P}${K}.`>
}[keyof T & string]

export type MessageKey = Keys<typeof en, string>
export type PluralKey = Keys<typeof en, Plural>
export type Params = Record<string, string | number>

export const dictionaries: Record<Language, Messages> = { en, ru }

// The interface language. Reading it inside t() makes every rendered string
// reactive, so switching language re-renders without a reload.
export const language = ref<Language>("en")

export function setLanguage(lang: Language) {
  language.value = lang
  document.documentElement.lang = lang
}

function lookup(key: string): unknown {
  let node: unknown = dictionaries[language.value]
  for (const part of key.split(".")) node = (node as Record<string, unknown> | undefined)?.[part]
  return node
}

function interpolate(text: string, params?: Params): string {
  return params ? text.replace(/\{(\w+)\}/g, (match, name: string) => String(params[name] ?? match)) : text
}

export function t(key: MessageKey, params?: Params): string {
  const text = lookup(key)
  return typeof text === "string" ? interpolate(text, params) : key
}

export function tc(key: PluralKey, count: number, params?: Params): string {
  return interpolate(pluralize(language.value, count, lookup(key) as Plural), params)
}
