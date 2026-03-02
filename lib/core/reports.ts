import { getClockIns } from "./clockins"

// month format: "YYYY-MM"
export function getMonthlyLeaderboard(month: string) {
  const clockins = getClockIns()

  // Only "present" counts as points
  const present = clockins.filter((c) => c.status === "present")

  // For now filter by clockedAt timestamp month
  const inMonth = present.filter((c) => c.clockedAt.slice(0, 7) === month)

  const map = new Map<string, number>()
  for (const c of inMonth) {
    map.set(c.memberId, (map.get(c.memberId) ?? 0) + 1)
  }

  const rows = Array.from(map.entries()).map(([memberId, presentCount]) => ({
    memberId,
    presentCount,
  }))

  rows.sort((a, b) => b.presentCount - a.presentCount)

  return rows.map((row, i) => ({ ...row, rank: i + 1 }))
}