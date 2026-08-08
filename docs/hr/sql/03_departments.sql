-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.departments
-- Descripción: Áreas o departamentos dentro de una empresa.
--              Soporta jerarquía: un departamento puede tener
--              un departamento padre (parent_id).
-- ============================================================

CREATE TABLE hr.departments (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    parent_id       BIGINT          REFERENCES hr.departments(id) ON DELETE RESTRICT,
    -- NULL = departamento raíz (sin padre)

    name            VARCHAR(150)    NOT NULL,
    code            VARCHAR(30),            -- Código interno del departamento
    description     TEXT,
    cost_center     VARCHAR(50),            -- Centro de costo contable

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_departments_company ON hr.departments (company_id);
CREATE INDEX idx_departments_parent  ON hr.departments (parent_id);

CREATE TRIGGER trg_departments_updated_at
    BEFORE UPDATE ON hr.departments
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.departments           IS 'Departamentos o áreas de la empresa. Soporta jerarquía mediante parent_id.';
COMMENT ON COLUMN hr.departments.parent_id IS 'NULL = departamento raíz. Permite anidar departamentos dentro de otros.';
COMMENT ON COLUMN hr.departments.cost_center IS 'Centro de costo contable asociado al departamento.';
