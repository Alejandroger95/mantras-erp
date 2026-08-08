-- ============================================================
-- mantrasdb | Módulo Logistics
-- Archivo: 13_differentiators.sql
-- Descripción: Funcionalidades diferenciadoras del ERP:
--   1. Documentos electrónicos SUNAT (GRE - Perú)
--   2. Cola de notificaciones (WhatsApp, SMS, Email, Push)
--   3. Huella de carbono por envío
--   4. Lecturas de sensores IoT (temperatura, humedad, peso)
--   5. Alertas del sistema
--
-- Estas tablas dan a mantrasdb ventajas sobre SAP y Oracle WMS
-- especialmente para PYMEs peruanas y latinoamericanas.
-- ============================================================

-- ============================================================
-- 1. DOCUMENTOS ELECTRÓNICOS SUNAT (GRE)
--    Guía de Remisión Electrónica — obligatoria en Perú
--    para trasladar mercadería de un punto a otro.
--    Emitida ante SUNAT antes de que el camión salga.
-- ============================================================
CREATE TABLE logistics.electronic_documents (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- Tipo de documento
    document_type       VARCHAR(20)     NOT NULL DEFAULT 'GRE',
    -- GRE = Guía de Remisión Electrónica (Perú)
    -- DAE = Declaración Aduanera de Exportación
    -- OTROS según país (factura electrónica en Col/Mex se agrega aquí)

    -- Referencia al envío o transferencia
    reference_type      VARCHAR(30)     NOT NULL,
    -- shipment | transfer_order | supplier_return | customer_return
    reference_id        BIGINT          NOT NULL,

    -- Datos SUNAT
    serie               VARCHAR(10),
    -- e.g. "T001"
    correlativo         VARCHAR(10),
    -- e.g. "000123"
    full_number         VARCHAR(30),
    -- serie-correlativo completo: "T001-000123"

    -- Estado ante SUNAT
    sunat_status        VARCHAR(20)     NOT NULL DEFAULT 'draft',
    -- draft | sent | accepted | rejected | cancelled

    sunat_ticket        VARCHAR(100),
    -- ticket de consulta si fue enviado en modo asíncrono
    sunat_response_code VARCHAR(10),
    sunat_response_desc TEXT,
    sunat_cdr_url       VARCHAR(500),
    -- URL del CDR (Constancia de Recepción) descargable

    -- Modalidad de traslado
    transfer_mode       VARCHAR(20)     NOT NULL DEFAULT 'private',
    -- private = transporte privado (vehículo propio)
    -- public  = transporte público (operador logístico)
    transfer_reason     VARCHAR(100),
    -- venta | traslado_entre_establecimientos | consignacion | devolucion | exportacion

    -- Datos del punto de partida y llegada
    departure_address   TEXT,
    arrival_address     TEXT,

    -- Datos del transportista (para modalidad pública)
    carrier_ruc         VARCHAR(15),
    carrier_name        VARCHAR(200),
    driver_name         VARCHAR(150),
    driver_document     VARCHAR(20),
    -- DNI o CE del conductor
    truck_plate         VARCHAR(20),

    -- Peso bruto total
    total_weight_kg     NUMERIC(10,3),

    -- XML enviado a SUNAT (blob comprimido)
    xml_content         TEXT,
    -- XML firmado digitalmente (guardar por compliance)
    cdr_content         TEXT,
    -- CDR recibido de SUNAT

    -- Fechas
    transfer_start_date DATE,
    sent_at             TIMESTAMPTZ,
    accepted_at         TIMESTAMPTZ,

    notes               TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_electronic_docs_company   ON logistics.electronic_documents (company_id);
CREATE INDEX idx_electronic_docs_reference ON logistics.electronic_documents (reference_type, reference_id);
CREATE INDEX idx_electronic_docs_status    ON logistics.electronic_documents (sunat_status);
CREATE INDEX idx_electronic_docs_number    ON logistics.electronic_documents (company_id, full_number)
    WHERE full_number IS NOT NULL;

CREATE TRIGGER trg_electronic_docs_updated_at
    BEFORE UPDATE ON logistics.electronic_documents
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.electronic_documents             IS 'Documentos electrónicos SUNAT. GRE (Guía de Remisión) obligatoria en Perú para trasladar mercadería.';
COMMENT ON COLUMN logistics.electronic_documents.sunat_status IS 'draft=en preparación, sent=enviado, accepted=aceptado por SUNAT, rejected=rechazado.';
COMMENT ON COLUMN logistics.electronic_documents.xml_content  IS 'XML firmado digitalmente enviado a SUNAT. Se guarda por obligación legal (5 años).';

-- ============================================================
-- 2. COLA DE NOTIFICACIONES
--    Diferenciador: WhatsApp para confirmación de entrega,
--    alertas de stock, avisos de recepción, etc.
-- ============================================================
CREATE TABLE logistics.notification_queue (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- Canal de envío
    channel             VARCHAR(20)     NOT NULL DEFAULT 'whatsapp',
    -- whatsapp | sms | email | push | slack | telegram

    -- Destinatario
    recipient_type      VARCHAR(20)     NOT NULL,
    -- customer | driver | warehouse_manager | picker | carrier | supplier
    recipient_id        BIGINT,
    -- ID del destinatario (según recipient_type)
    recipient_phone     VARCHAR(30),
    -- número de teléfono (para WhatsApp/SMS)
    recipient_email     VARCHAR(150),
    -- para email

    -- Contenido
    template_code       VARCHAR(50),
    -- código de plantilla aprobada (WhatsApp Business requiere plantillas)
    subject             VARCHAR(300),
    -- asunto (para email)
    message_body        TEXT            NOT NULL,
    -- cuerpo del mensaje (puede incluir variables)
    template_vars       JSONB,
    -- variables del template: {"order_number": "OD-1234", "eta": "15:00"}

    -- Referencia al evento que disparó la notificación
    trigger_type        VARCHAR(50),
    -- shipment_dispatched | delivery_confirmed | delivery_failed |
    -- stock_low | order_received | receipt_completed | wave_released
    trigger_reference_id BIGINT,

    -- Estado
    status              VARCHAR(20)     NOT NULL DEFAULT 'pending',
    -- pending | sending | sent | delivered | failed | cancelled

    -- Reintentos
    attempts            SMALLINT        NOT NULL DEFAULT 0,
    max_attempts        SMALLINT        NOT NULL DEFAULT 3,
    next_attempt_at     TIMESTAMPTZ,

    -- Respuesta del proveedor de notificaciones
    provider_message_id VARCHAR(200),
    -- ID del mensaje en WhatsApp Business / Twilio / AWS SNS
    provider_response   JSONB,
    error_message       TEXT,

    -- Prioridad
    priority            SMALLINT        NOT NULL DEFAULT 3,
    -- 1=urgente (entrega fallida) → 5=informativa

    scheduled_at        TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    sent_at             TIMESTAMPTZ,
    delivered_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_company  ON logistics.notification_queue (company_id);
CREATE INDEX idx_notifications_status   ON logistics.notification_queue (status)
    WHERE status IN ('pending', 'sending');
CREATE INDEX idx_notifications_schedule ON logistics.notification_queue (scheduled_at)
    WHERE status = 'pending';
CREATE INDEX idx_notifications_channel  ON logistics.notification_queue (channel);

CREATE TRIGGER trg_notifications_updated_at
    BEFORE UPDATE ON logistics.notification_queue
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.notification_queue         IS 'Cola de notificaciones multicanal: WhatsApp, SMS, Email, Push. Diferenciador para PYMEs peruanas.';
COMMENT ON COLUMN logistics.notification_queue.channel IS 'whatsapp=API Business de Meta, sms=Twilio/AWS, email=SES/SendGrid, push=Firebase.';
COMMENT ON COLUMN logistics.notification_queue.template_code IS 'Código de plantilla aprobada. WhatsApp Business exige plantillas pre-aprobadas para mensajes salientes.';

-- ============================================================
-- 3. HUELLA DE CARBONO POR ENVÍO
--    Diferenciador ESG: reportes de sostenibilidad para
--    empresas que necesitan medir su impacto ambiental.
-- ============================================================
CREATE TABLE logistics.shipment_carbon_footprint (
    id                      BIGSERIAL       PRIMARY KEY,
    shipment_id             BIGINT          NOT NULL REFERENCES logistics.shipments(id),
    company_id              BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- Datos del vehículo
    vehicle_type            VARCHAR(30)     NOT NULL DEFAULT 'diesel_truck',
    -- electric_van | diesel_truck | gasoline_van | motorcycle | bicycle | cargo_ship | airplane
    vehicle_fuel_type       VARCHAR(20)     NOT NULL DEFAULT 'diesel',
    -- diesel | gasoline | electric | hybrid | lpg

    -- Distancia
    distance_km             NUMERIC(10,2),
    -- kilómetros recorridos

    -- Carga
    cargo_weight_kg         NUMERIC(10,3),
    cargo_volume_m3         NUMERIC(10,6),

    -- Factores de emisión utilizados
    emission_factor_kg_per_km NUMERIC(10,6),
    -- kgCO₂/km para el tipo de vehículo
    emission_factor_source  VARCHAR(100),
    -- DEFRA 2024 | IPCC | EPA | CDP

    -- Resultado
    carbon_kg_co2           NUMERIC(12,4)   NOT NULL,
    -- kilogramos de CO₂ equivalente
    carbon_kg_co2_per_km    NUMERIC(10,6),
    -- intensidad: kgCO₂ / km
    carbon_kg_co2_per_kg    NUMERIC(10,6),
    -- intensidad: kgCO₂ / kg de carga

    -- Compensación (offsets)
    offset_kg_co2           NUMERIC(12,4)   NOT NULL DEFAULT 0,
    -- toneladas compensadas con créditos de carbono
    net_carbon_kg_co2       NUMERIC(12,4)
        GENERATED ALWAYS AS (carbon_kg_co2 - offset_kg_co2) STORED,
    -- huella neta

    calculation_method      VARCHAR(20)     NOT NULL DEFAULT 'estimated',
    -- estimated | carrier_reported | gps_calculated

    notes                   TEXT,
    calculated_at           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_carbon_shipment ON logistics.shipment_carbon_footprint (shipment_id);
CREATE INDEX idx_carbon_company  ON logistics.shipment_carbon_footprint (company_id);

COMMENT ON TABLE  logistics.shipment_carbon_footprint            IS 'Huella de carbono por envío. Para reportes ESG y certificaciones de sostenibilidad.';
COMMENT ON COLUMN logistics.shipment_carbon_footprint.net_carbon_kg_co2 IS 'Calculado: CO₂ total - compensaciones. Para declarar huella neta en reportes.';

-- ============================================================
-- 4. LECTURAS DE SENSORES IOT
--    Complementa logistics.location_sensors (definido en 05).
--    Almacena el histórico completo de lecturas.
-- ============================================================
CREATE TABLE logistics.sensor_readings (
    id              BIGSERIAL       PRIMARY KEY,
    sensor_id       BIGINT          NOT NULL REFERENCES logistics.location_sensors(id),
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    reading_value   NUMERIC(12,4)   NOT NULL,
    -- temperatura °C, humedad %, peso kg, etc.
    reading_unit    VARCHAR(10),
    -- °C | % | kg | lux | ppm

    -- ¿Generó alerta?
    is_alert        BOOLEAN         NOT NULL DEFAULT FALSE,
    alert_type      VARCHAR(20),
    -- too_high | too_low | offline | battery_low

    read_at         TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sensor_readings_sensor ON logistics.sensor_readings (sensor_id);
CREATE INDEX idx_sensor_readings_date   ON logistics.sensor_readings (read_at);
CREATE INDEX idx_sensor_readings_alert  ON logistics.sensor_readings (company_id, is_alert)
    WHERE is_alert = TRUE;

COMMENT ON TABLE  logistics.sensor_readings          IS 'Historial de lecturas IoT de sensores de temperatura, humedad y peso.';
COMMENT ON COLUMN logistics.sensor_readings.is_alert IS 'TRUE si la lectura superó los límites del sensor. Dispara notificación en notification_queue.';

-- ============================================================
-- 5. ALERTAS DEL SISTEMA
--    Centraliza alertas de stock bajo, vencimientos próximos,
--    sensores fuera de rango, robots con batería baja, etc.
-- ============================================================
CREATE TABLE logistics.system_alerts (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    warehouse_id        BIGINT          REFERENCES logistics.warehouses(id),

    alert_type          VARCHAR(50)     NOT NULL,
    -- stock_below_min | stock_below_reorder | lot_expiring_soon |
    -- lot_expired | sensor_out_of_range | robot_battery_low |
    -- robot_offline | dock_overdue | wave_stalled | short_pick_rate_high

    severity            VARCHAR(10)     NOT NULL DEFAULT 'warning',
    -- info | warning | critical

    -- Referencia al objeto que generó la alerta
    reference_type      VARCHAR(50),
    -- product | lot | location | robot | sensor | wave | dock
    reference_id        BIGINT,

    title               VARCHAR(200)    NOT NULL,
    description         TEXT,

    -- Estado
    status              VARCHAR(20)     NOT NULL DEFAULT 'open',
    -- open | acknowledged | resolved | suppressed

    acknowledged_by     BIGINT,
    -- employee_id
    acknowledged_at     TIMESTAMPTZ,
    resolved_at         TIMESTAMPTZ,

    -- Si se envió notificación
    notification_sent   BOOLEAN         NOT NULL DEFAULT FALSE,
    notification_id     BIGINT          REFERENCES logistics.notification_queue(id),

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_system_alerts_company  ON logistics.system_alerts (company_id);
CREATE INDEX idx_system_alerts_status   ON logistics.system_alerts (status)
    WHERE status IN ('open', 'acknowledged');
CREATE INDEX idx_system_alerts_severity ON logistics.system_alerts (severity)
    WHERE severity = 'critical';
CREATE INDEX idx_system_alerts_type     ON logistics.system_alerts (alert_type);

CREATE TRIGGER trg_system_alerts_updated_at
    BEFORE UPDATE ON logistics.system_alerts
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.system_alerts          IS 'Centro de alertas del WMS: stock bajo, vencimientos, sensores, robots, waves paradas.';
COMMENT ON COLUMN logistics.system_alerts.severity IS 'info=informativa, warning=atención requerida, critical=acción inmediata necesaria.';

-- ============================================================
-- 6. FK DIFERIDAS — ahora que outbound_orders existe,
--    agregamos las referencias que quedaron pendientes.
-- ============================================================

-- wave_orders → outbound_orders
ALTER TABLE logistics.wave_orders
    ADD CONSTRAINT fk_wave_orders_outbound_order
    FOREIGN KEY (outbound_order_id)
    REFERENCES logistics.outbound_orders(id)
    ON DELETE RESTRICT;

-- inventory_allocations → outbound_order_lines
ALTER TABLE logistics.inventory_allocations
    ADD CONSTRAINT fk_allocations_outbound_line
    FOREIGN KEY (outbound_order_line_id)
    REFERENCES logistics.outbound_order_lines(id)
    ON DELETE RESTRICT;

-- inventory_allocations → pick_tasks (referencia circular resuelta al final)
ALTER TABLE logistics.inventory_allocations
    ADD CONSTRAINT fk_allocations_pick_task
    FOREIGN KEY (pick_task_id)
    REFERENCES logistics.pick_tasks(id)
    ON DELETE SET NULL;

COMMENT ON TABLE logistics.system_alerts IS 'Centro de alertas del WMS. FK diferidas resueltas al final del archivo 13 (después de crear todas las tablas).';
