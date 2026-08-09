-- ============================================================
-- mantrasdb | Módulo Finance
-- Archivo: 07_budgets_cost_centers.sql
-- Descripción: Presupuestos, Centros de Costo y Contabilidad
--              Analítica — para gestión de rendimiento por área.
--
-- Módulos:
--   1. cost_centers         — centros de costo (dpto, área, proyecto)
--   2. profit_centers       — centros de beneficio (unidades de negocio)
--   3. budgets              — presupuestos anuales
--   4. budget_lines         — líneas por cuenta + período
--   5. cost_allocations     — distribución de costos entre centros
--   6. cost_allocation_rules— reglas automáticas de distribución
--   7. internal_orders      — órdenes internas (para proyectos/CAPEX)
--
-- Ejemplo real:
--   Empresa tiene 3 centros de costo: Lima, Arequipa, Callao.
--   Alquiler total: S/ 50,000 → se distribuye 60/25/15 automáticamente.
--   Cada centro tiene su propio P&L.
-- ============================================================

-- ============================================================
-- 1. CENTROS DE COSTO
--    Unidades de agrupación de costos y gastos para análisis.
--    Pueden ser departamentos, plantas, canales, proyectos.
-- ============================================================
CREATE TABLE finance.cost_centers (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- Jerarquía (árbol de centros de costo)
    parent_id           BIGINT      REFERENCES finance.cost_centers(id),

    code                VARCHAR(20) NOT NULL,
    name                VARCHAR(200) NOT NULL,
    description         TEXT,

    -- Tipo de centro
    center_type         VARCHAR(20) NOT NULL DEFAULT 'cost',
    -- cost          : solo acumula costos/gastos
    -- profit        : acumula ingresos y costos (P&L propio)
    -- investment    : centros de inversión (CAPEX)
    -- service       : centros de servicio (se distribuyen a otros)

    -- Responsable
    manager_employee_id BIGINT,
    -- REFERENCES hr.employees(id) — FK diferida

    -- Para centros vinculados a departamentos HR
    hr_department_id    BIGINT,

    -- Para centros vinculados a almacenes
    warehouse_id        BIGINT,
    -- REFERENCES logistics.warehouses(id) — FK diferida

    -- Período de vigencia
    valid_from          DATE,
    valid_to            DATE,

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    -- Nivel en la jerarquía
    level               SMALLINT    NOT NULL DEFAULT 1,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE INDEX idx_cc_company ON finance.cost_centers (company_id);
CREATE INDEX idx_cc_parent  ON finance.cost_centers (parent_id);

CREATE TRIGGER trg_cc_updated_at
    BEFORE UPDATE ON finance.cost_centers
    FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at();

COMMENT ON TABLE  finance.cost_centers IS 'Centros de costo para contabilidad analítica. Permiten conocer el costo real de cada departamento, planta o canal.';

-- ============================================================
-- 2. CENTROS DE BENEFICIO (PROFIT CENTERS)
--    Unidades con P&L propio (ingresos + gastos).
--    Ejemplo: Canal Retail vs Canal Mayorista vs Exportación.
-- ============================================================
CREATE TABLE finance.profit_centers (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    parent_id           BIGINT      REFERENCES finance.profit_centers(id),

    code                VARCHAR(20) NOT NULL,
    name                VARCHAR(200) NOT NULL,
    description         TEXT,

    manager_employee_id BIGINT,
    -- REFERENCES hr.employees(id) — FK diferida

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    level               SMALLINT    NOT NULL DEFAULT 1,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE TRIGGER trg_pc_updated_at
    BEFORE UPDATE ON finance.profit_centers
    FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at();

COMMENT ON TABLE finance.profit_centers IS 'Centros de beneficio: unidades con P&L propio. Ejemplo: Tiendas vs E-commerce vs B2B.';

-- ============================================================
-- 3. PRESUPUESTOS (BUDGETS)
-- ============================================================
CREATE TABLE finance.budgets (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    fiscal_year_id      BIGINT      NOT NULL REFERENCES finance.fiscal_years(id),

    code                VARCHAR(20) NOT NULL,
    name                VARCHAR(200) NOT NULL,
    description         TEXT,

    budget_type         VARCHAR(20) NOT NULL DEFAULT 'operational',
    -- operational   : presupuesto operacional (P&L proyectado)
    -- capital       : presupuesto de capital (CAPEX)
    -- cash_flow     : presupuesto de tesorería
    -- project       : presupuesto de proyecto específico

    -- Escenario presupuestario
    scenario            VARCHAR(20) NOT NULL DEFAULT 'base',
    -- base      : presupuesto base aprobado
    -- optimistic: escenario optimista
    -- pessimistic: escenario pesimista
    -- revised   : revisado durante el año

    status              VARCHAR(20) NOT NULL DEFAULT 'draft',
    -- draft     : en elaboración
    -- submitted : enviado para aprobación
    -- approved  : aprobado
    -- active    : vigente (se usa para control)
    -- revised   : revisado
    -- closed    : ejercicio cerrado

    -- Totales (calculados a partir de las líneas)
    total_revenue_budget    NUMERIC(18,2) NOT NULL DEFAULT 0,
    total_expense_budget    NUMERIC(18,2) NOT NULL DEFAULT 0,
    total_capex_budget      NUMERIC(18,2) NOT NULL DEFAULT 0,

    -- Aprobación
    approved_by         BIGINT,
    approved_at         TIMESTAMPTZ,
    approval_notes      TEXT,

    created_by          BIGINT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, fiscal_year_id, code)
);

CREATE TRIGGER trg_budgets_updated_at
    BEFORE UPDATE ON finance.budgets
    FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at();

COMMENT ON TABLE finance.budgets IS 'Cabecera del presupuesto. Puede haber múltiples escenarios (base, optimista, revisado) por ejercicio.';

-- ============================================================
-- 4. LÍNEAS DE PRESUPUESTO
--    Presupuesto por cuenta contable + período (mes) +
--    centro de costo / centro de beneficio.
-- ============================================================
CREATE TABLE finance.budget_lines (
    id                  BIGSERIAL   PRIMARY KEY,
    budget_id           BIGINT      NOT NULL REFERENCES finance.budgets(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    accounting_period_id BIGINT     NOT NULL REFERENCES finance.accounting_periods(id),
    account_id          BIGINT      NOT NULL REFERENCES finance.accounts(id),

    cost_center_id      BIGINT      REFERENCES finance.cost_centers(id),
    profit_center_id    BIGINT      REFERENCES finance.profit_centers(id),

    -- Importe presupuestado
    budgeted_amount     NUMERIC(18,2) NOT NULL DEFAULT 0,

    -- Importe real (actualizado al ejecutar asientos)
    actual_amount       NUMERIC(18,2) NOT NULL DEFAULT 0,

    -- Variación (desviación)
    variance            NUMERIC(18,2) GENERATED ALWAYS AS
        (actual_amount - budgeted_amount) STORED,
    variance_pct        NUMERIC(8,2) GENERATED ALWAYS AS (
        CASE WHEN budgeted_amount <> 0
            THEN ROUND(((actual_amount - budgeted_amount) / ABS(budgeted_amount)) * 100, 2)
            ELSE NULL
        END
    ) STORED,

    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()

);

CREATE UNIQUE INDEX uq_budget_lines
    ON finance.budget_lines (budget_id, accounting_period_id, account_id,
                             COALESCE(cost_center_id, 0::BIGINT),
                             COALESCE(profit_center_id, 0::BIGINT));

CREATE INDEX idx_budgetline_budget  ON finance.budget_lines (budget_id);
CREATE INDEX idx_budgetline_account ON finance.budget_lines (account_id);
CREATE INDEX idx_budgetline_cc      ON finance.budget_lines (cost_center_id) WHERE cost_center_id IS NOT NULL;

CREATE TRIGGER trg_budgetline_updated_at
    BEFORE UPDATE ON finance.budget_lines
    FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at();

COMMENT ON TABLE  finance.budget_lines IS 'Líneas de presupuesto por cuenta + período + centro de costo. variance = actual - presupuesto (negativo = ahorro para gastos / positivo = cumplimiento para ingresos).';
COMMENT ON COLUMN finance.budget_lines.variance IS 'Desviación: actual - presupuestado. Para gastos: positivo=sobrecosto, negativo=ahorro. Para ingresos: negativo=ventas bajas.';

-- ============================================================
-- 5. VISTA: PRESUPUESTO VS REAL
-- ============================================================
CREATE OR REPLACE VIEW finance.budget_vs_actual AS
SELECT
    bl.company_id,
    bl.budget_id,
    b.name              AS budget_name,
    b.scenario,
    ap.name             AS period_name,
    ap.start_date       AS period_start,
    a.code              AS account_code,
    a.name              AS account_name,
    at.financial_statement,
    cc.name             AS cost_center_name,
    pc.name             AS profit_center_name,
    bl.budgeted_amount,
    bl.actual_amount,
    bl.variance,
    bl.variance_pct,
    CASE
        WHEN bl.budgeted_amount = 0 THEN 'no_budget'
        WHEN ABS(bl.variance_pct) <= 5  THEN 'on_track'
        WHEN ABS(bl.variance_pct) <= 15 THEN 'warning'
        ELSE 'alert'
    END AS status
FROM finance.budget_lines bl
JOIN finance.budgets b              ON b.id = bl.budget_id
JOIN finance.accounting_periods ap  ON ap.id = bl.accounting_period_id
JOIN finance.accounts a             ON a.id = bl.account_id
JOIN finance.account_types at       ON at.id = a.account_type_id
LEFT JOIN finance.cost_centers cc   ON cc.id = bl.cost_center_id
LEFT JOIN finance.profit_centers pc ON pc.id = bl.profit_center_id;

COMMENT ON VIEW finance.budget_vs_actual IS 'Comparativo Presupuesto vs Real por cuenta, período y centro de costo. Incluye semáforo de desviación (on_track/warning/alert).';

-- ============================================================
-- 6. REGLAS DE DISTRIBUCIÓN DE COSTOS
--    Para repartir gastos comunes (alquiler, servicios, etc.)
--    entre centros de costo automáticamente.
-- ============================================================
CREATE TABLE finance.cost_allocation_rules (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    name                VARCHAR(200) NOT NULL,
    description         TEXT,

    -- Cuenta origen (la que se distribuye, ej: 635 Alquileres)
    source_account_id   BIGINT      NOT NULL REFERENCES finance.accounts(id),
    source_cost_center_id BIGINT    REFERENCES finance.cost_centers(id),

    -- Método de distribución
    allocation_method   VARCHAR(20) NOT NULL DEFAULT 'percentage',
    -- percentage     : % fijo por centro (suma = 100%)
    -- headcount      : proporción de empleados por centro
    -- revenue        : proporción de ingresos del mes
    -- equal          : partes iguales entre los centros
    -- manual         : sin regla automática

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    valid_from          DATE,
    valid_to            DATE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Líneas de la regla de distribución
CREATE TABLE finance.cost_allocation_rule_lines (
    id                      BIGSERIAL   PRIMARY KEY,
    cost_allocation_rule_id BIGINT      NOT NULL REFERENCES finance.cost_allocation_rules(id) ON DELETE CASCADE,
    company_id              BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Destino
    target_cost_center_id   BIGINT      NOT NULL REFERENCES finance.cost_centers(id),
    target_account_id       BIGINT      REFERENCES finance.accounts(id),
    -- si NULL, usa la misma cuenta origen

    allocation_percentage   NUMERIC(5,2) NOT NULL,
    -- % del total a asignar a este centro

    UNIQUE (cost_allocation_rule_id, target_cost_center_id)
);

COMMENT ON TABLE finance.cost_allocation_rules IS 'Reglas para distribuir costos comunes entre centros de costo. Ej: alquiler total → 60% Lima, 25% Arequipa, 15% Callao.';

-- ============================================================
-- 7. DISTRIBUCIONES REALIZADAS
--    Registro inmutable de cada distribución ejecutada.
-- ============================================================
CREATE TABLE finance.cost_allocations (
    id                      BIGSERIAL   PRIMARY KEY,
    company_id              BIGINT      NOT NULL REFERENCES hr.companies(id),
    cost_allocation_rule_id BIGINT      REFERENCES finance.cost_allocation_rules(id),
    accounting_period_id    BIGINT      NOT NULL REFERENCES finance.accounting_periods(id),

    allocation_date         DATE        NOT NULL,
    description             VARCHAR(300) NOT NULL,

    -- Origen
    source_account_id       BIGINT      NOT NULL REFERENCES finance.accounts(id),
    source_cost_center_id   BIGINT      REFERENCES finance.cost_centers(id),
    source_amount           NUMERIC(18,2) NOT NULL,

    -- Destino
    target_cost_center_id   BIGINT      NOT NULL REFERENCES finance.cost_centers(id),
    target_account_id       BIGINT      NOT NULL REFERENCES finance.accounts(id),
    allocated_amount        NUMERIC(18,2) NOT NULL,
    allocation_percentage   NUMERIC(5,2) NOT NULL,

    journal_entry_id        BIGINT      REFERENCES finance.journal_entries(id),

    created_by              BIGINT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- Inmutable
);

CREATE INDEX idx_calloc_period ON finance.cost_allocations (accounting_period_id);
CREATE INDEX idx_calloc_source ON finance.cost_allocations (source_cost_center_id);
CREATE INDEX idx_calloc_target ON finance.cost_allocations (target_cost_center_id);

COMMENT ON TABLE finance.cost_allocations IS 'Registro inmutable de distribuciones de costo ejecutadas. Cada fila = un destino de una distribución del período.';

-- ============================================================
-- 8. ÓRDENES INTERNAS (para proyectos y CAPEX)
--    Permite acumular costos e ingresos por orden específica
--    antes de imputarlos a una cuenta contable definitiva.
-- ============================================================
CREATE TABLE finance.internal_orders (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    order_number        VARCHAR(30) NOT NULL,
    name                VARCHAR(200) NOT NULL,
    description         TEXT,

    order_type          VARCHAR(20) NOT NULL DEFAULT 'project',
    -- project      : proyecto con fecha inicio/fin
    -- capex        : inversión de capital
    -- maintenance  : mantenimiento mayor
    -- event        : evento / campaña de marketing
    -- overhead     : distribución de gastos generales

    -- Responsable
    responsible_employee_id BIGINT,

    cost_center_id      BIGINT      REFERENCES finance.cost_centers(id),
    profit_center_id    BIGINT      REFERENCES finance.profit_centers(id),

    start_date          DATE,
    end_date            DATE,
    planned_cost        NUMERIC(18,2) NOT NULL DEFAULT 0,
    actual_cost         NUMERIC(18,2) NOT NULL DEFAULT 0,

    status              VARCHAR(20) NOT NULL DEFAULT 'open',
    -- open       : aceptando cargos
    -- in_progress: en ejecución
    -- completed  : completada, pendiente de liquidación
    -- settled    : liquidada (costos transferidos a cuentas definitivas)
    -- cancelled  : cancelada

    settlement_account_id BIGINT    REFERENCES finance.accounts(id),
    -- cuenta contable donde se imputan los costos al liquidar

    settlement_date     DATE,
    settlement_journal_entry_id BIGINT REFERENCES finance.journal_entries(id),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, order_number)
);

CREATE TRIGGER trg_intorder_updated_at
    BEFORE UPDATE ON finance.internal_orders
    FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at();

COMMENT ON TABLE  finance.internal_orders IS 'Órdenes internas para acumular costos de proyectos, CAPEX o mantenimientos mayores. Se liquidan al finalizar transfiriendo los costos a cuentas contables definitivas.';

-- ============================================================
-- 9. FKs DIFERIDAS (centros de costo en journal_entry_lines)
-- ============================================================
ALTER TABLE finance.journal_entry_lines
    ADD CONSTRAINT fk_jel_cost_center
    FOREIGN KEY (cost_center_id) REFERENCES finance.cost_centers(id);

ALTER TABLE finance.journal_entry_lines
    ADD CONSTRAINT fk_jel_profit_center
    FOREIGN KEY (profit_center_id) REFERENCES finance.profit_centers(id);

ALTER TABLE finance.petty_cash_transactions
    ADD CONSTRAINT fk_pctx_cost_center
    FOREIGN KEY (cost_center_id) REFERENCES finance.cost_centers(id);

ALTER TABLE finance.supplier_invoice_lines
    ADD CONSTRAINT fk_sinvl_cost_center
    FOREIGN KEY (cost_center_id) REFERENCES finance.cost_centers(id);
