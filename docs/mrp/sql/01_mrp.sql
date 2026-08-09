-- ============================================================
-- mantrasdb | Módulo MRP (Material Requirements Planning)
-- Archivo: 01_mrp.sql
-- Descripción: Planificación de requerimientos de materiales
--
-- Tablas:
--   1. mrp_parameters       — Parámetros de planificación por producto
--   2. demand_forecasts     — Cabeceras de pronóstico de demanda
--   3. demand_forecast_lines— Líneas del pronóstico por producto/período
--   4. mrp_runs             — Ejecución del cálculo MRP
--   5. planned_orders       — Órdenes planificadas (producción o compra)
--   6. planned_order_requirements — Requerimientos de materiales
--
-- Vistas:
--   mrp.coverage_view          — Cobertura de stock por producto
--   mrp.purchase_suggestions_view — Qué comprar y cuándo
-- ============================================================

CREATE SCHEMA IF NOT EXISTS mrp;

CREATE OR REPLACE FUNCTION mrp.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

-- ============================================================
-- 1. MRP_PARAMETERS — Parámetros de planificación por producto
-- ============================================================
CREATE TABLE mrp.mrp_parameters (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),
    product_id          BIGINT      NOT NULL REFERENCES logistics.products(id),

    -- Método de reorden
    reorder_method      VARCHAR(20) NOT NULL DEFAULT 'reorder_point',
    -- reorder_point : reponer cuando stock <= reorder_point_qty
    -- min_max       : mantener stock entre min_qty y max_qty
    -- lot_for_lot   : pedir exactamente lo que se necesita
    -- fixed_period  : pedir cada N días

    -- Niveles de stock
    reorder_point_qty   NUMERIC(18,6) NOT NULL DEFAULT 0,
    -- Punto de reorden: cuando el stock disponible cae por debajo de este valor, se genera una orden planificada

    min_stock_qty       NUMERIC(18,6) NOT NULL DEFAULT 0,
    max_stock_qty       NUMERIC(18,6),
    -- NULL = sin límite superior

    -- Cantidad de pedido
    min_order_qty       NUMERIC(18,6) NOT NULL DEFAULT 1,
    -- Cantidad mínima de pedido (MOQ del proveedor)

    multiple_qty        NUMERIC(18,6) NOT NULL DEFAULT 1,
    -- La cantidad pedida debe ser múltiplo de este valor

    -- Lead time
    lead_time_days      SMALLINT     NOT NULL DEFAULT 0,
    -- Días desde que se coloca la orden hasta que llega el material

    -- Para producción propia
    produce_delay_days  SMALLINT     NOT NULL DEFAULT 0,
    -- Días de producción

    -- ¿Se produce o se compra?
    supply_method       VARCHAR(20)  NOT NULL DEFAULT 'buy',
    -- buy / manufacture / buy_or_manufacture

    -- Proveedor preferido
    preferred_supplier_id BIGINT     REFERENCES logistics.suppliers(id),

    is_active           BOOLEAN      NOT NULL DEFAULT TRUE,

    created_by          BIGINT       REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX uq_mrp_param ON mrp.mrp_parameters (company_id, product_id);
CREATE TRIGGER trg_mrp_param_upd BEFORE UPDATE ON mrp.mrp_parameters
    FOR EACH ROW EXECUTE FUNCTION mrp.set_updated_at();
COMMENT ON TABLE mrp.mrp_parameters IS
'Parámetros de planificación por producto: método de reorden, punto de reorden, lead time, MOQ y método de suministro (compra/producción).';

-- ============================================================
-- 2. DEMAND_FORECASTS — Pronósticos de demanda (cabecera)
-- ============================================================
CREATE TABLE mrp.demand_forecasts (
    id              BIGSERIAL   PRIMARY KEY,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id),

    name            VARCHAR(200) NOT NULL,
    -- Ej: "Pronóstico Q1 2026", "Temporada Navidad 2026"

    forecast_type   VARCHAR(20)  NOT NULL DEFAULT 'manual',
    -- manual / sales_history / seasonal / ai_generated

    date_from       DATE        NOT NULL,
    date_to         DATE        NOT NULL,

    status          VARCHAR(20)  NOT NULL DEFAULT 'draft',
    -- draft / active / archived

    notes           TEXT,

    created_by      BIGINT      REFERENCES hr.system_users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TRIGGER trg_df_upd BEFORE UPDATE ON mrp.demand_forecasts
    FOR EACH ROW EXECUTE FUNCTION mrp.set_updated_at();

