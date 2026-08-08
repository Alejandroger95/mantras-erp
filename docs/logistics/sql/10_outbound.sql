-- ============================================================
-- mantrasdb | Módulo Logistics
-- Archivo: 10_outbound.sql
-- Descripción: Flujo de salida — órdenes de despacho, empaque,
--              envíos, rutas, paradas, entregas y devoluciones
--              de clientes.
--
-- Flujo:
--   outbound_order → wave → pick → pack_task → shipment
--   → route → route_stops → delivery → delivery_proof
-- ============================================================

-- ============================================================
-- Órdenes de salida (outbound orders)
-- Soporta B2B y B2C, ventas, transferencias y devoluciones
-- ============================================================
CREATE TABLE logistics.outbound_orders (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    warehouse_id        BIGINT          NOT NULL REFERENCES logistics.warehouses(id) ON DELETE RESTRICT,
    order_status_id     INTEGER         NOT NULL REFERENCES logistics.order_statuses(id),
    order_type_id       INTEGER         NOT NULL REFERENCES logistics.order_types(id),

    order_number        VARCHAR(50)     NOT NULL,
    external_reference  VARCHAR(100),
    -- número de pedido del cliente / sistema externo

    -- Cliente (B2B o B2C)
    customer_type       VARCHAR(10)     NOT NULL DEFAULT 'b2b',
    -- b2b | b2c
    customer_id         BIGINT,
    -- si B2B: ID de la empresa cliente (HR o futuro módulo CRM)
    customer_name       VARCHAR(300),
    customer_tax_id     VARCHAR(50),
    customer_email      VARCHAR(150),
    customer_phone      VARCHAR(30),

    -- Dirección de entrega
    delivery_address    VARCHAR(300)    NOT NULL,
    delivery_city       VARCHAR(100),
    delivery_state      VARCHAR(100),
    delivery_country    VARCHAR(100)    NOT NULL DEFAULT 'PE',
    delivery_zip        VARCHAR(20),
    delivery_latitude   NUMERIC(10,7),
    delivery_longitude  NUMERIC(10,7),
    delivery_reference  VARCHAR(300),
    -- referencia de entrega: "Casa azul, frente al parque"
    delivery_contact    VARCHAR(150),
    delivery_phone      VARCHAR(30),

    -- Fechas
    order_date          DATE            NOT NULL DEFAULT CURRENT_DATE,
    requested_date      DATE,
    -- fecha solicitada por el cliente
    promised_date       DATE,
    -- fecha prometida al cliente
    shipped_date        DATE,
    delivered_date      DATE,

    -- Prioridad
    priority            SMALLINT        NOT NULL DEFAULT 3,
    -- 1=urgente, 2=alta, 3=normal, 4=baja, 5=económica

    -- Moneda y totales
    currency            VARCHAR(10)     NOT NULL DEFAULT 'PEN',
    subtotal            NUMERIC(18,4)   NOT NULL DEFAULT 0,
    tax_amount          NUMERIC(18,4)   NOT NULL DEFAULT 0,
    discount_amount     NUMERIC(18,4)   NOT NULL DEFAULT 0,
    total_amount        NUMERIC(18,4)   NOT NULL DEFAULT 0,

    -- Transportista preferido
    carrier_id          BIGINT          REFERENCES logistics.carriers(id),
    carrier_service_id  BIGINT          REFERENCES logistics.carrier_services(id),

    -- Huella de carbono (diferenciador)
    carbon_kg_co2       NUMERIC(10,4),
    -- CO₂ estimado del envío en kg

    -- Referencia a wave asignada
    wave_id             BIGINT          REFERENCES logistics.waves(id),

    notes               TEXT,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, order_number)
);

CREATE INDEX idx_outbound_orders_company  ON logistics.outbound_orders (company_id);
CREATE INDEX idx_outbound_orders_status   ON logistics.outbound_orders (order_status_id);
CREATE INDEX idx_outbound_orders_date     ON logistics.outbound_orders (order_date);
CREATE INDEX idx_outbound_orders_priority ON logistics.outbound_orders (priority);

CREATE TRIGGER trg_outbound_orders_updated_at
    BEFORE UPDATE ON logistics.outbound_orders
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.outbound_orders               IS 'Órdenes de salida: ventas B2B/B2C, transferencias y devoluciones.';
COMMENT ON COLUMN logistics.outbound_orders.priority      IS '1=urgente → 5=económica. Determina qué órdenes entran primero a las waves.';
COMMENT ON COLUMN logistics.outbound_orders.carbon_kg_co2 IS 'CO₂ estimado del envío en kg. Diferenciador: reporte de huella de carbono por orden.';

