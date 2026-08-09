-- ============================================================
-- mantrasdb | Módulo Payroll Engine
-- Archivo: 01_payroll_engine.sql
-- Descripción: Motor de cálculo de nómina
--
-- Extiende el módulo HR (que ya tiene payroll_concepts,
-- payroll_periods y payroll_details básicos) con un motor
-- de reglas de cálculo reutilizable y liquidaciones formales.
--
-- Tablas:
--   1. payroll_rule_categories — Categorías (remuneraciones, descuentos, aportes)
--   2. payroll_rules           — Reglas con fórmulas de cálculo
--   3. payroll_structures      — Estructura salarial por tipo de contrato
--   4. payroll_structure_rules — Qué reglas incluye cada estructura
--   5. payroll_runs            — Ejecución de nómina para un período
--   6. payroll_run_lines       — Valor calculado por empleado por regla
--   7. payroll_slips           — Boleta de pago por empleado
--   8. payroll_slip_lines      — Líneas de la boleta
--
-- Vistas:
--   payroll.run_summary_view   — Resumen por ejecución
--   payroll.slip_detail_view   — Detalle de boleta por empleado
-- ============================================================

CREATE SCHEMA IF NOT EXISTS payroll;

CREATE OR REPLACE FUNCTION payroll.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

-- ============================================================
-- 1. PAYROLL_RULE_CATEGORIES
-- ============================================================
CREATE TABLE payroll.payroll_rule_categories (
    id              BIGSERIAL   PRIMARY KEY,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id),
    name            VARCHAR(100) NOT NULL,
    code            VARCHAR(20)  NOT NULL,
    -- Ej: REMU (remuneraciones), DESC (descuentos), APOR (aportes empleador)
    category_type   VARCHAR(20)  NOT NULL DEFAULT 'earning',
    -- earning / deduction / employer_contribution / informational
    sort_order      SMALLINT     NOT NULL DEFAULT 1,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX uq_prc_code ON payroll.payroll_rule_categories (company_id, code);
CREATE TRIGGER trg_prc_upd BEFORE UPDATE ON payroll.payroll_rule_categories
    FOR EACH ROW EXECUTE FUNCTION payroll.set_updated_at();

-- ============================================================
-- 2. PAYROLL_RULES — Reglas de cálculo
-- ============================================================
CREATE TABLE payroll.payroll_rules (
    id              BIGSERIAL   PRIMARY KEY,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id),
    category_id     BIGINT      NOT NULL REFERENCES payroll.payroll_rule_categories(id),

    code            VARCHAR(30)  NOT NULL,
    -- Ej: BASIC, BONO_PUNTUALIDAD, AFP_COMISION, ESSALUD, ONP

    name            VARCHAR(200) NOT NULL,
    -- Ej: "Remuneración Básica", "AFP – Comisión", "ESSALUD (empleador)"

    -- Tipo de cálculo
    compute_type    VARCHAR(20)  NOT NULL DEFAULT 'fixed',
    -- fixed        : monto fijo definido en el contrato
    -- pct_of_rule  : porcentaje de otra regla
    -- pct_of_basic : porcentaje del salario básico
    -- formula      : fórmula libre (Python/Jinja evaluada por la app)
    -- manual       : ingresado manualmente por RRHH

    -- Para pct_of_rule y pct_of_basic
    rate_pct        NUMERIC(7,4),
    -- Ej: 9.00 para ESSALUD (9%), 13.00 para ONP, 10.00 para AFP obligatorio

    -- Regla base para pct_of_rule
    base_rule_id    BIGINT      REFERENCES payroll.payroll_rules(id),

    -- Para formula
    formula_code    TEXT,
    -- Código evaluado por la aplicación. Variables disponibles:
    -- basic, total_earnings, period_days, worked_days, etc.

    -- ¿Afecta al neto del empleado?
    affects_net     BOOLEAN     NOT NULL DEFAULT TRUE,
    -- FALSE para aportes patronales (ESSALUD) que no afectan al empleado

    -- ¿Es aporte del empleador?
    is_employer     BOOLEAN     NOT NULL DEFAULT FALSE,

    -- Requisito mínimo de UIT/RMV (para reglas condicionales)
    applies_if_salary_above NUMERIC(18,4),
    -- NULL = siempre aplica

    -- ¿Solo para ciertos tipos de contrato?
    applies_to_contract_type BIGINT REFERENCES hr.contract_types(id),
    -- NULL = todos los contratos

    sort_order      SMALLINT    NOT NULL DEFAULT 1,
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,

    created_by      BIGINT      REFERENCES hr.system_users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX uq_pr_code ON payroll.payroll_rules (company_id, code);
CREATE TRIGGER trg_pr_upd BEFORE UPDATE ON payroll.payroll_rules
    FOR EACH ROW EXECUTE FUNCTION payroll.set_updated_at();
COMMENT ON TABLE payroll.payroll_rules IS
'Reglas de cálculo de nómina. Soporta monto fijo, % del básico, % de otra regla y fórmula libre. Cubre Perú: ESSALUD, AFP, ONP, 5ta categoría.';

