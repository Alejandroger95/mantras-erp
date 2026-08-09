import Fastify from 'fastify'
import cors from '@fastify/cors'
import helmet from '@fastify/helmet'
import jwt from '@fastify/jwt'
import { config, isDev } from './core/config.js'
import { errorHandler } from './core/errors.js'
import type { JWTUser } from './types/fastify.js'

export async function buildApp() {
  const app = Fastify({
    logger: isDev
      ? { transport: { target: 'pino-pretty', options: { colorize: true } } }
      : true,
  })

  // ── Seguridad ──────────────────────────────────────────
  await app.register(helmet, { contentSecurityPolicy: false })

  await app.register(cors, {
    origin: config.ALLOWED_ORIGINS.split(','),
    methods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  })

  // ── JWT ────────────────────────────────────────────────
  await app.register(jwt, {
    secret:  config.JWT_SECRET,
    sign:    { expiresIn: config.JWT_EXPIRES_IN },
  })

  // Decorator: protege rutas que requieren login
  app.decorate('authenticate', async function (request, reply) {
    try {
      await request.jwtVerify<JWTUser>()
    } catch {
      reply.code(401).send({ error: 'UNAUTHORIZED', message: 'Token inválido o expirado' })
    }
  })

  // ── Error handler global ───────────────────────────────
  app.setErrorHandler(errorHandler)

  // ── Rutas ──────────────────────────────────────────────
  await app.register(import('./modules/health/routes.js'))
  await app.register(import('./modules/auth/routes.js'),         { prefix: '/api/v1/auth' })
  await app.register(import('./modules/catalog/routes.js'),      { prefix: '/api/v1/catalog' })
  await app.register(import('./modules/appointments/routes.js'), { prefix: '/api/v1/appointments' })
  await app.register(import('./modules/dashboard/routes.js'),    { prefix: '/api/v1/dashboard' })

  return app
}
