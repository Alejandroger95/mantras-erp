-- ============================================================
-- mantrasdb | Módulo Logistics
-- Archivo: 09_waves_picking.sql
-- Descripción: Waves (olas de picking) y tareas de pick.
--
-- Flujo:
--   wave_template → wave → wave_orders → inventory_allocations
--   → pick_tasks → pick_task_details
--
-- Wave template: CONFIGURACIÓN de cómo funciona la ola
-- Wave:          INSTANCIA creada desde una plantilla
-- Allocation:    RESERVA de inventario para cada línea
--                (aquí se valida que el producto esté asignado)
-- Pick task:     Tarea para el picker/robot
-- ============================================================

-- ============================================================
-- Plantillas de wave (configuración)
-- ============================================================
CREATE TABLE logistics.wave_templates (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    warehouse_id        BIGINT          NOT NULL REFERENCES logistics.warehouses(id) ON DELETE RESTRICT,

    name                VARCHAR(200)    NOT NULL,
    description         TEXT,

    -- Método de picking
    picking_method      VARCHAR(20)     NOT NULL DEFAULT 'zone',
    -- zone     = por zonas, un picker por zona
    -- batch    = un picker toma varias órdenes a la vez
    -- cluster  = múltiples contenedores simultáneos
    -- discrete = una orden por picker a la vez

    -- Método de ordenamiento de tareas
    sort_method         VARCHAR(30)     NOT NULL DEFAULT 'location_sequence',
    -- location_sequence = por secuencia de ubicaciones (ruta óptima)
    -- order_priority    = por prioridad de la orden
    -- zone_then_order   = primero zona, luego orden

    -- Límites de la wave
    max_orders          INTEGER,
    -- máximo de órdenes por wave
    max_lines           INTEGER,
    -- máximo de líneas totales
    max_weight_kg       NUMERIC(10,3),
    max_volume_m3       NUMERIC(10,6),

    -- Liberación
    auto_release        BOOLEAN         NOT NULL DEFAULT FALSE,
    -- TRUE = se libera automáticamente al cumplir criterios
    release_time        TIME,
    -- hora del día en que se libera (si auto_release=TRUE)

    -- Criterios de inclusión de órdenes (JSONB flexible)
    inclusion_criteria  JSONB,
    -- Ej: {"order_type": ["sale"], "priority_min": 1, "zone_ids": [1,2,3]}

    -- Zonas y secuencia de recorrido
    zone_sequence       JSONB,
    -- Ej: [{"zone_id": 1, "seq": 1}, {"zone_id": 2, "seq": 2}]

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_wave_templates_company ON logistics.wave_templates (company_id);

CREATE TRIGGER trg_wave_templates_updated_at
    BEFORE UPDATE ON logistics.wave_templates
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.wave_templates                   IS 'Configuración de cómo funciona una ola de picking. Se instancia en waves.';
COMMENT ON COLUMN logistics.wave_templates.picking_method    IS 'zone=un picker por zona. batch=picker lleva múltiples órdenes. cluster=varios contenedores. discrete=una orden.';
COMMENT ON COLUMN logistics.wave_templates.inclusion_criteria IS 'JSON con reglas de qué órdenes entran en esta wave (tipo, prioridad, zona, etc.).';

-- ============================================================
-- Waves (instancias de ola de picking)
-- ============================================================
CREATE TABLE logistics.waves (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    warehouse_id        BIGINT          NOT NULL REFERENCES logistics.warehouses(id) ON DELETE RESTRICT,
    wave_template_id    BIGINT          REFERENCES logistics.wave_templates(id),
    wave_status_id      INTEGER         NOT NULL REFERENCES logistics.wave_statuses(id),

    wave_number         VARCHAR(50)     NOT NULL,
    wave_date           DATE            NOT NULL DEFAULT CURRENT_DATE,

    -- Estadísticas
    total_orders        INTEGER         NOT NULL DEFAULT 0,
    total_lines         INTEGER         NOT NULL DEFAULT 0,
    total_units         NUMERIC(18,4)   NOT NULL DEFAULT 0,
    total_weight_kg     NUMERIC(10,3),

    -- Tiempos
    planned_start       TIMESTAMPTZ,
    released_at         TIMESTAMPTZ,
    -- momento en que se liberan las tareas de pick
    completed_at        TIMESTAMPTZ,

    -- Quién creó y aprobó
    created_by          BIGINT,
    released_by         BIGINT,

    notes               TEXT,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, wave_number)
);

