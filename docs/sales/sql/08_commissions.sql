-- ============================================================
-- mantrasdb | Módulo Sales
-- Descripción: Vendedores, reglas de comisión y liquidación.
--
-- Flujo:
--   sales_rep → commission_rules → ventas del período
--   → commission_period → commission_calculations → pago
-- ============================================================

-- ============================================================
-- Vendedores (Sales Reps)
-- Extiende hr.employees con configuración de ventas
-- ============================================================
CREATE TABLE sales.sales_reps (
    id                  BIGSERIAL   PRIMARY KEY,
    employee_id         BIGINT      NOT NULL REFERENCES hr.employees(id) ON DELETE RESTRICT,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    code                VARCHAR(30) NOT NULL,
    -- código del vendedor: "VEN-001"

    -- Territorio / cartera asignada
    territory           VARCHAR(200),
    -- "Lima Norte", "Provincias", "Key Accounts"

    -- Cuota de ventas mensual
    monthly_quota       NUMERIC(18,4) NOT NULL DEFAULT 0,
    quota_currency      VARCHAR(10)   NOT NULL DEFAULT 'PEN',

    -- Comisión base
    base_commission_pct NUMERIC(5,2) NOT NULL DEFAULT 0,
    -- % de comisión sobre las ventas (puede ser sobreescrito por reglas)

    -- Estado
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (employee_id, company_id),
    UNIQUE (company_id, code)
);

CREATE INDEX idx_sales_reps_employee ON sales.sales_reps (employee_id);
CREATE INDEX idx_sales_reps_company  ON sales.sales_reps (company_id);

CREATE TRIGGER trg_sales_reps_updated_at
    BEFORE UPDATE ON sales.sales_reps
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.sales_reps                    IS 'Vendedores vinculados a hr.employees. Tienen cuota, territorio y % de comisión base.';
COMMENT ON COLUMN sales.sales_reps.monthly_quota      IS 'Cuota de ventas mensual. Se usa para calcular el % de cumplimiento y bonos por tramo.';

-- ============================================================
-- Ahora que sales_reps existe, agregamos las FKs diferidas
-- ============================================================
ALTER TABLE sales.customers
    ADD CONSTRAINT fk_customers_sales_rep
    FOREIGN KEY (sales_rep_id) REFERENCES sales.sales_reps(id)
    ON DELETE SET NULL;

ALTER TABLE sales.quotations
    ADD CONSTRAINT fk_quotations_sales_rep
    FOREIGN KEY (sales_rep_id) REFERENCES sales.sales_reps(id)
    ON DELETE SET NULL;

ALTER TABLE sales.sales_orders
    ADD CONSTRAINT fk_sales_orders_sales_rep
    FOREIGN KEY (sales_rep_id) REFERENCES sales.sales_reps(id)
    ON DELETE SET NULL;

