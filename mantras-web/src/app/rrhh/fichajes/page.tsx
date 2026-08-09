'use client'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '@/lib/api'
import { Clock } from 'lucide-react'

// ── Tipos ─────────────────────────────────────────────────────────────────────
interface PunchEvent {
  id: number
  punchType: string
  punchedAt: string
  notes: string | null
}

interface EmployeeStatus {
  employeeId: number
  fullName: string
  photoUrl: string | null
  positionName: string | null
  lastPunchType: string | null
  lastPunchAt: string | null
  todayPunches: PunchEvent[] | null
  currentStatus: 'not_started' | 'working' | 'on_break' | 'finished'
  nextAction: 'check_in' | 'break_start' | 'break_end' | 'check_out' | null
}

// ── Configuración visual ───────────────────────────────────────────────────────
const STATUS_CONFIG = {
  not_started: { label: 'Sin fichar',   dot: 'bg-slate-300',  badge: 'bg-slate-100 text-slate-500' },
  working:     { label: 'Trabajando',   dot: 'bg-green-400',  badge: 'bg-green-100 text-green-700' },
  on_break:    { label: 'Almorzando',   dot: 'bg-amber-400',  badge: 'bg-amber-100 text-amber-700' },
  finished:    { label: 'Salió',        dot: 'bg-slate-400',  badge: 'bg-slate-100 text-slate-500' },
}

const ACTION_CONFIG: Record<string, { label: string; color: string }> = {
  check_in:    { label: '🟢 Registrar entrada',       color: 'bg-green-600 hover:bg-green-700' },
  break_start: { label: '🟡 Iniciar almuerzo',         color: 'bg-amber-500 hover:bg-amber-600' },
  break_end:   { label: '🔵 Volver del almuerzo',      color: 'bg-blue-500 hover:bg-blue-600'   },
  check_out:   { label: '🔴 Registrar salida',         color: 'bg-red-500 hover:bg-red-600'     },
}

const PUNCH_LABELS: Record<string, string> = {
  check_in:    '🟢 Entrada',
  break_start: '🟡 Inicio almuerzo',
  break_end:   '🔵 Fin almuerzo',
  check_out:   '🔴 Salida',
}

