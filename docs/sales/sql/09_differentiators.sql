-- ============================================================
-- mantrasdb | Módulo Sales
-- Archivo: 09_differentiators.sql
-- Descripción: Diferenciadores del módulo de ventas:
--   1. Canal de ventas multicanal (WhatsApp, ecommerce, etc.)
--   2. Programa de fidelización (puntos y canjes)
--   3. Forecast de ventas
--   4. FKs diferidas (sales_orders → invoices, quotations)
-- ============================================================

-- ============================================================
-- 1. CANAL DE VENTAS Y CONVERSIÓN
--    Permite medir de dónde vienen las ventas y la tasa
--    de conversión cotización → orden por canal.
-- ============================================================
CREATE TABLE sales.sales_channels (
    id              BIGSERIAL   PRIMARY KEY,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    code            VARCHAR(30) NOT NULL,
    name            VARCHAR(100) NOT NULL,
    channel_type    VARCHAR(30) NOT NULL DEFAULT 'direct',
    -- direct | ecommerce | marketplace | whatsapp | phone |
    -- distributor | retail | b2b_portal

    -- Comisión del canal (si aplica, e.g. marketplace cobra %)
    platform_fee_pct    NUMERIC(5,2) NOT NULL DEFAULT 0,

    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (company_id, code)
);

CREATE TRIGGER trg_sales_channels_updated_at
    BEFORE UPDATE ON sales.sales_channels
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE sales.sales_channels IS 'Canales de venta: directo, ecommerce, WhatsApp, marketplace. Para análisis de conversión y rentabilidad por canal.';

