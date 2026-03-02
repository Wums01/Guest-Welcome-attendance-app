// app/(dashboard)/sessions/[id]/check-in/page.tsx

"use client"

import Link from "next/link"
import { useMemo, useEffect, useState } from "react"
import { useParams, useSearchParams } from "next/navigation"
import { getSessions } from "@/lib/core/sessions"

type ServiceMeta = {
  label: string
  serviceTime: string // "07:00"
  opensAt: string // "06:30"
}

// Lagos time rules
const SERVICE_RULES: Record<string, ServiceMeta> = {
  "Service 1": { label: "First Service", serviceTime: "07:00", opensAt: "06:30" },
  "Service 2": { label: "Second Service", serviceTime: "09:00", opensAt: "08:30" },
  "Service 3": { label: "Third Service", serviceTime: "11:30", opensAt: "11:00" },
}

function pad2(n: number) {
  return String(n).padStart(2, "0")
}

// ✅ Lagos time utilities (no external libs)
function nowInLagos(): Date {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Africa/Lagos",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).formatToParts(new Date())

  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "00"
  const yyyy = Number(get("year"))
  const mm = Number(get("month"))
  const dd = Number(get("day"))
  const hh = Number(get("hour"))
  const mi = Number(get("minute"))
  const ss = Number(get("second"))

  // Build a Date in local runtime timezone but representing Lagos clock time
  return new Date(yyyy, mm - 1, dd, hh, mi, ss)
}

function dateTimeFromISOAndHHMM(dateISO: string, hhmm: string) {
  const [y, m, d] = dateISO.split("-").map(Number)
  const [hh, mm] = hhmm.split(":").map(Number)
  return new Date(y, m - 1, d, hh, mm, 0)
}

function msToCountdown(ms: number) {
  if (ms <= 0) return "Open now"
  const totalMins = Math.ceil(ms / 60000)
  if (totalMins < 60) return `Opens in ${totalMins} min${totalMins === 1 ? "" : "s"}`
  const hrs = Math.floor(totalMins / 60)
  const mins = totalMins % 60
  return `Opens in ${hrs}h ${mins}m`
}

function inferServiceMeta(sessionName: string): ServiceMeta | null {
  const n = sessionName.toLowerCase()

  // best match first
  if (n.includes("service 1") || n.includes("first")) return SERVICE_RULES["Service 1"]
  if (n.includes("service 2") || n.includes("second")) return SERVICE_RULES["Service 2"]
  if (n.includes("service 3") || n.includes("third")) return SERVICE_RULES["Service 3"]

  return null
}

