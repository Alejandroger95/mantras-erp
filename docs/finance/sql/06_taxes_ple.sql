-- ============================================================
-- mantrasdb | Módulo Finance
-- Archivo: 06_taxes_ple.sql
-- Descripción: Impuestos, Obligaciones Tributarias y Libros
--              Electrónicos SUNAT (PLE) para Perú.
--              También cubre IVA/Impuesto Sociedades para España.
--
-- Módulos:
--   1. tax_types              — catálogo de impuestos (IGV, IR, IVA)
--   2. tax_periods            — períodos de declaración
--   3. tax_declarations       — declaraciones (PDT/formularios)
--   4. ple_records            — registros para PLE SUNAT
--   5. withholding_records    — retenciones y percepciones
--   6. detraction_records     — detracciones SPOT (Perú)
--   7. tax_installments       — fraccionamiento de deudas tributarias
--
-- PLE SUNAT (Programa de Libros Electrónicos):
--   Registro de Ventas e Ingresos     (RS: formato 14.1)
--   Registro de Compras               (RC: formato 8.1)
--   Libro Diario (simplificado)       (LD: formato 5.1)
--   Libro Diario de Formato Simplificado (5.3)
--   Libro Mayor                       (LM: formato 6.1)
--   Libro de Inventarios y Balances   (LIB: formato 3.1)
-- ============================================================

-- ============================================================
-- 1. TIPOS DE IMPUESTO
-- ============================================================
CREATE TABLE finance.tax_types (
    id              SERIAL      PRIMARY KEY,
    code            VARCHAR(20) NOT NULL UNIQUE,
    name            VARCHAR(100) NOT NULL,
    country_code    VARCHAR(5)  NOT NULL DEFAULT 'PE',

    tax_class       VARCHAR(20) NOT NULL,
    -- vat             : IGV / IVA (sobre ventas y compras)
    -- income          : Impuesto a la Renta / Impuesto Sociedades
    -- withholding     : retención en la fuente
    -- payroll_tax     : contribuciones laborales (EsSalud, ONP)
    -- municipal       : impuestos municipales (predial, alcabala)
    -- excise          : selectivo al consumo (ISC)
    -- export          : no aplica impuesto

    rate            NUMERIC(7,4),
    -- tasa estándar (puede variar por empresa/operación)

    -- Cuenta contable de crédito (para ventas)
    output_account_id INTEGER,
    -- Cuenta contable de débito (para compras)
    input_account_id  INTEGER,

    is_active       BOOLEAN     NOT NULL DEFAULT TRUE
);

INSERT INTO finance.tax_types (code, name, country_code, tax_class, rate) VALUES
-- Perú
('IGV_18',      'IGV 18% (estándar)',                     'PE', 'vat',       18.00),
('IGV_0',       'IGV Exonerado',                          'PE', 'vat',        0.00),
('IGV_EXPORT',  'IGV Exportación (0% con crédito)',       'PE', 'export',     0.00),
('ISC',         'Impuesto Selectivo al Consumo',          'PE', 'excise',     NULL),
('IR_3PCT',     'IR Retención 3a Categoría (8%→29.5%)',   'PE', 'income',     NULL),
('IR_2DA_5',    'IR 2da Categoría (dividendos 5%)',       'PE', 'withholding', 5.00),
('IR_4TA_8',    'Retención 4a Categoría (8%)',            'PE', 'withholding', 8.00),
('IR_NO_DOM_30','IR No Domiciliados 30%',                 'PE', 'withholding',30.00),
('ESSALUD_9',   'EsSalud Empleador 9%',                   'PE', 'payroll_tax', 9.00),
('ONP_13',      'ONP Trabajador 13%',                     'PE', 'payroll_tax',13.00),
('PREDIAL',     'Impuesto Predial',                       'PE', 'municipal',   NULL),
('ALCABALA',    'Alcabala (transferencia inmueble)',       'PE', 'municipal',   3.00),
-- España
('IVA_21',      'IVA General 21%',                       'ES', 'vat',        21.00),
('IVA_10',      'IVA Reducido 10%',                      'ES', 'vat',        10.00),
('IVA_4',       'IVA Superreducido 4%',                  'ES', 'vat',         4.00),
('IVA_0_ES',    'IVA Exento (España)',                   'ES', 'vat',         0.00),
('IS_25',       'Impuesto Sociedades 25%',               'ES', 'income',     25.00),
('IRPF_RET_15', 'Retención IRPF Profesionales 15%',     'ES', 'withholding',15.00),
('SS_EMP_ES',   'Seguridad Social Empresa (España)',     'ES', 'payroll_tax', NULL);

