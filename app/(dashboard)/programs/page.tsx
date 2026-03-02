// app/(dashboard)/programs/page.tsx

"use client"

import { useEffect, useMemo, useState } from "react"
import type { Program, ProgramType, Team } from "@/lib/types"
import { createProgram, deleteProgram, getPrograms } from "@/lib/core/programs"
import {
  createSundaySessions,
  createWednesdaySessions,
  createSession,
  getSessionsByProgram,
} from "@/lib/core/sessions"

const programTypes: { label: string; value: ProgramType }[] = [
  { label: "Sunday Service", value: "sunday" },
  { label: "Wednesday Switch Service", value: "wednesday" },
  { label: "Program", value: "program" },
  { label: "Meeting", value: "meeting" },
  { label: "Training", value: "training" },
]

const teams: Team[] = ["Team A", "Team B", "Team C"]

function todayISO() {
  return new Date().toISOString().slice(0, 10)
}

function currentMonthKey() {
  return new Date().toISOString().slice(0, 7) // YYYY-MM
}

function formatMonthLabel(key: string) {
  const [year, month] = key.split("-").map(Number)
  const d = new Date(year, month - 1, 1)
  return d.toLocaleString("default", { month: "long", year: "numeric" })
}

function niceType(t: ProgramType) {
  if (t === "sunday") return "Sunday"
  if (t === "wednesday") return "Wednesday"
  if (t === "meeting") return "Meeting"
  if (t === "training") return "Training"
  return "Program"
}

function safeMonthKey(p: Program) {
  // ✅ Group TBD programs separately
  if (p.isTBD || !p.startDate) return "TBD"
  return p.startDate.slice(0, 7)
}

function formatProgramDateRange(p: Program) {
  if (p.isTBD || !p.startDate || !p.endDate) return "TBD"
  return `${p.startDate} → ${p.endDate}`
}

