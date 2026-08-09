-- ============================================================
-- mantrasdb | Módulo Sales
-- Archivo: 04_quotations.sql
-- Descripción: Cotizaciones (proformas) y su ciclo de vida.
--
-- Flujo:
--   quotation (draft) → sent → approved → sales_order
--              ↓
--           rejected / expired
-- ============================================================

-- ============================================================
-- Cotizaciones
-- ============================================================
CREATE TABLE sales.quotations (
    id                      BIGSERIAL   PRIMARY KEY,
    company_id              BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    quotation_status_id     INTEGER     NOT NULL REFERENCES sales.quotation_statuses(id),
    customer_id             BIGINT      NOT NULL REFERENCES sales.customers(id),
    customer_contact_id     BIGINT      REFERENCES sales.customer_contacts(id),
    price_list_id           BIGINT      REFERENCES sales.price_lists(id),
    payment_terms_id        INTEGER     REFERENCES sales.payment_terms_catalog(id),

    -- Numeración
    quotation_number        VARCHAR(50) NOT NULL,
    -- referencia del cliente (su número de RFQ)
    customer_reference      VARCHAR(100),

    -- Fechas
    quotation_date          DATE        NOT NULL DEFAULT CURRENT_DATE,
    valid_until             DATE,
    -- fecha de vencimiento de la oferta

    -- Dirección de entrega
    delivery_address_id     BIGINT      REFERENCES sales.customer_addresses(id),
    delivery_notes          TEXT,
    requested_delivery_date DATE,

    -- Moneda y totales
    currency                VARCHAR(10) NOT NULL DEFAULT 'PEN',
    exchange_rate           NUMERIC(12,6) NOT NULL DEFAULT 1,
    -- tipo de cambio si la moneda no es PEN

    subtotal                NUMERIC(18,4) NOT NULL DEFAULT 0,
    discount_amount         NUMERIC(18,4) NOT NULL DEFAULT 0,
    tax_amount              NUMERIC(18,4) NOT NULL DEFAULT 0,
    total_amount            NUMERIC(18,4) NOT NULL DEFAULT 0,

    -- Vendedor
    sales_rep_id            BIGINT,
    -- REFERENCES sales.sales_reps(id) — FK diferida

    -- Canal de venta
    sales_channel           VARCHAR(30) NOT NULL DEFAULT 'direct',
    -- direct | ecommerce | marketplace | phone | whatsapp | distributor

    -- ¿Se convirtió en orden?
    converted_to_order_id   BIGINT,
    -- REFERENCES sales.sales_orders(id) — FK diferida

    notes                   TEXT,
    internal_notes          TEXT,
    -- notas internas que el cliente no ve

    is_active               BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, quotation_number)
);

CREATE INDEX idx_quotations_company  ON sales.quotations (company_id);
CREATE INDEX idx_quotations_customer ON sales.quotations (customer_id);
CREATE INDEX idx_quotations_status   ON sales.quotations (quotation_status_id);
CREATE INDEX idx_quotations_date     ON sales.quotations (quotation_date);
CREATE INDEX idx_quotations_rep      ON sales.quotations (sales_rep_id);

CREATE TRIGGER trg_quotations_updated_at
    BEFORE UPDATE ON sales.quotations
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.quotations                IS 'Cotizaciones / proformas enviadas al cliente. Se convierten en órdenes de venta al ser aprobadas.';
COMMENT ON COLUMN sales.quotations.sales_channel  IS 'Canal de origen: direct, ecommerce, whatsapp, marketplace. Para análisis de conversión.';
COMMENT ON COLUMN sales.quotations.exchange_rate  IS 'Tipo de cambio al momento de la cotización. Fija el valor aunque la moneda fluctúe.';

-- ============================================================
-- Líneas de cotización
-- ============================================================
CREATE TABLE sales.quotation_lines (
    id                  BIGSERIAL   PRIMARY KEY,
    quotation_id        BIGINT      NOT NULL REFERENCES sales.quotations(id) ON DELETE RESTRICT,
    product_id          BIGINT      NOT NULL REFERENCES logistics.products(id),
    variant_id          BIGINT      REFERENCES logistics.product_variants(id),
    unit_id             INTEGER     NOT NULL REFERENCES logistics.measurement_units(id),

    line_number         INTEGER     NOT NULL,
    description         VARCHAR(500),
    -- descripción personalizada (puede diferir del nombre del producto)

    quantity            NUMERIC(18,4) NOT NULL,
    unit_price          NUMERIC(18,6) NOT NULL,
    -- precio lista sin descuento

    discount_pct        NUMERIC(5,2) NOT NULL DEFAULT 0,
    discount_amount     NUMERIC(18,4) NOT NULL DEFAULT 0,
    tax_rate_id         INTEGER     REFERENCES sales.tax_rates(id),
    tax_pct             NUMERIC(5,2) NOT NULL DEFAULT 18,
    -- IGV por defecto 18% en Perú

    net_price           NUMERIC(18,6) NOT NULL DEFAULT 0,
    -- precio después de descuento, sin IGV
    line_total          NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- net_price × quantity (sin IGV)
    line_tax            NUMERIC(18,4) NOT NULL DEFAULT 0,
    line_total_with_tax NUMERIC(18,4) NOT NULL DEFAULT 0,

    requested_date      DATE,
    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (quotation_id, line_number)
);

CREATE INDEX idx_quotation_lines_quotation ON sales.quotation_lines (quotation_id);
CREATE INDEX idx_quotation_lines_product   ON sales.quotation_lines (product_id);

CREATE TRIGGER trg_quotation_lines_updated_at
    BEFORE UPDATE ON sales.quotation_lines
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE sales.quotation_lines IS 'Líneas de cotización con precio, descuento e impuesto por ítem.';

-- ============================================================
-- Historial de versiones de cotización
-- (cuando se modifica una cotización ya enviada)
-- ============================================================
CREATE TABLE sales.quotation_versions (
    id              BIGSERIAL   PRIMARY KEY,
    quotation_id    BIGINT      NOT NULL REFERENCES sales.quotations(id),
    version_number  INTEGER     NOT NULL,
    -- 1, 2, 3... cada vez que se re-envía con cambios

    changed_by      BIGINT,
    -- employee_id
    change_reason   TEXT,
    snapshot        JSONB,
    -- snapshot del estado de la cotización en esa versión

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (quotation_id, version_number)
);

COMMENT ON TABLE sales.quotation_versions IS 'Versiones de la cotización cuando se modifica después de enviada. Auditoría de negociación.';
