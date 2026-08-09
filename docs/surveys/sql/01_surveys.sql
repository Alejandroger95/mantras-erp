-- ============================================================
-- mantrasdb | Módulo Surveys
-- Archivo: 01_surveys.sql
-- Descripción: Encuestas de Satisfacción al Cliente
--
-- Schema genérico: funciona con Services (citas), Sales
-- (órdenes de venta) y Projects (proyectos completados).
--
-- Tablas:
--   1. survey_templates       — Plantillas de encuesta
--   2. survey_questions       — Preguntas del template
--   3. survey_question_options — Opciones para multiple_choice
-- ============================================================

CREATE SCHEMA IF NOT EXISTS surveys;

-- ============================================================
-- Función set_updated_at compartida del módulo
-- ============================================================
CREATE OR REPLACE FUNCTION surveys.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- ============================================================
-- 1. SURVEY_TEMPLATES — Plantillas de encuesta
--    Una empresa puede tener múltiples templates:
--    uno para citas, otro para proyectos, otro genérico.
-- ============================================================
CREATE TABLE surveys.survey_templates (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    name                VARCHAR(200) NOT NULL,
    -- Ej: "Encuesta post-cita", "NPS trimestral", "Satisfacción proyecto"

    description         TEXT,

    -- ── Evento que dispara el envío ───────────────────────────
    trigger_entity      VARCHAR(30)  NOT NULL DEFAULT 'any',
    -- any           : envío manual o desde cualquier módulo
    -- appointment   : al completar una cita (services)
    -- sales_order   : al completar/entregar una orden de venta
    -- project       : al cerrar un proyecto
    -- invoice       : al pagar una factura
    -- manual        : solo envío manual (campañas, NPS periódico)

    -- ── Canal de envío por defecto ────────────────────────────
    default_channel     VARCHAR(20)  NOT NULL DEFAULT 'whatsapp',
    -- whatsapp / email / sms / online / pos

    -- Minutos después del evento para enviar (0 = inmediato)
    send_delay_min      INTEGER      NOT NULL DEFAULT 60,

    -- ── Contenido ────────────────────────────────────────────
    intro_text          TEXT,
    -- Mensaje de bienvenida. Ej: "Hola {nombre}, ¿cómo fue tu visita?"

    outro_text          TEXT,
    -- Mensaje de cierre. Ej: "¡Gracias! Tu opinión nos ayuda a mejorar."

    -- ── Configuración ─────────────────────────────────────────
    language            VARCHAR(10)  NOT NULL DEFAULT 'es',

    -- Días de vigencia del link antes de expirar
    link_expiry_days    SMALLINT     NOT NULL DEFAULT 7,

    -- Número máximo de recordatorios si no responde
    max_reminders       SMALLINT     NOT NULL DEFAULT 2,

    -- Horas entre recordatorios
    reminder_interval_h SMALLINT     NOT NULL DEFAULT 24,

    -- ── Estado ───────────────────────────────────────────────
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE,

    -- Versión simple del template
    version             SMALLINT     NOT NULL DEFAULT 1,

    created_by          BIGINT       REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_tmpl_company ON surveys.survey_templates (company_id, is_active);
CREATE INDEX idx_tmpl_trigger ON surveys.survey_templates (trigger_entity);

CREATE TRIGGER trg_tmpl_updated_at
    BEFORE UPDATE ON surveys.survey_templates
    FOR EACH ROW EXECUTE FUNCTION surveys.set_updated_at();

COMMENT ON TABLE surveys.survey_templates IS
'Plantilla de encuesta. Define el evento disparador, canal de envío, textos y comportamiento de recordatorios.';

-- ============================================================
-- 2. SURVEY_QUESTIONS — Preguntas del template
--    Soporta NPS, CSAT, escala, texto libre, opción múltiple
--    y booleano (sí/no). Las preguntas se muestran en orden.
-- ============================================================
CREATE TABLE surveys.survey_questions (
    id                  BIGSERIAL   PRIMARY KEY,
    template_id         BIGINT      NOT NULL REFERENCES surveys.survey_templates(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    sort_order          SMALLINT    NOT NULL DEFAULT 1,
    -- Orden de aparición dentro del template

    question_text       TEXT        NOT NULL,
    -- Ej: "¿Qué tan probable es que nos recomiendes a un amigo?"

    -- ── Tipo de pregunta ──────────────────────────────────────
    question_type       VARCHAR(20) NOT NULL DEFAULT 'csat',
    -- nps             : escala 0-10 (Net Promoter Score)
    -- csat            : escala 1-5 estrellas (Customer Satisfaction)
    -- ces             : escala 1-7 (Customer Effort Score)
    -- scale           : escala numérica configurable (scale_min–scale_max)
    -- text            : respuesta de texto libre
    -- multiple_choice : opciones predefinidas (ver survey_question_options)
    -- boolean         : sí / no

    -- ── Parámetros para preguntas de escala ───────────────────
    scale_min           SMALLINT,
    -- Por defecto según tipo: NPS=0, CSAT=1, CES=1
    -- NULL para text, multiple_choice y boolean

    scale_max           SMALLINT,
    -- Por defecto: NPS=10, CSAT=5, CES=7

    scale_min_label     VARCHAR(100),
    -- Etiqueta extremo inferior. Ej: "Nada probable", "Muy difícil"

    scale_max_label     VARCHAR(100),
    -- Etiqueta extremo superior. Ej: "Muy probable", "Muy fácil"

    -- ── Comportamiento ────────────────────────────────────────
    is_required         BOOLEAN     NOT NULL DEFAULT TRUE,

    -- Lógica condicional: mostrar esta pregunta SOLO SI
    -- la pregunta anterior tiene score <= show_if_score_max
    -- (útil para pedir motivo solo a detractores NPS < 7)
    show_if_question_id BIGINT      REFERENCES surveys.survey_questions(id),
    show_if_score_max   SMALLINT,
    -- Ej: show_if_question_id = (id de NPS), show_if_score_max = 6
    --     → esta pregunta aparece solo si NPS ≤ 6

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sq_template ON surveys.survey_questions (template_id, sort_order);

CREATE TRIGGER trg_sq_updated_at
    BEFORE UPDATE ON surveys.survey_questions
    FOR EACH ROW EXECUTE FUNCTION surveys.set_updated_at();

COMMENT ON TABLE surveys.survey_questions IS
'Preguntas de una encuesta. Soporta NPS, CSAT, CES, escala, texto libre, opción múltiple y sí/no. Permite lógica condicional básica.';

-- ============================================================
-- 3. SURVEY_QUESTION_OPTIONS — Opciones para multiple_choice
--    Solo aplica a preguntas de tipo multiple_choice.
--    Ej: "¿Por qué no nos recomendarías?"
--        1. El precio es muy alto
--        2. El tiempo de espera fue largo
--        3. No quedé satisfecho con el servicio
--        4. Otro
-- ============================================================
CREATE TABLE surveys.survey_question_options (
    id                  BIGSERIAL   PRIMARY KEY,
    question_id         BIGINT      NOT NULL REFERENCES surveys.survey_questions(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    sort_order          SMALLINT    NOT NULL DEFAULT 1,

    option_text         VARCHAR(300) NOT NULL,
    -- Texto visible al cliente

    option_value        VARCHAR(100),
    -- Valor interno para reportes (si NULL, se usa option_text)
    -- Ej: 'price', 'wait_time', 'service_quality', 'other'

    -- ¿Esta opción habilita un campo de texto libre?
    allows_text_input   BOOLEAN     NOT NULL DEFAULT FALSE,
    -- Ej: opción "Otro (especifica):" → muestra un input de texto

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);

CREATE INDEX idx_sqo_question ON surveys.survey_question_options (question_id, sort_order);

COMMENT ON TABLE surveys.survey_question_options IS
'Opciones de respuesta para preguntas de tipo multiple_choice. Permite "Otro" con campo de texto libre.';