COMMENT ON TABLE finance.tax_types IS 'Catálogo de tipos de impuesto para Perú y España. Incluye IGV, IR, retenciones, IVA, IS.';

-- ============================================================
-- 2. PERÍODOS TRIBUTARIOS
--    Período mensual o anual según el impuesto.
-- ============================================================
CREATE TABLE finance.tax_periods (
    id              BIGSERIAL   PRIMARY KEY,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    tax_type_id     INTEGER     NOT NULL REFERENCES finance.tax_types(id),

    period_type     VARCHAR(10) NOT NULL DEFAULT 'monthly',
    -- monthly | quarterly | annual

    period_year     SMALLINT    NOT NULL,
    period_month    SMALLINT,
    -- NULL para declaraciones anuales

    start_date      DATE        NOT NULL,
    due_date        DATE        NOT NULL,
    -- fecha límite de presentación (según cronograma SUNAT/AEAT)

    status          VARCHAR(20) NOT NULL DEFAULT 'open',
    -- open       : período abierto, se pueden registrar operaciones
    -- declared   : declaración presentada
    -- paid       : impuesto pagado
    -- overdue    : vencido sin presentar
    -- rectified  : declaración rectificatoria presentada

    sunat_form_code VARCHAR(10),
    -- PDT: 621 (IGV+IR), 617 (IGV Otras), 693 (Renta Anual), etc.

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, tax_type_id, period_year, COALESCE(period_month, 0))
);

CREATE TRIGGER trg_taxperiod_updated_at
    BEFORE UPDATE ON finance.tax_periods
    FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at();

COMMENT ON TABLE finance.tax_periods IS 'Períodos de declaración tributaria. Controla las fechas de vencimiento y el estado de cada obligación.';

-- ============================================================
-- 3. DECLARACIONES TRIBUTARIAS
-- ============================================================
CREATE TABLE finance.tax_declarations (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),
    tax_period_id       BIGINT      NOT NULL REFERENCES finance.tax_periods(id),

    declaration_type    VARCHAR(20) NOT NULL DEFAULT 'original',
    -- original       : primera presentación
    -- rectificatory  : declaración rectificatoria
    -- substituting   : declaración sustitutoria

    presentation_date   DATE,
    -- fecha de presentación al SUNAT/AEAT

    -- Montos declarados
    taxable_base        NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- base imponible (ventas gravadas, renta, etc.)

    tax_calculated      NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- impuesto calculado

    tax_credits         NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- crédito fiscal (IGV de compras, retenciones, percepciones, etc.)

    tax_due             NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- impuesto por pagar: tax_calculated - tax_credits

    -- 🇵🇪 Específico IGV
    sales_taxable       NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- ventas gravadas
    sales_exempt        NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- ventas exoneradas
    sales_exported      NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- exportaciones
    igv_output          NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- IGV débito fiscal
    purchases_taxable   NUMERIC(18,2) NOT NULL DEFAULT 0,
    igv_input           NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- IGV crédito fiscal
    igv_balance         NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- saldo a favor (carry forward)

    -- Número de orden / número de declaración
    declaration_number  VARCHAR(30),
    sunat_operation_number VARCHAR(30),
    -- número de operación asignado por SUNAT/clave SOL

    -- Pago
    payment_amount      NUMERIC(18,2) NOT NULL DEFAULT 0,
    payment_date        DATE,
    payment_reference   VARCHAR(50),

    -- ¿Fraccionamiento solicitado?
    has_installment_plan BOOLEAN     NOT NULL DEFAULT FALSE,
    installment_plan_id BIGINT,
    -- REFERENCES finance.tax_installments(id) — FK diferida

    status              VARCHAR(20) NOT NULL DEFAULT 'draft',
    -- draft      : en preparación
    -- submitted  : presentada
    -- paid       : pagada
    -- overdue    : vencida con deuda
    -- in_dispute : en apelación o reclamación

    notes               TEXT,
    prepared_by         BIGINT,
    submitted_by        BIGINT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_taxdecl_company ON finance.tax_declarations (company_id);
