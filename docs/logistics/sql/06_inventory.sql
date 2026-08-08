-- ============================================================
-- mantrasdb | Módulo Logistics
-- Archivo: 06_inventory.sql
-- Descripción: Inventario, lotes, números de serie y el ledger
--              central de transacciones de inventario.
--
-- Diseño clave:
--   inventory          → stock actual por ubicación + lote
--   lots               → lotes/partidas con vencimiento
--   serial_numbers     → trazabilidad unitaria (productos serializados)
--   inventory_transactions → LEDGER CENTRAL de todos los movimientos
--
-- El ledger registra TODO: recepciones, picks, ajustes, ensamblaje
-- de kits, devoluciones, transferencias, etc. Es la fuente de verdad
-- histórica del inventario.
-- ============================================================

-- ============================================================
-- Lotes / partidas
-- ============================================================
CREATE TABLE logistics.lots (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    product_id          BIGINT          NOT NULL REFERENCES logistics.products(id) ON DELETE RESTRICT,
    supplier_id         BIGINT          REFERENCES logistics.suppliers(id),

    lot_number          VARCHAR(100)    NOT NULL,
    -- número de lote del proveedor o interno

    -- Fechas clave
    manufacture_date    DATE,
    expiry_date         DATE,
    received_date       DATE,

    -- Trazabilidad
    supplier_lot_number VARCHAR(100),
    -- número de lote del proveedor (puede diferir del interno)
    country_of_origin   VARCHAR(100),

    -- Estado
    status              VARCHAR(20)     NOT NULL DEFAULT 'available',
    -- available | quarantine | blocked | expired | consumed
    quarantine_reason   TEXT,

    notes               TEXT,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, product_id, lot_number)
);

CREATE INDEX idx_lots_company     ON logistics.lots (company_id);
CREATE INDEX idx_lots_product     ON logistics.lots (product_id);
CREATE INDEX idx_lots_expiry      ON logistics.lots (expiry_date) WHERE expiry_date IS NOT NULL;
CREATE INDEX idx_lots_status      ON logistics.lots (status) WHERE status = 'available';

CREATE TRIGGER trg_lots_updated_at
    BEFORE UPDATE ON logistics.lots
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.lots             IS 'Lotes/partidas de productos con control de vencimiento. Base del picking FEFO.';
COMMENT ON COLUMN logistics.lots.expiry_date IS 'Fecha de vencimiento. El sistema prioriza los lotes con menor fecha en picking FEFO.';

-- ============================================================
-- Números de serie (para productos serializados)
-- ============================================================
CREATE TABLE logistics.serial_numbers (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    product_id          BIGINT          NOT NULL REFERENCES logistics.products(id) ON DELETE RESTRICT,
    lot_id              BIGINT          REFERENCES logistics.lots(id),

    serial_number       VARCHAR(200)    NOT NULL,

    -- Estado actual
    status              VARCHAR(20)     NOT NULL DEFAULT 'in_stock',
    -- in_stock | sold | returned | scrapped | in_transit

    -- Trazabilidad
    received_date       DATE,
    sold_date           DATE,
    current_location_id BIGINT,
    -- REFERENCES logistics.locations(id) — FK sin constraint por circularidad, se actualiza

    notes               TEXT,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, product_id, serial_number)
);

CREATE INDEX idx_serial_numbers_product ON logistics.serial_numbers (product_id);
CREATE INDEX idx_serial_numbers_status  ON logistics.serial_numbers (status);

CREATE TRIGGER trg_serial_numbers_updated_at
    BEFORE UPDATE ON logistics.serial_numbers
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.serial_numbers IS 'Números de serie para productos serializados (electrónicos, equipos, etc.). Trazabilidad unitaria.';

-- ============================================================
-- Inventario actual (stock en tiempo real por ubicación + lote)
-- ============================================================
CREATE TABLE logistics.inventory (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    warehouse_id        BIGINT          NOT NULL REFERENCES logistics.warehouses(id) ON DELETE RESTRICT,
    location_id         BIGINT          NOT NULL REFERENCES logistics.locations(id) ON DELETE RESTRICT,
    product_id          BIGINT          NOT NULL REFERENCES logistics.products(id) ON DELETE RESTRICT,
    lot_id              BIGINT          REFERENCES logistics.lots(id),
    -- NULL si el producto no es trazado por lote
    unit_id             INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),

    -- Stock
    quantity_on_hand    NUMERIC(18,4)   NOT NULL DEFAULT 0,
    -- stock físico disponible en esta ubicación
    quantity_reserved   NUMERIC(18,4)   NOT NULL DEFAULT 0,
    -- stock reservado por allocations (waves activas, órdenes confirmadas)
    quantity_available  NUMERIC(18,4)
        GENERATED ALWAYS AS (quantity_on_hand - quantity_reserved) STORED,
    -- stock disponible para nuevas órdenes (calculado)

    -- Costo
    unit_cost           NUMERIC(18,6),
    -- costo unitario promedio ponderado de este stock

    -- Última actividad
    last_movement_at    TIMESTAMPTZ,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (location_id, product_id, lot_id, unit_id)
);

