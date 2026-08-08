-- ============================================================
-- mantrasdb | Módulo Logistics
-- Archivo: 11_transfers.sql
-- Descripción: Transferencias internas entre ubicaciones/almacenes
--              y reposición (replenishment) de zonas de picking.
--
-- Flujo transferencia:
--   transfer_order → transfer_order_lines → inventory_transactions
--   (transfer_out origen, transfer_in destino)
--
-- Flujo replenishment:
--   Sistema detecta stock bajo en pick face →
--   replenishment_task → operador/robot repone desde reserva
-- ============================================================

-- ============================================================
-- Órdenes de transferencia interna
-- ============================================================
CREATE TABLE logistics.transfer_orders (
    id                      BIGSERIAL       PRIMARY KEY,
    company_id              BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    transfer_status_id      INTEGER         NOT NULL REFERENCES logistics.transfer_statuses(id),

    transfer_number         VARCHAR(50)     NOT NULL,
    transfer_type           VARCHAR(20)     NOT NULL DEFAULT 'internal',
    -- internal      = dentro del mismo almacén (entre zonas)
    -- inter_warehouse = entre almacenes distintos

    -- Origen
    from_warehouse_id       BIGINT          NOT NULL REFERENCES logistics.warehouses(id),
    from_location_id        BIGINT          REFERENCES logistics.locations(id),
    -- si NULL = todo el almacén origen

    -- Destino
    to_warehouse_id         BIGINT          NOT NULL REFERENCES logistics.warehouses(id),
    to_location_id          BIGINT          REFERENCES logistics.locations(id),

    -- Razón
    transfer_reason         VARCHAR(200),
    -- rebalancing | replenishment | consolidation | quality_hold | damage | correction

    -- Quién autorizó
    approved_by             BIGINT,
    approved_at             TIMESTAMPTZ,

    -- Tiempos
    planned_date            DATE,
    started_at              TIMESTAMPTZ,
    completed_at            TIMESTAMPTZ,

    notes                   TEXT,
    is_active               BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, transfer_number)
);

CREATE INDEX idx_transfer_orders_company ON logistics.transfer_orders (company_id);
CREATE INDEX idx_transfer_orders_status  ON logistics.transfer_orders (transfer_status_id);

CREATE TRIGGER trg_transfer_orders_updated_at
    BEFORE UPDATE ON logistics.transfer_orders
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.transfer_orders               IS 'Órdenes de transferencia: mueve stock entre ubicaciones o almacenes.';
COMMENT ON COLUMN logistics.transfer_orders.transfer_type IS 'internal=misma bodega, inter_warehouse=entre bodegas distintas.';

-- ============================================================
-- Líneas de transferencia
-- ============================================================
CREATE TABLE logistics.transfer_order_lines (
    id                  BIGSERIAL       PRIMARY KEY,
    transfer_order_id   BIGINT          NOT NULL REFERENCES logistics.transfer_orders(id) ON DELETE RESTRICT,
    product_id          BIGINT          NOT NULL REFERENCES logistics.products(id),
    lot_id              BIGINT          REFERENCES logistics.lots(id),
    serial_number_id    BIGINT          REFERENCES logistics.serial_numbers(id),
    unit_id             INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),
    container_id        BIGINT          REFERENCES logistics.containers(id),

    line_number         INTEGER         NOT NULL,

    quantity_planned    NUMERIC(18,4)   NOT NULL,
    quantity_transferred NUMERIC(18,4)  NOT NULL DEFAULT 0,

    -- Quién ejecutó
    performed_by_type   VARCHAR(10)     NOT NULL DEFAULT 'human',
    -- human | robot | system
    performed_by_id     BIGINT,

    transferred_at      TIMESTAMPTZ,
    notes               TEXT,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (transfer_order_id, line_number)
);

CREATE INDEX idx_transfer_lines_order   ON logistics.transfer_order_lines (transfer_order_id);
CREATE INDEX idx_transfer_lines_product ON logistics.transfer_order_lines (product_id);

CREATE TRIGGER trg_transfer_lines_updated_at
    BEFORE UPDATE ON logistics.transfer_order_lines
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.transfer_order_lines IS 'Líneas de transferencia: qué producto, lote y cantidad se mueve.';

-- ============================================================
-- Tareas de reposición (replenishment)
-- Cuando el stock en la zona de pick cae bajo el mínimo,
-- el sistema genera una tarea para traer más desde la reserva.
-- ============================================================
CREATE TABLE logistics.replenishment_tasks (
    id                      BIGSERIAL       PRIMARY KEY,
    company_id              BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    warehouse_id            BIGINT          NOT NULL REFERENCES logistics.warehouses(id),
    product_id              BIGINT          NOT NULL REFERENCES logistics.products(id),
    lot_id                  BIGINT          REFERENCES logistics.lots(id),
    unit_id                 INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),

    task_number             VARCHAR(50)     NOT NULL,

    -- Origen (reserva / bulk)
    from_location_id        BIGINT          NOT NULL REFERENCES logistics.locations(id),

    -- Destino (pick face / zona de picking)
    to_location_id          BIGINT          NOT NULL REFERENCES logistics.locations(id),

    -- Cantidades
    quantity_requested      NUMERIC(18,4)   NOT NULL,
    -- cuánto pide el sistema para rellenar el pick face
    quantity_replenished    NUMERIC(18,4)   NOT NULL DEFAULT 0,

    -- Razón de disparo
    trigger_type            VARCHAR(20)     NOT NULL DEFAULT 'min_stock',
    -- min_stock      = stock cayó bajo el mínimo
    -- wave_request   = una wave requirió más stock del que había
    -- manual         = operador lo pidió manualmente

    -- Estado
    status                  VARCHAR(20)     NOT NULL DEFAULT 'pending',
    -- pending | assigned | in_progress | completed | cancelled

    -- Prioridad
    priority                SMALLINT        NOT NULL DEFAULT 3,
    -- 1=urgente (wave esperando) → 5=baja

    -- Quién ejecutó
    performed_by_type       VARCHAR(10)     NOT NULL DEFAULT 'human',
    -- human | robot
    performed_by_id         BIGINT,

    assigned_at             TIMESTAMPTZ,
    started_at              TIMESTAMPTZ,
    completed_at            TIMESTAMPTZ,

    notes                   TEXT,
    is_active               BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, task_number)
);

CREATE INDEX idx_replenishment_company  ON logistics.replenishment_tasks (company_id);
CREATE INDEX idx_replenishment_status   ON logistics.replenishment_tasks (status)
    WHERE status IN ('pending', 'assigned', 'in_progress');
CREATE INDEX idx_replenishment_product  ON logistics.replenishment_tasks (product_id);
CREATE INDEX idx_replenishment_to       ON logistics.replenishment_tasks (to_location_id);

CREATE TRIGGER trg_replenishment_updated_at
    BEFORE UPDATE ON logistics.replenishment_tasks
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.replenishment_tasks              IS 'Tareas de reposición del pick face. El sistema las genera cuando el stock de picking cae bajo el mínimo.';
COMMENT ON COLUMN logistics.replenishment_tasks.trigger_type IS 'min_stock=bajo mínimo, wave_request=wave necesita más, manual=pedido por operador.';
COMMENT ON COLUMN logistics.replenishment_tasks.priority     IS '1=urgente (wave bloqueada esperando stock) → 5=baja prioridad. Robots priorizan las de mayor urgencia.';
