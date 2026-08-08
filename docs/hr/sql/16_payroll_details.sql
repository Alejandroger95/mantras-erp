-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.payroll_details
-- Descripción: Líneas de nómina: cada concepto aplicado a cada
--              empleado en cada período de pago.
-- ============================================================

CREATE TABLE hr.payroll_details (
    id                  BIGSERIAL       PRIMARY KEY,
    payroll_period_id   BIGINT          NOT NULL REFERENCES hr.payroll_periods(id) ON DELETE RESTRICT,
    employee_id         BIGINT          NOT NULL REFERENCES hr.employees(id) ON DELETE RESTRICT,
    payroll_concept_id  BIGINT          NOT NULL REFERENCES hr.payroll_concepts(id),

    amount              NUMERIC(14,2)   NOT NULL,   -- Monto del concepto
    quantity            NUMERIC(10,2)   DEFAULT 1,  -- Unidades (horas, días, etc.)
    unit_value          NUMERIC(14,2),              -- Valor por unidad (si aplica)

    notes               TEXT,

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payroll_details_period   ON hr.payroll_details (payroll_period_id);
CREATE INDEX idx_payroll_details_employee ON hr.payroll_details (employee_id);
CREATE INDEX idx_payroll_details_concept  ON hr.payroll_details (payroll_concept_id);

CREATE TRIGGER trg_payroll_details_updated_at
    BEFORE UPDATE ON hr.payroll_details
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.payroll_details             IS 'Detalle línea a línea de cada nómina por empleado y período.';
COMMENT ON COLUMN hr.payroll_details.quantity    IS 'Aplica para conceptos variables: horas extra, días trabajados, etc.';
COMMENT ON COLUMN hr.payroll_details.unit_value  IS 'Valor por unidad cuando el concepto es variable.';