-- ============================================================
-- Reglas de comisión
-- ============================================================
CREATE TABLE sales.commission_rules (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    name                VARCHAR(200) NOT NULL,
    description         TEXT,

    -- Aplicación (puede ser a un rep específico o a todos)
    sales_rep_id        BIGINT      REFERENCES sales.sales_reps(id),
    -- NULL = aplica a todos

    -- Criterio de producto
    product_id          BIGINT      REFERENCES logistics.products(id),
    category_id         BIGINT      REFERENCES logistics.product_categories(id),
    customer_group_id   BIGINT      REFERENCES sales.customer_groups(id),
    -- NULL en todos = aplica a cualquier venta

    -- Tramos de comisión por % de cumplimiento de cuota
    -- Si no hay tramos, se usa commission_pct directo
    commission_pct      NUMERIC(5,2) NOT NULL DEFAULT 0,

    -- Tramos (JSONB para flexibilidad)
    tiers               JSONB,
    -- Ej: [{"min_quota_pct": 0, "max_quota_pct": 79, "commission_pct": 2},
    --      {"min_quota_pct": 80,"max_quota_pct": 99, "commission_pct": 3},
    --      {"min_quota_pct": 100,"max_quota_pct": null,"commission_pct": 5}]

    -- Base de cálculo
    base_type           VARCHAR(20) NOT NULL DEFAULT 'net_sales',
    -- net_sales = sobre ventas netas (sin IGV)
    -- gross_margin = sobre margen bruto
    -- collected = solo sobre lo cobrado (evita comisión en incobrables)

    -- Vigencia
    valid_from          DATE,
    valid_to            DATE,

    priority            INTEGER     NOT NULL DEFAULT 100,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_commission_rules_company ON sales.commission_rules (company_id);
CREATE INDEX idx_commission_rules_rep     ON sales.commission_rules (sales_rep_id);

CREATE TRIGGER trg_commission_rules_updated_at
    BEFORE UPDATE ON sales.commission_rules
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.commission_rules           IS 'Reglas de comisión por vendedor, producto y tramos de cuota.';
COMMENT ON COLUMN sales.commission_rules.tiers     IS 'JSON de tramos: [{min_quota_pct, max_quota_pct, commission_pct}]. Comisión escalonada por cumplimiento.';
COMMENT ON COLUMN sales.commission_rules.base_type IS 'collected = comisión solo sobre lo cobrado. Evita premiar ventas que luego no se cobran.';

-- ============================================================
-- Períodos de comisión (mensual / trimestral)
-- ============================================================
CREATE TABLE sales.commission_periods (
    id              BIGSERIAL   PRIMARY KEY,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    period_name     VARCHAR(100) NOT NULL,
    -- "Agosto 2026", "Q3 2026"
    period_type     VARCHAR(20) NOT NULL DEFAULT 'monthly',
    -- monthly | quarterly | annual
    start_date      DATE        NOT NULL,
    end_date        DATE        NOT NULL,

    status          VARCHAR(20) NOT NULL DEFAULT 'open',
    -- open | calculating | approved | paid | closed

    approved_by     BIGINT,
    approved_at     TIMESTAMPTZ,
    paid_at         TIMESTAMPTZ,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, start_date, period_type)
);

CREATE TRIGGER trg_commission_periods_updated_at
    BEFORE UPDATE ON sales.commission_periods
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE sales.commission_periods IS 'Períodos de liquidación de comisiones. El sistema calcula las comisiones al cerrar el período.';

-- ============================================================
-- Cálculo de comisión por vendedor / período
-- ============================================================
CREATE TABLE sales.commission_calculations (
    id                  BIGSERIAL   PRIMARY KEY,
    period_id           BIGINT      NOT NULL REFERENCES sales.commission_periods(id),
    sales_rep_id        BIGINT      NOT NULL REFERENCES sales.sales_reps(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- Ventas del período
    total_sales         NUMERIC(18,4) NOT NULL DEFAULT 0,
    total_collected     NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- lo realmente cobrado (base si base_type='collected')
    quota               NUMERIC(18,4) NOT NULL DEFAULT 0,
    quota_achievement_pct NUMERIC(5,2) NOT NULL DEFAULT 0,
    -- % de cumplimiento de cuota

    -- Comisión calculada
    commission_base     NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- monto sobre el cual se calcula la comisión
    commission_pct      NUMERIC(5,2)  NOT NULL DEFAULT 0,
    -- % aplicado (según la regla / tramo)
    commission_amount   NUMERIC(18,4) NOT NULL DEFAULT 0,

    -- Ajustes manuales
    adjustment_amount   NUMERIC(18,4) NOT NULL DEFAULT 0,
    adjustment_notes    TEXT,

    total_commission    NUMERIC(18,4)
        GENERATED ALWAYS AS (commission_amount + adjustment_amount) STORED,

    status              VARCHAR(20) NOT NULL DEFAULT 'draft',
    -- draft | approved | paid

    approved_by         BIGINT,
    approved_at         TIMESTAMPTZ,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (period_id, sales_rep_id)
);

CREATE INDEX idx_commission_calc_period ON sales.commission_calculations (period_id);
CREATE INDEX idx_commission_calc_rep    ON sales.commission_calculations (sales_rep_id);

CREATE TRIGGER trg_commission_calc_updated_at
    BEFORE UPDATE ON sales.commission_calculations
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.commission_calculations                    IS 'Comisión calculada por vendedor y período. Incluye ajustes manuales del área comercial.';
COMMENT ON COLUMN sales.commission_calculations.total_commission   IS 'Calculado: comisión + ajuste. Monto final a pagar al vendedor.';
