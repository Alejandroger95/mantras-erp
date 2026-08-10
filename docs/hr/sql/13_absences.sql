-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.absences
-- Descripción: Solicitudes y registros de ausencias por empleado.
--   absence_scope = 'partial'  → ausencia dentro de jornada (1-2h)
--   absence_scope = 'full_day' → ausencia de día(s) completo(s)
-- ============================================================

CREATE TABLE hr.absences (
    id                  BIGSERIAL       PRIMARY KEY,
    employee_id         BIGINT          NOT NULL REFERENCES hr.employees(id) ON DELETE RESTRICT,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    absence_type_id     BIGINT          NOT NULL REFERENCES hr.absence_types(id),

    -- ── Scope ──────────────────────────────────────────────
    absence_scope       VARCHAR(10)     NOT NULL DEFAULT 'full_day',
    -- 'partial' | 'full_day'

    -- ── Fechas (ambos scopes) ───────────────────────────────
    start_date          DATE            NOT NULL,
    end_date            DATE            NOT NULL,   -- = start_date para parciales
    total_days          SMALLINT,                   -- días hábiles; NULL para parciales

    -- ── Horas (solo scope = 'partial') ─────────────────────
    start_time          TIME,                       -- hora inicio de la ausencia
    end_time            TIME,                       -- hora fin de la ausencia
    duration_minutes    SMALLINT,                   -- calculado: end_time - start_time

    -- ── Flujo de aprobación ─────────────────────────────────
    status              VARCHAR(20)     NOT NULL DEFAULT 'pending',
    -- pending | approved | rejected | cancelled

    requested_by        BIGINT          REFERENCES hr.employees(id),  -- quién creó la solicitud
    reviewed_by         BIGINT          REFERENCES hr.employees(id),  -- quién aprobó/rechazó
    reviewed_at         TIMESTAMPTZ,

    -- ── Notas ───────────────────────────────────────────────
    reason              TEXT,           -- motivo del empleado
    notes               TEXT,           -- notas internas del revisor

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    -- ── Constraints de coherencia ───────────────────────────
    CONSTRAINT chk_absences_scope_values CHECK (
        absence_scope IN ('partial', 'full_day')
    ),
    CONSTRAINT chk_absences_partial_times CHECK (
        (absence_scope = 'partial'  AND start_time IS NOT NULL AND end_time IS NOT NULL AND end_time > start_time)
        OR
        (absence_scope = 'full_day' AND start_time IS NULL AND end_time IS NULL)
    ),
    CONSTRAINT chk_absences_dates CHECK (end_date >= start_date)
);

CREATE INDEX idx_absences_employee ON hr.absences (employee_id);
CREATE INDEX idx_absences_company  ON hr.absences (company_id);
CREATE INDEX idx_absences_dates    ON hr.absences (start_date, end_date);
CREATE INDEX idx_absences_status   ON hr.absences (status);
CREATE INDEX idx_absences_scope    ON hr.absences (absence_scope);
CREATE INDEX idx_absences_day      ON hr.absences (start_date, absence_scope);

CREATE TRIGGER trg_absences_updated_at
    BEFORE UPDATE ON hr.absences
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.absences                  IS 'Ausencias y permisos: parciales (dentro de jornada) y de día(s) completo(s).';
COMMENT ON COLUMN hr.absences.absence_scope    IS 'partial = ausencia dentro de la jornada | full_day = día(s) completo(s)';
COMMENT ON COLUMN hr.absences.start_time       IS 'Solo parciales: hora de inicio';
COMMENT ON COLUMN hr.absences.end_time         IS 'Solo parciales: hora de fin';
COMMENT ON COLUMN hr.absences.duration_minutes IS 'Solo parciales: duración en minutos';
COMMENT ON COLUMN hr.absences.requested_by     IS 'Quién creó la solicitud (el propio empleado, un manager o admin)';
COMMENT ON COLUMN hr.absences.reviewed_by      IS 'Quién aprobó o rechazó';
COMMENT ON COLUMN hr.absences.status           IS 'pending | approved | rejected | cancelled';
