"use client"

import Link from "next/link"
import { useParams } from "next/navigation"
import { getSessions } from "@/lib/core/sessions"

export default function SessionDetailsPage() {
  const params = useParams<{ id: string }>()
  const session = getSessions().find(s => s.id === params.id)

  if (!session) {
    return <div className="p-6">Session not found.</div>
  }

  return (
    <div className="space-y-4">
      <div className="rounded-2xl bg-white p-6 shadow-sm">
        <h1 className="text-xl font-semibold">{session.name}</h1>
        <p className="text-sm text-slate-600">{session.date}</p>

        <div className="mt-4 space-y-2">
          <Link
            href={`/sessions/${session.id}/check-in`}
            className="block rounded-xl bg-slate-900 px-4 py-3 text-white text-center"
          >
            Go to Check-in
          </Link>

          <Link
            href={`/sessions/${session.id}/code`}
            className="block rounded-xl border px-4 py-3 text-center"
          >
            Offline Code
          </Link>
        </div>
      </div>
    </div>
  )
}