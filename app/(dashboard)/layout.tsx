// app/(dashboard)/layout.tsx

import MobileBottomNav from "@/components/layout/MobileBottomNav"

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <div className="min-h-screen bg-slate-50">
      <main className="mx-auto max-w-md px-4 pb-24 pt-5">{children}</main>
      <MobileBottomNav />
    </div>
  )
}