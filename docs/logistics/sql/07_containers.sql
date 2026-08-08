-- ============================================================
-- mantrasdb | Módulo Logistics
-- Archivo: 07_containers.sql
-- Descripción: Contenedores y pallets — trazabilidad de unidades
--              de manipulación (SSCC, LP, LPN).
--
-- Cubre: cajas, pallets, contenedores marítimos 20ft/40ft,
--        bolsas, jaulas, etc.
-- Cada contenedor tiene un código único (LPN = License Plate Number)
-- que puede pistoliarse para ver su contenido completo.
-- ============================================================

-- ============================================================
-- Tipos de contenedor
-- ============================================================
CREATE TABLE logistics.container_types (
    id          SERIAL          PRIMARY KEY,
    code        VARCHAR(30)     NOT NULL UNIQUE,
    name        VARCHAR(100)    NOT NULL,
    description TEXT,
    -- Dimensiones estándar del tipo
    length_cm   NUMERIC(8,2),
    width_cm    NUMERIC(8,2),
    height_cm   NUMERIC(8,2),
    max_weight_kg NUMERIC(10,3)
);

INSERT INTO logistics.container_types (code, name, description, max_weight_kg) VALUES
('PALLET_WOOD',  'Pallet de madera',          'Pallet estándar 1.2×1m', 1000),
('PALLET_PLAST', 'Pallet de plástico',         'Pallet plástico reutilizable', 1200),
('BOX_CARDBOARD','Caja de cartón',             'Caja corrugada de cartón', 30),
('BOX_PLASTIC',  'Caja plástica (tote)',       'Caja plástica reutilizable para picking', 25),
('BAG',          'Bolsa',                      'Bolsa de polietileno o tela', 10),
('DRUM',         'Tambor / barril',            'Tambor metálico o plástico', 300),
('CAGE',         'Jaula metálica',             'Jaula de metal con ruedas', 500),
('CRATE',        'Cajón de madera',            'Cajón de madera para exportación', 200),
('CONTAINER_20', 'Contenedor marítimo 20 pies','Contenedor ISO 20ft', 28000),
('CONTAINER_40', 'Contenedor marítimo 40 pies','Contenedor ISO 40ft', 30480),
('SACK',         'Saco / costal',              'Saco de yute o polipropileno', 50),
('IBC',          'IBC / Contenedor intermedio','Intermediate Bulk Container 1000L', 1300);

COMMENT ON TABLE logistics.container_types IS 'Tipos de unidad de manipulación: pallets, cajas, tambores, contenedores marítimos, etc.';

-- ============================================================
-- Contenedores individuales
-- ============================================================
CREATE TABLE logistics.containers (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    container_type_id   INTEGER         NOT NULL REFERENCES logistics.container_types(id),
    warehouse_id        BIGINT          REFERENCES logistics.warehouses(id),
    location_id         BIGINT          REFERENCES logistics.locations(id),

    -- Identificación
    lpn                 VARCHAR(100)    NOT NULL,
    -- License Plate Number — código único pistoliable
    sscc                VARCHAR(20),
    -- Serial Shipping Container Code (estándar GS1, 18 dígitos)
    external_reference  VARCHAR(200),
    -- referencia del proveedor o transportista

    -- Estado
    status              VARCHAR(20)     NOT NULL DEFAULT 'available',
    -- available | in_use | in_transit | damaged | retired

    -- Dimensiones
    tare_weight_kg      NUMERIC(10,3),
    -- peso vacío del contenedor
    gross_weight_kg     NUMERIC(10,3),
    -- peso bruto incluyendo contenido
    max_weight_kg       NUMERIC(10,3),

    -- Temperatura (para contenedores refrigerados)
    is_temperature_controlled   BOOLEAN NOT NULL DEFAULT FALSE,
    temperature_celsius         NUMERIC(5,2),

    -- Trazabilidad
    seal_number         VARCHAR(100),
    -- número de precinto/sello (para contenedores marítimos)

    -- Referencia al documento que creó este contenedor
    created_from_type   VARCHAR(50),
    -- receipt | pack_task | transfer | manual
    created_from_id     BIGINT,

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    notes               TEXT,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, lpn)
);

CREATE INDEX idx_containers_company   ON logistics.containers (company_id);
CREATE INDEX idx_containers_warehouse ON logistics.containers (warehouse_id);
CREATE INDEX idx_containers_location  ON logistics.containers (location_id);
CREATE INDEX idx_containers_status    ON logistics.containers (status);

CREATE TRIGGER trg_containers_updated_at
    BEFORE UPDATE ON logistics.containers
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.containers      IS 'Contenedores físicos: cajas, pallets, contenedores marítimos. Cada uno tiene un LPN único.';
COMMENT ON COLUMN logistics.containers.lpn  IS 'License Plate Number — código único pistoliable. Muestra el contenido completo del contenedor.';
COMMENT ON COLUMN logistics.containers.sscc IS 'Serial Shipping Container Code estándar GS1 (18 dígitos). Para intercambio con partners externos.';

-- ============================================================
-- Contenido del contenedor (qué hay dentro)
-- ============================================================
CREATE TABLE logistics.container_contents (
    id                  BIGSERIAL       PRIMARY KEY,
    container_id        BIGINT          NOT NULL REFERENCES logistics.containers(id) ON DELETE RESTRICT,
    product_id          BIGINT          NOT NULL REFERENCES logistics.products(id),
    lot_id              BIGINT          REFERENCES logistics.lots(id),
    serial_number_id    BIGINT          REFERENCES logistics.serial_numbers(id),
    unit_id             INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),

    quantity            NUMERIC(18,4)   NOT NULL,

    -- Referencia al movimiento que puso esto aquí
    added_from_type     VARCHAR(50),
    -- receipt_line | pick_task | pack_task | manual
    added_from_id       BIGINT,

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_container_contents_container ON logistics.container_contents (container_id);
CREATE INDEX idx_container_contents_product   ON logistics.container_contents (product_id);

COMMENT ON TABLE logistics.container_contents IS 'Contenido actual de cada contenedor: producto, lote y cantidad.';

-- ============================================================
-- Movimientos de contenedor (trazabilidad de dónde ha estado)
-- ============================================================
CREATE TABLE logistics.container_movements (
    id                  BIGSERIAL       PRIMARY KEY,
    container_id        BIGINT          NOT NULL REFERENCES logistics.containers(id),

    from_location_id    BIGINT          REFERENCES logistics.locations(id),
    to_location_id      BIGINT          REFERENCES logistics.locations(id),
    from_warehouse_id   BIGINT          REFERENCES logistics.warehouses(id),
    to_warehouse_id     BIGINT          REFERENCES logistics.warehouses(id),

    movement_type       VARCHAR(30)     NOT NULL,
    -- receive | putaway | pick | transfer | ship | return

    -- Quién movió el contenedor
    performed_by_type   VARCHAR(10)     NOT NULL DEFAULT 'human',
    -- human | robot | system
    performed_by_id     BIGINT,

    -- Referencia
    reference_type      VARCHAR(50),
    reference_id        BIGINT,

    moved_at            TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    notes               TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_container_movements_container ON logistics.container_movements (container_id);
CREATE INDEX idx_container_movements_date      ON logistics.container_movements (moved_at);

COMMENT ON TABLE logistics.container_movements IS 'Historial de movimientos de cada contenedor. Trazabilidad completa de dónde ha estado.';
