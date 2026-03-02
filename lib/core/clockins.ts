// lib/core/clockins.ts

import type { ClockIn, AttendanceStatus, Member, Program, Session, Team } from "@/lib/types"
import { readStore, writeStore } from "@/lib/core/storage"
import type { StoreKey } from "@/lib/core/storage"
import { makeId } from "@/lib/core/id"
import { getMemberByOfflineCode, getMembers } from "@/lib/core/members"
import { getSessions } from "@/lib/core/sessions"
import { getPrograms } from "@/lib/core/programs"

const KEY: StoreKey = "clockins"
type ClockInMethod = ClockIn["method"]

export function getClockIns(): ClockIn[] {
  return readStore<ClockIn[]>(KEY, [])
}

export function getClockInsBySession(sessionId: string): ClockIn[] {
  return getClockIns().filter((c) => c.sessionId === sessionId)
}

export function getClockInCountBySession(sessionId: string): number {
  return getClockInsBySession(sessionId).length
}

export function clearSessionClockIns(sessionId: string) {
  const all = getClockIns()
  const filtered = all.filter((c) => c.sessionId !== sessionId)
  writeStore(KEY, filtered)
}

// ==================
// HELPERS
// ==================

function getSessionById(sessionId: string): Session | null {
  return getSessions().find((s) => s.id === sessionId) ?? null
}

function getProgramForSession(sessionId: string): Program | null {
  const session = getSessionById(sessionId)
  if (!session) return null
  return getPrograms().find((p) => p.id === session.programId) ?? null
}

// Service 1 -> Team A, Service 2 -> Team B, Service 3 -> Team C
function inferSundayServiceTeam(sessionName: string): Team | null {
  const name = sessionName.toLowerCase()
  if (name.includes("service 1") || name.includes("first")) return "Team A"
  if (name.includes("service 2") || name.includes("second")) return "Team B"
  if (name.includes("service 3") || name.includes("third")) return "Team C"
  return null
}

function isSundaySession(session: Session, program: Program | null): boolean {
  if (program?.programType === "sunday") return true
  return inferSundayServiceTeam(session.name) !== null
}

function writeAll(next: ClockIn[]) {
  writeStore(KEY, next)
}

function findExisting(all: ClockIn[], sessionId: string, memberId: string) {
  return all.find((c) => c.sessionId === sessionId && c.memberId === memberId) ?? null
}

// ==================
// CORE WRITE (no duplicates)
// ==================

export function clockInMember(input: {
  sessionId: string
  memberId: string
  status?: AttendanceStatus
  method?: ClockInMethod
}): ClockIn {
  const all = getClockIns()
  const status: AttendanceStatus = input.status ?? "present"
  const method: ClockInMethod = input.method ?? "offline_code"

  const existing = findExisting(all, input.sessionId, input.memberId)

  if (existing && (existing.status === "present" || existing.status === "excused")) {
    throw new Error("Already marked")
  }

  if (existing && existing.status === "absent" && (status === "present" || status === "excused")) {
    const updated: ClockIn = {
      ...existing,
      status,
      method,
      clockedAt: new Date().toISOString(),
    }
    const next = all.map((c) => (c.id === existing.id ? updated : c))
    writeAll(next)
    return updated
  }

  const created: ClockIn = {
    id: makeId(),
    sessionId: input.sessionId,
    memberId: input.memberId,
    status,
    method,
    clockedAt: new Date().toISOString(),
  }

  all.unshift(created)
  writeAll(all)
  return created
}

export function clockInByOfflineCode(input: {
  sessionId: string
  code: string
  status?: AttendanceStatus // present | excused
}): ClockIn {
  const member = getMemberByOfflineCode(input.code)

  if (!member) {
    throw new Error("Member not found")
  }

  const status: AttendanceStatus = input.status ?? "present"

  if (status === "absent") {
    throw new Error("Invalid status")
  }

  return clockInMember({
    sessionId: input.sessionId,
    memberId: member.id,
    status,
    method: "offline_code",
  })
}

// ==================
// FINALIZE ABSENCES
// ==================

export function finalizeSessionAbsences(sessionId: string) {
  const session = getSessionById(sessionId)
  if (!session) return

  const program = getProgramForSession(sessionId)
  const allMembers = getMembers()
  const allClockins = getClockIns()

  const sessionClockins = allClockins.filter((c) => c.sessionId === sessionId)

  const markedMemberIds = new Set(
    sessionClockins
      .filter((c) => c.status === "present" || c.status === "excused")
      .map((c) => c.memberId)
  )

  const sunday = isSundaySession(session, program)
  const expectedTeam = sunday ? inferSundayServiceTeam(session.name) : null

  const expectedMembers: Member[] = sunday
    ? allMembers.filter((m) => expectedTeam && m.team === expectedTeam)
    : allMembers

  const toAdd: ClockIn[] = []

  for (const m of expectedMembers) {
    if (markedMemberIds.has(m.id)) continue
    const existing = sessionClockins.find((c) => c.memberId === m.id)
    if (existing) continue

    toAdd.push({
      id: makeId(),
      sessionId,
      memberId: m.id,
      status: "absent",
      method: "manual",
      clockedAt: new Date().toISOString(),
    })
  }

  if (toAdd.length === 0) return
  writeAll([...toAdd, ...allClockins])
}