import postgres from 'postgres'
import { config } from './config.js'

/**
 * Conexión global a PostgreSQL usando postgres.js
 * — el driver más rápido para Node.js
 * — template literals protegen contra SQL injection por defecto
 * — tipos NUMERIC de PostgreSQL se parsean como number automáticamente
 */
export const sql = postgres(config.DATABASE_URL, {
  max:             20,   // pool de conexiones
  idle_timeout:    30,   // segundos antes de cerrar una conexión idle
  connect_timeout: 10,   // segundos para conectar

  types: {
    // PostgreSQL devuelve NUMERIC como string — lo convertimos a number
    numeric: {
      to:        0,
      from:      [1700],
      serialize: (x: number) => x.toString(),
      parse:     (x: string) => parseFloat(x),
    },
  },

  transform: {
    // snake_case en DB → camelCase en TypeScript automáticamente
    column: postgres.toCamel,
    // PostgreSQL BIGINT / BIGSERIAL → JS BigInt por defecto, pero
    // JSON.stringify no soporta BigInt → lo convertimos a number.
    // (IDs no superan 2^53, así que number es seguro)
    value: (v: unknown) => typeof v === 'bigint' ? Number(v) : v,
  },
})

/** Cierra el pool — llamar al apagar el servidor */
export async function closeDb() {
  await sql.end()
}
