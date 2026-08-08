-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.absences
-- Descripción: Solicitudes y registros de ausencias por empleado.
-- ============================================================

CREATE TABLE hr.absences (
    id                  BIGSERIAL       PRIMARY KEY,
    employee_id         BIGINT          NOT NULL REFERENCES hr.employees(id) ON DELETE RESTRICT,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    absence_type_id     BIGINT          NOT NULL REFERENCES hr.absence_types(id),

    start_date          DATE            NOT NULL,
    end_date            DATE            NOT NULL,
    total_days          SMALLINT,               -- Días hábiles de ausencia

    status              VARCHAR(20)     NOT NULL DEFAULT 'pending',
    -- pending | approved | rejected | cancelled

    reason              TEXT,
    approved_by         BIGINT          REFERENCES hr.employees(id),
    approved_at         TIMESTAMPTZ,

    notes               TEXT,

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_absences_employee ON hr.absences (employee_id);
CREATE INDEX idx_absences_company  ON hr.absences (company_id);
CREATE INDEX idx_absences_dates    ON hr.absences (start_date, end_date);
CREATE INDEX idx_absences_status   ON hr.absences (status);

CREATE TRIGGER trg_absences_updated_at
    BEFORE UPDATE ON hr.absences
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.absences         IS 'Ausencias y permisos de empleados con flujo de aprobación.';
COMMENT ON COLUMN hr.absences.status  IS 'pending | approved | rejected | cancelled';
