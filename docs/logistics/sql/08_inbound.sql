-- ============================================================
-- mantrasdb | Módulo Logistics
-- Archivo: 08_inbound.sql
-- Descripción: Flujo de entrada — órdenes de compra, recepción,
--              inspección de calidad, putaway y devoluciones
--              a proveedor.
--
-- Flujo:
--   purchase_order → receipt → quality_inspection → putaway_tasks
--   → inventory (stock actualizado) → inventory_transactions (ledger)
-- ============================================================

-- ============================================================
-- Órdenes de compra
-- ============================================================
CREATE TABLE logistics.purchase_orders (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    supplier_id         BIGINT          NOT NULL REFERENCES logistics.suppliers(id) ON DELETE RESTRICT,
    warehouse_id        BIGINT          NOT NULL REFERENCES logistics.warehouses(id) ON DELETE RESTRICT,
    order_status_id     INTEGER         NOT NULL REFERENCES logistics.order_statuses(id),
    order_type_id       INTEGER         NOT NULL REFERENCES logistics.order_types(id),

    -- Número y referencia
    order_number        VARCHAR(50)     NOT NULL,
    supplier_reference  VARCHAR(100),
    -- número de referencia del proveedor (su orden de venta)

    -- Fechas
    order_date          DATE            NOT NULL DEFAULT CURRENT_DATE,
    expected_date       DATE,
    -- fecha esperada de llegada
    confirmed_date      DATE,
    -- fecha confirmada por el proveedor

    -- Moneda y totales
    currency            VARCHAR(10)     NOT NULL DEFAULT 'PEN',
    subtotal            NUMERIC(18,4)   NOT NULL DEFAULT 0,
    tax_amount          NUMERIC(18,4)   NOT NULL DEFAULT 0,
    discount_amount     NUMERIC(18,4)   NOT NULL DEFAULT 0,
    total_amount        NUMERIC(18,4)   NOT NULL DEFAULT 0,

    -- Condiciones
    payment_terms       VARCHAR(100),
    incoterm            VARCHAR(10),
    -- EXW | FOB | CIF | DDP | DAP | FCA
    shipping_address    TEXT,

    -- Quién aprobó
    approved_by         BIGINT,
    -- employee_id
    approved_at         TIMESTAMPTZ,

    notes               TEXT,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, order_number)
);

CREATE INDEX idx_purchase_orders_company   ON logistics.purchase_orders (company_id);
CREATE INDEX idx_purchase_orders_supplier  ON logistics.purchase_orders (supplier_id);
CREATE INDEX idx_purchase_orders_status    ON logistics.purchase_orders (order_status_id);
CREATE INDEX idx_purchase_orders_date      ON logistics.purchase_orders (order_date);

CREATE TRIGGER trg_purchase_orders_updated_at
    BEFORE UPDATE ON logistics.purchase_orders
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.purchase_orders IS 'Órdenes de compra a proveedores. Punto de inicio del flujo inbound.';

-- ============================================================
-- Líneas de orden de compra
-- ============================================================
CREATE TABLE logistics.purchase_order_lines (
    id                  BIGSERIAL       PRIMARY KEY,
    purchase_order_id   BIGINT          NOT NULL REFERENCES logistics.purchase_orders(id) ON DELETE RESTRICT,
    product_id          BIGINT          NOT NULL REFERENCES logistics.products(id) ON DELETE RESTRICT,
    variant_id          BIGINT          REFERENCES logistics.product_variants(id),
    unit_id             INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),

    line_number         INTEGER         NOT NULL,
    supplier_sku        VARCHAR(150),

    quantity_ordered    NUMERIC(18,4)   NOT NULL,
    quantity_received   NUMERIC(18,4)   NOT NULL DEFAULT 0,
    quantity_pending    NUMERIC(18,4)
        GENERATED ALWAYS AS (quantity_ordered - quantity_received) STORED,

    unit_price          NUMERIC(18,6)   NOT NULL,
    discount_pct        NUMERIC(5,2)    NOT NULL DEFAULT 0,
    tax_pct             NUMERIC(5,2)    NOT NULL DEFAULT 0,
    line_total          NUMERIC(18,4)
        GENERATED ALWAYS AS (
            ROUND((quantity_ordered * unit_price * (1 - discount_pct/100))::NUMERIC, 4)
        ) STORED,

    expected_date       DATE,
    notes               TEXT,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (purchase_order_id, line_number)
);