-- ============================================================
-- 3. DEMAND_FORECAST_LINES — Líneas del pronóstico
-- ============================================================
CREATE TABLE mrp.demand_forecast_lines (
    id              BIGSERIAL   PRIMARY KEY,
    forecast_id     BIGINT      NOT NULL REFERENCES mrp.demand_forecasts(id) ON DELETE CASCADE,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id),

    product_id      BIGINT      NOT NULL REFERENCES logistics.products(id),

    -- Período de la línea
    period_start    DATE        NOT NULL,
    period_end      DATE        NOT NULL,

    -- Cantidad pronosticada
    forecast_qty    NUMERIC(18,6) NOT NULL DEFAULT 0,
    uom_id          BIGINT      REFERENCES logistics.measurement_units(id),

    -- Cantidad real (para comparar pronóstico vs real)
    actual_qty      NUMERIC(18,6),

    -- Precisión del pronóstico (calculada al cerrar el período)
    accuracy_pct    NUMERIC(7,2) GENERATED ALWAYS AS (
        CASE WHEN actual_qty IS NOT NULL AND forecast_qty > 0
             THEN ROUND(
                 (1 - ABS(actual_qty - forecast_qty) / NULLIF(forecast_qty, 0)) * 100
             , 2)
             ELSE NULL END
    ) STORED,

    notes           TEXT,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);
CREATE INDEX idx_dfl_forecast ON mrp.demand_forecast_lines (forecast_id);
CREATE INDEX idx_dfl_product  ON mrp.demand_forecast_lines (product_id, period_start);

-- ============================================================
-- 4. MRP_RUNS — Ejecución del cálculo MRP
-- ============================================================
CREATE TABLE mrp.mrp_runs (
    id              BIGSERIAL   PRIMARY KEY,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id),

    name            VARCHAR(200) NOT NULL,
    -- Ej: "MRP Semana 12 - 2026"

    run_date        DATE        NOT NULL DEFAULT CURRENT_DATE,

    -- Horizonte de planificación
    planning_horizon_days SMALLINT NOT NULL DEFAULT 90,

    -- Pronóstico usado
    forecast_id     BIGINT      REFERENCES mrp.demand_forecasts(id),

    -- Estado
    status          VARCHAR(20) NOT NULL DEFAULT 'draft',
    -- draft / running / completed / error

    -- Estadísticas del run
    products_analyzed INTEGER   NOT NULL DEFAULT 0,
    planned_orders_created INTEGER NOT NULL DEFAULT 0,

    run_started_at  TIMESTAMPTZ,
    run_finished_at TIMESTAMPTZ,

    error_message   TEXT,

    notes           TEXT,

    created_by      BIGINT      REFERENCES hr.system_users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TRIGGER trg_run_upd BEFORE UPDATE ON mrp.mrp_runs
    FOR EACH ROW EXECUTE FUNCTION mrp.set_updated_at();
COMMENT ON TABLE mrp.mrp_runs IS
'Ejecución del cálculo MRP. Analiza stock, demanda y parámetros para generar órdenes planificadas de compra o producción.';

-- ============================================================
-- 5. PLANNED_ORDERS — Órdenes planificadas
--    Resultado del MRP: qué comprar o producir, cuándo.
-- ============================================================
CREATE TABLE mrp.planned_orders (
    id              BIGSERIAL   PRIMARY KEY,
    run_id          BIGINT      NOT NULL REFERENCES mrp.mrp_runs(id) ON DELETE CASCADE,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id),

    product_id      BIGINT      NOT NULL REFERENCES logistics.products(id),

    -- Tipo de orden sugerida
    order_type      VARCHAR(20) NOT NULL DEFAULT 'purchase',
    -- purchase     : generar orden de compra
    -- manufacture  : generar orden de producción

    qty_planned     NUMERIC(18,6) NOT NULL,
    uom_id          BIGINT      REFERENCES logistics.measurement_units(id),

    -- Fecha en que se necesita el material
    date_required   DATE        NOT NULL,

    -- Fecha en que se debe lanzar la orden (date_required - lead_time)
    date_planned_start DATE     NOT NULL,

    -- Estado de la orden planificada
    status          VARCHAR(20) NOT NULL DEFAULT 'suggested',
    -- suggested    : generada por el MRP, pendiente de confirmación
    -- confirmed    : aprobada por el planificador
    -- converted    : convertida a orden de compra o producción real
    -- cancelled    : descartada

    -- Referencia a la orden real generada
    purchase_order_id BIGINT    REFERENCES logistics.purchase_orders(id),
    production_order_id BIGINT,
    -- REFERENCES production.production_orders(id) — FK lógica

    -- Proveedor sugerido (heredado de mrp_parameters)
    supplier_id     BIGINT      REFERENCES logistics.suppliers(id),

    -- Motivo de la necesidad
    demand_source   VARCHAR(30),
    -- forecast / sales_order / safety_stock / min_stock

    notes           TEXT,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_po_run     ON mrp.planned_orders (run_id);
CREATE INDEX idx_po_product ON mrp.planned_orders (product_id, date_required);
CREATE INDEX idx_po_status  ON mrp.planned_orders (status);
CREATE TRIGGER trg_po_upd BEFORE UPDATE ON mrp.planned_orders
    FOR EACH ROW EXECUTE FUNCTION mrp.set_updated_at();
COMMENT ON TABLE mrp.planned_orders IS
'Órdenes planificadas generadas por el MRP. Pueden ser de compra o producción. El planificador las confirma y convierte en órdenes reales.';

