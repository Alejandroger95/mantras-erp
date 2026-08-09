-- ============================================================
-- mantrasdb | Módulo Finance
-- Archivo: 02_journal_entries.sql
-- Descripción: Libro Diario — asientos contables en doble partida.
--
-- Regla de oro:
--   SUM(debit_amount) = SUM(credit_amount) por asiento.
--   Los asientos confirmados son INMUTABLES.
--   Para corregir: se crea un asiento de reversión + uno nuevo.
--
-- Tipos de asiento cubiertos:
--   manual          → ingreso manual por contable
--   sales_invoice   → factura de venta (auto desde Sales)
--   supplier_invoice→ factura de compra (auto desde AP)
--   payment         → cobro o pago
--   bank_reconciliation → partidas de conciliación
--   depreciation    → asiento de depreciación mensual (auto)
--   revaluation     → ajuste por diferencia de cambio
--   closing         → asiento de cierre del ejercicio
--   opening         → asiento de apertura del ejercicio
--   accrual         → devengo (gastos diferidos, ingresos diferidos)
--   adjustment      → ajuste de período
--   reversal        → reversión de un asiento anterior
-- ============================================================

-- ============================================================
-- 1. JOURNAL ENTRIES (Cabecera de asiento)
-- ============================================================
CREATE TABLE finance.journal_entries (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- Período contable al que pertenece
    accounting_period_id BIGINT     NOT NULL REFERENCES finance.accounting_periods(id) ON DELETE RESTRICT,

    -- Numeración
    entry_number        VARCHAR(30) NOT NULL,
    -- Formato: "A-2026-000123" (letra del libro + año + secuencial)

    -- Fecha del asiento (no necesariamente = fecha de registro)
    entry_date          DATE        NOT NULL,

    -- Tipo de asiento
    entry_type          VARCHAR(30) NOT NULL DEFAULT 'manual',
    -- manual | sales_invoice | supplier_invoice | payment |
    -- bank_reconciliation | depreciation | revaluation |
    -- closing | opening | accrual | adjustment | reversal

    -- Descripción / glosa
    description         VARCHAR(500) NOT NULL,

    -- Estado del asiento
    status              VARCHAR(20) NOT NULL DEFAULT 'draft',
    -- draft     : borrador, editable
    -- confirmed : confirmado, inmutable (solo reversión)
    -- cancelled : anulado (el asiento de reversión lo cancela)

    -- Moneda base del asiento (puede diferir de la moneda funcional)
    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',
    exchange_rate       NUMERIC(18,8) NOT NULL DEFAULT 1.0,
    -- tasa de cambio a moneda funcional de la empresa

    -- Totales (calculados al confirmar)
    total_debit         NUMERIC(18,2) NOT NULL DEFAULT 0,
    total_credit        NUMERIC(18,2) NOT NULL DEFAULT 0,

    -- Trazabilidad — enlace al documento origen
    source_module       VARCHAR(30),
    -- sales | purchases | treasury | assets | payroll | manual

    source_document_type VARCHAR(50),
    -- 'sales_invoice' | 'supplier_invoice' | 'customer_payment' |
    -- 'bank_statement_line' | 'depreciation_run' | etc.

    source_document_id  BIGINT,
    -- ID del documento en el módulo origen

    -- Reversión
    is_reversal         BOOLEAN     NOT NULL DEFAULT FALSE,
    reversed_entry_id   BIGINT      REFERENCES finance.journal_entries(id),
    -- si este asiento es la reversión de otro

    reversal_of_entry_id BIGINT     REFERENCES finance.journal_entries(id),
    -- si este asiento ha sido revertido

    -- Aprobación (para empresas con workflow de aprobación)
    requires_approval   BOOLEAN     NOT NULL DEFAULT FALSE,
    approved_by         BIGINT,
    approved_at         TIMESTAMPTZ,

    -- Creador
    created_by          BIGINT,
    confirmed_by        BIGINT,
    confirmed_at        TIMESTAMPTZ,

    -- Nota: asientos confirmados NO tienen updated_at (inmutables)
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, entry_number)
);

