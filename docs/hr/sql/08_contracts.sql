-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.contracts
-- Descripción: Contrato laboral formal. Liga al empleado con
--              su puesto, tipo de contrato y condiciones económicas.
--              Guarda historial completo (modificaciones = nuevo registro).
-- ============================================================

CREATE TABLE hr.contracts (
    id                  BIGSERIAL       PRIMARY KEY,
    employee_id         BIGINT          NOT NULL REFERENCES hr.employees(id) ON DELETE RESTRICT,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    position_id         BIGINT          REFERENCES hr.positions(id),
    contract_type_id    BIGINT          NOT NULL REFERENCES hr.contract_types(id),

    -- Vigencia
    start_date          DATE            NOT NULL,
    end_date            DATE,                       -- NULL = contrato indefinido activo
    is_current          BOOLEAN         NOT NULL DEFAULT TRUE,

    -- Condiciones económicas
    base_salary         NUMERIC(14,2)   NOT NULL,
    salary_currency     CHAR(3)         DEFAULT 'USD',
    payment_frequency   VARCHAR(20)     DEFAULT 'biweekly', -- weekly | biweekly | monthly

    -- Jornada
    weekly_hours        SMALLINT        DEFAULT 40,
    work_schedule       VARCHAR(50),            -- "Monday-Friday 9am-6pm", etc.

    -- Modificaciones
    reason              VARCHAR(100),           -- Motivo del contrato/modificación
    -- new_hire | promotion | salary_adjustment | position_change | renewal | other
    notes               TEXT,

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_contracts_employee ON hr.contracts (employee_id);
CREATE INDEX idx_contracts_company  ON hr.contracts (company_id);
CREATE INDEX idx_contracts_current  ON hr.contracts (employee_id) WHERE is_current = TRUE;

CREATE TRIGGER trg_contracts_updated_at
    BEFORE UPDATE ON hr.contracts
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.contracts             IS 'Contratos laborales con historial. Cada modificación genera un nuevo registro.';
COMMENT ON COLUMN hr.contracts.is_current  IS 'Solo un contrato por empleado debe tener is_current=TRUE.';
COMMENT ON COLUMN hr.contracts.end_date    IS 'NULL = contrato indefinido vigente.';
