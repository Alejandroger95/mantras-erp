-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.code_assignments
-- Descripción: Historial de asignación de códigos/claves a empleados.
--              Soporta rotación periódica: al vencer o rotarse,
--              se cierra el registro (end_date) y se crea uno nuevo.
--              Ej: empleado X tuvo "pindi" ene-mar, luego "t7" abr-jun.
-- ============================================================

CREATE TABLE hr.code_assignments (
    id                      BIGSERIAL       PRIMARY KEY,
    access_code_id          BIGINT          NOT NULL REFERENCES hr.access_codes(id) ON DELETE RESTRICT,
    employee_id             BIGINT          NOT NULL REFERENCES hr.employees(id) ON DELETE RESTRICT,

    -- Vigencia
    start_date              DATE            NOT NULL DEFAULT CURRENT_DATE,
    end_date                DATE,                       -- NULL = asignación actualmente vigente
    next_rotation_date      DATE,                       -- Calculada según la política del sistema

    -- Motivo del cambio (para registros de rotación)
    reason                  VARCHAR(50),
    -- initial_assignment | scheduled_rotation | manual_rotation | employee_termination | other
    notes                   TEXT,

    recorded_by             BIGINT          REFERENCES hr.employees(id),

    is_active               BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_code_assign_code     ON hr.code_assignments (access_code_id);
CREATE INDEX idx_code_assign_employee ON hr.code_assignments (employee_id);
CREATE INDEX idx_code_assign_active   ON hr.code_assignments (employee_id) WHERE end_date IS NULL;

CREATE TRIGGER trg_code_assignments_updated_at
    BEFORE UPDATE ON hr.code_assignments
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.code_assignments                     IS 'Historial de asignación de códigos. end_date NULL = asignación vigente.';
COMMENT ON COLUMN hr.code_assignments.next_rotation_date  IS 'Fecha calculada para la siguiente rotación según la política del sistema.';
COMMENT ON COLUMN hr.code_assignments.reason              IS 'initial_assignment | scheduled_rotation | manual_rotation | employee_termination | other';
