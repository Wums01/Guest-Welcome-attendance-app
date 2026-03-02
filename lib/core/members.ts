// lib/core/members.ts

import type { Member } from "@/lib/types"
import { makeId } from "./id"
import { readStore, writeStore } from "./storage"

const KEY = "members" as const

export function getMembers(): Member[] {
  return readStore<Member[]>(KEY, [])
}

export function getMemberById(id: string): Member | null {
  return getMembers().find((m) => m.id === id) ?? null
}

export function getMemberByOfflineCode(code: string): Member | null {
  return getMembers().find((m) => m.offlineCode === code) ?? null
}

function generate6DigitCode(existing: Set<string>) {
  // Simulate backend generation for now
  for (let i = 0; i < 30; i++) {
    const code = String(Math.floor(100000 + Math.random() * 900000))
    if (!existing.has(code)) return code
  }
  throw new Error("Could not generate unique offline code. Try again.")
}

// ✅ Offline code removed from input (backend will generate)
export function createMember(input: Omit<Member, "id" | "offlineCode" | "createdAt" | "updatedAt">): Member {
  const now = new Date().toISOString()
  const all = getMembers()

  const existingCodes = new Set(all.map((m) => m.offlineCode))
  const offlineCode = generate6DigitCode(existingCodes)

  const created: Member = {
    id: makeId(),
    ...input,
    offlineCode,
    createdAt: now,
    updatedAt: now,
  }

  all.unshift(created)
  writeStore(KEY, all)
  return created
}

export function deleteMember(id: string) {
  const kept = getMembers().filter((m) => m.id !== id)
  writeStore(KEY, kept)
}