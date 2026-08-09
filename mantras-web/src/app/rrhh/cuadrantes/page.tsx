'use client'
import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api'
import { Calendar } from 'lucide-react'

interface Shift {
  dayOfWeek: number   // 1=Mon … 7=Sun
  startTime: string
  endTime: string
  isRestDay: boolean
}

interface Schedule {
  id: number
  name: string
  description: string | null
  weeklyHours: number | null
  isActive: boolean
  shifts: Shift[]
}

const DAY_LABELS = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom']
const ALL_DAYS   = [1, 2, 3, 4, 5, 6, 7]

function fmt(t: string) {
  return t?.slice(0, 5) ?? '—'
}

export default function CuadrantesPage() {
  const { data: schedules = [], isLoading } = useQuery<Schedule[]>({
    queryKey: ['schedules'],
    queryFn: () => api.get('/api/v1/hr/schedules').then(r => r.data),
  })

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
          <Calendar size={24} /> Cuadrantes de trabajo
        </h1>
        <p className="text-slate-500 mt-1">{schedules.length} horarios configurados</p>
      </div>

      {isLoading ? (
        <div className="p-8 text-center text-slate-400">Cargando...</div>
      ) : schedules.length === 0 ? (
        <div className="bg-white rounded-xl border border-slate-200 p-8 text-center text-slate-400">
          No hay cuadrantes configurados aún
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {schedules.map(s => {
            const workDays = new Set(s.shifts.filter(sh => !sh.isRestDay).map(sh => sh.dayOfWeek))
            const firstShift = s.shifts.find(sh => !sh.isRestDay)

            return (
              <div key={s.id} className="bg-white rounded-xl border border-slate-200 p-5">
                <div className="flex items-start justify-between mb-3">
                  <div>
                    <h3 className="font-semibold text-slate-900">{s.name}</h3>
                    {s.description && (
                      <p className="text-xs text-slate-400 mt-0.5">{s.description}</p>
                    )}
                  </div>
                  <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                    s.isActive ? 'bg-green-100 text-green-700' : 'bg-slate-100 text-slate-500'
                  }`}>
                    {s.isActive ? 'Activo' : 'Inactivo'}
                  </span>
                </div>

                {/* Días de la semana */}
                <div className="flex gap-1 mb-3">
                  {ALL_DAYS.map(day => (
                    <span
                      key={day}
                      className={`text-xs px-1.5 py-0.5 rounded font-medium ${
                        workDays.has(day)
                          ? 'bg-slate-900 text-white'
                          : 'bg-slate-100 text-slate-400'
                      }`}
                    >
                      {DAY_LABELS[day]}
                    </span>
                  ))}
                </div>

                {/* Horario del primer día laboral */}
                {firstShift ? (
                  <div className="text-sm text-slate-600">
                    <span className="font-mono">{fmt(firstShift.startTime)}</span>
                    <span className="mx-1 text-slate-400">→</span>
                    <span className="font-mono">{fmt(firstShift.endTime)}</span>
                    {s.weeklyHours && (
                      <span className="ml-2 text-slate-400">· {s.weeklyHours}h/sem</span>
                    )}
                  </div>
                ) : (
                  <div className="text-sm text-slate-400">Sin turnos definidos</div>
                )}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
