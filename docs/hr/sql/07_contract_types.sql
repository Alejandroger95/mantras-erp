-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.contract_types
-- Descripción: Catálogo de tipos de contrato laboral.
-- ============================================================

CREATE TABLE hr.contract_types (
    id          BIGSERIAL       PRIMARY KEY,
    company_id  BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    name        VARCHAR(100)    NOT NULL,   -- "Planilla fija", "Por horas", "Por proyecto", "Honorarios"
    code        VARCHAR(20),
    description TEXT,
    is_permanent BOOLEAN        NOT NULL DEFAULT TRUE,
    -- TRUE = contrato indefinido / FALSE = contrato temporal o por proyecto

    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_contract_types_company ON hr.contract_types (company_id);

-- Datos de ejemplo
-- INSERT INTO hr.contract_types (company_id, name, code, is_permanent) VALUES
--   (1, 'Fixed salary',    'FIXED',    TRUE),
--   (1, 'Hourly',          'HOURLY',   FALSE),
--   (1, 'Project-based',   'PROJECT',  FALSE),
--   (1, 'Freelance / Fees','FREELANCE',FALSE);

CREATE TRIGGER trg_contract_types_updated_at
    BEFORE UPDATE ON hr.contract_types
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE hr.contract_types IS 'Catálogo de tipos de contrato: planilla fija, por horas, por proyecto, honorarios.';
