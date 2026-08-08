-- ============================================================
-- mantrasdb | Módulo HR
-- Tablas: hr.holiday_types / hr.holidays
-- Descripción: Días festivos y no laborables.
--              Soporta festivos nacionales (company_id NULL),
--              regionales y propios de cada empresa.
--              Consultado por asistencia y nómina para calcular
--              días laborables y pagos especiales.
-- ============================================================

CREATE TABLE hr.holiday_types (
    id          BIGSERIAL       PRIMARY KEY,
    name        VARCHAR(60)     NOT NULL,   -- National, Regional, Company, Bridge
    description TEXT,
    is_active   BOOLEAN         NOT NULL DEFAULT TRUE
);

INSERT INTO hr.holiday_types (name, description) VALUES
  ('National', 'Festivo definido por ley nacional, aplica a todo el país'),
  ('Regional', 'Festivo de un estado o región específica'),
  ('Company',  'Día no laborable definido por la propia empresa'),
  ('Bridge',   'Día puente entre festivo y fin de semana');

CREATE TABLE hr.holidays (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          REFERENCES hr.companies(id) ON DELETE CASCADE,
    -- NULL = festivo global/nacional (aplica a todas las empresas del país)

    holiday_type_id     BIGINT          NOT NULL REFERENCES hr.holiday_types(id),
    country             VARCHAR(100)    NOT NULL DEFAULT 'Mexico',
    region              VARCHAR(150),   -- NULL = aplica a todo el país

    name                VARCHAR(200)    NOT NULL,
    description         TEXT,
    date                DATE            NOT NULL,

    -- Recurrencia anual
    is_recurring        BOOLEAN         NOT NULL DEFAULT FALSE,
    -- TRUE  → el día y mes se repiten cada año (ej: 25-dic siempre)
    -- FALSE → aplica SOLO para el año de la fecha indicada

    -- Impacto laboral
    is_workday          BOOLEAN         NOT NULL DEFAULT FALSE,
    -- TRUE  → se trabaja pero con condiciones especiales (algunos sectores)
    double_pay          BOOLEAN         NOT NULL DEFAULT FALSE,
    -- TRUE  → si se trabaja, se paga al doble según la legislación

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_holidays_company ON hr.holidays (company_id);
CREATE INDEX idx_holidays_date    ON hr.holidays (date);
CREATE INDEX idx_holidays_country ON hr.holidays (country, region);

CREATE TRIGGER trg_holidays_updated_at
    BEFORE UPDATE ON hr.holidays
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.holidays               IS 'Días festivos. company_id NULL = festivo nacional para todo el país.';
COMMENT ON COLUMN hr.holidays.is_recurring  IS 'TRUE = se repite cada año en la misma fecha. FALSE = solo ese año.';
COMMENT ON COLUMN hr.holidays.double_pay    IS 'Si se trabaja este día, corresponde pago doble según ley.';
COMMENT ON COLUMN hr.holidays.is_workday    IS 'TRUE = festivo pero el sector/empresa debe trabajar igual.';
