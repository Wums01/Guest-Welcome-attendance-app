// lib/types.ts

export type Team = "Team A" | "Team B" | "Team C" | "None"

export type ProgramType = "sunday" | "wednesday" | "program" | "meeting" | "training"

export type Program = {
  id: string
  title: string
  programType: ProgramType

  // ✅ Dates can be null when TBD
  startDate: string | null // YYYY-MM-DD | null
  endDate: string | null // YYYY-MM-DD | null
  isTBD: boolean

  teamScope: "all" | Team | null
  createdAt: string
  updatedAt: string
}

export type Session = {
  id: string
  programId: string
  name: string
  date: string // YYYY-MM-DD
  startTime?: string | null // HH:mm
  endTime?: string | null // HH:mm
  clockInRequired: boolean
  createdAt: string
  updatedAt: string
}

export type AttendanceStatus = "present" | "absent" | "excused"

export type ClockIn = {
  id: string
  sessionId: string
  memberId: string
  status: AttendanceStatus
  clockedAt: string // ISO timestamp
  method: "manual" | "qr" | "self" | "offline_code"
}

export type Member = {
  id: string
  fullName: string
  phone: string
  offlineCode: string
  team: Team
  isMarried?: boolean
  birthdayMD: string // "MM-DD"
  anniversaryMD?: string | null
  createdAt: string
  updatedAt: string
}