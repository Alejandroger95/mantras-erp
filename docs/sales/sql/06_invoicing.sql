-- ============================================================
-- mantrasdb | Módulo Sales
-- Archivo: 06_invoicing.sql
-- Descripción: Facturación electrónica (Factura / Boleta /
--              Nota de Crédito / Nota de Débito) con integración
--              SUNAT para el mercado peruano.
--
-- Flujo:
--   sales_order → invoice (factura/boleta)
--   invoice → credit_note (devolución/descuento)
--   invoice → debit_note  (cargo adicional)
--
-- SUNAT:
--   Toda factura/boleta electrónica en Perú debe ser enviada
--   a SUNAT antes de ser entregada al cliente.
-- ============================================================

-- ============================================================
-- Comprobantes de venta (facturas y boletas)
-- ============================================================
CREATE TABLE sales.invoices (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    invoice_status_id   INTEGER     NOT NULL REFERENCES sales.invoice_statuses(id),
    document_type_id    INTEGER     NOT NULL REFERENCES sales.document_types(id),
    -- FAC=factura, BOL=boleta
    customer_id         BIGINT      NOT NULL REFERENCES sales.customers(id),
    sales_order_id      BIGINT      REFERENCES sales.sales_orders(id),
    payment_terms_id    INTEGER     REFERENCES sales.payment_terms_catalog(id),

    -- Numeración SUNAT: serie + correlativo
    serie               VARCHAR(10) NOT NULL,
    -- F001 (factura) | B001 (boleta)
    correlativo         VARCHAR(10) NOT NULL,
    full_number         VARCHAR(30) NOT NULL,
    -- F001-000001

    -- Fechas
    issue_date          DATE        NOT NULL DEFAULT CURRENT_DATE,
    due_date            DATE,
    -- fecha de vencimiento del pago

    -- Cliente (capturado al momento de emitir, no cambia)
    customer_name       VARCHAR(300) NOT NULL,
    customer_tax_id     VARCHAR(20),
    customer_tax_id_type VARCHAR(10),
    customer_address    TEXT,

    -- Moneda y totales
    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',
    exchange_rate       NUMERIC(12,6) NOT NULL DEFAULT 1,
    subtotal            NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- base imponible (sin IGV)
    discount_amount     NUMERIC(18,4) NOT NULL DEFAULT 0,
    tax_amount          NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- IGV
    other_charges       NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- percepciones, detracciones, otros
    total_amount        NUMERIC(18,4) NOT NULL DEFAULT 0,

    -- Detracción SUNAT (para servicios y algunos bienes)
    has_detraction      BOOLEAN     NOT NULL DEFAULT FALSE,
    detraction_pct      NUMERIC(5,2),
    detraction_amount   NUMERIC(18,4),
    detraction_code     VARCHAR(10),
    -- código de bien/servicio sujeto a detracción

    -- Estado de pago
    payment_status_id   INTEGER     REFERENCES sales.payment_statuses(id),
    amount_paid         NUMERIC(18,4) NOT NULL DEFAULT 0,

    -- SUNAT electrónica
    sunat_status        VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending | sent | accepted | rejected | cancelled
    sunat_ticket        VARCHAR(100),
    sunat_response_code VARCHAR(10),
    sunat_response_desc TEXT,
    sunat_hash          VARCHAR(200),
    -- hash del comprobante firmado digitalmente
    sunat_cdr_url       VARCHAR(500),
    xml_content         TEXT,
    -- XML firmado (obligatorio por ley, conservar 5 años)
    qr_code             TEXT,
    -- contenido del código QR para impresión

    -- Envío al cliente
    sent_to_customer_at TIMESTAMPTZ,
    sent_via            VARCHAR(20),
    -- email | whatsapp | portal | print

    notes               TEXT,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, full_number)
);

CREATE INDEX idx_invoices_company   ON sales.invoices (company_id);
CREATE INDEX idx_invoices_customer  ON sales.invoices (customer_id);
CREATE INDEX idx_invoices_status    ON sales.invoices (invoice_status_id);
CREATE INDEX idx_invoices_date      ON sales.invoices (issue_date);
CREATE INDEX idx_invoices_order     ON sales.invoices (sales_order_id);
CREATE INDEX idx_invoices_sunat     ON sales.invoices (sunat_status) WHERE sunat_status IN ('pending','sent');
CREATE INDEX idx_invoices_due       ON sales.invoices (due_date) WHERE due_date IS NOT NULL;

