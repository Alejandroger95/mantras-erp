'use client'
import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '@/lib/api'
import { Clock, AlertCircle, X } from 'lucide-react'

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
  currentStatus: 'not_started' | 'working' | 'on_break' | 'on_absence' | 'finished'
  nextAction: 'check_in' | 'working_options' | 'break_end' | 'absence_end' | null
}

// ── Configuración visual ───────────────────────────────────────────────────────
const STATUS_CONFIG = {
  not_started: { label: 'Sin fichar',   dot: 'bg-slate-300',  badge: 'bg-slate-100 text-slate-500' },
  working:     { label: 'Trabajando',   dot: 'bg-green-400',  badge: 'bg-green-100 text-green-700' },
  on_break:    { label: 'Almorzando',   dot: 'bg-amber-400',  badge: 'bg-amber-100 text-amber-700' },
  on_absence:  { label: 'Ausente',      dot: 'bg-orange-400', badge: 'bg-orange-100 text-orange-700' },
  finished:    { label: 'Salió',        dot: 'bg-slate-400',  badge: 'bg-slate-100 text-slate-500' },
}

const PUNCH_LABELS: Record<string, string> = {
  check_in:      '🟢 Entrada',
  break_start:   '🟡 Inicio almuerzo',
  break_end:     '🔵 Fin almuerzo',
  absence_start: '⚠️ Inicio ausencia',
  absence_end:   '✅ Fin ausencia',
  check_out:     '🔴 Salida',
}

