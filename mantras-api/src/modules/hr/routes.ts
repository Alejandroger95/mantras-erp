import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { getEmployees, getEmployeeById, getEmployeePunchStatus, registerPunch, getActiveAbsences, getSchedules } from './queries.js'
import { notFound } from '../../core/errors.js'

const hr: FastifyPluginAsync = async (app) => {

  app.addHook('preHandler', app.authenticate)

  // GET /api/v1/hr/employees
  app.get('/employees', async (req, reply) => {
    return reply.send(await getEmployees(req.user.companyId))
  })

  // GET /api/v1/hr/employees/:id
  app.get('/employees/:id', async (req, reply) => {
    const { id } = z.object({ id: z.coerce.number() }).parse(req.params)
    const emp = await getEmployeeById(req.user.companyId, id)
    if (!emp) throw notFound('Empleado no encontrado')
    return reply.send(emp)
  })

  // GET /api/v1/hr/punches/status  — estado actual de todos los empleados hoy
  app.get('/punches/status', async (req, reply) => {
    return reply.send(await getEmployeePunchStatus(req.user.companyId))
  })

  // POST /api/v1/hr/punches  — registrar un fichaje
  app.post('/punches', async (req, reply) => {
    req.log.info({ body: req.body }, '→ POST /punches body recibido')

    const result = z.object({
      employeeId: z.coerce.number().int().positive(),
      punchType:  z.enum(['check_in', 'break_start', 'break_end', 'check_out', 'overtime_start', 'overtime_end', 'absence_start', 'absence_end']),
      notes:      z.string().max(300).optional(),
      punchedAt:  z.string().datetime({ offset: true }).optional(), // permite registrar con hora personalizada
    }).safeParse(req.body)

    if (!result.success) {
      req.log.error({ body: req.body, errors: result.error.flatten() }, '✗ Validación fallida')
      return reply.status(400).send({
        error:   'VALIDATION_ERROR',
        message: 'Datos inválidos',
        details: result.error.flatten().fieldErrors,
      })
    }

    const punch = await registerPunch(req.user.companyId, result.data as Parameters<typeof registerPunch>[1])
    return reply.code(201).send(punch)
  })

  // GET /api/v1/hr/absences
  app.get('/absences', async (req, reply) => {
    return reply.send(await getActiveAbsences(req.user.companyId))
  })

  // GET /api/v1/hr/schedules
  app.get('/schedules', async (req, reply) => {
    return reply.send(await getSchedules(req.user.companyId))
  })
}

export default hr
