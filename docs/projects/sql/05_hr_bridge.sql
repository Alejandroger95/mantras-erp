-- ============================================================
-- mantrasdb | Módulo Projects
-- Archivo: 05_hr_bridge.sql
-- Descripción: Puente con el módulo HR
--
-- Extiende project_members con departamento (auto-rellenado
-- desde hr.employees.department_id) y agrega vistas que
-- permiten ver la carga de proyectos desde RR.HH.:
--
--   1. ALTER project_members: department_id + position_id
--   2. Trigger: auto-rellenar desde el empleado al insertar
--   3. projects.employee_project_view
--      → por empleado: en qué proyectos está, rol, horas,
--        tareas asignadas y tareas vencidas
--   4. projects.department_project_load_view
--      → por departamento: proyectos activos, miembros,
--        horas comprometidas y tareas vencidas
--   5. projects.employee_task_load_view
--      → por empleado: tareas activas hoy, horas estimadas
--        restantes y riesgo de sobrecarga
-- ============================================================

-- ============================================================
-- 1. Extender project_members con datos organizacionales de HR
-- ============================================================
ALTER TABLE projects.project_members
    ADD COLUMN IF NOT EXISTS department_id BIGINT REFERENCES hr.departments(id),
    -- Departamento del empleado al momento de unirse al proyecto.
    -- Auto-rellenado por el trigger; puede sobreescribirse manualmente
    -- si el empleado participa como representante de otra área.

    ADD COLUMN IF NOT EXISTS position_id   BIGINT REFERENCES hr.positions(id);
    -- Cargo del empleado al momento de unirse al proyecto (snapshot).

COMMENT ON COLUMN projects.project_members.department_id IS
    'Departamento HR del miembro al incorporarse al proyecto. Auto-rellenado desde hr.employees.department_id.';
COMMENT ON COLUMN projects.project_members.position_id IS
    'Cargo/puesto HR del miembro al incorporarse. Auto-rellenado desde hr.employees.position_id.';

-- ============================================================
-- 2. Trigger: auto-rellenar department_id y position_id
--    al insertar un miembro (si no se proveen explícitamente)
-- ============================================================
CREATE OR REPLACE FUNCTION projects.fill_member_hr_data()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.department_id IS NULL OR NEW.position_id IS NULL THEN
        SELECT
            COALESCE(NEW.department_id, e.department_id),
            COALESCE(NEW.position_id,   e.position_id)
        INTO NEW.department_id, NEW.position_id
        FROM hr.employees e
        WHERE e.id = NEW.employee_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_project_member_hr_data
    BEFORE INSERT ON projects.project_members
    FOR EACH ROW EXECUTE FUNCTION projects.fill_member_hr_data();

-- ============================================================
-- 3. VIEW: projects.employee_project_view
--    Perspectiva RR.HH.: qué proyectos tiene cada empleado,
--    cuántas horas lleva, tareas asignadas y mora actual.
-- ============================================================
CREATE OR REPLACE VIEW projects.employee_project_view AS
SELECT
    e.id                                                    AS employee_id,
    e.company_id,
    per.first_name || ' ' || per.last_name                  AS employee_name,
    d.name                                                  AS department_name,
    pos.title                                               AS position_title,

    -- Proyecto
    p.id                                                    AS project_id,
    p.code                                                  AS project_code,
    p.name                                                  AS project_name,
    p.status                                                AS project_status,
    p.is_internal,
    p.planned_end                                           AS project_deadline,

    -- Rol del miembro en el proyecto
    pm.role                                                 AS project_role,
    pm.allocated_hours,
    pm.hourly_rate,
    pm.start_date                                           AS member_since,

    -- Horas registradas por este empleado en este proyecto
    COALESCE(te_agg.hours_logged, 0)                        AS hours_logged,
    COALESCE(te_agg.billable_hours, 0)                      AS billable_hours_logged,

    -- Horas restantes (allocated - logged), puede ser negativo (sobrecarga)
    COALESCE(pm.allocated_hours, 0) - COALESCE(te_agg.hours_logged, 0)
                                                            AS hours_remaining,

    -- Tareas asignadas en este proyecto
    COALESCE(task_agg.total_tasks, 0)                       AS tasks_assigned,
    COALESCE(task_agg.done_tasks, 0)                        AS tasks_done,
    COALESCE(task_agg.in_progress_tasks, 0)                 AS tasks_in_progress,
    COALESCE(task_agg.overdue_tasks, 0)                     AS tasks_overdue,

    -- Puntualidad en este proyecto
    COALESCE(task_agg.on_time_tasks, 0)                     AS tasks_delivered_on_time,
    ROUND(
        COALESCE(task_agg.on_time_tasks, 0)::NUMERIC /
        NULLIF(COALESCE(task_agg.done_with_dates, 0), 0) * 100
    , 2)                                                    AS on_time_pct