CREATE INDEX idx_je_company          ON finance.journal_entries (company_id);
CREATE INDEX idx_je_period           ON finance.journal_entries (accounting_period_id);
CREATE INDEX idx_je_date             ON finance.journal_entries (entry_date);
CREATE INDEX idx_je_type             ON finance.journal_entries (entry_type);
CREATE INDEX idx_je_status           ON finance.journal_entries (status);
CREATE INDEX idx_je_source           ON finance.journal_entries (source_module, source_document_type, source_document_id);

COMMENT ON TABLE  finance.journal_entries             IS 'Libro Diario. Cabecera de asientos contables. Los asientos confirmados son inmutables — corrección solo por reversión.';
COMMENT ON COLUMN finance.journal_entries.entry_number IS 'Número secuencial del asiento. Formato recomendado: "A-2026-000001". Inmutable al confirmar.';
COMMENT ON COLUMN finance.journal_entries.total_debit  IS 'Suma de débitos de todas las líneas. Debe = total_credit al confirmar (doble partida).';
COMMENT ON COLUMN finance.journal_entries.source_document_id IS 'ID polimórfico al documento que generó este asiento (facturas, pagos, depreciaciones, etc.).';

-- ============================================================
-- 2. JOURNAL ENTRY LINES (Líneas del asiento — doble partida)
--    Cada asiento tiene ≥ 2 líneas.
--    SUM(debit_amount) = SUM(credit_amount) es obligatorio.
-- ============================================================
CREATE TABLE finance.journal_entry_lines (
    id                  BIGSERIAL   PRIMARY KEY,
    journal_entry_id    BIGINT      NOT NULL REFERENCES finance.journal_entries(id) ON DELETE RESTRICT,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- Cuenta contable
    account_id          BIGINT      NOT NULL REFERENCES finance.accounts(id) ON DELETE RESTRICT,

    -- Número de línea dentro del asiento
    line_number         SMALLINT    NOT NULL DEFAULT 1,

    -- Descripción de la línea
    description         VARCHAR(300),

    -- Importes (solo uno puede ser > 0 por línea)
    debit_amount        NUMERIC(18,2) NOT NULL DEFAULT 0,
    credit_amount       NUMERIC(18,2) NOT NULL DEFAULT 0,

    -- Importe en moneda del asiento (si difiere de la moneda funcional)
    amount_currency     NUMERIC(18,2),
    currency            VARCHAR(10),

    -- Tercero (obligatorio si account.requires_partner = TRUE)
    -- CxC / CxP: enlace al cliente o proveedor
    customer_id         BIGINT,
    -- REFERENCES sales.customers(id) — FK diferida

    supplier_id         BIGINT,
    -- REFERENCES logistics.suppliers(id) — FK diferida

    -- Análisis adicional
    cost_center_id      BIGINT,
    -- REFERENCES finance.cost_centers(id) — FK diferida

    profit_center_id    BIGINT,
    -- REFERENCES finance.profit_centers(id) — FK diferida

    -- Para conciliación automática (apertura / cierre de partidas)
    reconciliation_id   BIGINT,
    -- agrupa líneas que se compensan entre sí (ej: factura + cobro)

    is_reconciled       BOOLEAN     NOT NULL DEFAULT FALSE,
    reconciled_at       TIMESTAMPTZ,

    -- Vínculo a documento específico de la línea
    source_document_type VARCHAR(50),
    source_document_id   BIGINT,

    -- Nota: inmutable al confirmar el asiento padre
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- CHECK: una línea es débito O crédito, no ambos, no ninguno
    CONSTRAINT chk_jel_single_side CHECK (
        (debit_amount > 0 AND credit_amount = 0) OR
        (credit_amount > 0 AND debit_amount = 0)
    ),
    CONSTRAINT chk_jel_positive CHECK (
        debit_amount >= 0 AND credit_amount >= 0
    ),
    UNIQUE (journal_entry_id, line_number)
);