// Hora local actual en formato HH:MM
function nowHHMM() {
  const d = new Date()
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

// Convierte "HH:MM" de hoy a ISO string con offset local
function todayAtHHMM(hhmm: string): string {
  const [h, m] = hhmm.split(':').map(Number)
  const d = new Date()
  d.setHours(h, m, 0, 0)
  return d.toISOString()
}

// ── Modal de ausencia ──────────────────────────────────────────────────────────
interface AbsenceFormProps {
  employeeId: number
  fullName: string
  onCancel: () => void
  onSubmit: (employeeId: number, startIso: string, endIso: string, notes: string) => void
  loading: boolean
}

function AbsenceForm({ employeeId, fullName, onCancel, onSubmit, loading }: AbsenceFormProps) {
  const defaultStart = (() => {
    const d = new Date()
    d.setMinutes(d.getMinutes() - 60)
    return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
  })()
  const [startTime, setStartTime] = useState(defaultStart)
  const [endTime,   setEndTime]   = useState(nowHHMM())
  const [notes,     setNotes]     = useState('')

  const durationMins = (() => {
    const [sh, sm] = startTime.split(':').map(Number)
    const [eh, em] = endTime.split(':').map(Number)
    return Math.max(0, (eh * 60 + em) - (sh * 60 + sm))
  })()

  const valid = durationMins > 0

  return (
    <div className="mt-3 rounded-lg border border-orange-200 bg-orange-50 p-4 space-y-3">
      <div className="flex items-center justify-between">
        <p className="text-sm font-semibold text-orange-800">⚠️ Registrar ausencia — {fullName}</p>
        <button onClick={onCancel} className="text-orange-400 hover:text-orange-600">
          <X size={16} />
        </button>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="block text-xs text-orange-700 mb-1 font-medium">Hora de inicio</label>
          <input
            type="time"
            value={startTime}
            onChange={e => setStartTime(e.target.value)}
            className="w-full rounded-md border border-orange-300 bg-white px-2 py-1.5 text-sm text-slate-800 focus:outline-none focus:ring-2 focus:ring-orange-400"
          />
        </div>
        <div>
          <label className="block text-xs text-orange-700 mb-1 font-medium">Hora de fin</label>
          <input
            type="time"
            value={endTime}
            onChange={e => setEndTime(e.target.value)}
            className="w-full rounded-md border border-orange-300 bg-white px-2 py-1.5 text-sm text-slate-800 focus:outline-none focus:ring-2 focus:ring-orange-400"
          />
        </div>
      </div>

      {durationMins > 0 && (
        <p className="text-xs text-orange-600">
          Duración: <strong>{Math.floor(durationMins / 60)}h {durationMins % 60}min</strong>
        </p>
      )}
      {!valid && startTime && endTime && (
        <p className="text-xs text-red-500">La hora de fin debe ser posterior a la de inicio.</p>
      )}

      <div>
        <label className="block text-xs text-orange-700 mb-1 font-medium">Motivo <span className="font-normal opacity-60">(opcional)</span></label>
        <input
          type="text"
          value={notes}
          onChange={e => setNotes(e.target.value)}
          placeholder="Ej: Médico, gestión personal…"
          maxLength={200}
          className="w-full rounded-md border border-orange-300 bg-white px-2 py-1.5 text-sm text-slate-800 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-orange-400"
        />
      </div>

      <div className="flex gap-2 pt-1">
        <button
          onClick={onCancel}
          className="flex-1 py-1.5 rounded-md border border-orange-300 text-sm text-orange-700 hover:bg-orange-100 transition"
        >
          Cancelar
        </button>
        <button
          onClick={() => onSubmit(employeeId, todayAtHHMM(startTime), todayAtHHMM(endTime), notes)}
          disabled={!valid || loading}
          className="flex-1 py-1.5 rounded-md bg-orange-500 hover:bg-orange-600 text-white text-sm font-medium transition disabled:opacity-50"
        >
          {loading ? 'Registrando...' : 'Confirmar ausencia'}
        </button>
      </div>
    </div>
  )
}

// ── Componente tarjeta empleado ────────────────────────────────────────────────
function EmployeeCard({
  emp,
  onPunch,
  onAbsence,
  loadingId,
}: {
  emp: EmployeeStatus
  onPunch: (id: number, type: string) => void
  onAbsence: (id: number, startIso: string, endIso: string, notes: string) => void
  loadingId: number | null
}) {
  const [showAbsenceForm, setShowAbsenceForm] = useState(false)

  const status   = STATUS_CONFIG[emp.currentStatus]
  const initials = emp.fullName.split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase()
  const punches  = emp.todayPunches ?? []
  const isLoading = loadingId === emp.employeeId

  // Calcula horas trabajadas (descuenta breaks y ausencias)
  const workedMinutes = (() => {
    let mins = 0
    const now = new Date().toISOString()
    const find = (type: string) => punches.find(p => p.punchType === type)?.punchedAt

    // Segmento 1: check_in → break_start / absence_start / check_out / ahora
    const checkIn = find('check_in')
    if (checkIn) {
      const end1 = find('break_start') ?? find('absence_start') ?? find('check_out') ?? now
      mins += (new Date(end1).getTime() - new Date(checkIn).getTime()) / 60000
    }
    // Segmento 2: break_end → absence_start / check_out / ahora
    const breakEnd = find('break_end')
    if (breakEnd) {
      const end2 = find('absence_start') ?? find('check_out') ?? now
      mins += (new Date(end2).getTime() - new Date(breakEnd).getTime()) / 60000
    }
    // Segmento 3: absence_end → check_out / ahora
    const absenceEnd = find('absence_end')
    if (absenceEnd) {
      const end3 = find('check_out') ?? now
      mins += (new Date(end3).getTime() - new Date(absenceEnd).getTime()) / 60000
    }
    return Math.max(0, Math.floor(mins))
  })()

  const hhmm = (m: number) => `${Math.floor(m / 60)}h ${m % 60}min`
  const fmt  = (iso: string) => new Date(iso).toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit' })

  // Qué botones mostrar según el estado
  const renderActions = () => {
    if (emp.currentStatus === 'not_started') {
      return (
        <button
          onClick={() => onPunch(emp.employeeId, 'check_in')}
          disabled={isLoading}
          className="w-full py-2 rounded-lg text-sm font-medium text-white bg-green-600 hover:bg-green-700 transition disabled:opacity-60"
        >
          {isLoading ? 'Registrando...' : '🟢 Registrar entrada'}
        </button>
      )
    }

    if (emp.currentStatus === 'working') {
      return (
        <div className="space-y-2">
          {/* Botones opcionales en fila */}
          <div className="grid grid-cols-2 gap-2">
            <button
              onClick={() => { setShowAbsenceForm(false); onPunch(emp.employeeId, 'break_start') }}
              disabled={isLoading}
              className="py-2 rounded-lg text-sm font-medium text-white bg-amber-500 hover:bg-amber-600 transition disabled:opacity-60"
            >
              🟡 Almuerzo
            </button>
            <button
              onClick={() => setShowAbsenceForm(v => !v)}
              disabled={isLoading}
              className={`py-2 rounded-lg text-sm font-medium transition disabled:opacity-60 ${
                showAbsenceForm
                  ? 'bg-orange-100 text-orange-700 border border-orange-300'
                  : 'bg-orange-50 text-orange-700 border border-orange-200 hover:bg-orange-100'
              }`}
            >
              <AlertCircle size={13} className="inline mr-1" />
              Ausencia
            </button>
          </div>
          {/* Salida directa */}
          <button
            onClick={() => { setShowAbsenceForm(false); onPunch(emp.employeeId, 'check_out') }}
            disabled={isLoading}
            className="w-full py-2 rounded-lg text-sm font-medium text-white bg-red-500 hover:bg-red-600 transition disabled:opacity-60"
          >
            🔴 Registrar salida
          </button>

          {/* Formulario ausencia expandible */}
          {showAbsenceForm && (
            <AbsenceForm
              employeeId={emp.employeeId}
              fullName={emp.fullName}
              onCancel={() => setShowAbsenceForm(false)}
              loading={isLoading}
              onSubmit={(id, start, end, notes) => {
                setShowAbsenceForm(false)
                onAbsence(id, start, end, notes)
              }}
            />
          )}
        </div>
      )
    }

    if (emp.currentStatus === 'on_break') {
      return (
        <button
          onClick={() => onPunch(emp.employeeId, 'break_end')}
          disabled={isLoading}
          className="w-full py-2 rounded-lg text-sm font-medium text-white bg-blue-500 hover:bg-blue-600 transition disabled:opacity-60"
        >
          {isLoading ? 'Registrando...' : '🔵 Volver del almuerzo'}
        </button>
      )
    }

    if (emp.currentStatus === 'on_absence') {
      return (
        <button
          onClick={() => onPunch(emp.employeeId, 'absence_end')}
          disabled={isLoading}
          className="w-full py-2 rounded-lg text-sm font-medium text-white bg-orange-500 hover:bg-orange-600 transition disabled:opacity-60"
        >
          {isLoading ? 'Registrando...' : '✅ Marcar vuelta de ausencia'}
        </button>
      )
    }

    if (emp.currentStatus === 'finished') {
      return (
        <div className="w-full py-2 text-center text-sm text-slate-400">
          ✓ Jornada completada
        </div>
      )
    }

    return null
  }

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
              {p.notes && (
                <span className="text-slate-400 text-xs truncate">— {p.notes}</span>
              )}
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

      {/* Acciones */}
      {renderActions()}
    </div>
  )
}

