-- ============================================================
-- mantrasdb | Módulo Sales
-- Archivo: 13_customer_extensions.sql
-- Descripción: Extensiones del módulo de clientes:
--   1. customer_categories: clasificación granular de clientes
--   2. customer_bank_accounts: múltiples cuentas bancarias
--      por cliente, con moneda y cuenta preferida por moneda
--
-- Por qué este archivo existe:
--   El archivo 02_customers.sql tiene el núcleo del cliente.
--   Aquí agregamos atributos que dependen de tablas creadas
--   después (ej: bank accounts depende del esquema sales ya completo).
--
-- Casos reales cubiertos:
--   Distribuidora XYZ tiene:
--     - Cuenta BCP soles S/ → para pagos normales
--     - Cuenta Interbank soles S/ → para facturas > S/10,000
--     - Cuenta Scotiabank USD → para exportaciones
--     → Quiere cobrar en la BCP PEN por defecto, pero USD en Scotia
--
--   Saga Falabella (key account B2B):
--     - 3 cuentas: BCP PEN (preferida), BBVA PEN, Citibank USD
--     - Tiene contrato anual, RUC 20100070970
--     - Categoría: key_account
--
--   Pedro García (B2C, bodega):
--     - 1 cuenta Yape (número celular 999123456)
--     - Categoría: retail_small
-- ============================================================

-- ============================================================
-- 1. CATEGORÍAS DE CLIENTE (más granular que customer_type)
--    customer_type: b2b | b2c (existente en customers)
--    customer_category: dentro de b2b o b2c, ¿qué tipo exactamente?
--
--    Ejemplos:
--      B2B → key_account, distributor, wholesaler, retailer_chain,
--             government, ngo, reseller
--      B2C → individual, professional (autónomo), microenterprise
-- ============================================================
CREATE TABLE sales.customer_categories (
    id              SERIAL      PRIMARY KEY,
    company_id      BIGINT      REFERENCES hr.companies(id),
    -- NULL = categoría global del sistema

    code            VARCHAR(30) NOT NULL,
    name            VARCHAR(100) NOT NULL,
    description     TEXT,

    applies_to      VARCHAR(10) NOT NULL DEFAULT 'both',
    -- b2b | b2c | both

    -- Configuración por defecto para clientes de esta categoría
    default_credit_days     INTEGER,
    -- días de crédito por defecto al crear un cliente de esta categoría
    default_payment_terms   VARCHAR(100),
    requires_credit_check   BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE = los clientes de esta categoría requieren revisión de crédito

    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (code)
);

-- Catálogo pre-cargado
INSERT INTO sales.customer_categories
    (code, name, applies_to, default_credit_days, requires_credit_check)
VALUES
    -- B2B
    ('KEY_ACCOUNT',     'Key Account / Cuenta Clave',    'b2b', 60,  TRUE),
    ('DISTRIBUTOR',     'Distribuidor',                  'b2b', 30,  TRUE),
    ('WHOLESALER',      'Mayorista',                     'b2b', 30,  FALSE),
    ('RETAILER_CHAIN',  'Cadena Minorista',              'b2b', 45,  TRUE),
    ('RETAILER_SMALL',  'Tienda / Bodega',               'b2b', 0,   FALSE),
    ('GOVERNMENT',      'Entidad Pública / Gobierno',    'b2b', 90,  FALSE),
    ('NGO',             'ONG / Sin Fines de Lucro',      'b2b', 30,  FALSE),
    ('RESELLER',        'Revendedor / Canal Indirecto',  'b2b', 30,  FALSE),
    ('EXPORTER',        'Exportador',                    'b2b', 45,  TRUE),
    -- B2C
    ('INDIVIDUAL',      'Persona Natural / Consumidor',  'b2c', 0,   FALSE),
    ('PROFESSIONAL',    'Profesional Independiente',     'b2c', 0,   FALSE),
    ('MICROENTERPRISE', 'Microempresa (RUS/Régimen Simple)', 'b2c', 0, FALSE);

COMMENT ON TABLE  sales.customer_categories                       IS 'Clasificación granular de clientes. Va más allá de b2b/b2c: key_account, distribuidor, mayorista, bodega, gobierno, etc.';
COMMENT ON COLUMN sales.customer_categories.default_credit_days   IS 'Días de crédito por defecto al crear un cliente de esta categoría. Se puede sobreescribir por cliente.';
COMMENT ON COLUMN sales.customer_categories.requires_credit_check IS 'TRUE = el equipo de crédito debe revisar antes de dar crédito.';

-- Agregar customer_category_id a la tabla customers
ALTER TABLE sales.customers
    ADD COLUMN customer_category_id INTEGER REFERENCES sales.customer_categories(id);

COMMENT ON COLUMN sales.customers.customer_category_id IS 'Categoría granular del cliente (key_account, distributor, wholesaler, individual, etc.). Complementa customer_type (b2b/b2c).';

