import type { FastifyPluginAsync } from 'fastify'
import { getDailyDashboard, getMonthlyKPIs } from './queries.js'

const dashboard: FastifyPluginAsync = async (app) => {

  app.addHook('preHandler', app.authenticate)

  // GET /api/v1/dashboard/today
  // El resumen del día: citas, ingresos, próxima cita, top staff
  app.get('/today', async (req, reply) => {
    const data = await getDailyDashboard(req.user.companyId)
    return reply.send(data)
  })

  // GET /api/v1/dashboard/monthly
  // KPIs del mes en curso: totales, ticket promedio, clientes nuevos vs recurrentes
  app.get('/monthly', async (req, reply) => {
    const [data] = await getMonthlyKPIs(req.user.companyId)
    return reply.send(data)
  })
}

export default dashboard
