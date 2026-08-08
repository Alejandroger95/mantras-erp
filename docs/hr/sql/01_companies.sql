-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.companies
-- Descripción: Tenant raíz del sistema multi-empresa.
--              Toda entidad del ERP pertenece a una empresa.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS hr;

CREATE TABLE hr.companies (
    id                  BIGSERIAL       PRIMARY KEY,

    -- Identificación
    name                VARCHAR(200)    NOT NULL,
    trade_name          VARCHAR(200),
    tax_id              VARCHAR(20),                        -- RFC (MX), NIT (CO), RUC (PE/EC), CNPJ (BR), EIN (US)
    id_type             VARCHAR(20)     DEFAULT 'RFC',      -- RFC | NIT | RUC | CNPJ | EIN | otro

    -- Contacto
    phone               VARCHAR(30),
    email               VARCHAR(150),
    website             VARCHAR(200),

    -- Dirección fiscal
    address             TEXT,
    neighborhood        VARCHAR(150),
    city                VARCHAR(150),
    state               VARCHAR(150),
    country             VARCHAR(100)    DEFAULT 'Mexico',
    zip_code            VARCHAR(20),

    -- Configuración regional
    currency            CHAR(3)         DEFAULT 'USD',      -- ISO 4217
    timezone            VARCHAR(60)     DEFAULT 'America/Mexico_City',
    language            VARCHAR(10)     DEFAULT 'en',
    logo_url            TEXT,

    -- Configuración de nómina
    tax_regime          VARCHAR(150),
    payroll_frequency   VARCHAR(20)     DEFAULT 'biweekly', -- weekly | biweekly | monthly
    pay_day             SMALLINT,                           -- Día del mes o semana para el pago

    -- Control
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_companies_tax_id ON hr.companies (tax_id) WHERE tax_id IS NOT NULL;
CREATE INDEX idx_companies_active        ON hr.companies (is_active);

-- Función reutilizable para updated_at automático
CREATE OR REPLACE FUNCTION hr.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_companies_updated_at
    BEFORE UPDATE ON hr.companies
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

-- Comentarios
COMMENT ON TABLE  hr.companies                   IS 'Tenant raíz del sistema multi-empresa.';
COMMENT ON COLUMN hr.companies.tax_id            IS 'Identificador fiscal adaptable por país: RFC, NIT, RUC, CNPJ, EIN.';
COMMENT ON COLUMN hr.companies.payroll_frequency IS 'Frecuencia de pago: weekly (semanal), biweekly (quincenal), monthly (mensual).';
COMMENT ON COLUMN hr.companies.is_active         IS 'Borrado lógico. FALSE = empresa desactivada, no eliminada físicamente.';