CREATE TRIGGER trg_invoices_updated_at
    BEFORE UPDATE ON sales.invoices
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.invoices                 IS 'Facturas y boletas electrónicas con integración SUNAT. Cumple con la Resolución de Superintendencia N° 097-2012.';
COMMENT ON COLUMN sales.invoices.xml_content     IS 'XML firmado digitalmente enviado a SUNAT. Obligación legal: conservar 5 años.';
COMMENT ON COLUMN sales.invoices.has_detraction  IS 'TRUE si el comprobante está sujeto al Sistema de Detracciones SUNAT (SPOT).';
COMMENT ON COLUMN sales.invoices.sunat_hash      IS 'Hash SHA-256 del comprobante. Permite verificar integridad del documento.';

-- ============================================================
-- Líneas de factura / boleta
-- ============================================================
CREATE TABLE sales.invoice_lines (
    id                      BIGSERIAL   PRIMARY KEY,
    invoice_id              BIGINT      NOT NULL REFERENCES sales.invoices(id) ON DELETE RESTRICT,
    product_id              BIGINT      NOT NULL REFERENCES logistics.products(id),
    unit_id                 INTEGER     NOT NULL REFERENCES logistics.measurement_units(id),
    tax_rate_id             INTEGER     REFERENCES sales.tax_rates(id),

    line_number             INTEGER     NOT NULL,
    description             VARCHAR(500) NOT NULL,
    -- descripción que aparece en el comprobante

    -- Código SUNAT del producto (si aplica)
    sunat_product_code      VARCHAR(30),
    -- código de la ONU / catálogo SUNAT

    quantity                NUMERIC(18,4) NOT NULL,
    unit_price              NUMERIC(18,6) NOT NULL,
    -- precio unitario neto (sin IGV)

    discount_pct            NUMERIC(5,2) NOT NULL DEFAULT 0,
    discount_amount         NUMERIC(18,4) NOT NULL DEFAULT 0,
    tax_pct                 NUMERIC(5,2) NOT NULL DEFAULT 18,
    tax_amount              NUMERIC(18,4) NOT NULL DEFAULT 0,

    line_total_net          NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- subtotal sin IGV
    line_total              NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- subtotal con IGV

    -- Referencia a la línea de orden
    sales_order_line_id     BIGINT      REFERENCES sales.sales_order_lines(id),

    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (invoice_id, line_number)
);

CREATE INDEX idx_invoice_lines_invoice ON sales.invoice_lines (invoice_id);
CREATE INDEX idx_invoice_lines_product ON sales.invoice_lines (product_id);

COMMENT ON TABLE sales.invoice_lines IS 'Líneas del comprobante. Cada línea tiene código SUNAT, cantidad, precio y IGV.';

-- ============================================================
-- Notas de crédito
-- ============================================================
CREATE TABLE sales.credit_notes (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    invoice_status_id   INTEGER     NOT NULL REFERENCES sales.invoice_statuses(id),
    original_invoice_id BIGINT      NOT NULL REFERENCES sales.invoices(id),
    customer_id         BIGINT      NOT NULL REFERENCES sales.customers(id),

    -- Numeración SUNAT
    serie               VARCHAR(10) NOT NULL,
    -- FC01 (NC de factura) | BC01 (NC de boleta)
    correlativo         VARCHAR(10) NOT NULL,
    full_number         VARCHAR(30) NOT NULL,

    issue_date          DATE        NOT NULL DEFAULT CURRENT_DATE,

    -- Motivo de la NC (código SUNAT)
    reason_code         VARCHAR(10) NOT NULL,
    -- 01=anulación, 02=anulación por error, 03=corrección por error,
    -- 04=descuento global, 05=descuento por ítem, 06=devolución total,
    -- 07=devolución por ítem, 08=bonificación, 13=ajuste afecto
    reason_description  TEXT,

    -- Moneda y totales
    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',
    subtotal            NUMERIC(18,4) NOT NULL DEFAULT 0,
    tax_amount          NUMERIC(18,4) NOT NULL DEFAULT 0,
    total_amount        NUMERIC(18,4) NOT NULL DEFAULT 0,

    -- SUNAT
    sunat_status        VARCHAR(20) NOT NULL DEFAULT 'pending',
    sunat_response_code VARCHAR(10),
    xml_content         TEXT,

    -- Referencia a devolución en Logistics
    customer_return_id  BIGINT      REFERENCES logistics.customer_returns(id),

    notes               TEXT,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, full_number)
);

