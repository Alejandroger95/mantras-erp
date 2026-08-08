-- ============================================================
-- mantrasdb | Módulo HR
-- Tablas: hr.countries / hr.states / hr.cities
-- Descripción: Catálogo geográfico de 3 niveles.
--              Usado en companies, persons, employees, etc.
-- ============================================================

CREATE TABLE hr.countries (
    id          BIGSERIAL       PRIMARY KEY,
    name        VARCHAR(100)    NOT NULL,
    iso_code    CHAR(2)         NOT NULL,   -- ISO 3166-1 alpha-2: MX, CO, US, PE, etc.
    phone_code  VARCHAR(10),               -- +52, +57, +1, etc.
    currency    CHAR(3),                   -- ISO 4217
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_countries_iso ON hr.countries (iso_code);

INSERT INTO hr.countries (name, iso_code, phone_code, currency) VALUES
  ('Mexico',   'MX', '+52', 'MXN'),
  ('Colombia', 'CO', '+57', 'COP'),
  ('Peru',     'PE', '+51', 'PEN'),
  ('Ecuador',  'EC', '+593','USD'),
  ('Chile',    'CL', '+56', 'CLP'),
  ('Argentina','AR', '+54', 'ARS'),
  ('Spain',    'ES', '+34', 'EUR'),
  ('United States','US','+1','USD');

CREATE TABLE hr.states (
    id          BIGSERIAL       PRIMARY KEY,
    country_id  BIGINT          NOT NULL REFERENCES hr.countries(id) ON DELETE RESTRICT,
    name        VARCHAR(100)    NOT NULL,
    code        VARCHAR(10),               -- Código del estado/provincia
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_states_country ON hr.states (country_id);

CREATE TABLE hr.cities (
    id          BIGSERIAL       PRIMARY KEY,
    state_id    BIGINT          NOT NULL REFERENCES hr.states(id) ON DELETE RESTRICT,
    name        VARCHAR(100)    NOT NULL,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_cities_state ON hr.cities (state_id);

CREATE TRIGGER trg_countries_updated_at BEFORE UPDATE ON hr.countries FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();
CREATE TRIGGER trg_states_updated_at    BEFORE UPDATE ON hr.states    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();
CREATE TRIGGER trg_cities_updated_at    BEFORE UPDATE ON hr.cities    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE hr.countries IS 'Catálogo de países con código ISO y moneda.';
COMMENT ON TABLE hr.states    IS 'Estados o provincias por país.';
COMMENT ON TABLE hr.cities    IS 'Ciudades por estado.';
