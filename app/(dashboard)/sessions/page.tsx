// app/(dashboard)/sessions/page.tsx

"use client"

import Link from "next/link"
import { useEffect, useState } from "react"
import { getSessionsByDate } from "@/lib/core/sessions"
import { getClockInsBySession } from "@/lib/core/clockins"
import type { Session } from "@/lib/types"

function todayISO() {
  return new Date().toISOString().slice(0, 10)
}

function presentCount(sessionId: string) {
  return getClockInsBySession(sessionId).filter((c) => c.status === "present").length
}

export default function SessionsPage() {
  const [date, setDate] = useState(todayISO())
  const [sessions, setSessions] = useState<Session[]>([])
  const [tick, setTick] = useState(0)

  useEffect(() => {
    setSessions(getSessionsByDate(date))
  }, [date, tick])

  useEffect(() => {
    const onFocus = () => setTick((t) => t + 1)
    window.addEventListener("focus", onFocus)
    return () => window.removeEventListener("focus", onFocus)
  }, [])

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-slate-900">Sessions</h1>
        <p className="text-sm text-slate-900">
          Select a date to view sessions and clock members in.
        </p>
      </div>

      <div className="rounded-2xl bg-white p-4 shadow-sm">
        <label className="text-sm font-medium text-slate-900">Select date</label>
        <input
          type="date"
          value={date}
          onChange={(e) => setDate(e.target.value)}
          className="mt-2 w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 outline-none focus:border-slate-500"
        />
      </div>

      <div className="rounded-2xl bg-white shadow-sm">
        <div className="border-b px-4 py-3">
          <h2 className="text-sm font-semibold text-slate-900">Sessions on {date}</h2>
        </div>

        {sessions.length === 0 ? (
          <div className="p-6 text-center text-sm text-slate-700">
            No sessions found for this date.
          </div>
        ) : (
          <ul className="divide-y">
            {sessions.map((s) => {
              const present = presentCount(s.id)

              return (
                <li key={s.id} className="p-4">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <div className="font-medium text-slate-900">{s.name}</div>
                      <div className="text-xs text-slate-800">{s.date}</div>

                      <div className="mt-2 inline-flex rounded-full bg-slate-100 px-2.5 py-1 text-[11px] font-semibold text-slate-800">
                        Present: {present}
                      </div>
                    </div>

                    <Link
                      href={`/sessions/${s.id}/check-in`}
                      className="shrink-0 rounded-xl bg-slate-900 px-3 py-2 text-xs font-semibold text-white hover:bg-slate-800"
                    >
                      Check-in
                    </Link>
                  </div>
                </li>
              )
            })}
          </ul>
        )}
      </div>
    </div>
  )
}