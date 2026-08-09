-- ============================================================
-- mantrasdb | Módulo Sales
-- Archivo: 07_collections.sql
-- Descripción: Cobranzas — pagos de clientes, asignación a
--              facturas, gestión de mora y cuentas por cobrar.
--
-- Flujo:
--   invoice (issued) → customer_payment → payment_allocation
--                                          (qué facturas cubre)
--   invoice (overdue) → collection_reminder → promise_to_pay
-- ============================================================

-- ============================================================
-- Cuentas bancarias de la empresa (para recibir pagos)
-- ============================================================
CREATE TABLE sales.company_bank_accounts (
    id              BIGSERIAL   PRIMARY KEY,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    bank_name       VARCHAR(100) NOT NULL,
    account_type    VARCHAR(20) NOT NULL DEFAULT 'current',
    -- current=corriente | savings=ahorros
    account_number  VARCHAR(50) NOT NULL,
    cci             VARCHAR(30),
    -- Código de Cuenta Interbancario (Perú)
    currency        VARCHAR(10) NOT NULL DEFAULT 'PEN',
    is_default      BOOLEAN     NOT NULL DEFAULT FALSE,
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_company_bank_accounts_updated_at
    BEFORE UPDATE ON sales.company_bank_accounts
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE sales.company_bank_accounts IS 'Cuentas bancarias de la empresa para recibir pagos de clientes.';

-- ============================================================
-- Pagos recibidos de clientes
-- ============================================================
CREATE TABLE sales.customer_payments (
    id                      BIGSERIAL   PRIMARY KEY,
    company_id              BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    customer_id             BIGINT      NOT NULL REFERENCES sales.customers(id),
    payment_method_id       INTEGER     NOT NULL REFERENCES sales.payment_methods(id),
    bank_account_id         BIGINT      REFERENCES sales.company_bank_accounts(id),

    payment_number          VARCHAR(50) NOT NULL,
    -- número interno de registro de pago

    -- Monto
    currency                VARCHAR(10) NOT NULL DEFAULT 'PEN',
    exchange_rate           NUMERIC(12,6) NOT NULL DEFAULT 1,
    amount                  NUMERIC(18,4) NOT NULL,
    amount_allocated        NUMERIC(18,4) NOT NULL DEFAULT 0,
    amount_unallocated      NUMERIC(18,4)
        GENERATED ALWAYS AS (amount - amount_allocated) STORED,
    -- saldo sin asignar a facturas (crédito a favor del cliente)

    -- Referencias del pago
    reference_number        VARCHAR(100),
    -- número de operación bancaria, número de cheque, etc.
    payment_date            DATE        NOT NULL DEFAULT CURRENT_DATE,

    -- Estado
    status                  VARCHAR(20) NOT NULL DEFAULT 'received',
    -- received | allocated | partial | returned | voided

    received_by             BIGINT,
    -- employee_id de quien registró el pago

    notes                   TEXT,
    is_active               BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, payment_number)
);

CREATE INDEX idx_customer_payments_company  ON sales.customer_payments (company_id);
CREATE INDEX idx_customer_payments_customer ON sales.customer_payments (customer_id);
CREATE INDEX idx_customer_payments_date     ON sales.customer_payments (payment_date);
CREATE INDEX idx_customer_payments_status   ON sales.customer_payments (status);

CREATE TRIGGER trg_customer_payments_updated_at
    BEFORE UPDATE ON sales.customer_payments
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.customer_payments                  IS 'Pagos recibidos de clientes. Pueden cubrir una o varias facturas.';
COMMENT ON COLUMN sales.customer_payments.amount_unallocated IS 'Calculado: monto - asignado. Saldo sin aplicar a facturas (crédito a favor).';

