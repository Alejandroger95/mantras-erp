-- ============================================================
-- mantrasdb | Módulo Finance
-- Archivo: 03_accounts_payable.sql
-- Descripción: Cuentas por Pagar (AP) — ciclo completo de compras.
--
-- Flujo:
--   1. PO (logistics.purchase_orders) → Recepción de mercancía
--   2. supplier_invoices (factura del proveedor)
--   3. supplier_payments (pago al proveedor)
--   4. supplier_payment_allocations (cruce factura vs pago)
--
-- Casos específicos Perú:
--   🇵🇪 Detracciones (SPOT): porcentaje retenido en cuenta BN
--   🇵🇪 Retenciones: 3% cuando proveedor tiene resolución de retención
--   🇵🇪 Percepciones: adiciones al IGV en compras específicas
--   🇪🇸 IVA soportado / IVA deducible
--   📝 Notas de débito y crédito de proveedores
-- ============================================================

-- ============================================================
-- 1. TIPOS DE COMPROBANTE DE PROVEEDOR (catálogo)
-- ============================================================
CREATE TABLE finance.supplier_document_types (
    id              SERIAL      PRIMARY KEY,
    code            VARCHAR(10) NOT NULL UNIQUE,
    name            VARCHAR(100) NOT NULL,
    sunat_code      VARCHAR(10),
    -- código SUNAT para PLE (01=factura, 07=NC, 08=ND, etc.)
    country_code    VARCHAR(5)  NOT NULL DEFAULT 'PE',
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE
);

INSERT INTO finance.supplier_document_types (code, name, sunat_code, country_code) VALUES
-- Perú
('FAC',  'Factura',                              '01', 'PE'),
('BOL',  'Boleta de Venta',                      '03', 'PE'),
('NC',   'Nota de Crédito',                      '07', 'PE'),
('ND',   'Nota de Débito',                       '08', 'PE'),
('LIQ',  'Liquidación de Compra',                '04', 'PE'),
('REC',  'Recibo por Honorarios',                '02', 'PE'),
('TKT',  'Ticket de Máquina Registradora',       '12', 'PE'),
('DOC',  'Documento emitido por Banco',          '16', 'PE'),
-- España
('FAC_ES', 'Factura (España)',                   NULL, 'ES'),
('FC_ES',  'Factura Simplificada (España)',      NULL, 'ES'),
('NC_ES',  'Nota de Crédito (España)',           NULL, 'ES');

COMMENT ON TABLE finance.supplier_document_types IS 'Catálogo de tipos de comprobante de proveedor para registro de facturas (SUNAT Perú y PGC España).';

