import { sql } from '../../core/db.js'
import { unauthorized } from '../../core/errors.js'
import type { JWTUser } from '../../types/fastify.js'

interface LoginParams {
  email:    string
  password: string
}

/**
 * Busca el usuario por email y verifica la contraseña.
 *
 * DEV: usamos cognito_user_id como contraseña local para el MVP.
 * PROD: la auth la maneja Cognito — validamos el JWT de Cognito
 *       y buscamos por cognito_user_id, no por contraseña.
 */
export async function loginService(params: LoginParams): Promise<JWTUser> {
  const [user] = await sql<Array<{
    id:         number
    companyId:  number
    email:      string
    role:       string
    isActive:   boolean
  }>>`
    SELECT
      su.id,
      su.company_id,
      su.email,
      su.role,
      su.is_active
    FROM hr.system_users su
    WHERE su.email           = ${params.email}
      AND su.cognito_user_id = ${params.password}
    LIMIT 1
  `

  if (!user)        throw unauthorized('Email o contraseña incorrectos')
  if (!user.isActive) throw unauthorized('Usuario desactivado')

  return {
    sub:       user.id,
    companyId: user.companyId,
    email:     user.email,
    role:      user.role,
  }
}

/** Devuelve el perfil completo del usuario autenticado */
export async function getMeService(userId: number) {
  const [user] = await sql`
    SELECT
      su.id,
      su.email,
      su.role,
      su.company_id,
      c.name  AS company_name,
      p.first_name,
      p.last_name,
      p.personal_phone AS phone
    FROM hr.system_users su
    INNER JOIN hr.companies c ON c.id = su.company_id
    LEFT  JOIN hr.employees e ON e.id = su.employee_id
    LEFT  JOIN hr.persons   p ON p.id = e.person_id
    WHERE su.id = ${userId}
  `
  return user ?? null
}
