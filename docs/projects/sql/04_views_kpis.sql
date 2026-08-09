-- ============================================================
-- mantrasdb | Módulo Projects
-- Archivo: 04_views_kpis.sql
-- Descripción: Vistas analíticas y KPIs del módulo Projects.
--
-- Vistas:
--   1. project_dashboard_view   — estado integral por proyecto
--   2. team_utilization_view    — utilización del equipo por mes
--   3. billing_pipeline_view    — lo que está listo para facturar
-- ============================================================

-- ============================================================
-- 1. PROJECT DASHBOARD VIEW
-- Estado integral de cada proyecto con métricas clave.
-- ============================================================
CREATE OR REPLACE VIEW projects.project_dashboard_view AS
SELECT
    p.id                                                AS project_id,
    p.company_id,
    p.code                                              AS project_code,
    p.name                                              AS project_name,
    p.status,
    p.billing_type,
    p.priority,
    p.is_internal,
    p.currency,

    -- Cliente
    p.customer_id,
    c.trade_name                                        AS customer_name,

    -- Gerente de proyecto
    p.project_manager_id,
    per.first_name || ' ' || per.last_name              AS project_manager_name,

    -- Progreso
    p.progress_pct,

    -- Fechas
    p.planned_start,
    p.planned_end,
    p.actual_start,
    p.actual_end,
    CASE
        WHEN p.planned_end IS NOT NULL AND p.status NOT IN ('completed','cancelled')
        THEN p.planned_end - CURRENT_DATE
        ELSE NULL
    END                                                 AS days_remaining,

    -- Presupuesto de horas
    p.budget_hours,
    COALESCE(te_agg.total_hours, 0)                     AS total_hours_logged,
    CASE
        WHEN p.budget_hours > 0
        THEN ROUND(COALESCE(te_agg.total_hours, 0) / p.budget_hours * 100, 2)
        ELSE NULL
    END                                                 AS hours_consumed_pct,

    -- Presupuesto económico
    p.budget_amount,
    p.actual_cost,
    CASE
        WHEN p.budget_amount > 0
        THEN ROUND(p.actual_cost / p.budget_amount * 100, 2)
        ELSE NULL
    END                                                 AS budget_consumed_pct,

    -- Horas facturables y monto facturado pendiente
    COALESCE(te_agg.billable_hours, 0)                  AS billable_hours_logged,
    COALESCE(te_agg.total_billable_amount, 0)           AS total_billable_amount,

    -- Riesgos
    COALESCE(risk_agg.open_risks, 0)                    AS open_risks,
    COALESCE(risk_agg.critical_risks, 0)                AS critical_risks,

    -- Hitos
    COALESCE(ms_agg.total_milestones, 0)                AS total_milestones,
    COALESCE(ms_agg.open_milestones, 0)                 AS open_milestones,
    COALESCE(ms_agg.overdue_milestones, 0)              AS overdue_milestones,
    COALESCE(ms_agg.pending_billing_amount, 0)          AS pending_billing_amount,

    -- Fases
    COALESCE(phase_agg.total_phases, 0)                 AS total_phases,
    COALESCE(phase_agg.completed_phases, 0)             AS completed_phases,

    -- Equipo
    COALESCE(team_agg.team_size, 0)                     AS team_size,

    p.tags,
    p.created_at,
    p.updated_at

FROM projects.projects p

-- Cliente (opcional, proyectos internos no tienen cliente)
LEFT JOIN sales.customers c
    ON c.id = p.customer_id

-- Gerente de proyecto: employee → person
LEFT JOIN hr.employees mgr
    ON mgr.id = p.project_manager_id
LEFT JOIN hr.persons per
    ON per.id = mgr.person_id

-- Agregado de horas (time_entries)
LEFT JOIN (
    SELECT
        project_id,
        SUM(hours)                              AS total_hours,
        SUM(CASE WHEN is_billable THEN hours ELSE 0 END) AS billable_hours,
        SUM(billable_amount)                    AS total_billable_amount
    FROM projects.time_entries
    GROUP BY project_id
) te_agg ON te_agg.project_id = p.id

-- Agregado de riesgos
LEFT JOIN (
    SELECT
        project_id,
        COUNT(*) FILTER (WHERE status = 'open')                         AS open_risks,
        COUNT(*) FILTER (WHERE status = 'open' AND risk_level = 'critical') AS critical_risks
    FROM projects.project_risks
    GROUP BY project_id
) risk_agg ON risk_agg.project_id = p.id

