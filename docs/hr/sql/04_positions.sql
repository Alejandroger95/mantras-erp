-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.positions
-- Descripción: Puestos o cargos dentro de una empresa.
--              Incluye nivel jerárquico y banda salarial.
-- ============================================================

CREATE TABLE hr.positions (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    department_id       BIGINT          REFERENCES hr.departments(id) ON DELETE RESTRICT,

    name                VARCHAR(150)    NOT NULL,   -- "Gerente de Ventas", "Analista TI", etc.
    code                VARCHAR(30),
    description         TEXT,

    -- Jerarquía
    hierarchy_level     SMALLINT,               -- 1=Director, 2=Gerente, 3=Coordinador, 4=Analista, 5=Operativo
    reports_to_id       BIGINT          REFERENCES hr.positions(id), -- Puesto al que reporta

    -- Banda salarial
    min_salary          NUMERIC(14,2),
    max_salary          NUMERIC(14,2),
    salary_currency     CHAR(3)         DEFAULT 'USD',

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_positions_company    ON hr.positions (company_id);
CREATE INDEX idx_positions_department ON hr.positions (department_id);

CREATE TRIGGER trg_positions_updated_at
    BEFORE UPDATE ON hr.positions
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.positions                  IS 'Puestos o cargos de la empresa con nivel jerárquico y banda salarial.';
COMMENT ON COLUMN hr.positions.hierarchy_level  IS '1=Director | 2=Gerente | 3=Coordinador | 4=Analista | 5=Operativo';
COMMENT ON COLUMN hr.positions.reports_to_id    IS 'Puesto al que reporta directamente este cargo.';
