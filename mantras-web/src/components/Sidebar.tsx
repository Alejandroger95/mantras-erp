'use client'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useAuth } from '@/lib/auth'
import {
  LayoutDashboard, Users, Calendar, Clock, Umbrella,
  Scissors, ShoppingBag, BarChart2, LogOut, ChevronRight,
} from 'lucide-react'

const nav = [
  {
    section: 'Principal',
    items: [
      { label: 'Dashboard',    href: '/dashboard',              icon: LayoutDashboard },
    ],
  },
  {
    section: 'Recursos Humanos',
    items: [
      { label: 'Empleados',    href: '/rrhh/empleados',         icon: Users },
      { label: 'Cuadrantes',   href: '/rrhh/cuadrantes',        icon: Calendar },
      { label: 'Fichajes',     href: '/rrhh/fichajes',          icon: Clock },
      { label: 'Vacaciones',   href: '/rrhh/vacaciones',        icon: Umbrella },
    ],
  },
  {
    section: 'Servicios',
    items: [
      { label: 'Agenda',       href: '/agenda',                 icon: Scissors },
      { label: 'Catálogo',     href: '/catalogo',               icon: ShoppingBag },
    ],
  },
  {
    section: 'Reportes',
    items: [
      { label: 'Estadísticas', href: '/reportes',               icon: BarChart2 },
    ],
  },
]

export function Sidebar() {
  const pathname = usePathname()
  const { user, logout } = useAuth()

  return (
    <aside className="w-60 flex-shrink-0 bg-slate-900 text-slate-100 flex flex-col h-screen sticky top-0">
      {/* Logo */}
      <div className="px-5 py-5 border-b border-slate-800">
        <div className="flex items-center gap-2">
          <span className="text-xl">🐶</span>
          <span className="font-semibold text-white">Mantras ERP</span>
        </div>
        {user && (
          <p className="text-xs text-slate-400 mt-1 truncate">{user.email}</p>
        )}
      </div>

      {/* Navigation */}
      <nav className="flex-1 overflow-y-auto px-3 py-4 space-y-6">
        {nav.map((group) => (
          <div key={group.section}>
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider px-2 mb-2">
              {group.section}
            </p>
            <ul className="space-y-0.5">
              {group.items.map(({ label, href, icon: Icon }) => {
                const active = pathname === href || pathname.startsWith(href + '/')
                return (
                  <li key={href}>
                    <Link
                      href={href}
                      className={`flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition ${
                        active
                          ? 'bg-slate-700 text-white'
                          : 'text-slate-400 hover:bg-slate-800 hover:text-white'
                      }`}
                    >
                      <Icon size={16} />
                      <span className="flex-1">{label}</span>
                      {active && <ChevronRight size={14} className="text-slate-500" />}
                    </Link>
                  </li>
                )
              })}
            </ul>
          </div>
        ))}
      </nav>

      {/* Logout */}
      <div className="px-3 py-4 border-t border-slate-800">
        <button
          onClick={logout}
          className="flex items-center gap-3 w-full px-3 py-2 rounded-lg text-sm text-slate-400 hover:bg-slate-800 hover:text-white transition"
        >
          <LogOut size={16} />
          Cerrar sesión
        </button>
      </div>
    </aside>
  )
}
