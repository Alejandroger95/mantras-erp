-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.persons
-- Descripción: Identidad permanente e inmutable de una persona.
--              NO guarda documentos de identidad directamente —
--              eso va en hr.person_documents para soportar
--              cambios de documento (NIE → DNI, etc.) con historial.
--
--  persons (id=5, Juan Pérez)
--    ├── person_documents: NIE X1234567A  2018-2023 (histórico)
--    ├── person_documents: DNI 12345678Z  2023-hoy  (primario)
--    ├── employees id=12 → hired 2020, terminated 2022
--    └── employees id=47 → hired 2024, active
-- ============================================================

CREATE TABLE hr.persons (
    id                  BIGSERIAL       PRIMARY KEY,

    -- Identidad básica
    first_name          VARCHAR(150)    NOT NULL,
    last_name           VARCHAR(150)    NOT NULL,
    birth_date          DATE,
    gender              VARCHAR(20),
    -- male | female | other | not_specified

    -- Contacto personal (≠ correo corporativo en employees)
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

CREATE INDEX idx_persons_name  ON hr.persons (last_name, first_name);
CREATE INDEX idx_persons_email ON hr.persons (personal_email) WHERE personal_email IS NOT NULL;

CREATE TRIGGER trg_persons_updated_at
    BEFORE UPDATE ON hr.persons
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE hr.persons IS 'Identidad permanente. Documentos de identidad con historial en hr.person_documents.';