-- ============================================================
-- Líneas de orden de salida
-- ============================================================
CREATE TABLE logistics.outbound_order_lines (
    id                      BIGSERIAL       PRIMARY KEY,
    outbound_order_id       BIGINT          NOT NULL REFERENCES logistics.outbound_orders(id) ON DELETE RESTRICT,
    product_id              BIGINT          NOT NULL REFERENCES logistics.products(id),
    variant_id              BIGINT          REFERENCES logistics.product_variants(id),
    unit_id                 INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),

    line_number             INTEGER         NOT NULL,
    quantity_ordered        NUMERIC(18,4)   NOT NULL,
    quantity_allocated      NUMERIC(18,4)   NOT NULL DEFAULT 0,
    quantity_picked         NUMERIC(18,4)   NOT NULL DEFAULT 0,
    quantity_packed         NUMERIC(18,4)   NOT NULL DEFAULT 0,
    quantity_shipped        NUMERIC(18,4)   NOT NULL DEFAULT 0,

    unit_price              NUMERIC(18,6)   NOT NULL DEFAULT 0,
    discount_pct            NUMERIC(5,2)    NOT NULL DEFAULT 0,
    tax_pct                 NUMERIC(5,2)    NOT NULL DEFAULT 0,

    -- Para kits virtuales: se descompone aquí antes del picking
    is_kit_line             BOOLEAN         NOT NULL DEFAULT FALSE,
    kit_product_id          BIGINT          REFERENCES logistics.products(id),
    -- producto kit padre (si esta línea es un componente de kit virtual)

    notes                   TEXT,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (outbound_order_id, line_number)
);

CREATE INDEX idx_outbound_lines_order   ON logistics.outbound_order_lines (outbound_order_id);
CREATE INDEX idx_outbound_lines_product ON logistics.outbound_order_lines (product_id);

CREATE TRIGGER trg_outbound_lines_updated_at
    BEFORE UPDATE ON logistics.outbound_order_lines
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.outbound_order_lines IS 'Líneas de la orden de salida con tracking de cantidad por etapa: allocated, picked, packed, shipped.';

-- ============================================================
-- Tareas de empaque (pack)
-- ============================================================
CREATE TABLE logistics.pack_tasks (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    wave_id             BIGINT          NOT NULL REFERENCES logistics.waves(id) ON DELETE RESTRICT,
    pack_status_id      INTEGER         NOT NULL REFERENCES logistics.pack_statuses(id),

    task_number         VARCHAR(50)     NOT NULL,

    -- Estación de empaque
    pack_station        VARCHAR(50),
    -- código de la estación física

    -- Quién empaca
    performed_by_type   VARCHAR(10)     NOT NULL DEFAULT 'human',
    performed_by_id     BIGINT,

    -- Contenedor resultado del empaque
    output_container_id BIGINT          REFERENCES logistics.containers(id),

    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    notes               TEXT,

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, task_number)
);

CREATE INDEX idx_pack_tasks_wave ON logistics.pack_tasks (wave_id);

CREATE TRIGGER trg_pack_tasks_updated_at
    BEFORE UPDATE ON logistics.pack_tasks
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.pack_tasks IS 'Tareas de empaque en estación de packing. Consolida el pick en cajas/pallets para envío.';

-- ============================================================
-- Detalle de empaque
-- ============================================================
CREATE TABLE logistics.pack_task_details (
    id                  BIGSERIAL       PRIMARY KEY,
    pack_task_id        BIGINT          NOT NULL REFERENCES logistics.pack_tasks(id),
    pick_task_detail_id BIGINT          NOT NULL REFERENCES logistics.pick_task_details(id),
    product_id          BIGINT          NOT NULL REFERENCES logistics.products(id),
    lot_id              BIGINT          REFERENCES logistics.lots(id),
    unit_id             INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),
    container_id        BIGINT          REFERENCES logistics.containers(id),

    quantity_packed     NUMERIC(18,4)   NOT NULL,

    -- Foto del empaque (diferenciador)
    photo_url           VARCHAR(500),
    photo_taken_at      TIMESTAMPTZ,

    packed_at           TIMESTAMPTZ,
    notes               TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_pack_details_task ON logistics.pack_task_details (pack_task_id);

COMMENT ON TABLE logistics.pack_task_details IS 'Detalle de lo empacado por tarea. Incluye foto como evidencia del estado al despachar.';