CREATE INDEX idx_taxdecl_period  ON finance.tax_declarations (tax_period_id);

CREATE TRIGGER trg_taxdecl_updated_at
    BEFORE UPDATE ON finance.tax_declarations
    FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at();

COMMENT ON TABLE finance.tax_declarations IS 'Declaraciones tributarias (PDT SUNAT / modelos AEAT). Registra los importes declarados y el estado de pago.';

-- ============================================================
-- 4. REGISTROS PLE (PROGRAMA DE LIBROS ELECTRÓNICOS SUNAT)
--    Cada registro corresponde a una línea en los archivos
--    de texto que se envían al SUNAT.
-- ============================================================

-- 4a. Registro de Ventas (Formato 14.1 — SUNAT)
CREATE TABLE finance.ple_sales_records (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),
    tax_period_id       BIGINT      NOT NULL REFERENCES finance.tax_periods(id),

    -- Datos del comprobante
    issue_date          DATE        NOT NULL,
    due_date            DATE,
    doc_type_code       VARCHAR(5)  NOT NULL,
    -- 01=Factura, 03=Boleta, 07=NC, 08=ND, 12=Ticket, etc.
    doc_series          VARCHAR(10),
    doc_number          VARCHAR(20) NOT NULL,

    -- Comprobante relacionado (para NC/ND)
    related_doc_type    VARCHAR(5),
    related_doc_series  VARCHAR(10),
    related_doc_number  VARCHAR(20),
    related_issue_date  DATE,

    -- Cliente
    customer_doc_type   VARCHAR(5),
    -- 1=DNI, 4=Carné Extranjería, 6=RUC, 7=Pasaporte
    customer_doc_number VARCHAR(20),
    customer_name       VARCHAR(300),

    -- Importes
    export_amount       NUMERIC(18,2) NOT NULL DEFAULT 0,
    taxable_amount      NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- base imponible
    igv_amount          NUMERIC(18,2) NOT NULL DEFAULT 0,
    exempt_amount       NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- exonerado
    non_taxable_amount  NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- inafecto
    isc_amount          NUMERIC(18,2) NOT NULL DEFAULT 0,
    icbper_amount       NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- Impuesto al Consumo de Bolsas de Plástico
    other_charges       NUMERIC(18,2) NOT NULL DEFAULT 0,
    total_amount        NUMERIC(18,2) NOT NULL DEFAULT 0,

    currency            VARCHAR(3)  NOT NULL DEFAULT 'PEN',
    exchange_rate       NUMERIC(10,3),

    -- Estado del comprobante para PLE
    operation_status    VARCHAR(5)  NOT NULL DEFAULT '1',
    -- 1 = comprobante válido
    -- 6 = anulado (baja)
    -- 7 = excluido del registro

    -- Documento origen
    sales_invoice_id    BIGINT,
    -- REFERENCES sales.invoices(id) — FK diferida
    pos_transaction_id  BIGINT,
    -- REFERENCES sales.pos_transactions(id) — FK diferida

    -- Estado de envío al SUNAT
    ple_status          VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending   : pendiente de generar archivo
    -- generated : archivo generado
    -- sent      : enviado al SUNAT
    -- accepted  : aceptado por SUNAT
    -- rejected  : rechazado por SUNAT

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ple_sales_company ON finance.ple_sales_records (company_id);
CREATE INDEX idx_ple_sales_period  ON finance.ple_sales_records (tax_period_id);
CREATE INDEX idx_ple_sales_invoice ON finance.ple_sales_records (sales_invoice_id);