-- ============================================================
-- 6. PLANNED_ORDER_REQUIREMENTS — Requerimientos de materiales
--    Para órdenes de tipo 'manufacture': desglosa los
--    componentes del BOM que se necesitan.
-- ============================================================
CREATE TABLE mrp.planned_order_requirements (
    id                  BIGSERIAL   PRIMARY KEY,
    planned_order_id    BIGINT      NOT NULL REFERENCES mrp.planned_orders(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Componente requerido
    component_id        BIGINT      NOT NULL REFERENCES logistics.products(id),

    qty_required        NUMERIC(18,6) NOT NULL,
    uom_id              BIGINT      REFERENCES logistics.measurement_units(id),

    -- Stock disponible al momento del cálculo
    qty_available       NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- Neto a cubrir
    qty_to_supply       NUMERIC(18,6) GENERATED ALWAYS AS (
        GREATEST(qty_required - qty_available, 0)
    ) STORED,

    -- ¿Hay stock suficiente?
    is_covered          BOOLEAN     GENERATED ALWAYS AS (
        qty_available >= qty_required
    ) STORED,

    -- Si no está cubierto: ¿ya hay una planned_order para este componente?
    covered_by_planned_order_id BIGINT REFERENCES mrp.planned_orders(id),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);
CREATE INDEX idx_por_order     ON mrp.planned_order_requirements (planned_order_id);
CREATE INDEX idx_por_component ON mrp.planned_order_requirements (component_id);

-- ============================================================
-- VISTA 1: Cobertura de stock por producto
-- ============================================================
CREATE OR REPLACE VIEW mrp.coverage_view AS
SELECT
    mp.company_id,
    p.id                                            AS product_id,
    p.name                                          AS product_name,
    p.sku,

    -- Stock actual (del ledger de inventario)
    COALESCE(inv.qty_on_hand, 0)                    AS qty_on_hand,
    COALESCE(inv.qty_reserved, 0)                   AS qty_reserved,
    COALESCE(inv.qty_on_hand - inv.qty_reserved, 0) AS qty_available,

    -- Parámetros
    mp.reorder_point_qty,
    mp.min_stock_qty,
    mp.max_stock_qty,
    mp.lead_time_days,
    mp.supply_method,
    mp.reorder_method,

    -- ¿Está por debajo del punto de reorden?
    CASE
        WHEN COALESCE(inv.qty_on_hand - inv.qty_reserved, 0) <= mp.reorder_point_qty
        THEN TRUE ELSE FALSE
    END                                             AS needs_replenishment,

    -- Días de cobertura estimados (con demanda promedio del último mes)
    CASE WHEN COALESCE(recent_demand.avg_daily, 0) > 0
         THEN ROUND(
             COALESCE(inv.qty_on_hand - inv.qty_reserved, 0) /
             recent_demand.avg_daily
         )
         ELSE NULL
    END                                             AS coverage_days,

    mp.preferred_supplier_id

FROM mrp.mrp_parameters mp
INNER JOIN logistics.products p ON p.id = mp.product_id

-- Stock actual agregado por producto
LEFT JOIN (
    SELECT product_id,
           SUM(quantity) FILTER (WHERE transaction_type NOT IN ('reserved'))   AS qty_on_hand,
           SUM(quantity) FILTER (WHERE transaction_type = 'reserved')          AS qty_reserved
    FROM logistics.inventory_transactions
    GROUP BY product_id
) inv ON inv.product_id = mp.product_id

-- Demanda diaria promedio del último mes
LEFT JOIN (
    SELECT product_id,
           SUM(ABS(quantity)) / 30.0 AS avg_daily
    FROM logistics.inventory_transactions
    WHERE transaction_type IN ('sale', 'issue', 'consumption')
      AND created_at >= NOW() - INTERVAL '30 days'
    GROUP BY product_id
) recent_demand ON recent_demand.product_id = mp.product_id

WHERE mp.is_active = TRUE
ORDER BY needs_replenishment DESC, coverage_days ASC NULLS FIRST;

COMMENT ON VIEW mrp.coverage_view IS
'Cobertura de stock por producto: cantidad disponible, punto de reorden, días de cobertura y señal de reposición necesaria.';

-- ============================================================
-- VISTA 2: Sugerencias de compra
-- ============================================================
CREATE OR REPLACE VIEW mrp.purchase_suggestions_view AS
SELECT
    po.company_id,
    po.id                                           AS planned_order_id,
    p.id                                            AS product_id,
    p.name                                          AS product_name,
    p.sku,
    po.qty_planned,
    po.date_planned_start                           AS order_by_date,
    po.date_required,
    s.name                                          AS suggested_supplier,
    po.demand_source,
    po.status,
    mr.name                                         AS mrp_run_name,
    mr.run_date
FROM mrp.planned_orders     po
INNER JOIN mrp.mrp_runs      mr ON mr.id = po.run_id
INNER JOIN logistics.products p  ON p.id  = po.product_id
LEFT  JOIN logistics.suppliers s  ON s.id  = po.supplier_id
WHERE po.order_type = 'purchase'
  AND po.status IN ('suggested', 'confirmed')
ORDER BY po.date_required ASC;

COMMENT ON VIEW mrp.purchase_suggestions_view IS
'Sugerencias de compra del MRP: producto, cantidad, fecha límite de compra, proveedor sugerido y urgencia.';
