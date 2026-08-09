import { sql } from '../../core/db.js'

/** Lista de empleados activos con su persona, cargo y departamento */
export async function getEmployees(companyId: number) {
  return sql`
    SELECT
      e.id,
      e.employee_number,
      e.corporate_email,
      e.corporate_phone,
      e.hire_date,
      e.status,
      e.is_active,

      -- Persona
      p.first_name,
      p.last_name,
      p.first_name || ' ' || p.last_name  AS full_name,
      p.personal_email,
      p.personal_phone,
      p.photo_url,
      p.gender,
      p.birth_date,

      -- Cargo y Departamento
      pos.name   AS position_name,
      dep.name   AS department_name

    FROM hr.employees     e
    INNER JOIN hr.persons     p   ON p.id   = e.person_id
    LEFT  JOIN hr.positions   pos ON pos.id = e.position_id
    LEFT  JOIN hr.departments dep ON dep.id = e.department_id

    WHERE e.company_id = ${companyId}
      AND e.is_active  = true

    ORDER BY p.last_name, p.first_name
  `
}

/** Detalle de un empleado */
export async function getEmployeeById(companyId: number, employeeId: number) {
  const [employee] = await sql`
    SELECT
      e.id,
      e.employee_number,
      e.corporate_email,
      e.corporate_phone,
      e.hire_date,
      e.termination_date,
      e.work_city,
      e.work_country,
      e.status,
      e.is_active,

      p.first_name,
      p.last_name,
      p.personal_email,
      p.personal_phone,
      p.emergency_phone,
      p.emergency_contact,
      p.photo_url,
      p.gender,
      p.birth_date,
      p.address,
      p.city,
      p.country,

      pos.name   AS position_name,
      dep.name   AS department_name

    FROM hr.employees     e
    INNER JOIN hr.persons     p   ON p.id   = e.person_id
    LEFT  JOIN hr.positions   pos ON pos.id = e.position_id
    LEFT  JOIN hr.departments dep ON dep.id = e.department_id

    WHERE e.company_id = ${companyId}
      AND e.id         = ${employeeId}
  `
  return employee ?? null
}

/** Estado actual de cada empleado hoy — con su historial de fichajes y próxima acción */
export async function getEmployeePunchStatus(companyId: number) {
  return sql`
    WITH today_punches AS (
      SELECT
        tp.id,
        tp.employee_id,
        tp.punch_type,
        tp.punched_at,
        tp.notes,
        ROW_NUMBER() OVER (PARTITION BY tp.employee_id ORDER BY tp.punched_at DESC) AS rn
      FROM hr.time_punches tp
      WHERE tp.company_id      = ${companyId}
        AND tp.punched_at::date = CURRENT_DATE
        AND tp.is_valid         = true
    ),
    last_punch AS (
      SELECT * FROM today_punches WHERE rn = 1
    ),
    all_today AS (
      SELECT
        employee_id,
        JSON_AGG(
          JSON_BUILD_OBJECT(
            'id',        id,
            'punchType', punch_type,
            'punchedAt', punched_at,
            'notes',     notes
          ) ORDER BY punched_at
        ) AS punches
      FROM today_punches
      GROUP BY employee_id
    )
    SELECT
      e.id                                            AS employee_id,
      p.first_name || ' ' || p.last_name             AS full_name,
      p.photo_url,
      pos.name                                        AS position_name,
      lp.punch_type                                   AS last_punch_type,
      lp.punched_at                                   AS last_punch_at,
      at2.punches                                     AS today_punches,

      -- Estado semántico actual
      CASE
        WHEN lp.punch_type IS NULL        THEN 'not_started'
        WHEN lp.punch_type = 'check_in'   THEN 'working'
        WHEN lp.punch_type = 'break_start' THEN 'on_break'
        WHEN lp.punch_type = 'break_end'  THEN 'working'
        WHEN lp.punch_type = 'check_out'  THEN 'finished'
        ELSE 'working'
      END                                             AS current_status,

      -- Próxima acción a realizar
      CASE
        WHEN lp.punch_type IS NULL         THEN 'check_in'
        WHEN lp.punch_type = 'check_in'   THEN 'break_start'
        WHEN lp.punch_type = 'break_start' THEN 'break_end'
        WHEN lp.punch_type = 'break_end'  THEN 'check_out'
        WHEN lp.punch_type = 'check_out'  THEN NULL
        ELSE 'check_out'
      END                                             AS next_action

    FROM hr.employees        e
    INNER JOIN hr.persons    p   ON p.id   = e.person_id
    LEFT  JOIN hr.positions  pos ON pos.id = e.position_id
    LEFT  JOIN last_punch    lp  ON lp.employee_id = e.id
    LEFT  JOIN all_today     at2 ON at2.employee_id = e.id

    WHERE e.company_id = ${companyId}
      AND e.is_active  = true

    ORDER BY p.last_name, p.first_name
  `
}

/** Registra un nuevo fichaje */
export async function registerPunch(companyId: number, data: {
  employeeId: number
  punchType:  string
  notes?:     string
}) {
  const [punch] = await sql`
    INSERT INTO hr.time_punches (company_id, employee_id, punch_type, punched_at, source)
    VALUES (${companyId}, ${data.employeeId}, ${data.punchType}, NOW(), 'web')
    RETURNING id, punch_type, punched_at
  `
  return punch
}

/** Ausencias activas (vacaciones, permisos, bajas) */
export async function getActiveAbsences(companyId: number) {
  return sql`
    SELECT
      a.id,
      a.start_date,
      a.end_date,
      a.status,
      a.notes,
      at2.name                             AS absence_type,
      p.first_name || ' ' || p.last_name  AS full_name,
      p.photo_url

    FROM hr.absences      a
    INNER JOIN hr.employees    e   ON e.id   = a.employee_id
    INNER JOIN hr.persons      p   ON p.id   = e.person_id
    INNER JOIN hr.absence_types at2 ON at2.id = a.absence_type_id

    WHERE e.company_id  = ${companyId}
      AND a.status      = 'approved'
      AND a.end_date   >= CURRENT_DATE

    ORDER BY a.start_date
  `
}

/** Cuadrantes/horarios configurados con sus turnos diarios */
export async function getSchedules(companyId: number) {
  return sql`
    SELECT
      s.id,
      s.name,
      s.description,
      s.weekly_hours,
      s.is_active,
      COALESCE(
        JSON_AGG(
          JSON_BUILD_OBJECT(
            'dayOfWeek', sh.day_of_week,
            'startTime', sh.start_time,
            'endTime',   sh.end_time,
            'isRestDay', sh.is_rest_day
          ) ORDER BY sh.day_of_week
        ) FILTER (WHERE sh.id IS NOT NULL),
        '[]'
      ) AS shifts
    FROM hr.schedules s
    LEFT JOIN hr.shifts sh ON sh.schedule_id = s.id AND sh.is_active = true
    WHERE s.company_id = ${companyId}
    GROUP BY s.id, s.name, s.description, s.weekly_hours, s.is_active
    ORDER BY s.name
  `
}
