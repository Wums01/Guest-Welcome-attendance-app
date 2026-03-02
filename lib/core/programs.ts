// lib/core/programs.ts

import type { Program, ProgramType, Team } from "@/lib/types"
import { makeId } from "./id"
import { readStore, writeStore } from "./storage"
import { deleteSessionsByProgram } from "./sessions"

const KEY = "programs" as const

export function getPrograms(): Program[] {
  return readStore<Program[]>(KEY, [])
}

export function getProgramById(id: string): Program | null {
  return getPrograms().find((p) => p.id === id) ?? null
}

type CreateProgramInput =
  | {
      title: string
      programType: ProgramType
      teamScope: "all" | Team | null
      isTBD: true
      startDate?: null
      endDate?: null
    }
  | {
      title: string
      programType: ProgramType
      teamScope: "all" | Team | null
      isTBD: false
      startDate: string // YYYY-MM-DD
      endDate: string // YYYY-MM-DD
    }

export function createProgram(input: CreateProgramInput): Program {
  const now = new Date().toISOString()

  // Validate dates when not TBD
  if (!input.isTBD) {
    if (!input.startDate || !input.endDate) {
      throw new Error("Start date and end date are required when program is not TBD.")
    }
    if (input.endDate < input.startDate) {
      throw new Error("End date cannot be earlier than start date.")
    }
  }

  const program: Program = {
    id: makeId(),
    title: input.title.trim(),
    programType: input.programType,
    isTBD: input.isTBD,
    startDate: input.isTBD ? null : input.startDate,
    endDate: input.isTBD ? null : input.endDate,
    teamScope: input.teamScope,
    createdAt: now,
    updatedAt: now,
  }

  const all = getPrograms()
  all.unshift(program)
  writeStore(KEY, all)

  return program
}

export function updateProgram(programId: string, patch: Partial<Omit<Program, "id">>) {
  const all = getPrograms()
  const idx = all.findIndex((p) => p.id === programId)
  if (idx === -1) return

  const prev = all[idx]
  const next: Program = {
    ...prev,
    ...patch,
    updatedAt: new Date().toISOString(),
  }

  // Keep data consistent
  if (next.isTBD) {
    next.startDate = null
    next.endDate = null
  } else {
    // if not TBD, ensure dates exist
    if (!next.startDate || !next.endDate) {
      throw new Error("Start date and end date are required when program is not TBD.")
    }
    if (next.endDate < next.startDate) {
      throw new Error("End date cannot be earlier than start date.")
    }
  }

  all[idx] = next
  writeStore(KEY, all)
}

// ✅ Deletes program and ALSO removes its sessions (avoids “orphan sessions”)
export function deleteProgram(programId: string) {
  // delete related sessions first
  deleteSessionsByProgram(programId)

  // delete the program
  const kept = getPrograms().filter((p) => p.id !== programId)
  writeStore(KEY, kept)
}