-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.attendance
-- Descripción: Registro de asistencia diaria por empleado.
--              Guarda entrada, salida y calcula las horas trabajadas.
-- ============================================================

CREATE TABLE hr.attendance (
    id              BIGSERIAL       PRIMARY KEY,
    employee_id     BIGINT          NOT NULL REFERENCES hr.employees(id) ON DELETE RESTRICT,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    work_date       DATE            NOT NULL,
    check_in        TIMESTAMPTZ,            -- Hora de entrada
    check_out       TIMESTAMPTZ,            -- Hora de salida (NULL = aún no registra salida)

    -- Horas calculadas
    worked_hours    NUMERIC(5,2),           -- Horas efectivamente trabajadas
    overtime_hours  NUMERIC(5,2) DEFAULT 0, -- Horas extra

    -- Estado del día
    status          VARCHAR(20)     NOT NULL DEFAULT 'present',
    -- present | absent | holiday | remote | on_leave | half_day

    source          VARCHAR(20)     DEFAULT 'manual',
    -- manual | biometric | app | system

    notes           TEXT,

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_attendance_employee_date ON hr.attendance (employee_id, work_date);
CREATE INDEX idx_attendance_company              ON hr.attendance (company_id);
CREATE INDEX idx_attendance_date                 ON hr.attendance (work_date);

CREATE TRIGGER trg_attendance_updated_at
    BEFORE UPDATE ON hr.attendance
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.attendance             IS 'Registro diario de asistencia por empleado.';
COMMENT ON COLUMN hr.attendance.status      IS 'present | absent | holiday | remote | on_leave | half_day';
COMMENT ON COLUMN hr.attendance.source      IS 'Origen del registro: manual | biometric | app | system';
COMMENT ON COLUMN hr.attendance.worked_hours IS 'Calculado: diferencia entre check_out y check_in en horas.';
