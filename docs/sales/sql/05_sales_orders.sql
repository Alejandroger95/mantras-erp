-- ============================================================
-- mantrasdb | Módulo Sales
-- Archivo: 05_sales_orders.sql
-- Descripción: Órdenes de venta y su conexión con Logistics.
--
-- Flujo:
--   quotation (approved) → sales_order → logistics.outbound_order
--                                           → wave → pick → ship
--   sales_order → invoice (en 06_invoicing.sql)
-- ============================================================

-- ============================================================
-- Órdenes de venta
-- ============================================================
CREATE TABLE sales.sales_orders (
    id                      BIGSERIAL   PRIMARY KEY,
    company_id              BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    order_status_id         INTEGER     NOT NULL REFERENCES sales.order_statuses(id),
    order_type_id           INTEGER     NOT NULL REFERENCES sales.order_types(id),
    customer_id             BIGINT      NOT NULL REFERENCES sales.customers(id),
    customer_contact_id     BIGINT      REFERENCES sales.customer_contacts(id),
    price_list_id           BIGINT      REFERENCES sales.price_lists(id),
    payment_terms_id        INTEGER     REFERENCES sales.payment_terms_catalog(id),

    -- Numeración
    order_number            VARCHAR(50) NOT NULL,
    customer_po_number      VARCHAR(100),
    -- número de orden de compra del cliente

    -- Origen
    quotation_id            BIGINT      REFERENCES sales.quotations(id),
    -- si viene de una cotización aprobada

    -- Fechas
    order_date              DATE        NOT NULL DEFAULT CURRENT_DATE,
    requested_date          DATE,
    -- fecha solicitada por el cliente
    promised_date           DATE,
    -- fecha prometida por nosotros
    confirmed_date          DATE,

    -- Dirección de entrega
    delivery_address_id     BIGINT      REFERENCES sales.customer_addresses(id),
    delivery_address_text   VARCHAR(300),
    -- dirección en texto libre (si no está en el catálogo)
    delivery_notes          TEXT,

    -- Almacén de despacho
    warehouse_id            BIGINT      REFERENCES logistics.warehouses(id),

    -- Moneda y totales
    currency                VARCHAR(10) NOT NULL DEFAULT 'PEN',
    exchange_rate           NUMERIC(12,6) NOT NULL DEFAULT 1,
    subtotal                NUMERIC(18,4) NOT NULL DEFAULT 0,
    discount_amount         NUMERIC(18,4) NOT NULL DEFAULT 0,
    tax_amount              NUMERIC(18,4) NOT NULL DEFAULT 0,
    total_amount            NUMERIC(18,4) NOT NULL DEFAULT 0,

    -- Estado de pago
    payment_status_id       INTEGER     REFERENCES sales.payment_statuses(id),
    amount_paid             NUMERIC(18,4) NOT NULL DEFAULT 0,
    amount_pending          NUMERIC(18,4)
        GENERATED ALWAYS AS (total_amount - amount_paid) STORED,

    -- Vendedor y canal
    sales_rep_id            BIGINT,
    -- REFERENCES sales.sales_reps(id) — FK diferida
    sales_channel           VARCHAR(30) NOT NULL DEFAULT 'direct',

    -- Referencia al despacho en Logistics
    outbound_order_id       BIGINT,
    -- REFERENCES logistics.outbound_orders(id) — FK diferida

    -- Factura principal generada
    invoice_id              BIGINT,
    -- REFERENCES sales.invoices(id) — FK diferida

    notes                   TEXT,
    internal_notes          TEXT,
    is_active               BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, order_number)
);

CREATE INDEX idx_sales_orders_company  ON sales.sales_orders (company_id);
CREATE INDEX idx_sales_orders_customer ON sales.sales_orders (customer_id);
CREATE INDEX idx_sales_orders_status   ON sales.sales_orders (order_status_id);
CREATE INDEX idx_sales_orders_date     ON sales.sales_orders (order_date);
CREATE INDEX idx_sales_orders_rep      ON sales.sales_orders (sales_rep_id);
CREATE INDEX idx_sales_orders_quotation ON sales.sales_orders (quotation_id);