-- ============================================================
-- 3. PAYROLL_STRUCTURES — Estructura salarial
--    Agrupa las reglas que aplican a un tipo de empleado.
--    Ej: "Estructura Planilla Peru" / "Estructura Recibo por Honorarios"
-- ============================================================
CREATE TABLE payroll.payroll_structures (
    id              BIGSERIAL   PRIMARY KEY,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id),
    name            VARCHAR(200) NOT NULL,
    code            VARCHAR(30)  NOT NULL,
    description     TEXT,
    is_default      BOOLEAN     NOT NULL DEFAULT FALSE,
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_by      BIGINT      REFERENCES hr.system_users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX uq_ps_code ON payroll.payroll_structures (company_id, code);
CREATE TRIGGER trg_ps_upd BEFORE UPDATE ON payroll.payroll_structures
    FOR EACH ROW EXECUTE FUNCTION payroll.set_updated_at();

-- ============================================================
-- 4. PAYROLL_STRUCTURE_RULES — Reglas por estructura
-- ============================================================
CREATE TABLE payroll.payroll_structure_rules (
    id              BIGSERIAL   PRIMARY KEY,
    structure_id    BIGINT      NOT NULL REFERENCES payroll.payroll_structures(id) ON DELETE CASCADE,
    rule_id         BIGINT      NOT NULL REFERENCES payroll.payroll_rules(id),
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id),
    sort_order      SMALLINT    NOT NULL DEFAULT 1,
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);
CREATE UNIQUE INDEX uq_psr ON payroll.payroll_structure_rules (structure_id, rule_id);

