-- ============================================================
-- mantrasdb | Módulo Production
-- Archivo: 05_work_orders.sql
-- Descripción: Work Orders (Órdenes de Trabajo) + Time Entries
--
-- Una Work Order (WO) = una operación específica de la ruta
-- dentro de una Orden de Producción.
-- Una OP genera tantas WOs como operaciones tiene la ruta.
--
-- Módulos:
--   1. work_orders           — una WO por operación por OP
--   2. work_order_time_entries — registros de tiempo por operario/máquina
--   3. material_issues        — salidas de material en cada operación
--   4. work_order_outputs     — producción registrada por WO
--
-- Flujo de tiempo:
--   WO creada → queued → setup_in_progress → running → teardown
--   → quality_check → completed / rejected
--
-- Cada WO genera:
--   - Entradas en order_process_log (para trazabilidad)
--   - Movimientos en production_inventory_moves (consumo MP)
--   - Registro de labor (time_entries → costeo de mano de obra)
-- ============================================================

-- ============================================================
-- 1. WORK ORDERS
-- ============================================================
CREATE TABLE production.work_orders (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),
    production_order_id BIGINT      NOT NULL REFERENCES production.production_orders(id),

    work_order_number   VARCHAR(40) NOT NULL,
    -- Formato: OP-2024-00001-OP010 (OP padre + secuencia de operación)

    -- Operación de la ruta que ejecuta esta WO
    routing_operation_id BIGINT     REFERENCES production.routing_operations(id),
    operation_sequence  SMALLINT    NOT NULL,
    operation_name      VARCHAR(200) NOT NULL,

    -- Centro de trabajo y máquina asignados
    work_center_id      BIGINT      NOT NULL REFERENCES production.work_centers(id),
    machine_id          BIGINT      REFERENCES production.machines(id),

    -- Operario(s) asignados
    assigned_operator_id BIGINT,
    -- REFERENCES hr.employees(id) — FK diferida
    assigned_operator_ids BIGINT[],
    -- Para operaciones con múltiples operarios

    -- ── Cantidades ────────────────────────────────────────────
    planned_quantity    NUMERIC(18,6) NOT NULL,
    produced_quantity   NUMERIC(18,6) NOT NULL DEFAULT 0,
    rejected_quantity   NUMERIC(18,6) NOT NULL DEFAULT 0,
    scrap_quantity      NUMERIC(18,6) NOT NULL DEFAULT 0,
    rework_quantity     NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- ── Tiempos planificados (de la ruta) ─────────────────────
    planned_setup_min   NUMERIC(10,2) NOT NULL DEFAULT 0,
    planned_run_min     NUMERIC(10,2) NOT NULL DEFAULT 0,
    planned_teardown_min NUMERIC(10,2) NOT NULL DEFAULT 0,
    planned_wait_min    NUMERIC(10,2) NOT NULL DEFAULT 0,

    -- ── Tiempos reales ────────────────────────────────────────
    -- Timestamps de cada fase del proceso
    queued_at           TIMESTAMPTZ,
    -- Cuando la WO está en cola esperando disponibilidad del centro

    setup_started_at    TIMESTAMPTZ,
    -- Cuando el operario empieza a preparar la máquina

    setup_completed_at  TIMESTAMPTZ,
    -- Cuando termina la preparación y empieza la producción

    production_started_at TIMESTAMPTZ,
    -- Cuando empieza el proceso real de fabricación

    production_paused_at  TIMESTAMPTZ,
    -- Si hay una interrupción

    production_resumed_at TIMESTAMPTZ,
    -- Cuando se reanuda tras una interrupción

    production_completed_at TIMESTAMPTZ,
    -- Cuando termina el proceso de fabricación

    teardown_completed_at TIMESTAMPTZ,
    -- Cuando termina la limpieza/desmontaje

    quality_check_started_at TIMESTAMPTZ,
    quality_check_completed_at TIMESTAMPTZ,

    completed_at        TIMESTAMPTZ,
    -- Timestamp final cuando la WO queda cerrada

    -- ── Tiempos reales calculados ─────────────────────────────
    actual_setup_min    NUMERIC(10,2) GENERATED ALWAYS AS (
        CASE WHEN setup_started_at IS NOT NULL AND setup_completed_at IS NOT NULL
             THEN EXTRACT(EPOCH FROM (setup_completed_at - setup_started_at)) / 60
             ELSE NULL END
    ) STORED,

    actual_run_min      NUMERIC(10,2) GENERATED ALWAYS AS (
        CASE WHEN production_started_at IS NOT NULL AND production_completed_at IS NOT NULL
             THEN EXTRACT(EPOCH FROM (production_completed_at - production_started_at)) / 60
             ELSE NULL END
    ) STORED,

    actual_total_min    NUMERIC(10,2) GENERATED ALWAYS AS (
        CASE WHEN setup_started_at IS NOT NULL AND completed_at IS NOT NULL
             THEN EXTRACT(EPOCH FROM (completed_at - setup_started_at)) / 60
             ELSE NULL END
    ) STORED,

    -- Eficiencia real vs planificada (%)
    time_efficiency_pct NUMERIC(7,2) GENERATED ALWAYS AS (
        CASE WHEN actual_run_min IS NOT NULL AND actual_run_min > 0
                  AND planned_run_min > 0
             THEN ROUND((planned_run_min / actual_run_min) * 100, 2)
             ELSE NULL END
    ) STORED,

    -- ── Estado ───────────────────────────────────────────────
    status              VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending          : creada, esperando inicio
    -- queued           : en cola del centro de trabajo
    -- setup            : preparando máquina
    -- running          : en proceso
    -- interrupted      : parada temporal
    -- teardown         : limpieza/desmontaje
    -- quality_check    : en control de calidad
    -- completed        : terminada exitosamente
    -- rejected         : rechazada (todo a reproceso)
    -- partial          : parcialmente completada
    -- cancelled        : cancelada

    -- ── Calidad ───────────────────────────────────────────────
    quality_result      VARCHAR(20),
    -- pass / fail / conditional

    quality_notes       TEXT,

    -- ── Para refurbishment: grade asignado en esta WO ─────────
    assigned_grade_id   BIGINT      REFERENCES production.refurbishment_grades(id),

    -- ── Costos reales de esta WO ──────────────────────────────
    actual_labor_cost   NUMERIC(18,4) NOT NULL DEFAULT 0,
    actual_machine_cost NUMERIC(18,4) NOT NULL DEFAULT 0,
    actual_material_cost NUMERIC(18,4) NOT NULL DEFAULT 0,

    priority            SMALLINT    NOT NULL DEFAULT 5,
    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX uq_work_order_number
    ON production.work_orders (company_id, work_order_number);