-- Agregado de hitos
LEFT JOIN (
    SELECT
        project_id,
        COUNT(*)                                    AS total_milestones,
        COUNT(*) FILTER (WHERE NOT is_reached)      AS open_milestones,
        COUNT(*) FILTER (
            WHERE NOT is_reached AND due_date < CURRENT_DATE
        )                                           AS overdue_milestones,
        COALESCE(SUM(amount) FILTER (
            WHERE is_reached
              AND invoice_id IS NULL
              AND milestone_type = 'billing'
        ), 0)                                       AS pending_billing_amount
    FROM projects.project_milestones
    GROUP BY project_id
) ms_agg ON ms_agg.project_id = p.id

-- Agregado de fases
LEFT JOIN (
    SELECT
        project_id,
        COUNT(*)                                            AS total_phases,
        COUNT(*) FILTER (WHERE status = 'completed')       AS completed_phases
    FROM projects.project_phases
    GROUP BY project_id
) phase_agg ON phase_agg.project_id = p.id

-- Tamaño del equipo
LEFT JOIN (
    SELECT
        project_id,
        COUNT(*) FILTER (WHERE is_active)               AS team_size
    FROM projects.project_members
    GROUP BY project_id
) team_agg ON team_agg.project_id = p.id;

COMMENT ON VIEW projects.project_dashboard_view IS
'Vista integral por proyecto: estado, progreso, horas, presupuesto, riesgos e hitos. Una fila por proyecto.';

-- ============================================================
-- 2. TEAM UTILIZATION VIEW
-- Utilización del equipo por empleado, proyecto y mes.
-- ============================================================
CREATE OR REPLACE VIEW projects.team_utilization_view AS
SELECT
    DATE_TRUNC('month', te.entry_date)::DATE            AS month,
    te.employee_id,
    per.first_name || ' ' || per.last_name              AS employee_name,
    te.project_id,
    p.code                                              AS project_code,
    p.name                                              AS project_name,
    te.company_id,

    -- Rol del miembro en el proyecto
    pm.role,

    -- Horas
    SUM(te.hours)                                       AS total_hours,
    SUM(CASE WHEN te.is_billable THEN te.hours ELSE 0 END) AS billable_hours,
    SUM(CASE WHEN NOT te.is_billable THEN te.hours ELSE 0 END) AS non_billable_hours,

    -- % de facturabilidad
    CASE
        WHEN SUM(te.hours) > 0
        THEN ROUND(
            SUM(CASE WHEN te.is_billable THEN te.hours ELSE 0 END)
            / SUM(te.hours) * 100,
            2
        )
        ELSE 0
    END                                                 AS billable_pct,

    -- Monto facturable del período
    SUM(te.billable_amount)                             AS total_billable_amount

FROM projects.time_entries te

-- Datos del empleado
INNER JOIN hr.employees e
    ON e.id = te.employee_id
INNER JOIN hr.persons per
    ON per.id = e.person_id

-- Datos del proyecto
INNER JOIN projects.projects p
    ON p.id = te.project_id

-- Rol en el proyecto (LEFT: puede haber entradas sin miembro registrado)
LEFT JOIN projects.project_members pm
    ON pm.project_id = te.project_id
   AND pm.employee_id = te.employee_id

GROUP BY
    DATE_TRUNC('month', te.entry_date),
    te.employee_id,
    per.first_name,
    per.last_name,
    te.project_id,
    p.code,
    p.name,
    te.company_id,
    pm.role;

COMMENT ON VIEW projects.team_utilization_view IS
'Utilización del equipo agrupada por empleado × proyecto × mes. Muestra horas totales, facturables y porcentaje de utilización.';

-- ============================================================
-- 3. BILLING PIPELINE VIEW
-- Lo que está listo o pendiente de facturar.
-- Dos fuentes: hitos alcanzados sin factura y horas T&M sin facturar.
-- ============================================================
CREATE OR REPLACE VIEW projects.billing_pipeline_view AS

-- FUENTE 1: Hitos de facturación alcanzados pero aún no facturados
SELECT
    p.id                            AS project_id,
    p.code                          AS project_code,
    p.name                          AS project_name,
    p.customer_id,
    c.trade_name                    AS customer_name,
    p.billing_type,
    p.currency,
    'milestone'::TEXT               AS billing_source,
    ms.id                           AS source_id,
    ms.name                         AS source_description,
    ms.due_date                     AS reference_date,
    COALESCE(ms.amount, 0)          AS amount_pending,
    ms.reached_at                   AS event_date

FROM projects.project_milestones ms
INNER JOIN projects.projects p
    ON p.id = ms.project_id
LEFT JOIN sales.customers c
    ON c.id = p.customer_id
WHERE ms.is_reached
  AND ms.invoice_id IS NULL
  AND ms.milestone_type = 'billing'
  AND COALESCE(ms.amount, 0) > 0

UNION ALL