CREATE INDEX idx_po_lines_order   ON logistics.purchase_order_lines (purchase_order_id);
CREATE INDEX idx_po_lines_product ON logistics.purchase_order_lines (product_id);

CREATE TRIGGER trg_po_lines_updated_at
    BEFORE UPDATE ON logistics.purchase_order_lines
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.purchase_order_lines                IS 'Líneas de la orden de compra: producto, cantidad y precio.';
COMMENT ON COLUMN logistics.purchase_order_lines.quantity_pending IS 'Calculado: ordenado - recibido. Pendiente de recibir.';

-- ============================================================
-- Recepciones (GRN — Goods Receipt Note)
-- ============================================================
CREATE TABLE logistics.receipts (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    purchase_order_id   BIGINT          NOT NULL REFERENCES logistics.purchase_orders(id) ON DELETE RESTRICT,
    warehouse_id        BIGINT          NOT NULL REFERENCES logistics.warehouses(id) ON DELETE RESTRICT,
    dock_id             BIGINT          REFERENCES logistics.docks(id),
    receipt_status_id   INTEGER         NOT NULL REFERENCES logistics.receipt_statuses(id),

    receipt_number      VARCHAR(50)     NOT NULL,
    -- Documentos del proveedor
    supplier_invoice    VARCHAR(100),
    supplier_delivery_note VARCHAR(100),
    -- guía de remisión del proveedor

    -- Fechas
    scheduled_date      DATE,
    received_date       DATE,
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,

    -- Vehículo
    truck_plate         VARCHAR(30),
    driver_name         VARCHAR(150),
    driver_document     VARCHAR(50),
    -- DNI/CE del conductor

    -- Quién recibió
    received_by         BIGINT,
    -- employee_id

    notes               TEXT,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, receipt_number)
);

CREATE INDEX idx_receipts_company  ON logistics.receipts (company_id);
CREATE INDEX idx_receipts_po       ON logistics.receipts (purchase_order_id);
CREATE INDEX idx_receipts_status   ON logistics.receipts (receipt_status_id);

CREATE TRIGGER trg_receipts_updated_at
    BEFORE UPDATE ON logistics.receipts
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.receipts IS 'Recepciones físicas (GRN). Una PO puede tener múltiples recepciones parciales.';

-- ============================================================
-- Líneas de recepción
-- ============================================================
CREATE TABLE logistics.receipt_lines (
    id                      BIGSERIAL       PRIMARY KEY,
    receipt_id              BIGINT          NOT NULL REFERENCES logistics.receipts(id) ON DELETE RESTRICT,
    purchase_order_line_id  BIGINT          NOT NULL REFERENCES logistics.purchase_order_lines(id),
    product_id              BIGINT          NOT NULL REFERENCES logistics.products(id),
    lot_id                  BIGINT          REFERENCES logistics.lots(id),
    unit_id                 INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),

    line_number             INTEGER         NOT NULL,
    quantity_received       NUMERIC(18,4)   NOT NULL,
    quantity_accepted       NUMERIC(18,4)   NOT NULL DEFAULT 0,
    -- aprobada en inspección de calidad
    quantity_rejected       NUMERIC(18,4)   NOT NULL DEFAULT 0,
    -- rechazada en inspección de calidad

    -- Condición al recibir
    condition               VARCHAR(20)     NOT NULL DEFAULT 'good',
    -- good | damaged | partial | expired

    -- Contenedor/pallet en que llegó
    container_id            BIGINT          REFERENCES logistics.containers(id),

    notes                   TEXT,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_receipt_lines_receipt  ON logistics.receipt_lines (receipt_id);
