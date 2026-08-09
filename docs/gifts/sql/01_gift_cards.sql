-- ============================================================
-- mantrasdb | Módulo Gifts
-- Archivo: 01_gift_cards.sql
-- Descripción: Tarjetas de consumo / gift cards para clientes.
--
-- Una gift card puede ser:
--   - Vendida en caja (la clienta compra S/100 de crédito)
--   - Regalo de un concurso en redes sociales (tinte gratis)
--   - Regalo por referido o cumpleaños
--   - Vale de servicio específico (no monetario, sino "1 tinte completo")
--
-- Tablas:
--   1. gift_cards              — Tarjeta de consumo / vale
--   2. gift_card_transactions  — Cada uso o recarga (INMUTABLE)
--
-- Vistas:
--   gifts.gift_card_balance_view — Saldo actual y uso por tarjeta
-- ============================================================

CREATE SCHEMA IF NOT EXISTS gifts;

CREATE OR REPLACE FUNCTION gifts.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

-- ============================================================
-- 1. GIFT_CARDS — Tarjeta de consumo / vale de regalo
-- ============================================================
CREATE TABLE gifts.gift_cards (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Código único impreso en la tarjeta / enviado por WhatsApp
    code                VARCHAR(50)  NOT NULL,
    -- Ej: "GC-2026-00042", "TINTE-LUNA-001", "PROMO-IG-05"

    -- Tipo de gift card
    card_type           VARCHAR(20)  NOT NULL DEFAULT 'monetary',
    -- monetary       : saldo en dinero (S/100, S/50)
    -- service_voucher: vale por un servicio específico (1 tinte completo)
    -- product_voucher: vale por un producto específico
    -- bundle_voucher : vale por un paquete (servicio + producto)

    -- ── TARJETA MONETARIA ───────────────────────────────────
    initial_balance     NUMERIC(18,4),
    -- Monto inicial: S/100.00
    current_balance     NUMERIC(18,4),
    -- Saldo actual (se descuenta en cada uso)
    currency            VARCHAR(3)   NOT NULL DEFAULT 'PEN',

    -- ── VALE DE SERVICIO ESPECÍFICO ─────────────────────────
    -- Para "1 tinte completo gratis" o "1 manicure"
    service_id          BIGINT      REFERENCES services.services(id),
    service_quantity    SMALLINT    NOT NULL DEFAULT 1,
    -- Cuántos servicios incluye el vale

    -- ── VALE DE PRODUCTO ESPECÍFICO ─────────────────────────
    product_id          BIGINT      REFERENCES logistics.products(id),
    product_quantity    NUMERIC(10,3),

    -- ── ORIGEN DEL REGALO ───────────────────────────────────
    source              VARCHAR(25)  NOT NULL DEFAULT 'sold',
    -- sold            : comprada en caja por una clienta
    -- prize           : ganada en concurso/sorteo
    -- promotional     : dada como promoción (cumpleaños, bienvenida)
    -- referral        : recompensa por traer a otra clienta
    -- employee_reward : regalo para una empleada de parte del negocio
    -- compensation    : compensación por mala experiencia

    -- ── BENEFICIARIA ────────────────────────────────────────
    -- Quién recibe la tarjeta (puede ser clienta ya registrada o nueva)
    customer_id         BIGINT      REFERENCES sales.customers(id),
    recipient_name      VARCHAR(200),
    -- Para concursos: la ganadora puede no ser clienta aún
    recipient_phone     VARCHAR(30),
    recipient_email     VARCHAR(200),

    -- Quién la compró (si fue comprada como regalo para otra persona)
    purchased_by_customer_id BIGINT REFERENCES sales.customers(id),

    -- ── CAMPAÑA DE ORIGEN ───────────────────────────────────
    -- Se vincula en 02_campaigns.sql
    campaign_id         BIGINT,
    -- REFERENCES gifts.prize_campaigns(id) — FK diferida

    -- ── VIGENCIA ────────────────────────────────────────────
    issued_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    expires_at          DATE,
    -- NULL = sin vencimiento

    -- ── ESTADO ──────────────────────────────────────────────
    status              VARCHAR(20)  NOT NULL DEFAULT 'active',
    -- pending_activation: emitida pero no activada aún
    -- active           : vigente con saldo disponible
    -- depleted         : saldo agotado o servicio ya canjeado
    -- expired          : venció sin usarse (o parcialmente)
    -- cancelled        : anulada por el negocio

    -- ── VENTA ───────────────────────────────────────────────
    -- Si fue vendida: referencia a la transacción de compra
    sales_order_id      BIGINT      REFERENCES sales.sales_orders(id),
    invoice_id          BIGINT      REFERENCES sales.invoices(id),

    -- Notas internas
    notes               TEXT,

    issued_by           BIGINT      REFERENCES hr.system_users(id),
    activated_at        TIMESTAMPTZ,
    depleted_at         TIMESTAMPTZ,
    cancelled_at        TIMESTAMPTZ,
    cancellation_reason VARCHAR(200),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX uq_gift_card_code ON gifts.gift_cards (company_id, code);
CREATE INDEX idx_gc_customer   ON gifts.gift_cards (customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX idx_gc_status     ON gifts.gift_cards (company_id, status, expires_at);
CREATE INDEX idx_gc_campaign   ON gifts.gift_cards (campaign_id) WHERE campaign_id IS NOT NULL;
CREATE TRIGGER trg_gc_upd BEFORE UPDATE ON gifts.gift_cards
    FOR EACH ROW EXECUTE FUNCTION gifts.set_updated_at();
COMMENT ON TABLE gifts.gift_cards IS
'Tarjeta de consumo o vale de regalo. Puede ser monetaria (S/100) o vale de servicio/producto específico. Origen: vendida, premio, promocional, reward de empleada.';

-- ============================================================
-- 2. GIFT_CARD_TRANSACTIONS — Cada uso o recarga
--    INMUTABLE: cada movimiento queda registrado para siempre.
-- ============================================================
CREATE TABLE gifts.gift_card_transactions (
    id                  BIGSERIAL   PRIMARY KEY,
    gift_card_id        BIGINT      NOT NULL REFERENCES gifts.gift_cards(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    transaction_type    VARCHAR(20)  NOT NULL DEFAULT 'redemption',
    -- redemption   : uso/canje de la tarjeta
    -- top_up       : recarga de saldo
    -- refund       : devolución de saldo (si se anuló un servicio)
    -- expiry       : saldo vencido (para registro contable)
    -- activation   : activación de la tarjeta

    -- Monto del movimiento (para tarjetas monetarias)
    amount              NUMERIC(18,4),
    -- Positivo = recarga, Negativo = uso

    -- Saldo después del movimiento (snapshot)
    balance_after       NUMERIC(18,4),

    -- Para vales de servicio: cuántos servicios se canjearon
    quantity_used       SMALLINT,

    -- En qué se usó (referencia a la cita o venta)
    appointment_id      BIGINT      REFERENCES services.appointments(id),
    invoice_id          BIGINT      REFERENCES sales.invoices(id),

    -- Quién procesó la transacción
    processed_by        BIGINT      REFERENCES hr.system_users(id),

    notes               VARCHAR(300),

    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
    -- INMUTABLE
);
CREATE INDEX idx_gct_card      ON gifts.gift_card_transactions (gift_card_id, created_at DESC);
CREATE INDEX idx_gct_appt      ON gifts.gift_card_transactions (appointment_id) WHERE appointment_id IS NOT NULL;
COMMENT ON TABLE gifts.gift_card_transactions IS
'Cada movimiento de una gift card: uso, recarga, devolución, vencimiento. INMUTABLE — auditoría completa del ciclo de vida del saldo.';

-- ============================================================
-- VISTA: Saldo actual y uso por tarjeta
-- ============================================================
CREATE OR REPLACE VIEW gifts.gift_card_balance_view AS
SELECT
    gc.id                                               AS gift_card_id,
    gc.company_id,
    gc.code,
    gc.card_type,
    gc.status,
    gc.source,

    -- Cliente beneficiaria
    gc.customer_id,
    COALESCE(gc.recipient_name, 'Sin nombre')           AS recipient,
    gc.recipient_phone,

    -- Saldo
    gc.initial_balance,
    gc.current_balance,
    gc.currency,

    -- Para vales de servicio
    gc.service_quantity                                 AS total_services,
    COALESCE(
        SUM(gct.quantity_used) FILTER (WHERE gct.transaction_type = 'redemption'),
        0
    )::SMALLINT                                         AS services_used,
    gc.service_quantity - COALESCE(
        SUM(gct.quantity_used) FILTER (WHERE gct.transaction_type = 'redemption'),
        0
    )                                                   AS services_remaining,

    -- Uso total en dinero
    COALESCE(
        SUM(ABS(gct.amount)) FILTER (WHERE gct.transaction_type = 'redemption'),
        0
    )                                                   AS total_redeemed,

    -- Número de veces usada
    COUNT(gct.id) FILTER (WHERE gct.transaction_type = 'redemption')
                                                        AS times_used,

    -- Fechas
    gc.issued_at,
    gc.expires_at,
    gc.activated_at,

    -- ¿Está por vencer? (próximos 30 días)
    CASE
        WHEN gc.expires_at IS NULL THEN FALSE
        WHEN gc.expires_at BETWEEN CURRENT_DATE AND CURRENT_DATE + 30 THEN TRUE
        ELSE FALSE
    END                                                 AS expiring_soon,

    -- ¿Ya venció?
    CASE
        WHEN gc.expires_at IS NOT NULL AND gc.expires_at < CURRENT_DATE
         AND gc.status = 'active'
        THEN TRUE
        ELSE FALSE
    END                                                 AS is_overdue

FROM gifts.gift_cards           gc
LEFT JOIN gifts.gift_card_transactions gct ON gct.gift_card_id = gc.id
GROUP BY gc.id, gc.company_id, gc.code, gc.card_type, gc.status, gc.source,
         gc.customer_id, gc.recipient_name, gc.recipient_phone,
         gc.initial_balance, gc.current_balance, gc.currency,
         gc.service_quantity, gc.issued_at, gc.expires_at, gc.activated_at
ORDER BY gc.issued_at DESC;

COMMENT ON VIEW gifts.gift_card_balance_view IS
'Saldo actual, uso total y estado de vencimiento de cada gift card. Combina tarjetas monetarias y vales de servicio.';
