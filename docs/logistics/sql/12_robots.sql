-- ============================================================
-- mantrasdb | Módulo Logistics
-- Archivo: 12_robots.sql
-- Descripción: Robots AMR (Autonomous Mobile Robots) y
--              perfiles de operadores logísticos.
--
-- Filosofía de unificación:
--   - Humanos y robots son operadores del almacén.
--   - Ambos usan performed_by_type + performed_by_id.
--   - Los robots tienen su propio ID en logistics.robots.
--   - Los humanos tienen su ID en hr.employees.
--   - El perfil logístico del operador humano se guarda en
--     logistics.operator_profiles (sin duplicar hr.employees).
--
-- Trazabilidad: cualquier pick, pack, putaway o transferencia
-- muestra quién lo hizo — humano o robot — con el mismo patrón.
-- ============================================================

-- ============================================================
-- Tipos de robot
-- ============================================================
CREATE TABLE logistics.robot_types (
    id          SERIAL          PRIMARY KEY,
    code        VARCHAR(30)     NOT NULL UNIQUE,
    name        VARCHAR(100)    NOT NULL,
    description TEXT
);

INSERT INTO logistics.robot_types (code, name, description) VALUES
('AMR',       'Autonomous Mobile Robot',  'Robot autónomo de navegación libre (e.g., Locus, 6 River)'),
('AGV',       'Automated Guided Vehicle', 'Vehículo guiado por rutas fijas (magnetic tape / QR)'),
('SORTER',    'Automatic Sorter',         'Sistema de clasificación automática en conveyor'),
('PALLETIZER','Palletizer Robot',         'Robot de paletizado al final de línea'),
('COBOT',     'Collaborative Robot',      'Robot colaborativo que trabaja junto a humanos'),
('DRONE',     'Inventory Drone',          'Dron para conteo de inventario aéreo');

COMMENT ON TABLE logistics.robot_types IS 'Tipos de robot: AMR, AGV, Sorter, Palletizer, Cobot, Drone.';

-- ============================================================
-- Estaciones de carga
-- ============================================================
CREATE TABLE logistics.charging_stations (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    warehouse_id    BIGINT          NOT NULL REFERENCES logistics.warehouses(id),
    location_id     BIGINT          REFERENCES logistics.locations(id),

    station_code    VARCHAR(50)     NOT NULL,
    max_robots      INTEGER         NOT NULL DEFAULT 1,
    -- cuántos robots pueden cargar simultáneamente

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, station_code)
);

CREATE TRIGGER trg_charging_stations_updated_at
    BEFORE UPDATE ON logistics.charging_stations
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.charging_stations IS 'Estaciones de carga para robots. Cada estación admite un número máximo de robots simultáneos.';

-- ============================================================
-- Robots
-- ============================================================
CREATE TABLE logistics.robots (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    warehouse_id        BIGINT          NOT NULL REFERENCES logistics.warehouses(id),
    robot_type_id       INTEGER         NOT NULL REFERENCES logistics.robot_types(id),
    charging_station_id BIGINT          REFERENCES logistics.charging_stations(id),

    -- Identificación
    robot_code          VARCHAR(50)     NOT NULL,
    -- código interno del robot (e.g. "AMR-001")
    serial_number       VARCHAR(100),
    -- número de serie del fabricante
    model               VARCHAR(100),
    manufacturer        VARCHAR(100),

    -- Estado operativo
    status              VARCHAR(20)     NOT NULL DEFAULT 'idle',
    -- idle | picking | charging | maintenance | offline | error

    -- Capacidad
    max_payload_kg      NUMERIC(10,3),
    max_speed_mps       NUMERIC(6,3),
    -- metros por segundo

    -- Batería
    battery_pct         SMALLINT,
    -- porcentaje de batería actual (0-100)
    battery_min_pct     SMALLINT        NOT NULL DEFAULT 20,
    -- umbral mínimo para ir a cargar automáticamente

    -- Posición actual
    current_location_id BIGINT          REFERENCES logistics.locations(id),
    last_seen_at        TIMESTAMPTZ,

    -- Control remoto / API
    api_endpoint        VARCHAR(300),
    -- endpoint para enviarle comandos (REST/MQTT)

    -- Vida útil
    purchase_date       DATE,
    warranty_until      DATE,

    notes               TEXT,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, robot_code)
);

CREATE INDEX idx_robots_company   ON logistics.robots (company_id);
CREATE INDEX idx_robots_warehouse ON logistics.robots (warehouse_id);
CREATE INDEX idx_robots_status    ON logistics.robots (status);