-- FUENTE 2: Horas T&M facturables sin línea de factura
SELECT
    p.id                            AS project_id,
    p.code                          AS project_code,
    p.name                          AS project_name,
    p.customer_id,
    c.trade_name                    AS customer_name,
    p.billing_type,
    p.currency,
    'time_and_materials'::TEXT      AS billing_source,
    p.id                            AS source_id,
    'Horas T&M sin facturar'        AS source_description,
    MAX(te.entry_date)              AS reference_date,
    SUM(te.billable_amount)         AS amount_pending,
    MAX(te.created_at)              AS event_date

FROM projects.time_entries te
INNER JOIN projects.projects p
    ON p.id = te.project_id
LEFT JOIN sales.customers c
    ON c.id = p.customer_id
WHERE te.is_billable
  AND te.invoice_line_id IS NULL
  AND te.billable_amount > 0
  AND p.billing_type = 'time_and_materials'
  AND p.status NOT IN ('cancelled','draft')

GROUP BY
    p.id,
    p.code,
    p.name,
    p.customer_id,
    c.trade_name,
    p.billing_type,
    p.currency

HAVING SUM(te.billable_amount) > 0;

COMMENT ON VIEW projects.billing_pipeline_view IS
'Pipeline de facturación: hitos alcanzados sin facturar (billing milestones) y horas T&M pendientes de factura. Una fila por fuente de facturación.';

-- ============================================================
-- 4. TASK PERFORMANCE VIEW
-- Por tarea: responsable, planificado vs real, mora y puntualidad.
-- ============================================================
CREATE OR REPLACE VIEW projects.task_performance_view AS
SELECT
    pt.id                                               AS task_id,
    pt.company_id,
    pt.project_id,
    p.code                                              AS project_code,
    p.name                                              AS project_name,
    p.is_internal,
    pt.phase_id,
    ph.name                                             AS phase_name,
    pt.task_number,
    pt.name                                             AS task_name,
    pt.status,
    pt.priority,
    pt.story_points,

    -- Responsable
    pt.assigned_to_id,
    per.first_name || ' ' || per.last_name             AS assigned_to_name,

    -- Fechas planificadas vs reales
    pt.planned_start,
    pt.planned_end,
    pt.actual_start,
    pt.actual_end,

    -- ¿Está en mora? (tarea activa con planned_end vencido)
    CASE
        WHEN pt.status NOT IN ('done', 'cancelled')
             AND pt.planned_end IS NOT NULL
             AND pt.planned_end < CURRENT_DATE
        THEN TRUE
        ELSE FALSE
    END                                                 AS is_overdue,

    -- Días de diferencia (positivo = tarde, negativo = anticipado)
    -- Si ya se entregó: real - planificado
    -- Si aún no se entrega y está vencido: días transcurridos desde vencimiento
    CASE
        WHEN pt.actual_end IS NOT NULL AND pt.planned_end IS NOT NULL
        THEN (pt.actual_end - pt.planned_end)
        WHEN pt.status NOT IN ('done', 'cancelled')
             AND pt.planned_end IS NOT NULL
             AND pt.planned_end < CURRENT_DATE
        THEN (CURRENT_DATE - pt.planned_end)
        ELSE NULL
    END                                                 AS delay_days,

    -- ¿Entregó a tiempo? TRUE/FALSE/NULL(sin datos suficientes)
    CASE
        WHEN pt.actual_end IS NOT NULL AND pt.planned_end IS NOT NULL
        THEN pt.actual_end <= pt.planned_end
        WHEN pt.status NOT IN ('done', 'cancelled')
             AND pt.planned_end IS NOT NULL
             AND pt.planned_end >= CURRENT_DATE
        THEN TRUE   -- aún en plazo, cuenta como "a tiempo" por ahora
        WHEN pt.status = 'done'
        THEN NULL   -- completada pero sin fecha real registrada
        ELSE FALSE
    END                                                 AS delivered_on_time,

    -- Horas estimadas vs reales
    pt.estimated_hours,
    COALESCE(te_agg.actual_hours, 0)                   AS actual_hours_logged,
    CASE
        WHEN pt.estimated_hours > 0
        THEN ROUND(COALESCE(te_agg.actual_hours, 0) / pt.estimated_hours * 100, 2)
        ELSE NULL
    END                                                 AS hours_consumed_pct,

    pt.created_at

FROM projects.project_tasks pt
INNER JOIN projects.projects p
    ON p.id = pt.project_id
LEFT JOIN projects.project_phases ph
    ON ph.id = pt.phase_id
LEFT JOIN hr.employees e
    ON e.id = pt.assigned_to_id
LEFT JOIN hr.persons per
    ON per.id = e.person_id