CREATE INDEX idx_inventory_company   ON logistics.inventory (company_id);
CREATE INDEX idx_inventory_warehouse ON logistics.inventory (warehouse_id);
CREATE INDEX idx_inventory_location  ON logistics.inventory (location_id);
CREATE INDEX idx_inventory_product   ON logistics.inventory (product_id);
CREATE INDEX idx_inventory_lot       ON logistics.inventory (lot_id) WHERE lot_id IS NOT NULL;
CREATE INDEX idx_inventory_available ON logistics.inventory (company_id, product_id)
    WHERE quantity_on_hand > 0;

CREATE TRIGGER trg_inventory_updated_at
    BEFORE UPDATE ON logistics.inventory
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.inventory                    IS 'Stock actual por ubicación + lote. Fuente de verdad del inventario en tiempo real.';
COMMENT ON COLUMN logistics.inventory.quantity_reserved  IS 'Stock bloqueado por waves activas o allocations. No disponible para nuevas órdenes.';
COMMENT ON COLUMN logistics.inventory.quantity_available IS 'Calculado: on_hand - reserved. Disponible para nuevas órdenes.';
COMMENT ON COLUMN logistics.inventory.unit_cost          IS 'Costo promedio ponderado actualizado con cada recepción.';

-- ============================================================
-- Ledger central de transacciones de inventario
-- ============================================================
CREATE TABLE logistics.inventory_transactions (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    warehouse_id        BIGINT          NOT NULL REFERENCES logistics.warehouses(id) ON DELETE RESTRICT,
    product_id          BIGINT          NOT NULL REFERENCES logistics.products(id) ON DELETE RESTRICT,
    lot_id              BIGINT          REFERENCES logistics.lots(id),
    serial_number_id    BIGINT          REFERENCES logistics.serial_numbers(id),
    unit_id             INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),

    -- Tipo de movimiento
    adjustment_type_id  INTEGER         NOT NULL REFERENCES logistics.adjustment_types(id),
    transaction_type    VARCHAR(50)     NOT NULL,
    -- receipt            → entrada por compra
    -- putaway            → guardado en ubicación tras recepción
    -- pick               → salida para orden de despacho
    -- pack               → movimiento a zona de empaque
    -- ship               → confirmación de envío
    -- kit_assembly_out   → componente sale al ensamblar kit
    -- kit_assembly_in    → kit ensamblado entra al inventario
    -- kit_disassembly_out → kit sale al desarmar
    -- kit_disassembly_in  → componentes regresan al desarmar
    -- transfer_out       → sale de ubicación/almacén origen
    -- transfer_in        → entra a ubicación/almacén destino
    -- adjustment         → ajuste manual
    -- count_adjustment   → ajuste por conteo físico
    -- return_customer    → devolución de cliente ingresa al almacén
    -- return_supplier    → mercadería sale al proveedor
    -- scrap              → merma, daño, vencimiento

    -- Cantidad y dirección
    quantity            NUMERIC(18,4)   NOT NULL,
    -- POSITIVO = entrada al inventario, NEGATIVO = salida
    unit_cost           NUMERIC(18,6),

    -- Ubicaciones
    from_location_id    BIGINT          REFERENCES logistics.locations(id),
    to_location_id      BIGINT          REFERENCES logistics.locations(id),

    -- Referencia al documento origen
    reference_type      VARCHAR(50),
    -- purchase_order | receipt | outbound_order | wave | pick_task | kit_assembly |
    -- transfer_order | inventory_count | shipment | return
    reference_id        BIGINT,
    -- ID del documento origen

    -- Quién realizó el movimiento
    performed_by_type   VARCHAR(10)     NOT NULL DEFAULT 'system',
    -- human | robot | system
    performed_by_id     BIGINT,
    -- employee_id o robot_id según el tipo

    transaction_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    notes               TEXT,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
    -- SIN updated_at: el ledger es inmutable, nunca se edita
);

