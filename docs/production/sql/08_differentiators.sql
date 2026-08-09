-- ============================================================
-- mantrasdb | Módulo Production
-- Archivo: 08_differentiators.sql
-- Descripción: Diferenciadores avanzados + integraciones
--
-- Módulos:
--   1. lot_genealogy         — trazabilidad lote-a-lote
--   2. production_alerts     — alertas automáticas de producción
--   3. restaurant_features   — características específicas restaurante
--      - kitchen_stations    : estaciones de cocina (= work centers)
--      - order_tickets       : tickets/comandas por estación
--      - temperature_logs    : registros de temperatura HACCP
--   4. production_kpis       — KPIs calculados por período
--   5. iot_sensor_readings   — lecturas de sensores IoT
-- ============================================================

-- ============================================================
-- 1. LOT GENEALOGY (Trazabilidad Lote → Lote)
--    Registro de qué lotes de MP generaron qué lotes de PT.
--    Permite trazabilidad completa hacia atrás (backward) y
--    hacia adelante (forward).
--
--    Ejemplo:
--      Lote aceite de oliva #A001 + Lote romero #B002
--      → Producción OP-2024-001 → Lote conserva #C003
--    Si hay un problema en #A001 → saber qué PTs están afectados.
-- ============================================================
CREATE TABLE production.lot_genealogy (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Orden de producción que realizó la transformación
    production_order_id BIGINT      NOT NULL REFERENCES production.production_orders(id),

    -- Lote de entrada (MP / componente / insumo)
    input_lot_id        BIGINT      REFERENCES logistics.lots(id),
    input_serial_id     BIGINT      REFERENCES logistics.serial_numbers(id),
    input_product_id    BIGINT      REFERENCES logistics.products(id),
    input_quantity      NUMERIC(18,6),

    -- Lote de salida (PT / semielaborado)
    output_lot_id       BIGINT      REFERENCES logistics.lots(id),
    output_serial_id    BIGINT      REFERENCES logistics.serial_numbers(id),
    output_product_id   BIGINT      REFERENCES logistics.products(id),
    output_quantity     NUMERIC(18,6),

    -- Tipo de transformación
    transformation_type VARCHAR(20) NOT NULL DEFAULT 'manufacturing',
    -- manufacturing : fabricación estándar
    -- disassembly   : desarmado (logística inversa)
    -- refurbishment : reacondicionamiento
    -- splitting     : división de un lote en varios
    -- merging       : consolidación de varios lotes en uno

    recorded_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE: la genealogía es un registro histórico
);

CREATE INDEX idx_genealogy_input_lot    ON production.lot_genealogy (input_lot_id);
CREATE INDEX idx_genealogy_output_lot   ON production.lot_genealogy (output_lot_id);
CREATE INDEX idx_genealogy_order        ON production.lot_genealogy (production_order_id);
CREATE INDEX idx_genealogy_input_prod   ON production.lot_genealogy (input_product_id);
CREATE INDEX idx_genealogy_output_prod  ON production.lot_genealogy (output_product_id);

COMMENT ON TABLE production.lot_genealogy IS 'Trazabilidad lote-a-lote: de qué MP vino cada PT. Permite rastrear recalls hacia atrás (backward) y alertas hacia adelante (forward).';

