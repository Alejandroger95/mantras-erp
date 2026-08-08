-- ============================================================
-- mantrasdb | Módulo Logistics
-- Archivo: 05_warehouses_locations.sql
-- Descripción: Estructura física del almacén — almacenes,
--              zonas, pasillos, tipos de rack y ubicaciones.
--
-- Jerarquía:
--   warehouse → zones → aisles → locations (slots/bins)
--
-- Ejemplo de dirección de ubicación:
--   ALM-01 > Zona A > Pasillo 3 > Rack 05 > Nivel 2 > Posición 01
--   Código: A-03-05-02-01
-- ============================================================

-- ============================================================
-- Almacenes
-- ============================================================
CREATE TABLE logistics.warehouses (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    code            VARCHAR(20)     NOT NULL,
    name            VARCHAR(200)    NOT NULL,
    description     TEXT,

    -- Dirección física
    address         VARCHAR(300),
    city            VARCHAR(100),
    state           VARCHAR(100),
    country         VARCHAR(100)    NOT NULL DEFAULT 'PE',
    zip_code        VARCHAR(20),

    -- Geolocalización (para tracking y mapas)
    latitude        NUMERIC(10,7),
    longitude       NUMERIC(10,7),

    -- Capacidad
    total_area_m2   NUMERIC(10,2),
    storage_area_m2 NUMERIC(10,2),
    max_weight_ton  NUMERIC(10,2),

    -- Configuración
    timezone        VARCHAR(60)     NOT NULL DEFAULT 'America/Lima',
    currency        VARCHAR(10)     NOT NULL DEFAULT 'PEN',

    -- Tipo de almacén
    warehouse_type  VARCHAR(30)     NOT NULL DEFAULT 'standard',
    -- standard | refrigerated | frozen | hazmat | bonded | virtual
    -- bonded = almacén aduanero

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    notes           TEXT,

    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE INDEX idx_warehouses_company ON logistics.warehouses (company_id);

CREATE TRIGGER trg_warehouses_updated_at
    BEFORE UPDATE ON logistics.warehouses
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.warehouses IS 'Almacenes físicos o virtuales. Multi-almacén por empresa.';

-- ============================================================
-- Muelles de carga/descarga (docks)
-- ============================================================
CREATE TABLE logistics.docks (
    id              BIGSERIAL       PRIMARY KEY,
    warehouse_id    BIGINT          NOT NULL REFERENCES logistics.warehouses(id) ON DELETE RESTRICT,

    dock_number     VARCHAR(20)     NOT NULL,
    name            VARCHAR(100),
    dock_type       VARCHAR(20)     NOT NULL DEFAULT 'both',
    -- inbound | outbound | both

    -- Capacidad
    max_truck_length_m  NUMERIC(6,2),
    has_dock_leveler    BOOLEAN     NOT NULL DEFAULT FALSE,
    has_dock_seal       BOOLEAN     NOT NULL DEFAULT FALSE,
    -- sello térmico para cámaras de frío

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    notes           TEXT,

    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (warehouse_id, dock_number)
);

CREATE INDEX idx_docks_warehouse ON logistics.docks (warehouse_id);

CREATE TRIGGER trg_docks_updated_at
    BEFORE UPDATE ON logistics.docks
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.docks IS 'Muelles físicos de carga y descarga. Cada muelle tiene citas (dock_appointments).';

-- ============================================================
-- Zonas del almacén
-- ============================================================
CREATE TABLE logistics.warehouse_zones (
    id              BIGSERIAL       PRIMARY KEY,
    warehouse_id    BIGINT          NOT NULL REFERENCES logistics.warehouses(id) ON DELETE RESTRICT,
    zone_type_id    INTEGER         NOT NULL REFERENCES logistics.zone_types(id),

    code            VARCHAR(20)     NOT NULL,
    name            VARCHAR(150)    NOT NULL,
    description     TEXT,

    -- Control de temperatura (para zonas refrigeradas)
    has_temperature_control BOOLEAN NOT NULL DEFAULT FALSE,
    min_temp_celsius        NUMERIC(5,2),
    max_temp_celsius        NUMERIC(5,2),

    -- Área
    area_m2         NUMERIC(10,2),

    -- Secuencia para picking (orden de recorrido)
    picking_sequence INTEGER         NOT NULL DEFAULT 1,

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (warehouse_id, code)
);

CREATE INDEX idx_warehouse_zones_warehouse ON logistics.warehouse_zones (warehouse_id);

CREATE TRIGGER trg_warehouse_zones_updated_at
    BEFORE UPDATE ON logistics.warehouse_zones
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.warehouse_zones IS 'Zonas dentro del almacén: recepción, almacenaje, picking, despacho, cuarentena.';

-- ============================================================
-- Tipos de rack
-- ============================================================
CREATE TABLE logistics.rack_types (
    id          SERIAL          PRIMARY KEY,
    code        VARCHAR(50)     NOT NULL UNIQUE,
    -- selective | drive_in | push_back | cantilever | mezzanine | pallet_flow
    name        VARCHAR(100)    NOT NULL,
    description TEXT,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

INSERT INTO logistics.rack_types (code, name, description) VALUES
    ('selective',   'Rack selectivo',   'Acceso directo a cada pallet. El más común.'),
    ('drive_in',    'Drive-in',         'Alta densidad, LIFO. El montacargas entra al rack.'),
    ('push_back',   'Push-back',        'Alta densidad, LIFO. Carril inclinado con rodillos.'),
    ('cantilever',  'Cantilever',       'Para materiales largos: tuberías, madera, perfiles.'),
    ('mezzanine',   'Mezzanine',        'Plataforma elevada para picking manual liviano.'),
    ('pallet_flow', 'Pallet flow',      'Alta densidad, FIFO. Carril dinámico por gravedad.');

COMMENT ON TABLE logistics.rack_types IS 'Tipos de sistema de rack en el almacén.';

-- ============================================================
-- Pasillos
-- ============================================================
CREATE TABLE logistics.aisles (
    id              BIGSERIAL       PRIMARY KEY,
    zone_id         BIGINT          NOT NULL REFERENCES logistics.warehouse_zones(id) ON DELETE RESTRICT,
    rack_type_id    INTEGER         REFERENCES logistics.rack_types(id),

    code            VARCHAR(20)     NOT NULL,
    name            VARCHAR(100),

    -- Dimensiones
    length_m        NUMERIC(8,2),
    width_m         NUMERIC(8,2),
    height_m        NUMERIC(8,2),

    -- Secuencia de picking en la zona
    picking_sequence INTEGER        NOT NULL DEFAULT 1,

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (zone_id, code)
);

CREATE INDEX idx_aisles_zone ON logistics.aisles (zone_id);

CREATE TRIGGER trg_aisles_updated_at
    BEFORE UPDATE ON logistics.aisles
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.aisles IS 'Pasillos dentro de una zona. Cada pasillo puede tener su tipo de rack.';

-- ============================================================
-- Ubicaciones / slots / bins
-- ============================================================
CREATE TABLE logistics.locations (
    id                  BIGSERIAL       PRIMARY KEY,
    aisle_id            BIGINT          REFERENCES logistics.aisles(id),
    zone_id             BIGINT          NOT NULL REFERENCES logistics.warehouse_zones(id) ON DELETE RESTRICT,
    warehouse_id        BIGINT          NOT NULL REFERENCES logistics.warehouses(id) ON DELETE RESTRICT,
    location_type_id    INTEGER         NOT NULL REFERENCES logistics.location_types(id),

    -- Código único de ubicación dentro del almacén
    code                VARCHAR(50)     NOT NULL,
    -- Ej: A-03-05-02-01 (zona-pasillo-rack-nivel-posición)
    name                VARCHAR(150),

    -- Coordenadas en el rack
    rack                VARCHAR(10),    -- número de rack en el pasillo
    level               SMALLINT,       -- nivel / altura (1=piso, 2,3,4...)
    position            SMALLINT,       -- posición horizontal en el nivel

    -- Dimensiones y capacidad
    max_weight_kg       NUMERIC(10,3),
    max_volume_m3       NUMERIC(10,6),
    length_cm           NUMERIC(8,2),
    width_cm            NUMERIC(8,2),
    height_cm           NUMERIC(8,2),

    -- Control de temperatura (hereda de la zona pero puede especializarse)
    has_temperature_control BOOLEAN     NOT NULL DEFAULT FALSE,
    min_temp_celsius    NUMERIC(5,2),
    max_temp_celsius    NUMERIC(5,2),

    -- Restricciones de producto
    is_mixed_products   BOOLEAN         NOT NULL DEFAULT TRUE,
    -- FALSE = solo un SKU por ubicación
    is_mixed_lots       BOOLEAN         NOT NULL DEFAULT FALSE,
    -- FALSE = solo un lote por ubicación (recomendado para FEFO)

    -- Estado operativo
    is_blocked          BOOLEAN         NOT NULL DEFAULT FALSE,
    block_reason        TEXT,

    -- Secuencia de picking (para optimizar el recorrido)
    picking_sequence    INTEGER         NOT NULL DEFAULT 1,

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    notes               TEXT,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (warehouse_id, code)
);

CREATE INDEX idx_locations_warehouse  ON logistics.locations (warehouse_id);
CREATE INDEX idx_locations_zone       ON logistics.locations (zone_id);
CREATE INDEX idx_locations_aisle      ON logistics.locations (aisle_id);
CREATE INDEX idx_locations_active     ON logistics.locations (warehouse_id) WHERE is_active = TRUE AND is_blocked = FALSE;

CREATE TRIGGER trg_locations_updated_at
    BEFORE UPDATE ON logistics.locations
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.locations                      IS 'Ubicaciones físicas (slots/bins) dentro del almacén. Nivel más granular del almacén.';
COMMENT ON COLUMN logistics.locations.code                 IS 'Código único en el almacén. Ej: A-03-05-02-01 (zona-pasillo-rack-nivel-posición).';
COMMENT ON COLUMN logistics.locations.is_mixed_lots        IS 'FALSE recomendado para FEFO: evita mezcla de lotes con distintas fechas de vencimiento.';
COMMENT ON COLUMN logistics.locations.picking_sequence     IS 'Número de orden en el recorrido de picking. Define la ruta óptima del picker.';

-- ============================================================
-- Sensores IoT en ubicaciones (diferenciador)
-- ============================================================
CREATE TABLE logistics.location_sensors (
    id              BIGSERIAL       PRIMARY KEY,
    location_id     BIGINT          NOT NULL REFERENCES logistics.locations(id) ON DELETE RESTRICT,

    sensor_code     VARCHAR(100)    NOT NULL UNIQUE,
    sensor_type     VARCHAR(30)     NOT NULL,
    -- temperature | humidity | weight | motion | camera

    -- Umbrales de alerta
    alert_min       NUMERIC(10,4),
    alert_max       NUMERIC(10,4),

    last_reading    NUMERIC(10,4),
    last_reading_at TIMESTAMPTZ,
    last_status     VARCHAR(20)     DEFAULT 'ok',
    -- ok | alert | offline

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_location_sensors_location ON logistics.location_sensors (location_id);

CREATE TRIGGER trg_location_sensors_updated_at
    BEFORE UPDATE ON logistics.location_sensors
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.location_sensors IS 'Sensores IoT en ubicaciones: temperatura, humedad, peso. Activa alertas automáticas al salir de rango.';