-- ============================================================
-- Envíos (shipments)
-- ============================================================
CREATE TABLE logistics.shipments (
    id                      BIGSERIAL       PRIMARY KEY,
    company_id              BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    warehouse_id            BIGINT          NOT NULL REFERENCES logistics.warehouses(id) ON DELETE RESTRICT,
    shipment_status_id      INTEGER         NOT NULL REFERENCES logistics.shipment_statuses(id),
    carrier_id              BIGINT          NOT NULL REFERENCES logistics.carriers(id),
    carrier_service_id      BIGINT          REFERENCES logistics.carrier_services(id),

    shipment_number         VARCHAR(50)     NOT NULL,
    tracking_number         VARCHAR(200),
    -- código de rastreo del transportista

    -- Vehículo
    truck_plate             VARCHAR(30),
    driver_name             VARCHAR(150),
    driver_document         VARCHAR(50),
    driver_phone            VARCHAR(30),

    -- Muelle de salida
    dock_id                 BIGINT          REFERENCES logistics.docks(id),

    -- Totales
    total_weight_kg         NUMERIC(10,3),
    total_volume_m3         NUMERIC(10,6),
    total_packages          INTEGER,

    -- Huella de carbono calculada (diferenciador)
    carbon_kg_co2           NUMERIC(10,4),
    carbon_calculation_method VARCHAR(50),
    -- estimated | carrier_reported | calculated

    -- Fechas
    pickup_date             DATE,
    estimated_delivery_date DATE,
    actual_delivery_date    DATE,

    shipped_at              TIMESTAMPTZ,
    -- cuando salió del almacén
    delivered_at            TIMESTAMPTZ,

    -- SUNAT GRE (diferenciador Perú)
    gre_number              VARCHAR(50),
    -- número de guía de remisión electrónica
    gre_status              VARCHAR(20),
    -- draft | sent | accepted | rejected

    notes                   TEXT,
    is_active               BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, shipment_number)
);

CREATE INDEX idx_shipments_company  ON logistics.shipments (company_id);
CREATE INDEX idx_shipments_status   ON logistics.shipments (shipment_status_id);
CREATE INDEX idx_shipments_carrier  ON logistics.shipments (carrier_id);
CREATE INDEX idx_shipments_tracking ON logistics.shipments (tracking_number) WHERE tracking_number IS NOT NULL;

CREATE TRIGGER trg_shipments_updated_at
    BEFORE UPDATE ON logistics.shipments
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.shipments            IS 'Envíos consolidados con transportista. Puede contener múltiples órdenes.';
COMMENT ON COLUMN logistics.shipments.gre_number IS 'Guía de Remisión Electrónica SUNAT (Perú). Obligatoria para transporte de mercadería.';

-- ============================================================
-- Líneas del envío (qué órdenes/productos van en cada envío)
-- ============================================================
CREATE TABLE logistics.shipment_lines (
    id                      BIGSERIAL       PRIMARY KEY,
    shipment_id             BIGINT          NOT NULL REFERENCES logistics.shipments(id),
    outbound_order_id       BIGINT          NOT NULL REFERENCES logistics.outbound_orders(id),
    outbound_order_line_id  BIGINT          NOT NULL REFERENCES logistics.outbound_order_lines(id),
    product_id              BIGINT          NOT NULL REFERENCES logistics.products(id),
    lot_id                  BIGINT          REFERENCES logistics.lots(id),
    container_id            BIGINT          REFERENCES logistics.containers(id),
    unit_id                 INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),

    quantity_shipped        NUMERIC(18,4)   NOT NULL,
    notes                   TEXT,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_shipment_lines_shipment ON logistics.shipment_lines (shipment_id);
CREATE INDEX idx_shipment_lines_order    ON logistics.shipment_lines (outbound_order_id);

COMMENT ON TABLE logistics.shipment_lines IS 'Qué productos y órdenes van en cada envío.';

-- ============================================================
-- Rutas de entrega
-- ============================================================
CREATE TABLE logistics.routes (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    shipment_id         BIGINT          NOT NULL REFERENCES logistics.shipments(id),

    route_number        VARCHAR(50)     NOT NULL,

    -- Vehículo y conductor (puede heredar del shipment o diferir)
    truck_plate         VARCHAR(30),
    driver_name         VARCHAR(150),
    driver_phone        VARCHAR(30),

    -- Tiempos
    planned_start       TIMESTAMPTZ,
    actual_start        TIMESTAMPTZ,
    planned_end         TIMESTAMPTZ,
    actual_end          TIMESTAMPTZ,

    -- Totales
    total_stops         INTEGER         NOT NULL DEFAULT 0,
    total_distance_km   NUMERIC(10,2),
    total_weight_kg     NUMERIC(10,3),

    status              VARCHAR(20)     NOT NULL DEFAULT 'planned',
    -- planned | in_progress | completed | cancelled

    notes               TEXT,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, route_number)
);