-- ============================================================
-- 2. PRODUCTION ALERTS (Alertas Automáticas)
--    Sistema de alertas para eventos de producción.
--    Pueden dispararse por reglas automáticas (app backend)
--    o registrarse manualmente.
-- ============================================================
CREATE TABLE production.production_alerts (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    alert_type          VARCHAR(30) NOT NULL,
    -- order_delay        : OP con retraso vs fecha comprometida
    -- material_shortage  : falta material para iniciar OP
    -- quality_fail       : inspección fallida
    -- machine_breakdown  : avería de máquina
    -- temperature_out    : temperatura fuera de rango (HACCP)
    -- merma_excess       : merma supera % normal
    -- capacity_overload  : centro de trabajo sobrecargado
    -- backflush_pending  : backflush de materiales pendiente
    -- lot_expiry         : lote próximo a vencerse en producción

    severity            VARCHAR(10) NOT NULL DEFAULT 'warning',
    -- info / warning / critical

    -- Entidad a la que aplica
    production_order_id BIGINT      REFERENCES production.production_orders(id),
    work_order_id       BIGINT      REFERENCES production.work_orders(id),
    work_center_id      BIGINT      REFERENCES production.work_centers(id),
    machine_id          BIGINT      REFERENCES production.machines(id),
    area_id             BIGINT      REFERENCES production.production_areas(id),

    title               VARCHAR(200) NOT NULL,
    message             TEXT        NOT NULL,

    -- ¿Se envió notificación?
    notification_sent   BOOLEAN     NOT NULL DEFAULT FALSE,
    notification_sent_at TIMESTAMPTZ,
    -- A quién se notificó
    notified_user_ids   BIGINT[],

    -- Estado de la alerta
    status              VARCHAR(20) NOT NULL DEFAULT 'open',
    -- open       : activa, sin atender
    -- acknowledged: vista pero no resuelta
    -- resolved   : resuelta
    -- dismissed  : descartada (falsa alarma)

    acknowledged_by     BIGINT      REFERENCES hr.system_users(id),
    acknowledged_at     TIMESTAMPTZ,

    resolved_by         BIGINT      REFERENCES hr.system_users(id),
    resolved_at         TIMESTAMPTZ,

    -- Datos adicionales (contexto de la alerta)
    alert_data          JSONB,
    -- Ej: {"temperature_reading": 8.5, "max_allowed": 5.0, "sensor_id": "SENS-001"}

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_alerts_type    ON production.production_alerts (alert_type);
CREATE INDEX idx_alerts_severity ON production.production_alerts (severity);
CREATE INDEX idx_alerts_status  ON production.production_alerts (status);
CREATE INDEX idx_alerts_order   ON production.production_alerts (production_order_id);
CREATE INDEX idx_alerts_area    ON production.production_alerts (area_id);

COMMENT ON TABLE production.production_alerts IS 'Alertas de producción: demoras, falta material, fallos de calidad, averías, temperatura HACCP, merma excesiva.';

-- ============================================================
-- 3A. KITCHEN STATIONS (Estaciones de Cocina — Restaurantes)
--     Para restaurantes: las estaciones de cocina son centros
--     de trabajo especializados.
--     En el sistema de trabajo centers ya existen, pero aquí
--     añadimos la configuración específica de cocina.
-- ============================================================
CREATE TABLE production.kitchen_station_config (
    id                  BIGSERIAL   PRIMARY KEY,
    work_center_id      BIGINT      NOT NULL REFERENCES production.work_centers(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    station_type        VARCHAR(20) NOT NULL DEFAULT 'hot_kitchen',
    -- hot_kitchen   : cocina caliente (parrilla, wok, freidora)
    -- cold_kitchen  : cocina fría (ensaladas, sushi, ceviche)
    -- pastry        : repostería y panadería
    -- bar           : bar / bebidas
    -- dispatch      : zona de despacho / armado de platos
    -- delivery_prep : preparación para delivery

    -- Display en el KDS (Kitchen Display System)
    kds_display_order   SMALLINT    NOT NULL DEFAULT 10,
    -- Orden en el que aparece en la pantalla de cocina

    -- ¿Tiene pantalla KDS conectada?
    has_kds             BOOLEAN     NOT NULL DEFAULT FALSE,
    kds_device_id       VARCHAR(100),
    -- ID del dispositivo KDS (tablet, pantalla)

    -- Tiempo promedio de preparación por tipo de plato (minutos)
    avg_prep_time_min   NUMERIC(6,2) NOT NULL DEFAULT 10,

    -- Alerta si un ticket supera X minutos sin completarse
    alert_after_min     SMALLINT    NOT NULL DEFAULT 20,

    -- Control de temperatura de la estación (HACCP)
    min_temperature_c   NUMERIC(5,2),
    max_temperature_c   NUMERIC(5,2),

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (work_center_id)
);

CREATE TRIGGER trg_ksc_updated_at
    BEFORE UPDATE ON production.kitchen_station_config
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

COMMENT ON TABLE production.kitchen_station_config IS 'Configuración de estación de cocina: tipo (caliente/fría/bar/despacho), KDS, tiempo promedio y alertas. Las production_orders son comandas en restaurantes.';

-- ============================================================
-- 3B. ORDER TICKETS (Tickets de Comanda por Estación)
--     Para restaurantes: una comanda (production_order) se
--     divide en tickets por estación de cocina.
--     Cada ticket = un work_order dirigido a una estación.
-- ============================================================
CREATE TABLE production.order_tickets (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- La comanda (= production_order en el contexto de restaurante)
    production_order_id BIGINT      NOT NULL REFERENCES production.production_orders(id),

    -- La estación (= work_center configurada como kitchen_station)
    work_center_id      BIGINT      NOT NULL REFERENCES production.work_centers(id),

    -- Work order que ejecuta este ticket
    work_order_id       BIGINT      REFERENCES production.work_orders(id),

    ticket_number       VARCHAR(20) NOT NULL,

    -- Platos / ítems en este ticket (para esta estación)
    ticket_items        JSONB       NOT NULL DEFAULT '[]',
    -- Ej: [{"producto": "Lomo Saltado", "qty": 2, "notes": "sin picante"},
    --       {"producto": "Arroz blanco", "qty": 2}]

    -- Timestamps clave del ticket
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Cuando se recibió el pedido
    acknowledged_at     TIMESTAMPTZ,
    -- Cuando la cocina vio el ticket
    started_at          TIMESTAMPTZ,
    -- Cuando empezó la preparación
    ready_at            TIMESTAMPTZ,
    -- Cuando el plato está listo para despachar
    dispatched_at       TIMESTAMPTZ,
    -- Cuando salió al cliente (mesa o delivery)

    prep_time_min       NUMERIC(8,2) GENERATED ALWAYS AS (
        CASE WHEN ready_at IS NOT NULL AND started_at IS NOT NULL
             THEN EXTRACT(EPOCH FROM (ready_at - started_at)) / 60
             ELSE NULL END
    ) STORED,

    total_time_min      NUMERIC(8,2) GENERATED ALWAYS AS (
        CASE WHEN dispatched_at IS NOT NULL
             THEN EXTRACT(EPOCH FROM (dispatched_at - created_at)) / 60
             ELSE NULL END
    ) STORED,

    -- Estado del ticket en la estación
    status              VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending      : en espera de ser tomado
    -- in_progress  : en preparación
    -- ready        : listo para despachar
    -- dispatched   : despachado al cliente
    -- cancelled    : cancelado

    -- Prioridad (urgente, normal, VIP)
    priority            SMALLINT    NOT NULL DEFAULT 5,

    -- Mesa o pedido de delivery relacionado
    table_number        VARCHAR(20),
    delivery_order_ref  VARCHAR(50),

    notes               TEXT

    -- INMUTABLE (no se edita, solo se actualizan timestamps)
);

CREATE INDEX idx_ticket_order   ON production.order_tickets (production_order_id);
CREATE INDEX idx_ticket_station ON production.order_tickets (work_center_id);
CREATE INDEX idx_ticket_status  ON production.order_tickets (status);
CREATE INDEX idx_ticket_created ON production.order_tickets (created_at);

COMMENT ON TABLE production.order_tickets IS 'Tickets de comanda por estación de cocina. Los timestamps permiten medir tiempos de preparación y alertas KDS.';

-- ============================================================
-- 3C. TEMPERATURE LOGS (Registros de Temperatura HACCP)
--     Para alimentos y restaurantes: registro periódico de
--     temperatura en áreas y equipos críticos.
--     Exigido por HACCP y DIGESA (Perú).
-- ============================================================
CREATE TABLE production.temperature_logs (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- ¿Dónde se midió?
    area_id             BIGINT      REFERENCES production.production_areas(id),
    work_center_id      BIGINT      REFERENCES production.work_centers(id),
    machine_id          BIGINT      REFERENCES production.machines(id),
    -- Al menos uno de los tres debe estar presente

    -- ¿A qué OP o lote corresponde?
    production_order_id BIGINT      REFERENCES production.production_orders(id),
    lot_id              BIGINT      REFERENCES logistics.lots(id),

    -- Tipo de registro
    log_type            VARCHAR(20) NOT NULL DEFAULT 'routine',
    -- routine     : registro rutinario (cada N minutos)
    -- haccp_ccp   : Punto de Control Crítico HACCP
    -- alarm       : registrado por alarma de temperatura
    -- manual      : ingresado manualmente por operario

    -- Valores medidos
    temperature_c       NUMERIC(7,3) NOT NULL,
    -- Sensor o instrumento
    sensor_id           VARCHAR(100),
    instrument_code     VARCHAR(50),

    -- ¿Está dentro del rango aceptable?
    min_allowed_c       NUMERIC(7,3),
    max_allowed_c       NUMERIC(7,3),
    is_within_range     BOOLEAN     GENERATED ALWAYS AS (
        CASE WHEN min_allowed_c IS NOT NULL AND max_allowed_c IS NOT NULL
             THEN temperature_c BETWEEN min_allowed_c AND max_allowed_c
             ELSE NULL END
    ) STORED,

    -- ¿Generó una alerta?
    alert_generated     BOOLEAN     NOT NULL DEFAULT FALSE,
    alert_id            BIGINT      REFERENCES production.production_alerts(id),

    -- Acción correctiva tomada
    corrective_action   TEXT,

    measured_by         BIGINT      REFERENCES hr.system_users(id),
    measured_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE: los registros de temperatura no se editan
);

CREATE INDEX idx_templog_area    ON production.temperature_logs (area_id);
CREATE INDEX idx_templog_machine ON production.temperature_logs (machine_id);
CREATE INDEX idx_templog_order   ON production.temperature_logs (production_order_id);
CREATE INDEX idx_templog_range   ON production.temperature_logs (is_within_range);
CREATE INDEX idx_templog_at      ON production.temperature_logs (measured_at);

COMMENT ON TABLE production.temperature_logs IS 'Registros de temperatura HACCP: por área, centro, máquina o lote. Alerta automática si sale de rango. Inmutable.';

-- ============================================================
-- 4. PRODUCTION KPIs (KPIs Calculados por Período)
--    Tabla de resumen de KPIs por período y unidad (empresa,
--    planta, área, centro de trabajo).
--    Calculados por un job periódico y cacheados aquí.
-- ============================================================
CREATE TABLE production.production_kpis (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Granularidad del período
    period_type         VARCHAR(10) NOT NULL DEFAULT 'month',
    -- day / week / month / quarter / year

    period_start        DATE        NOT NULL,
    period_end          DATE        NOT NULL,

    -- ¿A qué nivel aplican estos KPIs?
    kpi_level           VARCHAR(20) NOT NULL DEFAULT 'company',
    -- company / warehouse / area / work_center / machine

    warehouse_id        BIGINT      REFERENCES logistics.warehouses(id),
    area_id             BIGINT      REFERENCES production.production_areas(id),
    work_center_id      BIGINT      REFERENCES production.work_centers(id),
    machine_id          BIGINT      REFERENCES production.machines(id),

    -- ── Volumen ───────────────────────────────────────────────
    total_orders        INTEGER     NOT NULL DEFAULT 0,
    completed_orders    INTEGER     NOT NULL DEFAULT 0,
    on_time_orders      INTEGER     NOT NULL DEFAULT 0,

    planned_qty         NUMERIC(18,6) NOT NULL DEFAULT 0,
    produced_good_qty   NUMERIC(18,6) NOT NULL DEFAULT 0,
    scrap_qty           NUMERIC(18,6) NOT NULL DEFAULT 0,
    rework_qty          NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- ── Tiempos ───────────────────────────────────────────────
    total_production_hours NUMERIC(12,4) NOT NULL DEFAULT 0,
    total_setup_hours   NUMERIC(12,4) NOT NULL DEFAULT 0,
    total_downtime_hours NUMERIC(12,4) NOT NULL DEFAULT 0,
    total_idle_hours    NUMERIC(12,4) NOT NULL DEFAULT 0,

    -- ── KPIs calculados ───────────────────────────────────────
    -- OTD: On-Time Delivery %
    otd_pct             NUMERIC(7,2) GENERATED ALWAYS AS (
        CASE WHEN total_orders > 0
             THEN ROUND(on_time_orders::NUMERIC / total_orders * 100, 2)
             ELSE NULL END
    ) STORED,

    -- FPY: First Pass Yield %
    fpy_pct             NUMERIC(7,2) GENERATED ALWAYS AS (
        CASE WHEN planned_qty > 0
             THEN ROUND(produced_good_qty / planned_qty * 100, 2)
             ELSE NULL END
    ) STORED,

    -- Scrap Rate %
    scrap_rate_pct      NUMERIC(7,2) GENERATED ALWAYS AS (
        CASE WHEN planned_qty > 0
             THEN ROUND(scrap_qty / planned_qty * 100, 2)
             ELSE NULL END
    ) STORED,

    -- Utilización (horas producción / horas totales disponibles)
    utilization_pct     NUMERIC(7,2) GENERATED ALWAYS AS (
        CASE WHEN (total_production_hours + total_idle_hours) > 0
             THEN ROUND(total_production_hours /
                  (total_production_hours + total_idle_hours + total_downtime_hours) * 100, 2)
             ELSE NULL END
    ) STORED,

    -- ── Costos ────────────────────────────────────────────────
    total_std_cost      NUMERIC(18,4) NOT NULL DEFAULT 0,
    total_actual_cost   NUMERIC(18,4) NOT NULL DEFAULT 0,
    total_variance      NUMERIC(18,4) GENERATED ALWAYS AS (total_actual_cost - total_std_cost) STORED,
    total_merma_cost    NUMERIC(18,4) NOT NULL DEFAULT 0,

    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',

    -- Fecha del último cálculo
    calculated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX uq_production_kpis
    ON production.production_kpis (company_id, period_type, period_start, kpi_level,
        COALESCE(work_center_id, 0::BIGINT),
        COALESCE(area_id, 0::BIGINT),
        COALESCE(machine_id, 0::BIGINT));

COMMENT ON TABLE production.production_kpis IS 'KPIs de producción por período y nivel: OTD, FPY, Scrap Rate, Utilización, OEE. Calculados por job periódico y cacheados.';

-- ============================================================
-- 5. IOT SENSOR READINGS (Lecturas de Sensores IoT)
--    Lecturas en tiempo real de sensores conectados a máquinas.
--    Datos de alta frecuencia → solo se guarda lo relevante
--    (anomalías, promedios por hora) para no inflar la BD.
-- ============================================================
CREATE TABLE production.iot_sensor_readings (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),
    machine_id          BIGINT      NOT NULL REFERENCES production.machines(id),

    sensor_id           VARCHAR(100) NOT NULL,
    -- ID del sensor físico (ej: 'SENS-001', OPC-UA node ID)

    sensor_type         VARCHAR(30) NOT NULL,
    -- temperature / pressure / vibration / speed / current /
    -- humidity / weight / flow_rate / counter / custom

    -- Valor medido
    reading_value       NUMERIC(18,6) NOT NULL,
    unit_of_measure     VARCHAR(20),
    -- '°C', 'bar', 'RPM', 'A', '%', 'kg', 'L/min'

    -- Contexto de producción al momento de la lectura
    production_order_id BIGINT      REFERENCES production.production_orders(id),
    work_order_id       BIGINT      REFERENCES production.work_orders(id),

    -- ¿Es una anomalía/alarma?
    is_anomaly          BOOLEAN     NOT NULL DEFAULT FALSE,
    anomaly_description TEXT,

    -- Si generó alerta de producción
    alert_id            BIGINT      REFERENCES production.production_alerts(id),

    read_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Timestamp exacto del sensor

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);

-- Índice para consultas por máquina y sensor en el tiempo
CREATE INDEX idx_iot_machine    ON production.iot_sensor_readings (machine_id, sensor_id);
CREATE INDEX idx_iot_read_at    ON production.iot_sensor_readings (read_at);
CREATE INDEX idx_iot_anomaly    ON production.iot_sensor_readings (is_anomaly) WHERE is_anomaly = TRUE;
CREATE INDEX idx_iot_order      ON production.iot_sensor_readings (production_order_id);

COMMENT ON TABLE production.iot_sensor_readings IS 'Lecturas de sensores IoT en máquinas: temperatura, presión, velocidad, vibración. Solo se persisten anomalías y promedios para control de volumen.';

-- ============================================================
-- VIEW: Estado actual de producción por área y estación
--       (combina área_dashboard con tickets de restaurante)
-- ============================================================
CREATE VIEW production.production_floor_view AS
SELECT
    a.id AS area_id,
    a.company_id,
    a.name AS area_name,
    a.area_type,
    a.color_hex,
    -- Órdenes/comandas activas
    COUNT(DISTINCT apl.production_order_id) FILTER (WHERE apl.area_status = 'active')
        AS active_orders,
    -- Tickets de cocina pendientes (solo restaurantes)
    COUNT(DISTINCT ot.id) FILTER (WHERE ot.status IN ('pending', 'in_progress'))
        AS open_tickets,
    -- Tiempo promedio de preparación de tickets hoy
    ROUND(AVG(ot.prep_time_min) FILTER (
        WHERE ot.ready_at IS NOT NULL
          AND ot.started_at >= CURRENT_DATE
    ), 2) AS avg_ticket_prep_min_today,
    -- Alertas abiertas en el área
    COUNT(DISTINCT pa.id) FILTER (WHERE pa.status = 'open')
        AS open_alerts,
    -- Temperatura fuera de rango hoy (HACCP)
    COUNT(DISTINCT tl.id) FILTER (WHERE tl.is_within_range = FALSE AND tl.measured_at >= CURRENT_DATE)
        AS temp_violations_today
FROM production.production_areas a
LEFT JOIN production.area_process_log apl ON apl.area_id = a.id
LEFT JOIN production.work_centers wc ON wc.area_id = a.id
LEFT JOIN production.order_tickets ot ON ot.work_center_id = wc.id
LEFT JOIN production.production_alerts pa ON pa.area_id = a.id
LEFT JOIN production.temperature_logs tl ON tl.area_id = a.id
WHERE a.is_active = TRUE
GROUP BY a.id, a.company_id, a.name, a.area_type, a.color_hex
ORDER BY a.flow_sequence;

COMMENT ON VIEW production.production_floor_view IS 'Vista del piso de producción en tiempo real: órdenes activas, tickets de cocina, alertas y violaciones de temperatura por área.';
