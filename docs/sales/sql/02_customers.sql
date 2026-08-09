-- ============================================================
-- mantrasdb | Módulo Sales
-- Archivo: 02_customers.sql
-- Descripción: Clientes, contactos, grupos y condiciones
--              comerciales por cliente.
--
-- Diseño:
--   Un cliente puede ser persona natural (B2C) o empresa (B2B).
--   Los contactos son las personas dentro de la empresa cliente
--   con quienes se negocia/coordina.
-- ============================================================

-- ============================================================
-- Grupos de clientes (segmentación)
-- ============================================================
CREATE TABLE sales.customer_groups (
    id          BIGSERIAL   PRIMARY KEY,
    company_id  BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    code        VARCHAR(30) NOT NULL,
    name        VARCHAR(100) NOT NULL,
    description TEXT,
    is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (company_id, code)
);

CREATE TRIGGER trg_customer_groups_updated_at
    BEFORE UPDATE ON sales.customer_groups
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE sales.customer_groups IS 'Segmentación de clientes: mayoristas, minoristas, distribuidores, VIP, etc.';

-- ============================================================
-- Clientes
-- ============================================================
CREATE TABLE sales.customers (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    customer_group_id   BIGINT      REFERENCES sales.customer_groups(id),

    -- Tipo de cliente
    customer_type       VARCHAR(10) NOT NULL DEFAULT 'b2b',
    -- b2b = empresa | b2c = persona natural

    -- Identificación
    code                VARCHAR(30),
    -- código interno del cliente
    trade_name          VARCHAR(300) NOT NULL,
    -- nombre comercial / razón social
    legal_name          VARCHAR(300),
    -- nombre legal completo (si difiere del comercial)

    -- Tributario
    tax_id_type         VARCHAR(10) NOT NULL DEFAULT 'RUC',
    -- RUC | DNI | CE | PASSPORT (Perú) | NIT (Colombia) | RFC (México)
    tax_id              VARCHAR(20),
    -- RUC/DNI/CE del cliente

    -- Contacto principal
    email               VARCHAR(150),
    phone               VARCHAR(30),
    website             VARCHAR(200),

    -- WhatsApp (diferenciador)
    whatsapp            VARCHAR(30),
    -- número de WhatsApp para envío de comprobantes y notificaciones

    -- Condiciones comerciales
    credit_limit        NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- límite de crédito en la moneda base
    credit_days         INTEGER     NOT NULL DEFAULT 0,
    -- días de crédito (0 = contado)
    payment_terms       VARCHAR(100),
    -- descripción de condiciones: "30/60/90 días"
    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',

    -- Vendedor asignado
    sales_rep_id        BIGINT,
    -- REFERENCES sales.sales_reps(id) — FK diferida (tabla en 08)

    -- Clasificación
    abc_classification  VARCHAR(1),
    -- A=top, B=medio, C=bajo (por volumen de compra)

    -- Puntos de fidelidad (diferenciador)
    loyalty_points      INTEGER     NOT NULL DEFAULT 0,

    -- Estado
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, tax_id)
);

CREATE INDEX idx_customers_company   ON sales.customers (company_id);
CREATE INDEX idx_customers_group     ON sales.customers (customer_group_id);
CREATE INDEX idx_customers_tax_id    ON sales.customers (company_id, tax_id);
CREATE INDEX idx_customers_sales_rep ON sales.customers (sales_rep_id);

CREATE TRIGGER trg_customers_updated_at
    BEFORE UPDATE ON sales.customers
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.customers                  IS 'Clientes B2B y B2C con condiciones comerciales, límite de crédito y fidelización.';
COMMENT ON COLUMN sales.customers.whatsapp         IS 'Número WhatsApp para envío automático de comprobantes y notificaciones de estado.';
COMMENT ON COLUMN sales.customers.abc_classification IS 'Clasificación ABC por volumen de compra. Actualizable por proceso batch mensual.';

-- ============================================================
-- Direcciones del cliente
-- ============================================================
CREATE TABLE sales.customer_addresses (
    id              BIGSERIAL   PRIMARY KEY,
    customer_id     BIGINT      NOT NULL REFERENCES sales.customers(id) ON DELETE RESTRICT,

    address_type    VARCHAR(20) NOT NULL DEFAULT 'billing',
    -- billing | shipping | both

    label           VARCHAR(100),
    -- "Oficina principal", "Almacén Ate", etc.

    address         VARCHAR(300) NOT NULL,
    district        VARCHAR(100),
    city            VARCHAR(100),
    state           VARCHAR(100),
    country         VARCHAR(100) NOT NULL DEFAULT 'PE',
    zip             VARCHAR(20),
    latitude        NUMERIC(10,7),
    longitude       NUMERIC(10,7),
    reference       VARCHAR(300),

    is_default      BOOLEAN     NOT NULL DEFAULT FALSE,
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_customer_addresses_customer ON sales.customer_addresses (customer_id);

CREATE TRIGGER trg_customer_addresses_updated_at
    BEFORE UPDATE ON sales.customer_addresses
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE sales.customer_addresses IS 'Direcciones de facturación y entrega por cliente. Un cliente puede tener varias.';

-- ============================================================
-- Contactos del cliente (personas dentro de la empresa)
-- ============================================================
CREATE TABLE sales.customer_contacts (
    id              BIGSERIAL   PRIMARY KEY,
    customer_id     BIGINT      NOT NULL REFERENCES sales.customers(id) ON DELETE RESTRICT,

    first_name      VARCHAR(150) NOT NULL,
    last_name       VARCHAR(150),
    position        VARCHAR(100),
    -- cargo: "Gerente de logística", "Jefe de compras"

    email           VARCHAR(150),
    phone           VARCHAR(30),
    whatsapp        VARCHAR(30),

    -- Permisos de negociación
    can_approve_orders  BOOLEAN NOT NULL DEFAULT FALSE,
    can_approve_quotes  BOOLEAN NOT NULL DEFAULT FALSE,

    is_primary      BOOLEAN     NOT NULL DEFAULT FALSE,
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_customer_contacts_customer ON sales.customer_contacts (customer_id);

CREATE TRIGGER trg_customer_contacts_updated_at
    BEFORE UPDATE ON sales.customer_contacts
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE sales.customer_contacts IS 'Contactos dentro de la empresa cliente: compradores, gerentes, logística.';

-- ============================================================
-- Historial crediticio del cliente
-- ============================================================
CREATE TABLE sales.customer_credit_history (
    id              BIGSERIAL   PRIMARY KEY,
    customer_id     BIGINT      NOT NULL REFERENCES sales.customers(id),
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    event_type      VARCHAR(30) NOT NULL,
    -- limit_increase | limit_decrease | payment_on_time | payment_late |
    -- default | credit_suspended | credit_restored

    old_credit_limit    NUMERIC(18,4),
    new_credit_limit    NUMERIC(18,4),
    old_credit_days     INTEGER,
    new_credit_days     INTEGER,

    reason          TEXT,
    performed_by    BIGINT,
    -- employee_id

    event_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_credit_history_customer ON sales.customer_credit_history (customer_id);

COMMENT ON TABLE sales.customer_credit_history IS 'Historial de cambios en condiciones de crédito del cliente. Auditoría completa.';
