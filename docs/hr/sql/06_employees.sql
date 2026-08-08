-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.employees
-- Descripción: Relación laboral entre una persona y una empresa.
--              Una misma persona puede tener múltiples registros
--              (un reingreso = un nuevo employee con el mismo person_id).
--              hire_date → termination_date define el período de empleo.
-- ============================================================

CREATE TABLE hr.employees (
    id                  BIGSERIAL       PRIMARY KEY,
    person_id           BIGINT          NOT NULL REFERENCES hr.persons(id) ON DELETE RESTRICT,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    department_id       BIGINT          REFERENCES hr.departments(id),
    position_id         BIGINT          REFERENCES hr.positions(id),

    -- Identificación laboral
    employee_number     VARCHAR(50),            -- Número o código interno del empleado
    corporate_email     VARCHAR(150),           -- Email corporativo (≠ personal_email en persons)
    corporate_phone     VARCHAR(30),

    -- Período de empleo
    hire_date           DATE            NOT NULL,
    termination_date    DATE,                   -- NULL = actualmente activo
    termination_reason  VARCHAR(50),
    -- resigned | dismissed | contract_ended | retired | deceased | other

    -- Ubicación de trabajo
    work_city           VARCHAR(150),
    work_state          VARCHAR(150),
    work_country        VARCHAR(100)    DEFAULT 'Mexico',

    -- Estado actual
    status              VARCHAR(20)     NOT NULL DEFAULT 'active',
    -- active | on_leave | suspended | terminated

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_employees_person    ON hr.employees (person_id);
CREATE INDEX idx_employees_company   ON hr.employees (company_id);
CREATE INDEX idx_employees_dept      ON hr.employees (department_id);
CREATE INDEX idx_employees_position  ON hr.employees (position_id);
CREATE INDEX idx_employees_status    ON hr.employees (status);
CREATE INDEX idx_employees_active    ON hr.employees (company_id) WHERE termination_date IS NULL;
CREATE UNIQUE INDEX idx_employees_number ON hr.employees (company_id, employee_number) WHERE employee_number IS NOT NULL;

CREATE TRIGGER trg_employees_updated_at
    BEFORE UPDATE ON hr.employees
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.employees                     IS 'Relación laboral. Un person_id puede tener múltiples employees por reingresos.';
COMMENT ON COLUMN hr.employees.person_id           IS 'Referencia a la identidad permanente. No cambia entre reingresos.';
COMMENT ON COLUMN hr.employees.termination_date    IS 'NULL = empleado activo. Con fecha = empleo terminado.';
COMMENT ON COLUMN hr.employees.termination_reason  IS 'resigned | dismissed | contract_ended | retired | deceased | other';
COMMENT ON COLUMN hr.employees.status              IS 'active | on_leave | suspended | terminated';