CREATE TRIGGER trg_routes_updated_at
    BEFORE UPDATE ON logistics.routes
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.routes IS 'Rutas de entrega asignadas a un vehículo. Contiene múltiples paradas secuenciadas.';

-- ============================================================
-- Paradas de ruta (route stops)
-- ============================================================
CREATE TABLE logistics.route_stops (
    id                  BIGSERIAL       PRIMARY KEY,
    route_id            BIGINT          NOT NULL REFERENCES logistics.routes(id) ON DELETE RESTRICT,
    outbound_order_id   BIGINT          NOT NULL REFERENCES logistics.outbound_orders(id),

    stop_sequence       INTEGER         NOT NULL,
    -- orden de visita en la ruta

    -- Dirección de entrega (puede diferir de la de la orden si se consolidó)
    delivery_address    VARCHAR(300)    NOT NULL,
    delivery_city       VARCHAR(100),
    delivery_latitude   NUMERIC(10,7),
    delivery_longitude  NUMERIC(10,7),
    delivery_contact    VARCHAR(150),
    delivery_phone      VARCHAR(30),

    -- Ventana horaria acordada con el cliente
    time_window_from    TIME,
    time_window_to      TIME,

    -- Tiempos reales
    estimated_arrival   TIMESTAMPTZ,
    actual_arrival      TIMESTAMPTZ,
    actual_departure    TIMESTAMPTZ,

    -- Estado de la entrega
    status              VARCHAR(20)     NOT NULL DEFAULT 'pending',
    -- pending | in_transit | arrived | delivered | failed | rescheduled

    failure_reason      VARCHAR(200),
    -- address_not_found | refused | absent | access_denied | other

    notes               TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (route_id, stop_sequence)
);

CREATE INDEX idx_route_stops_route ON logistics.route_stops (route_id);
CREATE INDEX idx_route_stops_order ON logistics.route_stops (outbound_order_id);

CREATE TRIGGER trg_route_stops_updated_at
    BEFORE UPDATE ON logistics.route_stops
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.route_stops              IS 'Paradas de cada ruta de entrega con ventana horaria y estado.';
COMMENT ON COLUMN logistics.route_stops.stop_sequence IS 'Orden secuencial de visita. El sistema puede optimizar esta secuencia.';

