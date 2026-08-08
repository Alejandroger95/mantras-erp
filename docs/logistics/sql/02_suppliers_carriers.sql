-- ============================================================
-- mantrasdb | Módulo Logistics
-- Archivo: 02_suppliers_carriers.sql
-- Descripción: Proveedores y transportistas — los partners
--              externos que interactúan con el almacén.
-- ============================================================

-- ============================================================
-- Proveedores
-- ============================================================
CREATE TABLE logistics.suppliers (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- Identidad
    name            VARCHAR(200)    NOT NULL,
    trade_name      VARCHAR(200),
    tax_id          VARCHAR(50),
    -- RUC, NIF, CNPJ, etc. según el país

    -- Contacto principal
    contact_name    VARCHAR(150),
    phone           VARCHAR(30),
    email           VARCHAR(150),
    website         VARCHAR(200),

    -- Dirección principal
    address         VARCHAR(300),
    city            VARCHAR(100),
    state           VARCHAR(100),
    country         VARCHAR(100)    NOT NULL DEFAULT 'PE',
    zip_code        VARCHAR(20),

    -- Condiciones comerciales
    currency        VARCHAR(10)     NOT NULL DEFAULT 'PEN',
    -- PEN | USD | EUR
    payment_terms   VARCHAR(100),
    -- Ej: "30 días neto", "contado", "45 días"
    credit_limit    NUMERIC(18,2),
    lead_time_days  INTEGER,
    -- días promedio de entrega desde orden hasta recepción

    -- Clasificación
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    notes           TEXT,

    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_suppliers_company     ON logistics.suppliers (company_id);
CREATE INDEX idx_suppliers_tax_id      ON logistics.suppliers (tax_id) WHERE tax_id IS NOT NULL;
CREATE INDEX idx_suppliers_name        ON logistics.suppliers (name);

CREATE TRIGGER trg_suppliers_updated_at
    BEFORE UPDATE ON logistics.suppliers
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.suppliers              IS 'Proveedores de mercadería. Cada empresa tiene su propio catálogo.';
COMMENT ON COLUMN logistics.suppliers.lead_time_days IS 'Días promedio desde la orden de compra hasta la recepción en almacén.';

-- ============================================================
-- Direcciones de proveedores (puede tener múltiples)
-- ============================================================
CREATE TABLE logistics.supplier_addresses (
    id              BIGSERIAL       PRIMARY KEY,
    supplier_id     BIGINT          NOT NULL REFERENCES logistics.suppliers(id) ON DELETE RESTRICT,

    address_type    VARCHAR(50)     NOT NULL DEFAULT 'shipping',
    -- billing | shipping | returns | warehouse

    contact_name    VARCHAR(150),
    phone           VARCHAR(30),
    email           VARCHAR(150),
    address         VARCHAR(300)    NOT NULL,
    city            VARCHAR(100)    NOT NULL,
    state           VARCHAR(100),
    country         VARCHAR(100)    NOT NULL DEFAULT 'PE',
    zip_code        VARCHAR(20),

    is_default      BOOLEAN         NOT NULL DEFAULT FALSE,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_supplier_addresses_supplier ON logistics.supplier_addresses (supplier_id);

CREATE TRIGGER trg_supplier_addresses_updated_at
    BEFORE UPDATE ON logistics.supplier_addresses
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.supplier_addresses IS 'Direcciones del proveedor: facturación, despacho, devoluciones.';

-- ============================================================
-- Transportistas
-- ============================================================
CREATE TABLE logistics.carriers (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    name            VARCHAR(200)    NOT NULL,
    trade_name      VARCHAR(200),
    tax_id          VARCHAR(50),

    -- Contacto
    contact_name    VARCHAR(150),
    phone           VARCHAR(30),
    email           VARCHAR(150),
    tracking_url    VARCHAR(300),
    -- URL base para tracking: https://tracking.carrier.com/{tracking_number}

    -- Cobertura
    country         VARCHAR(100)    NOT NULL DEFAULT 'PE',
    covers_international BOOLEAN    NOT NULL DEFAULT FALSE,

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    notes           TEXT,

    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_carriers_company ON logistics.carriers (company_id);

CREATE TRIGGER trg_carriers_updated_at
    BEFORE UPDATE ON logistics.carriers
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.carriers IS 'Empresas transportistas disponibles para envíos.';

-- ============================================================
-- Servicios de transportista
-- ============================================================
CREATE TABLE logistics.carrier_services (
    id                      BIGSERIAL       PRIMARY KEY,
    carrier_id              BIGINT          NOT NULL REFERENCES logistics.carriers(id) ON DELETE RESTRICT,
    carrier_service_type_id INTEGER         NOT NULL REFERENCES logistics.carrier_service_types(id),

    code                    VARCHAR(100)    NOT NULL,
    name                    VARCHAR(200)    NOT NULL,

    -- Tiempos estimados
    transit_days_min        INTEGER,
    transit_days_max        INTEGER,

    -- Restricciones
    max_weight_kg           NUMERIC(10,3),
    max_volume_m3           NUMERIC(10,3),
    max_length_cm           NUMERIC(8,2),

    -- Tarifa base (puede variar, esto es referencial)
    base_rate               NUMERIC(12,2),
    currency                VARCHAR(10)     NOT NULL DEFAULT 'PEN',

    is_active               BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_carrier_services_carrier ON logistics.carrier_services (carrier_id);

CREATE TRIGGER trg_carrier_services_updated_at
    BEFORE UPDATE ON logistics.carrier_services
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.carrier_services IS 'Servicios específicos de cada transportista: estándar, express, cadena de frío, etc.';
