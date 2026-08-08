-- ============================================================
-- mantrasdb | Módulo Logistics
-- Archivo: 04_product_kits.sql
-- Descripción: Kits y bundles — BOM (Bill of Materials).
--
-- Caso Santillana:
--   "Pack Escolar 2025" = Libro A (x1) + Cuaderno B (x2) + CD (x1)
--   Al ensamblar 10 packs:
--     → inventario de Libro A  baja 10
--     → inventario de Cuaderno B baja 20
--     → inventario de CD baja 10
--     → inventario de "Pack Escolar 2025" sube 10
--   Todo queda registrado en logistics.inventory_transactions
--
-- Tipos:
--   PHYSICAL: ensamblaje real, nuevo SKU en inventario
--   VIRTUAL:  agrupación para venta, componentes se descuentan al despachar
-- ============================================================

-- ============================================================
-- Definición del kit (el producto padre ya existe en logistics.products)
-- ============================================================
CREATE TABLE logistics.product_kits (
    id              BIGSERIAL       PRIMARY KEY,
    product_id      BIGINT          NOT NULL REFERENCES logistics.products(id) ON DELETE RESTRICT,
    -- el producto que es el kit (is_kit=TRUE en logistics.products)
    kit_type_id     INTEGER         NOT NULL REFERENCES logistics.kit_types(id),
    -- physical | virtual

    -- Solo para kits físicos
    assembly_time_minutes INTEGER,
    -- tiempo estimado de ensamblaje en minutos
    assembly_cost   NUMERIC(18,4),
    -- costo adicional de mano de obra por ensamblaje

    notes           TEXT,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (product_id)
    -- un producto solo puede ser definido como kit una vez
);

CREATE TRIGGER trg_product_kits_updated_at
    BEFORE UPDATE ON logistics.product_kits
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.product_kits               IS 'Define que un producto es un kit/bundle. El producto padre vive en logistics.products (is_kit=TRUE).';
COMMENT ON COLUMN logistics.product_kits.assembly_cost IS 'Costo adicional de mano de obra o proceso de ensamblaje, aparte del costo de los componentes.';

-- ============================================================
-- Componentes del kit — BOM (Bill of Materials)
-- ============================================================
CREATE TABLE logistics.product_kit_components (
    id                  BIGSERIAL       PRIMARY KEY,
    kit_id              BIGINT          NOT NULL REFERENCES logistics.product_kits(id) ON DELETE RESTRICT,
    component_product_id BIGINT         NOT NULL REFERENCES logistics.products(id) ON DELETE RESTRICT,
    -- producto componente (no puede ser otro kit físico en la misma línea)
    component_variant_id BIGINT         REFERENCES logistics.product_variants(id),
    -- variante específica del componente (opcional)

    quantity            NUMERIC(18,4)   NOT NULL,
    -- cantidad de este componente por cada unidad de kit
    unit_id             INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),
    -- unidad de la cantidad (UN, KG, LT, etc.)

    is_substitutable    BOOLEAN         NOT NULL DEFAULT FALSE,
    -- TRUE = puede sustituirse por otro producto si hay falta de stock
    substitute_product_id BIGINT        REFERENCES logistics.products(id),
    -- producto sustituto si is_substitutable=TRUE

    sequence            INTEGER         NOT NULL DEFAULT 1,
    -- orden de ensamblaje
    notes               TEXT,

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (kit_id, component_product_id, component_variant_id)
);

CREATE INDEX idx_kit_components_kit       ON logistics.product_kit_components (kit_id);
CREATE INDEX idx_kit_components_component ON logistics.product_kit_components (component_product_id);

CREATE TRIGGER trg_kit_components_updated_at
    BEFORE UPDATE ON logistics.product_kit_components
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.product_kit_components              IS 'BOM del kit: qué componentes lleva y en qué cantidad. Ej: Pack Escolar = Libro(x1) + Cuaderno(x2) + CD(x1).';
COMMENT ON COLUMN logistics.product_kit_components.quantity     IS 'Cantidad de este componente por cada unidad de kit ensamblado.';
COMMENT ON COLUMN logistics.product_kit_components.is_substitutable IS 'Si TRUE, se puede usar substitute_product_id cuando falta el componente original.';

-- ============================================================
-- Órdenes de ensamblaje / desarmado de kits
-- ============================================================
CREATE TABLE logistics.kit_assembly_orders (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    kit_id              BIGINT          NOT NULL REFERENCES logistics.product_kits(id) ON DELETE RESTRICT,
    warehouse_id        BIGINT          NOT NULL,
    -- REFERENCES logistics.warehouses(id) — tabla creada en 07_warehouses.sql

    order_number        VARCHAR(50)     NOT NULL,
    operation_type      VARCHAR(20)     NOT NULL DEFAULT 'assembly',
    -- assembly = ensamblar (componentes → kit)
    -- disassembly = desarmar (kit → componentes)

    quantity_planned    NUMERIC(18,4)   NOT NULL,
    -- cuántos kits se van a ensamblar (o desarmar)
    quantity_completed  NUMERIC(18,4)   NOT NULL DEFAULT 0,

    -- Fechas
    planned_date        DATE,
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,

    -- Operador
    performed_by_type   VARCHAR(10)     NOT NULL DEFAULT 'human',
    -- human | robot | system
    performed_by_id     BIGINT,
    -- employee_id o robot_id según performed_by_type

    status              VARCHAR(30)     NOT NULL DEFAULT 'draft',
    -- draft | in_progress | completed | cancelled
    notes               TEXT,

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, order_number)
);

CREATE INDEX idx_kit_assembly_orders_company ON logistics.kit_assembly_orders (company_id);
CREATE INDEX idx_kit_assembly_orders_kit     ON logistics.kit_assembly_orders (kit_id);

CREATE TRIGGER trg_kit_assembly_orders_updated_at
    BEFORE UPDATE ON logistics.kit_assembly_orders
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.kit_assembly_orders               IS 'Ordenes de ensamblaje (componentes → kit) o desarmado (kit → componentes).';
COMMENT ON COLUMN logistics.kit_assembly_orders.operation_type IS 'assembly: componentes consumidos, kit ingresa al inventario. disassembly: kit sale, componentes regresan.';
COMMENT ON COLUMN logistics.kit_assembly_orders.performed_by_type IS 'human=empleado, robot=AMR, system=proceso automático.';

-- ============================================================
-- Líneas de la orden de ensamblaje (detalle de movimientos)
-- ============================================================
CREATE TABLE logistics.kit_assembly_order_lines (
    id                  BIGSERIAL       PRIMARY KEY,
    assembly_order_id   BIGINT          NOT NULL REFERENCES logistics.kit_assembly_orders(id) ON DELETE RESTRICT,
    component_product_id BIGINT         NOT NULL REFERENCES logistics.products(id),

    quantity_planned    NUMERIC(18,4)   NOT NULL,
    -- cantidad de componente requerida según BOM × cantidad de kits
    quantity_actual     NUMERIC(18,4),
    -- cantidad real consumida (puede diferir si hubo sustitución o merma)
    unit_id             INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),

    lot_id              BIGINT,
    -- REFERENCES logistics.lots(id) — se agrega después
    location_id         BIGINT,
    -- REFERENCES logistics.locations(id) — se agrega después

    notes               TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_kit_assembly_lines_order ON logistics.kit_assembly_order_lines (assembly_order_id);

COMMENT ON TABLE logistics.kit_assembly_order_lines IS 'Detalle de componentes por orden de ensamblaje: qué se tomó, de qué lote y ubicación.';
