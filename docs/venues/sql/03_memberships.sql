-- ============================================================
-- mantrasdb | Módulo Venues
-- Archivo: 03_memberships.sql
-- Descripción: Membresías para clubs, piscinas y recintos
--
-- Tablas:
--   8. membership_types   — Tipos de membresía (Bronce/Plata/Oro)
--   9. memberships        — Membresía individual por cliente
--  10. membership_benefits — Beneficios incluidos por tipo de membresía
--  11. membership_invoices — Facturación periódica de la membresía
--
-- Vistas:
--   venues.membership_status_view  — Socios activos por tipo
--   venues.daily_access_view       — Quién está dentro ahora mismo
--   venues.membership_revenue_view — Ingresos por membresía por período
--
-- ALTER TABLE:
--   Completa la FK de access_logs.membership_id → memberships.id
--   (forward reference resuelta al final de este archivo)
-- ============================================================

-- ============================================================
-- 8. MEMBERSHIP_TYPES — Tipos de membresía
--    Ej: Bronce (mensual, acceso piscina), Oro (anual, acceso total)
-- ============================================================
CREATE TABLE venues.membership_types (
    id                  BIGSERIAL   PRIMARY KEY,
    venue_id            BIGINT      NOT NULL REFERENCES venues.venues(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    name                VARCHAR(100) NOT NULL,
    -- Ej: "Bronce", "Plata", "Oro", "Familiar", "Corporativo"

    code                VARCHAR(20),
    -- Código corto: BRON, PLAT, GOLD, FAM, CORP

    description         TEXT,

    -- Periodicidad de cobro
    billing_period      VARCHAR(20)  NOT NULL DEFAULT 'monthly',
    -- daily / weekly / monthly / quarterly / annual / one_time

    -- Precio según periodicidad
    price               NUMERIC(18,4) NOT NULL DEFAULT 0,
    currency            VARCHAR(3)   NOT NULL DEFAULT 'PEN',

    -- Precio de matrícula / inscripción (cobro único al inicio)
    enrollment_fee      NUMERIC(18,4) NOT NULL DEFAULT 0,

    -- ¿Cuántos titulares permite? (1 = individual, >1 = familiar/grupal)
    max_holders         SMALLINT    NOT NULL DEFAULT 1,

    -- ¿Incluye acceso a todas las zonas?
    all_zones_access    BOOLEAN     NOT NULL DEFAULT FALSE,

    -- Número máximo de visitas por período (NULL = ilimitado)
    max_visits_per_period INTEGER,

    -- Invitados gratis por visita
    free_guests_per_visit SMALLINT   NOT NULL DEFAULT 0,

    -- Descuento en consumos (%) para socios
    consumption_discount_pct NUMERIC(5,2) NOT NULL DEFAULT 0,

    -- Vigencia (en días) a partir de la fecha de inicio
    -- NULL = indefinido (se cobra recurrentemente)
    validity_days       INTEGER,

    -- ¿Permite congelar la membresía?
    can_freeze          BOOLEAN     NOT NULL DEFAULT FALSE,
    max_freeze_days     SMALLINT    NOT NULL DEFAULT 0,

    -- Imagen/color para UI
    color_hex           VARCHAR(7),
    -- Ej: "#FFD700" para Oro

    sort_order          SMALLINT    NOT NULL DEFAULT 1,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX uq_membership_type_code ON venues.membership_types (venue_id, code)
    WHERE code IS NOT NULL;
CREATE INDEX idx_mtype_venue ON venues.membership_types (venue_id, is_active);
CREATE TRIGGER trg_mtype_upd BEFORE UPDATE ON venues.membership_types
    FOR EACH ROW EXECUTE FUNCTION venues.set_updated_at();
COMMENT ON TABLE venues.membership_types IS
'Tipos de membresía del recinto: Bronce, Plata, Oro, Familiar. Define precio, periodicidad, zonas permitidas y beneficios.';

-- ============================================================
-- 9. MEMBERSHIPS — Membresía individual por cliente
-- ============================================================
CREATE TABLE venues.memberships (
    id                  BIGSERIAL   PRIMARY KEY,
    membership_type_id  BIGINT      NOT NULL REFERENCES venues.membership_types(id),
    venue_id            BIGINT      NOT NULL REFERENCES venues.venues(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Titular principal
    customer_id         BIGINT      NOT NULL REFERENCES sales.customers(id),

    -- Número de socio (generado por la empresa)
    member_number       VARCHAR(50)  NOT NULL,

    -- Código de acceso (para torniquete, tarjeta RFID, app)
    access_code         VARCHAR(100),
    -- Puede ser el mismo que el QR en la app

    -- Estado de la membresía
    status              VARCHAR(20)  NOT NULL DEFAULT 'active',
    -- pending_payment / active / frozen / expired / cancelled / suspended

    -- Vigencia
    started_at          DATE        NOT NULL DEFAULT CURRENT_DATE,
    expires_at          DATE,
    -- NULL si es de renovación automática indefinida

    -- Congelamiento temporal
    frozen_at           DATE,
    frozen_until        DATE,
    freeze_reason       VARCHAR(200),
    total_days_frozen   SMALLINT    NOT NULL DEFAULT 0,

    -- Próxima fecha de facturación
    next_billing_date   DATE,

    -- ¿Renovación automática activa?
    auto_renew          BOOLEAN     NOT NULL DEFAULT TRUE,

    -- Visitas en el período actual
    visits_this_period  INTEGER     NOT NULL DEFAULT 0,

    -- Conteo total histórico de visitas
    total_visits        INTEGER     NOT NULL DEFAULT 0,

    -- Cómo llegó el socio
    referral_source     VARCHAR(50),
    -- web / referral / walk_in / promotion / social_media

    -- Si fue referido por otro socio
    referred_by_membership_id BIGINT REFERENCES venues.memberships(id),

    notes               TEXT,

    cancelled_at        TIMESTAMPTZ,
    cancellation_reason VARCHAR(200),

    created_by          BIGINT      REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX uq_member_number ON venues.memberships (venue_id, member_number);
CREATE INDEX idx_membership_customer ON venues.memberships (customer_id);
CREATE INDEX idx_membership_status   ON venues.memberships (venue_id, status, expires_at);
CREATE TRIGGER trg_membership_upd BEFORE UPDATE ON venues.memberships
    FOR EACH ROW EXECUTE FUNCTION venues.set_updated_at();
COMMENT ON TABLE venues.memberships IS
'Membresía individual de un cliente al recinto. Controla vigencia, estado, congelamiento, visitas y renovación automática.';

-- ============================================================
-- 10. MEMBERSHIP_BENEFITS — Beneficios por tipo de membresía
--     Qué zonas puede usar, qué servicios incluye.
--     INMUTABLE: los beneficios quedan registrados al crear el tipo.
-- ============================================================
CREATE TABLE venues.membership_benefits (
    id                      BIGSERIAL   PRIMARY KEY,
    membership_type_id      BIGINT      NOT NULL REFERENCES venues.membership_types(id) ON DELETE CASCADE,
    company_id              BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Tipo de beneficio
    benefit_type            VARCHAR(30)  NOT NULL DEFAULT 'zone_access',
    -- zone_access      : acceso a una zona específica
    -- service_discount : descuento en un servicio
    -- guest_pass       : pases de invitado gratuitos por período
    -- product_discount : descuento en productos/consumos
    -- priority_booking : reservas con prioridad
    -- free_class       : clases incluidas por semana

    -- Zona incluida (si benefit_type = zone_access)
    zone_id                 BIGINT      REFERENCES venues.venue_zones(id),

    -- Descripción del beneficio
    description             VARCHAR(200) NOT NULL,
    -- Ej: "Acceso ilimitado Piscina Olímpica", "20% descuento en cafetería"

    -- Valor del beneficio (descuento % o cantidad)
    benefit_value           NUMERIC(10,4),
    -- Para descuentos: 20.00 = 20%
    -- Para clases: 2.00 = 2 clases/semana

    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);
CREATE INDEX idx_benefit_mtype ON venues.membership_benefits (membership_type_id);
COMMENT ON TABLE venues.membership_benefits IS
'Beneficios incluidos en cada tipo de membresía: zonas de acceso, descuentos, clases gratuitas, pases de invitado. Inmutable.';

-- ============================================================
-- 11. MEMBERSHIP_INVOICES — Facturación periódica de membresía
--     Registro de cada cobro periódico (mensual/anual).
-- ============================================================
CREATE TABLE venues.membership_invoices (
    id                  BIGSERIAL   PRIMARY KEY,
    membership_id       BIGINT      NOT NULL REFERENCES venues.memberships(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Período facturado
    period_start        DATE        NOT NULL,
    period_end          DATE        NOT NULL,

    -- Monto
    amount              NUMERIC(18,4) NOT NULL,
    currency            VARCHAR(3)   NOT NULL DEFAULT 'PEN',

    -- Tipo de cobro
    invoice_type        VARCHAR(20)  NOT NULL DEFAULT 'subscription',
    -- subscription / enrollment_fee / penalty / adjustment

    -- Estado del cobro
    status              VARCHAR(20)  NOT NULL DEFAULT 'pending',
    -- pending / paid / overdue / waived / refunded

    -- Referencia a factura del módulo Sales
    invoice_id          BIGINT      REFERENCES sales.invoices(id),

    paid_at             TIMESTAMPTZ,
    due_date            DATE        NOT NULL,

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_minvoice_membership ON venues.membership_invoices (membership_id, status);
CREATE INDEX idx_minvoice_due        ON venues.membership_invoices (due_date, status);
CREATE TRIGGER trg_minvoice_upd BEFORE UPDATE ON venues.membership_invoices
    FOR EACH ROW EXECUTE FUNCTION venues.set_updated_at();
COMMENT ON TABLE venues.membership_invoices IS
'Factura periódica de membresía. Registra cada cobro (suscripción, matrícula, penalidad) con referencia a sales.invoices.';

-- ============================================================
-- FK diferida: access_logs.membership_id → memberships.id
-- (tabla memberships recién creada en este archivo)
-- ============================================================
ALTER TABLE venues.access_logs
    ADD CONSTRAINT fk_access_log_membership
    FOREIGN KEY (membership_id) REFERENCES venues.memberships(id);

-- ============================================================
-- VISTA 1: Estado de socios activos
-- ============================================================
CREATE OR REPLACE VIEW venues.membership_status_view AS
SELECT
    v.id                                                    AS venue_id,
    v.company_id,
    v.name                                                  AS venue_name,

    mt.id                                                   AS type_id,
    mt.name                                                 AS membership_type,
    mt.billing_period,
    mt.price,
    mt.currency,

    COUNT(m.id)                                             AS total_members,
    COUNT(m.id) FILTER (WHERE m.status = 'active')          AS active_members,
    COUNT(m.id) FILTER (WHERE m.status = 'frozen')          AS frozen_members,
    COUNT(m.id) FILTER (WHERE m.status = 'expired')         AS expired_members,
    COUNT(m.id) FILTER (WHERE m.status = 'pending_payment') AS pending_payment,
    COUNT(m.id) FILTER (WHERE m.auto_renew = TRUE
                          AND m.status = 'active')          AS auto_renew_active,

    -- MRR estimado (socios activos × precio mensual equivalente)
    CASE
        WHEN mt.billing_period = 'monthly'
        THEN COUNT(m.id) FILTER (WHERE m.status = 'active') * mt.price
        WHEN mt.billing_period = 'annual'
        THEN COUNT(m.id) FILTER (WHERE m.status = 'active') * mt.price / 12
        WHEN mt.billing_period = 'quarterly'
        THEN COUNT(m.id) FILTER (WHERE m.status = 'active') * mt.price / 3
        ELSE NULL
    END                                                     AS estimated_mrr,

    -- Socios que vencen en los próximos 30 días
    COUNT(m.id) FILTER (
        WHERE m.status = 'active'
          AND m.expires_at IS NOT NULL
          AND m.expires_at BETWEEN CURRENT_DATE AND CURRENT_DATE + 30
    )                                                       AS expiring_soon

FROM venues.venues                v
INNER JOIN venues.membership_types    mt ON mt.venue_id  = v.id AND mt.is_active = TRUE
LEFT  JOIN venues.memberships         m  ON m.membership_type_id = mt.id
GROUP BY v.id, v.company_id, v.name,
         mt.id, mt.name, mt.billing_period, mt.price, mt.currency
ORDER BY v.name, mt.sort_order;

COMMENT ON VIEW venues.membership_status_view IS
'Socios activos, congelados y por vencer por tipo de membresía. Incluye MRR estimado y alertas de vencimiento próximo.';

-- ============================================================
-- VISTA 2: Quién está dentro ahora mismo
-- ============================================================
CREATE OR REPLACE VIEW venues.daily_access_view AS
WITH last_movement AS (
    SELECT DISTINCT ON (al.customer_id, al.event_id)
        al.customer_id,
        al.event_id,
        al.zone_id,
        al.movement_type,
        al.access_method,
        al.logged_at,
        al.ticket_id,
        al.membership_id
    FROM venues.access_logs al
    WHERE al.logged_at >= CURRENT_DATE
      AND al.movement_type IN ('entry', 'reentry', 'exit')
    ORDER BY al.customer_id, al.event_id, al.logged_at DESC
)
SELECT
    e.id                    AS event_id,
    e.company_id,
    e.name                  AS event_name,
    e.event_date,

    vz.name                 AS zone_name,
    vz.zone_type,

    lm.customer_id,
    lm.movement_type        AS last_movement,
    lm.access_method,
    lm.logged_at            AS last_access_at,
    lm.ticket_id,
    lm.membership_id,

    -- ¿Está actualmente dentro?
    (lm.movement_type IN ('entry', 'reentry')) AS is_inside,

    -- Tiempo dentro (si aún está)
    CASE
        WHEN lm.movement_type IN ('entry', 'reentry')
        THEN EXTRACT(EPOCH FROM (NOW() - lm.logged_at)) / 60
        ELSE NULL
    END                     AS minutes_inside

FROM last_movement          lm
INNER JOIN venues.events        e  ON e.id  = lm.event_id
INNER JOIN venues.venue_zones   vz ON vz.id = lm.zone_id
ORDER BY e.event_date, vz.zone_type, lm.logged_at;

COMMENT ON VIEW venues.daily_access_view IS
'Quién está dentro del recinto ahora mismo, por zona y evento. Basado en el último movimiento del día (entry/exit). Para pantallas de portería.';

-- ============================================================
-- VISTA 3: Ingresos por membresía por período
-- ============================================================
CREATE OR REPLACE VIEW venues.membership_revenue_view AS
SELECT
    mi.company_id,
    v.name                                                  AS venue_name,
    mt.name                                                 AS membership_type,
    mt.billing_period,

    -- Período (mes-año para cobros mensuales)
    TO_CHAR(mi.period_start, 'YYYY-MM')                     AS period_month,
    mi.period_start,
    mi.period_end,

    COUNT(mi.id)                                            AS total_invoices,
    COUNT(mi.id) FILTER (WHERE mi.status = 'paid')          AS paid_invoices,
    COUNT(mi.id) FILTER (WHERE mi.status = 'pending')       AS pending_invoices,
    COUNT(mi.id) FILTER (WHERE mi.status = 'overdue')       AS overdue_invoices,

    SUM(mi.amount)                                          AS total_billed,
    SUM(mi.amount) FILTER (WHERE mi.status = 'paid')        AS total_collected,
    SUM(mi.amount) FILTER (WHERE mi.status IN ('pending', 'overdue'))
                                                            AS total_outstanding,
    mi.currency

FROM venues.membership_invoices     mi
INNER JOIN venues.memberships       m  ON m.id  = mi.membership_id
INNER JOIN venues.membership_types  mt ON mt.id = m.membership_type_id
INNER JOIN venues.venues            v  ON v.id  = mt.venue_id
GROUP BY mi.company_id, v.name, mt.name, mt.billing_period,
         TO_CHAR(mi.period_start, 'YYYY-MM'), mi.period_start, mi.period_end, mi.currency
ORDER BY mi.period_start DESC, v.name, mt.name;

COMMENT ON VIEW venues.membership_revenue_view IS
'Ingresos por membresía agrupados por período: facturado vs cobrado vs pendiente. Para reporte financiero del recinto.';
