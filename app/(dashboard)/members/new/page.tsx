// app/(dashboard)/members/new/page.tsx

"use client"

import Link from "next/link"
import { useMemo, useState } from "react"
import { useForm } from "react-hook-form"
import { z } from "zod"
import { zodResolver } from "@hookform/resolvers/zod"

import type { Team } from "@/lib/types"
import { createMember } from "@/lib/core/members"

const teams = ["Team A", "Team B", "Team C", "None"] as const
const maritalStatuses = ["Single", "Married"] as const

function onlyDigits(s: string) {
  return s.replace(/\D/g, "")
}

function isValidMMDD(v: string) {
  if (!/^\d{2}-\d{2}$/.test(v)) return false
  const [mm, dd] = v.split("-").map(Number)
  if (mm < 1 || mm > 12) return false
  if (dd < 1 || dd > 31) return false
  return true
}

const memberSchema = z
  .object({
    fullName: z.string().min(2, "Full name is required"),
    team: z.enum(teams, { message: "Select a team" }),
    phone: z
      .string()
      .min(7, "Phone number is required")
      .transform((v) => onlyDigits(v))
      .refine((v) => v.length >= 8, "Enter a valid phone number"),
    birthdayMD: z
      .string()
      .min(1, "Birthday is required")
      .refine((v) => isValidMMDD(v), "Use MM-DD (e.g. 02-10)"),
    maritalStatus: z.enum(maritalStatuses, { message: "Select marital status" }),
    anniversaryMD: z.string().optional(),
  })
  .superRefine((data, ctx) => {
    if (data.maritalStatus === "Married") {
      const ann = (data.anniversaryMD ?? "").trim()
      if (!ann) {
        ctx.addIssue({
          code: "custom",
          path: ["anniversaryMD"],
          message: "Anniversary date is required for married members",
        })
        return
      }
      if (!isValidMMDD(ann)) {
        ctx.addIssue({
          code: "custom",
          path: ["anniversaryMD"],
          message: "Use MM-DD (e.g. 08-10)",
        })
      }
    }
  })

type MemberFormValues = z.infer<typeof memberSchema>
type TeamOption = Team

function FieldLabel({
  label,
  required,
  htmlFor,
}: {
  label: string
  required?: boolean
  htmlFor: string
}) {
  return (
    <label htmlFor={htmlFor} className="text-sm font-medium text-slate-900">
      {label} {required ? <span className="text-rose-600">*</span> : null}
    </label>
  )
}

function FieldError({ message }: { message?: string }) {
  if (!message) return null
  return <p className="mt-1 text-xs text-rose-600">{message}</p>
}