export default function CheckInPage() {
  const params = useParams<{ id: string }>()
  const sessionId = params.id

  const searchParams = useSearchParams()
  const testMode = searchParams.get("test") === "1" // ✅ force open with ?test=1

  const session = useMemo(() => {
    return getSessions().find((s) => s.id === sessionId)
  }, [sessionId])

  const meta = useMemo(() => {
    if (!session) return null
    return inferServiceMeta(session.name)
  }, [session])

  const [lagosNow, setLagosNow] = useState<Date>(() => nowInLagos())

  useEffect(() => {
    const t = setInterval(() => setLagosNow(nowInLagos()), 1000)
    return () => clearInterval(t)
  }, [])

  if (!session) {
    return (
      <div className="rounded-2xl bg-white p-6 shadow-sm text-sm text-slate-700">
        Session not found.{" "}
        <Link href="/sessions" className="underline">
          Go back
        </Link>
      </div>
    )
  }

  const opensAt = meta?.opensAt
  const opensAtDate = opensAt ? dateTimeFromISOAndHHMM(session.date, opensAt) : null

  // ✅ Open rules:
  // - If it has Sunday service timing -> open only when Lagos time >= opensAt
  // - If no timing (non-Sunday sessions) -> open anytime
  // - testMode always forces open
  const isOpen = testMode ? true : opensAtDate ? lagosNow.getTime() >= opensAtDate.getTime() : true
  const msUntilOpen = opensAtDate ? opensAtDate.getTime() - lagosNow.getTime() : 0

  const lagosClock = `${pad2(lagosNow.getHours())}:${pad2(lagosNow.getMinutes())}`

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="rounded-3xl bg-white p-5 shadow-sm">
        <div className="flex items-center justify-between gap-3">
          <div>
            <div className="text-xs text-slate-500">Guest Welcome Unit</div>
            <div className="mt-1 text-lg font-semibold text-slate-900">{session.name}</div>
            <div className="text-sm text-slate-500">{session.date}</div>
          </div>

          <div className="text-right">
            <div className="text-[11px] text-slate-500">Lagos time</div>
            <div className="text-sm font-semibold text-slate-900">{lagosClock}</div>
          </div>
        </div>

        {/* Timing card */}
        {meta ? (
          <div className="mt-4 rounded-2xl border border-slate-200 bg-slate-50 p-4">
            <div className="flex items-start justify-between gap-4">
              <div>
                <div className="text-sm font-semibold text-slate-900">{meta.label}</div>
                <div className="text-xs text-slate-600">
                  Service: <span className="font-medium">{meta.serviceTime}</span> • Clock-in opens:{" "}
                  <span className="font-medium">{meta.opensAt}</span>
                </div>
              </div>

              <span
                className={`shrink-0 rounded-full px-2.5 py-1 text-[11px] font-semibold ${
                  isOpen ? "bg-emerald-100 text-emerald-800" : "bg-amber-100 text-amber-800"
                }`}
              >
                {isOpen ? "Open" : "Closed"}
              </span>
            </div>

            {!isOpen && (
              <div className="mt-2 text-xs font-medium text-amber-800">
                {msToCountdown(msUntilOpen)}
              </div>
            )}

            {testMode && (
              <div className="mt-2 text-xs font-semibold text-indigo-700">
                Test mode ON (forced open)
              </div>
            )}
          </div>
        ) : (
          <div className="mt-4 rounded-2xl border border-slate-200 bg-slate-50 p-4 text-xs text-slate-600">
            No service timing for this session. Clock-in is allowed anytime.
          </div>
        )}

        <div className="mt-4">
          <Link
            href="/sessions"
            className="inline-flex rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-medium text-slate-900 hover:bg-slate-50"
          >
            Back
          </Link>
        </div>
      </div>

      {/* Methods */}
      <div className="rounded-2xl bg-white p-5 shadow-sm space-y-3">
        <div>
          <div className="text-sm font-semibold text-slate-900">Choose check-in method</div>
          <div className="text-xs text-slate-500">
            Team leads can clock members in by scanning or entering a 6-digit code.
          </div>
        </div>

        {/* Scan */}
        <Link
          href={isOpen ? `/sessions/${sessionId}/scan` : "#"}
          aria-disabled={!isOpen}
          className={`block rounded-2xl px-4 py-4 text-center text-sm font-semibold ${
            isOpen
              ? "bg-slate-900 text-white hover:bg-slate-800"
              : "bg-slate-200 text-slate-500 cursor-not-allowed"
          }`}
          onClick={(e) => {
            if (!isOpen) e.preventDefault()
          }}
        >
          Scan code
          <div className={`mt-1 text-[11px] font-normal ${isOpen ? "text-slate-200" : "text-slate-600"}`}>
            QR / Barcode (camera)
          </div>
        </Link>

        {/* Offline Code */}
        <Link
          href={isOpen ? `/sessions/${sessionId}/code` : "#"}
          aria-disabled={!isOpen}
          className={`block rounded-2xl border px-4 py-4 text-center text-sm font-semibold ${
            isOpen
              ? "border-slate-300 bg-white text-slate-900 hover:bg-slate-50"
              : "border-slate-200 bg-slate-100 text-slate-400 cursor-not-allowed"
          }`}
          onClick={(e) => {
            if (!isOpen) e.preventDefault()
          }}
        >
          Enter offline code
          <div className="mt-1 text-[11px] font-normal text-slate-600">6-digit numeric code</div>
        </Link>

        {!isOpen && meta && (
          <div className="rounded-2xl border border-amber-200 bg-amber-50 p-4 text-xs text-amber-900">
            Clock-in opens at <b>{meta.opensAt}</b> (Lagos time).
            <br />
            To test now, add <b>?test=1</b> to the URL.
          </div>
        )}
      </div>
    </div>
  )
}