CREATE INDEX idx_jel_entry       ON finance.journal_entry_lines (journal_entry_id);
CREATE INDEX idx_jel_account     ON finance.journal_entry_lines (account_id);
CREATE INDEX idx_jel_company     ON finance.journal_entry_lines (company_id);
CREATE INDEX idx_jel_customer    ON finance.journal_entry_lines (customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX idx_jel_supplier    ON finance.journal_entry_lines (supplier_id) WHERE supplier_id IS NOT NULL;
CREATE INDEX idx_jel_cost_center ON finance.journal_entry_lines (cost_center_id) WHERE cost_center_id IS NOT NULL;
CREATE INDEX idx_jel_reconcile   ON finance.journal_entry_lines (reconciliation_id) WHERE reconciliation_id IS NOT NULL;

COMMENT ON TABLE  finance.journal_entry_lines              IS 'Líneas del asiento. Doble partida: SUM(debit)=SUM(credit) por journal_entry_id. Inmutables al confirmar el asiento.';
COMMENT ON COLUMN finance.journal_entry_lines.debit_amount  IS 'Débito de la línea. Exactamente uno de debit_amount/credit_amount debe ser > 0.';
COMMENT ON COLUMN finance.journal_entry_lines.customer_id   IS 'Tercero cliente para cuentas de CxC (12x). FK diferida a sales.customers.';
COMMENT ON COLUMN finance.journal_entry_lines.supplier_id   IS 'Tercero proveedor para cuentas de CxP (42x). FK diferida a logistics.suppliers.';

-- ============================================================
-- 3. FUNCIÓN PARA CONFIRMAR UN ASIENTO
--    Valida doble partida y cambia status a 'confirmed'.
--    Llamar: SELECT finance.confirm_journal_entry(entry_id);
-- ============================================================
CREATE OR REPLACE FUNCTION finance.confirm_journal_entry(p_entry_id BIGINT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_total_debit  NUMERIC(18,2);
    v_total_credit NUMERIC(18,2);
    v_status       VARCHAR(20);
    v_period_status VARCHAR(20);
BEGIN
    -- Verificar estado actual
    SELECT je.status, ap.status
    INTO v_status, v_period_status
    FROM finance.journal_entries je
    JOIN finance.accounting_periods ap ON ap.id = je.accounting_period_id
    WHERE je.id = p_entry_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Asiento % no encontrado', p_entry_id;
    END IF;

    IF v_status <> 'draft' THEN
        RAISE EXCEPTION 'Solo se pueden confirmar asientos en borrador. Estado actual: %', v_status;
    END IF;

    IF v_period_status NOT IN ('open') THEN
        RAISE EXCEPTION 'El período contable no está abierto. Estado: %', v_period_status;
    END IF;

    -- Calcular totales
    SELECT
        COALESCE(SUM(debit_amount), 0),
        COALESCE(SUM(credit_amount), 0)
    INTO v_total_debit, v_total_credit
    FROM finance.journal_entry_lines
    WHERE journal_entry_id = p_entry_id;

    -- Validar doble partida
    IF v_total_debit = 0 AND v_total_credit = 0 THEN
        RAISE EXCEPTION 'El asiento % no tiene líneas', p_entry_id;
    END IF;

    IF ABS(v_total_debit - v_total_credit) > 0.01 THEN
        RAISE EXCEPTION 'Asiento % desbalanceado: débitos=% créditos=%',
            p_entry_id, v_total_debit, v_total_credit;
    END IF;

    -- Confirmar
    UPDATE finance.journal_entries
    SET
        status        = 'confirmed',
        total_debit   = v_total_debit,
        total_credit  = v_total_credit,
        confirmed_at  = NOW()
    WHERE id = p_entry_id;

END;
$$;

COMMENT ON FUNCTION finance.confirm_journal_entry IS 'Valida doble partida (débitos = créditos) y confirma el asiento, haciéndolo inmutable. Lanza excepción si el período está cerrado o el asiento desbalanceado.';

-- ============================================================
-- 4. FUNCIÓN PARA REVERTIR UN ASIENTO
--    Crea un asiento espejo con débitos y créditos invertidos.
-- ============================================================
CREATE OR REPLACE FUNCTION finance.reverse_journal_entry(
    p_entry_id          BIGINT,
    p_reversal_date     DATE,
    p_period_id         BIGINT,
    p_description       VARCHAR DEFAULT NULL
)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    v_orig              finance.journal_entries%ROWTYPE;
    v_new_entry_id      BIGINT;
    v_new_entry_number  VARCHAR(30);
    v_line              finance.journal_entry_lines%ROWTYPE;
    v_line_num          SMALLINT := 1;
BEGIN
    -- Leer asiento original
    SELECT * INTO v_orig FROM finance.journal_entries WHERE id = p_entry_id;

    IF v_orig.id IS NULL THEN
        RAISE EXCEPTION 'Asiento % no encontrado', p_entry_id;
    END IF;

    IF v_orig.status <> 'confirmed' THEN
        RAISE EXCEPTION 'Solo se pueden revertir asientos confirmados';
    END IF;

    IF v_orig.reversal_of_entry_id IS NOT NULL THEN
        RAISE EXCEPTION 'Este asiento ya fue revertido por el asiento %', v_orig.reversal_of_entry_id;
    END IF;

    -- Número de la reversión
    v_new_entry_number := 'REV-' || p_entry_id::TEXT || '-' || TO_CHAR(NOW(), 'YYYYMMDD');

    -- Crear asiento de reversión
    INSERT INTO finance.journal_entries (
        company_id, accounting_period_id, entry_number, entry_date,
        entry_type, description, status, currency, exchange_rate,
        source_module, source_document_type, source_document_id,
        is_reversal, reversed_entry_id, created_at
    )
    VALUES (
        v_orig.company_id, p_period_id, v_new_entry_number, p_reversal_date,
        'reversal',
        COALESCE(p_description, 'REVERSIÓN de asiento ' || v_orig.entry_number || ': ' || v_orig.description),
        'draft', v_orig.currency, v_orig.exchange_rate,
        v_orig.source_module, v_orig.source_document_type, v_orig.source_document_id,
        TRUE, p_entry_id, NOW()
    )
    RETURNING id INTO v_new_entry_id;

    -- Crear líneas invertidas (débito ↔ crédito)
    FOR v_line IN
        SELECT * FROM finance.journal_entry_lines
        WHERE journal_entry_id = p_entry_id
        ORDER BY line_number
    LOOP
        INSERT INTO finance.journal_entry_lines (
            journal_entry_id, company_id, account_id, line_number,
            description, debit_amount, credit_amount,
            amount_currency, currency,
            customer_id, supplier_id, cost_center_id, profit_center_id,
            source_document_type, source_document_id, created_at
        )
        VALUES (
            v_new_entry_id, v_line.company_id, v_line.account_id, v_line_num,
            v_line.description,
            -- INVERTIR débito y crédito
            v_line.credit_amount, v_line.debit_amount,
            v_line.amount_currency, v_line.currency,
            v_line.customer_id, v_line.supplier_id,
            v_line.cost_center_id, v_line.profit_center_id,
            v_line.source_document_type, v_line.source_document_id,
            NOW()
        );
        v_line_num := v_line_num + 1;
    END LOOP;

    -- Marcar original como revertido
    UPDATE finance.journal_entries
    SET reversal_of_entry_id = v_new_entry_id
    WHERE id = p_entry_id;

    RETURN v_new_entry_id;
END;
$$;

COMMENT ON FUNCTION finance.reverse_journal_entry IS 'Crea un asiento de reversión (espejo con débitos y créditos invertidos) y lo deja en borrador para revisar antes de confirmar.';

-- ============================================================
-- 5. VISTA: SALDO DE CUENTAS
--    Saldo acumulado por cuenta para una empresa.
--    En producción se recomienda materializar esta vista.
-- ============================================================
CREATE OR REPLACE VIEW finance.account_balances AS
SELECT
    jel.company_id,
    jel.account_id,
    a.code          AS account_code,
    a.name          AS account_name,
    at.normal_balance,
    SUM(jel.debit_amount)   AS total_debit,
    SUM(jel.credit_amount)  AS total_credit,
    -- Saldo neto según el saldo normal de la cuenta
    CASE at.normal_balance
        WHEN 'debit'  THEN SUM(jel.debit_amount)  - SUM(jel.credit_amount)
        WHEN 'credit' THEN SUM(jel.credit_amount) - SUM(jel.debit_amount)
    END AS balance
FROM finance.journal_entry_lines jel
JOIN finance.journal_entries je ON je.id = jel.journal_entry_id
    AND je.status = 'confirmed'
JOIN finance.accounts a  ON a.id  = jel.account_id
JOIN finance.account_types at ON at.id = a.account_type_id
GROUP BY
    jel.company_id, jel.account_id,
    a.code, a.name, at.normal_balance;

COMMENT ON VIEW finance.account_balances IS 'Saldo acumulado de cuentas contables (solo asientos confirmados). Para Balance de Comprobación y Estados Financieros.';

-- ============================================================
-- 6. VISTA: LIBRO MAYOR (MAYOR GENERAL)
--    Movimientos cronológicos por cuenta + saldo progresivo.
-- ============================================================
CREATE OR REPLACE VIEW finance.general_ledger AS
SELECT
    jel.company_id,
    jel.account_id,
    a.code              AS account_code,
    a.name              AS account_name,
    je.entry_date,
    je.entry_number,
    je.description      AS entry_description,
    jel.description     AS line_description,
    jel.debit_amount,
    jel.credit_amount,
    SUM(jel.debit_amount - jel.credit_amount)
        OVER (PARTITION BY jel.company_id, jel.account_id
              ORDER BY je.entry_date, je.entry_number, jel.line_number)
        AS running_balance,
    je.entry_type,
    je.status,
    ap.name             AS period_name,
    jel.customer_id,
    jel.supplier_id
FROM finance.journal_entry_lines jel
JOIN finance.journal_entries je ON je.id = jel.journal_entry_id
JOIN finance.accounts a         ON a.id  = jel.account_id
JOIN finance.accounting_periods ap ON ap.id = je.accounting_period_id
WHERE je.status = 'confirmed'
ORDER BY jel.account_id, je.entry_date, je.entry_number, jel.line_number;

COMMENT ON VIEW finance.general_ledger IS 'Libro Mayor General con saldo progresivo por cuenta. Filtra solo asientos confirmados.';

-- ============================================================
-- 7. VISTA: BALANCE DE COMPROBACIÓN
--    Totales de débito y crédito por cuenta en un período.
-- ============================================================
CREATE OR REPLACE VIEW finance.trial_balance AS
SELECT
    jel.company_id,
    ap.fiscal_year_id,
    ap.id               AS accounting_period_id,
    ap.name             AS period_name,
    jel.account_id,
    a.code              AS account_code,
    a.name              AS account_name,
    at.code             AS account_type_code,
    at.financial_statement,
    a.normal_balance,
    SUM(jel.debit_amount)   AS period_debit,
    SUM(jel.credit_amount)  AS period_credit,
    SUM(jel.debit_amount) - SUM(jel.credit_amount) AS net_movement
FROM finance.journal_entry_lines jel
JOIN finance.journal_entries je ON je.id = jel.journal_entry_id
    AND je.status = 'confirmed'
JOIN finance.accounts a  ON a.id  = jel.account_id
JOIN finance.account_types at ON at.id = a.account_type_id
JOIN finance.accounting_periods ap ON ap.id = je.accounting_period_id
GROUP BY
    jel.company_id, ap.fiscal_year_id, ap.id, ap.name,
    jel.account_id, a.code, a.name,
    at.code, at.financial_statement, a.normal_balance;

COMMENT ON VIEW finance.trial_balance IS 'Balance de Comprobación por período contable. Base para el Balance General y Estado de Resultados.';

-- ============================================================
-- 8. FK DIFERIDA: fiscal_years.closing_entry_id
-- ============================================================
ALTER TABLE finance.fiscal_years
    ADD CONSTRAINT fk_fiscal_year_closing_entry
    FOREIGN KEY (closing_entry_id)
    REFERENCES finance.journal_entries(id);
