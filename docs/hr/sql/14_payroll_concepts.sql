-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.payroll_concepts
-- Descripción: Catálogo de conceptos de nómina: ingresos,
--              deducciones y aportaciones del empleador.
-- ============================================================

CREATE TABLE hr.payroll_concepts (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    name            VARCHAR(150)    NOT NULL,
    code            VARCHAR(30),
    description     TEXT,

    concept_type    VARCHAR(20)     NOT NULL,
    -- earning      = ingreso para el empleado (salario, bono, comisión, etc.)
    -- deduction    = descuento al empleado (IMSS, ISR, préstamo, etc.)
    -- contribution = aportación del empleador (IMSS patronal, etc.)

    is_taxable      BOOLEAN         NOT NULL DEFAULT TRUE,  -- ¿Afecta base gravable?
    is_fixed        BOOLEAN         NOT NULL DEFAULT TRUE,  -- TRUE = monto fijo / FALSE = variable

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payroll_concepts_company ON hr.payroll_concepts (company_id);
CREATE INDEX idx_payroll_concepts_type    ON hr.payroll_concepts (concept_type);

CREATE TRIGGER trg_payroll_concepts_updated_at
    BEFORE UPDATE ON hr.payroll_concepts
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.payroll_concepts              IS 'Catálogo de conceptos de nómina: ingresos, deducciones y aportaciones.';
COMMENT ON COLUMN hr.payroll_concepts.concept_type IS 'earning | deduction | contribution';
COMMENT ON COLUMN hr.payroll_concepts.is_taxable   IS 'TRUE = el concepto forma parte de la base gravable para impuestos.';
