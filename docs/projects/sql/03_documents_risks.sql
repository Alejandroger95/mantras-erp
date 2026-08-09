-- ============================================================
-- mantrasdb | Módulo Projects
-- Archivo: 03_documents_risks.sql
-- Descripción: Documentos, registro de riesgos y
--              historial de cambios de estado del proyecto.
--
-- Tablas:
--   1. project_documents   — adjuntos y entregables
--   2. project_risks       — registro de riesgos con matriz probabilidad×impacto
--   3. project_status_log  — auditoría inmutable de cambios de estado (IMMUTABLE)
-- ============================================================

-- ============================================================
-- 1. PROJECT DOCUMENTS (Documentos y entregables)
-- ============================================================
CREATE TABLE projects.project_documents (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    project_id          BIGINT          NOT NULL REFERENCES projects.projects(id) ON DELETE RESTRICT,
    phase_id            BIGINT          REFERENCES projects.project_phases(id),
    -- NULL = documento de nivel proyecto (no asociado a una fase)
    task_id             BIGINT          REFERENCES projects.project_tasks(id),
    -- NULL = documento de nivel proyecto o fase

    -- Clasificación
    document_type       VARCHAR(30)     NOT NULL DEFAULT 'deliverable',
    -- requirement | design | deliverable | report | contract
    -- | meeting_notes | proposal | other

    -- Identificación
    name                VARCHAR(200)    NOT NULL,
    description         TEXT,

    -- Almacenamiento
    file_url            TEXT,
    -- URL al archivo en S3, GCS, OneDrive, etc.

    -- Versionado
    version             VARCHAR(20)     NOT NULL DEFAULT '1.0',
    -- Ej: '1.0', '2.1', 'final', 'v3-client-approved'

    -- Visibilidad
    is_client_visible   BOOLEAN         NOT NULL DEFAULT FALSE,
    -- TRUE = el cliente puede ver este documento en el portal

    -- Quién subió el archivo
    uploaded_by         BIGINT          REFERENCES hr.system_users(id),

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_documents_type
        CHECK (document_type IN (
            'requirement','design','deliverable','report','contract',
            'meeting_notes','proposal','other'
        ))
);

CREATE INDEX idx_documents_project     ON projects.project_documents (project_id);
CREATE INDEX idx_documents_phase       ON projects.project_documents (phase_id);
CREATE INDEX idx_documents_task        ON projects.project_documents (task_id);
CREATE INDEX idx_documents_company     ON projects.project_documents (company_id);
CREATE INDEX idx_documents_type        ON projects.project_documents (project_id, document_type);
CREATE INDEX idx_documents_client      ON projects.project_documents (project_id)
    WHERE is_client_visible;

CREATE TRIGGER trg_project_documents_updated_at
    BEFORE UPDATE ON projects.project_documents
    FOR EACH ROW EXECUTE FUNCTION projects.set_updated_at();

COMMENT ON TABLE  projects.project_documents                    IS 'Documentos, entregables y adjuntos del proyecto. Incluye control de versiones y visibilidad para el cliente.';
COMMENT ON COLUMN projects.project_documents.document_type      IS 'requirement | design | deliverable | report | contract | meeting_notes | proposal | other';
COMMENT ON COLUMN projects.project_documents.is_client_visible  IS 'TRUE = visible en el portal del cliente. FALSE = interno solamente.';
COMMENT ON COLUMN projects.project_documents.version            IS 'Versión del documento. Ej: 1.0, 2.1, final, v3-client-approved.';

-- ============================================================
-- 2. PROJECT RISKS (Registro de riesgos)
-- ============================================================
CREATE TABLE projects.project_risks (
    id                      BIGSERIAL       PRIMARY KEY,
    company_id              BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    project_id              BIGINT          NOT NULL REFERENCES projects.projects(id) ON DELETE RESTRICT,

    -- Descripción
    name                    VARCHAR(200)    NOT NULL,
    description             TEXT,

    -- Matriz de riesgo
    probability             SMALLINT        NOT NULL CHECK (probability BETWEEN 1 AND 5),
    -- 1=muy baja, 2=baja, 3=media, 4=alta, 5=muy alta
    impact                  SMALLINT        NOT NULL CHECK (impact BETWEEN 1 AND 5),
    -- 1=muy bajo, 2=bajo, 3=medio, 4=alto, 5=muy alto

    -- Score y nivel calculados (GENERATED ALWAYS AS STORED)
    risk_score              SMALLINT        GENERATED ALWAYS AS (probability * impact) STORED,
    -- Rango: 1-25
    -- 1-5 = low | 6-10 = medium | 11-19 = high | 20-25 = critical

    risk_level              VARCHAR(10)     GENERATED ALWAYS AS (
        CASE
            WHEN probability * impact <= 5  THEN 'low'
            WHEN probability * impact <= 10 THEN 'medium'
            WHEN probability * impact <= 19 THEN 'high'
            ELSE                                 'critical'
        END
    ) STORED,

    -- Clasificación
    risk_category           VARCHAR(30),
    -- technical | resource | timeline | budget | scope | external | legal

    -- Estado de gestión
    status                  VARCHAR(20)     NOT NULL DEFAULT 'open',
    -- open | mitigated | closed | accepted

    -- Planes
    mitigation_plan         TEXT,
    -- Acciones para reducir probabilidad o impacto
    contingency_plan        TEXT,
    -- Acciones si el riesgo se materializa

    -- Responsable
    owner_id                BIGINT          REFERENCES hr.employees(id),

    -- Fechas
    identified_date         DATE            NOT NULL DEFAULT CURRENT_DATE,
    target_resolution_date  DATE,

    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_risks_category
        CHECK (risk_category IS NULL OR risk_category IN (
            'technical','resource','timeline','budget','scope','external','legal'
        )),
    CONSTRAINT chk_risks_status
        CHECK (status IN ('open','mitigated','closed','accepted'))
);

