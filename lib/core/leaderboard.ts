import { getMembers } from "./members"
import { getClockIns } from "./clockins"
import { getSessions } from "./sessions"

export function getMonthlyLeaderboard(monthISO: string) {
  // monthISO = "2026-02"
  const members = getMembers()
  const sessions = getSessions().filter((s) => s.date.startsWith(monthISO))

  const sessionIds = new Set(sessions.map((s) => s.id))
  const clockins = getClockIns().filter(
    (c) => sessionIds.has(c.sessionId) && c.status === "present"
  )

  const scores = new Map<string, number>()
  for (const c of clockins) {
    scores.set(c.memberId, (scores.get(c.memberId) ?? 0) + 1)
  }

  const rows = members
    .map((m) => ({
      memberId: m.id,
      name: m.fullName,
      team: m.team,
      presentCount: scores.get(m.id) ?? 0,
    }))
    .sort((a, b) => b.presentCount - a.presentCount)

  return rows
}