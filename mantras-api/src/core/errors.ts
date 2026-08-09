import { type FastifyError, type FastifyReply, type FastifyRequest } from 'fastify'
import { ZodError } from 'zod'

/** Error de negocio con código HTTP */
export class AppError extends Error {
  constructor(
    public readonly statusCode: number,
    message: string,
    public readonly code?: string,
  ) {
    super(message)
    this.name = 'AppError'
  }
}

export const notFound      = (msg = 'No encontrado')      => new AppError(404, msg, 'NOT_FOUND')
export const unauthorized  = (msg = 'No autorizado')      => new AppError(401, msg, 'UNAUTHORIZED')
export const forbidden     = (msg = 'Acceso denegado')    => new AppError(403, msg, 'FORBIDDEN')
export const badRequest    = (msg: string)                => new AppError(400, msg, 'BAD_REQUEST')
export const conflict      = (msg: string)                => new AppError(409, msg, 'CONFLICT')

/** Handler global de errores para Fastify */
export function errorHandler(
  error: FastifyError | AppError | ZodError | Error,
  _req: FastifyRequest,
  reply: FastifyReply,
) {
  // Error de negocio conocido
  if (error instanceof AppError) {
    return reply.status(error.statusCode).send({
      error:   error.code ?? 'ERROR',
      message: error.message,
    })
  }

  // Error de validación Zod
  if (error instanceof ZodError) {
    return reply.status(400).send({
      error:   'VALIDATION_ERROR',
      message: 'Datos inválidos',
      details: error.flatten().fieldErrors,
    })
  }

  // Error de JWT
  if ('statusCode' in error && (error as FastifyError).statusCode === 401) {
    return reply.status(401).send({
      error:   'UNAUTHORIZED',
      message: 'Token inválido o expirado',
    })
  }

  // Error inesperado — no exponemos detalles en producción
  console.error('Error no controlado:', error)
  return reply.status(500).send({
    error:   'INTERNAL_ERROR',
    message: 'Error interno del servidor',
  })
}
