import { sql } from '../../core/db.js'

/**
 * Resumen del día — el primer número que tu mamá ve al abrir la app.
 * Una sola query con múltiples CTEs para que sea un solo round-trip a la DB.
 */
export async function getDailyDashboard(companyId: number, date?: string) {
  const targetDate = date ?? 'CURRENT_DATE'

  const [result] = await sql`
    WITH

    -- Citas del día
    appts AS (
      SELECT
        COUNT(*)                                            AS total,
        COUNT(*) FILTER (WHERE status = 'confirmed')        AS confirmed,
        COUNT(*) FILTER (WHERE status = 'completed')        AS completed,
        COUNT(*) FILTER (WHERE status = 'cancelled')        AS cancelled,
        COUNT(*) FILTER (WHERE status = 'no_show')          AS no_show,
        COUNT(*) FILTER (WHERE status = 'in_progress')      AS in_progress
      FROM services.appointments
      WHERE company_id    = ${companyId}
        AND scheduled_at::date = CURRENT_DATE
    ),

    -- Ingresos del día (citas completadas + ventas POS)
    revenue AS (
      SELECT COALESCE(SUM(i.total_amount), 0) AS total_revenue
      FROM sales.invoices i
      WHERE i.company_id   = ${companyId}
        AND i.issue_date   = CURRENT_DATE
        AND i.status NOT IN ('cancelled', 'voided')
    ),

    -- Próxima cita del día (la que viene ahora)
    next_appt AS (
      SELECT
        a.scheduled_at,
        c.first_name || ' ' || c.last_name                 AS customer_name,
        p.first_name  || ' ' || p.last_name                AS staff_name,
        STRING_AGG(sv.name, ', ' ORDER BY sv.name)         AS services
      FROM services.appointments        a
      INNER JOIN sales.customers        c   ON c.id = a.customer_id
      INNER JOIN hr.employees           e   ON e.id = a.staff_id
      INNER JOIN hr.persons             p   ON p.id = e.person_id
      LEFT  JOIN services.appointment_services aps ON aps.appointment_id = a.id
      LEFT  JOIN services.services      sv  ON sv.id = aps.service_id
      WHERE a.company_id      = ${companyId}
        AND a.scheduled_at::date = CURRENT_DATE
        AND a.scheduled_at    > NOW()
        AND a.status          = 'confirmed'
      GROUP BY a.id, a.scheduled_at, c.first_name, c.last_name, p.first_name, p.last_name
      ORDER BY a.scheduled_at
      LIMIT 1
    ),

    -- Top 3 estilistas del día por ingresos
    top_staff AS (
      SELECT
        p.first_name || ' ' || p.last_name                 AS staff_name,
        COUNT(a.id)                                         AS appointments_done,
        COALESCE(SUM(aps.price), 0)                         AS revenue
      FROM services.appointments        a
      INNER JOIN hr.employees           e   ON e.id = a.staff_id
      INNER JOIN hr.persons             p   ON p.id = e.person_id
      LEFT  JOIN services.appointment_services aps ON aps.appointment_id = a.id
      WHERE a.company_id      = ${companyId}
        AND a.scheduled_at::date = CURRENT_DATE
        AND a.status          = 'completed'
      GROUP BY e.id, p.first_name, p.last_name
      ORDER BY revenue DESC
      LIMIT 3
    )

    SELECT
      -- Citas
      appts.total             AS appointments_total,
      appts.confirmed         AS appointments_confirmed,
      appts.completed         AS appointments_completed,
      appts.cancelled         AS appointments_cancelled,
      appts.no_show           AS appointments_no_show,
      appts.in_progress       AS appointments_in_progress,

      -- Ingresos
      revenue.total_revenue,

      -- Próxima cita
      next_appt.scheduled_at  AS next_at,
      next_appt.customer_name AS next_customer,
      next_appt.staff_name    AS next_staff,
      next_appt.services      AS next_services,

      -- Top staff (JSON)
      (SELECT JSON_AGG(top_staff) FROM top_staff) AS top_staff,

      -- Fecha del reporte
      CURRENT_DATE            AS report_date,
      NOW()                   AS generated_at

    FROM appts, revenue
    LEFT JOIN next_appt ON TRUE
  `

  return result
}

/** KPIs del mes en curso — para el reporte mensual */
export async function getMonthlyKPIs(companyId: number) {
  return sql`
    SELECT
      DATE_TRUNC('month', CURRENT_DATE)                       AS month_start,

      -- Citas
      COUNT(a.id)                                             AS total_appointments,
      COUNT(a.id) FILTER (WHERE a.status = 'completed')       AS completed_appointments,
      COUNT(a.id) FILTER (WHERE a.status = 'no_show')         AS no_show_count,

      -- Ingresos
      COALESCE(SUM(i.total_amount), 0)                        AS total_revenue,
      COALESCE(AVG(i.total_amount), 0)                        AS avg_ticket,

      -- Clientes únicos atendidos
      COUNT(DISTINCT a.customer_id)                           AS unique_clients,

      -- Clientas nuevas (primera cita en el sistema)
      COUNT(DISTINCT a.customer_id) FILTER (
        WHERE NOT EXISTS (
          SELECT 1 FROM services.appointments a2
          WHERE a2.customer_id = a.customer_id
            AND a2.company_id  = a.company_id
            AND a2.scheduled_at < DATE_TRUNC('month', CURRENT_DATE)
        )
      )                                                       AS new_clients

    FROM services.appointments   a
    LEFT JOIN sales.invoices     i
           ON i.company_id  = a.company_id
          AND i.issue_date  = a.scheduled_at::date
    WHERE a.company_id             = ${companyId}
      AND a.scheduled_at::date >= DATE_TRUNC('month', CURRENT_DATE)
  `
}
