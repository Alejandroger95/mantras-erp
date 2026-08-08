-- ============================================================
-- mantrasdb | Módulo Logistics
-- Archivo: 01_statuses_types.sql
-- Descripción: Catálogos de estados y tipos — todas las tablas
--              de referencia del módulo. Se crean primero porque
--              el resto de tablas depende de estas como FK.
--
-- Diseño: Opción B (tablas separadas por entidad, estilo Oracle WMS)
--         Más claro para reportes y joins directos.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS logistics;

-- Función para actualizar updated_at automáticamente
CREATE OR REPLACE FUNCTION logistics.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Estados de órdenes de compra (inbound)
-- ============================================================
CREATE TABLE logistics.order_statuses (
    id          SERIAL          PRIMARY KEY,
    code        VARCHAR(50)     NOT NULL UNIQUE,
    -- draft | confirmed | in_progress | partially_received | completed | cancelled | on_hold
    name        VARCHAR(100)    NOT NULL,
    description TEXT,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

INSERT INTO logistics.order_statuses (code, name, description) VALUES
    ('draft',               'Borrador',             'Orden creada pero no confirmada'),
    ('confirmed',           'Confirmada',           'Orden confirmada con el proveedor'),
    ('in_progress',         'En proceso',           'Recepción iniciada parcialmente'),
    ('partially_received',  'Recibida parcial',     'Recibida con diferencias o incompleta'),
    ('completed',           'Completada',           'Recibida en su totalidad'),
    ('cancelled',           'Cancelada',            'Orden anulada'),
    ('on_hold',             'En espera',            'Pendiente de resolución');

COMMENT ON TABLE logistics.order_statuses IS 'Estados de órdenes de compra (inbound). Estilo Oracle WMS.';

-- ============================================================
-- Tipos de orden
-- ============================================================
CREATE TABLE logistics.order_types (
    id          SERIAL          PRIMARY KEY,
    code        VARCHAR(50)     NOT NULL UNIQUE,
    -- purchase | sale | transfer | return_supplier | return_customer | consignment | sample
    name        VARCHAR(100)    NOT NULL,
    direction   VARCHAR(10)     NOT NULL DEFAULT 'both',
    -- inbound | outbound | both
    description TEXT,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

INSERT INTO logistics.order_types (code, name, direction, description) VALUES
    ('purchase',            'Compra',               'inbound',  'Orden de compra a proveedor'),
    ('sale',                'Venta',                'outbound', 'Orden de venta a cliente'),
    ('transfer',            'Transferencia',        'both',     'Traslado entre almacenes o ubicaciones'),
    ('return_supplier',     'Devolución proveedor', 'outbound', 'Mercadería regresa al proveedor'),
    ('return_customer',     'Devolución cliente',   'inbound',  'Devolución de cliente al almacén'),
    ('consignment',         'Consignación',         'both',     'Mercadería en consignación'),
    ('sample',              'Muestra',              'outbound', 'Envío de muestras');

COMMENT ON TABLE logistics.order_types IS 'Tipos de orden: compra, venta, transferencia, devolución, consignación.';

-- ============================================================
-- Estados de recepción (receipt)
-- ============================================================
CREATE TABLE logistics.receipt_statuses (
    id          SERIAL          PRIMARY KEY,
    code        VARCHAR(50)     NOT NULL UNIQUE,
    -- pending | scheduled | in_progress | completed | discrepancy | rejected
    name        VARCHAR(100)    NOT NULL,
    description TEXT,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

INSERT INTO logistics.receipt_statuses (code, name, description) VALUES
    ('pending',       'Pendiente',        'Esperando llegada del proveedor'),
    ('scheduled',     'Programada',       'Cita de muelle asignada'),
    ('in_progress',   'En proceso',       'Descarga y conteo en curso'),
    ('completed',     'Completada',       'Recepción cerrada sin incidencias'),
    ('discrepancy',   'Con diferencia',   'Diferencia entre PO y recibido'),
    ('rejected',      'Rechazada',        'Mercadería rechazada en QC');

COMMENT ON TABLE logistics.receipt_statuses IS 'Estados del proceso de recepción física en muelle.';

-- ============================================================
-- Estados de envío (shipment)
-- ============================================================
CREATE TABLE logistics.shipment_statuses (
    id          SERIAL          PRIMARY KEY,
    code        VARCHAR(50)     NOT NULL UNIQUE,
    -- pending | assigned | loading | in_transit | delivered | failed | returned
    name        VARCHAR(100)    NOT NULL,
    description TEXT,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

INSERT INTO logistics.shipment_statuses (code, name, description) VALUES
    ('pending',       'Pendiente',        'Envío creado, aún sin transportista'),
    ('assigned',      'Asignado',         'Transportista y ruta asignados'),
    ('loading',       'Cargando',         'Mercadería siendo cargada en vehículo'),
    ('in_transit',    'En tránsito',      'Vehículo en camino'),
    ('delivered',     'Entregado',        'Entrega confirmada con prueba'),
    ('failed',        'Fallido',          'Intento de entrega sin éxito'),
    ('returned',      'Devuelto',         'Regresó al almacén sin entregar');

COMMENT ON TABLE logistics.shipment_statuses IS 'Estados del envío desde carga hasta entrega final.';

-- ============================================================
-- Estados de wave (ola de picking)
-- ============================================================
CREATE TABLE logistics.wave_statuses (
    id          SERIAL          PRIMARY KEY,
    code        VARCHAR(50)     NOT NULL UNIQUE,
    -- open | released | picking | completed | cancelled
    name        VARCHAR(100)    NOT NULL,
    description TEXT,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

INSERT INTO logistics.wave_statuses (code, name, description) VALUES
    ('open',        'Abierta',          'Wave creada, aceptando órdenes'),
    ('released',    'Liberada',         'Wave cerrada y tareas generadas'),
    ('picking',     'En picking',       'Pickers trabajando en esta wave'),
    ('completed',   'Completada',       'Todo pickeado y procesado'),
    ('cancelled',   'Cancelada',        'Wave anulada antes de completar');

COMMENT ON TABLE logistics.wave_statuses IS 'Estados de la ola de picking (wave).';

-- ============================================================
-- Estados de tarea de pick
-- ============================================================
CREATE TABLE logistics.pick_statuses (
    id          SERIAL          PRIMARY KEY,
    code        VARCHAR(50)     NOT NULL UNIQUE,
    -- pending | assigned | in_progress | completed | short_picked | cancelled
    name        VARCHAR(100)    NOT NULL,
    description TEXT,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

INSERT INTO logistics.pick_statuses (code, name, description) VALUES
    ('pending',       'Pendiente',        'Tarea generada, sin asignar'),
    ('assigned',      'Asignada',         'Asignada a picker o robot'),
    ('in_progress',   'En progreso',      'Picker en camino a la ubicación'),
    ('completed',     'Completada',       'Pick realizado en su totalidad'),
    ('short_picked',  'Short pick',       'Ubicación con menos stock del esperado'),
    ('cancelled',     'Cancelada',        'Tarea anulada');

COMMENT ON TABLE logistics.pick_statuses IS 'Estados de cada tarea individual de picking.';

-- ============================================================
-- Estados de tarea de pack (empaque)
-- ============================================================
CREATE TABLE logistics.pack_statuses (
    id          SERIAL          PRIMARY KEY,
    code        VARCHAR(50)     NOT NULL UNIQUE,
    -- pending | in_progress | completed | on_hold
    name        VARCHAR(100)    NOT NULL,
    description TEXT,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

INSERT INTO logistics.pack_statuses (code, name, description) VALUES
    ('pending',     'Pendiente',    'Esperando que llegue el pick'),
    ('in_progress', 'Empacando',    'En estación de empaque'),
    ('completed',   'Completado',   'Empacado y listo para despacho'),
    ('on_hold',     'En espera',    'Pausado por incidencia o revisión');

COMMENT ON TABLE logistics.pack_statuses IS 'Estados de las tareas de empaque en estación de packing.';

-- ============================================================
-- Estados de transferencia interna
-- ============================================================
CREATE TABLE logistics.transfer_statuses (
    id          SERIAL          PRIMARY KEY,
    code        VARCHAR(50)     NOT NULL UNIQUE,
    -- draft | approved | in_transit | completed | cancelled
    name        VARCHAR(100)    NOT NULL,
    description TEXT,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

INSERT INTO logistics.transfer_statuses (code, name, description) VALUES
    ('draft',       'Borrador',     'Transferencia creada sin aprobar'),
    ('approved',    'Aprobada',     'Autorizada para ejecutar'),
    ('in_transit',  'En tránsito',  'Mercadería moviéndose entre ubicaciones'),
    ('completed',   'Completada',   'Recibida en destino'),
    ('cancelled',   'Cancelada',    'Anulada antes de completar');

COMMENT ON TABLE logistics.transfer_statuses IS 'Estados de transferencias internas entre almacenes o ubicaciones.';

-- ============================================================
-- Tipos de ajuste de inventario
-- ============================================================
CREATE TABLE logistics.adjustment_types (
    id          SERIAL          PRIMARY KEY,
    code        VARCHAR(50)     NOT NULL UNIQUE,
    -- manual | count_adjustment | damage | expiry | kit_assembly | kit_disassembly | return | theft | system
    name        VARCHAR(100)    NOT NULL,
    affects_cost BOOLEAN        NOT NULL DEFAULT FALSE,
    -- indica si el ajuste debe actualizar el costo promedio
    description TEXT,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

INSERT INTO logistics.adjustment_types (code, name, affects_cost, description) VALUES
    ('manual',           'Ajuste manual',           TRUE,  'Corrección manual por error de sistema o conteo'),
    ('count_adjustment', 'Ajuste por conteo',       TRUE,  'Diferencia encontrada en conteo físico'),
    ('damage',           'Daño o merma',            TRUE,  'Producto dañado o en mal estado'),
    ('expiry',           'Vencimiento',             TRUE,  'Producto vencido dado de baja'),
    ('kit_assembly_out', 'Salida por ensamblaje',   FALSE, 'Componentes consumidos al armar un kit'),
    ('kit_assembly_in',  'Entrada por ensamblaje',  FALSE, 'Kit ensamblado ingresa al inventario'),
    ('kit_disassembly_out', 'Salida por desarmado', FALSE, 'Kit se deshace, sale del inventario'),
    ('kit_disassembly_in',  'Entrada por desarmado',FALSE, 'Componentes recuperados al desarmar kit'),
    ('return_customer',  'Devolución cliente',      FALSE, 'Mercadería devuelta por cliente'),
    ('return_supplier',  'Devolución proveedor',    FALSE, 'Mercadería enviada de vuelta al proveedor'),
    ('theft',            'Robo o pérdida',          TRUE,  'Producto reportado como robado o perdido'),
    ('system',           'Ajuste de sistema',       FALSE, 'Corrección automática del sistema');

COMMENT ON TABLE logistics.adjustment_types IS 'Tipos de ajuste de inventario con indicador de impacto en costo.';

-- ============================================================
-- Tipos de zona de almacén
-- ============================================================
CREATE TABLE logistics.zone_types (
    id          SERIAL          PRIMARY KEY,
    code        VARCHAR(50)     NOT NULL UNIQUE,
    -- receiving | storage | picking | shipping | quarantine | returns | staging | cross_dock
    name        VARCHAR(100)    NOT NULL,
    description TEXT,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

INSERT INTO logistics.zone_types (code, name, description) VALUES
    ('receiving',   'Recepción',        'Zona donde llega la mercadería del proveedor'),
    ('storage',     'Almacenaje',       'Zona de almacenamiento principal'),
    ('picking',     'Picking',          'Zona de alta rotación para picking rápido'),
    ('shipping',    'Despacho',         'Zona de consolidación y carga de envíos'),
    ('quarantine',  'Cuarentena',       'Productos en revisión de calidad o retenidos'),
    ('returns',     'Devoluciones',     'Zona de mercadería devuelta por clientes'),
    ('staging',     'Staging',          'Área temporal de preparación'),
    ('cross_dock',  'Cross-docking',    'Recibe y despacha sin almacenaje intermedio');

COMMENT ON TABLE logistics.zone_types IS 'Tipos de zona dentro del almacén.';

-- ============================================================
-- Tipos de ubicación (slot/bin)
-- ============================================================
CREATE TABLE logistics.location_types (
    id              SERIAL          PRIMARY KEY,
    code            VARCHAR(50)     NOT NULL UNIQUE,
    -- rack | floor | dock | bulk | virtual | refrigerated | hazmat
    name            VARCHAR(100)    NOT NULL,
    description     TEXT,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

INSERT INTO logistics.location_types (code, name, description) VALUES
    ('rack',         'Rack selectivo',    'Posición estándar en estantería de rack'),
    ('floor',        'Piso',             'Posición en piso (pallets completos)'),
    ('dock',         'Muelle',           'Ubicación virtual de muelle de carga'),
    ('bulk',         'Granel',           'Almacenaje a granel sin palletizar'),
    ('virtual',      'Virtual',          'Ubicación lógica sin espacio físico (sistema)'),
    ('refrigerated', 'Refrigerada',      'Ubicación con control de temperatura fría'),
    ('frozen',       'Congelada',        'Ubicación con temperatura bajo cero'),
    ('hazmat',       'Materiales peligrosos', 'Zona especial para productos peligrosos');

COMMENT ON TABLE logistics.location_types IS 'Tipos de ubicación física dentro del almacén.';

-- ============================================================
-- Tipos de servicio de transportista
-- ============================================================
CREATE TABLE logistics.carrier_service_types (
    id          SERIAL          PRIMARY KEY,
    code        VARCHAR(50)     NOT NULL UNIQUE,
    -- standard | express | same_day | refrigerated | hazmat | oversized | last_mile
    name        VARCHAR(100)    NOT NULL,
    description TEXT,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

INSERT INTO logistics.carrier_service_types (code, name, description) VALUES
    ('standard',        'Estándar',             'Entrega regular en plazo normal'),
    ('express',         'Express',              'Entrega prioritaria en 24-48h'),
    ('same_day',        'Mismo día',            'Entrega el mismo día del pedido'),
    ('refrigerated',    'Cadena de frío',       'Transporte con control de temperatura'),
    ('frozen',          'Congelado',            'Transporte en cadena de congelación'),
    ('hazmat',          'Materiales peligrosos','Transporte certificado para mercadería peligrosa'),
    ('oversized',       'Carga especial',       'Cargas de gran volumen o peso fuera de norma'),
    ('last_mile',       'Última milla',         'Entrega directa al consumidor final');

COMMENT ON TABLE logistics.carrier_service_types IS 'Tipos de servicio que ofrecen los transportistas.';

-- ============================================================
-- Tipos de kit / bundle
-- ============================================================
CREATE TABLE logistics.kit_types (
    id          SERIAL          PRIMARY KEY,
    code        VARCHAR(50)     NOT NULL UNIQUE,
    -- physical | virtual
    name        VARCHAR(100)    NOT NULL,
    description TEXT,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

INSERT INTO logistics.kit_types (code, name, description) VALUES
    ('physical', 'Kit físico',  'Se ensambla físicamente. Crea un nuevo SKU en inventario y consume los componentes.'),
    ('virtual',  'Kit virtual', 'Solo agrupación para la venta. Los componentes se descontarán individualmente al despachar.');

COMMENT ON TABLE logistics.kit_types IS 'Tipo de kit: físico (ensamblado, nuevo SKU) o virtual (agrupación lógica).';

-- ============================================================
-- Estados de cita de muelle (dock appointment)
-- ============================================================
CREATE TABLE logistics.dock_appointment_statuses (
    id          SERIAL          PRIMARY KEY,
    code        VARCHAR(50)     NOT NULL UNIQUE,
    -- scheduled | confirmed | arrived | in_progress | completed | no_show | cancelled
    name        VARCHAR(100)    NOT NULL,
    description TEXT,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

INSERT INTO logistics.dock_appointment_statuses (code, name, description) VALUES
    ('scheduled',   'Programada',   'Cita creada y hora asignada'),
    ('confirmed',   'Confirmada',   'Transportista confirmó la cita'),
    ('arrived',     'Llegó',        'Camión llegó al patio del almacén'),
    ('in_progress', 'En proceso',   'Carga o descarga en curso en el muelle'),
    ('completed',   'Completada',   'Operación finalizada y muelle liberado'),
    ('no_show',     'No se presentó', 'Transportista no llegó a la hora acordada'),
    ('cancelled',   'Cancelada',    'Cita anulada');

COMMENT ON TABLE logistics.dock_appointment_statuses IS 'Estados de las citas de muelle para inbound y outbound.';

-- ============================================================
-- Estados de inspección de calidad
-- ============================================================
CREATE TABLE logistics.inspection_statuses (
    id          SERIAL          PRIMARY KEY,
    code        VARCHAR(50)     NOT NULL UNIQUE,
    -- pending | in_progress | approved | approved_partial | rejected
    name        VARCHAR(100)    NOT NULL,
    description TEXT,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

INSERT INTO logistics.inspection_statuses (code, name, description) VALUES
    ('pending',          'Pendiente',            'En espera de inspector'),
    ('in_progress',      'En inspección',        'Inspector revisando la mercadería'),
    ('approved',         'Aprobada',             'Mercadería aprobada en su totalidad'),
    ('approved_partial', 'Aprobada parcial',     'Parte aprobada, parte rechazada o en cuarentena'),
    ('rejected',         'Rechazada',            'Toda la mercadería rechazada y en devolución');

COMMENT ON TABLE logistics.inspection_statuses IS 'Estados del proceso de inspección de calidad en recepción.';