CREATE INDEX idx_waves_company  ON logistics.waves (company_id);
CREATE INDEX idx_waves_status   ON logistics.waves (wave_status_id);
CREATE INDEX idx_waves_date     ON logistics.waves (wave_date);

CREATE TRIGGER trg_waves_updated_at
    BEFORE UPDATE ON logistics.waves
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.waves IS 'Instancia de ola de picking. Agrupa órdenes para ejecutar el picking eficientemente.';

-- ============================================================
-- Órdenes incluidas en una wave
-- ============================================================
CREATE TABLE logistics.wave_orders (
    id                  BIGSERIAL       PRIMARY KEY,
    wave_id             BIGINT          NOT NULL REFERENCES logistics.waves(id) ON DELETE RESTRICT,
    outbound_order_id   BIGINT          NOT NULL,
    -- REFERENCES logistics.outbound_orders(id) — tabla en 10_outbound.sql

    sequence            INTEGER         NOT NULL DEFAULT 1,
    -- prioridad de esta orden dentro de la wave

    added_at            TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (wave_id, outbound_order_id)
);

CREATE INDEX idx_wave_orders_wave  ON logistics.wave_orders (wave_id);

COMMENT ON TABLE logistics.wave_orders IS 'Qué órdenes están incluidas en cada wave.';

-- ============================================================
-- Allocations — reserva de inventario por línea de orden
-- (tabla clave para validar si el producto fue asignado)
-- ============================================================
CREATE TABLE logistics.inventory_allocations (
    id                      BIGSERIAL       PRIMARY KEY,
    company_id              BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    wave_id                 BIGINT          NOT NULL REFERENCES logistics.waves(id) ON DELETE RESTRICT,
    outbound_order_line_id  BIGINT          NOT NULL,
    -- REFERENCES logistics.outbound_order_lines(id) — tabla en 10_outbound.sql
    product_id              BIGINT          NOT NULL REFERENCES logistics.products(id),
    lot_id                  BIGINT          REFERENCES logistics.lots(id),
    serial_number_id        BIGINT          REFERENCES logistics.serial_numbers(id),
    location_id             BIGINT          NOT NULL REFERENCES logistics.locations(id),
    unit_id                 INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),

    -- Cantidades
    allocated_qty           NUMERIC(18,4)   NOT NULL,
    -- cuánto reservó el sistema de esta ubicación+lote
    picked_qty              NUMERIC(18,4)   NOT NULL DEFAULT 0,
    -- cuánto recogió el picker/robot realmente
    short_qty               NUMERIC(18,4)
        GENERATED ALWAYS AS (
            GREATEST(allocated_qty - picked_qty, 0)
        ) STORED,
    -- diferencia no recogida (short pick)

    -- Estado de esta allocación
    status                  VARCHAR(20)     NOT NULL DEFAULT 'pending',
    -- pending | allocated | in_progress | picked | short_picked | cancelled

    -- Referencia al pick task generado
    pick_task_id            BIGINT,
    -- REFERENCES logistics.pick_tasks(id) — se agrega después

    allocated_at            TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    picked_at               TIMESTAMPTZ,
    notes                   TEXT,

    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_allocations_wave     ON logistics.inventory_allocations (wave_id);
CREATE INDEX idx_allocations_product  ON logistics.inventory_allocations (product_id);
CREATE INDEX idx_allocations_location ON logistics.inventory_allocations (location_id);
CREATE INDEX idx_allocations_status   ON logistics.inventory_allocations (status)
    WHERE status IN ('pending', 'allocated', 'in_progress');

CREATE TRIGGER trg_allocations_updated_at
    BEFORE UPDATE ON logistics.inventory_allocations
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.inventory_allocations              IS 'Reserva de inventario por línea de orden antes del picking. Valida si el producto fue asignado.';
COMMENT ON COLUMN logistics.inventory_allocations.allocated_qty IS 'Cantidad reservada: bloquea stock en logistics.inventory.quantity_reserved.';
COMMENT ON COLUMN logistics.inventory_allocations.short_qty     IS 'Calculado: diferencia no recogida. > 0 = short pick (faltó stock en la ubicación).';