COMMENT ON TABLE finance.ple_sales_records IS '🇵🇪 Registro de Ventas e Ingresos (Formato 14.1 PLE SUNAT). Una línea por comprobante de venta emitido en el período.';

-- 4b. Registro de Compras (Formato 8.1 — SUNAT)
CREATE TABLE finance.ple_purchase_records (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),
    tax_period_id       BIGINT      NOT NULL REFERENCES finance.tax_periods(id),

    -- Datos del comprobante del proveedor
    issue_date          DATE        NOT NULL,
    due_date            DATE,
    doc_type_code       VARCHAR(5)  NOT NULL,
    doc_series          VARCHAR(10),
    doc_number          VARCHAR(20) NOT NULL,

    -- Proveedor
    supplier_doc_type   VARCHAR(5)  NOT NULL DEFAULT '6',
    -- 6=RUC (empresas) | 1=DNI (personas)
    supplier_doc_number VARCHAR(20) NOT NULL,
    supplier_name       VARCHAR(300) NOT NULL,

    -- Importes
    net_taxable_amount  NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- base imponible para crédito fiscal
    igv_amount          NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- IGV que da crédito fiscal
    non_creditable_igv  NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- IGV no utilizable como crédito
    isc_amount          NUMERIC(18,2) NOT NULL DEFAULT 0,
    icbper_amount       NUMERIC(18,2) NOT NULL DEFAULT 0,
    exempt_amount       NUMERIC(18,2) NOT NULL DEFAULT 0,
    non_taxable_amount  NUMERIC(18,2) NOT NULL DEFAULT 0,
    total_amount        NUMERIC(18,2) NOT NULL DEFAULT 0,

    currency            VARCHAR(3)  NOT NULL DEFAULT 'PEN',
    exchange_rate       NUMERIC(10,3),

    -- Detracción
    has_detraction      BOOLEAN     NOT NULL DEFAULT FALSE,
    detraction_constancy VARCHAR(50),

    operation_status    VARCHAR(5)  NOT NULL DEFAULT '1',

    supplier_invoice_id BIGINT      REFERENCES finance.supplier_invoices(id),

    ple_status          VARCHAR(20) NOT NULL DEFAULT 'pending',

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ple_purch_company  ON finance.ple_purchase_records (company_id);
CREATE INDEX idx_ple_purch_period   ON finance.ple_purchase_records (tax_period_id);
CREATE INDEX idx_ple_purch_invoice  ON finance.ple_purchase_records (supplier_invoice_id);

COMMENT ON TABLE finance.ple_purchase_records IS '🇵🇪 Registro de Compras (Formato 8.1 PLE SUNAT). Una línea por comprobante de compra recibido en el período.';

-- 4c. Libro Diario (Formato 5.1 — SUNAT)
CREATE TABLE finance.ple_journal_records (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),
    tax_period_id       BIGINT      NOT NULL REFERENCES finance.tax_periods(id),

    journal_entry_id    BIGINT      NOT NULL REFERENCES finance.journal_entries(id),
    journal_entry_line_id BIGINT    NOT NULL REFERENCES finance.journal_entry_lines(id),

    -- Datos del asiento
    entry_number        VARCHAR(30) NOT NULL,
    entry_date          DATE        NOT NULL,
    gloss               VARCHAR(100),
    -- glosa del asiento (primeros 100 chars)

    account_code        VARCHAR(20) NOT NULL,
    account_name        VARCHAR(300) NOT NULL,

    debit_amount        NUMERIC(18,2) NOT NULL DEFAULT 0,
    credit_amount       NUMERIC(18,2) NOT NULL DEFAULT 0,

    currency            VARCHAR(3)  NOT NULL DEFAULT 'PEN',
    exchange_rate       NUMERIC(10,3),

    ple_status          VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ple_journal_company ON finance.ple_journal_records (company_id);