CREATE INDEX idx_receipt_lines_product  ON logistics.receipt_lines (product_id);

CREATE TRIGGER trg_receipt_lines_updated_at
    BEFORE UPDATE ON logistics.receipt_lines
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.receipt_lines IS 'Detalle de cada línea recibida: producto, lote, cantidad aceptada y rechazada.';

-- ============================================================
-- Inspecciones de calidad
-- ============================================================
CREATE TABLE logistics.quality_inspections (
    id                  BIGSERIAL       PRIMARY KEY,
    receipt_id          BIGINT          NOT NULL REFERENCES logistics.receipts(id) ON DELETE RESTRICT,
    inspection_status_id INTEGER        NOT NULL REFERENCES logistics.inspection_statuses(id),

    inspection_number   VARCHAR(50)     NOT NULL,
    inspection_type     VARCHAR(30)     NOT NULL DEFAULT 'incoming',
    -- incoming | returns | periodic

    inspected_by        BIGINT,
    -- employee_id del inspector
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,

    -- Resultado global
    pass_rate_pct       NUMERIC(5,2),
    -- porcentaje aprobado

    notes               TEXT,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (receipt_id)
    -- una recepción tiene una sola inspección
);

CREATE TRIGGER trg_quality_inspections_updated_at
    BEFORE UPDATE ON logistics.quality_inspections
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.quality_inspections IS 'Inspección de calidad por cada recepción. Puede aprobar o rechazar parcialmente.';