CREATE INDEX idx_credit_notes_company  ON sales.credit_notes (company_id);
CREATE INDEX idx_credit_notes_invoice  ON sales.credit_notes (original_invoice_id);
CREATE INDEX idx_credit_notes_customer ON sales.credit_notes (customer_id);

CREATE TRIGGER trg_credit_notes_updated_at
    BEFORE UPDATE ON sales.credit_notes
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.credit_notes             IS 'Notas de crédito electrónicas SUNAT. Anulan o reducen el valor de una factura/boleta emitida.';
COMMENT ON COLUMN sales.credit_notes.reason_code IS 'Código de motivo según catálogo SUNAT: 01=anulación, 06=devolución total, 07=devolución ítem, etc.';

-- ============================================================
-- Líneas de nota de crédito
-- ============================================================
CREATE TABLE sales.credit_note_lines (
    id                  BIGSERIAL   PRIMARY KEY,
    credit_note_id      BIGINT      NOT NULL REFERENCES sales.credit_notes(id),
    product_id          BIGINT      NOT NULL REFERENCES logistics.products(id),
    unit_id             INTEGER     NOT NULL REFERENCES logistics.measurement_units(id),

    line_number         INTEGER     NOT NULL,
    description         VARCHAR(500) NOT NULL,
    quantity            NUMERIC(18,4) NOT NULL,
    unit_price          NUMERIC(18,6) NOT NULL,
    tax_pct             NUMERIC(5,2) NOT NULL DEFAULT 18,
    tax_amount          NUMERIC(18,4) NOT NULL DEFAULT 0,
    line_total_net      NUMERIC(18,4) NOT NULL DEFAULT 0,
    line_total          NUMERIC(18,4) NOT NULL DEFAULT 0,

    original_invoice_line_id BIGINT REFERENCES sales.invoice_lines(id),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (credit_note_id, line_number)
);

-- ============================================================
-- Notas de débito
-- ============================================================
CREATE TABLE sales.debit_notes (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    invoice_status_id   INTEGER     NOT NULL REFERENCES sales.invoice_statuses(id),
    original_invoice_id BIGINT      NOT NULL REFERENCES sales.invoices(id),
    customer_id         BIGINT      NOT NULL REFERENCES sales.customers(id),

    serie               VARCHAR(10) NOT NULL,
    correlativo         VARCHAR(10) NOT NULL,
    full_number         VARCHAR(30) NOT NULL,

    issue_date          DATE        NOT NULL DEFAULT CURRENT_DATE,

    reason_code         VARCHAR(10) NOT NULL,
    -- 01=intereses mora, 02=aumento valor, 03=penalidades
    reason_description  TEXT,

    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',
    subtotal            NUMERIC(18,4) NOT NULL DEFAULT 0,
    tax_amount          NUMERIC(18,4) NOT NULL DEFAULT 0,
    total_amount        NUMERIC(18,4) NOT NULL DEFAULT 0,

    sunat_status        VARCHAR(20) NOT NULL DEFAULT 'pending',
    xml_content         TEXT,

    notes               TEXT,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, full_number)
);

CREATE INDEX idx_debit_notes_company  ON sales.debit_notes (company_id);
CREATE INDEX idx_debit_notes_invoice  ON sales.debit_notes (original_invoice_id);

CREATE TRIGGER trg_debit_notes_updated_at
    BEFORE UPDATE ON sales.debit_notes
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.debit_notes             IS 'Notas de débito electrónicas SUNAT. Aumentan el valor de una factura (penalidades, intereses, ajustes).';
COMMENT ON COLUMN sales.debit_notes.reason_code IS 'Código SUNAT: 01=intereses por mora, 02=aumento de valor, 03=penalidades.';
