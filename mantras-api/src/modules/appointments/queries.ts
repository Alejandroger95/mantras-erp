import { sql } from '../../core/db.js'

/** Citas del día — la agenda principal */
export async function getTodayAppointments(companyId: number) {
  return sql`
    SELECT
      a.id,
      a.scheduled_at,
      a.duration_min,
      a.status,
      a.source,

      -- Cliente
      c.id          AS customer_id,
      c.first_name  AS customer_first_name,
      c.last_name   AS customer_last_name,
      c.phone       AS customer_phone,

      -- Estilista
      e.id          AS staff_id,
      p.first_name  AS staff_first_name,
      p.last_name   AS staff_last_name,

      -- Servicio(s)
      STRING_AGG(sv.name, ', ' ORDER BY sv.name) AS services

    FROM services.appointments        a
    INNER JOIN sales.customers        c  ON c.id = a.customer_id
    INNER JOIN hr.employees           e  ON e.id = a.staff_id
    INNER JOIN hr.persons             p  ON p.id = e.person_id
    LEFT  JOIN services.appointment_services aps ON aps.appointment_id = a.id
    LEFT  JOIN services.services      sv  ON sv.id = aps.service_id

    WHERE a.company_id  = ${companyId}
      AND a.scheduled_at::date = CURRENT_DATE
      AND a.status NOT IN ('cancelled', 'no_show')

    GROUP BY a.id, a.scheduled_at, a.duration_min, a.status, a.source,
             c.id, c.first_name, c.last_name, c.phone,
             e.id, p.first_name, p.last_name

    ORDER BY a.scheduled_at
  `
}

/** Citas por fecha (para la agenda semanal) */
export async function getAppointmentsByDate(
  companyId: number,
  dateFrom: string,
  dateTo: string,
) {
  return sql`
    SELECT
      a.id,
      a.scheduled_at,
      a.duration_min,
      a.status,
      a.source,
      c.first_name  AS customer_first_name,
      c.last_name   AS customer_last_name,
      c.phone       AS customer_phone,
      p.first_name  AS staff_first_name,
      p.last_name   AS staff_last_name,
      STRING_AGG(sv.name, ', ' ORDER BY sv.name) AS services
    FROM services.appointments        a
    INNER JOIN sales.customers        c  ON c.id = a.customer_id
    INNER JOIN hr.employees           e  ON e.id = a.staff_id
    INNER JOIN hr.persons             p  ON p.id = e.person_id
    LEFT  JOIN services.appointment_services aps ON aps.appointment_id = a.id
    LEFT  JOIN services.services      sv  ON sv.id = aps.service_id
    WHERE a.company_id        = ${companyId}
      AND a.scheduled_at::date BETWEEN ${dateFrom}::date AND ${dateTo}::date
    GROUP BY a.id, a.scheduled_at, a.duration_min, a.status, a.source,
             c.first_name, c.last_name, c.phone,
             p.first_name, p.last_name
    ORDER BY a.scheduled_at
  `
}

/** Crea una nueva cita */
export async function createAppointment(companyId: number, data: {
  customerId:   number
  staffId:      number
  scheduledAt:  string
  durationMin:  number
  serviceIds:   number[]
  source?:      string
  notes?:       string
}) {
  const [appt] = await sql`
    INSERT INTO services.appointments (
      company_id, customer_id, staff_id,
      scheduled_at, duration_min, source, notes, status
    ) VALUES (
      ${companyId}, ${data.customerId}, ${data.staffId},
      ${data.scheduledAt}, ${data.durationMin},
      ${data.source ?? 'admin'}, ${data.notes ?? null}, 'confirmed'
    )
    RETURNING id, scheduled_at, status
  `

  // Inserta los servicios de la cita
  if (data.serviceIds.length > 0) {
    await sql`
      INSERT INTO services.appointment_services (appointment_id, service_id, company_id)
      SELECT ${appt.id}, unnest(${data.serviceIds}::bigint[]), ${companyId}
    `
  }

  return appt
}

/** Actualiza el estado de una cita */
export async function updateAppointmentStatus(
  companyId: number,
  appointmentId: number,
  status: string,
) {
  const [updated] = await sql`
    UPDATE services.appointments
    SET status = ${status}, updated_at = NOW()
    WHERE id = ${appointmentId} AND company_id = ${companyId}
    RETURNING id, status, scheduled_at
  `
  return updated ?? null
}
