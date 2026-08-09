-- ============================================================
-- mantrasdb | Módulo Production
-- Archivo: 07_costing.sql
-- Descripción: Costeo de Producción
--
-- Módulos:
--   1. cost_versions          — versiones de costos estándar
--   2. standard_costs         — costo estándar por producto
--   3. product_cost_breakdown — desglose de costo por componente
--   4. production_order_costs — costos reales por OP
--   5. cost_variances         — variaciones (estándar vs real)
--   6. wip_balances           — Work In Progress (balance WIP)
--   7. sunat_merma_declarations — Declaraciones de merma SUNAT
--                                  Art. 37 LIR (Perú)
--
-- Filosofía de costeo:
--   Costo estándar = MP + MO + GIF (Gastos Indirectos de Fab.)
--   Variación = Real - Estándar
--
-- Funciona para CUALQUIER industria:
--   🏭 Manufactura  : MP + MOD + CIF (conversión)
--   👗 Textil       : tela + confección + corte (merma tela)
--   💎 Joyería      : metal + piedras + mano obra joyero
--   🍎 Alimentos    : insumos + merma cocción + mano obra
--   🍕 Restaurante  : receta (cost of food) + labor cocina
--   📱 Electrónica  : componentes + mano obra + prueba
-- ============================================================

-- ============================================================
-- 1. COST VERSIONS (Versiones de Costos)
--    Permite tener múltiples versiones de costo estándar:
--    presupuesto, real del año anterior, negociado, etc.
-- ============================================================
CREATE TABLE production.cost_versions (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    code                VARCHAR(20) NOT NULL,
    name                VARCHAR(100) NOT NULL,
    description         TEXT,

    version_type        VARCHAR(20) NOT NULL DEFAULT 'standard',
    -- standard    : costo estándar oficial del período
    -- budget      : presupuesto / plan anual
    -- simulation  : simulación para análisis
    -- actual      : costo real promedio del período

    fiscal_year         SMALLINT    NOT NULL,
    -- Año fiscal al que aplica esta versión

    valid_from          DATE        NOT NULL,
    valid_to            DATE,

    -- ¿Es la versión activa?
    is_active           BOOLEAN     NOT NULL DEFAULT FALSE,
    -- Solo UNA versión puede ser activa por company/fiscal_year

    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',

    approved_by         BIGINT      REFERENCES hr.system_users(id),
    approved_at         TIMESTAMPTZ,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code, fiscal_year)
);

CREATE TRIGGER trg_costver_updated_at
    BEFORE UPDATE ON production.cost_versions
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

