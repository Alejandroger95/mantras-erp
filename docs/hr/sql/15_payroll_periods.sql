-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.payroll_periods
-- Descripción: Períodos de pago de nómina por empresa.
--              Cada período define el rango de fechas y su estado.
-- ============================================================

CREATE TABLE hr.payroll_periods (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    name            VARCHAR(100)    NOT NULL,   -- "Quincena 1 - Enero 2025"
    frequency       VARCHAR(20)     NOT NULL,   -- weekly | biweekly | monthly
    start_date      DATE            NOT NULL,
    end_date        DATE            NOT NULL,
    payment_date    DATE            NOT NULL,   -- Fecha efectiva de pago

    status          VARCHAR(20)     NOT NULL DEFAULT 'open',
    -- open | processing | closed | paid

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payroll_periods_company ON hr.payroll_periods (company_id);
CREATE INDEX idx_payroll_periods_dates   ON hr.payroll_periods (start_date, end_date);
CREATE INDEX idx_payroll_periods_status  ON hr.payroll_periods (status);

CREATE TRIGGER trg_payroll_periods_updated_at
    BEFORE UPDATE ON hr.payroll_periods
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.payroll_periods              IS 'Períodos de nómina con fechas de corte y pago.';
COMMENT ON COLUMN hr.payroll_periods.status       IS 'open | processing | closed | paid';
COMMENT ON COLUMN hr.payroll_periods.payment_date IS 'Fecha en que se deposita el pago a los empleados.';
