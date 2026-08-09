'use client'
import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api'
import { useAuth } from '@/lib/auth'
import { Calendar, DollarSign, Users, TrendingUp } from 'lucide-react'

function StatCard({ label, value, icon: Icon, color }: {
  label: string; value: string | number; icon: React.ElementType; color: string
}) {
  return (
    <div className="bg-white rounded-xl border border-slate-200 p-5 flex items-center gap-4">
      <div className={`p-3 rounded-lg ${color}`}>
        <Icon size={20} className="text-white" />
      </div>
      <div>
        <p className="text-sm text-slate-500">{label}</p>
        <p className="text-2xl font-semibold text-slate-900">{value}</p>
      </div>
    </div>
  )
}

export default function DashboardPage() {
  const { user } = useAuth()

  const { data, isLoading } = useQuery({
    queryKey: ['dashboard-today'],
    queryFn: () => api.get('/api/v1/dashboard/today').then(r => r.data),
    refetchInterval: 60_000, // refresca cada minuto
  })

  const today = new Date().toLocaleDateString('es-PE', {
    weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
  })

  return (
    <div className="p-8">
      {/* Header */}
      <div className="mb-8">
        <h1 className="text-2xl font-semibold text-slate-900">
          Buenos días, {user?.email?.split('@')[0]} 👋
        </h1>
        <p className="text-slate-500 mt-1 capitalize">{today}</p>
      </div>

      {isLoading ? (
        <div className="grid grid-cols-4 gap-4">
          {[...Array(4)].map((_, i) => (
            <div key={i} className="bg-white rounded-xl border border-slate-200 p-5 h-24 animate-pulse" />
          ))}
        </div>
      ) : (
        <>
          {/* KPIs */}
          <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4 mb-8">
            <StatCard
              label="Citas hoy"
              value={data?.appointmentsTotal ?? 0}
              icon={Calendar}
              color="bg-blue-500"
            />
            <StatCard
              label="Completadas"
              value={data?.appointmentsCompleted ?? 0}
              icon={TrendingUp}
              color="bg-green-500"
            />
            <StatCard
              label="En progreso"
              value={data?.appointmentsInProgress ?? 0}
              icon={Users}
              color="bg-amber-500"
            />
            <StatCard
              label="Ingresos del día"
              value={`S/ ${Number(data?.totalRevenue ?? 0).toFixed(2)}`}
              icon={DollarSign}
              color="bg-purple-500"
            />
          </div>

          {/* Próxima cita */}
          {data?.nextAt && (
            <div className="bg-white rounded-xl border border-slate-200 p-5 mb-4">
              <h2 className="text-sm font-semibold text-slate-500 mb-3">PRÓXIMA CITA</h2>
              <div className="flex items-center gap-4">
                <div className="text-2xl font-bold text-slate-900">
                  {new Date(data.nextAt).toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit' })}
                </div>
                <div>
                  <p className="font-medium text-slate-900">{data.nextCustomer}</p>
                  <p className="text-sm text-slate-500">con {data.nextStaff} · {data.nextServices}</p>
                </div>
              </div>
            </div>
          )}

          {/* Top staff */}
          {data?.topStaff?.length > 0 && (
            <div className="bg-white rounded-xl border border-slate-200 p-5">
              <h2 className="text-sm font-semibold text-slate-500 mb-3">TOP ESTILISTAS HOY</h2>
              <div className="space-y-3">
                {data.topStaff.map((s: { staffName: string; appointmentsDone: number; revenue: number }, i: number) => (
                  <div key={i} className="flex items-center justify-between">
                    <div className="flex items-center gap-3">
                      <span className="text-slate-400 text-sm w-4">{i + 1}</span>
                      <span className="font-medium text-slate-900">{s.staffName}</span>
                    </div>
                    <div className="text-right">
                      <span className="text-sm text-slate-500">{s.appointmentsDone} citas</span>
                      <span className="ml-3 text-sm font-medium text-slate-900">S/ {Number(s.revenue).toFixed(2)}</span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </>
      )}
    </div>
  )
}