CREATE TRIGGER trg_robots_updated_at
    BEFORE UPDATE ON logistics.robots
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.robots             IS 'Robots del almacén: AMR, AGV, Sorters, etc. Su ID se usa como performed_by_id cuando performed_by_type=robot.';
COMMENT ON COLUMN logistics.robots.robot_code  IS 'Código interno del robot. Escanearlo en el pistolaje identifica quién realizó la operación.';
COMMENT ON COLUMN logistics.robots.battery_pct IS 'Batería actual. Cuando cae a battery_min_pct el sistema lo manda a cargar y reasigna su tarea.';

-- ============================================================
-- Tareas asignadas a robots
-- ============================================================
CREATE TABLE logistics.robot_tasks (
    id                  BIGSERIAL       PRIMARY KEY,
    robot_id            BIGINT          NOT NULL REFERENCES logistics.robots(id),
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    warehouse_id        BIGINT          NOT NULL REFERENCES logistics.warehouses(id),

    task_type           VARCHAR(30)     NOT NULL,
    -- pick | putaway | replenishment | transfer | charge | idle | count

    -- Referencia al documento asociado
    reference_type      VARCHAR(50),
    -- pick_task | replenishment_task | transfer_order | inventory_count
    reference_id        BIGINT,

    -- Ruta
    from_location_id    BIGINT          REFERENCES logistics.locations(id),
    to_location_id      BIGINT          REFERENCES logistics.locations(id),

    status              VARCHAR(20)     NOT NULL DEFAULT 'queued',
    -- queued | executing | completed | failed | cancelled

    -- Tiempos
    queued_at           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,

    -- Métricas
    distance_m          NUMERIC(10,2),
    -- metros recorridos en esta tarea
    duration_seconds    INTEGER,
    -- segundos que tardó

    error_message       TEXT,
    -- si falló, razón del fallo

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_robot_tasks_robot   ON logistics.robot_tasks (robot_id);
CREATE INDEX idx_robot_tasks_status  ON logistics.robot_tasks (status) WHERE status IN ('queued','executing');
CREATE INDEX idx_robot_tasks_ref     ON logistics.robot_tasks (reference_type, reference_id);

COMMENT ON TABLE  logistics.robot_tasks            IS 'Cola de tareas asignadas a robots. El sistema despacha tareas basándose en disponibilidad y batería.';
COMMENT ON COLUMN logistics.robot_tasks.distance_m IS 'Metros recorridos. Alimenta el reporte de productividad y uso del robot.';

-- ============================================================
-- Rendimiento diario del robot (agregado)
-- ============================================================
CREATE TABLE logistics.robot_performance (
    id                  BIGSERIAL       PRIMARY KEY,
    robot_id            BIGINT          NOT NULL REFERENCES logistics.robots(id),
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    performance_date    DATE            NOT NULL,

    -- Métricas operativas
    tasks_completed     INTEGER         NOT NULL DEFAULT 0,
    tasks_failed        INTEGER         NOT NULL DEFAULT 0,
    total_distance_m    NUMERIC(12,2)   NOT NULL DEFAULT 0,
    total_uptime_min    INTEGER         NOT NULL DEFAULT 0,
    total_idle_min      INTEGER         NOT NULL DEFAULT 0,
    total_charging_min  INTEGER         NOT NULL DEFAULT 0,

    -- Picking
    picks_completed     INTEGER         NOT NULL DEFAULT 0,
    units_picked        NUMERIC(18,4)   NOT NULL DEFAULT 0,

    -- Batería
    charge_cycles       SMALLINT        NOT NULL DEFAULT 0,
    battery_avg_pct     SMALLINT,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (robot_id, performance_date)
);

CREATE INDEX idx_robot_perf_robot ON logistics.robot_performance (robot_id);
CREATE INDEX idx_robot_perf_date  ON logistics.robot_performance (performance_date);

COMMENT ON TABLE logistics.robot_performance IS 'Rendimiento diario del robot: picks, distancia, uptime y ciclos de batería. Para dashboards y mantenimiento predictivo.';

-- ============================================================
-- Perfil logístico del operador humano
-- Extiende hr.employees con config específica de almacén.
-- Sin duplicar la cuenta de RRHH — mismo employee_id.
-- ============================================================
CREATE TABLE logistics.operator_profiles (
    id                  BIGSERIAL       PRIMARY KEY,
    employee_id         BIGINT          NOT NULL REFERENCES hr.employees(id) ON DELETE RESTRICT,
    -- FK al empleado en RRHH — mismo usuario, perfil adicional
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    warehouse_id        BIGINT          NOT NULL REFERENCES logistics.warehouses(id),

    -- Configuración de trabajo
    default_zone_id     BIGINT          REFERENCES logistics.warehouse_zones(id),
    -- zona asignada por defecto

    device_type         VARCHAR(20)     NOT NULL DEFAULT 'rf_gun',
    -- rf_gun | voice | mobile | tablet | wearable

    picking_method      VARCHAR(20)     NOT NULL DEFAULT 'discrete',
    -- discrete | batch | cluster

    -- Permisos específicos de almacén
    can_approve_counts  BOOLEAN         NOT NULL DEFAULT FALSE,
    can_adjust_inventory BOOLEAN        NOT NULL DEFAULT FALSE,
    can_approve_putaway  BOOLEAN        NOT NULL DEFAULT FALSE,
    can_manage_robots    BOOLEAN        NOT NULL DEFAULT FALSE,

    -- Gamificación (diferenciador)
    total_picks         INTEGER         NOT NULL DEFAULT 0,
    total_units_picked  NUMERIC(18,4)   NOT NULL DEFAULT 0,
    total_tasks_done    INTEGER         NOT NULL DEFAULT 0,
    accuracy_pct        NUMERIC(5,2),
    -- % de picks correctos (sin errores de producto/cantidad)
    gamification_points INTEGER         NOT NULL DEFAULT 0,
    gamification_level  VARCHAR(20)     NOT NULL DEFAULT 'rookie',
    -- rookie → picker → senior → expert → champion

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (employee_id, warehouse_id)
    -- un empleado puede tener perfil en más de un almacén
);

CREATE INDEX idx_operator_profiles_employee  ON logistics.operator_profiles (employee_id);
CREATE INDEX idx_operator_profiles_warehouse ON logistics.operator_profiles (warehouse_id);

CREATE TRIGGER trg_operator_profiles_updated_at
    BEFORE UPDATE ON logistics.operator_profiles
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.operator_profiles                IS 'Perfil logístico del operador. Extiende hr.employees con config de almacén, permisos y gamificación.';
COMMENT ON COLUMN logistics.operator_profiles.employee_id    IS 'Mismo ID de hr.employees — no hay cuenta duplicada. Un empleado = un usuario en el sistema.';
COMMENT ON COLUMN logistics.operator_profiles.gamification_level IS 'Sistema de niveles: rookie→picker→senior→expert→champion. Motiva precisión y velocidad.';

-- ============================================================
-- Rendimiento diario del operador humano
-- ============================================================
CREATE TABLE logistics.operator_performance (
    id                      BIGSERIAL       PRIMARY KEY,
    employee_id             BIGINT          NOT NULL REFERENCES hr.employees(id),
    company_id              BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    warehouse_id            BIGINT          NOT NULL REFERENCES logistics.warehouses(id),
    performance_date        DATE            NOT NULL,

    -- Picking
    picks_completed         INTEGER         NOT NULL DEFAULT 0,
    picks_with_errors       INTEGER         NOT NULL DEFAULT 0,
    units_picked            NUMERIC(18,4)   NOT NULL DEFAULT 0,
    short_picks             INTEGER         NOT NULL DEFAULT 0,
    -- veces que no encontró el stock

    -- Empaque
    packs_completed         INTEGER         NOT NULL DEFAULT 0,

    -- Putaway
    putaways_completed      INTEGER         NOT NULL DEFAULT 0,

    -- Tiempos
    active_minutes          INTEGER         NOT NULL DEFAULT 0,
    idle_minutes            INTEGER         NOT NULL DEFAULT 0,

    -- Calidad
    scan_accuracy_pct       NUMERIC(5,2),
    -- % de escaneos correctos al primer intento

    -- Puntos de gamificación ganados este día
    points_earned           INTEGER         NOT NULL DEFAULT 0,

    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (employee_id, warehouse_id, performance_date)
);

CREATE INDEX idx_operator_perf_employee ON logistics.operator_performance (employee_id);
CREATE INDEX idx_operator_perf_date     ON logistics.operator_performance (performance_date);

COMMENT ON TABLE logistics.operator_performance IS 'Rendimiento diario del operador humano. Base del sistema de gamificación y evaluaciones de desempeño.';
