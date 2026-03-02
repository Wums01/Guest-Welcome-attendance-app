"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"

const items = [
  { href: "/home", label: "Home" },
  { href: "/sessions", label: "Sessions" },
  { href: "/programs", label: "Programs" },
  { href: "/members", label: "Members" },
  { href: "/reports", label: "Reports" },
]

export default function MobileBottomNav() {
  const pathname = usePathname()

  return (
    <nav className="fixed bottom-0 left-0 right-0 z-50 border-t bg-white">
      <div className="mx-auto grid h-16 max-w-md grid-cols-5">
        {items.map((item) => {
          const active =
            pathname === item.href || pathname.startsWith(item.href + "/")

          return (
            <Link
              key={item.href}
              href={item.href}
              className={`flex flex-col items-center justify-center text-[12px] transition ${
                active
                  ? "text-slate-900 font-semibold"
                  : "text-slate-500 hover:text-slate-900"
              }`}
            >
              <span
                className={`h-1 w-8 rounded-full transition ${
                  active ? "bg-slate-900" : "bg-transparent"
                }`}
              />
              <span className="mt-2">{item.label}</span>
            </Link>
          )
        })}
      </div>
    </nav>
  )
}