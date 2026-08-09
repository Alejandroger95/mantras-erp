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
