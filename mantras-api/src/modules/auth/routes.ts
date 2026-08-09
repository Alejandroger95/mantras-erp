import type { FastifyPluginAsync } from 'fastify'
import { z } from 'zod'
import { loginService, getMeService } from './service.js'
import { notFound } from '../../core/errors.js'

const loginSchema = z.object({
  email:    z.string().email('Email inválido'),
  password: z.string().min(1, 'Contraseña requerida'),
})

const auth: FastifyPluginAsync = async (app) => {

  // POST /api/v1/auth/login
  app.post('/login', async (req, reply) => {
    const body = loginSchema.parse(req.body)
    const user  = await loginService(body)
    const token = app.jwt.sign(user)

    return reply.send({
      token,
      user: {
        id:        user.sub,
        email:     user.email,
        role:      user.role,
        companyId: user.companyId,
      },
    })
  })

  // GET /api/v1/auth/me  (requiere token)
  app.get('/me', { preHandler: app.authenticate }, async (req, reply) => {
    const me = await getMeService(req.user.sub)
    if (!me) throw notFound('Usuario no encontrado')
    return reply.send(me)
  })
}

export default auth
