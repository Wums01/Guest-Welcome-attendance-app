export type StoreKey = "programs" | "sessions" | "clockins" | "members" | "reports"

export function readStore<T>(key: StoreKey, fallback: T): T {
  if (typeof window === "undefined") return fallback

  const raw = window.localStorage.getItem(key)
  if (!raw) return fallback

  try {
    return JSON.parse(raw) as T
  } catch {
    return fallback
  }
}

export function writeStore<T>(key: StoreKey, value: T) {
  if (typeof window === "undefined") return
  window.localStorage.setItem(key, JSON.stringify(value))
}