-- ============================================================
-- mantrasdb | Módulo Production
-- Archivo: 04_production_orders.sql
-- Descripción: Órdenes de Producción (OP)
--
-- Una OP es la instrucción de fabricar X unidades de un producto.
-- Flujo completo:
--   draft → confirmed → material_reserved → in_progress
--   → quality_check → completed → closed
--
-- Integración con Logistics:
--   - Al confirmar: reserva de materia prima en inventario
--   - Al completar: ingreso de PT al almacén de productos terminados
--     vía logistics.inventory_transactions (tipo: production_output)
--   - Material consumido: salida vía inventory_transactions (tipo: production_consumption)
--
-- Tipos soportados:
--   🏭 manufacturing   : fabricación estándar
--   ♻️  disassembly    : desarmado / logística inversa
--   🔧 refurbishment   : reacondicionamiento
--   🔁 rework          : reproceso de rechazos
--   📦 subcontract     : maquila
--
-- Trazabilidad por proceso:
--   Cada OP genera N work_orders (uno por operación de la ruta).
--   Cada work_order tiene started_at + completed_at → tiempo real medido.
-- ============================================================

-- ============================================================
-- 1. PRODUCTION ORDER STATUSES (catálogo)
-- ============================================================
CREATE TABLE production.order_statuses (
    id          BIGSERIAL PRIMARY KEY,
    code        VARCHAR(30) NOT NULL UNIQUE,
    name        VARCHAR(100) NOT NULL,
    sequence    SMALLINT NOT NULL,
    is_final    BOOLEAN NOT NULL DEFAULT FALSE,
    color_hex   VARCHAR(7)
);

INSERT INTO production.order_statuses (code, name, sequence, is_final, color_hex) VALUES
('draft',             'Borrador',                    10, FALSE, '#9E9E9E'),
('confirmed',         'Confirmada',                  20, FALSE, '#2196F3'),
('material_reserved', 'Materiales Reservados',       30, FALSE, '#03A9F4'),
('in_progress',       'En Proceso',                  40, FALSE, '#FF9800'),
('quality_check',     'Control de Calidad',          50, FALSE, '#9C27B0'),
('completed',         'Completada',                  60, FALSE, '#4CAF50'),
('closed',            'Cerrada',                     70, TRUE,  '#607D8B'),
('cancelled',         'Cancelada',                   80, TRUE,  '#F44336'),
('on_hold',           'En Espera',                   90, FALSE, '#FFC107');

