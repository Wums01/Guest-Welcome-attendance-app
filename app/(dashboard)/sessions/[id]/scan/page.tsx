"use client"

import Link from "next/link"
import { useParams } from "next/navigation"

export default function ScanPage() {
  const params = useParams<{ id: string }>()
  const sessionId = params.id

  return (
    <div className="space-y-4">
      <div className="rounded-3xl bg-white p-5 shadow-sm">
        <div className="text-xs text-slate-500">Scan code</div>
        <div className="mt-1 text-lg font-semibold text-slate-900">
          Camera scanner
        </div>
        <div className="text-sm text-slate-500">
          This will be connected to backend later.
        </div>

        <div className="mt-4">
          <Link
            href={`/sessions/${sessionId}/check-in`}
            className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-medium text-slate-900 hover:bg-slate-50 inline-block"
          >
            Back
          </Link>
        </div>
      </div>

      <div className="rounded-2xl bg-white p-5 shadow-sm">
        <div className="rounded-2xl border border-dashed border-slate-300 bg-slate-50 p-10 text-center text-sm text-slate-500">
          Scanner UI will live here (QR/Barcode).
        </div>
      </div>
    </div>
  )
}