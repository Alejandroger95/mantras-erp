-- ============================================================
-- mantrasdb | Módulo Finance
-- Archivo: 08_closing_intercompany.sql
-- Descripción: Cierre de ejercicio, Revaluación de moneda
--              y Transacciones intercompany.
--
-- Módulos:
--   1. currency_revaluations    — ajuste por diferencia de cambio
--   2. intercompany_transactions — operaciones entre empresas del grupo
--   3. closing_procedures       — pasos del cierre de ejercicio
--   4. financial_statements     — snapshots de estados financieros
--   5. FKs diferidas finales
-- ============================================================

-- ============================================================
-- 1. REVALUACIONES DE MONEDA EXTRANJERA
--    Al cierre de cada mes, las cuentas en moneda extranjera
--    se revalúan al tipo de cambio del último día del período.
--    NIC 21: la diferencia va a resultados (77x/67x PCGE Perú).
-- ============================================================
CREATE TABLE finance.currency_revaluations (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    accounting_period_id BIGINT     NOT NULL REFERENCES finance.accounting_periods(id),

    revaluation_date    DATE        NOT NULL,
    -- último día del período

    foreign_currency    VARCHAR(10) NOT NULL,
    -- moneda extranjera revaluada (ej: USD, EUR)

    exchange_rate_id    BIGINT      REFERENCES finance.exchange_rates(id),
    closing_rate        NUMERIC(18,8) NOT NULL,
    -- tipo de cambio de cierre (SBS del último día del mes)

    previous_rate       NUMERIC(18,8) NOT NULL,
    -- tipo de cambio de la revaluación anterior

    -- Cuentas revaluadas (JSONB para flexibilidad)
    accounts_revalued   JSONB,
    -- [{"account_id": 123, "account_code": "1041", "balance_foreign": 5000,
    --   "balance_prev_pen": 17500, "balance_new_pen": 18250, "difference": 750}]

    total_gain          NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- ganancia cambiaria total (→ cta 773 PCGE / 763 PGC)
    total_loss          NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- pérdida cambiaria total (→ cta 673 PCGE / 668 PGC)
    net_difference      NUMERIC(18,2) GENERATED ALWAYS AS
        (total_gain - total_loss) STORED,

    -- Asiento generado
    journal_entry_id    BIGINT      REFERENCES finance.journal_entries(id),

    status              VARCHAR(20) NOT NULL DEFAULT 'draft',
    -- draft | posted | reversed

    executed_by         BIGINT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- Inmutable al postear
);

CREATE INDEX idx_crev_company ON finance.currency_revaluations (company_id);
CREATE INDEX idx_crev_period  ON finance.currency_revaluations (accounting_period_id);

COMMENT ON TABLE  finance.currency_revaluations IS 'Revaluación mensual de saldos en moneda extranjera (NIC 21). La diferencia cambiaria va a cuentas 773/673 en PCGE o 763/668 en PGC.';
COMMENT ON COLUMN finance.currency_revaluations.accounts_revalued IS 'JSONB con detalle de cada cuenta revaluada: saldo en ME, saldo previo en MN, saldo nuevo en MN, diferencia.';