-- ============================================================
-- Asignación de pagos a facturas
-- ============================================================
CREATE TABLE sales.payment_allocations (
    id              BIGSERIAL   PRIMARY KEY,
    payment_id      BIGINT      NOT NULL REFERENCES sales.customer_payments(id) ON DELETE RESTRICT,
    invoice_id      BIGINT      REFERENCES sales.invoices(id),
    credit_note_id  BIGINT      REFERENCES sales.credit_notes(id),
    -- un pago puede compensarse con una NC

    amount_applied  NUMERIC(18,4) NOT NULL,
    -- cuánto de este pago se aplica a esta factura

    applied_by      BIGINT,
    -- employee_id
    applied_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payment_allocations_payment  ON sales.payment_allocations (payment_id);
CREATE INDEX idx_payment_allocations_invoice  ON sales.payment_allocations (invoice_id);

COMMENT ON TABLE sales.payment_allocations IS 'Asignación de pagos a facturas. Un pago puede cubrir múltiples facturas y compensar notas de crédito.';

-- ============================================================
-- Cuotas de pago (para facturas con pago en cuotas)
-- ============================================================
CREATE TABLE sales.invoice_installments (
    id              BIGSERIAL   PRIMARY KEY,
    invoice_id      BIGINT      NOT NULL REFERENCES sales.invoices(id),
    installment_number INTEGER  NOT NULL,
    due_date        DATE        NOT NULL,
    amount          NUMERIC(18,4) NOT NULL,
    amount_paid     NUMERIC(18,4) NOT NULL DEFAULT 0,
    status          VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending | partial | paid | overdue

    paid_at         TIMESTAMPTZ,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (invoice_id, installment_number)
);

CREATE INDEX idx_installments_invoice ON sales.invoice_installments (invoice_id);
CREATE INDEX idx_installments_due     ON sales.invoice_installments (due_date)
    WHERE status IN ('pending', 'partial');

CREATE TRIGGER trg_installments_updated_at
    BEFORE UPDATE ON sales.invoice_installments
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE sales.invoice_installments IS 'Cuotas de pago para facturas con condición de cuotas. Cada cuota tiene su propia fecha de vencimiento.';

-- ============================================================
-- Gestión de cobranza (recordatorios y seguimiento)
-- ============================================================
CREATE TABLE sales.collection_reminders (
    id                      BIGSERIAL   PRIMARY KEY,
    company_id              BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    invoice_id              BIGINT      NOT NULL REFERENCES sales.invoices(id),
    customer_id             BIGINT      NOT NULL REFERENCES sales.customers(id),
    collection_status_id    INTEGER     NOT NULL REFERENCES sales.collection_statuses(id),

    reminder_number         INTEGER     NOT NULL DEFAULT 1,
    -- 1=primer aviso, 2=segundo aviso, 3=tercero (pre-legal)

    -- Monto en mora
    overdue_days            INTEGER     NOT NULL DEFAULT 0,
    overdue_amount          NUMERIC(18,4) NOT NULL,

    -- Gestión
    assigned_to             BIGINT,
    -- employee_id del gestor de cobranza
    contact_method          VARCHAR(20),
    -- phone | email | whatsapp | visit | letter

    last_contact_at         TIMESTAMPTZ,
    last_contact_notes      TEXT,

    -- Promesa de pago
    promise_date            DATE,
    promise_amount          NUMERIC(18,4),
    promise_kept            BOOLEAN,

    -- Escalado a legal
    escalated_to_legal      BOOLEAN     NOT NULL DEFAULT FALSE,
    escalated_at            TIMESTAMPTZ,

    notes                   TEXT,
    is_active               BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_collection_company  ON sales.collection_reminders (company_id);
CREATE INDEX idx_collection_invoice  ON sales.collection_reminders (invoice_id);
CREATE INDEX idx_collection_customer ON sales.collection_reminders (customer_id);
CREATE INDEX idx_collection_status   ON sales.collection_reminders (collection_status_id);

CREATE TRIGGER trg_collection_updated_at
    BEFORE UPDATE ON sales.collection_reminders
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.collection_reminders                  IS 'Gestión de cobranza de facturas vencidas: recordatorios, promesas de pago y escalado a legal.';
COMMENT ON COLUMN sales.collection_reminders.reminder_number  IS '1=primer aviso, 2=segundo aviso, 3=pre-legal. Escala automáticamente según días de mora.';
