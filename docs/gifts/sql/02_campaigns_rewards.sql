-- ============================================================
-- mantrasdb | Módulo Gifts
-- Archivo: 02_campaigns_rewards.sql
-- Descripción: Campañas de premios (concursos redes sociales,
--              sorteos, promotions) y reconocimientos al personal
--              (empleada del mes, canasta navideña, bono por meta).
--
-- Tablas:
--   3. prize_campaigns      — Campaña / concurso / sorteo
--   4. campaign_prizes      — Premios disponibles en la campaña
--   5. prize_winners        — Ganadoras y estado del canje
--   6. reward_programs      — Programas de reconocimiento al personal
--   7. employee_rewards     — Premio individual dado a una empleada
--
-- Vistas:
--   gifts.campaign_results_view      — Resultados y tasa de canje por campaña
--   gifts.employee_recognition_view  — Reconocimientos entregados por período
--
-- ALTER TABLE:
--   Completa FK gift_cards.campaign_id → prize_campaigns
-- ============================================================

-- ============================================================
-- 3. PRIZE_CAMPAIGNS — Campaña o concurso con premios
--    Ej: "Concurso Instagram Agosto 2026 — Gana tu tinte"
--        "Sorteo Aniversario — Pack completo de tratamiento"
--        "Cumpleañeras de Enero — 50% en tu próxima visita"
-- ============================================================
CREATE TABLE gifts.prize_campaigns (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    name                VARCHAR(200) NOT NULL,
    -- Ej: "Concurso Instagram — Tinte Gratis"

    description         TEXT,

    campaign_type       VARCHAR(25)  NOT NULL DEFAULT 'social_media',
    -- social_media    : concurso en Instagram, TikTok, Facebook
    -- in_store        : sorteo dentro del salón (urna, rifa)
    -- referral        : "trae a una amiga y gana"
    -- birthday        : regalo automático por cumpleaños
    -- seasonal        : campaña de temporada (Navidad, Día de la Madre)
    -- milestone       : por número de visitas (10ma visita = premio)
    -- satisfaction    : regalo por compensación o mala experiencia

    -- Plataforma (si es redes sociales)
    platform            VARCHAR(30),
    -- instagram / tiktok / facebook / whatsapp / in_person / all

    -- Mecánica del concurso (descripción libre)
    mechanics           TEXT,
    -- Ej: "Sigue nuestra cuenta, comenta y etiqueta a 2 amigas.
    --      La ganadora se anuncia el viernes 30 de agosto."

    -- Fechas de la campaña
    starts_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    ends_at             TIMESTAMPTZ,

    -- Fecha de anuncio de ganadoras
    announce_at         TIMESTAMPTZ,

    -- Total de ganadoras planificadas
    total_winners_planned INTEGER     NOT NULL DEFAULT 1,
    total_winners_actual  INTEGER     NOT NULL DEFAULT 0,

    -- Presupuesto de la campaña (costo de los premios)
    budget              NUMERIC(18,4),
    currency            VARCHAR(3)   NOT NULL DEFAULT 'PEN',

    -- Estado
    status              VARCHAR(20)  NOT NULL DEFAULT 'draft',
    -- draft / active / completed / cancelled

    -- Imagen/banner de la campaña (para mostrar en app o redes)
    banner_url          VARCHAR(500),

    -- Términos y condiciones
    terms_and_conditions TEXT,

    created_by          BIGINT      REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_campaign_company ON gifts.prize_campaigns (company_id, status, starts_at DESC);
CREATE TRIGGER trg_campaign_upd BEFORE UPDATE ON gifts.prize_campaigns
    FOR EACH ROW EXECUTE FUNCTION gifts.set_updated_at();
COMMENT ON TABLE gifts.prize_campaigns IS
'Campaña de premios: concurso de redes sociales, sorteo, campaña de cumpleañeras, referidos. Define mecánica, plataforma, fechas y presupuesto.';

-- FK diferida: gift_cards.campaign_id → prize_campaigns
ALTER TABLE gifts.gift_cards
    ADD CONSTRAINT fk_gc_campaign
    FOREIGN KEY (campaign_id) REFERENCES gifts.prize_campaigns(id);

-- ============================================================
-- 4. CAMPAIGN_PRIZES — Premios disponibles en una campaña
--    Una campaña puede tener varios tipos de premio:
--    Ej: 1er lugar = tinte + tratamiento, 2do = manicure gratis
-- ============================================================
CREATE TABLE gifts.campaign_prizes (
    id                  BIGSERIAL   PRIMARY KEY,
    campaign_id         BIGINT      NOT NULL REFERENCES gifts.prize_campaigns(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Nombre del premio
    name                VARCHAR(200) NOT NULL,
    -- Ej: "Tinte completo + tratamiento de keratina"
    --     "1 manicure gratis"
    --     "Gift card S/50"
    --     "Pack de productos Loreal"

    -- Tipo de premio
    prize_type          VARCHAR(20)  NOT NULL DEFAULT 'service_voucher',
    -- monetary_gift_card : gift card con saldo en dinero
    -- service_voucher    : vale por servicio específico
    -- product_bundle     : paquete de productos físicos
    -- discount_coupon    : descuento % en próxima visita
    -- experience         : experiencia (spa day, sesión VIP)
    -- custom             : premio personalizado (canasta, etc.)

    -- Para gift card monetaria
    gift_card_amount    NUMERIC(18,4),

    -- Para vale de servicio
    service_id          BIGINT      REFERENCES services.services(id),
    service_quantity    SMALLINT    NOT NULL DEFAULT 1,

    -- Para cupón de descuento
    discount_pct        NUMERIC(5,2),
    discount_valid_days SMALLINT,
    -- Cuántos días tiene para usarlo

    -- Para producto físico (descripción libre)
    product_description TEXT,
    -- Ej: "Kit Loreal: shampoo 500ml + acondicionador + mascarilla"

    -- Valor monetario estimado del premio (para presupuesto)
    estimated_value     NUMERIC(18,4),
    currency            VARCHAR(3)   NOT NULL DEFAULT 'PEN',

    -- Cuántos de este premio se darán
    quantity_available  INTEGER     NOT NULL DEFAULT 1,
    quantity_awarded    INTEGER     NOT NULL DEFAULT 0,

    -- Posición/lugar (1er lugar, 2do, etc.)
    prize_rank          SMALLINT    NOT NULL DEFAULT 1,
    -- 1 = primer lugar, 2 = segundo lugar, NULL = todos igual

    -- Imagen del premio
    image_url           VARCHAR(500),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_cprize_campaign ON gifts.campaign_prizes (campaign_id, prize_rank);
CREATE TRIGGER trg_cprize_upd BEFORE UPDATE ON gifts.campaign_prizes
    FOR EACH ROW EXECUTE FUNCTION gifts.set_updated_at();
COMMENT ON TABLE gifts.campaign_prizes IS
'Premios disponibles en una campaña. Una campaña puede tener varios premios (1er lugar, 2do, etc.). Cada premio puede ser gift card, vale de servicio, productos o descuento.';

-- ============================================================
-- 5. PRIZE_WINNERS — Ganadoras y estado del canje
-- ============================================================
CREATE TABLE gifts.prize_winners (
    id                  BIGSERIAL   PRIMARY KEY,
    campaign_id         BIGINT      NOT NULL REFERENCES gifts.prize_campaigns(id),
    prize_id            BIGINT      NOT NULL REFERENCES gifts.campaign_prizes(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Ganadora (puede ser clienta registrada o persona nueva)
    customer_id         BIGINT      REFERENCES sales.customers(id),
    -- Si ya es clienta

    -- Si no es clienta aún (lead de redes sociales)
    winner_name         VARCHAR(200),
    winner_phone        VARCHAR(30),
    winner_email        VARCHAR(200),
    winner_instagram    VARCHAR(100),
    -- Para concursos de Instagram: @usuario de la ganadora

    -- Gift card generada para esta ganadora
    gift_card_id        BIGINT      REFERENCES gifts.gift_cards(id),

    -- Estado del premio
    status              VARCHAR(20)  NOT NULL DEFAULT 'pending_announcement',
    -- pending_announcement : aún no se ha anunciado
    -- announced            : anunciada públicamente en redes
    -- contacted            : se le escribió por WhatsApp/DM
    -- claimed              : canjeó su premio
    -- expired              : venció sin canjear
    -- disqualified         : descalificada (no cumplió requisitos)

    -- Fechas
    announced_at        TIMESTAMPTZ,
    contacted_at        TIMESTAMPTZ,
    claimed_at          TIMESTAMPTZ,

    -- ¿Cómo se le notificó?
    notification_method VARCHAR(20),
    -- instagram_dm / whatsapp / phone_call / email / in_person

    -- Notas
    notes               TEXT,
    -- Ej: "No respondió por 3 días, se eligió suplente"

    registered_by       BIGINT      REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_winner_campaign ON gifts.prize_winners (campaign_id, status);
CREATE INDEX idx_winner_customer ON gifts.prize_winners (customer_id) WHERE customer_id IS NOT NULL;
CREATE TRIGGER trg_winner_upd BEFORE UPDATE ON gifts.prize_winners
    FOR EACH ROW EXECUTE FUNCTION gifts.set_updated_at();
COMMENT ON TABLE gifts.prize_winners IS
'Ganadoras de una campaña/concurso con estado de canje: anunciada → contactada → canjeó. Soporta ganadoras que aún no son clientas (lead de redes sociales).';

-- ============================================================
-- 6. REWARD_PROGRAMS — Programas de reconocimiento al personal
--    Ej: "Empleada del Mes", "Canasta Navideña", "Bono por Meta"
-- ============================================================
CREATE TABLE gifts.reward_programs (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    name                VARCHAR(200) NOT NULL,
    -- Ej: "Empleada del Mes", "Canasta Navideña 2026",
    --     "Bono por Meta de Ventas", "Regalo de Cumpleaños"

    description         TEXT,

    program_type        VARCHAR(25)  NOT NULL DEFAULT 'performance',
    -- performance     : reconocimiento por desempeño (empleada del mes)
    -- sales_target    : bono por alcanzar meta de ventas
    -- attendance      : premio por puntualidad / cero tardanzas
    -- seasonal        : regalo de temporada (Navidad, Día de la Madre)
    -- birthday        : regalo de cumpleaños del personal
    -- anniversary     : aniversario laboral (1 año, 5 años)
    -- referral        : trajo a un nuevo cliente

    -- Frecuencia de entrega
    frequency           VARCHAR(20)  NOT NULL DEFAULT 'one_time',
    -- monthly / quarterly / annual / one_time / event_based

    -- Criterio para ganarlo
    criteria            TEXT,
    -- Ej: "La estilista con más ventas del mes"
    --     "Cero tardanzas durante el mes"
    --     "Superar S/5,000 en servicios en el trimestre"

    -- Presupuesto por premio
    budget_per_award    NUMERIC(18,4),
    currency            VARCHAR(3)   NOT NULL DEFAULT 'PEN',

    -- ¿Está activo?
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_by          BIGINT      REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_rprogram_company ON gifts.reward_programs (company_id, is_active);
CREATE TRIGGER trg_rprogram_upd BEFORE UPDATE ON gifts.reward_programs
    FOR EACH ROW EXECUTE FUNCTION gifts.set_updated_at();
COMMENT ON TABLE gifts.reward_programs IS
'Programa de reconocimiento al personal: Empleada del Mes, Canasta Navideña, Bono por Meta. Define criterios, frecuencia y presupuesto.';

-- ============================================================
-- 7. EMPLOYEE_REWARDS — Premio individual entregado a una empleada
-- ============================================================
CREATE TABLE gifts.employee_rewards (
    id                  BIGSERIAL   PRIMARY KEY,
    program_id          BIGINT      REFERENCES gifts.reward_programs(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Empleada que recibe el premio
    employee_id         BIGINT      NOT NULL REFERENCES hr.employees(id),

    -- Nombre del reconocimiento (puede ser sin programa formal)
    reward_name         VARCHAR(200) NOT NULL,
    -- Ej: "Canasta Navideña 2026", "Empleada del Mes — Julio"
    --     "Bono por superar meta de ventas", "Regalo de cumpleaños"

    -- Tipo de premio
    reward_type         VARCHAR(25)  NOT NULL DEFAULT 'gift_basket',
    -- cash_bonus       : dinero en efectivo / transferencia
    -- gift_card        : tarjeta de consumo para el salón o externa
    -- gift_basket      : canasta (navidad, cumpleaños, parto)
    -- extra_day_off    : día libre adicional
    -- product          : producto específico (perfume, kit de belleza)
    -- experience       : experiencia (spa, cena, viaje)
    -- service          : servicio gratuito en el salón para ella
    -- recognition      : reconocimiento público (diploma, trofeo)
    -- custom           : otro tipo

    -- Descripción del premio físico
    description         TEXT,
    -- Ej: "Canasta con pavo, panetón, chocolates y vino"
    --     "Gift card S/200 — Ripley"
    --     "Kit de maquillaje MAC"

    -- Valor monetario del premio
    monetary_value      NUMERIC(18,4),
    currency            VARCHAR(3)   NOT NULL DEFAULT 'PEN',

    -- Si el premio es una gift card del propio salón
    gift_card_id        BIGINT      REFERENCES gifts.gift_cards(id),

    -- Período de evaluación por el que se ganó
    evaluation_period_start DATE,
    evaluation_period_end   DATE,
    -- Ej: del 1 al 31 de julio (para "Empleada del Mes Julio")

    -- Razón / logro específico
    reason              TEXT,
    -- Ej: "Mayor número de ventas en julio: S/4,850"
    --     "Cero tardanzas en todo el trimestre"
    --     "La clienta Rocío Flores dejó 5 estrellas y mencionó su nombre"

    -- Estado del entrega
    status              VARCHAR(20)  NOT NULL DEFAULT 'pending',
    -- pending    : aprobado pero no entregado aún
    -- delivered  : entregado a la empleada
    -- acknowledged : empleada confirmó recepción

    awarded_at          DATE        NOT NULL DEFAULT CURRENT_DATE,
    delivered_at        TIMESTAMPTZ,
    acknowledged_at     TIMESTAMPTZ,

    -- Quién aprobó / entregó el premio
    approved_by         BIGINT      REFERENCES hr.system_users(id),
    delivered_by        BIGINT      REFERENCES hr.system_users(id),

    -- ¿Se anunció públicamente en el salón?
    announced_publicly  BOOLEAN     NOT NULL DEFAULT FALSE,
    announcement_notes  TEXT,
    -- Ej: "Anunciado en la reunión del lunes y publicado en el grupo de WhatsApp"

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_ereward_employee ON gifts.employee_rewards (employee_id, awarded_at DESC);
CREATE INDEX idx_ereward_program  ON gifts.employee_rewards (program_id) WHERE program_id IS NOT NULL;
CREATE INDEX idx_ereward_status   ON gifts.employee_rewards (company_id, status);
CREATE TRIGGER trg_ereward_upd BEFORE UPDATE ON gifts.employee_rewards
    FOR EACH ROW EXECUTE FUNCTION gifts.set_updated_at();
COMMENT ON TABLE gifts.employee_rewards IS
'Premio individual entregado a una empleada: bono en efectivo, canasta navideña, gift card, día libre, producto o experiencia. Registra razón, valor, entrega y si se anunció públicamente.';

-- ============================================================
-- VISTA 1: Resultados de campañas
-- ============================================================
CREATE OR REPLACE VIEW gifts.campaign_results_view AS
SELECT
    pc.id                                               AS campaign_id,
    pc.company_id,
    pc.name                                             AS campaign_name,
    pc.campaign_type,
    pc.platform,
    pc.status,
    pc.starts_at,
    pc.ends_at,
    pc.total_winners_planned,

    -- Ganadoras reales
    COUNT(pw.id)                                        AS total_winners,
    COUNT(pw.id) FILTER (WHERE pw.status = 'claimed')   AS prizes_claimed,
    COUNT(pw.id) FILTER (WHERE pw.status = 'announced') AS pending_claim,
    COUNT(pw.id) FILTER (WHERE pw.status = 'expired')   AS expired_unclaimed,
    COUNT(pw.id) FILTER (WHERE pw.status = 'contacted') AS contacted_waiting,

    -- Tasa de canje
    ROUND(
        COUNT(pw.id) FILTER (WHERE pw.status = 'claimed')::NUMERIC /
        NULLIF(COUNT(pw.id), 0) * 100
    , 1)                                                AS claim_rate_pct,

    -- Cuántas ganadoras se convirtieron en clientas nuevas
    COUNT(pw.id) FILTER (WHERE pw.customer_id IS NOT NULL
                           AND pw.status = 'claimed')   AS existing_clients_won,
    COUNT(pw.id) FILTER (WHERE pw.customer_id IS NULL
                           AND pw.status = 'claimed')   AS new_leads_won,

    -- Presupuesto vs costo real
    pc.budget,
    COALESCE(SUM(cp.estimated_value) FILTER (WHERE pw.status = 'claimed'), 0)
                                                        AS actual_cost,
    pc.currency

FROM gifts.prize_campaigns          pc
LEFT JOIN gifts.prize_winners       pw ON pw.campaign_id = pc.id
LEFT JOIN gifts.campaign_prizes     cp ON cp.id = pw.prize_id
GROUP BY pc.id, pc.company_id, pc.name, pc.campaign_type, pc.platform,
         pc.status, pc.starts_at, pc.ends_at, pc.total_winners_planned,
         pc.budget, pc.currency
ORDER BY pc.starts_at DESC;

COMMENT ON VIEW gifts.campaign_results_view IS
'Resultados por campaña: ganadoras, tasa de canje, costo real vs presupuesto, nuevas clientas captadas por el concurso.';

-- ============================================================
-- VISTA 2: Reconocimientos al personal por período
-- ============================================================
CREATE OR REPLACE VIEW gifts.employee_recognition_view AS
SELECT
    er.company_id,
    e.id                                                AS employee_id,
    p.first_name || ' ' || p.last_name                 AS employee_name,
    d.name                                              AS department,
    pos.name                                            AS position,

    rp.name                                             AS program_name,
    rp.program_type,

    er.reward_name,
    er.reward_type,
    er.description,
    er.monetary_value,
    er.currency,
    er.reason,
    er.awarded_at,
    er.status,
    er.delivered_at,
    er.announced_publicly,

    -- Total de premios recibidos por esta empleada (histórico)
    COUNT(er2.id) OVER (PARTITION BY er.employee_id)    AS total_rewards_received,

    -- Valor total recibido
    SUM(er2.monetary_value) OVER (PARTITION BY er.employee_id)
                                                        AS total_value_received

FROM gifts.employee_rewards         er
INNER JOIN hr.employees             e   ON e.id  = er.employee_id
INNER JOIN hr.persons               p   ON p.id  = e.person_id
LEFT  JOIN hr.departments           d   ON d.id  = e.department_id
LEFT  JOIN hr.positions             pos ON pos.id = e.position_id
LEFT  JOIN gifts.reward_programs    rp  ON rp.id = er.program_id
LEFT  JOIN gifts.employee_rewards   er2 ON er2.employee_id = er.employee_id
ORDER BY er.awarded_at DESC;

COMMENT ON VIEW gifts.employee_recognition_view IS
'Reconocimientos entregados al personal: nombre, tipo de premio, razón, valor y totales históricos por empleada. Para dashboard de clima laboral y registro de RR.HH.';
