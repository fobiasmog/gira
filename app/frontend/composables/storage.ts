// Preferences remembered in this browser. They hold no personal data and
// survive sign-out. Storage can be blocked (private mode, site data disabled);
// a preference is then kept for this page only.
export function readStored(key: string): string | null {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}

export function writeStored(key: string, value: string): void {
  try {
    localStorage.setItem(key, value)
  } catch {
    // Not remembered.
  }
}
