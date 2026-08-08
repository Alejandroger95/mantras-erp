-- ============================================================
-- mantrasdb | Módulo HR
-- Tablas: hr.trainings / hr.training_participants
-- Descripción: Capacitaciones y cursos con sus participantes.
-- ============================================================

CREATE TABLE hr.trainings (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    name            VARCHAR(200)    NOT NULL,
    description     TEXT,
    category        VARCHAR(80),        -- technical | soft_skills | compliance | safety | other
    provider        VARCHAR(150),       -- Empresa o persona que imparte el curso
    instructor      VARCHAR(150),

    start_date      DATE,
    end_date        DATE,
    duration_hours  NUMERIC(6,2),
    location        VARCHAR(200),       -- Presencial o URL si es online
    modality        VARCHAR(20)  DEFAULT 'in_person',
    -- in_person | online | hybrid

    cost            NUMERIC(14,2),
    currency        CHAR(3)      DEFAULT 'USD',

    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE hr.training_participants (
    id              BIGSERIAL       PRIMARY KEY,
    training_id     BIGINT          NOT NULL REFERENCES hr.trainings(id) ON DELETE RESTRICT,
    employee_id     BIGINT          NOT NULL REFERENCES hr.employees(id) ON DELETE RESTRICT,

    status          VARCHAR(20)     NOT NULL DEFAULT 'enrolled',
    -- enrolled | completed | failed | cancelled

    score           NUMERIC(5,2),       -- Calificación obtenida
    passed          BOOLEAN,            -- TRUE = aprobó
    certificate_url TEXT,              -- URL del certificado si aplica
    notes           TEXT,

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_trainings_company              ON hr.trainings (company_id);
CREATE INDEX idx_training_participants_training ON hr.training_participants (training_id);
CREATE INDEX idx_training_participants_employee ON hr.training_participants (employee_id);
CREATE UNIQUE INDEX idx_training_participants_unique ON hr.training_participants (training_id, employee_id);

CREATE TRIGGER trg_trainings_updated_at             BEFORE UPDATE ON hr.trainings             FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();
CREATE TRIGGER trg_training_participants_updated_at BEFORE UPDATE ON hr.training_participants FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE hr.trainings             IS 'Capacitaciones y cursos ofrecidos a los empleados.';
COMMENT ON TABLE hr.training_participants IS 'Participantes de cada capacitación con resultado y certificado.';