CREATE INDEX idx_wo_order      ON production.work_orders (production_order_id);
CREATE INDEX idx_wo_workcenter ON production.work_orders (work_center_id);
CREATE INDEX idx_wo_status     ON production.work_orders (status);
CREATE INDEX idx_wo_operator   ON production.work_orders (assigned_operator_id);

CREATE TRIGGER trg_wo_updated_at
    BEFORE UPDATE ON production.work_orders
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

-- FK diferida desde production_inventory_moves
ALTER TABLE production.production_inventory_moves
    ADD CONSTRAINT fk_pim_work_order
    FOREIGN KEY (work_order_id)
    REFERENCES production.work_orders(id)
    DEFERRABLE INITIALLY DEFERRED;

COMMENT ON TABLE production.work_orders IS 'Una WO por operación por OP. Mide cada fase del proceso con timestamps precisos: setup, producción, teardown, QC.';

-- ============================================================
-- 2. WORK ORDER TIME ENTRIES
--    Registro granular del tiempo de cada operario y/o máquina.
--    Base para el costeo de mano de obra y el cálculo de OEE.
--
--    Puede haber múltiples time entries por WO si:
--    - Hay múltiples operarios
--    - Hay pausas y reanudaciones
--    - Se trabaja en turnos distintos
-- ============================================================
CREATE TABLE production.work_order_time_entries (
    id                  BIGSERIAL   PRIMARY KEY,
    work_order_id       BIGINT      NOT NULL REFERENCES production.work_orders(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Operario que registra el tiempo
    employee_id         BIGINT,
    -- REFERENCES hr.employees(id) — FK diferida

    -- Máquina usada en este intervalo
    machine_id          BIGINT      REFERENCES production.machines(id),

    -- Tipo de tiempo
    time_type           VARCHAR(20) NOT NULL DEFAULT 'productive',
    -- productive   : tiempo de producción real
    -- setup        : preparación
    -- teardown     : limpieza/desmontaje
    -- rework       : reproceso
    -- quality      : control de calidad
    -- idle         : espera (sin producción)
    -- training     : capacitación durante el turno

    started_at          TIMESTAMPTZ NOT NULL,
    ended_at            TIMESTAMPTZ,
    -- NULL = intervalo aún abierto (operario activo)

    duration_min        NUMERIC(10,2) GENERATED ALWAYS AS (
        CASE WHEN ended_at IS NOT NULL
             THEN EXTRACT(EPOCH FROM (ended_at - started_at)) / 60
             ELSE NULL END
    ) STORED,

    -- Unidades producidas en este intervalo
    quantity_produced   NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- Costo calculado (tasa del empleado × horas)
    labor_rate_per_hour NUMERIC(18,4),
    -- Heredado del perfil de pago del empleado
    labor_cost          NUMERIC(18,4) GENERATED ALWAYS AS (
        CASE WHEN ended_at IS NOT NULL AND labor_rate_per_hour IS NOT NULL
             THEN (EXTRACT(EPOCH FROM (ended_at - started_at)) / 3600) * labor_rate_per_hour
             ELSE NULL END
    ) STORED,

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE: los registros de tiempo no se editan
);

CREATE INDEX idx_te_workorder ON production.work_order_time_entries (work_order_id);
CREATE INDEX idx_te_employee  ON production.work_order_time_entries (employee_id);
CREATE INDEX idx_te_started   ON production.work_order_time_entries (started_at);
CREATE INDEX idx_te_type      ON production.work_order_time_entries (time_type);

COMMENT ON TABLE production.work_order_time_entries IS 'Registro granular de tiempo por operario y máquina. Base para costeo de MO y OEE. Inmutable.';

-- ============================================================
-- 3. MATERIAL ISSUES (Entregas de Material a Producción)
--    Registro de cada entrega de material desde almacén
--    hacia la línea de producción.
--    Vinculado con logistics.inventory_transactions.
-- ============================================================
CREATE TABLE production.material_issues (
    id                  BIGSERIAL   PRIMARY KEY,
    work_order_id       BIGINT      NOT NULL REFERENCES production.work_orders(id),
    production_order_id BIGINT      NOT NULL REFERENCES production.production_orders(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    material_requirement_id BIGINT  REFERENCES production.order_material_requirements(id),

    product_id          BIGINT      NOT NULL REFERENCES logistics.products(id),
    variant_id          BIGINT      REFERENCES logistics.product_variants(id),

    planned_quantity    NUMERIC(18,6) NOT NULL,
    issued_quantity     NUMERIC(18,6) NOT NULL,

    uom_id              BIGINT      REFERENCES logistics.measurement_units(id),

    -- Trazabilidad
    lot_id              BIGINT      REFERENCES logistics.lots(id),
    serial_id           BIGINT      REFERENCES logistics.serial_numbers(id),

    from_location_id    BIGINT      REFERENCES logistics.locations(id),
    to_location_id      BIGINT      REFERENCES logistics.locations(id),

    -- Referencia al movimiento de inventario en Logistics
    inventory_transaction_id BIGINT,
    -- REFERENCES logistics.inventory_transactions(id) — FK diferida

    issued_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    issued_by           BIGINT      REFERENCES hr.system_users(id),

    issue_type          VARCHAR(20) NOT NULL DEFAULT 'planned',
    -- planned     : según plan de materiales
    -- additional  : material adicional no planificado
    -- return      : devolución de material sobrante a almacén (cantidad negativa)
    -- scrap       : material enviado como merma

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);

CREATE INDEX idx_mi_workorder ON production.material_issues (work_order_id);
CREATE INDEX idx_mi_product   ON production.material_issues (product_id);
CREATE INDEX idx_mi_issued    ON production.material_issues (issued_at);

COMMENT ON TABLE production.material_issues IS 'Entregas de material a producción con trazabilidad lote/serie. Vinculado con logistics.inventory_transactions.';

-- ============================================================
-- 4. WORK ORDER OUTPUTS (Producción Registrada)
--    Cada vez que un operario reporta producción terminada
--    en una WO se registra aquí.
--    Al completar el output, se genera el movimiento de inventario.
-- ============================================================
CREATE TABLE production.work_order_outputs (
    id                  BIGSERIAL   PRIMARY KEY,
    work_order_id       BIGINT      NOT NULL REFERENCES production.work_orders(id),
    production_order_id BIGINT      NOT NULL REFERENCES production.production_orders(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    product_id          BIGINT      NOT NULL REFERENCES logistics.products(id),
    variant_id          BIGINT      REFERENCES logistics.product_variants(id),

    output_type         VARCHAR(20) NOT NULL DEFAULT 'good',
    -- good        : producción buena → entra al siguiente proceso o a PT
    -- scrap       : merma → disposición
    -- rework      : requiere reproceso → genera nueva OP de rework
    -- byproduct   : subproducto → inventario de subproductos

    quantity            NUMERIC(18,6) NOT NULL,
    uom_id              BIGINT      REFERENCES logistics.measurement_units(id),

    -- Lote asignado al output
    lot_id              BIGINT      REFERENCES logistics.lots(id),
    serial_id           BIGINT      REFERENCES logistics.serial_numbers(id),

    -- ¿Adónde va este output?
    to_location_id      BIGINT      REFERENCES logistics.locations(id),
    -- Si es el último paso → ubicación PT
    -- Si hay más pasos → almacén intermedio WIP (Work In Progress)

    -- Referencia al movimiento de inventario generado
    inventory_transaction_id BIGINT,
    -- REFERENCES logistics.inventory_transactions(id) — FK diferida

    -- Para refurbishment: grado clasificado en este output
    grade_id            BIGINT      REFERENCES production.refurbishment_grades(id),

    reported_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reported_by         BIGINT      REFERENCES hr.system_users(id),

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);

CREATE INDEX idx_wo_output_order   ON production.work_order_outputs (production_order_id);
CREATE INDEX idx_wo_output_type    ON production.work_order_outputs (output_type);
CREATE INDEX idx_wo_output_product ON production.work_order_outputs (product_id);

COMMENT ON TABLE production.work_order_outputs IS 'Producción reportada por operario por WO. Al registrar output bueno se genera el movimiento a inventory_transactions.';

-- ============================================================
-- VIEW: Performance por operario (mes actual)
-- ============================================================
CREATE VIEW production.operator_performance_view AS
SELECT
    te.employee_id,
    te.company_id,
    DATE_TRUNC('month', te.started_at) AS period_month,
    COUNT(DISTINCT te.work_order_id) AS work_orders_completed,
    ROUND(SUM(te.duration_min) FILTER (WHERE te.time_type = 'productive'), 2) AS productive_min,
    ROUND(SUM(te.duration_min) FILTER (WHERE te.time_type = 'setup'), 2) AS setup_min,
    ROUND(SUM(te.duration_min) FILTER (WHERE te.time_type = 'idle'), 2) AS idle_min,
    ROUND(SUM(te.duration_min), 2) AS total_min,
    SUM(te.quantity_produced) AS total_produced,
    ROUND(SUM(te.labor_cost), 2) AS total_labor_cost,
    -- Eficiencia: tiempo productivo / tiempo total
    ROUND(
        CASE WHEN SUM(te.duration_min) > 0
             THEN (SUM(te.duration_min) FILTER (WHERE te.time_type = 'productive') /
                   SUM(te.duration_min)) * 100
             ELSE NULL END, 2
    ) AS productive_efficiency_pct
FROM production.work_order_time_entries te
WHERE te.ended_at IS NOT NULL
GROUP BY te.employee_id, te.company_id, DATE_TRUNC('month', te.started_at);

COMMENT ON VIEW production.operator_performance_view IS 'Performance por operario: tiempo productivo vs idle vs setup, unidades producidas, eficiencia y costo de MO.';