-- ============================================================
-- 2. FACTURAS DE PROVEEDOR (SUPPLIER INVOICES)
-- ============================================================
CREATE TABLE finance.supplier_invoices (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    supplier_id         BIGINT      NOT NULL,
    -- REFERENCES logistics.suppliers(id) — FK diferida

    -- Tipo de documento
    document_type_id    INTEGER     NOT NULL REFERENCES finance.supplier_document_types(id),

    -- Datos del comprobante emitido por el proveedor
    supplier_doc_number VARCHAR(30) NOT NULL,
    -- "F001-00123456", "RHE-001-000001"

    supplier_serie      VARCHAR(10),
    -- serie del comprobante del proveedor (F001, B001, etc.)

    supplier_number     VARCHAR(20),
    -- número del comprobante del proveedor

    -- Fechas
    issue_date          DATE        NOT NULL,
    -- fecha en que el proveedor emitió el comprobante
    received_date       DATE        NOT NULL DEFAULT CURRENT_DATE,
    -- fecha en que la empresa recibió la factura
    due_date            DATE,
    -- fecha de vencimiento para pago

    -- Estado
    status              VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending    : registrada, pendiente de aprobación
    -- approved   : aprobada para pago
    -- partially_paid : pagada parcialmente
    -- paid        : pagada totalmente
    -- cancelled   : anulada (error de registro)
    -- disputed    : en disputa con el proveedor

    -- Moneda
    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',
    exchange_rate       NUMERIC(18,8) NOT NULL DEFAULT 1.0,

    -- Importes (en moneda del comprobante)
    subtotal            NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- base imponible antes de impuestos

    tax_amount          NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- IGV (18%) o IVA (España)

    other_charges       NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- fletes, seguros, otros cargos

    total_amount        NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- subtotal + tax_amount + other_charges

    -- 🇵🇪 DETRACCIONES (SPOT)
    -- El comprador retiene un % y lo deposita al BN a nombre del proveedor
    has_detraction      BOOLEAN     NOT NULL DEFAULT FALSE,
    detraction_code     VARCHAR(10),
    -- código del bien/servicio SUNAT (001=azúcar, 002=arroz, 021=transporte, etc.)
    detraction_rate     NUMERIC(5,2),
    -- porcentaje de detracción (4%, 9%, 12%, 15%, etc.)
    detraction_amount   NUMERIC(18,2),
    -- monto a depositar al BN
    detraction_payment_date DATE,
    -- fecha en que se realizó el depósito
    detraction_payment_constancy VARCHAR(50),
    -- constancia de depósito BN
    detraction_account  VARCHAR(20),
    -- cuenta BN del proveedor

    -- 🇵🇪 RETENCIONES
    -- 3% cuando proveedor tiene resolución de retención SUNAT
    has_retention       BOOLEAN     NOT NULL DEFAULT FALSE,
    retention_rate      NUMERIC(5,2) NOT NULL DEFAULT 3.0,
    retention_amount    NUMERIC(18,2),
    -- monto retenido (se paga a SUNAT por el comprador)

    -- 🇵🇪 PERCEPCIONES (solo en compras específicas como combustibles)
    has_perception      BOOLEAN     NOT NULL DEFAULT FALSE,
    perception_rate     NUMERIC(5,2),
    perception_amount   NUMERIC(18,2),

    -- Importes efectivos para el proveedor
    amount_payable      NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- total_amount - detraction_amount - retention_amount
    amount_paid         NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- suma de pagos realizados
    amount_outstanding  NUMERIC(18,2) GENERATED ALWAYS AS
        (amount_payable - amount_paid) STORED,
    -- saldo pendiente de pago

    -- Enlace a PO (puede ser múltiple — JSONB de IDs)
    purchase_order_ids  JSONB,
    -- [101, 102] — IDs de logistics.purchase_orders

    -- Asiento contable generado
    journal_entry_id    BIGINT      REFERENCES finance.journal_entries(id),

    -- Archivo (XML SUNAT o PDF)
    document_url        VARCHAR(500),
    xml_content         TEXT,
    -- contenido del XML UBL 2.1 (CDR SUNAT)

    -- Motivo de anulación
    cancellation_reason TEXT,
    cancelled_at        TIMESTAMPTZ,
    cancelled_by        BIGINT,

    created_by          BIGINT,
    approved_by         BIGINT,
    approved_at         TIMESTAMPTZ,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, supplier_id, supplier_doc_number)
);

CREATE INDEX idx_sinv_company      ON finance.supplier_invoices (company_id);
CREATE INDEX idx_sinv_supplier     ON finance.supplier_invoices (supplier_id);
CREATE INDEX idx_sinv_status       ON finance.supplier_invoices (status);
CREATE INDEX idx_sinv_issue_date   ON finance.supplier_invoices (issue_date);
CREATE INDEX idx_sinv_due_date     ON finance.supplier_invoices (due_date) WHERE due_date IS NOT NULL;
CREATE INDEX idx_sinv_outstanding  ON finance.supplier_invoices (amount_outstanding) WHERE amount_outstanding > 0;

CREATE TRIGGER trg_sinv_updated_at
    BEFORE UPDATE ON finance.supplier_invoices
    FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at();