-- ============================================================
-- 5. PAYROLL_RUNS — Ejecución de nómina para un período
-- ============================================================
CREATE TABLE payroll.payroll_runs (
    id              BIGSERIAL   PRIMARY KEY,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Período de nómina (referencia al módulo HR)
    period_id       BIGINT      NOT NULL REFERENCES hr.payroll_periods(id),

    structure_id    BIGINT      NOT NULL REFERENCES payroll.payroll_structures(id),

    name            VARCHAR(200) NOT NULL,
    -- Ej: "Planilla Enero 2026"

    -- Estado
    status          VARCHAR(20) NOT NULL DEFAULT 'draft',
    -- draft / computed / validated / paid / cancelled

    -- Fechas
    date_from       DATE        NOT NULL,
    date_to         DATE        NOT NULL,
    payment_date    DATE,

    -- Totales (calculados al correr la nómina)
    total_gross     NUMERIC(18,4) NOT NULL DEFAULT 0,
    total_deductions NUMERIC(18,4) NOT NULL DEFAULT 0,
    total_net       NUMERIC(18,4) NOT NULL DEFAULT 0,
    total_employer_contributions NUMERIC(18,4) NOT NULL DEFAULT 0,

    employee_count  INTEGER     NOT NULL DEFAULT 0,

    computed_at     TIMESTAMPTZ,
    validated_at    TIMESTAMPTZ,
    paid_at         TIMESTAMPTZ,

    computed_by     BIGINT      REFERENCES hr.system_users(id),
    validated_by    BIGINT      REFERENCES hr.system_users(id),

    notes           TEXT,

    created_by      BIGINT      REFERENCES hr.system_users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_run_period   ON payroll.payroll_runs (period_id);
CREATE INDEX idx_run_company  ON payroll.payroll_runs (company_id, status);
CREATE TRIGGER trg_run_upd BEFORE UPDATE ON payroll.payroll_runs
    FOR EACH ROW EXECUTE FUNCTION payroll.set_updated_at();
COMMENT ON TABLE payroll.payroll_runs IS
'Ejecución de nómina para un período. Contiene los totales y pasa por draft → computed → validated → paid.';

-- ============================================================
-- 6. PAYROLL_RUN_LINES — Valor calculado por empleado por regla
-- ============================================================
CREATE TABLE payroll.payroll_run_lines (
    id              BIGSERIAL   PRIMARY KEY,
    run_id          BIGINT      NOT NULL REFERENCES payroll.payroll_runs(id) ON DELETE CASCADE,
    employee_id     BIGINT      NOT NULL REFERENCES hr.employees(id),
    rule_id         BIGINT      NOT NULL REFERENCES payroll.payroll_rules(id),
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Valor calculado
    amount          NUMERIC(18,4) NOT NULL DEFAULT 0,

    -- Valor de la base usada en el cálculo (para auditoría)
    base_amount     NUMERIC(18,4),
    rate_pct_used   NUMERIC(7,4),

    -- Notas del cálculo
    computation_notes TEXT,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE: si se recalcula, se eliminan y recrean
);
CREATE INDEX idx_rl_run      ON payroll.payroll_run_lines (run_id, employee_id);
CREATE INDEX idx_rl_employee ON payroll.payroll_run_lines (employee_id);

-- ============================================================
-- 7. PAYROLL_SLIPS — Boleta de pago por empleado
-- ============================================================
CREATE TABLE payroll.payroll_slips (
    id              BIGSERIAL   PRIMARY KEY,
    run_id          BIGINT      NOT NULL REFERENCES payroll.payroll_runs(id),
    employee_id     BIGINT      NOT NULL REFERENCES hr.employees(id),
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Totales de la boleta
    total_gross     NUMERIC(18,4) NOT NULL DEFAULT 0,
    total_deductions NUMERIC(18,4) NOT NULL DEFAULT 0,
    total_net       NUMERIC(18,4) NOT NULL DEFAULT 0,
    total_employer_contributions NUMERIC(18,4) NOT NULL DEFAULT 0,

    -- Días trabajados
    days_worked     NUMERIC(5,2) NOT NULL DEFAULT 30,
    days_absent     NUMERIC(5,2) NOT NULL DEFAULT 0,

    -- Estado
    status          VARCHAR(20) NOT NULL DEFAULT 'draft',
    -- draft / computed / validated / paid

    paid_at         TIMESTAMPTZ,
    payment_method  VARCHAR(30),
    -- cash / bank_transfer / check

    bank_account    VARCHAR(50),
    -- Número de cuenta del empleado

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX uq_slip ON payroll.payroll_slips (run_id, employee_id);
CREATE TRIGGER trg_slip_upd BEFORE UPDATE ON payroll.payroll_slips
    FOR EACH ROW EXECUTE FUNCTION payroll.set_updated_at();
COMMENT ON TABLE payroll.payroll_slips IS
'Boleta de pago individual. Una por empleado por run. Contiene totales y estado de pago.';

-- ============================================================
-- 8. PAYROLL_SLIP_LINES — Líneas de la boleta
-- ============================================================
CREATE TABLE payroll.payroll_slip_lines (
    id              BIGSERIAL   PRIMARY KEY,
    slip_id         BIGINT      NOT NULL REFERENCES payroll.payroll_slips(id) ON DELETE CASCADE,
    rule_id         BIGINT      NOT NULL REFERENCES payroll.payroll_rules(id),
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Copia de datos de la regla (snapshot para historial)
    rule_code       VARCHAR(30)  NOT NULL,
    rule_name       VARCHAR(200) NOT NULL,
    category_type   VARCHAR(20)  NOT NULL,
    -- earning / deduction / employer_contribution / informational

    amount          NUMERIC(18,4) NOT NULL DEFAULT 0,
    sort_order      SMALLINT     NOT NULL DEFAULT 1,

    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
    -- INMUTABLE
);
CREATE INDEX idx_sl_slip ON payroll.payroll_slip_lines (slip_id, sort_order);

-- ============================================================
-- VISTA 1: Resumen por ejecución de nómina
-- ============================================================
CREATE OR REPLACE VIEW payroll.run_summary_view AS
SELECT
    r.id                                            AS run_id,
    r.company_id,
    r.name                                          AS run_name,
    r.status,
    r.date_from,
    r.date_to,
    r.payment_date,
    r.employee_count,
    r.total_gross,
    r.total_deductions,
    r.total_net,
    r.total_employer_contributions,

    -- Costo total empresa = neto + aportes patronales
    r.total_gross + r.total_employer_contributions  AS total_employer_cost,

    ps.name                                         AS structure_name,
    pp.name                                         AS period_name

FROM payroll.payroll_runs       r
INNER JOIN payroll.payroll_structures ps ON ps.id = r.structure_id
INNER JOIN hr.payroll_periods         pp ON pp.id = r.period_id
ORDER BY r.date_from DESC;

COMMENT ON VIEW payroll.run_summary_view IS
'Resumen de cada ejecución de nómina: empleados, bruto, descuentos, neto y costo total empresa.';

-- ============================================================
-- VISTA 2: Detalle de boleta por empleado
-- ============================================================
CREATE OR REPLACE VIEW payroll.slip_detail_view AS
SELECT
    sl.id                                           AS slip_id,
    sl.run_id,
    sl.company_id,

    -- Empleado
    e.id                                            AS employee_id,
    per.first_name || ' ' || per.last_name          AS employee_name,
    d.name                                          AS department,
    pos.name                                        AS position_name,

    -- Período
    r.date_from,
    r.date_to,
    r.name                                          AS run_name,

    -- Días
    sl.days_worked,
    sl.days_absent,

    -- Totales
    sl.total_gross,
    sl.total_deductions,
    sl.total_net,
    sl.total_employer_contributions,

    -- Pago
    sl.status,
    sl.paid_at,
    sl.payment_method

FROM payroll.payroll_slips      sl
INNER JOIN payroll.payroll_runs  r   ON r.id   = sl.run_id
INNER JOIN hr.employees          e   ON e.id   = sl.employee_id
INNER JOIN hr.persons            per ON per.id = e.person_id
LEFT  JOIN hr.departments        d   ON d.id   = e.department_id
LEFT  JOIN hr.positions          pos ON pos.id = e.position_id
ORDER BY r.date_from DESC, per.last_name;

COMMENT ON VIEW payroll.slip_detail_view IS
'Detalle de boleta: empleado, período, días trabajados, totales y estado de pago.';