-- ============================================================
-- Tareas de picking
-- ============================================================
CREATE TABLE logistics.pick_tasks (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    wave_id             BIGINT          NOT NULL REFERENCES logistics.waves(id) ON DELETE RESTRICT,
    pick_status_id      INTEGER         NOT NULL REFERENCES logistics.pick_statuses(id),

    task_number         VARCHAR(50)     NOT NULL,

    -- Quién ejecuta (humano o robot)
    performed_by_type   VARCHAR(10)     NOT NULL DEFAULT 'human',
    -- human | robot
    performed_by_id     BIGINT,
    -- employee_id o robot_id

    -- Zona/área asignada
    zone_id             BIGINT          REFERENCES logistics.warehouse_zones(id),

    -- Contenedor destino del picker
    container_id        BIGINT          REFERENCES logistics.containers(id),

    -- Totales
    total_lines         INTEGER         NOT NULL DEFAULT 0,
    total_units         NUMERIC(18,4)   NOT NULL DEFAULT 0,

    -- Tiempos
    assigned_at         TIMESTAMPTZ,
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,

    notes               TEXT,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, task_number)
);

CREATE INDEX idx_pick_tasks_wave     ON logistics.pick_tasks (wave_id);
CREATE INDEX idx_pick_tasks_status   ON logistics.pick_tasks (pick_status_id);
CREATE INDEX idx_pick_tasks_operator ON logistics.pick_tasks (performed_by_type, performed_by_id);

CREATE TRIGGER trg_pick_tasks_updated_at
    BEFORE UPDATE ON logistics.pick_tasks
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.pick_tasks                      IS 'Tareas de picking asignadas a un operador (humano o robot AMR).';
COMMENT ON COLUMN logistics.pick_tasks.performed_by_type    IS 'human=empleado pistoliando. robot=AMR autónomo. Ambos quedan trazados igual.';

-- ============================================================
-- Detalle de pick task (línea por línea)
-- ============================================================
CREATE TABLE logistics.pick_task_details (
    id                  BIGSERIAL       PRIMARY KEY,
    pick_task_id        BIGINT          NOT NULL REFERENCES logistics.pick_tasks(id) ON DELETE RESTRICT,
    allocation_id       BIGINT          NOT NULL REFERENCES logistics.inventory_allocations(id),
    product_id          BIGINT          NOT NULL REFERENCES logistics.products(id),
    lot_id              BIGINT          REFERENCES logistics.lots(id),
    serial_number_id    BIGINT          REFERENCES logistics.serial_numbers(id),
    from_location_id    BIGINT          NOT NULL REFERENCES logistics.locations(id),
    unit_id             INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),

    sequence            INTEGER         NOT NULL DEFAULT 1,
    -- orden de recorrido dentro de la tarea (ruta óptima)

    quantity_to_pick    NUMERIC(18,4)   NOT NULL,
    quantity_picked     NUMERIC(18,4)   NOT NULL DEFAULT 0,

    -- Verificación
    scanned_barcode     VARCHAR(200),
    -- código de barras escaneado para confirmar el producto
    scan_confirmed      BOOLEAN         NOT NULL DEFAULT FALSE,

    -- Foto del pick (diferenciador)
    photo_url           VARCHAR(500),
    photo_taken_at      TIMESTAMPTZ,

    status              VARCHAR(20)     NOT NULL DEFAULT 'pending',
    -- pending | picked | short_picked | skipped

    picked_at           TIMESTAMPTZ,
    notes               TEXT,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_pick_details_task     ON logistics.pick_task_details (pick_task_id);
CREATE INDEX idx_pick_details_product  ON logistics.pick_task_details (product_id);
CREATE INDEX idx_pick_details_location ON logistics.pick_task_details (from_location_id);

CREATE TRIGGER trg_pick_details_updated_at
    BEFORE UPDATE ON logistics.pick_task_details
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.pick_task_details           IS 'Líneas de cada tarea de picking con verificación por escaneo y foto.';
COMMENT ON COLUMN logistics.pick_task_details.photo_url IS 'Foto tomada al picar el producto. Evidencia para reclamos. Diferenciador del ERP.';
