"use client"

import { useEffect, useMemo, useState } from "react"
import type { ClockIn, Member } from "@/lib/types"
import { getClockIns } from "@/lib/core/clockins"
import { getMembers } from "@/lib/core/members"
import { getSessions } from "@/lib/core/sessions"

type Row = {
  memberId: string
  fullName: string
  team: string
  presentCount: number
}

function yyyyMmFromISO(dateISO: string) {
  // "2026-02-17" -> "2026-02"
  return dateISO.slice(0, 7)
}

function currentYearMonth() {
  const d = new Date()
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, "0")
  return { year: y, month: m } // month is "01".."12"
}

const MONTHS = [
  { label: "January", value: "01" },
  { label: "February", value: "02" },
  { label: "March", value: "03" },
  { label: "April", value: "04" },
  { label: "May", value: "05" },
  { label: "June", value: "06" },
  { label: "July", value: "07" },
  { label: "August", value: "08" },
  { label: "September", value: "09" },
  { label: "October", value: "10" },
  { label: "November", value: "11" },
  { label: "December", value: "12" },
]

export default function LeaderboardPage() {
  const nowYM = useMemo(() => currentYearMonth(), [])

  const [query, setQuery] = useState("")
  const [clockins, setClockins] = useState<ClockIn[]>([])
  const [members, setMembers] = useState<Member[]>([])
  const [sessions, setSessions] = useState<ReturnType<typeof getSessions>>([])

  // Month filter
  const [year, setYear] = useState<number>(nowYM.year)
  const [month, setMonth] = useState<string>(nowYM.month) // "01".."12"

  function refresh() {
    setClockins(getClockIns())
    setMembers(getMembers())
    setSessions(getSessions())
  }

  useEffect(() => {
    refresh()
  }, [])

  const rows = useMemo<Row[]>(() => {
    const memberMap = new Map<string, Member>()
    for (const m of members) memberMap.set(m.id, m)

    // sessionId -> sessionDate (YYYY-MM-DD)
    const sessionDateMap = new Map<string, string>()
    for (const s of sessions) sessionDateMap.set(s.id, s.date)

    const targetYM = `${year}-${month}` // e.g. "2026-12"

    // Count present clock-ins, but ONLY those whose session date is inside targetYM
    const counts = new Map<string, number>()

    for (const c of clockins) {
      if (c.status !== "present") continue

      const sessionDate = sessionDateMap.get(c.sessionId)
      if (!sessionDate) continue

      if (yyyyMmFromISO(sessionDate) !== targetYM) continue

      counts.set(c.memberId, (counts.get(c.memberId) ?? 0) + 1)
    }

    let list: Row[] = []
    for (const [memberId, presentCount] of counts.entries()) {
      const member = memberMap.get(memberId)

      list.push({
        memberId,
        fullName: member?.fullName ?? "Unknown member",
        team: (member as any)?.team ?? "None",
        presentCount,
      })
    }

    // Highest -> lowest
    list.sort((a, b) => {
      if (b.presentCount !== a.presentCount) return b.presentCount - a.presentCount
      return a.fullName.localeCompare(b.fullName)
    })

    // Search
    const q = query.trim().toLowerCase()
    if (!q) return list
    return list.filter((r) => {
      return (
        r.fullName.toLowerCase().includes(q) ||
        (r.team ?? "").toLowerCase().includes(q) ||
        r.memberId.toLowerCase().includes(q)
      )
    })
  }, [clockins, members, sessions, query, year, month])

  const totalPresentForMonth = useMemo(() => {
    const sessionDateMap = new Map<string, string>()
    for (const s of sessions) sessionDateMap.set(s.id, s.date)

    const targetYM = `${year}-${month}`
    return clockins.filter((c) => {
      if (c.status !== "present") return false
      const sessionDate = sessionDateMap.get(c.sessionId)
      if (!sessionDate) return false
      return yyyyMmFromISO(sessionDate) === targetYM
    }).length
  }, [clockins, sessions, year, month])

  const yearsOptions = useMemo(() => {
    // show current year +/- 2 (you can adjust)
    const y = nowYM.year
    return [y - 2, y - 1, y, y + 1, y + 2]
  }, [nowYM.year])

  const monthLabel = useMemo(() => MONTHS.find((m) => m.value === month)?.label ?? month, [month])

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="rounded-3xl bg-white p-5 shadow-sm">
        <div className="flex items-start justify-between gap-3">
          <div>
            <div className="text-sm font-semibold text-slate-900">Monthly Leaderboard</div>
            <div className="text-xs text-slate-500">
              Highest attendance for <b>{monthLabel}</b> {year} (each service attended = 1 point)
            </div>
          </div>

          <div className="rounded-2xl bg-slate-50 px-3 py-2 text-right">
            <div className="text-[11px] text-slate-500">Total present</div>
            <div className="text-sm font-semibold text-slate-900">{totalPresentForMonth}</div>
          </div>
        </div>

        {/* Month/Year Filters */}
        <div className="mt-4 grid grid-cols-2 gap-3">
          <div>
            <div className="text-xs font-medium text-slate-700">Month</div>
            <select
              value={month}
              onChange={(e) => setMonth(e.target.value)}
              className="mt-1 w-full rounded-2xl border border-slate-300 bg-white px-3 py-3 text-sm outline-none focus:border-slate-500"
            >
              {MONTHS.map((m) => (
                <option key={m.value} value={m.value}>
                  {m.label}
                </option>
              ))}
            </select>
          </div>

          <div>
            <div className="text-xs font-medium text-slate-700">Year</div>
            <select
              value={year}
              onChange={(e) => setYear(Number(e.target.value))}
              className="mt-1 w-full rounded-2xl border border-slate-300 bg-white px-3 py-3 text-sm outline-none focus:border-slate-500"
            >
              {yearsOptions.map((y) => (
                <option key={y} value={y}>
                  {y}
                </option>
              ))}
            </select>
          </div>
        </div>

        {/* Search + Refresh */}
        <div className="mt-3 space-y-3">
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search name, team or memberId…"
            className="w-full rounded-2xl border border-slate-300 bg-white px-4 py-3 text-sm outline-none focus:border-slate-500"
          />

          <button
            type="button"
            onClick={refresh}
            className="w-full rounded-2xl border border-slate-300 bg-white px-4 py-3 text-sm font-semibold text-slate-900 hover:bg-slate-50"
          >
            Refresh leaderboard
          </button>
        </div>
      </div>

      {/* List */}
      <div className="rounded-2xl bg-white shadow-sm">
        <div className="flex items-center justify-between border-b px-4 py-3">
          <div className="text-sm font-semibold text-slate-900">Ranking</div>
          <div className="text-xs text-slate-500">{rows.length} result(s)</div>
        </div>

        {rows.length === 0 ? (
          <div className="p-6 text-center text-sm text-slate-600">
            No data for <b>{monthLabel}</b> {year}.
            <div className="mt-1 text-xs text-slate-500">
              Make sure members are created and clocked in as “present” in sessions within this month.
            </div>
          </div>
        ) : (
          <ul className="divide-y">
            {rows.map((r, idx) => (
              <li key={r.memberId} className="px-4 py-4">
                <div className="flex items-center justify-between gap-3">
                  <div className="flex items-center gap-3">
                    <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-slate-900 text-sm font-semibold text-white">
                      {idx + 1}
                    </div>

                    <div>
                      <div className="text-sm font-semibold text-slate-900">{r.fullName}</div>
                      <div className="text-xs text-slate-600">
                        {(r.team ? `${r.team} • ` : "")}ID: {r.memberId}
                      </div>
                    </div>
                  </div>

                  <div className="text-right">
                    <div className="text-xs text-slate-500">Points</div>
                    <div className="text-lg font-semibold text-slate-900">{r.presentCount}</div>
                  </div>
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}