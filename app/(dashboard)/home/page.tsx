"use client"

import Image from "next/image"
import Link from "next/link"
import { useEffect, useMemo, useState } from "react"
import { getSessionsByDate } from "@/lib/core/sessions"
import { getClockInsBySession } from "@/lib/core/clockins"
import { getMembers } from "@/lib/core/members"
import type { ClockIn, Member, Session } from "@/lib/types"

/* =========================
   UTILITIES
========================= */

function formatDateISO(d: Date) {
  return d.toISOString().slice(0, 10)
}

function greetingFromHour(hour: number) {
  if (hour < 12) return "Good morning"
  if (hour < 18) return "Good afternoon"
  return "Good evening"
}

function pad2(n: number) {
  return String(n).padStart(2, "0")
}

function mmddFromDate(d: Date) {
  return `${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`
}

function dateFromMMDD(mmdd: string) {
  const [mm, dd] = mmdd.split("-").map(Number)
  const year = new Date().getFullYear()
  return new Date(year, mm - 1, dd)
}

function isWithinDays(target: Date, days: number) {
  const today = new Date()
  today.setHours(0, 0, 0, 0)

  const end = new Date(today)
  end.setDate(today.getDate() + days)

  return target > today && target <= end
}

export default function HomePage() {
  const [now, setNow] = useState(new Date())
  const [tick, setTick] = useState(0)

  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 60000)
    return () => clearInterval(id)
  }, [])

  useEffect(() => {
    const onFocus = () => setTick((t) => t + 1)
    window.addEventListener("focus", onFocus)
    return () => window.removeEventListener("focus", onFocus)
  }, [])

  const dateISO = useMemo(() => formatDateISO(now), [now])
  const greeting = useMemo(() => greetingFromHour(now.getHours()), [now])
  const todayMMDD = useMemo(() => mmddFromDate(now), [now])

  const members = useMemo<Member[]>(() => {
    void tick
    return getMembers()
  }, [tick])

  /* =========================
     🎉 CELEBRATIONS
  ========================= */

  const todaysBirthdays = members.filter(
    (m) => m.birthdayMD === todayMMDD
  )

  const todaysAnniversaries = members.filter(
    (m) => m.anniversaryMD === todayMMDD
  )

  const upcomingBirthdays = members.filter((m) => {
    if (!m.birthdayMD || m.birthdayMD === todayMMDD) return false
    return isWithinDays(dateFromMMDD(m.birthdayMD), 7)
  })

  const upcomingAnniversaries = members.filter((m) => {
    if (!m.anniversaryMD || m.anniversaryMD === todayMMDD) return false
    return isWithinDays(dateFromMMDD(m.anniversaryMD), 7)
  })

  /* =========================
     ATTENDANCE
  ========================= */

  const sessions = useMemo<Session[]>(() => {
    void tick
    return getSessionsByDate(dateISO)
  }, [dateISO, tick])

  const todayClockIns = useMemo<ClockIn[]>(() => {
    return sessions.flatMap((s) => getClockInsBySession(s.id))
  }, [sessions])

  const presentUnique = useMemo(() => {
    const set = new Set<string>()
    todayClockIns.forEach((c) => {
      if (c.status === "present") set.add(c.memberId)
    })
    return set.size
  }, [todayClockIns])

  const totalMembers = members.length
  const unmarked = Math.max(0, totalMembers - presentUnique)

  /* =========================
     BUTTON STYLE
  ========================= */

  const actionBtn =
    "block w-full rounded-2xl border border-slate-200 bg-white px-4 py-4 text-center text-sm font-semibold text-slate-900 shadow-sm transition hover:bg-slate-900 hover:text-white hover:border-slate-900 active:scale-[0.99]"

  return (
    <div className="space-y-6">

      {/* HEADER */}
      <div className="rounded-3xl bg-white p-6 shadow-sm text-center">
        <Image
          src="/elevation-logo.png"
          alt="Elevation"
          width={72}
          height={72}
          className="mx-auto mb-4"
        />
        <div className="text-xl font-bold text-slate-900">
          {greeting} 👋
        </div>
        <div className="text-sm font-medium text-slate-700">
          Guest Welcome Unit
        </div>
        <div className="text-xs text-slate-500 mt-1">
          {dateISO}
        </div>
      </div>

      {/* CELEBRATIONS */}
      {(todaysBirthdays.length > 0 ||
        todaysAnniversaries.length > 0 ||
        upcomingBirthdays.length > 0 ||
        upcomingAnniversaries.length > 0) && (
        <div className="rounded-2xl border border-amber-200 bg-amber-50 p-4 shadow-sm space-y-2">
          <div className="text-sm font-bold text-amber-900">
            🎉 Celebrations
          </div>

          {todaysBirthdays.map((m) => (
            <div key={m.id} className="text-sm font-semibold text-slate-900">
              🎂 {m.fullName} (Birthday)
            </div>
          ))}

          {todaysAnniversaries.map((m) => (
            <div key={m.id} className="text-sm font-semibold text-slate-900">
              💍 {m.fullName} (Anniversary)
            </div>
          ))}

          {upcomingBirthdays.map((m) => (
            <div key={m.id} className="text-sm text-slate-800">
              🎂 {m.fullName} — {m.birthdayMD}
            </div>
          ))}

          {upcomingAnniversaries.map((m) => (
            <div key={m.id} className="text-sm text-slate-800">
              💍 {m.fullName} — {m.anniversaryMD}
            </div>
          ))}
        </div>
      )}

      {/* TODAY STATUS (clean, not bulky) */}
      <div className="rounded-2xl bg-white p-5 shadow-sm">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-lg font-bold text-slate-900">
              Today
            </div>
            <div className="text-sm text-slate-600 mt-1">
              {sessions.length === 0
                ? "No sessions scheduled"
                : `${sessions.length} session${
                    sessions.length > 1 ? "s" : ""
                  } scheduled`}
            </div>
          </div>

          {sessions.length === 0 ? (
            <Link href="/programs" className={actionBtn}>
              Create program
            </Link>
          ) : (
            <Link href="/sessions" className={actionBtn}>
              Open sessions
            </Link>
          )}
        </div>
      </div>

      {/* ATTENDANCE */}
      <div className="rounded-2xl bg-white p-5 shadow-sm">
        <div className="text-lg font-bold text-slate-900">
          Today’s Attendance
        </div>

        <div className="mt-5 grid grid-cols-3 gap-4 text-center">
          <div className="rounded-2xl bg-slate-50 p-4">
            <div className="text-2xl font-extrabold text-slate-900">
              {presentUnique}
            </div>
            <div className="text-sm font-medium text-slate-700">
              Present
            </div>
          </div>

          <div className="rounded-2xl bg-slate-50 p-4">
            <div className="text-2xl font-extrabold text-slate-900">
              {unmarked}
            </div>
            <div className="text-sm font-medium text-slate-700">
              Unmarked
            </div>
          </div>

          <div className="rounded-2xl bg-slate-50 p-4">
            <div className="text-2xl font-extrabold text-slate-900">
              {totalMembers}
            </div>
            <div className="text-sm font-medium text-slate-700">
              Members
            </div>
          </div>
        </div>
      </div>

      {/* QUICK ACTIONS */}
      <div className="rounded-2xl bg-white p-5 shadow-sm">
        <div className="text-sm font-bold text-slate-900 mb-4">
          Quick actions
        </div>

        <div className="space-y-4">
          <Link
            href="/sessions"
            className="block w-full rounded-2xl bg-slate-900 px-4 py-4 text-center text-sm font-semibold text-white shadow-sm transition hover:bg-slate-900 active:scale-[0.99]"
          >
            Mark attendance
          </Link>

          <div className="grid grid-cols-2 gap-4">
            <Link href="/sessions" className={actionBtn}>
              Sessions
            </Link>

            <Link href="/programs" className={actionBtn}>
              Programs
            </Link>

            <Link href="/members" className={actionBtn}>
              Members
            </Link>

            <Link href="/reports" className={actionBtn}>
              Reports
            </Link>
          </div>
        </div>
      </div>
    </div>
  )
}