-- ============================================================
-- 2. TRANSACCIONES INTERCOMPANY
--    Operaciones entre empresas del mismo grupo empresarial.
--    Deben eliminarse en la consolidación.
-- ============================================================
CREATE TABLE finance.intercompany_transactions (
    id                  BIGSERIAL   PRIMARY KEY,

    -- Empresa que origina la transacción
    originating_company_id BIGINT   NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    -- Empresa que recibe la transacción
    receiving_company_id   BIGINT   NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    transaction_date    DATE        NOT NULL,

    transaction_type    VARCHAR(20) NOT NULL,
    -- sale            : venta intercompany (ej: holding vende a subsidiaria)
    -- purchase        : compra intercompany
    -- loan            : préstamo entre empresas
    -- service_charge  : cargo por servicios de gestión (management fee)
    -- dividend        : dividendo intercompany
    -- capital_transfer: transferencia de capital
    -- recharge        : redistribución de costos

    description         VARCHAR(500) NOT NULL,
    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',
    amount              NUMERIC(18,2) NOT NULL,
    exchange_rate       NUMERIC(18,8) NOT NULL DEFAULT 1.0,
    amount_functional   NUMERIC(18,2) NOT NULL,

    -- Estado de matching (debe coincidir en ambas empresas)
    matching_status     VARCHAR(20) NOT NULL DEFAULT 'unmatched',
    -- unmatched   : solo una empresa lo tiene registrado
    -- matched     : ambas empresas tienen el asiento
    -- reconciled  : verificado y conciliado
    -- difference  : hay diferencia entre las dos empresas

    -- Asientos en cada empresa
    originating_journal_entry_id BIGINT REFERENCES finance.journal_entries(id),
    receiving_journal_entry_id   BIGINT REFERENCES finance.journal_entries(id),

    -- ¿Eliminación en consolidación?
    is_eliminated       BOOLEAN     NOT NULL DEFAULT FALSE,
    elimination_entry_id BIGINT     REFERENCES finance.journal_entries(id),

    -- Referencia al documento origen en cada empresa
    originating_invoice_id  BIGINT,
    receiving_invoice_id    BIGINT,

    notes               TEXT,
    created_by          BIGINT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ic_orig ON finance.intercompany_transactions (originating_company_id);
CREATE INDEX idx_ic_recv ON finance.intercompany_transactions (receiving_company_id);
CREATE INDEX idx_ic_date ON finance.intercompany_transactions (transaction_date);

CREATE TRIGGER trg_ic_updated_at
    BEFORE UPDATE ON finance.intercompany_transactions
    FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at();

COMMENT ON TABLE  finance.intercompany_transactions IS 'Transacciones entre empresas del grupo. Deben estar en matching antes del cierre para garantizar la eliminación correcta en la consolidación.';

-- ============================================================
-- 3. PROCEDIMIENTOS DE CIERRE DE EJERCICIO
--    Check-list del proceso de cierre. Cada paso se marca
--    cuando está completo.
-- ============================================================
CREATE TABLE finance.closing_procedures (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    fiscal_year_id      BIGINT      NOT NULL REFERENCES finance.fiscal_years(id),

    -- Paso del proceso de cierre
    step_code           VARCHAR(30) NOT NULL,
    step_name           VARCHAR(200) NOT NULL,
    step_description    TEXT,
    step_order          SMALLINT    NOT NULL,

    -- Área responsable
    responsible_area    VARCHAR(50),
    -- 'accounting' | 'treasury' | 'tax' | 'management' | 'audit'

    status              VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending    : pendiente
    -- in_progress: en proceso
    -- completed  : completado
    -- skipped    : omitido (justificado)
    -- blocked    : bloqueado por un paso anterior

    -- Asiento generado por este paso (si aplica)
    journal_entry_id    BIGINT      REFERENCES finance.journal_entries(id),

    due_date            DATE,
    completed_by        BIGINT,
    completed_at        TIMESTAMPTZ,
    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (fiscal_year_id, step_code)
);

-- Pasos estándar del cierre (se insertan al iniciar el proceso de cierre)
-- Esta función los genera por empresa y año fiscal
CREATE OR REPLACE FUNCTION finance.initialize_closing_procedures(
    p_company_id    BIGINT,
    p_fiscal_year_id BIGINT
)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE v_rows INTEGER;
BEGIN
    INSERT INTO finance.closing_procedures
        (company_id, fiscal_year_id, step_code, step_name, step_order, responsible_area)
    VALUES
        (p_company_id, p_fiscal_year_id, 'BANK_REC',       'Conciliación bancaria de todos los períodos',              1,  'treasury'),
        (p_company_id, p_fiscal_year_id, 'AP_CUTOFF',      'Corte de cuentas por pagar (facturas pendientes)',          2,  'accounting'),
        (p_company_id, p_fiscal_year_id, 'AR_CUTOFF',      'Corte de cuentas por cobrar (facturas emitidas)',           3,  'accounting'),
        (p_company_id, p_fiscal_year_id, 'INVENTORY',      'Valuación de inventarios (FEFO/promedio/NIIF)',             4,  'accounting'),
        (p_company_id, p_fiscal_year_id, 'FIXED_ASSETS',   'Ejecución de depreciación del último período',              5,  'accounting'),
        (p_company_id, p_fiscal_year_id, 'ACCRUALS',       'Devengos: gastos del ejercicio sin factura',               6,  'accounting'),
        (p_company_id, p_fiscal_year_id, 'PREPAYMENTS',    'Ajuste de pagos anticipados y seguros por devengar',       7,  'accounting'),
        (p_company_id, p_fiscal_year_id, 'FX_REVALUATION', 'Revaluación de saldos en moneda extranjera (NIC 21)',      8,  'accounting'),
        (p_company_id, p_fiscal_year_id, 'IC_MATCHING',    'Conciliación de operaciones intercompany',                 9,  'accounting'),
        (p_company_id, p_fiscal_year_id, 'PROVISIONS',     'Provisiones: CTS, vacaciones, cobranza dudosa',           10,  'accounting'),
        (p_company_id, p_fiscal_year_id, 'TAX_REVIEW',     'Revisión de impuestos diferidos (NIC 12)',                11,  'tax'),
        (p_company_id, p_fiscal_year_id, 'INCOME_TAX',     'Cálculo del Impuesto a la Renta / IS del ejercicio',     12,  'tax'),
        (p_company_id, p_fiscal_year_id, 'BUDGET_ANALYSIS','Análisis presupuesto vs real — informe de desviaciones',  13,  'management'),
        (p_company_id, p_fiscal_year_id, 'TRIAL_BALANCE',  'Revisión del Balance de Comprobación final',              14,  'accounting'),
        (p_company_id, p_fiscal_year_id, 'CLOSING_ENTRY',  'Asiento de cierre (traslado a resultados acumulados)',    15,  'accounting'),
        (p_company_id, p_fiscal_year_id, 'OPENING_ENTRY',  'Asiento de apertura del nuevo ejercicio',                 16,  'accounting'),
        (p_company_id, p_fiscal_year_id, 'PLE_SUNAT',      'Generación y validación de Libros Electrónicos PLE',      17,  'tax'),
        (p_company_id, p_fiscal_year_id, 'LOCK_YEAR',      'Bloqueo del ejercicio cerrado (status=locked)',           18,  'management'),
        (p_company_id, p_fiscal_year_id, 'AUDIT_DOCS',     'Preparación de documentación para auditoría',             19,  'audit')
    ON CONFLICT (fiscal_year_id, step_code) DO NOTHING;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows;
END;
$$;

COMMENT ON TABLE finance.closing_procedures IS 'Check-list del cierre de ejercicio. 19 pasos estándar desde conciliación bancaria hasta bloqueo del año y entrega de documentación a auditoría.';
COMMENT ON FUNCTION finance.initialize_closing_procedures IS 'Genera los 19 pasos estándar del proceso de cierre para una empresa y año fiscal. Llamar al iniciar el cierre.';

-- ============================================================
-- 4. ESTADOS FINANCIEROS — SNAPSHOTS
--    Al cerrar el ejercicio se guardan los estados financieros
--    como snapshot (inmutable para comparativos futuros).
-- ============================================================
CREATE TABLE finance.financial_statement_snapshots (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),
    fiscal_year_id      BIGINT      NOT NULL REFERENCES finance.fiscal_years(id),
    accounting_period_id BIGINT     REFERENCES finance.accounting_periods(id),
    -- NULL = cierre del ejercicio completo

    statement_type      VARCHAR(30) NOT NULL,
    -- balance_sheet       : Balance General / Estado de Situación Financiera
    -- income_statement    : Estado de Resultados / P&L
    -- cash_flow           : Estado de Flujos de Efectivo (indirecto/directo)
    -- equity_changes      : Estado de Cambios en el Patrimonio

    snapshot_date       DATE        NOT NULL,
    -- fecha a la que corresponde el estado financiero

    -- Contenido del estado financiero en JSONB
    -- Permite almacenar la estructura completa del estado
    statement_data      JSONB       NOT NULL,
    -- {
    --   "currency": "PEN",
    --   "sections": [
    --     {"code": "ASSET_CURRENT", "name": "Activo Corriente", "total": 1234567.89,
    --      "accounts": [{"code": "101", "name": "Caja", "balance": 5000.00}, ...]},
    --     ...
    --   ],
    --   "totals": {"total_assets": 2000000, "total_liabilities": 800000, "equity": 1200000}
    -- }

    comparative_period_id BIGINT    REFERENCES finance.accounting_periods(id),
    comparative_data    JSONB,
    -- datos del período comparativo (año anterior)

    -- Aprobación del estado financiero
    is_audited          BOOLEAN     NOT NULL DEFAULT FALSE,
    auditor_name        VARCHAR(200),
    audit_date          DATE,
    audit_opinion       VARCHAR(30),
    -- unqualified | qualified | adverse | disclaimer

    prepared_by         BIGINT,
    approved_by         BIGINT,
    approved_at         TIMESTAMPTZ,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- Inmutable
);