-- ============================================================
-- 2. PRODUCTION ORDERS (Cabecera)
-- ============================================================
CREATE TABLE production.production_orders (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Número de orden (autogenerado)
    order_number        VARCHAR(30) NOT NULL,
    -- Formato: OP-2024-00001 (manufacturing), DA-2024-00001 (disassembly), RF-2024-00001 (refurb)

    order_type          VARCHAR(20) NOT NULL DEFAULT 'manufacturing',
    -- manufacturing   : fabricación estándar
    -- disassembly     : desarmado (logística inversa / trade-in)
    -- refurbishment   : reacondicionamiento de retorno
    -- rework          : reproceso de unidades rechazadas
    -- subcontract     : maquila

    status_code         VARCHAR(30) NOT NULL DEFAULT 'draft'
                        REFERENCES production.order_statuses(code),

    -- ── Producto a fabricar ───────────────────────────────────
    product_id          BIGINT      NOT NULL REFERENCES logistics.products(id),
    product_variant_id  BIGINT      REFERENCES logistics.product_variants(id),

    -- Cantidad planificada
    planned_quantity    NUMERIC(18,6) NOT NULL,
    uom_id              BIGINT      REFERENCES logistics.measurement_units(id),

    -- Cantidad realmente producida (se va llenando conforme avanza)
    produced_quantity   NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- Cantidad rechazada / merma
    rejected_quantity   NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- Cantidad en reproceso
    rework_quantity     NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- ── BOM y Ruta ────────────────────────────────────────────
    bom_header_id       BIGINT      REFERENCES production.bom_headers(id),
    bom_version_id      BIGINT      REFERENCES production.bom_versions(id),

    routing_id          BIGINT      REFERENCES production.routings(id),
    routing_version_id  BIGINT      REFERENCES production.routing_versions(id),

    -- ── Para desarmado (disassembly) ─────────────────────────
    disassembly_bom_id  BIGINT      REFERENCES production.disassembly_bom(id),

    -- ── Para refurbishment ────────────────────────────────────
    -- Grado asignado al retorno ANTES de reparar
    initial_grade_id    BIGINT      REFERENCES production.refurbishment_grades(id),
    -- Grado final DESPUÉS del proceso
    final_grade_id      BIGINT      REFERENCES production.refurbishment_grades(id),

    -- ── Para reproceso (rework) ───────────────────────────────
    -- Orden original que generó el rechazo
    parent_order_id     BIGINT      REFERENCES production.production_orders(id),

    -- ── Trazabilidad del producto de entrada (retorno/trade-in)─
    -- Para disassembly y refurbishment: qué unidad entró
    input_lot_id        BIGINT      REFERENCES logistics.lots(id),
    input_serial_id     BIGINT      REFERENCES logistics.serial_numbers(id),
    input_return_id     BIGINT,
    -- REFERENCES logistics.customer_returns(id) — FK diferida

    -- ── Fechas ────────────────────────────────────────────────
    planned_start_date  DATE        NOT NULL,
    planned_end_date    DATE        NOT NULL,

    -- Tiempos reales (se llenan al ejecutar)
    actual_start_at     TIMESTAMPTZ,
    actual_end_at       TIMESTAMPTZ,

    -- Tiempo total de producción (calculado)
    actual_duration_min NUMERIC(10,2) GENERATED ALWAYS AS (
        CASE WHEN actual_end_at IS NOT NULL AND actual_start_at IS NOT NULL
             THEN EXTRACT(EPOCH FROM (actual_end_at - actual_start_at)) / 60
             ELSE NULL END
    ) STORED,

    -- ── Ubicaciones (integración Logistics) ───────────────────
    -- ¿Dónde se produce?
    production_warehouse_id BIGINT  REFERENCES logistics.warehouses(id),

    -- ¿A dónde va el producto terminado?
    -- Esta ubicación alimenta inventory_transactions al completar la OP
    output_location_id  BIGINT      REFERENCES logistics.locations(id),
    -- Típicamente: zona PT (Productos Terminados) o almacén de PT

    -- ¿De dónde salen las materias primas?
    input_location_id   BIGINT      REFERENCES logistics.locations(id),
    -- Típicamente: zona de MP (Materia Prima) o almacén de insumos

    -- ── Lote del producto terminado ───────────────────────────
    -- El lote asignado a las unidades que producirá esta OP
    output_lot_id       BIGINT      REFERENCES logistics.lots(id),

    -- ── Prioridad y planificación ─────────────────────────────
    priority            SMALLINT    NOT NULL DEFAULT 5,
    -- 1 = urgente, 5 = normal, 10 = baja prioridad

    -- Origen de la OP
    origin_type         VARCHAR(20) NOT NULL DEFAULT 'manual',
    -- manual      : creada manualmente por planificador
    -- sales_order : generada desde orden de venta
    -- mrp         : generada por MRP (planificación de necesidades)
    -- forecast    : generada desde pronóstico de ventas
    -- return      : generada desde devolución (refurb/disassembly)

    origin_sales_order_id BIGINT,
    -- REFERENCES sales.sales_orders(id) — FK diferida

    -- ── Costeo ───────────────────────────────────────────────
    -- Costo estándar planificado
    std_material_cost   NUMERIC(18,4) NOT NULL DEFAULT 0,
    std_labor_cost      NUMERIC(18,4) NOT NULL DEFAULT 0,
    std_overhead_cost   NUMERIC(18,4) NOT NULL DEFAULT 0,
    std_total_cost      NUMERIC(18,4) GENERATED ALWAYS AS (
        std_material_cost + std_labor_cost + std_overhead_cost
    ) STORED,

    -- Costo real (se llena al cerrar la OP)
    actual_material_cost NUMERIC(18,4) NOT NULL DEFAULT 0,
    actual_labor_cost   NUMERIC(18,4) NOT NULL DEFAULT 0,
    actual_overhead_cost NUMERIC(18,4) NOT NULL DEFAULT 0,
    actual_total_cost   NUMERIC(18,4) GENERATED ALWAYS AS (
        actual_material_cost + actual_labor_cost + actual_overhead_cost
    ) STORED,

    -- Varianza (real - estándar)
    cost_variance       NUMERIC(18,4) GENERATED ALWAYS AS (
        (actual_material_cost + actual_labor_cost + actual_overhead_cost) -
        (std_material_cost + std_labor_cost + std_overhead_cost)
    ) STORED,

    notes               TEXT,

    created_by          BIGINT      REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX uq_prod_order_number
    ON production.production_orders (company_id, order_number);
CREATE INDEX idx_po_product    ON production.production_orders (product_id);
CREATE INDEX idx_po_status     ON production.production_orders (status_code);
CREATE INDEX idx_po_dates      ON production.production_orders (planned_start_date, planned_end_date);
CREATE INDEX idx_po_company    ON production.production_orders (company_id);

CREATE TRIGGER trg_po_updated_at
    BEFORE UPDATE ON production.production_orders
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

-- FK diferida: machine_downtime.affected_production_order_id
ALTER TABLE production.machine_downtime
    ADD CONSTRAINT fk_downtime_order
    FOREIGN KEY (affected_production_order_id)
    REFERENCES production.production_orders(id)
    DEFERRABLE INITIALLY DEFERRED;

COMMENT ON TABLE production.production_orders IS 'Órdenes de producción universales: manufactura, desarmado, refurbishment, reproceso, maquila. Integración directa con inventory_transactions.';

-- ============================================================
-- 3. MATERIAL REQUIREMENTS (Necesidades de Materiales)
--    Lista de materiales requeridos por la OP,
--    generada automáticamente al explotar el BOM.
--    Sirve para reservar stock en logistics y generar el picking list.
-- ============================================================
CREATE TABLE production.order_material_requirements (
    id                  BIGSERIAL   PRIMARY KEY,
    production_order_id BIGINT      NOT NULL REFERENCES production.production_orders(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    bom_line_id         BIGINT      REFERENCES production.bom_lines(id),
    -- NULL si fue agregado manualmente

    component_product_id BIGINT     NOT NULL REFERENCES logistics.products(id),
    component_variant_id BIGINT     REFERENCES logistics.product_variants(id),

    -- Cantidad requerida (calculada del BOM × cantidad OP)
    required_quantity   NUMERIC(18,6) NOT NULL,
    uom_id              BIGINT      REFERENCES logistics.measurement_units(id),

    -- Cantidad ya reservada en inventario
    reserved_quantity   NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- Cantidad consumida realmente (backflush o manual)
    consumed_quantity   NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- Merma esperada según BOM
    planned_scrap       NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- Merma real registrada
    actual_scrap        NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- Fuente del material
    source_location_id  BIGINT      REFERENCES logistics.locations(id),
    source_lot_id       BIGINT      REFERENCES logistics.lots(id),

    -- Referencia al inventory_transaction de reserva
    reservation_tx_id   BIGINT,
    -- REFERENCES logistics.inventory_transactions(id) — FK diferida

    -- Estado del requerimiento
    status              VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending   : pendiente de reserva
    -- reserved  : stock reservado
    -- issued    : material enviado a producción
    -- consumed  : consumo registrado
    -- partial   : consumo parcial

    component_type      VARCHAR(20) NOT NULL DEFAULT 'component',
    -- Heredado del bom_line

    consumption_method  VARCHAR(20) NOT NULL DEFAULT 'manual',
    -- manual / backflush / pick_list

    sequence            SMALLINT    NOT NULL DEFAULT 10,

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_matreq_order     ON production.order_material_requirements (production_order_id);
CREATE INDEX idx_matreq_component ON production.order_material_requirements (component_product_id);

CREATE TRIGGER trg_matreq_updated_at
    BEFORE UPDATE ON production.order_material_requirements
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

COMMENT ON TABLE production.order_material_requirements IS 'Necesidades de material por OP. Explosión del BOM. Base para reserva de stock y picking list de almacén.';

-- ============================================================
-- 4. PRODUCTION INVENTORY MOVEMENTS
--    Registro de todos los movimientos de inventario
--    generados por la OP (entradas y salidas).
--    Esta tabla es el puente entre Production y Logistics.
--
--    Tipos de movimiento que genera una OP:
--    - production_consumption : salida de MP al proceso
--    - production_output      : entrada de PT al almacén
--    - production_scrap       : salida de merma
--    - production_byproduct   : entrada de subproducto
-- ============================================================
CREATE TABLE production.production_inventory_moves (
    id                  BIGSERIAL   PRIMARY KEY,
    production_order_id BIGINT      NOT NULL REFERENCES production.production_orders(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Referencia al movimiento en logistics
    inventory_transaction_id BIGINT NOT NULL,
    -- REFERENCES logistics.inventory_transactions(id) — FK diferida

    move_type           VARCHAR(30) NOT NULL,
    -- production_consumption  : salida de materia prima
    -- production_output       : entrada de producto terminado al almacén PT
    -- production_scrap        : salida de merma/desecho
    -- production_byproduct    : entrada de subproducto/co-producto
    -- production_rework_in    : entrada de material a reprocesar
    -- production_rework_out   : salida de reprocesado
    -- disassembly_input       : entrada del producto a desarmar
    -- disassembly_output      : salida de componentes recuperados

    product_id          BIGINT      NOT NULL REFERENCES logistics.products(id),
    variant_id          BIGINT      REFERENCES logistics.product_variants(id),

    quantity            NUMERIC(18,6) NOT NULL,
    uom_id              BIGINT      REFERENCES logistics.measurement_units(id),

    -- Lote y serie
    lot_id              BIGINT      REFERENCES logistics.lots(id),
    serial_id           BIGINT      REFERENCES logistics.serial_numbers(id),

    -- Ubicaciones
    from_location_id    BIGINT      REFERENCES logistics.locations(id),
    to_location_id      BIGINT      REFERENCES logistics.locations(id),

    -- Timestamp exacto del movimiento
    moved_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Work order que generó el movimiento (si aplica)
    work_order_id       BIGINT,
    -- REFERENCES production.work_orders(id) — FK diferida

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE: no tiene updated_at
);

CREATE INDEX idx_pim_order    ON production.production_inventory_moves (production_order_id);
CREATE INDEX idx_pim_type     ON production.production_inventory_moves (move_type);
CREATE INDEX idx_pim_product  ON production.production_inventory_moves (product_id);
CREATE INDEX idx_pim_moved_at ON production.production_inventory_moves (moved_at);

COMMENT ON TABLE production.production_inventory_moves IS 'Puente Production ↔ Logistics. Registra cada movimiento de inventario generado por una OP con timestamp exacto.';

-- ============================================================
-- 5. PRODUCTION ORDER PROCESS TRACKING
--    Trazabilidad detallada de en qué PROCESO está cada OP.
--    Cada proceso tiene su propio start/end timestamp,
--    permitiendo calcular el tiempo real en cada etapa.
--
--    Un proceso = una operación de la ruta (routing_operation).
--    Esta tabla se llena CONFORME AVANZA la producción,
--    no al crear la OP.
-- ============================================================
CREATE TABLE production.order_process_log (
    id                  BIGSERIAL   PRIMARY KEY,
    production_order_id BIGINT      NOT NULL REFERENCES production.production_orders(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- ¿Qué proceso/operación?
    routing_operation_id BIGINT     REFERENCES production.routing_operations(id),
    -- NULL si es un evento de la OP (no de una operación específica)

    process_name        VARCHAR(200) NOT NULL,
    -- Nombre del proceso (puede diferir de la operación si se modificó)

    -- Centro de trabajo y máquina reales usados
    work_center_id      BIGINT      REFERENCES production.work_centers(id),
    machine_id          BIGINT      REFERENCES production.machines(id),

    -- ── Tiempos reales ────────────────────────────────────────
    started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at        TIMESTAMPTZ,
    -- NULL = proceso aún activo

    -- Tiempo en minutos (calculado automáticamente)
    duration_min        NUMERIC(10,2) GENERATED ALWAYS AS (
        CASE WHEN completed_at IS NOT NULL
             THEN EXTRACT(EPOCH FROM (completed_at - started_at)) / 60
             ELSE NULL END
    ) STORED,

    -- Tiempo planificado (para comparar)
    planned_duration_min NUMERIC(10,2),

    -- Varianza de tiempo (real - planificado)
    time_variance_min   NUMERIC(10,2) GENERATED ALWAYS AS (
        CASE WHEN completed_at IS NOT NULL AND planned_duration_min IS NOT NULL
             THEN EXTRACT(EPOCH FROM (completed_at - started_at)) / 60 - planned_duration_min
             ELSE NULL END
    ) STORED,

    -- ── Resultado del proceso ─────────────────────────────────
    process_status      VARCHAR(20) NOT NULL DEFAULT 'in_progress',
    -- in_progress / completed / interrupted / scrapped

    -- Unidades procesadas en este paso
    quantity_processed  NUMERIC(18,6) NOT NULL DEFAULT 0,
    quantity_passed     NUMERIC(18,6) NOT NULL DEFAULT 0,
    quantity_rejected   NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- ¿El proceso fue interrumpido? (avería, falta de material, etc.)
    was_interrupted     BOOLEAN     NOT NULL DEFAULT FALSE,
    interruption_reason TEXT,

    -- ¿El QC de este paso fue OK?
    quality_result      VARCHAR(20),
    -- pass / fail / conditional / pending

    -- Operario(s) que realizaron el proceso
    operator_ids        BIGINT[],
    -- Array de hr.employees(id)

    -- Notas de producción (incidencias, observaciones)
    operator_notes      TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE: el log no se modifica, solo se crea
);

CREATE INDEX idx_opl_order     ON production.order_process_log (production_order_id);
CREATE INDEX idx_opl_started   ON production.order_process_log (started_at);
CREATE INDEX idx_opl_operation ON production.order_process_log (routing_operation_id);

COMMENT ON TABLE production.order_process_log IS 'Trazabilidad en tiempo real de cada proceso. started_at + completed_at dan el tiempo real por operación. Inmutable — el historial no se borra.';

-- ============================================================
-- VIEW: Estado actual de producción por OP
-- ============================================================
CREATE VIEW production.production_order_status_view AS
SELECT
    po.id,
    po.company_id,
    po.order_number,
    po.order_type,
    po.status_code,
    p.name AS product_name,
    po.planned_quantity,
    po.produced_quantity,
    po.rejected_quantity,
    ROUND(
        CASE WHEN po.planned_quantity > 0
             THEN (po.produced_quantity / po.planned_quantity) * 100
             ELSE 0 END, 2
    ) AS completion_pct,
    po.planned_start_date,
    po.planned_end_date,
    po.actual_start_at,
    po.actual_end_at,
    po.actual_duration_min,
    -- Proceso actual (último proceso activo)
    (SELECT opl.process_name
     FROM production.order_process_log opl
     WHERE opl.production_order_id = po.id
       AND opl.process_status = 'in_progress'
     ORDER BY opl.started_at DESC LIMIT 1) AS current_process,
    -- Último proceso completado
    (SELECT opl.process_name
     FROM production.order_process_log opl
     WHERE opl.production_order_id = po.id
       AND opl.process_status = 'completed'
     ORDER BY opl.completed_at DESC LIMIT 1) AS last_completed_process,
    po.std_total_cost,
    po.actual_total_cost,
    po.cost_variance
FROM production.production_orders po
JOIN logistics.products p ON p.id = po.product_id;

COMMENT ON VIEW production.production_order_status_view IS 'Vista de estado en tiempo real: % completado, proceso actual, proceso anterior, costos vs estándar.';
