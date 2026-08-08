-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.persons
-- Descripción: Identidad permanente e inmutable de una persona.
--              Una persona puede ingresar, renunciar y reingresar
--              múltiples veces. Cada período de empleo crea un nuevo
--              registro en hr.employees, pero siempre apunta al
--              mismo person_id → la misma persona real.
--
--  persons (id=5, Juan Pérez)
--    └── employees id=12 → hired 2020-01-01, terminated 2022-06-30
--    └── employees id=47 → hired 2024-03-01, terminated NULL (activo)
-- ============================================================

CREATE TABLE hr.persons (
    id                  BIGSERIAL       PRIMARY KEY,

    -- Identidad
    first_name          VARCHAR(150)    NOT NULL,
    last_name           VARCHAR(150)    NOT NULL,
    birth_date          DATE,
    gender              VARCHAR(20),
    -- male | female | other | not_specified

    -- Documento de identidad principal
    document_type       VARCHAR(30)     NOT NULL DEFAULT 'ID',
    -- CURP (MX) | DNI (ES/AR/PE) | CC (CO) | NIT (CO) | RUC (PE/EC) | PASSPORT | other
    document_number     VARCHAR(60),
    document_country    VARCHAR(100)    DEFAULT 'Mexico',

    -- Contacto personal (≠ correo corporativo)
    personal_email      VARCHAR(150),
    personal_phone      VARCHAR(30),
    emergency_phone     VARCHAR(30),
    emergency_contact   VARCHAR(150),   -- Nombre del contacto de emergencia

    -- Dirección personal
    address             TEXT,
    city                VARCHAR(150),
    state               VARCHAR(150),
    country             VARCHAR(100)    DEFAULT 'Mexico',
    zip_code            VARCHAR(20),

    -- Información adicional
    marital_status      VARCHAR(20),
    -- single | married | divorced | widowed | common_law
    education_level     VARCHAR(50),
    photo_url           TEXT,

    -- Control
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_persons_document
    ON hr.persons (document_type, document_number)
    WHERE document_number IS NOT NULL;

CREATE INDEX idx_persons_name  ON hr.persons (last_name, first_name);
CREATE INDEX idx_persons_email ON hr.persons (personal_email) WHERE personal_email IS NOT NULL;

CREATE TRIGGER trg_persons_updated_at
    BEFORE UPDATE ON hr.persons
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.persons                  IS 'Identidad permanente. Permite reingresos sin duplicar la persona real.';
COMMENT ON COLUMN hr.persons.document_type    IS 'Tipo de documento: CURP, DNI, CC, NIT, PASSPORT, etc. Varía por país.';
COMMENT ON COLUMN hr.persons.document_number  IS 'Número del documento. Único por document_type.';
COMMENT ON COLUMN hr.persons.emergency_contact IS 'Nombre completo del contacto en caso de emergencia.';
