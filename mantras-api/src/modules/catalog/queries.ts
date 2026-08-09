import { sql } from '../../core/db.js'

/** Lista todos los servicios activos del salón */
export async function getServices(companyId: number) {
  return sql`
    SELECT
      s.id,
      s.name,
      s.description,
      sc.name  AS category,
      s.duration_min,
      s.base_price,
      s.currency,
      s.is_active
    FROM services.services s
    LEFT JOIN services.service_categories sc ON sc.id = s.category_id
    WHERE s.company_id = ${companyId}
      AND s.is_active  = true
    ORDER BY sc.sort_order, s.sort_order, s.name
  `
}

/** Detalle de un servicio con sus variantes */
export async function getServiceById(companyId: number, serviceId: number) {
  const [service] = await sql`
    SELECT
      s.id,
      s.name,
      s.description,
      sc.name      AS category,
      s.duration_min,
      s.base_price,
      s.currency,
      s.is_active,
      s.color_hex
    FROM services.services s
    LEFT JOIN services.service_categories sc ON sc.id = s.category_id
    WHERE s.company_id = ${companyId}
      AND s.id         = ${serviceId}
  `

  if (!service) return null

  const variants = await sql`
    SELECT id, name, duration_min, price, currency
    FROM services.service_variants
    WHERE service_id = ${serviceId}
      AND is_active  = true
    ORDER BY price
  `

  return { ...service, variants }
}

/** Lista el personal disponible (estilistas) */
export async function getStaff(companyId: number) {
  return sql`
    SELECT
      e.id,
      p.first_name,
      p.last_name,
      p.first_name || ' ' || p.last_name AS full_name,
      pos.name  AS position,
      sp.skill_level,
      p.photo_url
    FROM hr.employees           e
    INNER JOIN hr.persons       p   ON p.id   = e.person_id
    LEFT  JOIN hr.positions     pos ON pos.id = e.position_id
    LEFT  JOIN services.staff_services sp
           ON sp.employee_id = e.id
          AND sp.is_active   = true
    WHERE e.company_id  = ${companyId}
      AND e.is_active   = true
    GROUP BY e.id, p.first_name, p.last_name, pos.name,
             sp.skill_level, p.photo_url
    ORDER BY p.first_name
  `
}
