import { onScopeDispose, ref, type Ref } from "vue"

export function useMediaQuery(query: string): Readonly<Ref<boolean>> {
  const list = matchMedia(query)
  const matches = ref(list.matches)
  const update = (event: MediaQueryListEvent) => { matches.value = event.matches }
  list.addEventListener("change", update)
  onScopeDispose(() => list.removeEventListener("change", update))
  return matches
}
