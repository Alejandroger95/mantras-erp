-- ============================================================
-- mantrasdb | Módulo HR
-- Tablas: hr.document_categories / hr.documents
-- Descripción: Repositorio universal de documentos.
--              Cualquier entidad del sistema puede tener
--              múltiples documentos asociados con versionado.
--
-- USO:
--   documents(entity_type='employee',            entity_id=7)  → CV, ID, CURP
--   documents(entity_type='contract',            entity_id=45) → contrato firmado
--   documents(entity_type='absence',             entity_id=12) → certificado médico
--   documents(entity_type='disciplinary_action', entity_id=3)  → acta firmada
--   documents(entity_type='equipment_assignment',entity_id=8)  → acta de entrega
-- ============================================================

CREATE TABLE hr.document_categories (
    id          BIGSERIAL       PRIMARY KEY,
    name        VARCHAR(100)    NOT NULL,
    description TEXT,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE
);

INSERT INTO hr.document_categories (name, description) VALUES
  ('Employment contract',         'Contrato de trabajo firmado por ambas partes'),
  ('Contract amendment',          'Modificación o adendum a un contrato existente'),
  ('Medical certificate',         'Constancia médica para justificar ausencia'),
  ('Disability certificate',      'Documento oficial de incapacidad por enfermedad'),
  ('Disciplinary notice',         'Acta de amonestación o acción disciplinaria'),
  ('Equipment delivery receipt',  'Acta de entrega de equipo al empleado'),
  ('Equipment return receipt',    'Acta de devolución de equipo por el empleado'),
  ('Government-issued ID',        'Credencial, pasaporte u otro documento de identidad'),
  ('Tax document',                'CURP, RFC, NIT u otro documento fiscal'),
  ('Proof of address',            'Recibo de servicios u otro comprobante de domicilio'),
  ('Birth certificate',           'Acta de nacimiento del empleado'),
  ('Academic certificate',        'Título profesional o certificado de estudios'),
  ('Performance review',          'Documento de evaluación de desempeño firmado'),
  ('Employment verification',     'Carta o constancia de trabajo emitida por la empresa'),
  ('Resignation letter',          'Carta de renuncia voluntaria del empleado'),
  ('Severance agreement',         'Documento de finiquito o liquidación'),
  ('Equipment photo',             'Fotografía del equipo al momento de entrega o devolución'),
  ('Other',                       'Documento que no clasifica en las categorías anteriores');

CREATE TABLE hr.documents (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id),

    -- ── Relación polimórfica ──────────────────────────────────
    -- A qué entidad pertenece este documento
    entity_type     VARCHAR(60)     NOT NULL,
    -- employee | contract | absence | disciplinary_action |
    -- equipment | equipment_assignment | performance_review | training
    entity_id       BIGINT          NOT NULL,

    -- Clasificación
    category_id     BIGINT          REFERENCES hr.document_categories(id),

    -- ── Archivo ───────────────────────────────────────────────
    file_name       VARCHAR(255)    NOT NULL,   -- Nombre en el sistema de almacenamiento
    original_name   VARCHAR(255),              -- Nombre con el que subió el usuario
    mime_type       VARCHAR(100),              -- application/pdf | image/jpeg | image/png
    file_size_bytes BIGINT,
    url             TEXT            NOT NULL,   -- URL del archivo (S3, GCS, Azure Blob, etc.)

    -- ── Versionado ────────────────────────────────────────────
    version         SMALLINT        NOT NULL DEFAULT 1,
    is_current      BOOLEAN         NOT NULL DEFAULT TRUE,
    -- TRUE = versión activa. Las anteriores quedan como historial.
    -- Regla: solo un documento por entidad+categoría debe tener is_current=TRUE

    -- ── Metadatos ─────────────────────────────────────────────
    description     TEXT,
    document_date   DATE,           -- Fecha del documento (no de la subida)
    expires_at      DATE,           -- Para docs que expiran: certificados, permisos

    -- ── Auditoría ─────────────────────────────────────────────
    uploaded_by     BIGINT          REFERENCES hr.employees(id),

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_documents_entity   ON hr.documents (entity_type, entity_id);
CREATE INDEX idx_documents_company  ON hr.documents (company_id);
CREATE INDEX idx_documents_category ON hr.documents (category_id);
CREATE INDEX idx_documents_current  ON hr.documents (entity_type, entity_id) WHERE is_current = TRUE;
CREATE INDEX idx_documents_expires  ON hr.documents (expires_at)
    WHERE expires_at IS NOT NULL AND is_active = TRUE;

CREATE TRIGGER trg_documents_updated_at
    BEFORE UPDATE ON hr.documents
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.documents              IS 'Repositorio universal. Cualquier entidad puede tener N documentos con historial y versionado.';
COMMENT ON COLUMN hr.documents.entity_type  IS 'Discriminador polimórfico: employee | contract | absence | disciplinary_action | equipment | performance_review | training';
COMMENT ON COLUMN hr.documents.entity_id    IS 'ID del registro en la tabla indicada por entity_type.';
COMMENT ON COLUMN hr.documents.is_current   IS 'Solo el doc vigente aplica. Versiones anteriores quedan como historial.';
COMMENT ON COLUMN hr.documents.expires_at   IS 'Para docs con vencimiento: certificados médicos, permisos temporales.';