-- ============================================================
-- 2. STANDARD COSTS (Costos Estándar por Producto)
--    Costo total estándar por producto en una versión y período.
-- ============================================================
CREATE TABLE production.standard_costs (
    id                  BIGSERIAL   PRIMARY KEY,
    cost_version_id     BIGINT      NOT NULL REFERENCES production.cost_versions(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),
    product_id          BIGINT      NOT NULL REFERENCES logistics.products(id),
    variant_id          BIGINT      REFERENCES logistics.product_variants(id),
    uom_id              BIGINT      REFERENCES logistics.measurement_units(id),

    -- ── Componentes del costo estándar ────────────────────────
    -- MP: Materias Primas
    std_material_cost   NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- MOD: Mano de Obra Directa
    std_labor_cost      NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- GIF / CIF: Gastos Indirectos de Fabricación
    std_overhead_cost   NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- Subcontratación (si aplica)
    std_subcontract_cost NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- Costo de merma incluido (normal)
    std_scrap_cost      NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- Costo total = suma de los anteriores (GENERATED)
    std_total_cost      NUMERIC(18,6) GENERATED ALWAYS AS (
        std_material_cost + std_labor_cost + std_overhead_cost +
        std_subcontract_cost + std_scrap_cost
    ) STORED,

    -- Para joyería: costo del metal precioso separado
    std_precious_metal_cost NUMERIC(18,6) NOT NULL DEFAULT 0,

    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',

    -- Última vez que se calculó (auto o manual)
    last_calculated_at  TIMESTAMPTZ,
    calculation_method  VARCHAR(20) NOT NULL DEFAULT 'rollup',
    -- rollup  : explosión de BOM multinivel
    -- manual  : ingresado directamente
    -- average : promedio de compras recientes

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX uq_std_costs
    ON production.standard_costs (cost_version_id, product_id, COALESCE(variant_id, 0::BIGINT));

CREATE TRIGGER trg_stdcost_updated_at
    BEFORE UPDATE ON production.standard_costs
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

COMMENT ON TABLE production.standard_costs IS 'Costo estándar por producto y versión: MP + MOD + GIF + subcontratación + merma. Calculado por explosión de BOM (rollup) o ingresado manualmente.';

-- ============================================================
-- 3. PRODUCT COST BREAKDOWN (Desglose de Costo)
--    Detalla qué componente o operación aporta cuánto al costo.
--    Generado automáticamente por el proceso de rollup de BOM.
-- ============================================================
CREATE TABLE production.product_cost_breakdown (
    id                  BIGSERIAL   PRIMARY KEY,
    standard_cost_id    BIGINT      NOT NULL REFERENCES production.standard_costs(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- ¿Este renglón es de material o de operación?
    breakdown_type      VARCHAR(20) NOT NULL DEFAULT 'material',
    -- material    : componente de BOM
    -- labor       : operación de la ruta (MO)
    -- overhead    : GIF asignado por tasa
    -- subcontract : operación subcontratada

    -- Para material:
    bom_line_id         BIGINT      REFERENCES production.bom_lines(id),
    component_product_id BIGINT     REFERENCES logistics.products(id),

    -- Para operación:
    routing_operation_id BIGINT     REFERENCES production.routing_operations(id),

    level_in_bom        SMALLINT    NOT NULL DEFAULT 1,
    -- 1 = nivel directo, 2 = subnivel, etc.

    -- Cantidad por unidad de producto terminado
    quantity_per_unit   NUMERIC(18,6) NOT NULL,
    uom_id              BIGINT      REFERENCES logistics.measurement_units(id),

    -- Costo unitario del componente/operación
    unit_cost           NUMERIC(18,6) NOT NULL,
    -- Para material: precio estándar de compra
    -- Para labor: tasa horaria del empleado × tiempo op

    -- Porcentaje de scrap incluido
    scrap_pct           NUMERIC(7,4) NOT NULL DEFAULT 0,

    -- Costo total aportado a 1 unidad de PT
    total_cost_contribution NUMERIC(18,6) GENERATED ALWAYS AS (
        quantity_per_unit * unit_cost * (1 + scrap_pct / 100)
    ) STORED,

    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE: se regenera en cada recálculo
);

CREATE INDEX idx_pcb_stdcost    ON production.product_cost_breakdown (standard_cost_id);
CREATE INDEX idx_pcb_component  ON production.product_cost_breakdown (component_product_id);

COMMENT ON TABLE production.product_cost_breakdown IS 'Desglose nivel a nivel del costo estándar: qué componente/operación aporta cuánto. Generado por rollup de BOM.';

-- ============================================================
-- 4. PRODUCTION ORDER COSTS (Costos Reales por OP)
--    Acumula los costos reales incurridos en cada OP.
--    Se actualiza con cada material_issue y time_entry.
-- ============================================================
CREATE TABLE production.production_order_costs (
    id                  BIGSERIAL   PRIMARY KEY,
    production_order_id BIGINT      NOT NULL REFERENCES production.production_orders(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    cost_version_id     BIGINT      REFERENCES production.cost_versions(id),
    -- Versión estándar para comparar

    -- ── Costos estándar (planificados) ────────────────────────
    std_material_cost   NUMERIC(18,6) NOT NULL DEFAULT 0,
    std_labor_cost      NUMERIC(18,6) NOT NULL DEFAULT 0,
    std_overhead_cost   NUMERIC(18,6) NOT NULL DEFAULT 0,
    std_subcontract_cost NUMERIC(18,6) NOT NULL DEFAULT 0,
    std_scrap_cost      NUMERIC(18,6) NOT NULL DEFAULT 0,
    std_total_cost      NUMERIC(18,6) GENERATED ALWAYS AS (
        std_material_cost + std_labor_cost + std_overhead_cost +
        std_subcontract_cost + std_scrap_cost
    ) STORED,

    -- ── Costos reales (acumulados) ────────────────────────────
    actual_material_cost NUMERIC(18,6) NOT NULL DEFAULT 0,
    actual_labor_cost   NUMERIC(18,6) NOT NULL DEFAULT 0,
    actual_overhead_cost NUMERIC(18,6) NOT NULL DEFAULT 0,
    actual_subcontract_cost NUMERIC(18,6) NOT NULL DEFAULT 0,
    actual_scrap_cost   NUMERIC(18,6) NOT NULL DEFAULT 0,
    actual_total_cost   NUMERIC(18,6) GENERATED ALWAYS AS (
        actual_material_cost + actual_labor_cost + actual_overhead_cost +
        actual_subcontract_cost + actual_scrap_cost
    ) STORED,

    -- ── Variaciones (real - estándar) ─────────────────────────
    material_variance   NUMERIC(18,6) GENERATED ALWAYS AS (actual_material_cost - std_material_cost) STORED,
    labor_variance      NUMERIC(18,6) GENERATED ALWAYS AS (actual_labor_cost - std_labor_cost) STORED,
    overhead_variance   NUMERIC(18,6) GENERATED ALWAYS AS (actual_overhead_cost - std_overhead_cost) STORED,
    total_variance      NUMERIC(18,6) GENERATED ALWAYS AS (
        (actual_material_cost + actual_labor_cost + actual_overhead_cost + actual_subcontract_cost + actual_scrap_cost) -
        (std_material_cost + std_labor_cost + std_overhead_cost + std_subcontract_cost + std_scrap_cost)
    ) STORED,

    -- ── Eficiencia ────────────────────────────────────────────
    -- Porcentaje: (estándar / real) * 100
    cost_efficiency_pct NUMERIC(7,2) GENERATED ALWAYS AS (
        CASE WHEN (actual_material_cost + actual_labor_cost + actual_overhead_cost +
                   actual_subcontract_cost + actual_scrap_cost) > 0
             THEN ROUND(
                 (std_material_cost + std_labor_cost + std_overhead_cost +
                  std_subcontract_cost + std_scrap_cost) /
                 (actual_material_cost + actual_labor_cost + actual_overhead_cost +
                  actual_subcontract_cost + actual_scrap_cost) * 100, 2)
             ELSE NULL END
    ) STORED,

    -- ── Cantidades para costo unitario ─────────────────────────
    planned_quantity    NUMERIC(18,6) NOT NULL,
    actual_good_quantity NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- Costo unitario real (sobre unidades buenas)
    actual_unit_cost    NUMERIC(18,6) GENERATED ALWAYS AS (
        CASE WHEN actual_good_quantity > 0
             THEN ROUND(
                 (actual_material_cost + actual_labor_cost + actual_overhead_cost +
                  actual_subcontract_cost + actual_scrap_cost) / actual_good_quantity, 6)
             ELSE NULL END
    ) STORED,

    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',

    -- Estado del cierre de costos de la OP
    cost_status         VARCHAR(20) NOT NULL DEFAULT 'open',
    -- open     : OP en proceso, costos parciales
    -- pending  : OP completada, pendiente cierre contable
    -- closed   : costos cerrados y contabilizados

    closed_at           TIMESTAMPTZ,
    closed_by           BIGINT      REFERENCES hr.system_users(id),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (production_order_id)
);

CREATE TRIGGER trg_pocosts_updated_at
    BEFORE UPDATE ON production.production_order_costs
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

COMMENT ON TABLE production.production_order_costs IS 'Costos acumulados por OP: estándar vs real, variaciones y eficiencia. Base para el cierre contable de producción.';

-- ============================================================
-- 5. COST VARIANCES (Registro de Variaciones)
--    Detalle de cada variación detectada al cerrar la OP.
--    Una variación puede ser de precio, cantidad o eficiencia.
-- ============================================================
CREATE TABLE production.cost_variances (
    id                  BIGSERIAL   PRIMARY KEY,
    production_order_id BIGINT      NOT NULL REFERENCES production.production_orders(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    variance_type       VARCHAR(30) NOT NULL,
    -- material_price      : precio de compra > precio estándar
    -- material_quantity   : se usó más material del planificado
    -- labor_rate          : tasa de MO > tasa estándar
    -- labor_efficiency    : más horas que las estándar
    -- overhead_volume     : volumen < capacidad normal
    -- overhead_spending   : gasto GIF > presupuestado
    -- scrap_variance      : merma real > merma estándar

    -- Componente involucrado
    product_id          BIGINT      REFERENCES logistics.products(id),
    routing_operation_id BIGINT     REFERENCES production.routing_operations(id),

    -- Valores
    std_value           NUMERIC(18,6) NOT NULL,
    actual_value        NUMERIC(18,6) NOT NULL,
    variance_amount     NUMERIC(18,6) GENERATED ALWAYS AS (actual_value - std_value) STORED,

    -- Positivo = desfavorable (costó más), Negativo = favorable
    is_favorable        BOOLEAN     GENERATED ALWAYS AS (actual_value <= std_value) STORED,

    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',

    -- ¿Se contabilizó?
    journal_entry_id    BIGINT,
    -- REFERENCES finance.journal_entries(id) — FK diferida

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);

CREATE INDEX idx_cv_order ON production.cost_variances (production_order_id);
CREATE INDEX idx_cv_type  ON production.cost_variances (variance_type);

COMMENT ON TABLE production.cost_variances IS 'Variaciones de costo al cierre de OP: precio, cantidad, eficiencia MO, volumen GIF, merma. Se contabilizan en finance.journal_entries.';

-- ============================================================
-- 6. WIP BALANCES (Work In Progress)
--    Balance mensual del inventario en proceso.
--    Permite el balance contable: MP → WIP → PT
-- ============================================================
CREATE TABLE production.wip_balances (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),
    cost_version_id     BIGINT      REFERENCES production.cost_versions(id),

    -- Período contable
    period_year         SMALLINT    NOT NULL,
    period_month        SMALLINT    NOT NULL,

    -- OP que tiene saldo WIP abierto
    production_order_id BIGINT      NOT NULL REFERENCES production.production_orders(id),

    product_id          BIGINT      NOT NULL REFERENCES logistics.products(id),

    -- Saldo inicial del período
    opening_material    NUMERIC(18,6) NOT NULL DEFAULT 0,
    opening_labor       NUMERIC(18,6) NOT NULL DEFAULT 0,
    opening_overhead    NUMERIC(18,6) NOT NULL DEFAULT 0,
    opening_total       NUMERIC(18,6) GENERATED ALWAYS AS (
        opening_material + opening_labor + opening_overhead
    ) STORED,

    -- Cargos del período (materiales consumidos + MO aplicada + GIF)
    charges_material    NUMERIC(18,6) NOT NULL DEFAULT 0,
    charges_labor       NUMERIC(18,6) NOT NULL DEFAULT 0,
    charges_overhead    NUMERIC(18,6) NOT NULL DEFAULT 0,
    charges_total       NUMERIC(18,6) GENERATED ALWAYS AS (
        charges_material + charges_labor + charges_overhead
    ) STORED,

    -- Transferidos a PT (completados)
    transfers_to_fg     NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- Saldo final = apertura + cargos - transferidos
    closing_total       NUMERIC(18,6) GENERATED ALWAYS AS (
        (opening_material + opening_labor + opening_overhead) +
        (charges_material + charges_labor + charges_overhead) -
        transfers_to_fg
    ) STORED,

    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, period_year, period_month, production_order_id)
);

CREATE TRIGGER trg_wip_updated_at
    BEFORE UPDATE ON production.wip_balances
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

COMMENT ON TABLE production.wip_balances IS 'Balance WIP por OP por período: apertura + cargos (MP+MO+GIF) - transferidos a PT. Base para el cierre contable mensual.';

-- ============================================================
-- 7. SUNAT MERMA DECLARATIONS (Perú — Art. 37 LIR)
--    Declaración formal de mermas para deducibilidad tributaria.
--
--    SUNAT distingue:
--      - Merma: pérdida física (peso, volumen, cantidad) en el
--        proceso de producción. Se deduce con INFORME TÉCNICO
--        de un profesional independiente habilitado.
--      - Desmedro: pérdida de calidad irrecuperable (destrucción
--        de inventario obsoleto/dañado). Se deduce con
--        presencia de notario y comunicación previa a SUNAT.
-- ============================================================
CREATE TABLE production.sunat_merma_declarations (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    declaration_number  VARCHAR(30) NOT NULL,

    declaration_type    VARCHAR(20) NOT NULL DEFAULT 'merma',
    -- merma    : pérdida física cuantitativa (Art. 37 LIR, inciso f)
    -- desmedro : pérdida cualitativa (necesita destrucción + notario)

    -- Período fiscal que cubre
    fiscal_year         SMALLINT    NOT NULL,
    fiscal_period_start DATE        NOT NULL,
    fiscal_period_end   DATE        NOT NULL,

    -- Productos afectados
    product_id          BIGINT      REFERENCES logistics.products(id),
    production_order_id BIGINT      REFERENCES production.production_orders(id),

    -- Cantidad declarada
    declared_quantity   NUMERIC(18,6) NOT NULL,
    uom_id              BIGINT      REFERENCES logistics.measurement_units(id),

    -- Porcentaje sobre el total procesado (merma %)
    declared_merma_pct  NUMERIC(7,4) NOT NULL,

    -- Valor de la merma para deducción
    declared_value      NUMERIC(18,4) NOT NULL,
    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',

    -- Informe técnico (para merma)
    technical_report_number VARCHAR(100),
    -- Número del informe del profesional independiente

    technical_expert_name VARCHAR(200),
    -- Nombre del perito / profesional que emitió el informe

    technical_expert_cip  VARCHAR(30),
    -- Colegiatura del profesional (CIP para ingenieros, etc.)

    technical_report_date DATE,

    -- Para desmedros: datos de destrucción
    destruction_date    DATE,
    notary_name         VARCHAR(200),
    notary_office       VARCHAR(200),
    sunat_notification_date DATE,
    -- Debe notificarse a SUNAT con ≥ 6 días hábiles antes

    -- Estado de la declaración
    status              VARCHAR(20) NOT NULL DEFAULT 'draft',
    -- draft     : borrador
    -- submitted : presentada a SUNAT o registrada internamente
    -- accepted  : aceptada / deducida en la DJ anual

    -- Asiento contable generado
    journal_entry_id    BIGINT,
    -- REFERENCES finance.journal_entries(id) — FK diferida

    notes               TEXT,

    prepared_by         BIGINT      REFERENCES hr.system_users(id),
    approved_by         BIGINT      REFERENCES hr.system_users(id),
    approved_at         TIMESTAMPTZ,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, declaration_number)
);

CREATE TRIGGER trg_sunat_merma_updated_at
    BEFORE UPDATE ON production.sunat_merma_declarations
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

-- Vínculo entre la declaración y los registros de merma
CREATE TABLE production.sunat_merma_declaration_lines (
    id                      BIGSERIAL   PRIMARY KEY,
    declaration_id          BIGINT      NOT NULL REFERENCES production.sunat_merma_declarations(id) ON DELETE CASCADE,
    merma_record_id         BIGINT      NOT NULL REFERENCES production.merma_records(id),
    company_id              BIGINT      NOT NULL REFERENCES hr.companies(id),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (declaration_id, merma_record_id)
);

COMMENT ON TABLE production.sunat_merma_declarations IS 'Declaraciones de merma/desmedro para deducción Art. 37 LIR (Perú). Merma requiere informe técnico de profesional habilitado. Desmedro requiere destrucción ante notario y comunicación previa a SUNAT.';

-- ============================================================
-- VIEW: Dashboard de costos por OP (resumen ejecutivo)
-- ============================================================
CREATE VIEW production.order_cost_dashboard AS
SELECT
    poc.production_order_id,
    poc.company_id,
    poc.planned_quantity,
    poc.actual_good_quantity,
    -- Eficiencia de producción (unidades buenas vs planificadas)
    CASE WHEN poc.planned_quantity > 0
         THEN ROUND(poc.actual_good_quantity / poc.planned_quantity * 100, 2)
         ELSE NULL END AS production_efficiency_pct,
    -- Costos estándar
    poc.std_total_cost,
    -- Costos reales
    poc.actual_total_cost,
    -- Variación total (+ = desfavorable, - = favorable)
    poc.total_variance,
    -- Eficiencia de costo
    poc.cost_efficiency_pct,
    -- Costo real por unidad buena
    poc.actual_unit_cost,
    -- Mermas registradas
    m.total_merma_cost,
    m.costo_merma_deducible,
    m.costo_merma_no_deducible,
    m.avg_merma_pct
FROM production.production_order_costs poc
LEFT JOIN production.merma_by_order m ON m.production_order_id = poc.production_order_id;

COMMENT ON VIEW production.order_cost_dashboard IS 'Dashboard ejecutivo de costos por OP: estándar vs real, variación, eficiencia y mermas (deducible SUNAT vs no deducible).';