COMMENT ON TABLE  finance.supplier_invoices IS 'Facturas de proveedor. Cubre facturas, boletas, RHE, liquidaciones de compra. Incluye detracciones, retenciones y percepciones para Perú.';
COMMENT ON COLUMN finance.supplier_invoices.has_detraction IS '🇵🇪 TRUE cuando la compra está sujeta al SPOT (Sistema de Pago de Obligaciones Tributarias). El comprador deposita un % al Banco de la Nación.';
COMMENT ON COLUMN finance.supplier_invoices.has_retention  IS '🇵🇪 TRUE cuando el proveedor tiene resolución de agente de retención (3% del importe). El comprador lo paga a SUNAT.';
COMMENT ON COLUMN finance.supplier_invoices.amount_outstanding IS 'Saldo pendiente calculado automáticamente: amount_payable - amount_paid.';

-- ============================================================
-- 3. LÍNEAS DE FACTURA DE PROVEEDOR
-- ============================================================
CREATE TABLE finance.supplier_invoice_lines (
    id                  BIGSERIAL   PRIMARY KEY,
    supplier_invoice_id BIGINT      NOT NULL REFERENCES finance.supplier_invoices(id) ON DELETE RESTRICT,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    line_number         SMALLINT    NOT NULL DEFAULT 1,

    -- Producto o servicio (opcional — puede ser descripción libre)
    product_id          BIGINT,
    -- REFERENCES logistics.products(id) — FK diferida

    description         VARCHAR(500) NOT NULL,

    -- Cantidades y precios
    quantity            NUMERIC(18,4) NOT NULL DEFAULT 1,
    unit_price          NUMERIC(18,6) NOT NULL DEFAULT 0,
    unit_id             INTEGER,
    -- REFERENCES logistics.units_of_measure(id) — FK diferida

    -- Descuentos
    discount_pct        NUMERIC(5,2) NOT NULL DEFAULT 0,
    discount_amount     NUMERIC(18,2) NOT NULL DEFAULT 0,

    -- Subtotal y tax
    line_subtotal       NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- quantity * unit_price - descuentos
    tax_rate            NUMERIC(5,2) NOT NULL DEFAULT 18.0,
    -- 18% IGV Perú / 21% IVA España / 0% exonerado
    tax_amount          NUMERIC(18,2) NOT NULL DEFAULT 0,
    line_total          NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- line_subtotal + tax_amount

    -- Cuenta contable de gasto/costo
    account_id          BIGINT      REFERENCES finance.accounts(id),
    -- ej: 60101 Compras de mercaderías, 63101 Transporte, etc.

    cost_center_id      BIGINT,
    -- REFERENCES finance.cost_centers(id) — FK diferida

    -- ¿Deducible como gasto tributario? (IR Perú)
    is_tax_deductible   BOOLEAN     NOT NULL DEFAULT TRUE,
    -- FALSE = gastos no deducibles (ej: multas, donaciones sin convenio)

    -- Enlace a línea de PO
    purchase_order_line_id BIGINT,

    -- Enlace a línea de recepción (logistics.receipt_lines)
    receipt_line_id     BIGINT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (supplier_invoice_id, line_number)
);

CREATE INDEX idx_sinvl_invoice  ON finance.supplier_invoice_lines (supplier_invoice_id);
CREATE INDEX idx_sinvl_product  ON finance.supplier_invoice_lines (product_id) WHERE product_id IS NOT NULL;
CREATE INDEX idx_sinvl_account  ON finance.supplier_invoice_lines (account_id) WHERE account_id IS NOT NULL;

COMMENT ON TABLE finance.supplier_invoice_lines IS 'Líneas de factura de proveedor. Cada línea tiene su cuenta de gasto y centro de costo para el asiento contable.';