-- ============================================================
-- Líneas de inspección (por producto/lote)
-- ============================================================
CREATE TABLE logistics.quality_inspection_lines (
    id                      BIGSERIAL       PRIMARY KEY,
    inspection_id           BIGINT          NOT NULL REFERENCES logistics.quality_inspections(id),
    receipt_line_id         BIGINT          NOT NULL REFERENCES logistics.receipt_lines(id),

    quantity_inspected      NUMERIC(18,4)   NOT NULL,
    quantity_approved       NUMERIC(18,4)   NOT NULL DEFAULT 0,
    quantity_rejected       NUMERIC(18,4)   NOT NULL DEFAULT 0,
    quantity_quarantine     NUMERIC(18,4)   NOT NULL DEFAULT 0,

    rejection_reason        VARCHAR(200),
    -- damage | expiry | wrong_product | wrong_quantity | contamination | other

    photo_url               VARCHAR(500),
    -- foto de la mercadería inspeccionada (diferenciador)

    notes                   TEXT,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_qi_lines_inspection ON logistics.quality_inspection_lines (inspection_id);

COMMENT ON TABLE logistics.quality_inspection_lines IS 'Detalle por línea de la inspección: aprobado, rechazado y en cuarentena.';

-- ============================================================
-- Tareas de putaway (guardado en ubicación)
-- ============================================================
CREATE TABLE logistics.putaway_tasks (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    receipt_line_id     BIGINT          NOT NULL REFERENCES logistics.receipt_lines(id),
    warehouse_id        BIGINT          NOT NULL REFERENCES logistics.warehouses(id),
    product_id          BIGINT          NOT NULL REFERENCES logistics.products(id),
    lot_id              BIGINT          REFERENCES logistics.lots(id),
    unit_id             INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),

    -- Ubicaciones
    from_location_id    BIGINT          REFERENCES logistics.locations(id),
    -- zona de recepción/staging
    suggested_location_id BIGINT        REFERENCES logistics.locations(id),
    -- sugerida por la regla de putaway
    actual_location_id  BIGINT          REFERENCES logistics.locations(id),
    -- donde realmente se guardó (puede diferir de la sugerida)

    quantity            NUMERIC(18,4)   NOT NULL,
    container_id        BIGINT          REFERENCES logistics.containers(id),

    status              VARCHAR(20)     NOT NULL DEFAULT 'pending',
    -- pending | assigned | in_progress | completed | cancelled

    -- Quién ejecutó
    performed_by_type   VARCHAR(10)     NOT NULL DEFAULT 'human',
    performed_by_id     BIGINT,

    assigned_at         TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    notes               TEXT,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_putaway_tasks_company  ON logistics.putaway_tasks (company_id);
CREATE INDEX idx_putaway_tasks_status   ON logistics.putaway_tasks (status) WHERE status IN ('pending','in_progress');

CREATE TRIGGER trg_putaway_tasks_updated_at
    BEFORE UPDATE ON logistics.putaway_tasks
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.putaway_tasks IS 'Tareas de guardado tras recepción. El sistema sugiere la ubicación óptima según las reglas de putaway.';

-- ============================================================
-- Reglas de putaway (dónde guardar cada tipo de producto)
-- ============================================================
CREATE TABLE logistics.putaway_rules (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    warehouse_id        BIGINT          NOT NULL REFERENCES logistics.warehouses(id),

    -- Criterios de aplicación (del más específico al más general)
    product_id          BIGINT          REFERENCES logistics.products(id),
    category_id         BIGINT          REFERENCES logistics.product_categories(id),
    supplier_id         BIGINT          REFERENCES logistics.suppliers(id),

    -- Destino
    zone_id             BIGINT          REFERENCES logistics.warehouse_zones(id),
    location_id         BIGINT          REFERENCES logistics.locations(id),
    -- si se especifica location_id, va directo ahí

    -- Estrategia
    strategy            VARCHAR(20)     NOT NULL DEFAULT 'FEFO',
    -- FIFO | FEFO | NEAREST | FIXED
    priority            INTEGER         NOT NULL DEFAULT 100,
    -- menor número = mayor prioridad

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_putaway_rules_company ON logistics.putaway_rules (company_id, warehouse_id);

CREATE TRIGGER trg_putaway_rules_updated_at
    BEFORE UPDATE ON logistics.putaway_rules
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.putaway_rules IS 'Reglas de guardado automático: qué producto va a qué zona/ubicación al recibirlo.';

-- ============================================================
-- Devoluciones a proveedor
-- ============================================================
CREATE TABLE logistics.supplier_returns (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    supplier_id         BIGINT          NOT NULL REFERENCES logistics.suppliers(id),
    warehouse_id        BIGINT          NOT NULL REFERENCES logistics.warehouses(id),
    receipt_id          BIGINT          REFERENCES logistics.receipts(id),
    -- recepción origen de la devolución (si aplica)

    return_number       VARCHAR(50)     NOT NULL,
    return_reason       VARCHAR(200)    NOT NULL,
    -- damage | wrong_product | excess | quality | expired

    status              VARCHAR(20)     NOT NULL DEFAULT 'draft',
    -- draft | approved | shipped | completed | cancelled

    approved_by         BIGINT,
    approved_at         TIMESTAMPTZ,
    shipped_at          TIMESTAMPTZ,

    notes               TEXT,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, return_number)
);

CREATE TRIGGER trg_supplier_returns_updated_at
    BEFORE UPDATE ON logistics.supplier_returns
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.supplier_returns IS 'Devoluciones de mercadería al proveedor por daño, exceso, error o calidad.';

-- ============================================================
-- Líneas de devolución a proveedor
-- ============================================================
CREATE TABLE logistics.supplier_return_lines (
    id                  BIGSERIAL       PRIMARY KEY,
    return_id           BIGINT          NOT NULL REFERENCES logistics.supplier_returns(id),
    product_id          BIGINT          NOT NULL REFERENCES logistics.products(id),
    lot_id              BIGINT          REFERENCES logistics.lots(id),
    unit_id             INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),
    from_location_id    BIGINT          REFERENCES logistics.locations(id),

    quantity            NUMERIC(18,4)   NOT NULL,
    unit_cost           NUMERIC(18,6),

    notes               TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_supplier_return_lines_return ON logistics.supplier_return_lines (return_id);

COMMENT ON TABLE logistics.supplier_return_lines IS 'Detalle de productos devueltos al proveedor por línea.';
