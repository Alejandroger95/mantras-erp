-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.absence_types
-- Descripción: Catálogo de tipos de ausencia o permiso.
-- ============================================================

CREATE TABLE hr.absence_types (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    name                VARCHAR(100)    NOT NULL,
    code                VARCHAR(20),
    description         TEXT,

    is_paid             BOOLEAN         NOT NULL DEFAULT TRUE,   -- TRUE = con goce de sueldo
    requires_document   BOOLEAN         NOT NULL DEFAULT FALSE,  -- TRUE = exige certificado
    max_days_per_year   SMALLINT,                                -- NULL = sin límite

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_absence_types_company ON hr.absence_types (company_id);

-- Datos de ejemplo
-- INSERT INTO hr.absence_types (company_id, name, code, is_paid, requires_document) VALUES
--   (1, 'Vacation',         'VAC',  TRUE,  FALSE),
--   (1, 'Sick leave',       'SICK', TRUE,  TRUE),
--   (1, 'Unpaid leave',     'UNPL', FALSE, FALSE),
--   (1, 'Maternity leave',  'MAT',  TRUE,  TRUE),
--   (1, 'Paternity leave',  'PAT',  TRUE,  TRUE),
--   (1, 'Personal day',     'PERS', TRUE,  FALSE);

CREATE TRIGGER trg_absence_types_updated_at
    BEFORE UPDATE ON hr.absence_types
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE hr.absence_types IS 'Tipos de ausencia: vacaciones, enfermedad, permiso sin goce, maternidad, etc.';
