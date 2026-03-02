// lib/core/sessions.ts

import type { Session } from "@/lib/types"
import { makeId } from "./id"
import { readStore, writeStore } from "./storage"

const KEY = "sessions" as const

export function getSessions(): Session[] {
  return readStore<Session[]>(KEY, [])
}

export function getSessionById(id: string): Session | null {
  return getSessions().find((s) => s.id === id) ?? null
}

export function getSessionsByDate(date: string): Session[] {
  return getSessions().filter((s) => s.date === date)
}

export function getSessionsByProgram(programId: string): Session[] {
  return getSessions().filter((s) => s.programId === programId)
}

/**
 * yearMonth format: "YYYY-MM" e.g. "2026-12"
 */
export function getSessionsByMonth(yearMonth: string): Session[] {
  return getSessions().filter((s) => s.date.slice(0, 7) === yearMonth)
}

export function createSession(input: {
  programId: string
  name: string
  date: string // YYYY-MM-DD
  startTime?: string | null
  endTime?: string | null
  clockInRequired?: boolean
}): Session {
  const now = new Date().toISOString()

  const session: Session = {
    id: makeId(),
    programId: input.programId,
    name: input.name.trim(),
    date: input.date,
    startTime: input.startTime ?? null,
    endTime: input.endTime ?? null,
    clockInRequired: input.clockInRequired ?? true,
    createdAt: now,
    updatedAt: now,
  }

  const all = getSessions()
  all.unshift(session)
  writeStore(KEY, all)

  return session
}

// ✅ Sunday helper: Service 1 / Service 2 / Service 3 (for a specific date)
export function createSundaySessions(programId: string, date: string) {
  const names = ["Service 1", "Service 2", "Service 3"]
  return names.map((name) => createSession({ programId, name, date }))
}

// ✅ Wednesday helper: Switch Service (for a specific date)
export function createWednesdaySessions(programId: string, date: string) {
  return [createSession({ programId, name: "Switch Service", date })]
}

export function updateSession(sessionId: string, patch: Partial<Omit<Session, "id">>) {
  const all = getSessions()
  const idx = all.findIndex((s) => s.id === sessionId)
  if (idx === -1) return

  all[idx] = {
    ...all[idx],
    ...patch,
    updatedAt: new Date().toISOString(),
  }

  writeStore(KEY, all)
}

export function deleteSession(sessionId: string) {
  const kept = getSessions().filter((s) => s.id !== sessionId)
  writeStore(KEY, kept)
}

// ✅ Used by deleteProgram() so sessions don’t remain “hanging”
export function deleteSessionsByProgram(programId: string) {
  const kept = getSessions().filter((s) => s.programId !== programId)
  writeStore(KEY, kept)
}