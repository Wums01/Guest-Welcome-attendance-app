"use client"

import Link from "next/link"
import { useMemo, useState } from "react"
import { useParams, useRouter } from "next/navigation"
import { getSessions } from "@/lib/core/sessions"
import { clockInByOfflineCode } from "@/lib/core/clockins"

function onlyDigits(s: string) {
  return s.replace(/\D/g, "")
}

type MarkStatus = "present" | "excused"

export default function OfflineCodePage() {
  const router = useRouter()
  const params = useParams<{ id: string }>()
  const sessionId = params.id

  const session = useMemo(
    () => getSessions().find((s) => s.id === sessionId),
    [sessionId]
  )

  const [code, setCode] = useState("")
  const [markAs, setMarkAs] = useState<MarkStatus>("present")

  const [status, setStatus] = useState<"idle" | "success" | "error" | "warning">(
    "idle"
  )
  const [message, setMessage] = useState<string>("")
  const [isLoading, setIsLoading] = useState(false)

  function handleChange(value: string) {
    const digits = onlyDigits(value).slice(0, 6)
    setCode(digits)
    setStatus("idle")
    setMessage("")
  }

  async function submit() {
    if (code.length !== 6) {
      setStatus("error")
      setMessage("Enter a valid 6-digit code.")
      return
    }

    try {
      setIsLoading(true)

      clockInByOfflineCode({
        sessionId,
        code,
        status: markAs, // ✅ present OR excused
      })

      setStatus("success")
      setMessage(
        markAs === "excused"
          ? `Marked as EXCUSED for code ${code}.`
          : `Clock-in successful for code ${code}.`
      )

      setTimeout(() => {
        router.push(`/sessions/${sessionId}/check-in`)
      }, 900)
    } catch (err: any) {
      if (err?.message === "Already marked") {
        setStatus("warning")
        setMessage("Already marked for this session.")
      } else if (err?.message === "Member not found") {
        setStatus("error")
        setMessage("Code not found.")
      } else {
        setStatus("error")
        setMessage("Something went wrong.")
      }
    } finally {
      setIsLoading(false)
    }
  }

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

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="rounded-3xl bg-white p-5 shadow-sm">
        <div className="text-xs text-slate-500">Enter offline code</div>
        <div className="mt-1 text-lg font-semibold text-slate-900">
          {session.name}
        </div>
        <div className="text-sm text-slate-500">{session.date}</div>

        <div className="mt-4">
          <Link
            href={`/sessions/${sessionId}/check-in`}
            className="inline-block rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-medium text-slate-900 hover:bg-slate-50"
          >
            Back
          </Link>
        </div>
      </div>

      {/* Input card */}
      <div className="rounded-2xl bg-white p-5 shadow-sm space-y-4">
        <div>
          <div className="text-sm font-semibold text-slate-900">
            Member offline code
          </div>
          <div className="text-xs text-slate-500">
            Enter the 6-digit numeric code.
          </div>
        </div>

        {/* ✅ Present / Excused toggle */}
        <div className="rounded-2xl border border-slate-200 bg-slate-50 p-2">
          <div className="grid grid-cols-2 gap-2">
            <button
              type="button"
              onClick={() => setMarkAs("present")}
              className={`rounded-xl px-3 py-2 text-sm font-semibold ${
                markAs === "present"
                  ? "bg-slate-900 text-white"
                  : "bg-white text-slate-900 border border-slate-200 hover:bg-slate-50"
              }`}
            >
              Present
            </button>

            <button
              type="button"
              onClick={() => setMarkAs("excused")}
              className={`rounded-xl px-3 py-2 text-sm font-semibold ${
                markAs === "excused"
                  ? "bg-amber-600 text-white"
                  : "bg-white text-slate-900 border border-slate-200 hover:bg-slate-50"
              }`}
            >
              Excused
            </button>
          </div>

          <div className="mt-2 text-[11px] text-slate-600">
            Choose <b>Excused</b> only for members with valid reason.
          </div>
        </div>

        <input
          inputMode="numeric"
          value={code}
          onChange={(e) => handleChange(e.target.value)}
          placeholder="e.g. 123456"
          className="w-full rounded-2xl border border-slate-200 px-4 py-4 text-center text-xl tracking-[0.3em] outline-none focus:border-slate-400"
        />

        <button
          type="button"
          onClick={submit}
          className="w-full rounded-2xl bg-slate-900 px-4 py-4 text-sm font-semibold text-white hover:bg-slate-800 disabled:opacity-50"
          disabled={code.length !== 6 || isLoading}
        >
          {isLoading
            ? "Processing..."
            : markAs === "excused"
            ? "Confirm excused"
            : "Confirm clock-in"}
        </button>

        {status !== "idle" && (
          <div
            className={`rounded-xl px-3 py-2 text-sm ${
              status === "success"
                ? "bg-green-50 text-green-700"
                : status === "warning"
                ? "bg-amber-50 text-amber-700"
                : "bg-rose-50 text-rose-700"
            }`}
          >
            {message}
          </div>
        )}

        <p className="text-[11px] text-slate-500">
          A member can only be marked once per session. Marking as <b>Excused</b>{" "}
          still counts as “marked”, not “present”.
        </p>
      </div>
    </div>
  )
}