// ── Componente tarjeta empleado ────────────────────────────────────────────────
function EmployeeCard({ emp, onPunch, loading }: { emp: EmployeeStatus; onPunch: (id: number, type: string) => void; loading?: boolean }) {
  const status  = STATUS_CONFIG[emp.currentStatus]
  const action  = emp.nextAction ? ACTION_CONFIG[emp.nextAction] : null
  const initials = emp.fullName.split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase()
  const punches  = emp.todayPunches ?? []

  // Calcula horas trabajadas
  const workedMinutes = (() => {
    let mins = 0
    const byType = (t: string) => punches.find(p => p.punchType === t)?.punchedAt
    const checkIn    = byType('check_in')
    const breakStart = byType('break_start')
    const breakEnd   = byType('break_end')
    const checkOut   = byType('check_out')
    if (checkIn) {
      const endFirst  = breakStart ?? checkOut ?? new Date().toISOString()
      mins += (new Date(endFirst).getTime() - new Date(checkIn).getTime()) / 60000
    }
    if (breakEnd) {
      const endSecond = checkOut ?? new Date().toISOString()
      mins += (new Date(endSecond).getTime() - new Date(breakEnd).getTime()) / 60000
    }
    return Math.max(0, Math.floor(mins))
  })()

  const hhmm = (m: number) => `${Math.floor(m / 60)}h ${m % 60}min`
  const fmt  = (iso: string) => new Date(iso).toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit' })

  return (
    <div className="bg-white rounded-xl border border-slate-200 p-5">
      {/* Header */}
      <div className="flex items-center gap-3 mb-4">
        {emp.photoUrl ? (
          <img src={emp.photoUrl} alt={emp.fullName} className="w-10 h-10 rounded-full object-cover" />
        ) : (
          <div className="w-10 h-10 rounded-full bg-slate-200 flex items-center justify-center text-sm font-semibold text-slate-600">
            {initials}
          </div>
        )}
        <div className="flex-1 min-w-0">
          <p className="font-semibold text-slate-900 truncate">{emp.fullName}</p>
          <p className="text-xs text-slate-400">{emp.positionName ?? '—'}</p>
        </div>
        <span className={`flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium ${status.badge}`}>
          <span className={`w-1.5 h-1.5 rounded-full ${status.dot}`} />
          {status.label}
        </span>
      </div>

      {/* Línea de tiempo */}
      {punches.length > 0 ? (
        <div className="mb-4 space-y-1">
          {punches.map((p) => (
            <div key={p.id} className="flex items-center gap-2 text-sm">
              <span className="text-slate-400 font-mono w-12 text-right">{fmt(p.punchedAt)}</span>
              <span className="text-slate-600">{PUNCH_LABELS[p.punchType] ?? p.punchType}</span>
            </div>
          ))}
          {workedMinutes > 0 && (
            <div className="flex items-center gap-2 text-xs text-slate-400 pt-1 border-t border-slate-100 mt-2">
              <Clock size={12} />
              <span>
                {emp.currentStatus === 'finished' ? 'Total trabajado' : 'Trabajado hasta ahora'}:
                <strong className="text-slate-700 ml-1">{hhmm(workedMinutes)}</strong>
              </span>
            </div>
          )}
        </div>
      ) : (
        <p className="text-sm text-slate-400 mb-4">Sin fichajes hoy</p>
      )}

      {/* Botón siguiente acción */}
      {action && emp.nextAction && (
        <button
          onClick={() => onPunch(emp.employeeId, emp.nextAction!)}
          disabled={loading}
          className={`w-full py-2 rounded-lg text-sm font-medium text-white transition ${action.color} disabled:opacity-60`}
        >
          {loading ? 'Registrando...' : action.label}
        </button>
      )}
      {emp.currentStatus === 'finished' && (
        <div className="w-full py-2 text-center text-sm text-slate-400">
          ✓ Jornada completada
        </div>
      )}
    </div>
  )
}

// ── Página principal ───────────────────────────────────────────────────────────
export default function FichajesPage() {
  const queryClient = useQueryClient()

  const { data: employees = [], isLoading } = useQuery<EmployeeStatus[]>({
    queryKey: ['punches-status'],
    queryFn: () => api.get('/api/v1/hr/punches/status').then(r => r.data),
    refetchInterval: 30_000,
  })

  const { mutate: registerPunch, isPending } = useMutation({
    mutationFn: ({ employeeId, punchType }: { employeeId: number; punchType: string }) =>
      api.post('/api/v1/hr/punches', { employeeId, punchType }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['punches-status'] }),
    onError: (err: any) => {
      const msg     = err?.response?.data?.message ?? err.message
      const details = JSON.stringify(err?.response?.data?.details ?? {}, null, 2)
      alert(`Error al fichar: ${msg}\n\nDetalle:\n${details}`)
    },
  })

  const working  = employees.filter(e => e.currentStatus === 'working')
  const onBreak  = employees.filter(e => e.currentStatus === 'on_break')
  const finished = employees.filter(e => e.currentStatus === 'finished')
  const pending  = employees.filter(e => e.currentStatus === 'not_started')

  return (
    <div className="p-8">
      {/* Header */}
      <div className="mb-6">
        <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
          <Clock size={24} /> Fichajes
        </h1>
        <p className="text-slate-500 mt-1">
          {working.length} trabajando · {onBreak.length} almorzando · {finished.length} salieron · {pending.length} sin fichar
        </p>
      </div>

      {isLoading ? (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {[...Array(4)].map((_, i) => (
            <div key={i} className="bg-white rounded-xl border border-slate-200 h-48 animate-pulse" />
          ))}
        </div>
      ) : employees.length === 0 ? (
        <div className="bg-white rounded-xl border border-slate-200 p-8 text-center text-slate-400">
          No hay empleados activos
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {employees.map(emp => (
            <EmployeeCard
              key={emp.employeeId}
              emp={emp}
              loading={isPending}
              onPunch={(id, type) => registerPunch({ employeeId: id, punchType: type })}
            />
          ))}
        </div>
      )}
    </div>
  )
}