FROM hr.employees e
INNER JOIN hr.persons per
    ON per.id = e.person_id
LEFT JOIN hr.departments d
    ON d.id = e.department_id
LEFT JOIN hr.positions pos
    ON pos.id = e.position_id
INNER JOIN projects.project_members pm
    ON pm.employee_id = e.id AND pm.is_active = TRUE
INNER JOIN projects.projects p
    ON p.id = pm.project_id AND p.status NOT IN ('cancelled', 'completed')

-- Horas registradas en este proyecto
LEFT JOIN (
    SELECT employee_id, project_id,
           SUM(hours)                                           AS hours_logged,
           SUM(CASE WHEN is_billable THEN hours ELSE 0 END)    AS billable_hours
    FROM projects.time_entries
    GROUP BY employee_id, project_id
) te_agg
    ON te_agg.employee_id = e.id AND te_agg.project_id = p.id

-- Tareas asignadas en este proyecto
LEFT JOIN (
    SELECT
        assigned_to_id,
        project_id,
        COUNT(*)                                                AS total_tasks,
        COUNT(*) FILTER (WHERE status = 'done')                 AS done_tasks,
        COUNT(*) FILTER (WHERE status = 'in_progress')          AS in_progress_tasks,
        COUNT(*) FILTER (
            WHERE status NOT IN ('done','cancelled')
              AND planned_end IS NOT NULL
              AND planned_end < CURRENT_DATE
        )                                                       AS overdue_tasks,
        COUNT(*) FILTER (
            WHERE actual_end IS NOT NULL
              AND planned_end IS NOT NULL
              AND actual_end <= planned_end
        )                                                       AS on_time_tasks,
        COUNT(*) FILTER (
            WHERE actual_end IS NOT NULL AND planned_end IS NOT NULL
        )                                                       AS done_with_dates
    FROM projects.project_tasks
    WHERE status != 'cancelled'
    GROUP BY assigned_to_id, project_id
) task_agg
    ON task_agg.assigned_to_id = e.id AND task_agg.project_id = p.id

ORDER BY e.id, p.planned_end NULLS LAST;

COMMENT ON VIEW projects.employee_project_view IS
'Vista HR: por empleado activo, todos sus proyectos en curso con horas asignadas vs registradas, tareas por estado y puntualidad de entregas.';

-- ============================================================
-- 4. VIEW: projects.department_project_load_view
--    Por departamento: proyectos activos, miembros asignados,
--    horas totales comprometidas y tareas en mora.
-- ============================================================
CREATE OR REPLACE VIEW projects.department_project_load_view AS
SELECT
    d.id                                                    AS department_id,
    d.company_id,
    d.name                                                  AS department_name,

    -- Proyectos activos en los que participa el departamento
    COUNT(DISTINCT p.id)                                    AS active_projects,
    COUNT(DISTINCT p.id) FILTER (WHERE p.is_internal)       AS internal_projects,
    COUNT(DISTINCT p.id) FILTER (WHERE NOT p.is_internal)   AS client_projects,

    -- Miembros del departamento en proyectos activos
    COUNT(DISTINCT pm.employee_id)                          AS members_in_projects,

    -- Horas comprometidas (allocated) en proyectos activos
    COALESCE(SUM(pm.allocated_hours), 0)                    AS total_allocated_hours,

    -- Horas ya registradas por miembros del departamento
    COALESCE(SUM(te_agg.hours_logged), 0)                   AS total_hours_logged,

    -- Tareas asignadas a miembros del departamento
    COALESCE(SUM(task_agg.total_tasks), 0)                  AS total_tasks_assigned,
    COALESCE(SUM(task_agg.overdue_tasks), 0)                AS total_tasks_overdue,

    -- Proyectos con hitos vencidos (señal de alerta)
    COUNT(DISTINCT ms_agg.project_id) FILTER (
        WHERE ms_agg.has_overdue_milestone
    )                                                       AS projects_with_overdue_milestones

FROM hr.departments d

-- Miembros del departamento asignados a proyectos activos
INNER JOIN projects.project_members pm
    ON pm.department_id = d.id AND pm.is_active = TRUE
INNER JOIN projects.projects p
    ON p.id = pm.project_id AND p.status = 'active'

-- Horas registradas por empleados de este departamento
LEFT JOIN (
    SELECT project_id, employee_id, SUM(hours) AS hours_logged
    FROM projects.time_entries
    GROUP BY project_id, employee_id
) te_agg
    ON te_agg.project_id = p.id AND te_agg.employee_id = pm.employee_id