// ── Página principal ───────────────────────────────────────────────────────────
export default function FichajesPage() {
  const queryClient = useQueryClient()
  const [loadingId, setLoadingId] = useState<number | null>(null)

  const { data: employees = [], isLoading } = useQuery<EmployeeStatus[]>({
    queryKey: ['punches-status'],
    queryFn: () => api.get('/api/v1/hr/punches/status').then(r => r.data),
    refetchInterval: 30_000,
  })

  const { mutate: registerPunch } = useMutation({
    mutationFn: ({ employeeId, punchType, punchedAt, notes }: {
      employeeId: number
      punchType: string
      punchedAt?: string
      notes?: string
    }) => api.post('/api/v1/hr/punches', { employeeId, punchType, punchedAt, notes }),
    onMutate: ({ employeeId }) => setLoadingId(employeeId),
    onSettled: () => setLoadingId(null),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['punches-status'] }),
    onError: (err: any) => {
      const msg     = err?.response?.data?.message ?? err.message
      const details = JSON.stringify(err?.response?.data?.details ?? {}, null, 2)
      alert(`Error al fichar: ${msg}\n\nDetalle:\n${details}`)
    },
  })

  // Registra ausencia como dos fichajes consecutivos con hora personalizada
  const handleAbsence = (employeeId: number, startIso: string, endIso: string, notes: string) => {
    registerPunch(
      { employeeId, punchType: 'absence_start', punchedAt: startIso, notes: notes || undefined },
      {
        onSuccess: () => {
          registerPunch({ employeeId, punchType: 'absence_end', punchedAt: endIso, notes: notes || undefined })
        },
      }
    )
  }

  const working   = employees.filter(e => e.currentStatus === 'working')
  const onBreak   = employees.filter(e => e.currentStatus === 'on_break')
  const onAbsence = employees.filter(e => e.currentStatus === 'on_absence')
  const finished  = employees.filter(e => e.currentStatus === 'finished')
  const pending   = employees.filter(e => e.currentStatus === 'not_started')

  return (
    <div className="p-8">
      {/* Header */}
      <div className="mb-6">
        <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
          <Clock size={24} /> Fichajes
        </h1>
        <p className="text-slate-500 mt-1">
          {working.length} trabajando
          {onBreak.length > 0 && ` · ${onBreak.length} almorzando`}
          {onAbsence.length > 0 && ` · ${onAbsence.length} ausentes`}
          {finished.length > 0 && ` · ${finished.length} salieron`}
          {pending.length > 0 && ` · ${pending.length} sin fichar`}
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
              loadingId={loadingId}
              onPunch={(id, type) => registerPunch({ employeeId: id, punchType: type })}
              onAbsence={handleAbsence}
            />
          ))}
        </div>
      )}
    </div>
  )
}
