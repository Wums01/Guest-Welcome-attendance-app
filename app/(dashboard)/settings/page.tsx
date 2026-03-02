"use client"

import { useEffect, useState } from "react"
import { isTestMode, setTestMode } from "@/lib/core/settings"

export default function SettingsPage() {
  const [testMode, setTestModeState] = useState(false)

  useEffect(() => {
    setTestModeState(isTestMode())
  }, [])

  function toggle() {
    const next = !testMode
    setTestModeState(next)
    setTestMode(next)
  }

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold text-slate-900">Settings</h1>
        <p className="text-sm text-slate-600">App preferences</p>
      </div>

      <div className="rounded-2xl bg-white p-4 shadow-sm">
        <div className="flex items-center justify-between gap-3">
          <div>
            <div className="text-sm font-semibold text-slate-900">Test mode</div>
            <div className="text-xs text-slate-500">
              Allow check-in at any time (for testing).
            </div>
          </div>

          <button
            onClick={toggle}
            className={`rounded-xl px-4 py-2 text-sm font-semibold text-white ${
              testMode ? "bg-emerald-600" : "bg-slate-900"
            }`}
          >
            {testMode ? "ON" : "OFF"}
          </button>
        </div>
      </div>
    </div>
  )
}