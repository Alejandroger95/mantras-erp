-- ============================================================
-- mantrasdb | Módulo Surveys
-- Archivo: 02_responses.sql
-- Descripción: Invitaciones, respuestas y vistas analíticas
--
-- Tablas:
--   4. survey_invitations      — Invitación enviada al cliente
--   5. survey_responses        — Respuesta (cabecera)
--   6. survey_response_answers — Respuesta por pregunta
--
-- Vistas:
--   surveys.nps_summary_view          — NPS por empresa/template/mes
--   surveys.csat_summary_view         — CSAT promedio por mes
--   surveys.response_detail_view      — Detalle completo de cada respuesta
--   surveys.pending_invitations_view  — Invitaciones sin respuesta
-- ============================================================

-- ============================================================
-- 4. SURVEY_INVITATIONS — Invitación enviada al cliente
--    Una invitación se crea automáticamente al completarse
--    el evento (cita, orden, proyecto) o manualmente.
--    El token único es el que va en el link de la encuesta.
-- ============================================================
CREATE TABLE surveys.survey_invitations (
    id                  BIGSERIAL   PRIMARY KEY,
    template_id         BIGINT      NOT NULL REFERENCES surveys.survey_templates(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    customer_id         BIGINT      NOT NULL REFERENCES sales.customers(id),

    -- ── Evento que disparó la invitación (polimórfico) ────────
    trigger_entity      VARCHAR(30),
    -- appointment / sales_order / project / invoice / manual

    trigger_entity_id   BIGINT,
    -- ID genérico del objeto (mismo valor que los campos de abajo)

    -- FK lógicas a cada módulo:
    appointment_id      BIGINT,
    -- REFERENCES services.appointments(id) — FK diferida;
    -- se agrega vía ALTER TABLE al final de este archivo
    -- (surveys carga después de services, pero por claridad se documenta aquí)

    sales_order_id      BIGINT      REFERENCES sales.sales_orders(id),

    project_id          BIGINT,
    -- REFERENCES projects.projects(id) — FK diferida
    -- (se mantiene como BIGINT plain; ambos schemas cargan antes de surveys)

    invoice_id          BIGINT      REFERENCES sales.invoices(id),

    -- ── Canal de entrega ─────────────────────────────────────
    channel             VARCHAR(20) NOT NULL DEFAULT 'whatsapp',
    -- whatsapp / email / sms / online / pos

    -- ── Token único para el link ─────────────────────────────
    token               VARCHAR(100) NOT NULL,
    -- Generado por la app (UUID o token aleatorio de 64 chars)
    -- Se usa en: https://dominio.com/survey/{token}

    -- ── Estado de la invitación ───────────────────────────────
    status              VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending     : pendiente de envío (en cola)
    -- sent        : enviado al cliente
    -- opened      : el cliente abrió el link
    -- completed   : respondió la encuesta
    -- expired     : venció el link sin respuesta
    -- bounced     : error de entrega (número inválido, etc.)
    -- opted_out   : el cliente no desea recibir encuestas

    sent_at             TIMESTAMPTZ,
    opened_at           TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,

    expires_at          TIMESTAMPTZ,
    -- Calculado al crear: NOW() + template.link_expiry_days * INTERVAL '1 day'

    -- ── Recordatorios ────────────────────────────────────────
    reminders_sent      SMALLINT    NOT NULL DEFAULT 0,
    last_reminder_at    TIMESTAMPTZ,

    -- ── Metadata de entrega ───────────────────────────────────
    delivery_status     VARCHAR(20),
    -- sent / delivered / read / failed (según respuesta del proveedor)

    external_message_id VARCHAR(200),
    -- ID del mensaje en WhatsApp Business API, SendGrid, etc.

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX uq_survey_token
    ON surveys.survey_invitations (token);
CREATE INDEX idx_inv_customer
    ON surveys.survey_invitations (customer_id);
CREATE INDEX idx_inv_template
    ON surveys.survey_invitations (template_id);
CREATE INDEX idx_inv_status
    ON surveys.survey_invitations (status);
CREATE INDEX idx_inv_appointment
    ON surveys.survey_invitations (appointment_id)
    WHERE appointment_id IS NOT NULL;
CREATE INDEX idx_inv_sales_order
    ON surveys.survey_invitations (sales_order_id)
    WHERE sales_order_id IS NOT NULL;
CREATE INDEX idx_inv_project
    ON surveys.survey_invitations (project_id)
    WHERE project_id IS NOT NULL;

CREATE TRIGGER trg_inv_updated_at
    BEFORE UPDATE ON surveys.survey_invitations
    FOR EACH ROW EXECUTE FUNCTION surveys.set_updated_at();

COMMENT ON TABLE surveys.survey_invitations IS
'Invitación de encuesta enviada al cliente. Cada invitación tiene un token único para el link. Se vincula al evento que la disparó (cita, orden, proyecto).';

-- ============================================================
-- 5. SURVEY_RESPONSES — Respuesta del cliente (cabecera)
--    Una por invitación. Contiene los scores resumen (NPS,
--    CSAT) desnormalizados para facilitar los dashboards.
--    Las respuestas detalladas van en survey_response_answers.
-- ============================================================
CREATE TABLE surveys.survey_responses (
    id                  BIGSERIAL   PRIMARY KEY,
    invitation_id       BIGINT      NOT NULL REFERENCES surveys.survey_invitations(id),
    template_id         BIGINT      NOT NULL REFERENCES surveys.survey_templates(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),
    customer_id         BIGINT      NOT NULL REFERENCES sales.customers(id),

    -- ── Canal de respuesta ────────────────────────────────────
    response_channel    VARCHAR(20) NOT NULL DEFAULT 'online',
    -- online / pos / whatsapp / email / agent (capturado por un agente)

    -- ── Tiempos ───────────────────────────────────────────────
    started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at        TIMESTAMPTZ,

    duration_sec        INTEGER     GENERATED ALWAYS AS (
        CASE WHEN completed_at IS NOT NULL
             THEN EXTRACT(EPOCH FROM (completed_at - started_at))::INTEGER
             ELSE NULL END
    ) STORED,

    is_complete         BOOLEAN     NOT NULL DEFAULT FALSE,

    -- ── Scores resumen (desnormalizados) ──────────────────────
    -- Se actualizan al guardar las respuestas individuales.

    nps_score           SMALLINT,
    -- 0-10, NULL si no hay pregunta NPS en el template
    -- CONSTRAINT: CHECK (nps_score BETWEEN 0 AND 10)

    nps_category        VARCHAR(20) GENERATED ALWAYS AS (
        CASE
            WHEN nps_score >= 9 THEN 'promoter'
            WHEN nps_score >= 7 THEN 'passive'
            WHEN nps_score >= 0 THEN 'detractor'
            ELSE NULL
        END
    ) STORED,
    -- promoter  : NPS 9-10 → clientes leales
    -- passive   : NPS 7-8  → satisfechos pero vulnerables
    -- detractor : NPS 0-6  → clientes insatisfechos

    csat_avg            NUMERIC(4,2),
    -- Promedio de todas las preguntas CSAT (1.00-5.00)

    -- ── Metadata del respondiente ─────────────────────────────
    ip_address          INET,
    user_agent          VARCHAR(500),
    -- Para detectar respuestas duplicadas o fraudulentas

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- INMUTABLE: los cambios se hacen en survey_response_answers

    CONSTRAINT chk_nps_range  CHECK (nps_score IS NULL OR nps_score BETWEEN 0 AND 10),
    CONSTRAINT chk_csat_range CHECK (csat_avg  IS NULL OR csat_avg  BETWEEN 1 AND 5)
);

CREATE INDEX idx_resp_invitation ON surveys.survey_responses (invitation_id);
CREATE INDEX idx_resp_customer   ON surveys.survey_responses (customer_id);
CREATE INDEX idx_resp_template   ON surveys.survey_responses (template_id, company_id);
CREATE INDEX idx_resp_nps        ON surveys.survey_responses (nps_score)
    WHERE nps_score IS NOT NULL;
CREATE INDEX idx_resp_created    ON surveys.survey_responses (created_at);

COMMENT ON TABLE surveys.survey_responses IS
'Cabecera de la respuesta del cliente. Contiene NPS y CSAT desnormalizados para dashboards. El detalle por pregunta va en survey_response_answers.';

-- ============================================================
-- 6. SURVEY_RESPONSE_ANSWERS — Respuesta por pregunta
--    Una fila por pregunta respondida.
--    INMUTABLE: los datos de respuesta no se modifican.
-- ============================================================
CREATE TABLE surveys.survey_response_answers (
    id                  BIGSERIAL   PRIMARY KEY,
    response_id         BIGINT      NOT NULL REFERENCES surveys.survey_responses(id) ON DELETE CASCADE,
    question_id         BIGINT      NOT NULL REFERENCES surveys.survey_questions(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- ── Respuesta según tipo de pregunta ──────────────────────

    -- Para NPS, CSAT, CES, scale → score numérico
    score               SMALLINT,

    -- Para text → respuesta libre
    text_answer         TEXT,

    -- Para multiple_choice → opción seleccionada
    selected_option_id  BIGINT      REFERENCES surveys.survey_question_options(id),

    -- Texto libre adicional (cuando la opción permite texto, ej: "Otro: ___")
    option_text_input   VARCHAR(500),

    -- Para boolean → sí/no
    bool_answer         BOOLEAN,

    -- ── Metadata ──────────────────────────────────────────────
    answered_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);

CREATE INDEX idx_ans_response  ON surveys.survey_response_answers (response_id);
CREATE INDEX idx_ans_question  ON surveys.survey_response_answers (question_id);

COMMENT ON TABLE surveys.survey_response_answers IS
'Respuesta individual por pregunta. Soporta score numérico (NPS/CSAT/escala), texto libre, opción múltiple y booleano. Inmutable.';

-- ============================================================
-- FK diferidas (surveys carga después de services y projects)
-- ============================================================

-- survey_invitations.appointment_id → services.appointments(id)
ALTER TABLE surveys.survey_invitations
    ADD CONSTRAINT fk_inv_appointment
        FOREIGN KEY (appointment_id)
        REFERENCES services.appointments(id);

-- survey_invitations.project_id → projects.projects(id)
ALTER TABLE surveys.survey_invitations
    ADD CONSTRAINT fk_inv_project
        FOREIGN KEY (project_id)
        REFERENCES projects.projects(id);

-- ============================================================
-- VISTA 1: NPS por empresa, template y mes
-- ============================================================
CREATE OR REPLACE VIEW surveys.nps_summary_view AS
SELECT
    sr.company_id,
    sr.template_id,
    st.name                                                     AS template_name,
    DATE_TRUNC('month', sr.created_at)::DATE                    AS month,

    COUNT(*)                                                    AS total_responses,
    COUNT(*) FILTER (WHERE sr.nps_category = 'promoter')        AS promoters,
    COUNT(*) FILTER (WHERE sr.nps_category = 'passive')         AS passives,
    COUNT(*) FILTER (WHERE sr.nps_category = 'detractor')       AS detractors,

    -- NPS = % promotores − % detractores (rango: −100 a +100)
    ROUND(
        (
            COUNT(*) FILTER (WHERE sr.nps_category = 'promoter')::NUMERIC -
            COUNT(*) FILTER (WHERE sr.nps_category = 'detractor')::NUMERIC
        ) / NULLIF(COUNT(*), 0) * 100
    , 1)                                                        AS nps_score,

    ROUND(AVG(sr.nps_score), 2)                                 AS avg_nps_raw

FROM surveys.survey_responses sr
INNER JOIN surveys.survey_templates st ON st.id = sr.template_id
WHERE sr.is_complete = TRUE
  AND sr.nps_score   IS NOT NULL
GROUP BY sr.company_id, sr.template_id, st.name,
         DATE_TRUNC('month', sr.created_at)::DATE
ORDER BY month DESC, nps_score DESC;

COMMENT ON VIEW surveys.nps_summary_view IS
'NPS por empresa, template y mes. NPS = %promotores − %detractores (rango −100 a +100).';

-- ============================================================
-- VISTA 2: CSAT promedio por template y mes
-- ============================================================
CREATE OR REPLACE VIEW surveys.csat_summary_view AS
SELECT
    sr.company_id,
    sr.template_id,
    st.name                                                     AS template_name,
    DATE_TRUNC('month', sr.created_at)::DATE                    AS month,

    COUNT(*)                                                    AS total_responses,
    ROUND(AVG(sr.csat_avg), 2)                                  AS csat_avg,

    -- % satisfechos (4-5 estrellas)
    ROUND(
        COUNT(*) FILTER (WHERE sr.csat_avg >= 4)::NUMERIC /
        NULLIF(COUNT(*), 0) * 100
    , 1)                                                        AS satisfied_pct,

    -- % insatisfechos (1-2 estrellas)
    ROUND(
        COUNT(*) FILTER (WHERE sr.csat_avg < 3)::NUMERIC /
        NULLIF(COUNT(*), 0) * 100
    , 1)                                                        AS unsatisfied_pct

FROM surveys.survey_responses sr
INNER JOIN surveys.survey_templates st ON st.id = sr.template_id
WHERE sr.is_complete = TRUE
  AND sr.csat_avg    IS NOT NULL
GROUP BY sr.company_id, sr.template_id, st.name,
         DATE_TRUNC('month', sr.created_at)::DATE
ORDER BY month DESC;

COMMENT ON VIEW surveys.csat_summary_view IS
'CSAT promedio por empresa, template y mes. Incluye % satisfechos (≥4 estrellas) e insatisfechos (<3 estrellas).';

-- ============================================================
-- VISTA 3: Detalle de cada respuesta con cliente y origen
-- ============================================================
CREATE OR REPLACE VIEW surveys.response_detail_view AS
SELECT
    sr.id                                                       AS response_id,
    sr.company_id,
    sr.created_at                                               AS responded_at,

    -- Cliente
    c.id                                                        AS customer_id,
    c.trade_name                                                AS customer_name,
    c.phone                                                     AS customer_phone,
    c.email                                                     AS customer_email,

    -- Template
    st.name                                                     AS template_name,
    st.trigger_entity,

    -- Evento origen
    si.trigger_entity                                           AS event_type,
    si.trigger_entity_id                                        AS event_id,
    si.appointment_id,
    si.sales_order_id,
    si.project_id,
    si.invoice_id,

    -- Canal
    si.channel                                                  AS invitation_channel,
    sr.response_channel,

    -- Scores
    sr.nps_score,
    sr.nps_category,
    sr.csat_avg,

    -- Tiempos
    si.sent_at,
    si.opened_at,
    sr.started_at,
    sr.completed_at,
    sr.duration_sec,
    sr.is_complete

FROM surveys.survey_responses    sr
INNER JOIN surveys.survey_invitations si ON si.id  = sr.invitation_id
INNER JOIN surveys.survey_templates   st ON st.id  = sr.template_id
INNER JOIN sales.customers            c  ON c.id   = sr.customer_id
ORDER BY sr.created_at DESC;

COMMENT ON VIEW surveys.response_detail_view IS
'Vista detalle: cada respuesta con cliente, canal, evento de origen, NPS, CSAT y tiempos. Base para exportes y análisis cualitativos.';

-- ============================================================
-- VISTA 4: Invitaciones pendientes de respuesta
--    Para seguimiento y reenvío de recordatorios
-- ============================================================
CREATE OR REPLACE VIEW surveys.pending_invitations_view AS
SELECT
    si.id                                                       AS invitation_id,
    si.company_id,
    si.customer_id,
    c.trade_name                                                AS customer_name,
    c.phone,
    c.email,

    st.name                                                     AS template_name,
    st.max_reminders,

    si.channel,
    si.status,
    si.sent_at,
    si.expires_at,
    si.reminders_sent,
    si.last_reminder_at,
    si.delivery_status,

    -- Tiempo transcurrido desde el envío
    EXTRACT(EPOCH FROM (NOW() - si.sent_at)) / 3600             AS hours_since_sent,

    -- ¿Puede recibir otro recordatorio?
    CASE
        WHEN si.reminders_sent < st.max_reminders
         AND (si.last_reminder_at IS NULL
              OR NOW() > si.last_reminder_at + (st.reminder_interval_h || ' hours')::INTERVAL)
        THEN TRUE
        ELSE FALSE
    END                                                         AS can_send_reminder,

    si.trigger_entity,
    si.trigger_entity_id,
    si.appointment_id,
    si.sales_order_id,
    si.project_id

FROM surveys.survey_invitations  si
INNER JOIN surveys.survey_templates st ON st.id  = si.template_id
INNER JOIN sales.customers          c  ON c.id   = si.customer_id
WHERE si.status IN ('sent', 'opened')
  AND (si.expires_at IS NULL OR si.expires_at > NOW())
ORDER BY si.sent_at ASC;

COMMENT ON VIEW surveys.pending_invitations_view IS
'Invitaciones enviadas sin respuesta aún. Incluye señal can_send_reminder para automatizar recordatorios.';
