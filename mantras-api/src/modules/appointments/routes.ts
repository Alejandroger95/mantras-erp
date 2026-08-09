import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import {
  getTodayAppointments,
  getAppointmentsByDate,
  createAppointment,
  updateAppointmentStatus,
} from './queries.js'
import { notFound, badRequest } from '../../core/errors.js'

const VALID_STATUSES = ['confirmed', 'in_progress', 'completed', 'cancelled', 'no_show'] as const

const appointments: FastifyPluginAsync = async (app) => {

  app.addHook('preHandler', app.authenticate)

  // GET /api/v1/appointments/today
  app.get('/today', async (req, reply) => {
    const list = await getTodayAppointments(req.user.companyId)
    return reply.send(list)
  })

  // GET /api/v1/appointments?from=2026-08-01&to=2026-08-07
  app.get('/', async (req, reply) => {
    const { from, to } = z.object({
      from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Formato: YYYY-MM-DD'),
      to:   z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Formato: YYYY-MM-DD'),
    }).parse(req.query)

    const list = await getAppointmentsByDate(req.user.companyId, from, to)
    return reply.send(list)
  })

  // POST /api/v1/appointments
  app.post('/', async (req, reply) => {
    const body = z.object({
      customerId:  z.number().int().positive(),
      staffId:     z.number().int().positive(),
      scheduledAt: z.string().datetime({ offset: true }),
      durationMin: z.number().int().min(5).max(480),
      serviceIds:  z.array(z.number().int().positive()).min(1),
      source:      z.enum(['admin', 'whatsapp', 'web', 'phone', 'walk_in']).optional(),
      notes:       z.string().max(500).optional(),
    }).parse(req.body)

    const appt = await createAppointment(req.user.companyId, body)
    return reply.code(201).send(appt)
  })

  // PATCH /api/v1/appointments/:id/status
  app.patch('/:id/status', async (req, reply) => {
    const { id } = z.object({ id: z.coerce.number() }).parse(req.params)
    const { status } = z.object({
      status: z.enum(VALID_STATUSES),
    }).parse(req.body)

    const updated = await updateAppointmentStatus(req.user.companyId, id, status)
    if (!updated) throw notFound('Cita no encontrada')
    return reply.send(updated)
  })
}

export default appointments
