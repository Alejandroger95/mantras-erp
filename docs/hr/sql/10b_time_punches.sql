-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.time_punches
-- Descripción: Fichajes — registros brutos de entrada/salida.
--              Son los eventos individuales tal como llegan del
--              dispositivo (biométrico, app, web, manual, admin).
--              La tabla hr.attendance es el resumen diario
--              calculado a partir de estos fichajes.
--
-- Estados de un fichaje (punch_status):
--   active    = fichaje válido y vigente
--   cancelled = error del empleado; cancelado por sí mismo o manager
--   annulled  = anulado administrativamente por admin/manager
--
-- Flujo de corrección:
--   1. Empleado ficha mal → punch queda en BD con punch_status='active'
--   2. Admin crea nuevo punch correcto (original_punch_id → punch erróneo)
--   3. Admin cancela el erróneo (punch_status='cancelled', cancel_reason)
--   4. Queries de estado solo leen WHERE punch_status = 'active'
--
-- Geofencing:
--   Si el dispositivo manda lat/lon, la API llama a hr.match_work_location()
--   y guarda location_id + location_match_distance_m automáticamente.
-- ============================================================

CREATE TABLE hr.time_punches (
    id              BIGSERIAL       PRIMARY KEY,
    employee_id     BIGINT          NOT NULL REFERENCES hr.employees(id) ON DELETE RESTRICT,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    attendance_id   BIGINT,
    -- NULL = fichaje pendiente de procesar.

    -- ── El fichaje en sí ───────────────────────────────────
    punched_at      TIMESTAMPTZ     NOT NULL,
    punch_type      VARCHAR(20)     NOT NULL,
    -- check_in | check_out | break_start | break_end
    -- absence_start | absence_end | overtime_start | overtime_end

    -- ── Estado ─────────────────────────────────────────────
    punch_status    VARCHAR(20)     NOT NULL DEFAULT 'active',
    -- active | cancelled | annulled

    -- ── Origen del fichaje ─────────────────────────────────
    source          VARCHAR(30)     NOT NULL DEFAULT 'web',
    -- biometric | mobile_app | web | manual | nfc | qr
    -- admin_created | admin_corrected
    device_id       VARCHAR(100),
    ip_address      INET,

    -- ── Geolocalización ────────────────────────────────────
    latitude        NUMERIC(10,7),
    longitude       NUMERIC(10,7),
    location_name   VARCHAR(150),           -- texto libre si no hay work_location
    location_id     BIGINT  REFERENCES hr.work_locations(id),
    -- Ubicación reconocida por geofencing. NULL = fuera de zona conocida.
    location_match_distance_m NUMERIC(8,2),
    -- Distancia exacta en metros al centro de la ubicación reconocida.

    -- ── Auditoría de cancelación / anulación ───────────────
    cancelled_by    BIGINT          REFERENCES hr.employees(id),
    cancelled_at    TIMESTAMPTZ,
    cancel_reason   TEXT,

    -- ── Auditoría de edición de hora por admin ─────────────
    original_punched_at TIMESTAMPTZ,
    -- Hora original antes de ser editada. NULL = nunca editado.
    modified_by     BIGINT          REFERENCES hr.employees(id),
    modified_at     TIMESTAMPTZ,

    -- ── Corrección de otro fichaje ─────────────────────────
    original_punch_id BIGINT        REFERENCES hr.time_punches(id),
    -- Si este punch corrige otro, apunta al original (que quedará cancelled).

    -- ── Quién lo registró (admin creando retroactivo) ──────
    recorded_by     BIGINT          REFERENCES hr.employees(id),
    notes           TEXT,

    -- ── Validación legacy (mantener por compatibilidad) ────
    is_valid        BOOLEAN         NOT NULL DEFAULT TRUE,
    invalid_reason  TEXT,

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_punch_status CHECK (
        punch_status IN ('active', 'cancelled', 'annulled')
    )
);

CREATE INDEX idx_time_punches_employee    ON hr.time_punches (employee_id);
CREATE INDEX idx_time_punches_company     ON hr.time_punches (company_id);
CREATE INDEX idx_time_punches_punched_at  ON hr.time_punches (punched_at);
CREATE INDEX idx_time_punches_status      ON hr.time_punches (punch_status);
CREATE INDEX idx_time_punches_location    ON hr.time_punches (location_id) WHERE location_id IS NOT NULL;
CREATE INDEX idx_time_punches_attendance  ON hr.time_punches (attendance_id) WHERE attendance_id IS NOT NULL;
CREATE INDEX idx_time_punches_active_unprocessed
    ON hr.time_punches (employee_id, punched_at)
    WHERE punch_status = 'active' AND attendance_id IS NULL;

CREATE TRIGGER trg_time_punches_updated_at
    BEFORE UPDATE ON hr.time_punches
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.time_punches                        IS 'Fichajes brutos. hr.attendance se calcula desde aquí usando solo punch_status=active.';
COMMENT ON COLUMN hr.time_punches.punch_type             IS 'check_in | check_out | break_start | break_end | absence_start | absence_end | overtime_start | overtime_end';
COMMENT ON COLUMN hr.time_punches.punch_status           IS 'active | cancelled | annulled. Queries de estado solo leen active.';
COMMENT ON COLUMN hr.time_punches.source                 IS 'biometric | mobile_app | web | manual | nfc | qr | admin_created | admin_corrected';
COMMENT ON COLUMN hr.time_punches.location_id            IS 'work_location reconocida por geofencing. NULL = fuera de zona conocida.';
COMMENT ON COLUMN hr.time_punches.location_match_distance_m IS 'Distancia en metros al centro de la ubicación reconocida.';
COMMENT ON COLUMN hr.time_punches.original_punched_at    IS 'Hora original antes de edición por admin. NULL = nunca editado.';
COMMENT ON COLUMN hr.time_punches.original_punch_id      IS 'Si este punch corrige otro, apunta al original (que quedará cancelled).';
COMMENT ON COLUMN hr.time_punches.cancelled_by           IS 'Quién canceló o anuló el fichaje';
COMMENT ON COLUMN hr.time_punches.recorded_by            IS 'Admin que creó el fichaje retroactivamente';