-- ============================================================
-- 4. PAGOS A PROVEEDORES
-- ============================================================
CREATE TABLE finance.supplier_payments (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    supplier_id         BIGINT      NOT NULL,
    -- REFERENCES logistics.suppliers(id) — FK diferida

    -- Numeración interna
    payment_number      VARCHAR(30) NOT NULL,

    payment_date        DATE        NOT NULL,

    -- Método de pago
    payment_method      VARCHAR(30) NOT NULL,
    -- transfer     : transferencia bancaria
    -- check        : cheque
    -- cash         : efectivo
    -- debit_card   : tarjeta de débito
    -- yape         : Yape (Perú)
    -- plin         : Plin (Perú)
    -- bcp_plin     : BCP Plin (Perú)
    -- bizum        : Bizum (España)
    -- compensation : compensación (cruce de deudas)

    -- Moneda y monto
    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',
    exchange_rate       NUMERIC(18,8) NOT NULL DEFAULT 1.0,
    amount              NUMERIC(18,2) NOT NULL,
    amount_functional   NUMERIC(18,2) NOT NULL,
    -- monto en moneda funcional de la empresa

    -- Cuenta bancaria origen (la de la empresa)
    bank_account_id     BIGINT,
    -- REFERENCES finance.bank_accounts(id) — FK diferida

    -- Cuenta bancaria destino (la del proveedor)
    supplier_bank_account_id BIGINT,
    -- REFERENCES logistics.supplier_bank_accounts(id) — FK diferida

    reference_number    VARCHAR(100),
    -- número de transacción bancaria, número de cheque, etc.

    status              VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending    : registrado, pendiente de aplicación
    -- applied    : aplicado contra facturas (total o parcialmente)
    -- cancelled  : anulado

    -- Monto no aplicado aún
    amount_unapplied    NUMERIC(18,2) NOT NULL DEFAULT 0,

    -- Asiento contable
    journal_entry_id    BIGINT      REFERENCES finance.journal_entries(id),

    notes               TEXT,
    created_by          BIGINT,

    -- No tiene updated_at para preservar trazabilidad
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, payment_number)
);

CREATE INDEX idx_spmt_company   ON finance.supplier_payments (company_id);
CREATE INDEX idx_spmt_supplier  ON finance.supplier_payments (supplier_id);
CREATE INDEX idx_spmt_date      ON finance.supplier_payments (payment_date);
CREATE INDEX idx_spmt_status    ON finance.supplier_payments (status);

COMMENT ON TABLE  finance.supplier_payments            IS 'Pagos efectuados a proveedores. Un pago puede aplicarse contra una o varias facturas.';
COMMENT ON COLUMN finance.supplier_payments.amount_unapplied IS 'Saldo del pago no aplicado a ninguna factura. Se reduce con cada allocation.';

-- ============================================================
-- 5. ALLOCATIONS (CRUCE PAGO vs FACTURA)
--    Un pago puede cubrir múltiples facturas y viceversa.
-- ============================================================
CREATE TABLE finance.supplier_payment_allocations (
    id                      BIGSERIAL   PRIMARY KEY,
    company_id              BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    supplier_payment_id     BIGINT      NOT NULL REFERENCES finance.supplier_payments(id) ON DELETE RESTRICT,
    supplier_invoice_id     BIGINT      NOT NULL REFERENCES finance.supplier_invoices(id) ON DELETE RESTRICT,

    allocated_amount        NUMERIC(18,2) NOT NULL,
    -- importe del pago que se aplica a esta factura

    allocation_date         DATE        NOT NULL,
    currency                VARCHAR(10) NOT NULL DEFAULT 'PEN',
    exchange_rate           NUMERIC(18,8) NOT NULL DEFAULT 1.0,

    -- Diferencia de cambio generada por el cruce
    exchange_difference     NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- positivo = ganancia cambiaria / negativo = pérdida

    -- Asiento de diferencia de cambio (si aplica)
    exchange_journal_entry_id BIGINT    REFERENCES finance.journal_entries(id),

    notes                   TEXT,
    created_by              BIGINT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (supplier_payment_id, supplier_invoice_id)
);

CREATE INDEX idx_spalloc_payment ON finance.supplier_payment_allocations (supplier_payment_id);
CREATE INDEX idx_spalloc_invoice ON finance.supplier_payment_allocations (supplier_invoice_id);

COMMENT ON TABLE finance.supplier_payment_allocations IS 'Cruce (matching) entre pagos y facturas de proveedor. Permite pagos parciales y pagos que cubren múltiples facturas.';