export default function NewMemberPage() {
  const [status, setStatus] = useState<"idle" | "success" | "error">("idle")
  const [message, setMessage] = useState("")
  const [generatedOfflineCode, setGeneratedOfflineCode] = useState<string | null>(null)

  const {
    register,
    handleSubmit,
    watch,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<MemberFormValues>({
    resolver: zodResolver(memberSchema),
    defaultValues: {
      fullName: "",
      team: "Team A",
      phone: "",
      birthdayMD: "",
      maritalStatus: "Single",
      anniversaryMD: "",
    },
    mode: "onTouched",
  })

  const maritalStatus = watch("maritalStatus")
  const showAnniversary = useMemo(() => maritalStatus === "Married", [maritalStatus])

  const onSubmit = async (data: MemberFormValues) => {
    setStatus("idle")
    setMessage("")
    setGeneratedOfflineCode(null)

    try {
      const created = createMember({
        fullName: data.fullName.trim(),
        team: data.team as TeamOption,
        phone: data.phone, // already digits-only due to transform()
        isMarried: data.maritalStatus === "Married",
        birthdayMD: data.birthdayMD.trim(),
        anniversaryMD:
          data.maritalStatus === "Married" ? (data.anniversaryMD?.trim() || null) : null,
      })

      setStatus("success")
      setMessage("Member registered successfully ✅")
      setGeneratedOfflineCode(created.offlineCode)

      reset({
        fullName: "",
        team: data.team,
        phone: "",
        birthdayMD: "",
        maritalStatus: "Single",
        anniversaryMD: "",
      })
    } catch (err: any) {
      setStatus("error")
      setMessage(err?.message ?? "Could not register member.")
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900">Register Member</h1>
          <p className="text-sm text-slate-700">
            Phone and Birthday are required. Anniversary is required only if married.
          </p>
        </div>

        <Link
          href="/members"
          className="shrink-0 rounded-xl border border-slate-300 bg-white px-3 py-2 text-xs font-semibold text-slate-900 hover:bg-slate-50"
        >
          View members
        </Link>
      </div>

      <form onSubmit={handleSubmit(onSubmit)} className="rounded-2xl border bg-white p-4 sm:p-6">
        <div className="grid gap-4">
          <div>
            <FieldLabel htmlFor="fullName" label="Full name" required />
            <input
              id="fullName"
              placeholder="e.g. Obebe Elizabeth"
              className="mt-2 w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 placeholder:text-slate-400 outline-none focus:border-slate-500"
              {...register("fullName")}
            />
            <FieldError message={errors.fullName?.message} />
          </div>

          <div>
            <FieldLabel htmlFor="team" label="Team" required />
            <select
              id="team"
              className="mt-2 w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 outline-none focus:border-slate-500"
              {...register("team")}
            >
              {teams.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </select>
            <FieldError message={errors.team?.message} />
          </div>

          <div>
            <FieldLabel htmlFor="phone" label="Phone number" required />
            <input
              id="phone"
              inputMode="tel"
              placeholder="e.g. 08012345678"
              className="mt-2 w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 placeholder:text-slate-400 outline-none focus:border-slate-500"
              {...register("phone")}
            />
            <FieldError message={errors.phone?.message} />
          </div>

          <div>
            <FieldLabel htmlFor="birthdayMD" label="Birthday (MM-DD)" required />
            <input
              id="birthdayMD"
              placeholder="MM-DD (e.g. 02-10)"
              className="mt-2 w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 placeholder:text-slate-400 outline-none focus:border-slate-500"
              {...register("birthdayMD")}
            />
            <FieldError message={errors.birthdayMD?.message} />
            <p className="mt-1 text-xs text-slate-700">Month and day only (year not required)</p>
          </div>

          <div>
            <FieldLabel htmlFor="maritalStatus" label="Marital status" required />
            <select
              id="maritalStatus"
              className="mt-2 w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 outline-none focus:border-slate-500"
              {...register("maritalStatus")}
            >
              {maritalStatuses.map((m) => (
                <option key={m} value={m}>
                  {m}
                </option>
              ))}
            </select>
            <FieldError message={errors.maritalStatus?.message} />
          </div>

          <div className={showAnniversary ? "" : "opacity-50"}>
            <FieldLabel
              htmlFor="anniversaryMD"
              label="Anniversary (MM-DD)"
              required={showAnniversary}
            />
            <input
              id="anniversaryMD"
              placeholder={showAnniversary ? "MM-DD (e.g. 08-10)" : "Only required if married"}
              disabled={!showAnniversary}
              className="mt-2 w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 placeholder:text-slate-400 outline-none focus:border-slate-500 disabled:cursor-not-allowed disabled:bg-slate-100"
              {...register("anniversaryMD")}
            />
            <FieldError message={errors.anniversaryMD?.message} />
          </div>

          <div className="flex items-center gap-3 pt-2">
            <button
              type="submit"
              disabled={isSubmitting}
              className="inline-flex items-center justify-center rounded-xl bg-slate-900 px-4 py-2 text-sm font-semibold text-white hover:bg-slate-800 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isSubmitting ? "Saving..." : "Register member"}
            </button>

            <button
              type="button"
              onClick={() => {
                setStatus("idle")
                setMessage("")
                setGeneratedOfflineCode(null)
                reset()
              }}
              className="rounded-xl border border-slate-300 bg-white px-4 py-2 text-sm font-semibold text-slate-900 hover:bg-slate-50"
            >
              Reset
            </button>
          </div>

          {status !== "idle" ? (
            <div
              className={`rounded-xl border px-3 py-2 text-sm ${
                status === "success"
                  ? "border-emerald-200 bg-emerald-50 text-emerald-900"
                  : "border-rose-200 bg-rose-50 text-rose-900"
              }`}
            >
              <div>{message}</div>
              {status === "success" && generatedOfflineCode ? (
                <div className="mt-2 text-xs">
                  Offline Code:{" "}
                  <span className="font-bold tracking-wider">{generatedOfflineCode}</span>
                </div>
              ) : null}
            </div>
          ) : null}
        </div>
      </form>
    </div>
  )
}