// app/(dashboard)/members/page.tsx
// ✅ list-only page (search + expand/collapse + link to /members/new)

"use client"

import Link from "next/link"
import { useEffect, useMemo, useState } from "react"
import type { Member } from "@/lib/types"
import { deleteMember, getMembers } from "@/lib/core/members"

const PREVIEW_COUNT = 12

export default function MembersPage() {
  const [members, setMembers] = useState<Member[]>([])
  const [query, setQuery] = useState("")
  const [showAllMembers, setShowAllMembers] = useState(false)

  function refresh() {
    setMembers(getMembers())
  }

  useEffect(() => {
    refresh()
  }, [])

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return members
    return members.filter((m) => {
      const name = (m.fullName ?? "").toLowerCase()
      return (
        name.includes(q) ||
        (m.offlineCode ?? "").includes(q) ||
        (m.phone ?? "").includes(q) ||
        (m.team ?? "").toLowerCase().includes(q)
      )
    })
  }, [members, query])

  const visibleMembers = useMemo(() => {
    if (showAllMembers) return filtered
    return filtered.slice(0, PREVIEW_COUNT)
  }, [filtered, showAllMembers])

  const canToggleMembers = filtered.length > PREVIEW_COUNT

  return (
    <div className="space-y-5">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900">Members</h1>
          <p className="text-sm text-slate-700">
            Search members. Registration is on a separate page.
          </p>
        </div>

        <Link
          href="/members/new"
          className="shrink-0 rounded-xl bg-slate-900 px-3 py-2 text-xs font-semibold text-white hover:bg-slate-800"
        >
          + Add member
        </Link>
      </div>

      <div className="rounded-2xl bg-white shadow-sm">
        <div className="border-b px-4 py-3">
          <div className="flex items-start justify-between gap-3">
            <div>
              <div className="text-sm font-semibold text-slate-900">Registered members</div>
              <div className="text-xs text-slate-700">Search by name, code, phone or team.</div>
            </div>

            {canToggleMembers ? (
              <button
                type="button"
                onClick={() => setShowAllMembers((v) => !v)}
                className="shrink-0 rounded-xl border border-slate-300 bg-white px-3 py-2 text-xs font-semibold text-slate-900 hover:bg-slate-50"
              >
                {showAllMembers ? "Collapse" : "Expand"}
              </button>
            ) : null}
          </div>

          <input
            value={query}
            onChange={(e) => {
              setQuery(e.target.value)
              setShowAllMembers(false)
            }}
            placeholder="Search..."
            className="mt-3 w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 placeholder:text-slate-400 outline-none focus:border-slate-500"
          />

          <div className="mt-2 text-xs text-slate-600">
            Showing <b>{visibleMembers.length}</b> of <b>{filtered.length}</b>
          </div>
        </div>

        {filtered.length === 0 ? (
          <div className="p-6 text-center text-sm text-slate-700">No members found.</div>
        ) : (
          <ul className="divide-y">
            {visibleMembers.map((m) => (
              <li key={m.id} className="p-4">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <div className="font-semibold text-slate-900">{m.fullName}</div>
                    <div className="mt-1 text-xs text-slate-800">
                      {m.team} • Code:{" "}
                      <span className="font-semibold">{m.offlineCode}</span>
                      {m.phone ? ` • ${m.phone}` : ""}
                    </div>

                    <div className="mt-2 flex flex-wrap gap-2">
                      {m.birthdayMD ? (
                        <span className="rounded-full bg-slate-100 px-2.5 py-1 text-[11px] font-semibold text-slate-800">
                          Birthday: {m.birthdayMD}
                        </span>
                      ) : null}

                      {m.isMarried ? (
                        <span className="rounded-full bg-emerald-50 px-2.5 py-1 text-[11px] font-semibold text-emerald-800">
                          Married
                        </span>
                      ) : (
                        <span className="rounded-full bg-slate-100 px-2.5 py-1 text-[11px] font-semibold text-slate-800">
                          Single
                        </span>
                      )}

                      {m.isMarried && m.anniversaryMD ? (
                        <span className="rounded-full bg-emerald-50 px-2.5 py-1 text-[11px] font-semibold text-emerald-800">
                          Anniversary: {m.anniversaryMD}
                        </span>
                      ) : null}
                    </div>
                  </div>

                  <button
                    type="button"
                    onClick={() => {
                      const ok = confirm(`Delete ${m.fullName}?`)
                      if (!ok) return
                      deleteMember(m.id)
                      refresh()
                    }}
                    className="rounded-xl border border-rose-300 bg-white px-3 py-2 text-xs font-semibold text-rose-700 hover:bg-rose-50"
                  >
                    Delete
                  </button>
                </div>
              </li>
            ))}
          </ul>
        )}

        {canToggleMembers ? (
          <div className="border-t p-3">
            <button
              type="button"
              onClick={() => setShowAllMembers((v) => !v)}
              className="w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm font-semibold text-slate-900 hover:bg-slate-50"
            >
              {showAllMembers ? "View less" : `View all (${filtered.length})`}
            </button>
          </div>
        ) : null}
      </div>
    </div>
  )
}