-- ============================================================
-- 6. NOTAS DE CRÉDITO Y DÉBITO DE PROVEEDORES
--    Se registran como supplier_invoices con tipo NC/ND.
--    Esta tabla registra el cruce NC → factura original.
-- ============================================================
CREATE TABLE finance.supplier_credit_note_applications (
    id                      BIGSERIAL   PRIMARY KEY,
    company_id              BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- La nota de crédito (tipo NC en supplier_invoices)
    credit_note_id          BIGINT      NOT NULL REFERENCES finance.supplier_invoices(id),
    -- La factura que reduce
    original_invoice_id     BIGINT      NOT NULL REFERENCES finance.supplier_invoices(id),

    applied_amount          NUMERIC(18,2) NOT NULL,
    applied_date            DATE        NOT NULL DEFAULT CURRENT_DATE,

    notes                   TEXT,
    created_by              BIGINT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (credit_note_id, original_invoice_id)
);

COMMENT ON TABLE finance.supplier_credit_note_applications IS 'Cruce entre Notas de Crédito de proveedor y las facturas que reducen (un NC puede reducir varias facturas).';

-- ============================================================
-- 7. GASTOS DE PROVEEDOR SIN FACTURA (DEVENGOS / ACCRUALS)
--    Registro de gastos estimados antes de recibir la factura.
--    Ejemplo: servicio de electricidad de diciembre cobrado en enero.
-- ============================================================
CREATE TABLE finance.expense_accruals (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    supplier_id         BIGINT,
    -- REFERENCES logistics.suppliers(id) — FK diferida

    -- Período al que pertenece el gasto
    accounting_period_id BIGINT     NOT NULL REFERENCES finance.accounting_periods(id),

    description         VARCHAR(300) NOT NULL,
    accrual_date        DATE        NOT NULL,

    amount              NUMERIC(18,2) NOT NULL,
    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',

    -- Cuenta de gasto
    expense_account_id  BIGINT      NOT NULL REFERENCES finance.accounts(id),

    status              VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending   : devengo registrado, factura no recibida
    -- invoiced  : factura recibida y cruzada con este devengo
    -- cancelled : anulado

    -- Cuando llega la factura
    supplier_invoice_id BIGINT      REFERENCES finance.supplier_invoices(id),
    reversal_journal_entry_id BIGINT REFERENCES finance.journal_entries(id),

    journal_entry_id    BIGINT      REFERENCES finance.journal_entries(id),

    notes               TEXT,
    created_by          BIGINT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_accrual_updated_at
    BEFORE UPDATE ON finance.expense_accruals
    FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at();

COMMENT ON TABLE finance.expense_accruals IS 'Devengos de gasto (accruals): gastos del período sin factura todavía. Al recibir la factura se revierte el devengo y se registra la factura real.';

-- ============================================================
-- 8. CUENTA CORRIENTE DE PROVEEDORES (vista resumen)
-- ============================================================
CREATE OR REPLACE VIEW finance.supplier_account_statement AS
SELECT
    si.company_id,
    si.supplier_id,
    si.id                   AS document_id,
    'invoice'               AS document_kind,
    si.document_type_id,
    si.supplier_doc_number  AS reference,
    si.issue_date           AS document_date,
    si.due_date,
    si.currency,
    si.total_amount         AS original_amount,
    si.amount_payable       AS payable_amount,
    si.amount_paid,
    si.amount_outstanding,
    si.status
FROM finance.supplier_invoices si
WHERE si.status NOT IN ('cancelled')
UNION ALL
SELECT
    sp.company_id,
    sp.supplier_id,
    sp.id,
    'payment',
    NULL,
    sp.payment_number,
    sp.payment_date,
    NULL,
    sp.currency,
    -sp.amount,
    -sp.amount,
    -sp.amount,
    0,
    sp.status
FROM finance.supplier_payments sp
WHERE sp.status NOT IN ('cancelled');

COMMENT ON VIEW finance.supplier_account_statement IS 'Extracto de cuenta corriente por proveedor: facturas pendientes y pagos realizados.';
