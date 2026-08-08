-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.person_documents
-- Descripción: Historial de documentos de identidad de una persona.
--              Una persona puede cambiar de tipo de documento
--              (ej: NIE → DNI al obtener ciudadanía) y el sistema
--              conserva todo el historial. is_primary = TRUE indica
--              el documento vigente activo.
--
-- Ejemplo real:
--   person_id=5 (Juan García)
--     NIE X1234567A  España  2018-01-15 → 2023-06-30  is_primary=FALSE
--     DNI 12345678Z  España  2023-07-01 → NULL        is_primary=TRUE
-- ============================================================

CREATE TABLE hr.person_documents (
    id              BIGSERIAL       PRIMARY KEY,
    person_id       BIGINT          NOT NULL REFERENCES hr.persons(id) ON DELETE RESTRICT,

    -- Tipo y número de documento
    document_type   VARCHAR(30)     NOT NULL,
    -- CURP (MX) | RFC (MX) | DNI (ES/AR/PE) | NIE (ES - extranjeros)
    -- CC (CO) | NIT (CO) | RUC (PE/EC) | PASSPORT | SSN (US) | other
    document_number VARCHAR(60)     NOT NULL,
    document_country VARCHAR(100)   NOT NULL DEFAULT 'Mexico',

    -- Datos del documento físico
    issue_date      DATE,                   -- Fecha de emisión
    expiry_date     DATE,                   -- Fecha de vencimiento (NULL = no vence)
    issued_by       VARCHAR(200),           -- Autoridad emisora (ej: "Ministerio del Interior")

    -- Estado
    is_primary      BOOLEAN         NOT NULL DEFAULT FALSE,
    -- TRUE = documento vigente activo. Solo uno por persona debe ser TRUE.
    -- Al activar un nuevo doc, el anterior se pone en FALSE automáticamente (app layer).

    -- Motivo del cambio (para registros no primarios)
    replacement_reason VARCHAR(100),
    -- citizenship_obtained | document_expired | lost | damaged | name_change | other

    notes           TEXT,

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_person_docs_person  ON hr.person_documents (person_id);
CREATE INDEX idx_person_docs_primary ON hr.person_documents (person_id) WHERE is_primary = TRUE;
CREATE UNIQUE INDEX idx_person_docs_number
    ON hr.person_documents (document_type, document_number)
    WHERE is_active = TRUE;

CREATE TRIGGER trg_person_documents_updated_at
    BEFORE UPDATE ON hr.person_documents
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.person_documents                    IS 'Historial de documentos de identidad. Soporta cambios NIE→DNI, renovaciones, pérdidas, etc.';
COMMENT ON COLUMN hr.person_documents.is_primary         IS 'TRUE = documento vigente activo. Solo uno por persona.';
COMMENT ON COLUMN hr.person_documents.replacement_reason IS 'Motivo por el que este doc dejó de ser primario: citizenship_obtained | expired | lost | damaged | name_change | other';
COMMENT ON COLUMN hr.person_documents.expiry_date        IS 'NULL = documento sin fecha de vencimiento (ej: DNI en algunos países).';
