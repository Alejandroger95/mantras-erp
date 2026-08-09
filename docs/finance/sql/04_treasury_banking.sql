-- ============================================================
-- mantrasdb | Módulo Finance
-- Archivo: 04_treasury_banking.sql
-- Descripción: Tesorería y Bancos — gestión de cuentas bancarias,
--              conciliación, caja chica, tipos de cambio.
--
-- Módulos:
--   1. bank_accounts          — cuentas bancarias de la empresa
--   2. bank_transactions      — movimientos bancarios
--   3. bank_reconciliations   — conciliación mensual
--   4. bank_reconciliation_items — partidas conciliadas
--   5. petty_cash             — cajas chicas (fondos fijos)
--   6. petty_cash_transactions — movimientos de caja chica
--   7. exchange_rates         — tipos de cambio (SBS Perú, BCE España)
--   8. currency_conversions   — historial de conversiones realizadas
--
-- 🇵🇪 Tipos de cambio: SBS publica tipo compra y venta diariamente.
-- 🇪🇸 España: BCE / Banco de España para EUR/otras monedas.
-- ============================================================

-- ============================================================
-- 1. CUENTAS BANCARIAS DE LA EMPRESA
-- ============================================================
CREATE TABLE finance.bank_accounts (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- Datos del banco
    bank_name           VARCHAR(200) NOT NULL,
    -- "Banco de Crédito del Perú", "BBVA Perú", "Interbank", etc.

    bank_code           VARCHAR(10),
    -- código SUNAT del banco (002=BCP, 011=BBVA, 018=BIF, 023=Interbank)

    -- Cuenta
    account_number      VARCHAR(30) NOT NULL,
    account_type        VARCHAR(20) NOT NULL DEFAULT 'checking',
    -- checking     : cuenta corriente
    -- savings      : cuenta de ahorros
    -- cts          : CTS (Compensación por Tiempo de Servicio)
    -- trust        : fideicomiso
    -- investment   : inversión

    -- CCI / IBAN
    cci                 VARCHAR(30),
    -- CCI de 20 dígitos (Perú: Código de Cuenta Interbancario)
    iban                VARCHAR(34),
    -- IBAN (España / Europa)

    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',
    -- PEN | USD | EUR

    -- Cuenta contable vinculada (104x en PCGE Perú / 57x en PGC España)
    gl_account_id       BIGINT      REFERENCES finance.accounts(id),

    -- Saldo
    current_balance     NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- saldo contable actual (actualizado con cada transacción confirmada)

    last_reconciled_date DATE,
    last_reconciled_balance NUMERIC(18,2),

    -- Límites y alertas
    min_balance_alert   NUMERIC(18,2),
    -- alerta cuando el saldo cae por debajo de este importe

    -- Estado
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    is_petty_cash       BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE si es la cuenta contable de una caja chica

    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, account_number)
);

CREATE INDEX idx_bkacc_company  ON finance.bank_accounts (company_id);
CREATE INDEX idx_bkacc_currency ON finance.bank_accounts (currency);

CREATE TRIGGER trg_bkacc_updated_at
    BEFORE UPDATE ON finance.bank_accounts
    FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at();

COMMENT ON TABLE  finance.bank_accounts              IS 'Cuentas bancarias de la empresa. Cada cuenta tiene su moneda y su cuenta contable vinculada (104x PCGE / 57x PGC).';
COMMENT ON COLUMN finance.bank_accounts.cci          IS '🇵🇪 Código de Cuenta Interbancario (20 dígitos). Requerido para transferencias interbancarias en Perú.';

