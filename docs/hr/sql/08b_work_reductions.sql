-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.work_reductions
-- Descripción: Reducción temporal de jornada laboral.
--              Cubre casos como reducción por paternidad/maternidad,
--              cuidado de familiar, motivos médicos o acuerdo personal.
--              Afecta el cálculo de nómina y la planificación de horarios.
--
-- Ejemplo: Juan trabaja 40h/semana. Solicita reducción por paternidad
--          al 50% → pasa a 20h/semana del 2025-03-01 al 2025-09-01.
--          Durante ese período su salario base se ajusta proporcionalmente
--          y su horario cambia en el sistema.
-- ============================================================

CREATE TABLE hr.work_reductions (
    id                      BIGSERIAL       PRIMARY KEY,
    employee_id             BIGINT          NOT NULL REFERENCES hr.employees(id) ON DELETE RESTRICT,
    company_id              BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    contract_id             BIGINT          REFERENCES hr.contracts(id),  -- Contrato afectado

    -- Motivo legal
    reason                  VARCHAR(50)     NOT NULL,
    -- paternity | maternity | childcare | family_care | medical | personal | legal_obligation | other
    legal_basis             TEXT,
    -- Artículo de ley que ampara la reducción (ej: "Art. 37.5 Estatuto de los Trabajadores")

    -- Jornada original y reducida
    original_weekly_hours   NUMERIC(5,2)    NOT NULL,   -- Ej: 40.00
    reduced_weekly_hours    NUMERIC(5,2)    NOT NULL,   -- Ej: 20.00
    reduction_percentage    NUMERIC(5,2)    GENERATED ALWAYS AS
        (ROUND(((original_weekly_hours - reduced_weekly_hours) / original_weekly_hours) * 100, 2))
        STORED,
    -- Calculado automáticamente: ((40 - 20) / 40) * 100 = 50.00%

    -- Impacto en nómina
    salary_adjusted         BOOLEAN         NOT NULL DEFAULT TRUE,
    -- TRUE = el salario se reduce proporcionalmente a la reducción de horas
    adjusted_salary         NUMERIC(14,2),
    -- Monto del salario durante la reducción (si salary_adjusted = TRUE)

    -- Vigencia
    start_date              DATE            NOT NULL,
    end_date                DATE,                       -- NULL = vigente indefinidamente
    is_current              BOOLEAN         NOT NULL DEFAULT TRUE,

    -- Aprobación
    status                  VARCHAR(20)     NOT NULL DEFAULT 'pending',
    -- pending | approved | active | completed | rejected
    approved_by             BIGINT          REFERENCES hr.employees(id),
    approved_at             TIMESTAMPTZ,
    rejection_reason        TEXT,

    notes                   TEXT,

    is_active               BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_work_reductions_employee ON hr.work_reductions (employee_id);
CREATE INDEX idx_work_reductions_company  ON hr.work_reductions (company_id);
CREATE INDEX idx_work_reductions_current  ON hr.work_reductions (employee_id) WHERE is_current = TRUE;
CREATE INDEX idx_work_reductions_dates    ON hr.work_reductions (start_date, end_date);

CREATE TRIGGER trg_work_reductions_updated_at
    BEFORE UPDATE ON hr.work_reductions
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.work_reductions                       IS 'Reducciones temporales de jornada: paternidad, maternidad, médica, cuidado familiar, etc.';
COMMENT ON COLUMN hr.work_reductions.reason                IS 'paternity | maternity | childcare | family_care | medical | personal | legal_obligation | other';
COMMENT ON COLUMN hr.work_reductions.reduction_percentage  IS 'Calculado automáticamente: ((original - reduced) / original) * 100';
COMMENT ON COLUMN hr.work_reductions.salary_adjusted       IS 'TRUE = el salario baja proporcionalmente. FALSE = mantiene salario completo (ej: baja médica cubierta por seguro).';
COMMENT ON COLUMN hr.work_reductions.legal_basis           IS 'Artículo de ley que ampara la reducción. Importante para auditorías laborales.';