LEFT JOIN (
    SELECT task_id, SUM(hours) AS actual_hours
    FROM projects.time_entries
    WHERE task_id IS NOT NULL
    GROUP BY task_id
) te_agg ON te_agg.task_id = pt.id
WHERE pt.status != 'cancelled'
ORDER BY
    -- primero las tareas vencidas
    CASE
        WHEN pt.status NOT IN ('done','cancelled')
             AND pt.planned_end IS NOT NULL
             AND pt.planned_end < CURRENT_DATE
        THEN 0 ELSE 1
    END,
    pt.planned_end NULLS LAST;

COMMENT ON VIEW projects.task_performance_view IS
'Por tarea: responsable asignado, fechas planificadas vs reales, mora activa (is_overdue), días de retraso o adelanto (delay_days), entrega a tiempo (delivered_on_time) y horas consumidas vs estimadas.';

-- ============================================================
-- 5. RESPONSIBLE PERFORMANCE VIEW
-- KPIs de puntualidad y entrega por empleado × proyecto.
-- Aplica a proyectos internos (is_internal=TRUE) y externos.
-- ============================================================
CREATE OR REPLACE VIEW projects.responsible_performance_view AS
SELECT
    pt.assigned_to_id,
    per.first_name || ' ' || per.last_name             AS employee_name,
    pt.company_id,
    p.id                                               AS project_id,
    p.code                                             AS project_code,
    p.name                                             AS project_name,
    p.is_internal,

    -- Tareas asignadas a esta persona en este proyecto
    COUNT(pt.id)                                       AS total_tasks,
    COUNT(pt.id) FILTER (WHERE pt.status = 'done')    AS completed_tasks,
    COUNT(pt.id) FILTER (
        WHERE pt.status IN ('todo','in_progress','review')
    )                                                  AS pending_tasks,

    -- Puntualidad en entregas ya completadas
    COUNT(pt.id) FILTER (
        WHERE pt.actual_end IS NOT NULL
          AND pt.planned_end IS NOT NULL
          AND pt.actual_end <= pt.planned_end
    )                                                  AS tasks_on_time,
    COUNT(pt.id) FILTER (
        WHERE pt.actual_end IS NOT NULL
          AND pt.planned_end IS NOT NULL
          AND pt.actual_end > pt.planned_end
    )                                                  AS tasks_late,

    -- Tareas activas actualmente vencidas
    COUNT(pt.id) FILTER (
        WHERE pt.status NOT IN ('done','cancelled')
          AND pt.planned_end IS NOT NULL
          AND pt.planned_end < CURRENT_DATE
    )                                                  AS tasks_currently_overdue,

    -- % de entrega a tiempo (sobre las que tienen fecha planificada y real)
    ROUND(
        COUNT(pt.id) FILTER (
            WHERE pt.actual_end IS NOT NULL
              AND pt.planned_end IS NOT NULL
              AND pt.actual_end <= pt.planned_end
        )::NUMERIC /
        NULLIF(COUNT(pt.id) FILTER (
            WHERE pt.actual_end IS NOT NULL
              AND pt.planned_end IS NOT NULL
        ), 0) * 100
    , 2)                                               AS on_time_delivery_pct,

    -- Promedio de días de retraso en tareas entregadas tarde
    ROUND(AVG(
        pt.actual_end - pt.planned_end
    ) FILTER (
        WHERE pt.actual_end IS NOT NULL
          AND pt.planned_end IS NOT NULL
          AND pt.actual_end > pt.planned_end
    ), 1)                                              AS avg_delay_days,

    -- Horas registradas en este proyecto
    ROUND(COALESCE(SUM(te_agg.actual_hours), 0), 2)   AS total_hours_logged

FROM projects.project_tasks pt
INNER JOIN projects.projects p
    ON p.id = pt.project_id
INNER JOIN hr.employees e
    ON e.id = pt.assigned_to_id
INNER JOIN hr.persons per
    ON per.id = e.person_id
LEFT JOIN (
    SELECT task_id, SUM(hours) AS actual_hours
    FROM projects.time_entries
    WHERE task_id IS NOT NULL
    GROUP BY task_id
) te_agg ON te_agg.task_id = pt.id
WHERE pt.assigned_to_id IS NOT NULL
  AND pt.status != 'cancelled'
GROUP BY
    pt.assigned_to_id,
    per.first_name, per.last_name,
    pt.company_id,
    p.id, p.code, p.name, p.is_internal
ORDER BY
    tasks_currently_overdue DESC,
    on_time_delivery_pct ASC NULLS LAST;

COMMENT ON VIEW projects.responsible_performance_view IS
'KPIs de puntualidad por empleado × proyecto: tareas completadas, en plazo, tarde, actualmente vencidas y porcentaje de entrega a tiempo. Aplica a proyectos internos y externos.';
