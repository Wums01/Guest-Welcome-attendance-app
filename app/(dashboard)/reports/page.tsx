// app/(dashboard)/reports/page.tsx

"use client"

import { useEffect, useMemo, useState } from "react"
import { getSessionsByDate, getSessions } from "@/lib/core/sessions"
import { getClockInsBySession, clearSessionClockIns, getClockIns } from "@/lib/core/clockins"
import { getMembers, getMemberByOfflineCode } from "@/lib/core/members"
import type { ClockIn, Member, Session } from "@/lib/types"

function todayISO() {
  return new Date().toISOString().slice(0, 10)
}

function monthISOFromDateISO(dateISO: string) {
  return dateISO.slice(0, 7)
}

function currentYearISO() {
  return String(new Date().getFullYear())
}

function startOfMonthISO(monthISO: string) {
  return `${monthISO}-01`
}

function endOfMonthISO(monthISO: string) {
  const [y, m] = monthISO.split("-").map(Number)
  const d = new Date(y, m, 0)
  const mm = String(m).padStart(2, "0")
  const dd = String(d.getDate()).padStart(2, "0")
  return `${y}-${mm}-${dd}`
}

type Counts = {
  present: number
  absent: number
  excused: number
  marked: number
}

function countStatuses(list: ClockIn[]): Counts {
  const present = list.filter((c) => c.status === "present").length
  const absent = list.filter((c) => c.status === "absent").length
  const excused = list.filter((c) => c.status === "excused").length
  return { present, absent, excused, marked: list.length }
}

function downloadTextFile(filename: string, content: string) {
  const blob = new Blob([content], { type: "text/csv;charset=utf-8;" })
  const url = URL.createObjectURL(blob)
  const a = document.createElement("a")
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  URL.revokeObjectURL(url)
}

function formatISOTime(iso: string) {
  try {
    const d = new Date(iso)
    return d.toLocaleString()
  } catch {
    return iso
  }
}

function csvEscape(v: any) {
  const s = String(v ?? "")
  return `"${s.replaceAll('"', '""')}"`
}

function medal(rank: number) {
  if (rank === 1) return "🥇"
  if (rank === 2) return "🥈"
  if (rank === 3) return "🥉"
  return String(rank)
}

function fireConfetti() {
  const count = 45
  const emojis = ["🎉", "✨", "🎊", "⭐️"]

  for (let i = 0; i < count; i++) {
    const s = document.createElement("span")
    s.textContent = emojis[Math.floor(Math.random() * emojis.length)]
    s.style.position = "fixed"
    s.style.left = Math.random() * 100 + "vw"
    s.style.top = "-12px"
    s.style.fontSize = 14 + Math.random() * 18 + "px"
    s.style.zIndex = "9999"
    s.style.pointerEvents = "none"
    s.style.transition = "transform 1.4s ease, opacity 1.4s ease"
    s.style.opacity = "1"
    document.body.appendChild(s)

    requestAnimationFrame(() => {
      const x = (Math.random() - 0.5) * 220
      const y = 700 + Math.random() * 350
      s.style.transform = `translate(${x}px, ${y}px) rotate(${Math.random() * 720}deg)`
      s.style.opacity = "0"
    })

    setTimeout(() => s.remove(), 1500)
  }
}

type SearchHit = {
  sessionName: string
  sessionId: string
  sessionDate: string
  clockin: ClockIn
  member: Member | null
}

type LeaderRow = {
  memberId: string
  memberName: string
  team?: string
  offlineCode?: string
  points: number
}

const PREVIEW_LEADERS = 10
const PREVIEW_SESSIONS = 6
const PREVIEW_SEARCH = 8