-- ============================================================
-- 2. CUENTAS BANCARIAS DEL CLIENTE
--    Un cliente puede tener múltiples cuentas bancarias.
--    Cada moneda tiene su cuenta preferida (is_preferred_for_currency).
--
--    Casos:
--      - BCP Soles (preferida en PEN) → pagar facturas normales
--      - Scotiabank USD (preferida en USD) → pagar exportaciones
--      - Interbank Soles (secundaria) → backup
--      - Yape (número celular) → pagos rápidos B2C
--
--    Relación con cobros:
--      Cuando se emite una cobranza o transferencia al cliente
--      (ej: NC de rebate, devolución de pago), el sistema
--      sugiere la cuenta is_preferred_for_currency = TRUE
--      en la moneda del documento.
-- ============================================================
CREATE TABLE sales.customer_bank_accounts (
    id                  BIGSERIAL   PRIMARY KEY,
    customer_id         BIGINT      NOT NULL REFERENCES sales.customers(id) ON DELETE RESTRICT,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- Banco
    bank_name           VARCHAR(100) NOT NULL,
    -- "BCP", "Interbank", "BBVA", "Scotiabank", "BanBif", "Pichincha"
    -- "Santander", "BBVA España", "CaixaBank" (para España)
    bank_code           VARCHAR(20),
    -- código del banco (para transferencias interbancarias)
    -- Perú: código BN (100=BN, 9=BCP, 11=Interbank, 18=Scotiabank, etc.)
    swift_code          VARCHAR(20),
    -- para transferencias internacionales (BCRPPEPL, etc.)

    -- Cuenta
    account_type        VARCHAR(20) NOT NULL DEFAULT 'checking',
    -- checking  : cuenta corriente (más común en B2B)
    -- savings   : cuenta de ahorros
    -- digital   : billetera digital (Yape, Plin, Nequi, Bizum)
    -- other     : otro tipo

    account_number      VARCHAR(50),
    -- número de cuenta

    -- Perú: Código de Cuenta Interbancaria (CCI) — 20 dígitos
    cci                 VARCHAR(30),
    -- necesario para transferencias entre bancos distintos en Perú

    -- Internacional (IBAN — España, Europa)
    iban                VARCHAR(34),
    -- formato: ES91 2100 0418 4502 0005 1332

    -- Billeteras digitales (Yape, Plin, etc.)
    digital_wallet_type VARCHAR(20),
    -- yape | plin | nequi | bizum | mercadopago | paypal
    digital_wallet_id   VARCHAR(100),
    -- número de celular o ID de la billetera

    -- Moneda de la cuenta
    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',
    -- PEN | USD | EUR | COP | MXN | etc.

    -- ¿Es la cuenta preferida para esta moneda?
    is_preferred_for_currency BOOLEAN NOT NULL DEFAULT FALSE,
    -- Solo puede haber UNA cuenta con is_preferred=TRUE por (customer + currency)
    -- El sistema valida esto con el UNIQUE partial index de abajo

    -- Nombre del titular (puede diferir si es cuenta de tercero autorizado)
    account_holder_name VARCHAR(300),
    -- Ej: "DISTRIBUIDORA XYZ S.A.C." o "Pedro García Ríos"
    account_holder_tax_id VARCHAR(20),
    -- RUC/DNI del titular

    -- Verificación
    is_verified         BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE = el equipo de cobranzas verificó que la cuenta es correcta
    verified_by         BIGINT,
    -- REFERENCES hr.employees(id)
    verified_at         TIMESTAMPTZ,

    -- Etiqueta para el usuario
    label               VARCHAR(100),
    -- "BCP Soles (principal)", "Scotia USD exportaciones", "Yape personal"

    notes               TEXT,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_cust_bank_customer  ON sales.customer_bank_accounts (customer_id);
CREATE INDEX idx_cust_bank_currency  ON sales.customer_bank_accounts (customer_id, currency);

-- Garantiza que solo hay UNA cuenta preferida por cliente por moneda
CREATE UNIQUE INDEX uidx_cust_bank_preferred
    ON sales.customer_bank_accounts (customer_id, currency)
    WHERE is_preferred_for_currency = TRUE;
-- Este index único parcial es la clave:
-- permite múltiples cuentas en PEN pero solo UNA puede ser preferida.

CREATE TRIGGER trg_cust_bank_updated_at
    BEFORE UPDATE ON sales.customer_bank_accounts
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.customer_bank_accounts IS 'Cuentas bancarias del cliente. Un cliente puede tener varias cuentas (en soles, en dólares, Yape, etc.). Solo una puede ser la preferida por moneda.';
COMMENT ON COLUMN sales.customer_bank_accounts.currency                  IS 'Moneda de la cuenta: PEN | USD | EUR. Cada moneda tiene su cuenta preferida independiente.';
COMMENT ON COLUMN sales.customer_bank_accounts.is_preferred_for_currency IS 'TRUE = cuenta preferida para transferencias en esta moneda. Solo puede haber UNA por (cliente + moneda). El sistema la sugiere al hacer pagos.';
COMMENT ON COLUMN sales.customer_bank_accounts.cci                       IS 'Código de Cuenta Interbancaria (Perú). 20 dígitos. Necesario para transferencias entre bancos distintos.';
COMMENT ON COLUMN sales.customer_bank_accounts.iban                      IS 'IBAN para España/Europa. Formato: ES91 2100 0418 4502 0005 1332.';
COMMENT ON COLUMN sales.customer_bank_accounts.digital_wallet_type       IS 'yape | plin | nequi | bizum | mercadopago | paypal. Para pagos digitales en B2C.';
COMMENT ON COLUMN sales.customer_bank_accounts.is_verified               IS 'TRUE = el equipo de cobranzas verificó que la cuenta existe y es del cliente. Previene errores de transferencia.';

-- ============================================================
-- 3. REFERENCIAS A CUENTA BANCARIA EN PAGOS
--    Cuando se procesa un pago al cliente (NC de rebate,
--    devolución, etc.), se registra qué cuenta se usó.
-- ============================================================
ALTER TABLE sales.customer_payments
    ADD COLUMN customer_bank_account_id BIGINT REFERENCES sales.customer_bank_accounts(id);
-- Útil para saber a qué cuenta se envió el pago (en caso de NC/rebate/devolución)

COMMENT ON COLUMN sales.customer_payments.customer_bank_account_id IS 'Cuenta bancaria del cliente usada en este pago o transferencia. Trazabilidad de a dónde fue el dinero.';
