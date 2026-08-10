-- ============================================================
-- MIGRACIÓN: Jerarquía de empleados (jefe directo + historial)
-- ============================================================
-- hr.employees         → añade reports_to (jefe actual, conveniencia)
-- hr.employee_reporting_history → historial completo de cambios de jefe
-- ============================================================

BEGIN;

-- ── 1. Columna de conveniencia en hr.employees ────────────────────────────────
--    Siempre refleja el jefe vigente. Para queries rápidas del día a día.

ALTER TABLE hr.employees
  ADD COLUMN IF NOT EXISTS reports_to BIGINT REFERENCES hr.employees(id);

COMMENT ON COLUMN hr.employees.reports_to
  IS 'Jefe directo actual (conveniencia). Historial completo en hr.employee_reporting_history.';

CREATE INDEX IF NOT EXISTS idx_employees_reports_to
  ON hr.employees (reports_to);

-- ── 2. Tabla de historial de jerarquía ───────────────────────────────────────

CREATE TABLE IF NOT EXISTS hr.employee_reporting_history (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    employee_id         BIGINT          NOT NULL REFERENCES hr.employees(id) ON DELETE RESTRICT,
    reports_to          BIGINT          REFERENCES hr.employees(id),
    -- NULL = sin jefe directo (ej: director general)

    effective_from      DATE            NOT NULL DEFAULT CURRENT_DATE,
    effective_to        DATE,
    -- NULL = vigente actualmente

    reason              VARCHAR(200),
    -- 'contratación', 'reorganización', 'cambio de área', 'baja del jefe', etc.

    created_by          BIGINT          REFERENCES hr.employees(id),
    -- Empleado (admin/manager) que registró el cambio

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    -- Solo puede haber un registro vigente por empleado a la vez
    CONSTRAINT chk_reporting_dates CHECK (
        effective_to IS NULL OR effective_to >= effective_from
    )
);

-- Trigger para updated_at
CREATE TRIGGER trg_employee_reporting_history_updated_at
    BEFORE UPDATE ON hr.employee_reporting_history
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

-- Índices
CREATE INDEX IF NOT EXISTS idx_emp_reporting_employee
  ON hr.employee_reporting_history (employee_id);

CREATE INDEX IF NOT EXISTS idx_emp_reporting_reports_to
  ON hr.employee_reporting_history (reports_to);

CREATE INDEX IF NOT EXISTS idx_emp_reporting_dates
  ON hr.employee_reporting_history (employee_id, effective_from, effective_to);

-- Solo un registro vigente (effective_to IS NULL) por empleado
CREATE UNIQUE INDEX IF NOT EXISTS idx_emp_reporting_current
  ON hr.employee_reporting_history (employee_id)
  WHERE effective_to IS NULL;

-- Comentarios
COMMENT ON TABLE  hr.employee_reporting_history IS 'Historial de jerarquía: quién reportaba a quién y en qué período.';
COMMENT ON COLUMN hr.employee_reporting_history.employee_id    IS 'El subordinado';
COMMENT ON COLUMN hr.employee_reporting_history.reports_to     IS 'El jefe directo. NULL = sin jefe (top nivel)';
COMMENT ON COLUMN hr.employee_reporting_history.effective_from IS 'Fecha desde la que aplica esta relación';
COMMENT ON COLUMN hr.employee_reporting_history.effective_to   IS 'Fecha hasta la que aplica. NULL = vigente hoy';
COMMENT ON COLUMN hr.employee_reporting_history.reason         IS 'Motivo del cambio de jefe';
COMMENT ON COLUMN hr.employee_reporting_history.created_by     IS 'Admin o manager que registró el cambio';

-- ── 3. Función helper: cambiar jefe de un empleado ───────────────────────────
--    Cierra el registro vigente y abre uno nuevo. Actualiza hr.employees.reports_to.
--    Uso: SELECT hr.set_employee_manager(employee_id, new_manager_id, 'reorganización', created_by_id);

CREATE OR REPLACE FUNCTION hr.set_employee_manager(
    p_employee_id   BIGINT,
    p_reports_to    BIGINT,         -- nuevo jefe (NULL = sin jefe)
    p_reason        VARCHAR(200)    DEFAULT NULL,
    p_created_by    BIGINT          DEFAULT NULL,
    p_effective     DATE            DEFAULT CURRENT_DATE
)
RETURNS hr.employee_reporting_history AS $$
DECLARE
    v_company_id BIGINT;
    v_new_row    hr.employee_reporting_history;
BEGIN
    SELECT company_id INTO v_company_id FROM hr.employees WHERE id = p_employee_id;

    -- Cerrar registro vigente si existe
    UPDATE hr.employee_reporting_history
       SET effective_to = p_effective - INTERVAL '1 day'
     WHERE employee_id  = p_employee_id
       AND effective_to IS NULL;

    -- Insertar nuevo registro
    INSERT INTO hr.employee_reporting_history
        (company_id, employee_id, reports_to, effective_from, reason, created_by)
    VALUES
        (v_company_id, p_employee_id, p_reports_to, p_effective, p_reason, p_created_by)
    RETURNING * INTO v_new_row;

    -- Actualizar conveniencia en hr.employees
    UPDATE hr.employees
       SET reports_to = p_reports_to
     WHERE id = p_employee_id;

    RETURN v_new_row;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION hr.set_employee_manager IS
  'Cambia el jefe de un empleado: cierra el registro vigente en el historial, abre uno nuevo y actualiza hr.employees.reports_to.';

COMMIT;