export default function ReportsPage() {
  const [date, setDate] = useState(todayISO())
  const [sessions, setSessions] = useState<Session[]>([])
  const [openSessionId, setOpenSessionId] = useState<string | null>(null)

  const [monthISO, setMonthISO] = useState(() => monthISOFromDateISO(todayISO()))
  const [yearISO, setYearISO] = useState(() => currentYearISO())

  const [query, setQuery] = useState("")
  const [searchResults, setSearchResults] = useState<SearchHit[]>([])

  const [showAllMonthly, setShowAllMonthly] = useState(false)
  const [showAllYearly, setShowAllYearly] = useState(false)
  const [showAllSessions, setShowAllSessions] = useState(false)
  const [showAllSearch, setShowAllSearch] = useState(false)

  const [tick, setTick] = useState(0)
  function refresh() {
    setTick((t) => t + 1)
  }

  useEffect(() => {
    setSessions(getSessionsByDate(date))
  }, [date, tick])

  const members = useMemo(() => {
    void tick
    return getMembers()
  }, [tick])

  const memberById = useMemo(() => {
    const map = new Map<string, Member>()
    for (const m of members) map.set(m.id, m)
    return map
  }, [members])

  const allSessions = useMemo(() => {
    void tick
    return getSessions()
  }, [tick])

  const sessionById = useMemo(() => {
    const map = new Map<string, Session>()
    for (const s of allSessions) map.set(s.id, s)
    return map
  }, [allSessions])

  function normalizeMemberId(rawMemberId: string) {
    if (memberById.has(rawMemberId)) return rawMemberId
    if (/^\d{6}$/.test(rawMemberId)) {
      const m = getMemberByOfflineCode(rawMemberId)
      if (m) return m.id
    }
    return rawMemberId
  }

  const rows = useMemo(() => {
    void tick
    return sessions.map((s) => {
      const clockins = getClockInsBySession(s.id)
      clockins.sort((a, b) => (a.clockedAt < b.clockedAt ? 1 : -1))
      const counts = countStatuses(clockins)
      return { session: s, counts, clockins }
    })
  }, [sessions, tick])

  const totals = useMemo(() => {
    return rows.reduce(
      (acc, r) => {
        acc.present += r.counts.present
        acc.absent += r.counts.absent
        acc.excused += r.counts.excused
        acc.marked += r.counts.marked
        return acc
      },
      { present: 0, absent: 0, excused: 0, marked: 0 } as Counts
    )
  }, [rows])

  function runSearch() {
    const raw = query.trim()
    if (!raw) {
      setSearchResults([])
      return
    }

    const q = raw.toLowerCase()
    let candidateMemberIds: string[] = []

    if (/^\d{6}$/.test(raw)) {
      const m = getMemberByOfflineCode(raw)
      if (m) candidateMemberIds.push(m.id)
    }

    candidateMemberIds.push(raw)

    const nameMatches = members
      .filter((m) => (m.fullName ?? "").toLowerCase().includes(q))
      .map((m) => m.id)

    candidateMemberIds.push(...nameMatches)
    candidateMemberIds = Array.from(new Set(candidateMemberIds))

    const hits: SearchHit[] = []
    for (const r of rows) {
      for (const c of r.clockins) {
        const normalized = normalizeMemberId(c.memberId)
        if (candidateMemberIds.includes(normalized)) {
          const member = memberById.get(normalized) ?? null
          hits.push({
            sessionName: r.session.name,
            sessionId: r.session.id,
            sessionDate: r.session.date,
            clockin: { ...c, memberId: normalized },
            member,
          })
        }
      }
    }

    hits.sort((a, b) => (a.clockin.clockedAt < b.clockin.clockedAt ? 1 : -1))
    setSearchResults(hits)
    setShowAllSearch(false)
  }

  function handleDownloadSummaryCSV() {
    const header = ["date", "session_name", "session_id", "present", "absent", "excused", "marked"]
    const lines = [header.join(",")]

    for (const r of rows) {
      lines.push(
        [
          csvEscape(date),
          csvEscape(r.session.name),
          csvEscape(r.session.id),
          r.counts.present,
          r.counts.absent,
          r.counts.excused,
          r.counts.marked,
        ].join(",")
      )
    }

    lines.push(
      [
        csvEscape(date),
        csvEscape("TOTAL"),
        csvEscape(""),
        totals.present,
        totals.absent,
        totals.excused,
        totals.marked,
      ].join(",")
    )

    downloadTextFile(`report-summary-${date}.csv`, lines.join("\n"))
  }

  function handleDownloadDetailedCSV() {
    const header = [
      "report_date",
      "session_date",
      "session_name",
      "session_id",
      "clockin_id",
      "member_name",
      "member_id",
      "team",
      "status",
      "method",
      "clockedAt",
    ]
    const lines = [header.join(",")]

    for (const r of rows) {
      for (const c of r.clockins) {
        const normalizedId = normalizeMemberId(c.memberId)
        const m = memberById.get(normalizedId)

        lines.push(
          [
            csvEscape(date),
            csvEscape(r.session.date),
            csvEscape(r.session.name),
            csvEscape(r.session.id),
            csvEscape(c.id),
            csvEscape(m?.fullName ?? "Unknown member"),
            csvEscape(normalizedId),
            csvEscape((m as any)?.team ?? ""),
            csvEscape(c.status),
            csvEscape(c.method),
            csvEscape(c.clockedAt),
          ].join(",")
        )
      }
    }

    downloadTextFile(`report-detailed-${date}.csv`, lines.join("\n"))
  }

  // ✅ SAFE RESET: clear clock-ins for all sessions on selected date
  function resetAttendanceForSelectedDate() {
    const ok = confirm(`This will reset ONLY attendance (clock-ins) for ${date}. Continue?`)
    if (!ok) return

    const daySessions = getSessionsByDate(date)
    if (daySessions.length === 0) {
      alert("No sessions found for this date.")
      return
    }

    daySessions.forEach((s) => clearSessionClockIns(s.id))

    setQuery("")
    setSearchResults([])
    setOpenSessionId(null)
    setShowAllSessions(false)
    setShowAllSearch(false)
    refresh()

    alert("Attendance reset done ✅")
  }

  const monthlyLeaderboard = useMemo<LeaderRow[]>(() => {
    const startISO = startOfMonthISO(monthISO)
    const endISO = endOfMonthISO(monthISO)

    const pointsByMember = new Map<string, number>()
    const allClockins = getClockIns()

    for (const c of allClockins) {
      if (c.status !== "present") continue
      const s = sessionById.get(c.sessionId)
      if (!s) continue
      if (s.date < startISO || s.date > endISO) continue

      const normalizedId = normalizeMemberId(c.memberId)
      pointsByMember.set(normalizedId, (pointsByMember.get(normalizedId) ?? 0) + 1)
    }

    const list: LeaderRow[] = []
    for (const [memberId, points] of pointsByMember.entries()) {
      const m = memberById.get(memberId)
      list.push({
        memberId,
        memberName: m?.fullName ?? "Unknown member",
        team: (m as any)?.team,
        offlineCode: m?.offlineCode,
        points,
      })
    }

    list.sort((a, b) => b.points - a.points || a.memberName.localeCompare(b.memberName))
    return list
  }, [monthISO, tick, sessionById, memberById])

  useEffect(() => {
    if (monthlyLeaderboard.length > 0) fireConfetti()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [monthISO])

  function downloadMonthlyLeaderboardCSV() {
    const header = ["month", "rank", "member_name", "member_id", "team", "offline_code", "points"]
    const lines = [header.join(",")]

    monthlyLeaderboard.forEach((r, idx) => {
      lines.push(
        [
          csvEscape(monthISO),
          idx + 1,
          csvEscape(r.memberName),
          csvEscape(r.memberId),
          csvEscape(r.team ?? ""),
          csvEscape(r.offlineCode ?? ""),
          r.points,
        ].join(",")
      )
    })

    downloadTextFile(`monthly-leaderboard-${monthISO}.csv`, lines.join("\n"))
  }

  const yearlyLeaderboard = useMemo<LeaderRow[]>(() => {
    const pointsByMember = new Map<string, number>()
    const allClockins = getClockIns()

    for (const c of allClockins) {
      if (c.status !== "present") continue
      const s = sessionById.get(c.sessionId)
      if (!s) continue
      if (!s.date.startsWith(yearISO + "-")) continue

      const normalizedId = normalizeMemberId(c.memberId)
      pointsByMember.set(normalizedId, (pointsByMember.get(normalizedId) ?? 0) + 1)
    }

    const list: LeaderRow[] = []
    for (const [memberId, points] of pointsByMember.entries()) {
      const m = memberById.get(memberId)
      list.push({
        memberId,
        memberName: m?.fullName ?? "Unknown member",
        team: (m as any)?.team,
        offlineCode: m?.offlineCode,
        points,
      })
    }

    list.sort((a, b) => b.points - a.points || a.memberName.localeCompare(b.memberName))
    return list
  }, [yearISO, tick, sessionById, memberById])

  function downloadYearlyLeaderboardCSV() {
    const header = ["year", "rank", "member_name", "member_id", "team", "offline_code", "points"]
    const lines = [header.join(",")]

    yearlyLeaderboard.forEach((r, idx) => {
      lines.push(
        [
          csvEscape(yearISO),
          idx + 1,
          csvEscape(r.memberName),
          csvEscape(r.memberId),
          csvEscape(r.team ?? ""),
          csvEscape(r.offlineCode ?? ""),
          r.points,
        ].join(",")
      )
    })

    downloadTextFile(`yearly-leaderboard-${yearISO}.csv`, lines.join("\n"))
  }

  const visibleMonthly = useMemo(
    () => (showAllMonthly ? monthlyLeaderboard : monthlyLeaderboard.slice(0, PREVIEW_LEADERS)),
    [monthlyLeaderboard, showAllMonthly]
  )

  const visibleYearly = useMemo(
    () => (showAllYearly ? yearlyLeaderboard : yearlyLeaderboard.slice(0, PREVIEW_LEADERS)),
    [yearlyLeaderboard, showAllYearly]
  )

  const visibleSessions = useMemo(
    () => (showAllSessions ? rows : rows.slice(0, PREVIEW_SESSIONS)),
    [rows, showAllSessions]
  )

  const visibleSearch = useMemo(
    () => (showAllSearch ? searchResults : searchResults.slice(0, PREVIEW_SEARCH)),
    [searchResults, showAllSearch]
  )

  return (
    <div className="space-y-5">
      {/* Header + Action Bar */}
      <div className="rounded-2xl bg-white p-4 shadow-sm">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h1 className="text-2xl font-semibold text-slate-900">Reports</h1>
            <p className="text-sm text-slate-800">
              Daily report + monthly & yearly leaderboard (points = present clock-ins).
            </p>
          </div>

          <div className="flex gap-2">
            <button
              type="button"
              onClick={refresh}
              className="rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm font-semibold text-slate-900 hover:bg-slate-50"
            >
              Refresh
            </button>

            {/* ✅ SAFE RESET ONLY */}
            <button
              type="button"
              onClick={resetAttendanceForSelectedDate}
              className="rounded-xl border border-rose-300 bg-rose-50 px-3 py-2 text-sm font-semibold text-rose-800 hover:bg-rose-100"
            >
              Reset attendance (selected date)
            </button>
          </div>
        </div>

        <div className="mt-3 rounded-xl border border-slate-200 bg-slate-50 p-3 text-xs text-slate-800">
          ✅ This reset clears <b>ONLY clock-ins</b> for the selected date. Programs, sessions, members remain.
        </div>
      </div>

      {/* Monthly Leaderboard */}
      <div className="rounded-2xl bg-white p-4 shadow-sm space-y-3">
        <div className="flex items-start justify-between gap-3">
          <div>
            <div className="text-sm font-semibold text-slate-900">Monthly Leaderboard</div>
            <div className="text-xs text-slate-700">
              Points = total <b>present</b> clock-ins in the month (3 services = 3 points).
            </div>
          </div>

          <div className="flex gap-2">
            {monthlyLeaderboard.length > PREVIEW_LEADERS ? (
              <button
                type="button"
                onClick={() => setShowAllMonthly((v) => !v)}
                className="rounded-xl border border-slate-300 bg-white px-3 py-2 text-xs font-semibold text-slate-900 hover:bg-slate-50"
              >
                {showAllMonthly ? "View less" : "View all"}
              </button>
            ) : null}

            <button
              type="button"
              onClick={downloadMonthlyLeaderboardCSV}
              className="rounded-xl border border-slate-300 bg-white px-3 py-2 text-xs font-semibold text-slate-900 hover:bg-slate-50"
            >
              Download CSV
            </button>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <label className="text-sm font-medium text-slate-900">Month</label>
          <input
            type="month"
            value={monthISO}
            onChange={(e) => {
              setMonthISO(e.target.value)
              setShowAllMonthly(false)
            }}
            className="rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 outline-none focus:border-slate-500"
          />
        </div>

        {monthlyLeaderboard.length === 0 ? (
          <div className="text-sm text-slate-700">No attendance records for this month yet.</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead>
                <tr className="text-xs text-slate-700">
                  <th className="py-2 pr-3">Rank</th>
                  <th className="py-2 pr-3">Member</th>
                  <th className="py-2 pr-3">Team</th>
                  <th className="py-2 pr-3">Member ID</th>
                  <th className="py-2 pr-3">Points</th>
                </tr>
              </thead>

              <tbody className="divide-y divide-slate-200">
                {visibleMonthly.map((r, idx) => (
                  <tr key={r.memberId} className={`text-slate-900 ${idx === 0 ? "bg-emerald-50" : ""}`}>
                    <td className="py-2 pr-3 font-semibold">
                      <span className="text-lg">{medal(idx + 1)}</span>
                    </td>

                    <td className="py-2 pr-3">
                      <div className="font-semibold">{r.memberName}</div>
                      {r.offlineCode ? (
                        <div className="text-[11px] text-slate-700">Code: {r.offlineCode}</div>
                      ) : null}
                    </td>

                    <td className="py-2 pr-3 text-xs text-slate-800">{r.team ?? ""}</td>
                    <td className="py-2 pr-3 text-xs text-slate-800">{r.memberId}</td>
                    <td className="py-2 pr-3 font-semibold">{r.points}</td>
                  </tr>
                ))}
              </tbody>
            </table>

            {monthlyLeaderboard.length > PREVIEW_LEADERS ? (
              <div className="mt-3">
                <button
                  type="button"
                  onClick={() => setShowAllMonthly((v) => !v)}
                  className="w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm font-semibold text-slate-900 hover:bg-slate-50"
                >
                  {showAllMonthly ? "View less" : `View all (${monthlyLeaderboard.length})`}
                </button>
              </div>
            ) : null}
          </div>
        )}
      </div>

      {/* Yearly Leaderboard */}
      <div className="rounded-2xl bg-white p-4 shadow-sm space-y-3">
        <div className="flex items-start justify-between gap-3">
          <div>
            <div className="text-sm font-semibold text-slate-900">Yearly Leaderboard</div>
            <div className="text-xs text-slate-700">End-of-year ranking (all months combined).</div>
          </div>

          <div className="flex gap-2">
            {yearlyLeaderboard.length > PREVIEW_LEADERS ? (
              <button
                type="button"
                onClick={() => setShowAllYearly((v) => !v)}
                className="rounded-xl border border-slate-300 bg-white px-3 py-2 text-xs font-semibold text-slate-900 hover:bg-slate-50"
              >
                {showAllYearly ? "View less" : "View all"}
              </button>
            ) : null}

            <button
              type="button"
              onClick={downloadYearlyLeaderboardCSV}
              className="rounded-xl border border-slate-300 bg-white px-3 py-2 text-xs font-semibold text-slate-900 hover:bg-slate-50"
            >
              Download CSV
            </button>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <label className="text-sm font-medium text-slate-900">Year</label>
          <input
            inputMode="numeric"
            value={yearISO}
            onChange={(e) => {
              setYearISO(e.target.value.replace(/\D/g, "").slice(0, 4))
              setShowAllYearly(false)
            }}
            placeholder="e.g. 2026"
            className="rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 outline-none focus:border-slate-500"
          />
        </div>

        {yearlyLeaderboard.length === 0 ? (
          <div className="text-sm text-slate-700">No attendance records for this year yet.</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead>
                <tr className="text-xs text-slate-700">
                  <th className="py-2 pr-3">Rank</th>
                  <th className="py-2 pr-3">Member</th>
                  <th className="py-2 pr-3">Team</th>
                  <th className="py-2 pr-3">Member ID</th>
                  <th className="py-2 pr-3">Points</th>
                </tr>
              </thead>

              <tbody className="divide-y divide-slate-200">
                {visibleYearly.map((r, idx) => (
                  <tr key={r.memberId} className="text-slate-900">
                    <td className="py-2 pr-3 font-semibold">
                      <span className="text-lg">{medal(idx + 1)}</span>
                    </td>

                    <td className="py-2 pr-3">
                      <div className="font-semibold">{r.memberName}</div>
                      {r.offlineCode ? (
                        <div className="text-[11px] text-slate-700">Code: {r.offlineCode}</div>
                      ) : null}
                    </td>

                    <td className="py-2 pr-3 text-xs text-slate-800">{r.team ?? ""}</td>
                    <td className="py-2 pr-3 text-xs text-slate-800">{r.memberId}</td>
                    <td className="py-2 pr-3 font-semibold">{r.points}</td>
                  </tr>
                ))}
              </tbody>
            </table>

            {yearlyLeaderboard.length > PREVIEW_LEADERS ? (
              <div className="mt-3">
                <button
                  type="button"
                  onClick={() => setShowAllYearly((v) => !v)}
                  className="w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm font-semibold text-slate-900 hover:bg-slate-50"
                >
                  {showAllYearly ? "View less" : `View all (${yearlyLeaderboard.length})`}
                </button>
              </div>
            ) : null}
          </div>
        )}
      </div>

      {/* Daily Controls */}
      <div className="rounded-2xl bg-white p-4 shadow-sm space-y-3">
        <div>
          <label className="text-sm font-medium text-slate-900">Select date</label>
          <input
            type="date"
            value={date}
            onChange={(e) => {
              setDate(e.target.value)
              setQuery("")
              setSearchResults([])
              setOpenSessionId(null)
              setShowAllSessions(false)
              setShowAllSearch(false)
            }}
            className="mt-2 w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 outline-none focus:border-slate-500"
          />
        </div>

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <button
            type="button"
            onClick={handleDownloadSummaryCSV}
            className="rounded-xl bg-slate-900 px-4 py-2 text-sm font-semibold text-white hover:bg-slate-800"
          >
            Download Summary CSV
          </button>

          <button
            type="button"
            onClick={handleDownloadDetailedCSV}
            className="rounded-xl border border-slate-300 bg-white px-4 py-2 text-sm font-semibold text-slate-900 hover:bg-slate-50"
          >
            Download Detailed CSV
          </button>

          <button
            type="button"
            onClick={refresh}
            className="rounded-xl border border-slate-300 bg-white px-4 py-2 text-sm font-semibold text-slate-900 hover:bg-slate-50"
          >
            Refresh
          </button>
        </div>

        {/* Search */}
        <div className="rounded-2xl border border-slate-200 bg-slate-50 p-3">
          <div className="flex items-start justify-between gap-3">
            <div>
              <div className="text-sm font-semibold text-slate-900">Search</div>
              <div className="text-xs text-slate-700">
                Search by <b>offline code</b>, <b>member ID</b> or <b>member name</b> for {date}.
              </div>
            </div>

            {searchResults.length > PREVIEW_SEARCH ? (
              <button
                type="button"
                onClick={() => setShowAllSearch((v) => !v)}
                className="shrink-0 rounded-xl border border-slate-300 bg-white px-3 py-2 text-xs font-semibold text-slate-900 hover:bg-slate-50"
              >
                {showAllSearch ? "View less" : "View all"}
              </button>
            ) : null}
          </div>

          <div className="mt-2 flex gap-2">
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="e.g. 123456 or Wunmi"
              className="w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 placeholder:text-slate-400 outline-none focus:border-slate-500"
            />
            <button
              type="button"
              onClick={runSearch}
              className="shrink-0 rounded-xl bg-slate-900 px-4 py-2 text-sm font-semibold text-white hover:bg-slate-800"
            >
              Search
            </button>
          </div>

          {searchResults.length > 0 ? (
            <div className="mt-3 space-y-2">
              <div className="text-xs text-slate-800">
                Found <b>{searchResults.length}</b> result(s)
              </div>

              {visibleSearch.map((r) => (
                <div
                  key={r.clockin.id}
                  className="rounded-xl border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-900"
                >
                  <div>
                    Member: <b>{r.member?.fullName ?? r.clockin.memberId}</b>{" "}
                    <span className="text-xs opacity-80">(ID: {r.clockin.memberId})</span>
                  </div>
                  <div className="text-xs">
                    Team: <b>{(r.member as any)?.team ?? ""}</b>
                  </div>
                  <div className="text-xs">
                    Session: <b>{r.sessionName}</b> • {r.sessionDate}
                  </div>
                  <div className="text-xs">
                    Status: <b>{r.clockin.status}</b> • Method: <b>{r.clockin.method}</b> •{" "}
                    {formatISOTime(r.clockin.clockedAt)}
                  </div>
                </div>
              ))}

              {searchResults.length > PREVIEW_SEARCH ? (
                <button
                  type="button"
                  onClick={() => setShowAllSearch((v) => !v)}
                  className="w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm font-semibold text-slate-900 hover:bg-slate-50"
                >
                  {showAllSearch ? "View less" : `View all (${searchResults.length})`}
                </button>
              ) : null}
            </div>
          ) : query.trim() ? (
            <div className="mt-3 rounded-xl border border-rose-200 bg-rose-50 p-3 text-sm text-rose-900">
              Not found for this date ❌
            </div>
          ) : null}
        </div>
      </div>

      {/* Totals */}
      <div className="rounded-2xl bg-white p-4 shadow-sm">
        <div className="text-sm font-semibold text-slate-900">Totals for {date}</div>

        <div className="mt-3 grid grid-cols-4 gap-3 text-center">
          <div className="rounded-xl bg-slate-50 p-3">
            <div className="text-lg font-semibold text-slate-900">{totals.present}</div>
            <div className="text-[11px] font-medium text-slate-800">Present</div>
          </div>
          <div className="rounded-xl bg-slate-50 p-3">
            <div className="text-lg font-semibold text-slate-900">{totals.absent}</div>
            <div className="text-[11px] font-medium text-slate-800">Absent</div>
          </div>
          <div className="rounded-xl bg-slate-50 p-3">
            <div className="text-lg font-semibold text-slate-900">{totals.excused}</div>
            <div className="text-[11px] font-medium text-slate-800">Excused</div>
          </div>
          <div className="rounded-xl bg-slate-50 p-3">
            <div className="text-lg font-semibold text-slate-900">{totals.marked}</div>
            <div className="text-[11px] font-medium text-slate-800">Marked</div>
          </div>
        </div>
      </div>

      {/* Sessions list */}
      <div className="rounded-2xl bg-white shadow-sm">
        <div className="flex items-start justify-between gap-3 border-b px-4 py-3">
          <div>
            <div className="text-sm font-semibold text-slate-900">Sessions on {date}</div>
            <div className="text-xs text-slate-700">Tap “View details” to see members.</div>
          </div>

          {rows.length > PREVIEW_SESSIONS ? (
            <button
              type="button"
              onClick={() => setShowAllSessions((v) => !v)}
              className="shrink-0 rounded-xl border border-slate-300 bg-white px-3 py-2 text-xs font-semibold text-slate-900 hover:bg-slate-50"
            >
              {showAllSessions ? "View less" : "View all"}
            </button>
          ) : null}
        </div>

        {rows.length === 0 ? (
          <div className="p-6 text-center text-sm text-slate-700">No sessions found for this date.</div>
        ) : (
          <ul className="divide-y">
            {visibleSessions.map(({ session, counts, clockins }) => {
              const isOpen = openSessionId === session.id

              return (
                <li key={session.id} className="p-4">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <div className="font-semibold text-slate-900">{session.name}</div>
                      <div className="text-xs text-slate-700">{session.date}</div>

                      <div className="mt-2 flex flex-wrap gap-2">
                        <span className="rounded-full bg-emerald-50 px-2.5 py-1 text-[11px] font-semibold text-emerald-800">
                          Present: {counts.present}
                        </span>
                        <span className="rounded-full bg-rose-50 px-2.5 py-1 text-[11px] font-semibold text-rose-800">
                          Absent: {counts.absent}
                        </span>
                        <span className="rounded-full bg-amber-50 px-2.5 py-1 text-[11px] font-semibold text-amber-800">
                          Excused: {counts.excused}
                        </span>
                        <span className="rounded-full bg-slate-100 px-2.5 py-1 text-[11px] font-semibold text-slate-800">
                          Marked: {counts.marked}
                        </span>
                      </div>
                    </div>

                    <div className="flex gap-2">
                      <button
                        type="button"
                        onClick={() => setOpenSessionId(isOpen ? null : session.id)}
                        className="rounded-xl border border-slate-300 bg-white px-3 py-2 text-xs font-semibold text-slate-900 hover:bg-slate-50"
                      >
                        {isOpen ? "Hide details" : "View details"}
                      </button>

                      <button
                        type="button"
                        onClick={() => {
                          const ok = confirm(`Reset ALL clock-ins for "${session.name}"?`)
                          if (!ok) return
                          clearSessionClockIns(session.id)
                          setSearchResults([])
                          setQuery("")
                          refresh()
                        }}
                        className="rounded-xl border border-rose-300 bg-white px-3 py-2 text-xs font-semibold text-rose-700 hover:bg-rose-50"
                      >
                        Reset clock-ins
                      </button>
                    </div>
                  </div>

                  {isOpen && (
                    <div className="mt-4 rounded-2xl border border-slate-200 bg-slate-50 p-3">
                      {clockins.length === 0 ? (
                        <div className="text-sm text-slate-700">No clock-ins yet.</div>
                      ) : (
                        <div className="overflow-x-auto">
                          <table className="w-full text-left text-sm">
                            <thead>
                              <tr className="text-xs text-slate-700">
                                <th className="py-2 pr-3">Member</th>
                                <th className="py-2 pr-3">Team</th>
                                <th className="py-2 pr-3">Status</th>
                                <th className="py-2 pr-3">Method</th>
                                <th className="py-2 pr-3">Time</th>
                              </tr>
                            </thead>

                            <tbody className="divide-y divide-slate-200">
                              {clockins.map((c) => {
                                const normalizedId = normalizeMemberId(c.memberId)
                                const m = memberById.get(normalizedId)

                                return (
                                  <tr key={c.id} className="text-slate-900">
                                    <td className="py-2 pr-3">
                                      <div className="font-semibold">{m?.fullName ?? "Unknown member"}</div>
                                      <div className="text-[11px] text-slate-700">ID: {normalizedId}</div>
                                    </td>
                                    <td className="py-2 pr-3 text-xs text-slate-800">{(m as any)?.team ?? ""}</td>
                                    <td className="py-2 pr-3">
                                      <span
                                        className={`rounded-full px-2 py-0.5 text-[11px] font-semibold ${
                                          c.status === "present"
                                            ? "bg-emerald-100 text-emerald-800"
                                            : c.status === "absent"
                                            ? "bg-rose-100 text-rose-800"
                                            : "bg-amber-100 text-amber-800"
                                        }`}
                                      >
                                        {c.status}
                                      </span>
                                    </td>
                                    <td className="py-2 pr-3 text-xs text-slate-800">{c.method}</td>
                                    <td className="py-2 pr-3 text-xs text-slate-800">{formatISOTime(c.clockedAt)}</td>
                                  </tr>
                                )
                              })}
                            </tbody>
                          </table>
                        </div>
                      )}
                    </div>
                  )}
                </li>
              )
            })}
          </ul>
        )}

        {rows.length > PREVIEW_SESSIONS ? (
          <div className="border-t p-3">
            <button
              type="button"
              onClick={() => setShowAllSessions((v) => !v)}
              className="w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm font-semibold text-slate-900 hover:bg-slate-50"
            >
              {showAllSessions ? "View less" : `View all (${rows.length})`}
            </button>
          </div>
        ) : null}
      </div>
    </div>
  )
}