CREATE INDEX idx_risks_project      ON projects.project_risks (project_id);
CREATE INDEX idx_risks_company      ON projects.project_risks (company_id);
CREATE INDEX idx_risks_status       ON projects.project_risks (project_id, status);
CREATE INDEX idx_risks_level        ON projects.project_risks (project_id, risk_level);
CREATE INDEX idx_risks_open_high    ON projects.project_risks (project_id)
    WHERE status = 'open' AND risk_level IN ('high','critical');

CREATE TRIGGER trg_project_risks_updated_at
    BEFORE UPDATE ON projects.project_risks
    FOR EACH ROW EXECUTE FUNCTION projects.set_updated_at();

COMMENT ON TABLE  projects.project_risks              IS 'Registro de riesgos del proyecto. Matriz probabilidad (1-5) × impacto (1-5) genera score y nivel automáticamente.';
COMMENT ON COLUMN projects.project_risks.probability  IS '1=muy baja, 2=baja, 3=media, 4=alta, 5=muy alta probabilidad de ocurrencia.';
COMMENT ON COLUMN projects.project_risks.impact       IS '1=muy bajo, 2=bajo, 3=medio, 4=alto, 5=muy alto impacto en el proyecto.';
COMMENT ON COLUMN projects.project_risks.risk_score   IS 'probability × impact. GENERATED STORED. Rango 1-25.';
COMMENT ON COLUMN projects.project_risks.risk_level   IS 'low (1-5) | medium (6-10) | high (11-19) | critical (20-25). GENERATED STORED.';
COMMENT ON COLUMN projects.project_risks.mitigation_plan    IS 'Acciones preventivas para reducir probabilidad o impacto antes de que ocurra.';
COMMENT ON COLUMN projects.project_risks.contingency_plan   IS 'Plan de respuesta si el riesgo se materializa.';

-- ============================================================
-- 3. PROJECT STATUS LOG (Historial de estados — IMMUTABLE)
-- ============================================================
-- IMMUTABLE: registro de auditoría. No se modifica ni elimina.
CREATE TABLE projects.project_status_log (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    project_id      BIGINT          NOT NULL REFERENCES projects.projects(id) ON DELETE RESTRICT,

    -- Transición de estado
    from_status     VARCHAR(20),
    -- NULL = creación inicial del proyecto
    to_status       VARCHAR(20)     NOT NULL,

    -- Motivo del cambio
    reason          TEXT,
    -- Ej: "Cliente solicitó pausar", "Sprint completado", "Aprobado por PM"

    -- Quién hizo el cambio
    changed_by      BIGINT          REFERENCES hr.system_users(id),
    changed_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
    -- IMMUTABLE: sin updated_at
);
-- IMMUTABLE

CREATE INDEX idx_status_log_project    ON projects.project_status_log (project_id);
CREATE INDEX idx_status_log_company    ON projects.project_status_log (company_id);
CREATE INDEX idx_status_log_changed    ON projects.project_status_log (project_id, changed_at DESC);

COMMENT ON TABLE  projects.project_status_log             IS 'Auditoría inmutable de cambios de estado. IMMUTABLE: no se modifica ni elimina.';
COMMENT ON COLUMN projects.project_status_log.from_status IS 'Estado anterior. NULL = creación del registro.';
COMMENT ON COLUMN projects.project_status_log.to_status   IS 'Nuevo estado. Valores: draft | planning | active | on_hold | completed | cancelled.';
COMMENT ON COLUMN projects.project_status_log.changed_by  IS 'Usuario del sistema que realizó el cambio de estado.';
