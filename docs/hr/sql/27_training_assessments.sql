-- ============================================================
-- mantrasdb | Módulo HR
-- Tablas: hr.training_assessments / hr.assessment_results
-- Vista:  hr.training_summary_view
-- Descripción: Evaluaciones formales de capacitaciones con
--              resultados por empleado e intento. Extiende
--              hr.trainings con tipo y rango de puntaje, y
--              permite múltiples evaluaciones ponderadas por
--              capacitación (examen parcial, examen final, etc.).
-- ============================================================

-- ──────────────────────────────────────────────────────────────
-- 1. Extender hr.trainings con columnas de puntaje
-- ──────────────────────────────────────────────────────────────
ALTER TABLE hr.trainings
    ADD COLUMN IF NOT EXISTS score_type    VARCHAR(20)  NOT NULL DEFAULT 'percentage',
    -- percentage: puntaje 0-100 (%)
    -- integer:    puntaje entero, e.g. 0-20 (nota vigesimal peruana)
    -- pass_fail:  sin puntaje numérico, solo aprobado/reprobado
    ADD COLUMN IF NOT EXISTS min_score     NUMERIC(6,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS max_score     NUMERIC(6,2) NOT NULL DEFAULT 100,
    ADD COLUMN IF NOT EXISTS passing_score NUMERIC(6,2) NOT NULL DEFAULT 70;
    -- Ej percentage: passing=70 significa ≥70% para aprobar
    -- Ej integer (vigesimal): max=20, passing=11

COMMENT ON COLUMN hr.trainings.score_type    IS 'percentage | integer | pass_fail';
COMMENT ON COLUMN hr.trainings.min_score     IS 'Puntaje mínimo posible (normalmente 0).';
COMMENT ON COLUMN hr.trainings.max_score     IS 'Puntaje máximo posible (100 para percentage, 20 para vigesimal).';
COMMENT ON COLUMN hr.trainings.passing_score IS 'Puntaje mínimo para aprobar.';

-- ──────────────────────────────────────────────────────────────
-- 2. Función trigger: calcular passed y status automáticamente
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION hr.compute_training_passed()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_score_type    VARCHAR(20);
    v_passing_score NUMERIC(6,2);
BEGIN
    SELECT score_type, passing_score
      INTO v_score_type, v_passing_score
      FROM hr.trainings
     WHERE id = NEW.training_id;

    IF v_score_type = 'pass_fail' THEN
        -- Para pass_fail, passed lo establece la aplicación; no se toca.
        NULL;
    ELSE
        NEW.passed := (NEW.score IS NOT NULL AND NEW.score >= v_passing_score);

        IF NEW.passed IS TRUE AND NEW.status = 'enrolled' THEN
            NEW.status := 'completed';
        ELSIF NEW.passed IS FALSE AND NEW.score IS NOT NULL AND NEW.status = 'enrolled' THEN
            NEW.status := 'failed';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- ──────────────────────────────────────────────────────────────
-- 3. Tabla: hr.training_assessments
-- ──────────────────────────────────────────────────────────────
CREATE TABLE hr.training_assessments (
    id              BIGSERIAL    PRIMARY KEY,
    training_id     BIGINT       NOT NULL REFERENCES hr.trainings(id)  ON DELETE RESTRICT,
    company_id      BIGINT       NOT NULL REFERENCES hr.companies(id)  ON DELETE RESTRICT,

    name            VARCHAR(200) NOT NULL,
    -- "Examen final", "Módulo 1 — SQL Básico"

    assessment_type VARCHAR(20)  NOT NULL DEFAULT 'exam',
    -- exam | quiz | practical | observation | simulation

    weight_pct      NUMERIC(5,2) NOT NULL DEFAULT 100,
    -- % del total. Las evaluaciones de un mismo training deben sumar 100.
    -- Ej: examen parcial 40% + examen final 60%

    score_type      VARCHAR(20)  NOT NULL DEFAULT 'percentage',
    -- percentage | integer | pass_fail
    max_score       NUMERIC(6,2) NOT NULL DEFAULT 100,
    passing_score   NUMERIC(6,2) NOT NULL DEFAULT 70,

    attempts_allowed INTEGER     NOT NULL DEFAULT 1,
    -- 0 = ilimitado

    instructions    TEXT,

    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ──────────────────────────────────────────────────────────────
-- 4. Tabla: hr.assessment_results
-- ──────────────────────────────────────────────────────────────
CREATE TABLE hr.assessment_results (
    id                     BIGSERIAL    PRIMARY KEY,
    assessment_id          BIGINT       NOT NULL REFERENCES hr.training_assessments(id) ON DELETE RESTRICT,
    training_id            BIGINT       NOT NULL REFERENCES hr.trainings(id)            ON DELETE RESTRICT,
    employee_id            BIGINT       NOT NULL REFERENCES hr.employees(id)            ON DELETE RESTRICT,
    company_id             BIGINT       NOT NULL REFERENCES hr.companies(id)            ON DELETE RESTRICT,

    attempt_number         SMALLINT     NOT NULL DEFAULT 1,

    score                  NUMERIC(6,2),

    -- Snapshot del passing_score y max_score al momento de rendir (garantiza inmutabilidad histórica)
    passing_score_snapshot NUMERIC(6,2) NOT NULL,
    max_score_snapshot     NUMERIC(6,2) NOT NULL,

    passed                 BOOLEAN      GENERATED ALWAYS AS (
                               score IS NOT NULL AND score >= passing_score_snapshot
                           ) STORED,

    score_pct              NUMERIC(5,2) GENERATED ALWAYS AS (
                               CASE WHEN max_score_snapshot > 0
                                    THEN ROUND(score / max_score_snapshot * 100, 2)
                                    ELSE NULL END
                           ) STORED,
    -- % sobre el máximo, independientemente del score_type

    started_at             TIMESTAMPTZ,
    submitted_at           TIMESTAMPTZ,
    duration_min           INTEGER      GENERATED ALWAYS AS (
                               CASE WHEN started_at IS NOT NULL AND submitted_at IS NOT NULL
                                    THEN EXTRACT(EPOCH FROM (submitted_at - started_at))::INTEGER / 60
                                    ELSE NULL END
                           ) STORED,

    evaluated_by           BIGINT       REFERENCES hr.employees(id),
    -- NULL si fue auto-corregido

    feedback               TEXT,

    created_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW()
    -- INMUTABLE: cada intento es un registro permanente; sin updated_at
);

-- ──────────────────────────────────────────────────────────────
-- 5. Vista: hr.training_summary_view
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW hr.training_summary_view AS
SELECT
    tp.id                                               AS participant_id,
    tp.employee_id,
    tp.training_id,
    t.name                                              AS training_name,
    t.score_type,
    tp.score,
    t.max_score,
    t.passing_score,
    tp.passed,
    tp.status,
    tp.certificate_url,
    CASE
        WHEN tp.status = 'cancelled'
            THEN 'Cancelado'
        WHEN tp.passed IS TRUE
            THEN 'Aprobado (' || tp.score::TEXT || '/' || t.max_score::TEXT || ')'
        WHEN tp.passed IS FALSE AND tp.score IS NOT NULL
            THEN 'Reprobado (' || tp.score::TEXT || '/' || t.max_score::TEXT || ')'
        ELSE 'Pendiente'
    END                                                 AS result_label
FROM hr.training_participants tp
JOIN hr.trainings t ON t.id = tp.training_id;

-- ──────────────────────────────────────────────────────────────
-- 6. Índices
-- ──────────────────────────────────────────────────────────────
CREATE INDEX        idx_training_assessments_training
    ON hr.training_assessments (training_id);
CREATE UNIQUE INDEX idx_training_assessments_name
    ON hr.training_assessments (training_id, name);

CREATE INDEX        idx_assessment_results_assessment
    ON hr.assessment_results (assessment_id);
CREATE INDEX        idx_assessment_results_employee
    ON hr.assessment_results (employee_id);
CREATE INDEX        idx_assessment_results_training
    ON hr.assessment_results (training_id);
CREATE UNIQUE INDEX idx_assessment_results_unique
    ON hr.assessment_results (assessment_id, employee_id, attempt_number);

-- ──────────────────────────────────────────────────────────────
-- 7. Triggers
-- ──────────────────────────────────────────────────────────────

-- training_assessments: updated_at
CREATE TRIGGER trg_training_assessments_updated_at
    BEFORE UPDATE ON hr.training_assessments
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

-- training_participants: auto-calcular passed y status a partir del puntaje
CREATE TRIGGER trg_training_participants_compute_passed
    BEFORE INSERT OR UPDATE ON hr.training_participants
    FOR EACH ROW EXECUTE FUNCTION hr.compute_training_passed();

-- ──────────────────────────────────────────────────────────────
-- 8. Comentarios
-- ──────────────────────────────────────────────────────────────
COMMENT ON TABLE  hr.training_assessments
    IS 'Evaluaciones formales multicomponente de cada capacitación (examen, quiz, práctica).';
COMMENT ON COLUMN hr.training_assessments.assessment_type
    IS 'exam | quiz | practical | observation | simulation';
COMMENT ON COLUMN hr.training_assessments.weight_pct
    IS '% del puntaje total. Las evaluaciones de un mismo training deben sumar 100.';
COMMENT ON COLUMN hr.training_assessments.score_type
    IS 'percentage | integer | pass_fail';
COMMENT ON COLUMN hr.training_assessments.attempts_allowed
    IS 'Número máximo de intentos permitidos. 0 = ilimitado.';

COMMENT ON TABLE  hr.assessment_results
    IS 'Resultados individuales por empleado, evaluación e intento. Registro inmutable.';
COMMENT ON COLUMN hr.assessment_results.attempt_number
    IS 'Número de intento (1, 2, 3...). Único con assessment_id + employee_id.';
COMMENT ON COLUMN hr.assessment_results.passing_score_snapshot
    IS 'Snapshot del passing_score al momento de rendir. Garantiza inmutabilidad histórica.';
COMMENT ON COLUMN hr.assessment_results.max_score_snapshot
    IS 'Snapshot del max_score al momento de rendir.';
COMMENT ON COLUMN hr.assessment_results.passed
    IS 'Generado: TRUE si score IS NOT NULL AND score >= passing_score_snapshot.';
COMMENT ON COLUMN hr.assessment_results.score_pct
    IS 'Generado: % del puntaje sobre el máximo, independientemente del score_type.';
COMMENT ON COLUMN hr.assessment_results.duration_min
    IS 'Generado: duración en minutos entre started_at y submitted_at.';
COMMENT ON COLUMN hr.assessment_results.evaluated_by
    IS 'Empleado evaluador. NULL si fue auto-corregido.';

COMMENT ON VIEW   hr.training_summary_view
    IS 'Resumen por empleado y capacitación: puntaje, resultado y etiqueta legible.';
