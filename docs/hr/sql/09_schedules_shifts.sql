-- ============================================================
-- mantrasdb | Módulo HR
-- Tablas: hr.schedules / hr.shifts
-- Descripción: Horarios de trabajo y sus turnos específicos.
-- ============================================================

CREATE TABLE hr.schedules (
    id          BIGSERIAL       PRIMARY KEY,
    company_id  BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    name        VARCHAR(100)    NOT NULL,   -- "Horario matutino", "Turno nocturno", etc.
    description TEXT,
    weekly_hours SMALLINT,                 -- Total de horas laborales por semana

    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE TABLE hr.shifts (
    id              BIGSERIAL       PRIMARY KEY,
    schedule_id     BIGINT          NOT NULL REFERENCES hr.schedules(id) ON DELETE RESTRICT,

    day_of_week     SMALLINT        NOT NULL,   -- 1=Monday ... 7=Sunday
    start_time      TIME            NOT NULL,
    end_time        TIME            NOT NULL,
    is_rest_day     BOOLEAN         NOT NULL DEFAULT FALSE,  -- TRUE = día de descanso

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_schedules_company ON hr.schedules (company_id);
CREATE INDEX idx_shifts_schedule   ON hr.shifts (schedule_id);

CREATE TRIGGER trg_schedules_updated_at BEFORE UPDATE ON hr.schedules FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();
CREATE TRIGGER trg_shifts_updated_at    BEFORE UPDATE ON hr.shifts    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.schedules              IS 'Horarios de trabajo definidos por la empresa.';
COMMENT ON TABLE  hr.shifts                 IS 'Turnos diarios dentro de un horario.';
COMMENT ON COLUMN hr.shifts.day_of_week     IS '1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday, 7=Sunday';
COMMENT ON COLUMN hr.shifts.is_rest_day     IS 'TRUE = día de descanso obligatorio dentro del horario.';