CREATE INDEX idx_fss_company ON finance.financial_statement_snapshots (company_id);
CREATE INDEX idx_fss_year    ON finance.financial_statement_snapshots (fiscal_year_id);

COMMENT ON TABLE  finance.financial_statement_snapshots IS 'Snapshots inmutables de estados financieros al cierre. Permite comparativos históricos y archivo para auditoría.';
COMMENT ON COLUMN finance.financial_statement_snapshots.statement_data IS 'JSONB con la estructura completa del estado financiero: secciones, cuentas, totales. Inmutable tras la aprobación.';

-- ============================================================
-- 5. FKs DIFERIDAS FINALES
-- ============================================================

-- Cuenta corriente de clientes (journal_entry_lines → sales.customers)
-- No se puede hacer referencia directa por esquemas cruzados
-- Se implementa como FK soft (validación en aplicación) para:
--   finance.journal_entry_lines.customer_id → sales.customers.id
--   finance.journal_entry_lines.supplier_id → logistics.suppliers.id

-- Cuentas bancarias → supplier_payments
ALTER TABLE finance.supplier_payments
    ADD CONSTRAINT fk_spmt_bank_account
    FOREIGN KEY (bank_account_id) REFERENCES finance.bank_accounts(id);

-- expense_accruals
ALTER TABLE finance.expense_accruals
    ADD CONSTRAINT fk_ea_period
    FOREIGN KEY (accounting_period_id) REFERENCES finance.accounting_periods(id);