CREATE INDEX idx_ple_journal_period  ON finance.ple_journal_records (tax_period_id);
CREATE INDEX idx_ple_journal_entry   ON finance.ple_journal_records (journal_entry_id);

COMMENT ON TABLE finance.ple_journal_records IS '🇵🇪 Libro Diario (Formato 5.1 PLE SUNAT). Una línea por cada línea de asiento del período.';

-- ============================================================
-- 5. RETENCIONES Y PERCEPCIONES
-- ============================================================
CREATE TABLE finance.withholding_records (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    withholding_type    VARCHAR(20) NOT NULL,
    -- retention_3pct   : retención 3% (proveedor agente de retención)
    -- perception       : percepción IGV (compras de combustible, etc.)
    -- 4th_category     : retención 4ta categoría (honorarios)
    -- 2nd_category     : retención 2da categoría (dividendos, regalías)
    -- non_resident     : retención no domiciliados

    withholding_date    DATE        NOT NULL,
    tax_type_id         INTEGER     NOT NULL REFERENCES finance.tax_types(id),

    -- Tercero
    counterpart_doc_type VARCHAR(5),
    counterpart_doc_number VARCHAR(20),
    counterpart_name    VARCHAR(300),

    -- Para retenciones sobre compras: la factura del proveedor
    supplier_invoice_id BIGINT      REFERENCES finance.supplier_invoices(id),
    -- Para retenciones de 4ta: la RHE del prestador
    service_invoice_id  BIGINT      REFERENCES finance.supplier_invoices(id),

    base_amount         NUMERIC(18,2) NOT NULL,
    withholding_rate    NUMERIC(5,2) NOT NULL,
    withholding_amount  NUMERIC(18,2) NOT NULL,

    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',

    -- Constancia emitida al proveedor
    certificate_number  VARCHAR(30),

    -- Asiento contable
    journal_entry_id    BIGINT      REFERENCES finance.journal_entries(id),

    -- Pago al SUNAT (se declara en PDT 621/617)
    tax_period_id       BIGINT      REFERENCES finance.tax_periods(id),
    paid_to_sunat       BOOLEAN     NOT NULL DEFAULT FALSE,
    payment_date        DATE,

    created_by          BIGINT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- Inmutable
);

CREATE INDEX idx_wth_company  ON finance.withholding_records (company_id);
CREATE INDEX idx_wth_type     ON finance.withholding_records (withholding_type);
CREATE INDEX idx_wth_date     ON finance.withholding_records (withholding_date);

COMMENT ON TABLE  finance.withholding_records IS '🇵🇪 Retenciones y percepciones de IGV / IR. Incluye retenciones 4ta categoría (RHE), 2da categoría (dividendos), retención a no domiciliados.';

