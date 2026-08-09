-- ============================================================
-- mantrasdb | Módulo CRM
-- Archivo: 01_crm.sql
-- Descripción: Customer Relationship Management
--
-- Tablas:
--   1. pipelines           — Embudos de venta
--   2. pipeline_stages     — Etapas del embudo
--   3. leads               — Prospectos sin calificar
--   4. opportunities       — Oportunidades calificadas
--   5. opportunity_contacts— Contactos vinculados a oportunidad
--   6. crm_activities      — Llamadas, emails, reuniones, tareas
--
-- Vistas:
--   crm.pipeline_view      — Estado actual de cada pipeline
--   crm.sales_funnel_view  — Conversión por etapa
-- ============================================================

CREATE SCHEMA IF NOT EXISTS crm;

CREATE OR REPLACE FUNCTION crm.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

-- ============================================================
-- 1. PIPELINES — Embudos de venta
-- ============================================================
CREATE TABLE crm.pipelines (
    id              BIGSERIAL   PRIMARY KEY,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id),
    name            VARCHAR(100) NOT NULL,
    -- Ej: "Ventas B2B", "Proyectos TI", "Servicios"
    description     TEXT,
    is_default      BOOLEAN     NOT NULL DEFAULT FALSE,
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_by      BIGINT      REFERENCES hr.system_users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TRIGGER trg_pipeline_upd BEFORE UPDATE ON crm.pipelines
    FOR EACH ROW EXECUTE FUNCTION crm.set_updated_at();

-- ============================================================
-- 2. PIPELINE_STAGES — Etapas del embudo
-- ============================================================
CREATE TABLE crm.pipeline_stages (
    id              BIGSERIAL   PRIMARY KEY,
    pipeline_id     BIGINT      NOT NULL REFERENCES crm.pipelines(id) ON DELETE CASCADE,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id),
    name            VARCHAR(100) NOT NULL,
    -- Ej: "Contacto inicial", "Demo", "Propuesta", "Negociación", "Cerrado"
    sort_order      SMALLINT    NOT NULL DEFAULT 1,
    probability_pct NUMERIC(5,2) NOT NULL DEFAULT 0,
    -- Probabilidad de cierre en esta etapa (0-100)
    stage_type      VARCHAR(20) NOT NULL DEFAULT 'open',
    -- open / won / lost
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_stages_pipeline ON crm.pipeline_stages (pipeline_id, sort_order);
CREATE TRIGGER trg_stage_upd BEFORE UPDATE ON crm.pipeline_stages
    FOR EACH ROW EXECUTE FUNCTION crm.set_updated_at();

