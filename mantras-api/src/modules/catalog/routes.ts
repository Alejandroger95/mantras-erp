import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { getServices, getServiceById, getStaff } from './queries.js'
import { notFound } from '../../core/errors.js'

const catalog: FastifyPluginAsync = async (app) => {

  // Todas las rutas del catálogo requieren login
  app.addHook('preHandler', app.authenticate)

  // GET /api/v1/catalog/services
  app.get('/services', async (req, reply) => {
    const services = await getServices(req.user.companyId)
    return reply.send(services)
  })

  // GET /api/v1/catalog/services/:id
  app.get('/services/:id', async (req, reply) => {
    const { id } = z.object({ id: z.coerce.number() }).parse(req.params)
    const service = await getServiceById(req.user.companyId, id)
    if (!service) throw notFound('Servicio no encontrado')
    return reply.send(service)
  })

  // GET /api/v1/catalog/staff
  app.get('/staff', async (req, reply) => {
    const staff = await getStaff(req.user.companyId)
    return reply.send(staff)
  })
}

export default catalog
