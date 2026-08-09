'use client'
import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api'
import { Umbrella } from 'lucide-react'

interface Absence {
  id: number
  fullName: string
  absenceType: string
  startDate: string
  endDate: string
  status: string
  photoUrl: string | null
  notes: string | null
}

export default function VacacionesPage() {
  const { data: absences = [], isLoading } = useQuery<Absence[]>({
    queryKey: ['absences'],
    queryFn: () => api.get('/api/v1/hr/absences').then(r => r.data),
  })

  const fmt = (d: string) => new Date(d).toLocaleDateString('es-PE', { day: '2-digit', month: 'short' })
  const days = (from: string, to: string) =>
    Math.ceil((new Date(to).getTime() - new Date(from).getTime()) / 86_400_000) + 1

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
          <Umbrella size={24} /> Vacaciones y ausencias
        </h1>
        <p className="text-slate-500 mt-1">{absences.length} ausencias activas</p>
      </div>

      <div className="bg-white rounded-xl border border-slate-200 overflow-hidden">
        {isLoading ? (
          <div className="p-8 text-center text-slate-400">Cargando...</div>
        ) : absences.length === 0 ? (
          <div className="p-8 text-center text-slate-400">No hay ausencias activas</div>
        ) : (
          <table className="w-full text-sm">
            <thead className="border-b border-slate-200 bg-slate-50">
              <tr>
                <th className="text-left px-4 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wider">Empleado</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wider">Tipo</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wider">Desde</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wider">Hasta</th>
                <th className="text-left px-4 py-3 text-xs font-semibold text-slate-500 uppercase tracking-wider">Días</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {absences.map(a => {
                const initials = a.fullName.split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase()
                return (
                  <tr key={a.id} className="hover:bg-slate-50">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-3">
                        {a.photoUrl ? (
                          <img src={a.photoUrl} alt={a.fullName} className="w-7 h-7 rounded-full object-cover" />
                        ) : (
                          <div className="w-7 h-7 rounded-full bg-slate-200 flex items-center justify-center text-xs font-semibold text-slate-600">
                            {initials}
                          </div>
                        )}
                        <span className="font-medium text-slate-900">{a.fullName}</span>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-slate-700">{a.absenceType}</td>
                    <td className="px-4 py-3 text-slate-500">{fmt(a.startDate)}</td>
                    <td className="px-4 py-3 text-slate-500">{fmt(a.endDate)}</td>
                    <td className="px-4 py-3">
                      <span className="bg-blue-50 text-blue-700 px-2 py-0.5 rounded-full text-xs font-medium">
                        {days(a.startDate, a.endDate)}d
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
