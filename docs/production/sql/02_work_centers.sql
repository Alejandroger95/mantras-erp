-- ============================================================
-- mantrasdb | Módulo Production
-- Archivo: 02_work_centers.sql
-- Descripción: Centros de Trabajo, Máquinas y Capacidad
--
-- Módulos:
--   1. work_center_types   — tipos de centro (taller, línea, célula)
--   2. work_centers        — centros de trabajo
--   3. machines            — máquinas/equipos dentro de cada centro
--   4. work_center_capacity— capacidad por turno
--   5. work_center_calendar— calendario de disponibilidad
--   6. maintenance_plans   — mantenimiento preventivo de máquinas
--   7. machine_downtime    — registro de paradas no planificadas
--
-- Funciona para:
--   🏭 Manufactura: línea A, línea B, taller de soldadura
--   👗 Textil: sala de corte, sala de costura, acabados
--   💎 Joyería: taller de fundición, pulido, engaste
--   📱 Electrónica: banco de pruebas, estación de reparación
--   🔧 Refurbishment: zona de recepción, zona de clasificación
-- ============================================================

-- ============================================================
-- 1. WORK CENTER TYPES
-- ============================================================
CREATE TABLE production.work_center_types (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      REFERENCES hr.companies(id),
    -- NULL = tipo global del sistema

    code                VARCHAR(20) NOT NULL,
    name                VARCHAR(100) NOT NULL,

    center_category     VARCHAR(20) NOT NULL DEFAULT 'internal',
    -- internal       : taller/línea propio
    -- subcontract    : proveedor externo (maquila)
    -- virtual        : centro lógico (para planificación)

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO production.work_center_types (company_id, code, name, center_category) VALUES
(NULL, 'ASSEMBLY',    'Ensamblaje',              'internal'),
(NULL, 'MACHINING',   'Mecanizado',              'internal'),
(NULL, 'WELDING',     'Soldadura',               'internal'),
(NULL, 'PAINTING',    'Pintura / Acabados',      'internal'),
(NULL, 'QUALITY',     'Control de Calidad',      'internal'),
(NULL, 'PACKAGING',   'Empaque y Embalaje',      'internal'),
(NULL, 'CUTTING',     'Corte (Textil)',           'internal'),
(NULL, 'SEWING',      'Costura',                 'internal'),
(NULL, 'CASTING',     'Fundición (Joyería)',      'internal'),
(NULL, 'POLISHING',   'Pulido / Acabado',        'internal'),
(NULL, 'SETTING',     'Engaste (Joyería)',        'internal'),
(NULL, 'TESTING',     'Banco de Pruebas',        'internal'),
(NULL, 'REPAIR',      'Reparación / Refurbish',  'internal'),
(NULL, 'GRADING',     'Clasificación / Grado',   'internal'),
(NULL, 'MAQUILA',     'Subcontratación / Maquila','subcontract'),
(NULL, 'VIRTUAL',     'Planificación Virtual',   'virtual');

-- ============================================================
-- 2. WORK CENTERS
-- ============================================================
CREATE TABLE production.work_centers (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    code                VARCHAR(30) NOT NULL,
    name                VARCHAR(200) NOT NULL,
    description         TEXT,

    work_center_type_id BIGINT      NOT NULL REFERENCES production.work_center_types(id),

    -- Ubicación física
    warehouse_id        BIGINT      REFERENCES logistics.warehouses(id),
    warehouse_zone_id   BIGINT      REFERENCES logistics.warehouse_zones(id),

    -- Responsable del centro
    supervisor_employee_id BIGINT,
    -- REFERENCES hr.employees(id) — FK diferida

    -- Centro de costo asociado (para costeo analítico)
    cost_center_id      BIGINT,
    -- REFERENCES finance.cost_centers(id) — FK diferida

    -- Capacidad estándar
    capacity_type       VARCHAR(20) NOT NULL DEFAULT 'machine',
    -- machine     : capacidad en horas-máquina
    -- labor       : capacidad en horas-hombre
    -- pieces      : capacidad en unidades/turno
    -- weight      : capacidad en kg/turno (fundición, alimentos)

    -- Horas disponibles por turno (base)
    hours_per_shift     NUMERIC(5,2) NOT NULL DEFAULT 8.00,
    shifts_per_day      SMALLINT    NOT NULL DEFAULT 1,

    -- Eficiencia del centro (%)
    efficiency_pct      NUMERIC(7,4) NOT NULL DEFAULT 100.00,

    -- Número de máquinas/puestos en este centro
    machine_count       SMALLINT    NOT NULL DEFAULT 1,

    -- Para subcontratación
    subcontractor_id    BIGINT      REFERENCES logistics.suppliers(id),

    -- Tasa de costo por hora (para costeo)
    cost_per_hour       NUMERIC(18,4),
    cost_currency       VARCHAR(10) NOT NULL DEFAULT 'PEN',

    is_bottleneck       BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE = recurso cuello de botella (Theory of Constraints)

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE INDEX idx_wc_company  ON production.work_centers (company_id);
CREATE INDEX idx_wc_type     ON production.work_centers (work_center_type_id);

CREATE TRIGGER trg_wc_updated_at
    BEFORE UPDATE ON production.work_centers
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

COMMENT ON TABLE production.work_centers IS 'Centros de trabajo: líneas, talleres, bancos de prueba, zonas de refurbishment, subcontratistas.';

-- ============================================================
-- 3. MACHINES (Máquinas y Equipos)
--    Equipos individuales dentro de un centro de trabajo.
--    Pueden venir del módulo HR (equipment) o ser específicos de producción.
-- ============================================================
CREATE TABLE production.machines (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),
    work_center_id      BIGINT      NOT NULL REFERENCES production.work_centers(id),

    code                VARCHAR(30) NOT NULL,
    name                VARCHAR(200) NOT NULL,
    description         TEXT,

    -- Vinculo con activo fijo (si está en finance.fixed_assets)
    fixed_asset_id      BIGINT,
    -- REFERENCES finance.fixed_assets(id) — FK diferida

    -- Vinculo con equipo HR (si fue registrado en assets de RRHH)
    hr_equipment_id     BIGINT      REFERENCES hr.equipment(id),

    -- Especificaciones técnicas
    manufacturer        VARCHAR(100),
    model               VARCHAR(100),
    serial_number       VARCHAR(100),
    year_manufactured   SMALLINT,
    year_installed      SMALLINT,

    -- Capacidad individual
    capacity_per_hour   NUMERIC(18,4),
    capacity_uom_id     BIGINT      REFERENCES logistics.measurement_units(id),

    -- Para IoT / sensores
    has_iot_sensors     BOOLEAN     NOT NULL DEFAULT FALSE,
    iot_device_id       VARCHAR(100),
    -- ID del dispositivo IoT conectado (MQTT, OPC-UA, etc.)

    -- Estado actual
    machine_status      VARCHAR(20) NOT NULL DEFAULT 'operational',
    -- operational   : funcionando
    -- maintenance   : en mantenimiento planificado
    -- breakdown     : avería / parada no planificada
    -- idle          : disponible pero sin asignación
    -- retired       : dado de baja

    last_maintenance_date DATE,
    next_maintenance_date DATE,

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE TRIGGER trg_machine_updated_at
    BEFORE UPDATE ON production.machines
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

COMMENT ON TABLE production.machines IS 'Máquinas y equipos individuales. Vinculados a activos fijos y con soporte IoT.';

-- ============================================================
-- 4. WORK CENTER CAPACITY
--    Capacidad disponible por turno y período.
--    Permite planificación de capacidad (CRP).
-- ============================================================
CREATE TABLE production.work_center_capacity (
    id                  BIGSERIAL   PRIMARY KEY,
    work_center_id      BIGINT      NOT NULL REFERENCES production.work_centers(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Período de planificación
    valid_from          DATE        NOT NULL,
    valid_to            DATE,

    day_of_week         SMALLINT,
    -- NULL = aplica todos los días
    -- 1=Lunes, 2=Martes, ... 7=Domingo

    shift_number        SMALLINT    NOT NULL DEFAULT 1,
    -- 1 = turno mañana, 2 = turno tarde, 3 = turno noche

    shift_start         TIME        NOT NULL DEFAULT '08:00',
    shift_end           TIME        NOT NULL DEFAULT '17:00',

    -- Horas disponibles (descontando pausas)
    available_hours     NUMERIC(5,2) NOT NULL DEFAULT 8.00,

    -- Número de operarios asignados a este turno
    operator_count      SMALLINT    NOT NULL DEFAULT 1,

    -- Máquinas activas en este turno
    active_machines     SMALLINT    NOT NULL DEFAULT 1,

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_wcc_center ON production.work_center_capacity (work_center_id);
CREATE INDEX idx_wcc_dates  ON production.work_center_capacity (valid_from, valid_to);

-- ============================================================
-- 5. WORK CENTER CALENDAR (Excepciones al calendario base)
--    Días festivos, paradas programadas, mantenimiento, etc.
-- ============================================================
CREATE TABLE production.work_center_calendar (
    id                  BIGSERIAL   PRIMARY KEY,
    work_center_id      BIGINT      NOT NULL REFERENCES production.work_centers(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    exception_date      DATE        NOT NULL,

    exception_type      VARCHAR(20) NOT NULL DEFAULT 'holiday',
    -- holiday         : día festivo (sin producción)
    -- extra_shift     : turno extra (mayor capacidad)
    -- maintenance     : parada por mantenimiento
    -- breakdown       : avería registrada
    -- partial         : día parcial

    available_hours     NUMERIC(5,2) NOT NULL DEFAULT 0,
    -- 0 = sin producción, >0 = horas disponibles ese día

    reason              VARCHAR(200),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX uq_wc_calendar
    ON production.work_center_calendar (work_center_id, exception_date);

-- ============================================================
-- 6. MAINTENANCE PLANS (Mantenimiento Preventivo)
--    Plan de mantenimiento por máquina o centro de trabajo.
--    Integra con el módulo HR (equipment) y Finance (activos fijos).
-- ============================================================
CREATE TABLE production.maintenance_plans (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),
    machine_id          BIGINT      NOT NULL REFERENCES production.machines(id),

    plan_code           VARCHAR(30) NOT NULL,
    plan_name           VARCHAR(200) NOT NULL,
    description         TEXT,

    maintenance_type    VARCHAR(20) NOT NULL DEFAULT 'preventive',
    -- preventive  : mantenimiento preventivo programado
    -- predictive  : basado en condición (sensores IoT)
    -- corrective  : correctivo post-avería

    -- Frecuencia
    frequency_type      VARCHAR(20) NOT NULL DEFAULT 'calendar_days',
    -- calendar_days    : cada N días calendario
    -- machine_hours    : cada N horas de operación
    -- production_cycles: cada N ciclos de producción

    frequency_value     NUMERIC(10,2) NOT NULL,
    -- ej: 90 días, 500 horas, 10000 ciclos

    -- Duración estimada del mantenimiento (horas)
    estimated_hours     NUMERIC(5,2) NOT NULL DEFAULT 4.00,

    -- ¿Requiere parar la máquina?
    requires_downtime   BOOLEAN     NOT NULL DEFAULT TRUE,

    -- Responsable
    assigned_employee_id BIGINT,
    -- REFERENCES hr.employees(id) — FK diferida

    -- Proveedor externo de mantenimiento
    maintenance_supplier_id BIGINT  REFERENCES logistics.suppliers(id),

    last_performed_date DATE,
    next_due_date       DATE,
    next_due_hours      NUMERIC(10,2),

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, plan_code)
);

CREATE TRIGGER trg_maintplan_updated_at
    BEFORE UPDATE ON production.maintenance_plans
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

-- ============================================================
-- 7. MACHINE DOWNTIME (Paradas No Planificadas)
--    Registro de averías, paradas de emergencia y su impacto
--    en la producción. Clave para calcular OEE.
--    OEE = Disponibilidad × Rendimiento × Calidad
-- ============================================================
CREATE TABLE production.machine_downtime (
    id                  BIGSERIAL   PRIMARY KEY,
    machine_id          BIGINT      NOT NULL REFERENCES production.machines(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    start_datetime      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    end_datetime        TIMESTAMPTZ,
    -- NULL = parada aún activa

    downtime_minutes    NUMERIC(8,2) GENERATED ALWAYS AS (
        CASE WHEN end_datetime IS NOT NULL
             THEN EXTRACT(EPOCH FROM (end_datetime - start_datetime)) / 60
             ELSE NULL END
    ) STORED,

    downtime_type       VARCHAR(20) NOT NULL DEFAULT 'breakdown',
    -- breakdown      : avería mecánica/eléctrica
    -- setup          : cambio de formato/herramienta
    -- material_wait  : espera de material
    -- operator_absent: operario ausente
    -- quality_issue  : parada por problema de calidad
    -- planned_maint  : mantenimiento planificado
    -- power_outage   : corte de energía

    root_cause          TEXT,
    corrective_action   TEXT,

    -- Impacto en producción
    affected_production_order_id BIGINT,
    -- REFERENCES production.production_orders(id) — FK diferida

    reported_by         BIGINT      REFERENCES hr.system_users(id),
    resolved_by         BIGINT      REFERENCES hr.system_users(id),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_downtime_machine ON production.machine_downtime (machine_id);
CREATE INDEX idx_downtime_dates   ON production.machine_downtime (start_datetime);

COMMENT ON TABLE production.machine_downtime IS 'Paradas no planificadas. Alimenta el cálculo de OEE (Disponibilidad × Rendimiento × Calidad).';

-- ============================================================
-- VIEW: OEE por máquina (resumen del mes actual)
-- ============================================================
CREATE VIEW production.machine_oee_summary AS
SELECT
    m.id AS machine_id,
    m.company_id,
    m.code AS machine_code,
    m.name AS machine_name,
    wc.name AS work_center_name,
    DATE_TRUNC('month', CURRENT_DATE) AS period_month,
    -- Minutos disponibles teóricos (turnos × horas)
    wc.hours_per_shift * wc.shifts_per_day * wc.machine_count * 60 * 22 AS theoretical_minutes,
    -- Minutos de parada del mes
    COALESCE(SUM(d.downtime_minutes), 0) AS downtime_minutes,
    -- Disponibilidad (%)
    CASE WHEN wc.hours_per_shift * wc.shifts_per_day * wc.machine_count * 60 * 22 > 0
         THEN ROUND(
             (1 - COALESCE(SUM(d.downtime_minutes), 0) /
              (wc.hours_per_shift * wc.shifts_per_day * wc.machine_count * 60 * 22)
             ) * 100, 2)
         ELSE NULL
    END AS availability_pct
FROM production.machines m
JOIN production.work_centers wc ON m.work_center_id = wc.id
LEFT JOIN production.machine_downtime d
    ON d.machine_id = m.id
    AND DATE_TRUNC('month', d.start_datetime) = DATE_TRUNC('month', CURRENT_DATE)
WHERE m.is_active = TRUE
GROUP BY m.id, m.company_id, m.code, m.name, wc.name,
         wc.hours_per_shift, wc.shifts_per_day, wc.machine_count;

COMMENT ON VIEW production.machine_oee_summary IS 'Disponibilidad OEE por máquina en el mes actual. Alimentar con work_orders para rendimiento y calidad.';
