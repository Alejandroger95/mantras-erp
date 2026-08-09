import { z } from 'zod'

const envSchema = z.object({
  NODE_ENV:         z.enum(['development', 'production', 'test']).default('development'),
  PORT:             z.coerce.number().default(3000),
  DATABASE_URL:     z.string({ required_error: 'DATABASE_URL es requerida' }),
  JWT_SECRET:       z.string({ required_error: 'JWT_SECRET es requerida' }).min(32, 'JWT_SECRET debe tener al menos 32 caracteres'),
  JWT_EXPIRES_IN:   z.string().default('7d'),
  ALLOWED_ORIGINS:  z.string().default('http://localhost:3001'),
})

const parsed = envSchema.safeParse(process.env)

if (!parsed.success) {
  console.error('❌  Variables de entorno inválidas:')
  console.error(parsed.error.flatten().fieldErrors)
  process.exit(1)
}

export const config = parsed.data

export const isDev  = config.NODE_ENV === 'development'
export const isProd = config.NODE_ENV === 'production'
