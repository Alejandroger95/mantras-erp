import '@fastify/jwt'

/** Payload que vive dentro del JWT en cada request */
export interface JWTUser {
  sub:        number   // system_user id
  companyId:  number   // empresa — inyectado en TODOS los queries
  email:      string
  role:       string   // admin | staff | viewer
}

declare module '@fastify/jwt' {
  interface FastifyJWT {
    payload: JWTUser
    user:    JWTUser
  }
}

declare module 'fastify' {
  interface FastifyInstance {
    authenticate: (request: FastifyRequest, reply: FastifyReply) => Promise<void>
  }
}