export default function ProgramsPage() {
  const [programs, setPrograms] = useState<Program[]>([])

  // Month accordion (current month open by default)
  const [expandedMonths, setExpandedMonths] = useState<string[]>([currentMonthKey()])

  // Per-program session accordion
  const [expandedProgramId, setExpandedProgramId] = useState<string | null>(null)

  // Create program form
  const [title, setTitle] = useState("")
  const [programType, setProgramType] = useState<ProgramType>("sunday")

  // ✅ TBD toggle
  const [isTBD, setIsTBD] = useState(false)

  const [startDate, setStartDate] = useState(todayISO())
  const [endDate, setEndDate] = useState(todayISO())
  const [teamScope, setTeamScope] = useState<"all" | Team>("all")

  // Add extra session form (shown inside expanded program)
  const [sessionName, setSessionName] = useState("")
  const [sessionDate, setSessionDate] = useState(todayISO())

  useEffect(() => {
    setPrograms(getPrograms())
  }, [])

  function refresh() {
    setPrograms(getPrograms())
  }

  const grouped = useMemo(() => {
    const map: Record<string, Program[]> = {}

    programs.forEach((p) => {
      const key = safeMonthKey(p)
      if (!map[key]) map[key] = []
      map[key].push(p)
    })

    // sort:
    // - TBD first
    // - then newest month first
    const entries = Object.entries(map).sort((a, b) => {
      if (a[0] === "TBD" && b[0] !== "TBD") return -1
      if (b[0] === "TBD" && a[0] !== "TBD") return 1
      return a[0] > b[0] ? -1 : 1
    })

    return entries
  }, [programs])

  function toggleMonth(key: string) {
    setExpandedMonths((prev) =>
      prev.includes(key) ? prev.filter((m) => m !== key) : [...prev, key]
    )
  }

  function handleCreateProgram(e: React.FormEvent) {
    e.preventDefault()

    const name = title.trim()
    if (!name) {
      alert("Program title is required")
      return
    }

    // ✅ Create program with TBD support
    const created = isTBD
      ? createProgram({
          title: name,
          programType,
          teamScope,
          isTBD: true,
        })
      : createProgram({
          title: name,
          programType,
          startDate,
          endDate,
          teamScope,
          isTBD: false,
        })

    // ✅ Auto sessions ONLY when NOT TBD and when startDate exists
    if (!created.isTBD && created.startDate) {
      if (programType === "sunday") createSundaySessions(created.id, created.startDate)
      if (programType === "wednesday") createWednesdaySessions(created.id, created.startDate)
    }

    setTitle("")
    refresh()

    // ✅ open month group + open program
    const monthKey = safeMonthKey(created)
    if (!expandedMonths.includes(monthKey)) {
      setExpandedMonths((prev) => [...prev, monthKey])
    }
    setExpandedProgramId(created.id)
  }

  function handleCreateManualSession(programId: string) {
    if (!sessionName.trim()) {
      alert("Session name is required")
      return
    }
    if (!sessionDate) {
      alert("Session date is required")
      return
    }

    createSession({
      programId,
      name: sessionName.trim(),
      date: sessionDate,
    })

    setSessionName("")
    refresh()
    setExpandedProgramId(programId)
  }

  function handleDeleteProgram(programId: string, title: string) {
    const ok = confirm(
      `Delete "${title}"?\n\nThis will also delete all sessions under it.\n(Recommended only during testing)`
    )
    if (!ok) return

    // ✅ deleteProgram already deletes sessions too (in our core)
    deleteProgram(programId)

    setExpandedProgramId((prev) => (prev === programId ? null : prev))
    refresh()
  }

  const card = "rounded-2xl bg-white p-4 shadow-sm"
  const btnHoverDark =
    "rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-900 transition hover:bg-slate-900 hover:text-white"
  const btnDanger =
    "rounded-xl border border-rose-200 bg-rose-50 px-3 py-2 text-sm font-semibold text-rose-800 transition hover:bg-rose-100"

  return (
    <div className="space-y-6">
      {/* CREATE PROGRAM */}
      <form onSubmit={handleCreateProgram} className={card}>
        <div className="space-y-4">
          <div className="text-lg font-bold text-slate-900">Create Program</div>

          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Program title (e.g. March Meeting)"
            className="w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 placeholder:text-slate-400 outline-none focus:border-slate-500"
          />

          <div className="grid grid-cols-2 gap-3">
            <select
              value={programType}
              onChange={(e) => setProgramType(e.target.value as ProgramType)}
              className="w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 outline-none focus:border-slate-500"
            >
              {programTypes.map((t) => (
                <option key={t.value} value={t.value}>
                  {t.label}
                </option>
              ))}
            </select>

            <select
              value={teamScope}
              onChange={(e) => setTeamScope(e.target.value as any)}
              className="w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 outline-none focus:border-slate-500"
            >
              <option value="all">All teams</option>
              {teams.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </select>
          </div>

          {/* ✅ TBD toggle */}
          <div className="rounded-2xl border border-slate-200 bg-slate-50 p-3">
            <label className="flex items-center gap-2 text-sm font-semibold text-slate-900">
              <input
                type="checkbox"
                checked={isTBD}
                onChange={(e) => setIsTBD(e.target.checked)}
                className="h-4 w-4"
              />
              Date is TBD (I don’t know the date yet)
            </label>
            <div className="mt-1 text-xs text-slate-600">
              If checked, the program will be saved under <b>TBD</b>. You can later edit the dates when you’re ready.
            </div>
          </div>

          {/* Dates (disabled when TBD) */}
          <div className={`grid grid-cols-2 gap-3 ${isTBD ? "opacity-50" : ""}`}>
            <div>
              <div className="text-xs font-semibold text-slate-700">Start date</div>
              <input
                type="date"
                value={startDate}
                onChange={(e) => setStartDate(e.target.value)}
                disabled={isTBD}
                className="mt-1 w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 outline-none focus:border-slate-500 disabled:bg-slate-100 disabled:cursor-not-allowed"
              />
            </div>

            <div>
              <div className="text-xs font-semibold text-slate-700">End date</div>
              <input
                type="date"
                value={endDate}
                onChange={(e) => setEndDate(e.target.value)}
                disabled={isTBD}
                className="mt-1 w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 outline-none focus:border-slate-500 disabled:bg-slate-100 disabled:cursor-not-allowed"
              />
            </div>
          </div>

          <div className="text-xs text-slate-700">
            ✅ Sunday/Wed auto-create sessions only when a date is set. ✅ For Program/Meeting/Training, add sessions only if needed.
          </div>

          <button
            type="submit"
            className="w-full rounded-xl bg-slate-900 py-3 text-sm font-semibold text-white transition hover:bg-slate-800"
          >
            Create Program
          </button>
        </div>
      </form>

      {/* PROGRAM LIST BY MONTH */}
      {grouped.length === 0 ? (
        <div className={card}>No programs created yet.</div>
      ) : (
        grouped.map(([monthKey, list]) => {
          const open = expandedMonths.includes(monthKey)

          return (
            <div key={monthKey} className={card}>
              <button
                type="button"
                onClick={() => toggleMonth(monthKey)}
                className="flex w-full items-center justify-between"
              >
                <div className="text-lg font-bold text-slate-900">
                  {monthKey === "TBD" ? "TBD (Dates not set yet)" : formatMonthLabel(monthKey)}
                </div>
                <div className="text-sm text-slate-500">{open ? "Hide" : "View"}</div>
              </button>

              {open ? (
                <div className="mt-4 space-y-4">
                  {list.map((p) => {
                    const sessions = getSessionsByProgram(p.id)
                    const programOpen = expandedProgramId === p.id
                    const auto = p.programType === "sunday" || p.programType === "wednesday"

                    return (
                      <div key={p.id} className="rounded-xl border border-slate-200 p-3">
                        <div className="flex items-start justify-between gap-3">
                          <div>
                            <div className="font-semibold text-slate-900">{p.title}</div>
                            <div className="text-xs text-slate-600">
                              {formatProgramDateRange(p)} • {niceType(p.programType)} •{" "}
                              {p.teamScope ?? "all"}
                            </div>
                            <div className="mt-1 text-xs text-slate-500">
                              Sessions: <b>{sessions.length}</b>
                            </div>
                          </div>

                          <div className="flex flex-col gap-2">
                            <button
                              type="button"
                              onClick={() => setExpandedProgramId(programOpen ? null : p.id)}
                              className={btnHoverDark}
                            >
                              {programOpen ? "Hide sessions" : "View sessions"}
                            </button>

                            <button
                              type="button"
                              onClick={() => handleDeleteProgram(p.id, p.title)}
                              className={btnDanger}
                            >
                              Delete
                            </button>
                          </div>
                        </div>

                        {programOpen ? (
                          <div className="mt-3 space-y-3">
                            {sessions.length === 0 ? (
                              <div className="rounded-xl bg-slate-50 p-3 text-sm text-slate-700">
                                No sessions yet.
                              </div>
                            ) : (
                              <div className="space-y-2">
                                {sessions.map((s) => (
                                  <div
                                    key={s.id}
                                    className="rounded-lg bg-slate-50 px-3 py-2 text-sm text-slate-900"
                                  >
                                    {s.name} — {s.date}
                                  </div>
                                ))}
                              </div>
                            )}

                            {/* Add extra session ONLY if not auto program */}
                            {!auto ? (
                              <div className="rounded-xl border border-slate-200 bg-white p-3">
                                <div className="text-sm font-semibold text-slate-900">
                                  Add extra session
                                </div>
                                <div className="text-xs text-slate-600">
                                  Use only if you need to add something special.
                                </div>

                                <div className="mt-3 space-y-2">
                                  <input
                                    value={sessionName}
                                    onChange={(e) => setSessionName(e.target.value)}
                                    placeholder="Session name (e.g. Day 2 / Morning / Evening)"
                                    className="w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 placeholder:text-slate-400 outline-none focus:border-slate-500"
                                  />

                                  <input
                                    type="date"
                                    value={sessionDate}
                                    onChange={(e) => setSessionDate(e.target.value)}
                                    className="w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 outline-none focus:border-slate-500"
                                  />

                                  <button
                                    type="button"
                                    onClick={() => handleCreateManualSession(p.id)}
                                    className="w-full rounded-xl bg-slate-900 py-2 text-sm font-semibold text-white transition hover:bg-slate-800"
                                  >
                                    Add session
                                  </button>
                                </div>
                              </div>
                            ) : null}
                          </div>
                        ) : null}
                      </div>
                    )
                  })}
                </div>
              ) : null}
            </div>
          )
        })
      )}
    </div>
  )
}