-- ============================================================
-- 2. PROGRAMA DE FIDELIZACIÓN
--    Clientes acumulan puntos por compras y los canjean
--    por descuentos o productos.
-- ============================================================
CREATE TABLE sales.loyalty_transactions (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    customer_id         BIGINT      NOT NULL REFERENCES sales.customers(id),

    transaction_type    VARCHAR(20) NOT NULL,
    -- earn | redeem | expire | adjust | bonus

    points              INTEGER     NOT NULL,
    -- positivo=ganó, negativo=canjeó/expiró

    -- Referencia al evento que generó el movimiento
    reference_type      VARCHAR(30),
    -- invoice | credit_note | manual | promo
    reference_id        BIGINT,

    -- Descripción para el cliente
    description         VARCHAR(200),
    -- "Compra factura F001-00123", "Canje por descuento S/20"

    expiry_date         DATE,
    -- fecha en que expiran estos puntos

    balance_after       INTEGER     NOT NULL DEFAULT 0,
    -- saldo de puntos después de esta transacción

    performed_by        BIGINT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_loyalty_customer ON sales.loyalty_transactions (customer_id);
CREATE INDEX idx_loyalty_company  ON sales.loyalty_transactions (company_id);
CREATE INDEX idx_loyalty_expiry   ON sales.loyalty_transactions (expiry_date)
    WHERE expiry_date IS NOT NULL AND transaction_type = 'earn';

COMMENT ON TABLE  sales.loyalty_transactions             IS 'Libro mayor de puntos de fidelización. Inmutable — registra cada ganancia, canje y expiración.';
COMMENT ON COLUMN sales.loyalty_transactions.points      IS 'Positivo=ganó puntos (earn/bonus). Negativo=canjeó o expiraron.';
COMMENT ON COLUMN sales.loyalty_transactions.balance_after IS 'Saldo de puntos del cliente después de esta transacción. Facilita auditoría sin recalcular.';

-- ============================================================
-- Reglas de acumulación de puntos
-- ============================================================
CREATE TABLE sales.loyalty_rules (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    name                VARCHAR(200) NOT NULL,

    -- Criterio
    product_id          BIGINT      REFERENCES logistics.products(id),
    category_id         BIGINT      REFERENCES logistics.product_categories(id),
    customer_group_id   BIGINT      REFERENCES sales.customer_groups(id),
    -- NULL = aplica a todo

    -- Puntos
    points_per_currency NUMERIC(8,4) NOT NULL DEFAULT 1,
    -- puntos por cada S/ (o USD) gastado
    min_purchase_amount NUMERIC(18,4),
    -- monto mínimo de compra para acumular

    -- Vigencia
    valid_from          DATE,
    valid_to            DATE,

    points_expiry_days  INTEGER,
    -- cuántos días tienen validez los puntos ganados con esta regla

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_loyalty_rules_updated_at
    BEFORE UPDATE ON sales.loyalty_rules
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE sales.loyalty_rules IS 'Reglas de acumulación de puntos por producto, categoría o grupo de cliente.';

-- ============================================================
-- 3. FORECAST DE VENTAS
--    Proyecciones por vendedor, cliente o producto.
--    Permite comparar forecast vs real al cierre del mes.
-- ============================================================
CREATE TABLE sales.sales_forecasts (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    sales_rep_id        BIGINT      REFERENCES sales.sales_reps(id),
    customer_id         BIGINT      REFERENCES sales.customers(id),
    product_id          BIGINT      REFERENCES logistics.products(id),
    category_id         BIGINT      REFERENCES logistics.product_categories(id),

    forecast_period     DATE        NOT NULL,
    -- primer día del mes proyectado (2026-08-01)
    period_type         VARCHAR(20) NOT NULL DEFAULT 'monthly',

    -- Proyección
    forecast_amount     NUMERIC(18,4) NOT NULL DEFAULT 0,
    forecast_quantity   NUMERIC(18,4),
    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',

    -- Real al cierre (se actualiza al final del período)
    actual_amount       NUMERIC(18,4),
    actual_quantity     NUMERIC(18,4),

    -- Desviación
    variance_amount     NUMERIC(18,4)
        GENERATED ALWAYS AS (
            COALESCE(actual_amount, 0) - forecast_amount
        ) STORED,
    variance_pct        NUMERIC(8,2)
        GENERATED ALWAYS AS (
            CASE WHEN forecast_amount > 0
                 THEN ROUND(((COALESCE(actual_amount, 0) - forecast_amount) / forecast_amount * 100)::NUMERIC, 2)
                 ELSE NULL
            END
        ) STORED,

    notes               TEXT,
    created_by          BIGINT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, sales_rep_id, customer_id, product_id, forecast_period, period_type)
);

CREATE INDEX idx_forecasts_company ON sales.sales_forecasts (company_id);
CREATE INDEX idx_forecasts_period  ON sales.sales_forecasts (forecast_period);
CREATE INDEX idx_forecasts_rep     ON sales.sales_forecasts (sales_rep_id);

CREATE TRIGGER trg_forecasts_updated_at
    BEFORE UPDATE ON sales.sales_forecasts
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.sales_forecasts              IS 'Forecast de ventas por vendedor, cliente y/o producto. Se compara contra el real al cierre del período.';
COMMENT ON COLUMN sales.sales_forecasts.variance_pct IS 'Calculado: (real - forecast) / forecast × 100. Positivo=sobre-cumplimiento, negativo=brecha.';

-- ============================================================
-- 4. FKs DIFERIDAS
--    Resolvemos las referencias circulares ahora que todas
--    las tablas de Sales están creadas.
-- ============================================================

-- quotations → sales_orders (cuando se convierte)
ALTER TABLE sales.quotations
    ADD CONSTRAINT fk_quotations_converted_order
    FOREIGN KEY (converted_to_order_id)
    REFERENCES sales.sales_orders(id)
    ON DELETE SET NULL;

-- sales_orders → invoices (factura generada)
ALTER TABLE sales.sales_orders
    ADD CONSTRAINT fk_sales_orders_invoice
    FOREIGN KEY (invoice_id)
    REFERENCES sales.invoices(id)
    ON DELETE SET NULL;

-- sales_orders → logistics.outbound_orders (despacho)
ALTER TABLE sales.sales_orders
    ADD CONSTRAINT fk_sales_orders_outbound
    FOREIGN KEY (outbound_order_id)
    REFERENCES logistics.outbound_orders(id)
    ON DELETE SET NULL;

-- ============================================================
-- 5. MOTIVOS DE ANULACIÓN
--    Catálogo de categorías de anulación para órdenes,
--    facturas y cotizaciones. Con auditoría completa:
--    quién anuló, cuándo y por qué.
--
--    Flujo de anulación de una orden:
--      1. Cambiar order_status → 'cancelled'
--      2. Registrar cancellation_reason_id + notes + cancelled_by
--      3. Si hay outbound_order → cancelar en logistics
--      4. Si hay invoice emitida → emitir credit_note con reason_code '01'
--      5. Si hay inventory descontado → inventory_transaction positiva (devuelve stock)
--
--    Flujo de anulación de una factura:
--      1. Cambiar invoice_status → 'cancelled'
--      2. Enviar NC a SUNAT con razón '01 - Anulación'
--      3. SUNAT marca el comprobante como inválido
--      4. Registrar cancellation_reason_id + cancelled_by + cancelled_at
-- ============================================================
CREATE TABLE sales.cancellation_reasons (
    id              SERIAL      PRIMARY KEY,
    company_id      BIGINT      REFERENCES hr.companies(id),
    -- NULL = razón global del sistema (pre-cargada)

    code            VARCHAR(30) NOT NULL,
    name            VARCHAR(200) NOT NULL,

    applies_to      VARCHAR(20) NOT NULL DEFAULT 'all',
    -- all | order | invoice | quotation | pos_transaction

    requires_notes  BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE = el usuario DEBE escribir una descripción adicional

    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (code)
);

-- Catálogo pre-cargado (company_id = NULL = globales del sistema)
INSERT INTO sales.cancellation_reasons
    (code, name, applies_to, requires_notes)
VALUES
    ('PRECIO_ERROR',     'Error en el precio',              'all',             FALSE),
    ('DUPLICADO',        'Documento duplicado',             'all',             FALSE),
    ('CLIENTE_ERROR',    'Cliente incorrecto',              'all',             FALSE),
    ('PRODUCTO_ERROR',   'Producto incorrecto',             'all',             FALSE),
    ('CANTIDAD_ERROR',   'Cantidad incorrecta',             'all',             FALSE),
    ('SOLICITUD_CLIENTE','Solicitud del cliente',           'all',             TRUE),
    ('NO_STOCK',         'Sin stock disponible',            'order',           FALSE),
    ('PAGO_RECHAZADO',   'Pago rechazado / no efectuado',  'invoice',         FALSE),
    ('CLIENTE_CANCELO',  'Cliente canceló el pedido',       'order',           TRUE),
    ('DEVOLUCION',       'Devolución de mercadería',        'invoice',         FALSE),
    ('ERROR_SISTEMA',    'Error del sistema',               'all',             TRUE),
    ('PRUEBA',           'Documento de prueba / test',      'all',             FALSE),
    ('OTROS',            'Otros motivos',                   'all',             TRUE);

COMMENT ON TABLE  sales.cancellation_reasons              IS 'Catálogo de categorías de anulación. applies_to filtra qué tipo de documento puede usar cada razón.';
COMMENT ON COLUMN sales.cancellation_reasons.requires_notes IS 'Si TRUE, el sistema obliga al usuario a escribir cancellation_notes al anular.';

-- ─── Campos de anulación en sales_orders ───────────────────
ALTER TABLE sales.sales_orders
    ADD COLUMN cancellation_reason_id  INTEGER     REFERENCES sales.cancellation_reasons(id),
    ADD COLUMN cancellation_notes      TEXT,
    ADD COLUMN cancelled_at            TIMESTAMPTZ,
    ADD COLUMN cancelled_by            BIGINT;
    -- cancelled_by REFERENCES hr.employees(id) — sin FK para evitar dependencia circular

COMMENT ON COLUMN sales.sales_orders.cancellation_reason_id IS 'Categoría de anulación. Obligatorio cuando order_status = cancelled.';
COMMENT ON COLUMN sales.sales_orders.cancelled_at           IS 'Timestamp de anulación. El inventario se revierte en este momento.';
COMMENT ON COLUMN sales.sales_orders.cancelled_by           IS 'ID del empleado que anuló la orden (hr.employees). Para auditoría.';

-- ─── Campos de anulación en invoices ───────────────────────
ALTER TABLE sales.invoices
    ADD COLUMN cancellation_reason_id  INTEGER     REFERENCES sales.cancellation_reasons(id),
    ADD COLUMN cancellation_notes      TEXT,
    ADD COLUMN cancelled_at            TIMESTAMPTZ,
    ADD COLUMN cancelled_by            BIGINT;
    -- La anulación de una factura SUNAT requiere NC con reason_code '01'

COMMENT ON COLUMN sales.invoices.cancellation_reason_id IS 'Categoría de anulación. La anulación electrónica requiere NC a SUNAT (reason_code 01).';
COMMENT ON COLUMN sales.invoices.cancellation_notes     IS 'Descripción libre del motivo. Aparece en el XML de la Nota de Crédito de anulación.';
COMMENT ON COLUMN sales.invoices.cancelled_at           IS 'Timestamp de anulación. Después de este momento la factura no tiene valor legal.';

-- ─── Campos de anulación en quotations ─────────────────────
ALTER TABLE sales.quotations
    ADD COLUMN cancellation_reason_id  INTEGER     REFERENCES sales.cancellation_reasons(id),
    ADD COLUMN cancellation_notes      TEXT;

COMMENT ON COLUMN sales.quotations.cancellation_reason_id IS 'Motivo por el que se rechazó o anuló la cotización.';
