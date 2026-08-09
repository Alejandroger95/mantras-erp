-- ============================================================
-- mantrasdb | Módulo Sales
-- Archivo: 10_promotions.sql
-- Descripción: Motor completo de promociones y descuentos.
--
-- Conceptos implementados:
--   - Promotions: BOGO, 2x1, ítem gratis, flash sale, bundle
--   - Ad-hoc discounts: la "rebaja peruana" con control de límites
--   - Rebate agreements: descuentos retroactivos acumulados (SAP SD)
--   - Sales rep discount limits: quién puede dar cuánto sin aprobar
--
-- Waterfall de precio (aplicado en capa de negocio):
--   1. customer_special_prices (precio negociado → mayor prioridad)
--   2. price_list_items + price_scales (precio de lista + escala volumen)
--   3. discount_rules (descuentos comerciales estándar)
--   4. promotions (promos activas, por prioridad; cumul. o exclusivas)
--   5. ad_hoc_price_overrides (rebaja del vendedor, con límite y aprobación)
--   6. tax (siempre sobre el neto resultante, nunca incluido en BD)
--
-- Casos reales cubiertos:
--   B2C: "Lleva 2 pagás 1" (BOGO) en tienda de ropa
--   B2C: 2x1 jabas de huevo con precio por fracción (2.5 jabas = 2 precios)
--   B2B: Promo volumen: 50+ kg de papa → S/4.00/kg (via price_scales)
--   Retail: La rebaja peruana — vendedor da 10%, límite 5% → pide aprobación
--   Enterprise: Saga Falabella acumula S/600K → NC al cierre del año
-- ============================================================