-- ============================================================
-- 3. LEADS — Prospectos (aún sin calificar)
-- ============================================================
CREATE TABLE crm.leads (
    id              BIGSERIAL   PRIMARY KEY,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Datos del prospecto
    name            VARCHAR(300) NOT NULL,
    -- Nombre de la empresa o persona
    contact_name    VARCHAR(200),
    email           VARCHAR(200),
    phone           VARCHAR(30),
    website         VARCHAR(200),

    -- Origen del lead
    source          VARCHAR(30) NOT NULL DEFAULT 'manual',
    -- manual / web_form / referral / social / email_campaign /
    -- cold_call / event / whatsapp / organic

    -- Sector / industria
    industry        VARCHAR(100),

    -- Asignado a
    assigned_to_id  BIGINT      REFERENCES hr.employees(id),

    -- Puntuación (0-100, calculada o manual)
    lead_score      SMALLINT    NOT NULL DEFAULT 0,

    -- Estado
    status          VARCHAR(20) NOT NULL DEFAULT 'new',
    -- new / contacted / qualified / disqualified / converted

    disqualify_reason VARCHAR(200),

    -- Al convertir el lead → se crea una opportunity
    converted_to_opportunity_id BIGINT,
    -- REFERENCES crm.opportunities(id) — FK circular, se agrega abajo

    converted_at    TIMESTAMPTZ,

    notes           TEXT,

    created_by      BIGINT      REFERENCES hr.system_users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_lead_company  ON crm.leads (company_id, status);
CREATE INDEX idx_lead_assigned ON crm.leads (assigned_to_id);
CREATE TRIGGER trg_lead_upd BEFORE UPDATE ON crm.leads
    FOR EACH ROW EXECUTE FUNCTION crm.set_updated_at();

-- ============================================================
-- 4. OPPORTUNITIES — Oportunidades calificadas en pipeline
-- ============================================================
CREATE TABLE crm.opportunities (
    id              BIGSERIAL   PRIMARY KEY,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id),

    name            VARCHAR(300) NOT NULL,
    -- Ej: "Implementación ERP - Empresa XYZ"

    -- Referencia al cliente (si ya existe en Sales)
    customer_id     BIGINT      REFERENCES sales.customers(id),

    -- Empresa/contacto si no es cliente aún
    prospect_name   VARCHAR(300),
    contact_name    VARCHAR(200),
    contact_email   VARCHAR(200),
    contact_phone   VARCHAR(30),

    -- Pipeline y etapa actual
    pipeline_id     BIGINT      NOT NULL REFERENCES crm.pipelines(id),
    stage_id        BIGINT      NOT NULL REFERENCES crm.pipeline_stages(id),

    -- Vendedor responsable
    assigned_to_id  BIGINT      REFERENCES hr.employees(id),

    -- Valor esperado
    expected_revenue NUMERIC(18,4),
    currency        VARCHAR(3)  NOT NULL DEFAULT 'PEN',

    -- Probabilidad (heredada del stage, ajustable manualmente)
    probability_pct NUMERIC(5,2) NOT NULL DEFAULT 0,

    -- Valor ponderado: expected_revenue * probability_pct / 100
    weighted_revenue NUMERIC(18,4) GENERATED ALWAYS AS (
        ROUND(expected_revenue * probability_pct / 100, 4)
    ) STORED,

    -- Fechas
    expected_close_date DATE,
    actual_close_date   DATE,

    -- Estado
    status          VARCHAR(20) NOT NULL DEFAULT 'open',
    -- open / won / lost / on_hold

    lost_reason     VARCHAR(200),

    -- Origen (del lead o directo)
    source          VARCHAR(30),
    lead_id         BIGINT      REFERENCES crm.leads(id),

    -- Referencia a cotización/orden generada al ganar
    quotation_id    BIGINT      REFERENCES sales.quotations(id),
    sales_order_id  BIGINT      REFERENCES sales.sales_orders(id),

    notes           TEXT,
    next_action     VARCHAR(300),
    next_action_date DATE,

    created_by      BIGINT      REFERENCES hr.system_users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_opp_company   ON crm.opportunities (company_id, status);
CREATE INDEX idx_opp_pipeline  ON crm.opportunities (pipeline_id, stage_id);
CREATE INDEX idx_opp_assigned  ON crm.opportunities (assigned_to_id);
CREATE INDEX idx_opp_customer  ON crm.opportunities (customer_id);
CREATE TRIGGER trg_opp_upd BEFORE UPDATE ON crm.opportunities
    FOR EACH ROW EXECUTE FUNCTION crm.set_updated_at();

-- FK circular leads → opportunities (ahora que opportunities existe)
ALTER TABLE crm.leads
    ADD CONSTRAINT fk_lead_converted_opp
        FOREIGN KEY (converted_to_opportunity_id)
        REFERENCES crm.opportunities(id);

-- ============================================================
-- 5. OPPORTUNITY_CONTACTS — Contactos vinculados a oportunidad
--    Una oportunidad puede tener múltiples interlocutores.
-- ============================================================
CREATE TABLE crm.opportunity_contacts (
    id              BIGSERIAL   PRIMARY KEY,
    opportunity_id  BIGINT      NOT NULL REFERENCES crm.opportunities(id) ON DELETE CASCADE,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Contacto en nuestro sistema (si existe)
    customer_contact_id BIGINT  REFERENCES sales.customer_contacts(id),

    -- O datos directos si no está en el sistema
    contact_name    VARCHAR(200),
    contact_title   VARCHAR(100),
    -- Ej: "Gerente de TI", "CFO"
    email           VARCHAR(200),
    phone           VARCHAR(30),

    role            VARCHAR(100),
    -- Rol en la decisión: "Decision maker" / "Influencer" / "End user" / "Gatekeeper"

    is_primary      BOOLEAN     NOT NULL DEFAULT FALSE,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);
CREATE INDEX idx_opp_contacts ON crm.opportunity_contacts (opportunity_id);

-- ============================================================
-- 6. CRM_ACTIVITIES — Actividades (llamadas, emails, reuniones)
-- ============================================================
CREATE TABLE crm.crm_activities (
    id              BIGSERIAL   PRIMARY KEY,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id),

    activity_type   VARCHAR(20) NOT NULL DEFAULT 'task',
    -- call / email / meeting / demo / task / whatsapp / note

    subject         VARCHAR(300) NOT NULL,
    description     TEXT,

    -- Entidad relacionada (polimórfico)
    related_to      VARCHAR(20),
    -- lead / opportunity
    lead_id         BIGINT      REFERENCES crm.leads(id),
    opportunity_id  BIGINT      REFERENCES crm.opportunities(id),

    -- Responsable
    assigned_to_id  BIGINT      REFERENCES hr.employees(id),

    -- Fechas
    scheduled_at    TIMESTAMPTZ,
    done_at         TIMESTAMPTZ,

    -- Estado
    status          VARCHAR(20) NOT NULL DEFAULT 'planned',
    -- planned / done / cancelled

    duration_min    SMALLINT,
    -- Para llamadas y reuniones

    outcome         TEXT,
    -- Resultado / notas post-actividad

    created_by      BIGINT      REFERENCES hr.system_users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_act_opp    ON crm.crm_activities (opportunity_id);
CREATE INDEX idx_act_lead   ON crm.crm_activities (lead_id);
CREATE INDEX idx_act_assign ON crm.crm_activities (assigned_to_id, status);
CREATE TRIGGER trg_act_upd BEFORE UPDATE ON crm.crm_activities
    FOR EACH ROW EXECUTE FUNCTION crm.set_updated_at();

-- ============================================================
-- VISTA 1: Pipeline — oportunidades por vendedor y etapa
-- ============================================================
CREATE OR REPLACE VIEW crm.pipeline_view AS
SELECT
    o.company_id,
    pl.name                                         AS pipeline_name,
    ps.name                                         AS stage_name,
    ps.sort_order                                   AS stage_order,
    ps.probability_pct                              AS stage_probability,

    COUNT(o.id)                                     AS opportunities,
    SUM(o.expected_revenue)                         AS total_expected,
    SUM(o.weighted_revenue)                         AS total_weighted,

    -- Por vendedor
    e.id                                            AS employee_id,
    per.first_name || ' ' || per.last_name          AS sales_rep,

    o.status
FROM crm.opportunities o
INNER JOIN crm.pipelines       pl  ON pl.id  = o.pipeline_id
INNER JOIN crm.pipeline_stages ps  ON ps.id  = o.stage_id
LEFT  JOIN hr.employees        e   ON e.id   = o.assigned_to_id
LEFT  JOIN hr.persons          per ON per.id = e.person_id
WHERE o.status = 'open'
GROUP BY o.company_id, pl.name, ps.name, ps.sort_order, ps.probability_pct,
         e.id, per.first_name, per.last_name, o.status
ORDER BY ps.sort_order;

COMMENT ON VIEW crm.pipeline_view IS
'Estado actual del pipeline: oportunidades abiertas por etapa y vendedor, con valor esperado y ponderado.';

-- ============================================================
-- VISTA 2: Embudo de ventas — conversión por etapa
-- ============================================================
CREATE OR REPLACE VIEW crm.sales_funnel_view AS
SELECT
    o.company_id,
    pl.id                                           AS pipeline_id,
    pl.name                                         AS pipeline_name,
    ps.id                                           AS stage_id,
    ps.name                                         AS stage_name,
    ps.sort_order,
    ps.probability_pct,

    COUNT(*) FILTER (WHERE o.status = 'open')       AS open_count,
    COUNT(*) FILTER (WHERE o.status = 'won')        AS won_count,
    COUNT(*) FILTER (WHERE o.status = 'lost')       AS lost_count,

    -- Tasa de conversión (won / total cerradas)
    ROUND(
        COUNT(*) FILTER (WHERE o.status = 'won')::NUMERIC /
        NULLIF(
            COUNT(*) FILTER (WHERE o.status IN ('won','lost')), 0
        ) * 100
    , 1)                                            AS win_rate_pct,

    SUM(o.expected_revenue) FILTER (WHERE o.status = 'won')
                                                    AS won_revenue,
    AVG(
        CASE WHEN o.status = 'won' AND o.actual_close_date IS NOT NULL
             THEN o.actual_close_date - o.created_at::DATE
        END
    )                                               AS avg_days_to_close

FROM crm.opportunities o
INNER JOIN crm.pipelines       pl ON pl.id = o.pipeline_id
INNER JOIN crm.pipeline_stages ps ON ps.id = o.stage_id
GROUP BY o.company_id, pl.id, pl.name, ps.id, ps.name, ps.sort_order, ps.probability_pct
ORDER BY ps.sort_order;

COMMENT ON VIEW crm.sales_funnel_view IS
'Embudo de ventas: conteo y tasa de conversión por etapa, incluyendo ingresos ganados y días promedio de cierre.';
