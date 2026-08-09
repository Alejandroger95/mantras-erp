import type { FastifyPluginAsync } from 'fastify'
import { sql } from '../../core/db.js'

const health: FastifyPluginAsync = async (app) => {
  // GET /health — para Cloud Run y balanceadores
  app.get('/health', async (_req, reply) => {
    try {
      await sql`SELECT 1`
      return reply.send({ status: 'ok', db: 'connected', ts: new Date().toISOString() })
    } catch {
      return reply.code(503).send({ status: 'error', db: 'disconnected' })
    }
  })
}

export default health
