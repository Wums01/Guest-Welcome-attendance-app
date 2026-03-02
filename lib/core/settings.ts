const KEY = "test_mode_enabled"

export function isTestMode(): boolean {
  if (typeof window === "undefined") return false
  return localStorage.getItem(KEY) === "true"
}

export function setTestMode(value: boolean) {
  if (typeof window === "undefined") return
  localStorage.setItem(KEY, value ? "true" : "false")
}