CREATE TRIGGER trg_sales_orders_updated_at
    BEFORE UPDATE ON sales.sales_orders
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.sales_orders                    IS 'Órdenes de venta confirmadas. Generan outbound_order en Logistics y facturas en Sales.';
COMMENT ON COLUMN sales.sales_orders.customer_po_number IS 'Número de orden de compra del cliente. Imprescindible en ventas B2B para la validación del pago.';
COMMENT ON COLUMN sales.sales_orders.amount_pending     IS 'Calculado: total - pagado. Saldo pendiente del cliente.';

-- ============================================================
-- Líneas de orden de venta
-- ============================================================
CREATE TABLE sales.sales_order_lines (
    id                      BIGSERIAL   PRIMARY KEY,
    sales_order_id          BIGINT      NOT NULL REFERENCES sales.sales_orders(id) ON DELETE RESTRICT,
    product_id              BIGINT      NOT NULL REFERENCES logistics.products(id),
    variant_id              BIGINT      REFERENCES logistics.product_variants(id),
    unit_id                 INTEGER     NOT NULL REFERENCES logistics.measurement_units(id),

    line_number             INTEGER     NOT NULL,
    description             VARCHAR(500),

    -- Cantidades con seguimiento por etapa
    quantity_ordered        NUMERIC(18,4) NOT NULL,
    quantity_delivered      NUMERIC(18,4) NOT NULL DEFAULT 0,
    quantity_invoiced       NUMERIC(18,4) NOT NULL DEFAULT 0,
    quantity_pending        NUMERIC(18,4)
        GENERATED ALWAYS AS (quantity_ordered - quantity_delivered) STORED,

    -- Precio
    unit_price              NUMERIC(18,6) NOT NULL,
    discount_pct            NUMERIC(5,2)  NOT NULL DEFAULT 0,
    discount_amount         NUMERIC(18,4) NOT NULL DEFAULT 0,
    tax_rate_id             INTEGER       REFERENCES sales.tax_rates(id),
    tax_pct                 NUMERIC(5,2)  NOT NULL DEFAULT 18,

    net_price               NUMERIC(18,6) NOT NULL DEFAULT 0,
    line_total              NUMERIC(18,4) NOT NULL DEFAULT 0,
    line_tax                NUMERIC(18,4) NOT NULL DEFAULT 0,
    line_total_with_tax     NUMERIC(18,4) NOT NULL DEFAULT 0,

    -- Referencia a la cotización origen
    quotation_line_id       BIGINT      REFERENCES sales.quotation_lines(id),

    requested_date          DATE,
    notes                   TEXT,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (sales_order_id, line_number)
);

CREATE INDEX idx_so_lines_order   ON sales.sales_order_lines (sales_order_id);
CREATE INDEX idx_so_lines_product ON sales.sales_order_lines (product_id);

CREATE TRIGGER trg_so_lines_updated_at
    BEFORE UPDATE ON sales.sales_order_lines
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.sales_order_lines                  IS 'Líneas de orden de venta con tracking de cantidad entregada e invoiced.';
COMMENT ON COLUMN sales.sales_order_lines.quantity_pending IS 'Calculado: ordenado - entregado. Pendiente de despachar.';

-- ============================================================
-- Programación de entregas (cuando hay múltiples fechas)
-- ============================================================
CREATE TABLE sales.delivery_schedules (
    id                  BIGSERIAL   PRIMARY KEY,
    sales_order_line_id BIGINT      NOT NULL REFERENCES sales.sales_order_lines(id),
    product_id          BIGINT      NOT NULL REFERENCES logistics.products(id),
    unit_id             INTEGER     NOT NULL REFERENCES logistics.measurement_units(id),

    scheduled_date      DATE        NOT NULL,
    quantity_scheduled  NUMERIC(18,4) NOT NULL,
    quantity_delivered  NUMERIC(18,4) NOT NULL DEFAULT 0,

    status              VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending | confirmed | delivered | cancelled

    warehouse_id        BIGINT      REFERENCES logistics.warehouses(id),
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_delivery_schedules_line ON sales.delivery_schedules (sales_order_line_id);
CREATE INDEX idx_delivery_schedules_date ON sales.delivery_schedules (scheduled_date);

CREATE TRIGGER trg_delivery_schedules_updated_at
    BEFORE UPDATE ON sales.delivery_schedules
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE sales.delivery_schedules IS 'Programación de entregas parciales. Una línea puede tener múltiples fechas de entrega (entregas programadas).';