CREATE INDEX idx_inv_tx_company       ON logistics.inventory_transactions (company_id);
CREATE INDEX idx_inv_tx_product       ON logistics.inventory_transactions (product_id);
CREATE INDEX idx_inv_tx_warehouse     ON logistics.inventory_transactions (warehouse_id);
CREATE INDEX idx_inv_tx_lot           ON logistics.inventory_transactions (lot_id) WHERE lot_id IS NOT NULL;
CREATE INDEX idx_inv_tx_type          ON logistics.inventory_transactions (transaction_type);
CREATE INDEX idx_inv_tx_reference     ON logistics.inventory_transactions (reference_type, reference_id);
CREATE INDEX idx_inv_tx_date          ON logistics.inventory_transactions (transaction_at);
CREATE INDEX idx_inv_tx_operator      ON logistics.inventory_transactions (performed_by_type, performed_by_id);

COMMENT ON TABLE  logistics.inventory_transactions                IS 'LEDGER CENTRAL inmutable. Registra cada movimiento de inventario. Fuente de verdad histórica.';
COMMENT ON COLUMN logistics.inventory_transactions.quantity       IS 'POSITIVO = entrada. NEGATIVO = salida. La suma da el stock actual.';
COMMENT ON COLUMN logistics.inventory_transactions.transaction_type IS 'Tipo semántico del movimiento: receipt, pick, kit_assembly_in/out, transfer, etc.';
COMMENT ON COLUMN logistics.inventory_transactions.performed_by_type IS 'human=empleado, robot=AMR, system=proceso automático del ERP.';

-- ============================================================
-- Conteos físicos de inventario
-- ============================================================
CREATE TABLE logistics.inventory_counts (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    warehouse_id    BIGINT          NOT NULL REFERENCES logistics.warehouses(id) ON DELETE RESTRICT,

    count_number    VARCHAR(50)     NOT NULL,
    count_type      VARCHAR(20)     NOT NULL DEFAULT 'cycle',
    -- cycle = conteo cíclico (parcial, por zona o categoría)
    -- full  = conteo total del almacén

    status          VARCHAR(20)     NOT NULL DEFAULT 'draft',
    -- draft | in_progress | completed | cancelled

    planned_date    DATE,
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,

    -- Resumen
    total_locations     INTEGER,
    locations_counted   INTEGER     NOT NULL DEFAULT 0,
    total_discrepancies INTEGER     NOT NULL DEFAULT 0,

    notes           TEXT,
    created_by      BIGINT,
    -- employee_id que inició el conteo

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, count_number)
);

CREATE INDEX idx_inventory_counts_company ON logistics.inventory_counts (company_id);

CREATE TRIGGER trg_inventory_counts_updated_at
    BEFORE UPDATE ON logistics.inventory_counts
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.inventory_counts IS 'Conteos físicos de inventario: cíclico (parcial) o total del almacén.';

-- ============================================================
-- Detalle del conteo físico por ubicación
-- ============================================================
CREATE TABLE logistics.inventory_count_details (
    id                  BIGSERIAL       PRIMARY KEY,
    count_id            BIGINT          NOT NULL REFERENCES logistics.inventory_counts(id) ON DELETE RESTRICT,
    location_id         BIGINT          NOT NULL REFERENCES logistics.locations(id),
    product_id          BIGINT          NOT NULL REFERENCES logistics.products(id),
    lot_id              BIGINT          REFERENCES logistics.lots(id),
    unit_id             INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),

    -- Cantidades
    quantity_system     NUMERIC(18,4)   NOT NULL,
    -- stock que tenía el sistema antes del conteo
    quantity_counted    NUMERIC(18,4),
    -- lo que encontró el contador
    quantity_difference NUMERIC(18,4)
        GENERATED ALWAYS AS (
            COALESCE(quantity_counted, 0) - quantity_system
        ) STORED,
    -- diferencia: positivo = sobrante, negativo = faltante

    -- Quién contó
    counted_by_type     VARCHAR(10)     DEFAULT 'human',
    counted_by_id       BIGINT,
    counted_at          TIMESTAMPTZ,

    -- Si se generó ajuste
    adjustment_generated    BOOLEAN     NOT NULL DEFAULT FALSE,
    transaction_id          BIGINT,
    -- ID en inventory_transactions del ajuste generado

    notes               TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_count_details_count    ON logistics.inventory_count_details (count_id);
CREATE INDEX idx_count_details_location ON logistics.inventory_count_details (location_id);
CREATE INDEX idx_count_details_product  ON logistics.inventory_count_details (product_id);

CREATE TRIGGER trg_count_details_updated_at
    BEFORE UPDATE ON logistics.inventory_count_details
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.inventory_count_details                    IS 'Detalle por ubicación del conteo físico. Registra diferencias sistema vs. físico.';
COMMENT ON COLUMN logistics.inventory_count_details.quantity_difference IS 'Calculado: contado - sistema. Positivo=sobrante, negativo=faltante.';
