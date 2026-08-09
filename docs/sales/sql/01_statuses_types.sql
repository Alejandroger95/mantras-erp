-- ============================================================
-- mantrasdb | Módulo Sales
-- Archivo: 01_statuses_types.sql
-- Descripción: Schema sales, función updated_at y todos los
--              catálogos de estados y tipos del módulo de ventas.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS sales;

-- Función reutilizable para updated_at
CREATE OR REPLACE FUNCTION sales.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Estados de cotización
-- ============================================================
CREATE TABLE sales.quotation_statuses (
    id          SERIAL      PRIMARY KEY,
    code        VARCHAR(30) NOT NULL UNIQUE,
    name        VARCHAR(100) NOT NULL,
    description TEXT
);

INSERT INTO sales.quotation_statuses (code, name) VALUES
('draft',     'Borrador'),
('sent',      'Enviada al cliente'),
('reviewed',  'Revisada por el cliente'),
('approved',  'Aprobada'),
('rejected',  'Rechazada'),
('expired',   'Expirada'),
('converted', 'Convertida en orden');

-- ============================================================
-- Estados de orden de venta
-- ============================================================
CREATE TABLE sales.order_statuses (
    id          SERIAL      PRIMARY KEY,
    code        VARCHAR(30) NOT NULL UNIQUE,
    name        VARCHAR(100) NOT NULL,
    description TEXT
);

INSERT INTO sales.order_statuses (code, name) VALUES
('draft',           'Borrador'),
('confirmed',       'Confirmada'),
('in_fulfillment',  'En despacho'),
('partially_shipped','Enviada parcialmente'),
('shipped',         'Enviada'),
('delivered',       'Entregada'),
('invoiced',        'Facturada'),
('completed',       'Completada'),
('cancelled',       'Cancelada'),
('on_hold',         'En espera');

-- ============================================================
-- Tipos de orden de venta
-- ============================================================
CREATE TABLE sales.order_types (
    id          SERIAL      PRIMARY KEY,
    code        VARCHAR(30) NOT NULL UNIQUE,
    name        VARCHAR(100) NOT NULL,
    description TEXT
);

INSERT INTO sales.order_types (code, name) VALUES
('standard',    'Venta estándar'),
('urgent',      'Venta urgente'),
('consignment', 'Consignación'),
('sample',      'Muestra'),
('return',      'Devolución'),
('replacement', 'Reposición');

-- ============================================================
-- Estados de factura / comprobante
-- ============================================================
CREATE TABLE sales.invoice_statuses (
    id          SERIAL      PRIMARY KEY,
    code        VARCHAR(30) NOT NULL UNIQUE,
    name        VARCHAR(100) NOT NULL,
    description TEXT
);

INSERT INTO sales.invoice_statuses (code, name) VALUES
('draft',    'Borrador'),
('issued',   'Emitida'),
('sent',     'Enviada al cliente'),
('accepted', 'Aceptada por SUNAT'),
('rejected', 'Rechazada por SUNAT'),
('paid',     'Pagada'),
('partial',  'Pago parcial'),
('overdue',  'Vencida'),
('cancelled','Anulada'),
('voided',   'Nula');

-- ============================================================
-- Tipos de documento de venta (SUNAT Perú)
-- ============================================================
CREATE TABLE sales.document_types (
    id              SERIAL      PRIMARY KEY,
    code            VARCHAR(10) NOT NULL UNIQUE,
    -- código SUNAT: 01=factura, 03=boleta, 07=NC, 08=ND
    sunat_code      VARCHAR(10),
    name            VARCHAR(100) NOT NULL,
    description     TEXT,
    affects_tax     BOOLEAN NOT NULL DEFAULT TRUE,
    -- las boletas de personas naturales sin RUC no afectan IGV crédito fiscal
    is_active       BOOLEAN NOT NULL DEFAULT TRUE
);

INSERT INTO sales.document_types (code, sunat_code, name, affects_tax) VALUES
('FAC', '01', 'Factura',                    TRUE),
('BOL', '03', 'Boleta de venta',            FALSE),
('NC',  '07', 'Nota de crédito',            TRUE),
('ND',  '08', 'Nota de débito',             TRUE),
('LIQ', '02', 'Liquidación de compra',      TRUE),
('TKT', '12', 'Ticket / cinta de máquina',  FALSE),
('PRO', 'PR', 'Proforma (no SUNAT)',        FALSE);

COMMENT ON TABLE  sales.document_types            IS 'Tipos de comprobante de pago. Códigos SUNAT para facturación electrónica peruana.';
COMMENT ON COLUMN sales.document_types.sunat_code IS 'Código de tipo de comprobante en el catálogo SUNAT (catálogo N° 01).';

-- ============================================================
-- Estados de pago
-- ============================================================
CREATE TABLE sales.payment_statuses (
    id          SERIAL      PRIMARY KEY,
    code        VARCHAR(30) NOT NULL UNIQUE,
    name        VARCHAR(100) NOT NULL
);

INSERT INTO sales.payment_statuses (code, name) VALUES
('pending',   'Pendiente'),
('partial',   'Pago parcial'),
('paid',      'Pagado'),
('overdue',   'Vencido'),
('disputed',  'En disputa'),
('written_off','Castigado');

-- ============================================================
-- Métodos de pago
-- ============================================================
CREATE TABLE sales.payment_methods (
    id          SERIAL      PRIMARY KEY,
    code        VARCHAR(30) NOT NULL UNIQUE,
    name        VARCHAR(100) NOT NULL,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE
);

INSERT INTO sales.payment_methods (code, name) VALUES
('cash',         'Efectivo'),
('bank_transfer','Transferencia bancaria'),
('check',        'Cheque'),
('credit_card',  'Tarjeta de crédito'),
('debit_card',   'Tarjeta de débito'),
('yape',         'Yape'),
('plin',         'Plin'),
('paypal',       'PayPal'),
('credit_line',  'Línea de crédito'),
('barter',       'Canje / trueque');

COMMENT ON TABLE sales.payment_methods IS 'Métodos de pago aceptados. Incluye billeteras digitales peruanas (Yape, Plin).';

-- ============================================================
-- Tipos de descuento
-- ============================================================
CREATE TABLE sales.discount_types (
    id          SERIAL      PRIMARY KEY,
    code        VARCHAR(30) NOT NULL UNIQUE,
    name        VARCHAR(100) NOT NULL,
    description TEXT
);

INSERT INTO sales.discount_types (code, name) VALUES
('commercial',  'Descuento comercial'),
('volume',      'Descuento por volumen'),
('promo',       'Descuento promocional'),
('loyalty',     'Descuento por fidelidad'),
('seasonal',    'Descuento de temporada'),
('clearance',   'Liquidación'),
('employee',    'Descuento empleado');

-- ============================================================
-- Estados de cobranza
-- ============================================================
CREATE TABLE sales.collection_statuses (
    id          SERIAL      PRIMARY KEY,
    code        VARCHAR(30) NOT NULL UNIQUE,
    name        VARCHAR(100) NOT NULL
);

INSERT INTO sales.collection_statuses (code, name) VALUES
('pending',    'Pendiente'),
('in_process', 'En gestión'),
('promise',    'Promesa de pago'),
('legal',      'En proceso legal'),
('paid',       'Cobrado'),
('written_off','Castigado');
