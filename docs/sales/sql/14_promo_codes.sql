-- ============================================================
-- mantrasdb | Módulo Sales
-- Archivo: 14_promo_codes.sql
-- Descripción: Códigos Promocionales
--
-- Diferencia con promotions (10_promotions.sql):
--   - promotions: descuentos AUTOMÁTICOS (el sistema los aplica
--     si se cumplen las condiciones: monto mínimo, producto, etc.)
--   - promo_codes: el cliente ingresa UN CÓDIGO manualmente
--     (VERANO20, BIENVENIDA10, CUMPLE-ANA, etc.)
--
-- Los promo_codes pueden vincularse a una promotion existente
-- (para reutilizar la lógica de descuento) o tener su propio
-- descuento directo.
--
-- Módulos:
--   1. promo_codes         — definición del código
--   2. promo_code_redemptions — historial de canjes
-- ============================================================

-- ============================================================
-- 1. PROMO CODES
-- ============================================================
CREATE TABLE sales.promo_codes (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    code                VARCHAR(50) NOT NULL,
    -- El código que ingresa el cliente. Ej: VERANO20, BIENVENIDA10
    -- Se guarda en UPPER automáticamente desde la aplicación

    description         VARCHAR(200),

    -- ── Tipo de descuento ─────────────────────────────────────
    discount_type       VARCHAR(20) NOT NULL DEFAULT 'percentage',
    -- percentage  : % de descuento sobre el total
    -- fixed       : monto fijo de descuento (S/ 20, $ 10)
    -- free_item   : un ítem gratis (vinculado a un producto)
    -- free_service: un servicio gratis (vinculado a services)

    discount_value      NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- Para percentage: 20 = 20%
    -- Para fixed: 20 = S/ 20

    -- Monto máximo de descuento (para tipo percentage)
    max_discount_amount NUMERIC(18,4),
    -- Ej: 20% pero máximo S/ 50

    -- Ítem o servicio gratis
    free_product_id     BIGINT      REFERENCES logistics.products(id),
    free_service_id     BIGINT,
    -- FK lógica → services.services(id); se agrega vía ALTER TABLE
    -- en docs/services/sql/01_service_catalog.sql (services carga después de sales)

    -- ── Vinculo con promoción existente ───────────────────────
    -- Si se vincula a una promotion, se aplica esa lógica
    promotion_id        BIGINT      REFERENCES sales.promotions(id),

    -- ── Condiciones de uso ────────────────────────────────────
    min_order_amount    NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- Monto mínimo de la orden para poder usar el código

    -- ¿A qué aplica el descuento?
    applies_to          VARCHAR(20) NOT NULL DEFAULT 'total',
    -- total       : sobre el total de la orden
    -- category    : solo a productos de cierta categoría
    -- product     : solo a un producto específico
    -- service     : solo a un servicio específico
    -- first_item  : solo al ítem más caro

    applies_to_category_id  BIGINT  REFERENCES logistics.product_categories(id),
    applies_to_product_id   BIGINT  REFERENCES logistics.products(id),
    applies_to_service_id   BIGINT,
    -- FK lógica → services.services(id); se agrega vía ALTER TABLE
    -- en docs/services/sql/01_service_catalog.sql (services carga después de sales)

    -- ── Límites de uso ────────────────────────────────────────
    max_uses_total      INTEGER,
    -- NULL = usos ilimitados

    max_uses_per_customer INTEGER NOT NULL DEFAULT 1,
    -- Por defecto: 1 uso por cliente

    -- ¿Solo para nuevos clientes?
    new_customers_only  BOOLEAN     NOT NULL DEFAULT FALSE,

    -- ¿Solo para un cliente específico? (código personalizado)
    specific_customer_id BIGINT     REFERENCES sales.customers(id),
    -- Ej: código de cumpleaños para Ana: CUMPLE-ANA

    -- ── Vigencia ──────────────────────────────────────────────
    valid_from          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    valid_to            TIMESTAMPTZ,
    -- NULL = sin vencimiento

    -- ── Contadores ────────────────────────────────────────────
    times_used          INTEGER     NOT NULL DEFAULT 0,
    -- Se incrementa con cada canje exitoso

    total_discount_given NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- Suma acumulada de descuentos otorgados

    -- ── Canal de uso ──────────────────────────────────────────
    valid_channels      VARCHAR(20)[] NOT NULL DEFAULT ARRAY['all'],
    -- ARRAY['all'] / ARRAY['online', 'pos'] / ARRAY['services']

    -- ── Estado ───────────────────────────────────────────────
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_by          BIGINT      REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX uq_promo_code
    ON sales.promo_codes (company_id, UPPER(code));
CREATE INDEX idx_pc_valid ON sales.promo_codes (valid_from, valid_to);
CREATE INDEX idx_pc_customer ON sales.promo_codes (specific_customer_id);

CREATE TRIGGER trg_pc_updated_at
    BEFORE UPDATE ON sales.promo_codes
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE sales.promo_codes IS 'Códigos que el cliente ingresa manualmente (VERANO20, BIENVENIDA10). Soporta % o monto fijo, límite de usos, vigencia y cliente específico (cumpleaños).';

-- ============================================================
-- 2. PROMO CODE REDEMPTIONS (Historial de Canjes)
-- ============================================================
CREATE TABLE sales.promo_code_redemptions (
    id                  BIGSERIAL   PRIMARY KEY,
    promo_code_id       BIGINT      NOT NULL REFERENCES sales.promo_codes(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    customer_id         BIGINT      NOT NULL REFERENCES sales.customers(id),

    -- Dónde se usó el código
    redeemed_in         VARCHAR(20) NOT NULL DEFAULT 'sales_order',
    -- sales_order / invoice / appointment / pos_transaction

    sales_order_id      BIGINT      REFERENCES sales.sales_orders(id),
    invoice_id          BIGINT      REFERENCES sales.invoices(id),
    appointment_id      BIGINT,
    -- FK lógica → services.appointments(id); se agrega en 03_appointments.sql
    pos_transaction_id  BIGINT      REFERENCES sales.pos_transactions(id),

    -- Monto descontado en este canje
    order_amount_before NUMERIC(18,4) NOT NULL,
    discount_applied    NUMERIC(18,4) NOT NULL,
    order_amount_after  NUMERIC(18,4) GENERATED ALWAYS AS (order_amount_before - discount_applied) STORED,

    redeemed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);

CREATE INDEX idx_pcr_code     ON sales.promo_code_redemptions (promo_code_id);
CREATE INDEX idx_pcr_customer ON sales.promo_code_redemptions (customer_id);
CREATE INDEX idx_pcr_redeemed ON sales.promo_code_redemptions (redeemed_at);

COMMENT ON TABLE sales.promo_code_redemptions IS 'Historial de canjes de códigos promocionales. Permite verificar usos por cliente y acumular el descuento total otorgado.';