-- ============================================================
-- 1. PROMOCIONES (cabecera)
-- ============================================================
CREATE TABLE sales.promotions (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    code                VARCHAR(30) NOT NULL,
    name                VARCHAR(300) NOT NULL,
    description         TEXT,

    promo_type          VARCHAR(30) NOT NULL,
    -- percentage_off     : descuento porcentual (20% off)
    -- fixed_amount_off   : monto fijo de descuento (S/10 off)
    -- fixed_price        : precio fijo resultante (S/99 todo incluido)
    -- free_item          : ítem gratis al comprar X
    -- bogo               : compra X lleva Y gratis (Buy One Get One)
    -- bundle             : pack de productos a precio especial
    -- free_shipping      : envío gratis (para ecommerce)

    -- Vigencia (con hora — soporta flash sales de 2 horas)
    valid_from          TIMESTAMPTZ,
    valid_to            TIMESTAMPTZ,

    -- Control de usos
    max_uses_total      INTEGER,
    -- NULL = ilimitado
    max_uses_per_customer INTEGER,
    current_uses        INTEGER     NOT NULL DEFAULT 0,

    -- Combinación con otras promos
    priority            INTEGER     NOT NULL DEFAULT 100,
    -- menor número = mayor prioridad (10 > 100)
    is_exclusive        BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE = esta promo no se acumula con ninguna otra
    -- FALSE = puede acumularse con otras promos no exclusivas

    -- Filtros de aplicación
    applies_to_channels     JSONB,
    -- NULL = todos | ["direct","ecommerce","pos"] IDs de canales
    applies_to_customer_groups JSONB,
    -- NULL = todos | [1, 2] IDs de customer_groups

    -- Código de cupón (si requiere código para activarse)
    coupon_code         VARCHAR(50),
    -- NULL = se aplica automáticamente sin código

    -- Visualización para el cliente
    promo_badge         VARCHAR(100),
    -- "JULIO ESCOLAR", "BLACK FRIDAY", "2X1 JABAS"

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    created_by          BIGINT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE INDEX idx_promotions_company    ON sales.promotions (company_id);
CREATE INDEX idx_promotions_valid_from ON sales.promotions (valid_from);
CREATE INDEX idx_promotions_valid_to   ON sales.promotions (valid_to);
CREATE INDEX idx_promotions_active     ON sales.promotions (is_active);

CREATE TRIGGER trg_promotions_updated_at
    BEFORE UPDATE ON sales.promotions
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.promotions              IS 'Cabecera de promociones. Define tipo, vigencia, prioridad y si es exclusiva (no acumulable).';
COMMENT ON COLUMN sales.promotions.promo_type   IS 'Tipo: percentage_off | fixed_amount_off | fixed_price | free_item | bogo | bundle | free_shipping.';
COMMENT ON COLUMN sales.promotions.is_exclusive IS 'TRUE = esta promo bloquea las demás. FALSE = puede coexistir con otras promos no exclusivas.';
COMMENT ON COLUMN sales.promotions.priority     IS 'Menor número = mayor prioridad. Si dos promos exclusivas aplican, gana la de menor priority.';

-- ============================================================
-- 2. CONDICIONES DE LA PROMOCIÓN
--    Qué tiene que ocurrir para que la promo se active.
--    Una promo puede tener múltiples condiciones (se evalúan con AND).
-- ============================================================
CREATE TABLE sales.promotion_conditions (
    id                  BIGSERIAL   PRIMARY KEY,
    promotion_id        BIGINT      NOT NULL REFERENCES sales.promotions(id) ON DELETE CASCADE,

    condition_type      VARCHAR(40) NOT NULL,
    -- min_order_amount   : monto mínimo de la orden (ej: compra desde S/200)
    -- min_quantity       : cantidad mínima de un producto específico
    -- specific_product   : solo si el producto X está en la orden
    -- specific_category  : solo si hay al menos 1 producto de la categoría Y
    -- specific_customer_group : solo para clientes del grupo Z
    -- customer_birthday_month : mes de cumpleaños del cliente
    -- day_of_week        : lunes a viernes (Happy Hour)
    -- time_range         : entre 12:00 y 14:00 (almuerzo)
    -- first_purchase     : solo para la primera compra del cliente
    -- min_loyalty_points : cliente tiene >= X puntos de fidelización

    -- Para condiciones de monto mínimo
    min_amount          NUMERIC(18,4),

    -- Para condiciones de cantidad mínima
    -- Soporta DECIMALES: 2.5 jabas, 1.5 kg, etc.
    min_quantity        NUMERIC(18,4),
    product_id          BIGINT      REFERENCES logistics.products(id),
    variant_id          BIGINT      REFERENCES logistics.product_variants(id),
    category_id         BIGINT      REFERENCES logistics.product_categories(id),

    -- Para condiciones de tiempo / día
    day_of_week         JSONB,
    -- [1,2,3,4,5] = lunes a viernes (ISO: lunes=1, domingo=7)
    time_from           TIME,
    time_to             TIME,

    -- Para puntos de fidelización
    min_loyalty_points  INTEGER,

    -- Parámetros adicionales en JSON
    params              JSONB,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_promo_conditions_promo ON sales.promotion_conditions (promotion_id);

COMMENT ON TABLE  sales.promotion_conditions                  IS 'Condiciones que deben cumplirse para activar la promo. Múltiples condiciones = AND. Soporta cantidades fraccionarias (2.5 jabas).';
COMMENT ON COLUMN sales.promotion_conditions.min_quantity     IS 'Cantidad mínima (acepta decimales). Ej: promo activa si compra >= 2.5 jabas de huevo.';
COMMENT ON COLUMN sales.promotion_conditions.day_of_week     IS 'Array JSON de días ISO (1=lun, 7=dom). Ej: [1,2,3,4,5] = solo días hábiles.';

-- ============================================================
-- 3. EFECTOS DE LA PROMOCIÓN
--    Qué beneficio recibe el cliente cuando la promo aplica.
-- ============================================================
CREATE TABLE sales.promotion_effects (
    id                  BIGSERIAL   PRIMARY KEY,
    promotion_id        BIGINT      NOT NULL REFERENCES sales.promotions(id) ON DELETE CASCADE,

    effect_type         VARCHAR(30) NOT NULL,
    -- percentage_off       : % de descuento sobre el precio
    -- fixed_amount_off     : monto fijo de descuento (S/10)
    -- fixed_price          : precio resultante fijo (S/99 el pack)
    -- free_item            : añade producto gratis a la orden
    -- bogo                 : la 2da unidad (o Y-ésima) es gratis
    -- cheapest_free        : el ítem más barato de la orden es gratis
    -- most_expensive_off   : % de descuento en el ítem más caro
    -- points_multiplier    : multiplica los puntos de fidelización

    -- Parámetros del efecto
    discount_pct        NUMERIC(5,2),
    -- para percentage_off / most_expensive_off
    discount_amount     NUMERIC(18,4),
    -- para fixed_amount_off
    fixed_price         NUMERIC(18,6),
    -- para fixed_price (precio neto resultante, sin IGV)

    -- Para ítems gratuitos (free_item, bogo)
    free_product_id     BIGINT      REFERENCES logistics.products(id),
    free_variant_id     BIGINT      REFERENCES logistics.product_variants(id),
    free_quantity       NUMERIC(18,4),
    -- soporta decimales: 0.5 kg gratis, 1 jaba gratis, etc.

    -- Multiplicador de puntos (para loyalty)
    points_multiplier   NUMERIC(5,2),
    -- Ej: 3.0 = triples los puntos normales

    -- A qué líneas aplica el efecto
    applies_to          VARCHAR(30) NOT NULL DEFAULT 'matching_lines',
    -- matching_lines     : a las líneas que cumplen la condición
    -- all_lines          : a todas las líneas de la orden
    -- order_total        : al total de la orden (un descuento global)
    -- cheapest_line      : a la línea de menor precio
    -- most_expensive_line: a la línea de mayor precio
    -- specific_product   : a un producto específico (free_product_id)

    -- Límites del efecto (para no descuentar más de lo necesario)
    max_discount_amount NUMERIC(18,4),
    -- tope en S/ del descuento (NULL = sin tope)
    max_free_quantity   NUMERIC(18,4),
    -- máximo de cantidad gratuita (para free_item)

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_promo_effects_promo ON sales.promotion_effects (promotion_id);

COMMENT ON TABLE  sales.promotion_effects                  IS 'Beneficio que recibe el cliente cuando la promo aplica. Ej: 20% off, ítem gratis, precio fijo de pack.';
COMMENT ON COLUMN sales.promotion_effects.free_quantity    IS 'Cantidad gratuita. Soporta decimales (0.5 kg gratis, 1 jaba gratis).';
COMMENT ON COLUMN sales.promotion_effects.max_discount_amount IS 'Tope en S/ del descuento. Útil para "10% off con máximo S/50 de descuento".';

-- ============================================================
-- 4. BUNDLE (COMPONENTES DEL PACK)
--    Para promos de tipo bundle: qué productos y cantidades
--    forman el pack y cuál es el precio total del pack.
--    Ej: "Pack Back to School": Laptop + Mouse + Mochila = S/2,500
-- ============================================================
CREATE TABLE sales.promotion_bundles (
    id                  BIGSERIAL   PRIMARY KEY,
    promotion_id        BIGINT      NOT NULL REFERENCES sales.promotions(id) ON DELETE CASCADE,
    product_id          BIGINT      NOT NULL REFERENCES logistics.products(id),
    variant_id          BIGINT      REFERENCES logistics.product_variants(id),

    quantity_required   NUMERIC(18,4) NOT NULL,
    -- cantidad de este producto en el bundle (soporta decimales)

    is_trigger          BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE = comprar este producto activa el bundle
    -- FALSE = es parte del resultado/beneficio del bundle

    -- Para el prorrateo contable del descuento del bundle
    -- El descuento total se distribuye en proporción al precio de cada componente
    price_weight        NUMERIC(5,4) NOT NULL DEFAULT 0,
    -- peso proporcional (se calcula al guardar; suma = 1.0000 en todos los componentes)

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_promo_bundles_promo ON sales.promotion_bundles (promotion_id);

COMMENT ON TABLE  sales.promotion_bundles IS 'Componentes de un bundle. price_weight permite prorratear el descuento del pack entre los componentes para contabilidad correcta.';

-- ============================================================
-- 5. REGISTRO DE PROMOS APLICADAS
--    Por cada orden/factura/POS, qué promo se aplicó,
--    en qué línea y cuánto se ahorró.
--    INMUTABLE — para auditoría y contabilidad.
-- ============================================================
CREATE TABLE sales.promotions_applied (
    id                  BIGSERIAL   PRIMARY KEY,
    promotion_id        BIGINT      NOT NULL REFERENCES sales.promotions(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- Documento donde se aplicó la promo
    reference_type      VARCHAR(20) NOT NULL,
    -- order | quotation | pos_transaction
    reference_id        BIGINT      NOT NULL,
    line_id             BIGINT,
    -- NULL = descuento al total de la orden

    -- Resultado del efecto
    discount_amount     NUMERIC(18,4) NOT NULL DEFAULT 0,
    free_quantity       NUMERIC(18,4),
    free_product_id     BIGINT      REFERENCES logistics.products(id),

    -- Descripción del beneficio (para imprimir en boleta / email)
    benefit_description VARCHAR(300),
    -- "2x1 Jabas de Huevo: 1 jaba gratis (ahorraste S/32.50)"
    -- "Promo Julio Escolar: 20% off → ahorraste S/24.00"

    -- Uso del cupón (si aplica)
    coupon_code_used    VARCHAR(50),

    applied_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE: sin updated_at
);

CREATE INDEX idx_promos_applied_promo     ON sales.promotions_applied (promotion_id);
CREATE INDEX idx_promos_applied_reference ON sales.promotions_applied (reference_type, reference_id);

COMMENT ON TABLE  sales.promotions_applied IS 'Registro inmutable de qué promos se aplicaron y cuánto se ahorró. Base para reportes de efectividad de promos y contabilidad del costo de descuentos.';

-- ============================================================
-- 6. LÍMITE DE DESCUENTO POR VENDEDOR
--    Hasta qué % puede rebajar el vendedor sin necesitar aprobación.
--    Inspirado en SAP SD "condition exclusion" + jerarquía de aprobación.
-- ============================================================
CREATE TABLE sales.sales_rep_discount_limits (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    sales_rep_id        BIGINT      NOT NULL REFERENCES sales.sales_reps(id),

    -- Límite por categoría de producto (NULL = aplica a todos)
    category_id         BIGINT      REFERENCES logistics.product_categories(id),

    max_discount_pct    NUMERIC(5,2) NOT NULL DEFAULT 5,
    -- % máximo que puede dar sin aprobación
    max_discount_amount NUMERIC(18,4),
    -- monto máximo de descuento (aplica el menor entre % y monto)

    -- Quién aprueba cuando supera el límite
    approver_id         BIGINT      REFERENCES sales.sales_reps(id),
    -- NULL = usa el supervisor del vendedor en hr.employees

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, sales_rep_id, category_id)
);

CREATE TRIGGER trg_rep_discount_limits_updated_at
    BEFORE UPDATE ON sales.sales_rep_discount_limits
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.sales_rep_discount_limits                  IS 'Límite de descuento que puede dar el vendedor sin aprobación. Si el ad-hoc supera el límite, va al flujo de aprobación.';
COMMENT ON COLUMN sales.sales_rep_discount_limits.max_discount_pct IS '% máximo de descuento sin necesitar aprobación. Ej: 5% → el vendedor puede dar hasta 5% solo.';

-- ============================================================
-- 7. DESCUENTOS AD-HOC (LA "REBAJA PERUANA")
--    Descuento manual en el momento de la venta.
--    El vendedor rebaja porque el cliente lo pide, por
--    precio de competencia, producto dañado, cliente fiel, etc.
--
--    Flujo:
--      1. Vendedor pone el descuento en la orden
--      2. Sistema verifica vs sales_rep_discount_limits
--      3. Si supera límite → genera aprobación pendiente
--      4. Supervisor aprueba/rechaza (en app o via WhatsApp)
--      5. Si rechazado → precio vuelve al original
-- ============================================================
CREATE TABLE sales.ad_hoc_price_overrides (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- Documento donde se aplica el descuento
    reference_type      VARCHAR(20) NOT NULL,
    -- order | quotation | pos_transaction
    reference_id        BIGINT      NOT NULL,
    line_id             BIGINT,
    -- NULL = descuento al total de la orden

    -- Tipo de override
    override_type       VARCHAR(20) NOT NULL DEFAULT 'percentage',
    -- percentage    : % de descuento sobre el precio
    -- fixed_amount  : monto fijo de descuento
    -- fixed_price   : precio fijo resultante (el cliente pide "ponme a S/180")

    override_pct        NUMERIC(5,2),
    override_amount     NUMERIC(18,4),
    override_price      NUMERIC(18,6),

    -- Para auditoría
    original_price      NUMERIC(18,6) NOT NULL,
    final_price         NUMERIC(18,6) NOT NULL,
    discount_given      NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- monto total de descuento otorgado

    -- Motivo (el vendedor debe justificarlo)
    reason_code         VARCHAR(30),
    -- customer_request | competitor_price | damaged_goods
    -- loyalty | bulk_deal | sample | other
    reason_notes        TEXT,

    -- Trazabilidad
    requested_by        BIGINT      NOT NULL,
    -- REFERENCES hr.employees(id) — el vendedor que pidió el descuento

    -- Flujo de aprobación
    requires_approval   BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE si el descuento supera el límite del vendedor

    approved_by         BIGINT,
    -- REFERENCES hr.employees(id) — supervisor que aprobó
    approved_at         TIMESTAMPTZ,

    approval_status     VARCHAR(20) NOT NULL DEFAULT 'auto_approved',
    -- auto_approved : dentro del límite, no necesita aprobación
    -- pending       : esperando aprobación del supervisor
    -- approved      : supervisor aprobó
    -- rejected      : supervisor rechazó → precio vuelve al original

    rejection_notes     TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_adhoc_overrides_reference ON sales.ad_hoc_price_overrides (reference_type, reference_id);
CREATE INDEX idx_adhoc_overrides_requester ON sales.ad_hoc_price_overrides (requested_by);
CREATE INDEX idx_adhoc_overrides_approval  ON sales.ad_hoc_price_overrides (approval_status)
    WHERE approval_status = 'pending';

CREATE TRIGGER trg_adhoc_overrides_updated_at
    BEFORE UPDATE ON sales.ad_hoc_price_overrides
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.ad_hoc_price_overrides                   IS 'La rebaja peruana: descuento manual del vendedor. Si supera su límite aprobado, requiere autorización del supervisor. Registro completo para auditoría.';
COMMENT ON COLUMN sales.ad_hoc_price_overrides.reason_code       IS 'Motivo: customer_request | competitor_price | damaged_goods | loyalty | bulk_deal | sample | other.';
COMMENT ON COLUMN sales.ad_hoc_price_overrides.approval_status   IS 'auto_approved=dentro del límite | pending=esperando supervisor | approved=aprobado | rejected=rechazado (precio vuelve al original).';

-- ============================================================
-- 8. ACUERDOS DE REBATE (DESCUENTO RETROACTIVO)
--    Usado por grandes cadenas: el proveedor devuelve un %
--    al cierre del período según el volumen acumulado.
--
--    Ej real: Saga Falabella negocia con Alicorp:
--      - S/0-299K compradas: 1% de rebate
--      - S/300K-499K:        1.5% de rebate
--      - S/500K+:            2.5% de rebate
--    Al 31-dic, si compraron S/620K → Alicorp emite NC por S/15,500
--
--    El sistema provisiona mensualmente (rebate_accruals) para que
--    finanzas pueda ver la provisión y no se lleven sorpresas.
-- ============================================================
CREATE TABLE sales.rebate_agreements (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    customer_id         BIGINT      NOT NULL REFERENCES sales.customers(id),

    code                VARCHAR(30) NOT NULL,
    name                VARCHAR(300) NOT NULL,

    -- Período del acuerdo
    start_date          DATE        NOT NULL,
    end_date            DATE        NOT NULL,

    -- Base de cálculo del rebate
    basis_type          VARCHAR(30) NOT NULL DEFAULT 'net_sales',
    -- net_sales    = sobre ventas netas (sin IGV, sin devoluciones)
    -- gross_margin = sobre margen bruto
    -- quantity     = por volumen de unidades

    -- Filtro de productos (NULL = todas las compras del cliente)
    product_id          BIGINT      REFERENCES logistics.products(id),
    category_id         BIGINT      REFERENCES logistics.product_categories(id),

    -- Tramos de rebate (JSONB — flexible para cualquier estructura)
    tiers               JSONB       NOT NULL,
    -- Formato:
    -- [
    --   {"min": 0,      "max": 299999.99, "rebate_pct": 1.0},
    --   {"min": 300000, "max": 499999.99, "rebate_pct": 1.5},
    --   {"min": 500000, "max": null,      "rebate_pct": 2.5}
    -- ]
    -- max: null = sin límite superior

    -- Acumulado actual (actualizado cada vez que se valida una factura)
    accrued_basis       NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- suma de ventas netas que cuentan para el rebate
    accrued_rebate      NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- provisión acumulada hasta hoy

    -- Frecuencia de liquidación (cuando se emite la NC al cliente)
    settlement_frequency VARCHAR(20) NOT NULL DEFAULT 'annual',
    -- monthly | quarterly | annual | on_close

    last_settlement_date DATE,
    total_settled        NUMERIC(18,4) NOT NULL DEFAULT 0,

    status              VARCHAR(20) NOT NULL DEFAULT 'active',
    -- active | settled | expired | cancelled

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    notes               TEXT,
    created_by          BIGINT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE INDEX idx_rebate_agreements_customer ON sales.rebate_agreements (customer_id);
CREATE INDEX idx_rebate_agreements_company  ON sales.rebate_agreements (company_id);
CREATE INDEX idx_rebate_agreements_status   ON sales.rebate_agreements (status);

CREATE TRIGGER trg_rebate_agreements_updated_at
    BEFORE UPDATE ON sales.rebate_agreements
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.rebate_agreements        IS 'Acuerdos de rebate retroactivo (SAP SD style). Provisión mensual + liquidación con Nota de Crédito al cierre del período.';
COMMENT ON COLUMN sales.rebate_agreements.tiers  IS 'JSON de tramos: [{min, max, rebate_pct}]. max: null = sin límite. La base acumulada se compara contra estos tramos para determinar el % que aplica.';
COMMENT ON COLUMN sales.rebate_agreements.accrued_rebate IS 'Provisión acumulada hasta el día de hoy. Lo que finanzas debe reservar como pasivo.';

-- ============================================================
-- 9. PROVISIONES DE REBATE (inmutable — libro mayor)
--    Cada mes se registra la provisión del período.
--    Al liquidar, se registra la NC y se cierra el período.
-- ============================================================
CREATE TABLE sales.rebate_accruals (
    id                      BIGSERIAL   PRIMARY KEY,
    rebate_agreement_id     BIGINT      NOT NULL REFERENCES sales.rebate_agreements(id),
    company_id              BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- Período (primer día del mes)
    period_date             DATE        NOT NULL,
    -- 2026-01-01 = provisión de enero 2026

    -- Documento que generó la provisión (puede ser NULL si es cálculo mensual global)
    invoice_id              BIGINT      REFERENCES sales.invoices(id),

    -- Montos del período
    basis_amount            NUMERIC(18,4) NOT NULL,
    -- ventas netas del período que cuentan para el rebate
    rebate_pct              NUMERIC(5,2) NOT NULL,
    -- % aplicado según el tramo alcanzado a esta fecha
    accrual_amount          NUMERIC(18,4) NOT NULL,
    -- provisión del período: basis_amount × rebate_pct / 100

    accrual_type            VARCHAR(20) NOT NULL DEFAULT 'monthly',
    -- monthly    = provisión mensual automática
    -- settlement = liquidación final (NC emitida)
    -- reversal   = reversión de provisión
    -- adjustment = ajuste manual

    -- Si es liquidación, referencia a la NC emitida al cliente
    credit_note_id          BIGINT      REFERENCES sales.credit_notes(id),

    -- Acumulado después de esta entrada (para auditoría rápida)
    cumulative_basis        NUMERIC(18,4) NOT NULL DEFAULT 0,
    cumulative_accrual      NUMERIC(18,4) NOT NULL DEFAULT 0,

    notes                   TEXT,
    created_by              BIGINT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE: sin updated_at (igual que inventory_transactions)
);

CREATE INDEX idx_rebate_accruals_agreement ON sales.rebate_accruals (rebate_agreement_id);
CREATE INDEX idx_rebate_accruals_period    ON sales.rebate_accruals (period_date);
CREATE INDEX idx_rebate_accruals_invoice   ON sales.rebate_accruals (invoice_id)
    WHERE invoice_id IS NOT NULL;

COMMENT ON TABLE  sales.rebate_accruals IS 'Libro mayor inmutable de provisiones de rebate. Una fila por mes (o por factura). La liquidación crea una fila tipo "settlement" con referencia a la NC emitida.';