-- ============================================================
-- Prueba de entrega (proof of delivery)
-- ============================================================
CREATE TABLE logistics.delivery_proofs (
    id                  BIGSERIAL       PRIMARY KEY,
    route_stop_id       BIGINT          NOT NULL REFERENCES logistics.route_stops(id) ON DELETE RESTRICT,

    -- Quién recibió
    received_by_name    VARCHAR(150)    NOT NULL,
    received_by_document VARCHAR(50),
    -- DNI/CE de quien firma

    -- Evidencia
    signature_url       VARCHAR(500),
    -- firma digital del receptor
    photo_url           VARCHAR(500),
    -- foto de la entrega (diferenciador)
    photo_taken_at      TIMESTAMPTZ,

    -- Geolocalización de la entrega
    latitude            NUMERIC(10,7),
    longitude           NUMERIC(10,7),

    delivered_at        TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    notes               TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_delivery_proofs_stop ON logistics.delivery_proofs (route_stop_id);

COMMENT ON TABLE  logistics.delivery_proofs          IS 'Prueba de entrega: firma, foto y geolocalización. Evidencia ante reclamos del cliente.';
COMMENT ON COLUMN logistics.delivery_proofs.photo_url IS 'Foto tomada al momento de entregar. Diferenciador frente a SAP/Oracle para PYMEs peruanas.';

-- ============================================================
-- Eventos de tracking (GPS / estado en tiempo real)
-- ============================================================
CREATE TABLE logistics.tracking_events (
    id                  BIGSERIAL       PRIMARY KEY,
    shipment_id         BIGINT          NOT NULL REFERENCES logistics.shipments(id),
    route_id            BIGINT          REFERENCES logistics.routes(id),

    event_type          VARCHAR(30)     NOT NULL,
    -- departed | arrived_stop | delivered | failed | delayed | picked_up | in_customs
    event_description   VARCHAR(300),

    latitude            NUMERIC(10,7),
    longitude           NUMERIC(10,7),
    location_name       VARCHAR(200),

    event_source        VARCHAR(20)     NOT NULL DEFAULT 'system',
    -- system | carrier_api | driver_app | manual

    event_at            TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_tracking_events_shipment ON logistics.tracking_events (shipment_id);
CREATE INDEX idx_tracking_events_date     ON logistics.tracking_events (event_at);

COMMENT ON TABLE logistics.tracking_events IS 'Eventos GPS y de estado del envío en tiempo real. Alimenta el tracking del cliente.';

-- ============================================================
-- Citas de muelle (dock appointments)
-- ============================================================
CREATE TABLE logistics.dock_appointments (
    id                          BIGSERIAL       PRIMARY KEY,
    company_id                  BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    dock_id                     BIGINT          NOT NULL REFERENCES logistics.docks(id) ON DELETE RESTRICT,
    dock_appointment_status_id  INTEGER         NOT NULL REFERENCES logistics.dock_appointment_statuses(id),

    appointment_number          VARCHAR(50)     NOT NULL,
    appointment_type            VARCHAR(10)     NOT NULL DEFAULT 'inbound',
    -- inbound | outbound

    -- Referencia al documento
    purchase_order_id           BIGINT          REFERENCES logistics.purchase_orders(id),
    shipment_id                 BIGINT          REFERENCES logistics.shipments(id),

    -- Transportista
    carrier_id                  BIGINT          REFERENCES logistics.carriers(id),
    truck_plate                 VARCHAR(30),
    driver_name                 VARCHAR(150),
    driver_phone                VARCHAR(30),

    -- Ventana de tiempo
    scheduled_start             TIMESTAMPTZ     NOT NULL,
    scheduled_end               TIMESTAMPTZ     NOT NULL,
    actual_arrival              TIMESTAMPTZ,
    actual_departure            TIMESTAMPTZ,

    notes                       TEXT,
    is_active                   BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at                  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, appointment_number)
);

CREATE INDEX idx_dock_appointments_dock    ON logistics.dock_appointments (dock_id);
CREATE INDEX idx_dock_appointments_date    ON logistics.dock_appointments (scheduled_start);
CREATE INDEX idx_dock_appointments_status  ON logistics.dock_appointments (dock_appointment_status_id);

CREATE TRIGGER trg_dock_appointments_updated_at
    BEFORE UPDATE ON logistics.dock_appointments
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.dock_appointments IS 'Citas de muelle: programa cuándo llega/sale cada camión y a qué puerta.';

-- ============================================================
-- Devoluciones de clientes
-- ============================================================
CREATE TABLE logistics.customer_returns (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    outbound_order_id   BIGINT          NOT NULL REFERENCES logistics.outbound_orders(id),
    warehouse_id        BIGINT          NOT NULL REFERENCES logistics.warehouses(id),

    return_number       VARCHAR(50)     NOT NULL,
    return_reason       VARCHAR(200)    NOT NULL,
    -- damaged | wrong_item | change_of_mind | defective | not_delivered

    status              VARCHAR(20)     NOT NULL DEFAULT 'requested',
    -- requested | approved | in_transit | received | inspected | restocked | scrapped | refunded

    -- Resultado de inspección
    inspection_result   VARCHAR(20),
    -- good | damaged | scrapped

    received_at         TIMESTAMPTZ,
    notes               TEXT,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, return_number)
);

CREATE TRIGGER trg_customer_returns_updated_at
    BEFORE UPDATE ON logistics.customer_returns
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.customer_returns IS 'Devoluciones de clientes: RMA (Return Merchandise Authorization).';

-- ============================================================
-- Líneas de devolución de cliente
-- ============================================================
CREATE TABLE logistics.customer_return_lines (
    id                      BIGSERIAL       PRIMARY KEY,
    return_id               BIGINT          NOT NULL REFERENCES logistics.customer_returns(id),
    outbound_order_line_id  BIGINT          NOT NULL REFERENCES logistics.outbound_order_lines(id),
    product_id              BIGINT          NOT NULL REFERENCES logistics.products(id),
    lot_id                  BIGINT          REFERENCES logistics.lots(id),
    unit_id                 INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),

    quantity_returned       NUMERIC(18,4)   NOT NULL,
    condition               VARCHAR(20)     NOT NULL DEFAULT 'unknown',
    -- good | damaged | scrapped
    restock_location_id     BIGINT          REFERENCES logistics.locations(id),
    -- dónde se vuelve a guardar (si está en buen estado)

    notes                   TEXT,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_customer_return_lines_return ON logistics.customer_return_lines (return_id);

COMMENT ON TABLE logistics.customer_return_lines IS 'Detalle de productos devueltos por cliente con estado de condición.';