-- ============================================================
-- 2. TRANSACCIONES BANCARIAS
--    Movimientos reales de la cuenta. Pueden venir del extracto
--    bancario (importado) o ser registrados manualmente.
-- ============================================================
CREATE TABLE finance.bank_transactions (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    bank_account_id     BIGINT      NOT NULL REFERENCES finance.bank_accounts(id) ON DELETE RESTRICT,

    -- Fecha del movimiento (según extracto)
    transaction_date    DATE        NOT NULL,
    value_date          DATE,
    -- fecha valor (disponibilidad real del dinero)

    -- Tipo de movimiento
    transaction_type    VARCHAR(30) NOT NULL,
    -- deposit         : abono / depósito
    -- withdrawal      : cargo / retiro
    -- transfer_in     : transferencia recibida
    -- transfer_out    : transferencia enviada
    -- fee             : comisión bancaria
    -- interest        : interés acreditado
    -- tax_collection  : cobro de impuesto por el banco
    -- direct_debit    : domiciliación
    -- check_payment   : pago con cheque
    -- pos_sale        : venta POS (abono)
    -- yape_plin       : cobro Yape/Plin

    amount              NUMERIC(18,2) NOT NULL,
    -- positivo = abono / negativo = cargo

    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',

    -- Descripción del extracto
    description         VARCHAR(500),
    reference           VARCHAR(100),
    -- número de operación del banco

    -- Estado de conciliación
    reconciliation_status VARCHAR(20) NOT NULL DEFAULT 'unreconciled',
    -- unreconciled : sin conciliar
    -- reconciled   : conciliado con movimiento contable
    -- excluded     : excluido (no afecta contabilidad, ej: error bancario)

    reconciliation_id   BIGINT,
    -- REFERENCES finance.bank_reconciliations(id) — FK diferida

    -- Vinculo al asiento contable generado
    journal_entry_id    BIGINT      REFERENCES finance.journal_entries(id),

    -- Origen del movimiento
    source              VARCHAR(20) NOT NULL DEFAULT 'import',
    -- import   : importado del extracto bancario
    -- manual   : registrado manualmente
    -- payment  : generado desde supplier_payments
    -- collection: generado desde sales.customer_payments

    -- Documento origen (pago a proveedor, cobro a cliente, etc.)
    source_document_type VARCHAR(50),
    source_document_id   BIGINT,

    is_reconciled       BOOLEAN GENERATED ALWAYS AS
        (reconciliation_status = 'reconciled') STORED,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_bktx_account      ON finance.bank_transactions (bank_account_id);
CREATE INDEX idx_bktx_company      ON finance.bank_transactions (company_id);
CREATE INDEX idx_bktx_date         ON finance.bank_transactions (transaction_date);
CREATE INDEX idx_bktx_status       ON finance.bank_transactions (reconciliation_status);
CREATE INDEX idx_bktx_source       ON finance.bank_transactions (source_document_type, source_document_id);

CREATE TRIGGER trg_bktx_updated_at
    BEFORE UPDATE ON finance.bank_transactions
    FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at();

COMMENT ON TABLE  finance.bank_transactions                   IS 'Movimientos del extracto bancario. Se importan o registran manualmente y luego se concilian con los asientos contables.';
COMMENT ON COLUMN finance.bank_transactions.value_date        IS 'Fecha valor del banco (cuando el dinero está disponible). Puede diferir de transaction_date.';
COMMENT ON COLUMN finance.bank_transactions.reconciliation_status IS 'unreconciled → reconciled cuando se cruza con el movimiento contable correspondiente.';

-- ============================================================
-- 3. CONCILIACIONES BANCARIAS (mensual por cuenta)
-- ============================================================
CREATE TABLE finance.bank_reconciliations (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    bank_account_id     BIGINT      NOT NULL REFERENCES finance.bank_accounts(id) ON DELETE RESTRICT,
    accounting_period_id BIGINT     NOT NULL REFERENCES finance.accounting_periods(id),

    reconciliation_date DATE        NOT NULL,

    -- Saldos al cierre del período
    statement_balance   NUMERIC(18,2) NOT NULL,
    -- saldo según el extracto bancario (banco)

    book_balance        NUMERIC(18,2) NOT NULL,
    -- saldo según los libros contables (cuenta 104x/57x)

    -- Partidas de conciliación
    outstanding_checks  NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- cheques emitidos no cobrados aún por el beneficiario

    deposits_in_transit NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- depósitos enviados pero no acreditados aún

    bank_errors         NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- errores del banco (débitos/créditos incorrectos)

    book_errors         NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- errores en libros (registros incorrectos)

    bank_charges        NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- comisiones y cargos bancarios no registrados en libros

    bank_interest       NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- intereses acreditados no registrados en libros

    -- Saldo ajustado (debe cuadrar con el contable)
    adjusted_statement_balance NUMERIC(18,2) GENERATED ALWAYS AS (
        statement_balance
        + deposits_in_transit
        - outstanding_checks
        + bank_errors
    ) STORED,

    adjusted_book_balance NUMERIC(18,2) GENERATED ALWAYS AS (
        book_balance
        + bank_interest
        - bank_charges
        + book_errors
    ) STORED,

    -- Diferencia (debe ser 0 al finalizar)
    difference          NUMERIC(18,2) GENERATED ALWAYS AS (
        (statement_balance + deposits_in_transit - outstanding_checks + bank_errors)
        - (book_balance + bank_interest - bank_charges + book_errors)
    ) STORED,

    status              VARCHAR(20) NOT NULL DEFAULT 'in_progress',
    -- in_progress : en proceso de conciliación
    -- completed   : conciliación cuadrada (difference = 0)
    -- approved    : aprobada por el responsable

    notes               TEXT,
    completed_by        BIGINT,
    completed_at        TIMESTAMPTZ,
    approved_by         BIGINT,
    approved_at         TIMESTAMPTZ,

    created_by          BIGINT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (bank_account_id, accounting_period_id)
);

CREATE TRIGGER trg_bkrec_updated_at
    BEFORE UPDATE ON finance.bank_reconciliations
    FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at();

COMMENT ON TABLE  finance.bank_reconciliations        IS 'Conciliación bancaria mensual. adjusted_statement_balance debe igualar adjusted_book_balance al cerrar.';
COMMENT ON COLUMN finance.bank_reconciliations.difference IS 'Diferencia entre saldo ajustado del banco y saldo ajustado de libros. Debe ser 0 para aprobar.';

-- FK diferida
ALTER TABLE finance.bank_transactions
    ADD CONSTRAINT fk_bktx_reconciliation
    FOREIGN KEY (reconciliation_id)
    REFERENCES finance.bank_reconciliations(id);

-- ============================================================
-- 4. PARTIDAS DE CONCILIACIÓN (ITEMS)
--    Cada transacción bancaria cruzada con su asiento contable.
-- ============================================================
CREATE TABLE finance.bank_reconciliation_items (
    id                      BIGSERIAL   PRIMARY KEY,
    bank_reconciliation_id  BIGINT      NOT NULL REFERENCES finance.bank_reconciliations(id) ON DELETE RESTRICT,
    company_id              BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Movimiento bancario (del extracto)
    bank_transaction_id     BIGINT      REFERENCES finance.bank_transactions(id),

    -- Movimiento contable (del libro mayor)
    journal_entry_line_id   BIGINT      REFERENCES finance.journal_entry_lines(id),

    -- Tipo de partida
    item_type               VARCHAR(30) NOT NULL,
    -- matched              : conciliado (banco ↔ libro cuadran)
    -- outstanding_check    : cheque emitido no cobrado
    -- deposit_in_transit   : depósito en tránsito
    -- bank_only            : en extracto, no en libros (comisión, etc.)
    -- book_only            : en libros, no en extracto (asiento manual)
    -- discrepancy          : diferencia de importe

    amount                  NUMERIC(18,2) NOT NULL,
    notes                   TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_bkrecitem_rec   ON finance.bank_reconciliation_items (bank_reconciliation_id);
CREATE INDEX idx_bkrecitem_bktx  ON finance.bank_reconciliation_items (bank_transaction_id);

COMMENT ON TABLE finance.bank_reconciliation_items IS 'Partidas de la conciliación bancaria. Cada ítem cruza un movimiento del extracto con un asiento contable.';

-- ============================================================
-- 5. CAJAS CHICAS (PETTY CASH — FONDOS FIJOS)
--    Perú: "Caja Chica". España: "Caja Pequeña".
--    Cuenta PCGE: 102 "Fondos Fijos"
-- ============================================================
CREATE TABLE finance.petty_cash (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    name                VARCHAR(100) NOT NULL,
    -- "Caja Chica Oficina Lima", "Fondo Fijo Almacén"

    custodian_id        BIGINT,
    -- empleado responsable
    -- REFERENCES hr.employees(id) — FK diferida

    -- Importe del fondo
    fund_amount         NUMERIC(18,2) NOT NULL,
    -- monto asignado al fondo fijo

    current_balance     NUMERIC(18,2) NOT NULL,
    -- saldo actual disponible

    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',

    -- Cuenta contable (102x PCGE)
    gl_account_id       BIGINT      REFERENCES finance.accounts(id),

    -- Importe mínimo para reposición
    replenishment_threshold NUMERIC(18,2),
    -- cuando current_balance < threshold se solicita reposición

    status              VARCHAR(20) NOT NULL DEFAULT 'active',
    -- active    : en operación
    -- suspended : suspendido temporalmente
    -- closed    : cerrado definitivamente

    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_pcash_updated_at
    BEFORE UPDATE ON finance.petty_cash
    FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at();

COMMENT ON TABLE finance.petty_cash IS 'Cajas chicas (fondos fijos). Se recargan periódicamente. Cuenta PCGE 102 "Fondos Fijos".';

-- ============================================================
-- 6. MOVIMIENTOS DE CAJA CHICA
-- ============================================================
CREATE TABLE finance.petty_cash_transactions (
    id                  BIGSERIAL   PRIMARY KEY,
    petty_cash_id       BIGINT      NOT NULL REFERENCES finance.petty_cash(id) ON DELETE RESTRICT,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    transaction_date    DATE        NOT NULL,

    transaction_type    VARCHAR(20) NOT NULL,
    -- expense        : gasto (salida de caja)
    -- replenishment  : reposición del fondo (entrada de caja)
    -- adjustment     : ajuste por diferencia de arqueo

    description         VARCHAR(300) NOT NULL,

    amount              NUMERIC(18,2) NOT NULL,
    -- positivo = entrada (reposición) / negativo = salida (gasto)

    -- Comprobante de respaldo
    receipt_type        VARCHAR(30),
    -- 'boleta' | 'factura' | 'recibo' | 'vale_interno' | 'ticket'
    receipt_number      VARCHAR(50),
    supplier_name       VARCHAR(200),
    -- proveedor / beneficiario del gasto

    -- Cuenta de gasto
    expense_account_id  BIGINT      REFERENCES finance.accounts(id),

    cost_center_id      BIGINT,
    -- REFERENCES finance.cost_centers(id) — FK diferida

    category            VARCHAR(50),
    -- 'transport' | 'office_supplies' | 'meals' | 'courier' | 'utilities' | 'other'

    -- Asiento contable (al rendirse la caja chica)
    journal_entry_id    BIGINT      REFERENCES finance.journal_entries(id),

    -- Foto del comprobante
    receipt_photo_url   VARCHAR(500),

    approved_by         BIGINT,
    approved_at         TIMESTAMPTZ,

    created_by          BIGINT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- Inmutable: no tiene updated_at
);

CREATE INDEX idx_pctx_petty_cash ON finance.petty_cash_transactions (petty_cash_id);
CREATE INDEX idx_pctx_date       ON finance.petty_cash_transactions (transaction_date);
CREATE INDEX idx_pctx_type       ON finance.petty_cash_transactions (transaction_type);

COMMENT ON TABLE  finance.petty_cash_transactions IS 'Movimientos de caja chica. Los gastos se rinden periódicamente generando un asiento de reposición.';
COMMENT ON COLUMN finance.petty_cash_transactions.amount IS 'Positivo=entrada (reposición del fondo). Negativo=salida (gasto pagado con la caja).';

-- ============================================================
-- 7. TIPOS DE CAMBIO
--    Perú: SBS publica tipo compra y tipo venta diariamente.
--    España: BCE publica el tipo de referencia (único).
--    Se almacena el historial para poder contabilizar
--    al tipo correcto en la fecha del asiento.
-- ============================================================
CREATE TABLE finance.exchange_rates (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      REFERENCES hr.companies(id),
    -- NULL = tipo de cambio del sistema (pre-cargado de SBS/BCE)
    -- ID   = tipo de cambio personalizado por empresa

    rate_date           DATE        NOT NULL,
    from_currency       VARCHAR(10) NOT NULL,
    to_currency         VARCHAR(10) NOT NULL,

    -- Tasa de compra (el banco te compra divisas a este precio)
    buy_rate            NUMERIC(18,8) NOT NULL,
    -- Tasa de venta (el banco te vende divisas a este precio)
    sell_rate           NUMERIC(18,8) NOT NULL,
    -- Tasa promedio (usada para contabilización — SBS promedio ponderado)
    mid_rate            NUMERIC(18,8) NOT NULL,

    -- Fuente de la tasa
    rate_source         VARCHAR(20) NOT NULL DEFAULT 'sbs',
    -- sbs     : Superintendencia de Banca y Seguros (Perú)
    -- bce     : Banco Central Europeo (España)
    -- banrep  : Banco de la República (Colombia)
    -- manual  : ingresado manualmente por el usuario

    is_official         BOOLEAN     NOT NULL DEFAULT TRUE,
    -- TRUE = tipo oficial del banco central / SBS

    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- UNIQUE con expresión (COALESCE) requiere índice único, no constraint de tabla
CREATE UNIQUE INDEX uq_exchange_rates
    ON finance.exchange_rates (COALESCE(company_id, 0::BIGINT), rate_date, from_currency, to_currency, rate_source);

CREATE INDEX idx_exrate_date     ON finance.exchange_rates (rate_date);
CREATE INDEX idx_exrate_pair     ON finance.exchange_rates (from_currency, to_currency);
CREATE INDEX idx_exrate_company  ON finance.exchange_rates (company_id) WHERE company_id IS NOT NULL;

COMMENT ON TABLE  finance.exchange_rates           IS 'Historial de tipos de cambio. SBS Perú (compra/venta diaria), BCE España (referencia). Se usa para valorar asientos en moneda extranjera.';
COMMENT ON COLUMN finance.exchange_rates.buy_rate  IS 'Tipo compra: precio al que el banco compra divisas al cliente (ej: USD→PEN). Para ingresos en USD.';
COMMENT ON COLUMN finance.exchange_rates.sell_rate IS 'Tipo venta: precio al que el banco vende divisas al cliente (ej: PEN→USD). Para pagos en USD.';
COMMENT ON COLUMN finance.exchange_rates.mid_rate  IS 'Tipo promedio ponderado (SBS). Se usa para contabilización según NIC 21.';

-- Función para obtener el tipo de cambio vigente para una fecha
CREATE OR REPLACE FUNCTION finance.get_exchange_rate(
    p_date          DATE,
    p_from_currency VARCHAR,
    p_to_currency   VARCHAR,
    p_company_id    BIGINT DEFAULT NULL,
    p_rate_type     VARCHAR DEFAULT 'mid'  -- 'mid' | 'buy' | 'sell'
)
RETURNS NUMERIC(18,8) LANGUAGE plpgsql AS $$
DECLARE
    v_rate NUMERIC(18,8);
BEGIN
    -- Si son la misma moneda, retornar 1
    IF p_from_currency = p_to_currency THEN
        RETURN 1.0;
    END IF;

    -- Buscar tipo de cambio: primero empresa, luego sistema, retroceder hasta 7 días
    SELECT
        CASE p_rate_type
            WHEN 'buy'  THEN buy_rate
            WHEN 'sell' THEN sell_rate
            ELSE mid_rate
        END
    INTO v_rate
    FROM finance.exchange_rates
    WHERE from_currency = p_from_currency
      AND to_currency   = p_to_currency
      AND rate_date    <= p_date
      AND (company_id = p_company_id OR company_id IS NULL)
    ORDER BY
        CASE WHEN company_id = p_company_id THEN 0 ELSE 1 END,
        rate_date DESC
    LIMIT 1;

    IF v_rate IS NULL THEN
        RAISE WARNING 'No se encontró tipo de cambio para %→% al %. Usando 1.0',
            p_from_currency, p_to_currency, p_date;
        RETURN 1.0;
    END IF;

    RETURN v_rate;
END;
$$;

COMMENT ON FUNCTION finance.get_exchange_rate IS 'Obtiene el tipo de cambio vigente para una fecha. Prioriza tipos de la empresa sobre los del sistema. Retrocede hasta 7 días si no hay dato del día exacto.';

-- ============================================================
-- 8. HISTORIAL DE CONVERSIONES REALIZADAS
--    Registro de cada vez que se usó un tipo de cambio
--    para una transacción (trazabilidad para auditoría).
-- ============================================================
CREATE TABLE finance.currency_conversions (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    conversion_date     DATE        NOT NULL,
    from_currency       VARCHAR(10) NOT NULL,
    to_currency         VARCHAR(10) NOT NULL,
    exchange_rate_id    BIGINT      REFERENCES finance.exchange_rates(id),

    rate_used           NUMERIC(18,8) NOT NULL,
    rate_type           VARCHAR(10) NOT NULL DEFAULT 'mid',
    -- mid | buy | sell

    amount_from         NUMERIC(18,2) NOT NULL,
    amount_to           NUMERIC(18,2) NOT NULL,

    -- Documento que originó la conversión
    source_document_type VARCHAR(50),
    source_document_id   BIGINT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- Inmutable
);

CREATE INDEX idx_ccnv_company ON finance.currency_conversions (company_id);
CREATE INDEX idx_ccnv_date    ON finance.currency_conversions (conversion_date);

COMMENT ON TABLE finance.currency_conversions IS 'Registro de conversiones de moneda realizadas. Trazabilidad completa del tipo de cambio usado en cada transacción.';

-- ============================================================
-- 9. PREVISIONES DE TESORERÍA (CASH FLOW FORECAST)
--    Proyección de entradas y salidas futuras de efectivo.
-- ============================================================
CREATE TABLE finance.cash_flow_forecasts (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    bank_account_id     BIGINT      REFERENCES finance.bank_accounts(id),

    forecast_date       DATE        NOT NULL,
    -- fecha esperada del movimiento

    flow_type           VARCHAR(20) NOT NULL,
    -- inflow  : entrada de efectivo esperada
    -- outflow : salida de efectivo esperada

    category            VARCHAR(50),
    -- 'customer_payment' | 'supplier_payment' | 'payroll' |
    -- 'tax' | 'loan' | 'other'

    description         VARCHAR(300) NOT NULL,
    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',
    expected_amount     NUMERIC(18,2) NOT NULL,
    actual_amount       NUMERIC(18,2),
    -- importe real cuando se materializa

    -- Documento origen
    source_document_type VARCHAR(50),
    source_document_id   BIGINT,
    -- ej: supplier_invoices.id con due_date próximo

    status              VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending   : esperado, no realizado
    -- realized  : realizado
    -- cancelled : cancelado / no se materializó

    probability_pct     SMALLINT    NOT NULL DEFAULT 100,
    -- probabilidad de ocurrencia (100% = certeza)

    created_by          BIGINT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_cff_company ON finance.cash_flow_forecasts (company_id);
CREATE INDEX idx_cff_date    ON finance.cash_flow_forecasts (forecast_date);
CREATE INDEX idx_cff_status  ON finance.cash_flow_forecasts (status);

CREATE TRIGGER trg_cff_updated_at
    BEFORE UPDATE ON finance.cash_flow_forecasts
    FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at();

COMMENT ON TABLE finance.cash_flow_forecasts IS 'Previsión de tesorería: entradas y salidas futuras esperadas. Permite gestión proactiva de liquidez.';
