-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.performance_reviews
-- Descripción: Evaluaciones periódicas de desempeño por empleado.
-- ============================================================

CREATE TABLE hr.performance_reviews (
    id              BIGSERIAL       PRIMARY KEY,
    employee_id     BIGINT          NOT NULL REFERENCES hr.employees(id) ON DELETE RESTRICT,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    period          VARCHAR(50)     NOT NULL,   -- "Q1 2025", "H2 2024", "Annual 2024"
    review_date     DATE            NOT NULL,

    -- Calificación global
    overall_score   NUMERIC(4,2),              -- Ej: 4.5 sobre 5
    score_scale     SMALLINT        DEFAULT 5,  -- Escala máxima (5 o 10)
    rating          VARCHAR(30),               -- outstanding | exceeds | meets | below | unsatisfactory

    -- Detalles
    strengths       TEXT,
    areas_to_improve TEXT,
    goals_next_period TEXT,
    comments        TEXT,

    -- Responsable
    reviewed_by     BIGINT          NOT NULL REFERENCES hr.employees(id),

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_perf_reviews_employee ON hr.performance_reviews (employee_id);
CREATE INDEX idx_perf_reviews_company  ON hr.performance_reviews (company_id);

CREATE TRIGGER trg_performance_reviews_updated_at
    BEFORE UPDATE ON hr.performance_reviews
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.performance_reviews        IS 'Evaluaciones de desempeño periódicas por empleado.';
COMMENT ON COLUMN hr.performance_reviews.rating IS 'outstanding | exceeds | meets | below | unsatisfactory';
