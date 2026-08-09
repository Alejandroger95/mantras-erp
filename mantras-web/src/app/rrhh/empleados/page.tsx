'use client'
import { useQuery } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import { api } from '@/lib/api'
import { useAuth } from '@/lib/auth'
import { Users, Plus, Search } from 'lucide-react'
import { useState } from 'react'
import Link from 'next/link'

interface Employee {
  id: number
  fullName: string
  positionName: string | null
  departmentName: string | null
  corporateEmail: string | null
  personalPhone: string | null
  hireDate: string
  status: string
  photoUrl: string | null
}

const statusLabel: Record<string, { label: string; color: string }> = {
  active:     { label: 'Activo',    color: 'bg-green-100 text-green-700' },
  on_leave:   { label: 'De baja',   color: 'bg-amber-100 text-amber-700' },
  suspended:  { label: 'Suspendido',color: 'bg-red-100 text-red-700' },
  terminated: { label: 'Baja',      color: 'bg-slate-100 text-slate-500' },
}

export default function EmpleadosPage() {
  const { user } = useAuth()
  const router = useRouter()
  const [search, setSearch] = useState('')

  const { data: employees = [], isLoading } = useQuery<Employee[]>({
    queryKey: ['employees'],
    queryFn: () => api.get('/api/v1/hr/employees').then(r => r.data),
  })

  const filtered = employees.filter(e =>
    e.fullName.toLowerCase().includes(search.toLowerCase()) ||
    e.positionName?.toLowerCase().includes(search.toLowerCase()) ||
    e.departmentName?.toLowerCase().includes(search.toLowerCase())
  )

  return (
    <div className="p-8">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
            <Users size={24} /> Empleados
          </h1>
          <p className="text-slate-500 mt-1">{employees.length} empleados activos</p>
        </div>
        <button className="flex items-center gap-2 bg-slate-900 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-slate-700 transition">
          <Plus size={16} /> Nuevo empleado
        </button>
      </div>

      {/* Search */}
      <div className="relative mb-6">
        <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
        <input
          type="text"
          placeholder="Buscar por nombre, cargo o departamento..."
          value={search}
          onChange={e => setSearch(e.target.value)}
          className="w-full pl-9 pr-4 py-2 border border-slate-200 rounded-lg text-sm bg-white focus:outline-none focus:ring-2 focus:ring-slate-900"
        />
      </div>

      {/* Table */}
      <div className="bg-white rounded-xl border border-slate-200 overflow-hidden">
        {isLoading ? (
          <div className="p-8 text-center text-slate-500">Cargando empleados...</div>
        ) : filtered.length === 0 ? (
          <div className="p-8 text-center text-slate-500">
            {search ? 'No se encontraron resultados' : 'No hay empleados registrados aún'}
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead className="border-b border-slate-200 bg-slate-50">
              <tr>
                <th className="text-left px-4 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wider">Empleado</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wider">Cargo</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wider">Departamento</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wider">Teléfono</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wider">Desde</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wider">Estado</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {filtered.map((emp) => {
                const st = statusLabel[emp.status] ?? { label: emp.status, color: 'bg-slate-100 text-slate-500' }
                const initials = emp.fullName.split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase()
                return (
                  <tr
                    key={emp.id}
                    className="hover:bg-slate-50 cursor-pointer transition"
                    onClick={() => router.push(`/rrhh/empleados/${emp.id}`)}
                  >
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-3">
                        {emp.photoUrl ? (
                          <img src={emp.photoUrl} alt={emp.fullName} className="w-8 h-8 rounded-full object-cover" />
                        ) : (
                          <div className="w-8 h-8 rounded-full bg-slate-200 flex items-center justify-center text-xs font-semibold text-slate-600">
                            {initials}
                          </div>
                        )}
                        <div>
                          <p className="font-medium text-slate-900">{emp.fullName}</p>
                          <p className="text-xs text-slate-400">{emp.corporateEmail ?? emp.personalPhone ?? '—'}</p>
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-slate-700">{emp.positionName ?? '—'}</td>
                    <td className="px-4 py-3 text-slate-700">{emp.departmentName ?? '—'}</td>
                    <td className="px-4 py-3 text-slate-500">{emp.personalPhone ?? '—'}</td>
                    <td className="px-4 py-3 text-slate-500">
                      {new Date(emp.hireDate).toLocaleDateString('es-PE')}
                    </td>
                    <td className="px-4 py-3">
                      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${st.color}`}>
                        {st.label}
                      </span>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}