-- ============================================================
-- 6. DETRACCIONES (SPOT — Perú)
--    Sistema de Pago de Obligaciones Tributarias.
--    El comprador retiene un % y lo deposita al BN.
-- ============================================================
CREATE TABLE finance.detraction_records (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Tipo de operación sujeta
    detraction_code     VARCHAR(10) NOT NULL,
    -- catálogo SUNAT: 001=azúcar, 009=arena/piedra, 012=intermediación laboral,
    --                 021=transporte de bienes, 022=transporte público, etc.
    detraction_description VARCHAR(200),
    detraction_rate     NUMERIC(5,2) NOT NULL,
    -- 4% | 9% | 10% | 12% | 14% | 15% | etc. según el bien/servicio

    -- Factura del proveedor
    supplier_invoice_id BIGINT      REFERENCES finance.supplier_invoices(id),

    -- Importes
    invoice_amount      NUMERIC(18,2) NOT NULL,
    detraction_amount   NUMERIC(18,2) NOT NULL,
    net_payment_to_supplier NUMERIC(18,2) NOT NULL,
    -- invoice_amount - detraction_amount

    -- Datos del depósito al BN
    supplier_bn_account VARCHAR(20) NOT NULL,
    -- número de cuenta del proveedor en el Banco de la Nación
    deposit_date        DATE,
    deposit_constancy   VARCHAR(50),
    -- número de constancia de depósito

    -- Estado
    status              VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending    : pendiente de depositar
    -- deposited  : depositado al BN
    -- late       : fuera de plazo (multa aplicable)

    -- Asiento contable (débito 4018 Detracciones, crédito cuenta bancaria)
    journal_entry_id    BIGINT      REFERENCES finance.journal_entries(id),

    notes               TEXT,
    created_by          BIGINT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- Inmutable
);

CREATE INDEX idx_det_company  ON finance.detraction_records (company_id);
CREATE INDEX idx_det_invoice  ON finance.detraction_records (supplier_invoice_id);
CREATE INDEX idx_det_status   ON finance.detraction_records (status);

COMMENT ON TABLE  finance.detraction_records IS '🇵🇪 Detracciones SPOT. Registro de los montos retenidos al proveedor y depositados al Banco de la Nación a su cuenta de detracciones.';

-- ============================================================
-- 7. FRACCIONAMIENTO DE DEUDAS TRIBUTARIAS (Perú/España)
-- ============================================================
CREATE TABLE finance.tax_installment_plans (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Deuda original
    tax_declaration_id  BIGINT      REFERENCES finance.tax_declarations(id),
    debt_type           VARCHAR(50),
    -- 'igv' | 'income_tax' | 'customs' | 'penalty'

    total_debt          NUMERIC(18,2) NOT NULL,
    interest_rate       NUMERIC(5,4) NOT NULL,
    -- TIM (Tasa de Interés Moratorio) SUNAT: ~0.04% diario

    number_of_installments SMALLINT NOT NULL,
    approval_date       DATE        NOT NULL,
    approval_resolution VARCHAR(50),
    -- resolución SUNAT que aprueba el fraccionamiento

    status              VARCHAR(20) NOT NULL DEFAULT 'active',
    -- active | completed | defaulted (incumplimiento)

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE finance.tax_installments (
    id                  BIGSERIAL   PRIMARY KEY,
    installment_plan_id BIGINT      NOT NULL REFERENCES finance.tax_installment_plans(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    installment_number  SMALLINT    NOT NULL,
    due_date            DATE        NOT NULL,

    principal_amount    NUMERIC(18,2) NOT NULL,
    interest_amount     NUMERIC(18,2) NOT NULL,
    total_amount        NUMERIC(18,2) NOT NULL,

    status              VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending | paid | overdue

    payment_date        DATE,
    payment_amount      NUMERIC(18,2),
    payment_reference   VARCHAR(50),

    journal_entry_id    BIGINT      REFERENCES finance.journal_entries(id),

    UNIQUE (installment_plan_id, installment_number)
);

-- FK diferida tax_declarations → installment_plan
ALTER TABLE finance.tax_declarations
    ADD CONSTRAINT fk_taxdecl_installment
    FOREIGN KEY (installment_plan_id)
    REFERENCES finance.tax_installment_plans(id);

COMMENT ON TABLE finance.tax_installment_plans IS 'Fraccionamiento de deudas tributarias (Art. 36 Código Tributario Perú / aplazamiento AEAT España). Permite pagar en cuotas con TIM.';
