-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.time_punches
-- Descripción: Fichajes — registros brutos de entrada/salida.
--              Son los eventos individuales tal como llegan del
--              dispositivo (biométrico, app, web, manual).
--              La tabla hr.attendance es el resumen diario
--              calculado a partir de estos fichajes.
--
-- Flujo:
--   time_punches (eventos brutos)
--     → procesados por el sistema
--     → generan / actualizan hr.attendance (resumen diario)
--
-- Ejemplo de un día:
--   08:01  check_in    (biometric)
--   10:00  break_start (mobile_app)
--   10:15  break_end   (mobile_app)
--   14:00  break_start (mobile_app)
--   14:30  break_end   (mobile_app)
--   17:03  check_out   (biometric)
-- ============================================================

CREATE TABLE hr.time_punches (
    id              BIGSERIAL       PRIMARY KEY,
    employee_id     BIGINT          NOT NULL REFERENCES hr.employees(id) ON DELETE RESTRICT,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- FK a hr.attendance sin constraint directo para evitar dependencia circular.
    -- Se llena cuando el sistema procesa y consolida el día.
    attendance_id   BIGINT,
    -- NULL = fichaje pendiente de procesar. El sistema lo llena al calcular la asistencia.

    -- El fichaje en sí
    punched_at      TIMESTAMPTZ     NOT NULL,
    punch_type      VARCHAR(20)     NOT NULL,
    -- check_in | check_out | break_start | break_end | overtime_start | overtime_end

    -- Origen del fichaje
    source          VARCHAR(20)     NOT NULL DEFAULT 'manual',
    -- biometric | mobile_app | web | manual | nfc | qr
    device_id       VARCHAR(100),

    -- Geolocalización (útil para empleados remotos o en campo)
    location_name   VARCHAR(150),
    latitude        NUMERIC(10,7),
    longitude       NUMERIC(10,7),

    -- Validación
    is_valid        BOOLEAN         NOT NULL DEFAULT TRUE,
    invalid_reason  TEXT,

    recorded_by     BIGINT          REFERENCES hr.employees(id),
    notes           TEXT,

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_time_punches_employee    ON hr.time_punches (employee_id);
CREATE INDEX idx_time_punches_company     ON hr.time_punches (company_id);
CREATE INDEX idx_time_punches_punched_at  ON hr.time_punches (punched_at);
CREATE INDEX idx_time_punches_attendance  ON hr.time_punches (attendance_id) WHERE attendance_id IS NOT NULL;
CREATE INDEX idx_time_punches_unprocessed
    ON hr.time_punches (employee_id, punched_at)
    WHERE attendance_id IS NULL AND is_valid = TRUE;

CREATE TRIGGER trg_time_punches_updated_at
    BEFORE UPDATE ON hr.time_punches
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

-- Añadir FK a attendance ahora que ambas tablas existen
-- (se ejecuta este archivo después de 10_holidays y antes de 11_attendance,
--  por lo que attendance aún no existe; el FK se aplica con ALTER TABLE al final)
-- ALTER TABLE hr.time_punches
--   ADD CONSTRAINT fk_time_punches_attendance
--   FOREIGN KEY (attendance_id) REFERENCES hr.attendance(id);
-- Descomentar y ejecutar DESPUÉS de correr 11_attendance.sql

COMMENT ON TABLE  hr.time_punches              IS 'Fichajes brutos de entrada/salida. hr.attendance se calcula desde aquí.';
COMMENT ON COLUMN hr.time_punches.punch_type   IS 'check_in | check_out | break_start | break_end | overtime_start | overtime_end';
COMMENT ON COLUMN hr.time_punches.source       IS 'biometric | mobile_app | web | manual | nfc | qr';
COMMENT ON COLUMN hr.time_punches.is_valid     IS 'FALSE = fichaje descartado por duplicado, fuera de rango u otro motivo.';
COMMENT ON COLUMN hr.time_punches.attendance_id IS 'ID en hr.attendance. NULL = pendiente de procesar.';