-- Tareas por empleado y proyecto
LEFT JOIN (
    SELECT
        project_id,
        assigned_to_id,
        COUNT(*) FILTER (WHERE status != 'cancelled') AS total_tasks,
        COUNT(*) FILTER (
            WHERE status NOT IN ('done','cancelled')
              AND planned_end IS NOT NULL
              AND planned_end < CURRENT_DATE
        ) AS overdue_tasks
    FROM projects.project_tasks
    GROUP BY project_id, assigned_to_id
) task_agg
    ON task_agg.project_id = p.id AND task_agg.assigned_to_id = pm.employee_id

-- Hitos vencidos por proyecto
LEFT JOIN (
    SELECT project_id,
           bool_or(NOT is_reached AND due_date < CURRENT_DATE) AS has_overdue_milestone
    FROM projects.project_milestones
    GROUP BY project_id
) ms_agg ON ms_agg.project_id = p.id

GROUP BY d.id, d.company_id, d.name
ORDER BY total_tasks_overdue DESC, active_projects DESC;

COMMENT ON VIEW projects.department_project_load_view IS
'Vista HR: carga de proyectos por departamento — proyectos activos, miembros asignados, horas comprometidas vs registradas y tareas en mora.';

-- ============================================================
-- 5. VIEW: projects.employee_task_load_view
--    Carga de trabajo actual por empleado (tareas activas,
--    horas estimadas restantes, riesgo de sobrecarga).
--    Útil para el jefe de equipo al asignar nuevas tareas.
-- ============================================================
CREATE OR REPLACE VIEW projects.employee_task_load_view AS
SELECT
    e.id                                                    AS employee_id,
    e.company_id,
    per.first_name || ' ' || per.last_name                  AS employee_name,
    d.name                                                  AS department_name,
    pos.title                                               AS position_title,

    -- Tareas activas asignadas hoy
    COUNT(pt.id)                                            AS active_tasks,
    COUNT(pt.id) FILTER (WHERE pt.priority = 'critical')   AS critical_tasks,
    COUNT(pt.id) FILTER (WHERE pt.priority = 'high')       AS high_priority_tasks,

    -- Tareas vencidas (en mora)
    COUNT(pt.id) FILTER (
        WHERE pt.planned_end IS NOT NULL AND pt.planned_end < CURRENT_DATE
    )                                                       AS overdue_tasks,

    -- Horas estimadas restantes (todas las tareas activas)
    COALESCE(SUM(
        GREATEST(
            COALESCE(pt.estimated_hours, 0) -
            COALESCE(te_agg.hours_logged, 0),
            0
        )
    ), 0)                                                   AS estimated_hours_remaining,

    -- Proyectos distintos en los que trabaja hoy
    COUNT(DISTINCT pt.project_id)                           AS projects_count,

    -- Próxima fecha límite de tarea
    MIN(pt.planned_end) FILTER (
        WHERE pt.planned_end IS NOT NULL
          AND pt.planned_end >= CURRENT_DATE
    )                                                       AS next_deadline,

    -- Señal de sobrecarga: TRUE si tiene >3 tareas activas o >40h restantes
    CASE
        WHEN COUNT(pt.id) > 3
          OR COALESCE(SUM(
                GREATEST(
                    COALESCE(pt.estimated_hours, 0) - COALESCE(te_agg.hours_logged, 0),
                    0
                )
             ), 0) > 40
        THEN TRUE
        ELSE FALSE
    END                                                     AS overload_risk

FROM hr.employees e
INNER JOIN hr.persons per
    ON per.id = e.person_id
LEFT JOIN hr.departments d
    ON d.id = e.department_id
LEFT JOIN hr.positions pos
    ON pos.id = e.position_id

-- Tareas activas asignadas a este empleado
LEFT JOIN projects.project_tasks pt
    ON pt.assigned_to_id = e.id
   AND pt.status IN ('todo','in_progress','review')

-- Horas ya registradas por tarea
LEFT JOIN (
    SELECT task_id, SUM(hours) AS hours_logged
    FROM projects.time_entries
    WHERE task_id IS NOT NULL
    GROUP BY task_id
) te_agg ON te_agg.task_id = pt.id

WHERE e.is_active = TRUE
GROUP BY
    e.id, e.company_id,
    per.first_name, per.last_name,
    d.name, pos.title
ORDER BY overload_risk DESC, overdue_tasks DESC, active_tasks DESC;

COMMENT ON VIEW projects.employee_task_load_view IS
'Carga de trabajo actual por empleado: tareas activas, horas estimadas restantes, riesgo de sobrecarga (>3 tareas o >40h pendientes). Útil al asignar nuevas tareas.';
