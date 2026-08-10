-- ============================================================
-- MIGRACIÓN: hr.work_locations + mejoras a hr.time_punches
-- ============================================================
-- 1. Activar extensión earthdistance (geofencing)
-- 2. Crear hr.work_locations  (zonas de trabajo con geofence)
-- 3. Extender hr.time_punches:
--      · punch_status    (active | cancelled | annulled)
--      · auditoría de cancelación/anulación
--      · auditoría de edición de hora
--      · original_punch_id (si es corrección de otro punch)
--      · ip_address, location_id, location_match_distance_m
-- ============================================================

BEGIN;

-- ── 1. Extensiones necesarias ─────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS cube;         -- requerida por earthdistance
CREATE EXTENSION IF NOT EXISTS earthdistance; -- cálculo de distancia geográfica

-- ── 2. hr.work_locations ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS hr.work_locations (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    name            VARCHAR(150)    NOT NULL,   -- 'Oficina central', 'Almacén norte'
    description     TEXT,
    address         VARCHAR(300),

    -- Coordenadas del centro del geofence
    latitude        NUMERIC(10,7)   NOT NULL,
    longitude       NUMERIC(10,7)   NOT NULL,

    -- Radio del geofence en metros
    -- Si el empleado ficha dentro de este radio → se asocia automáticamente
    radius_meters   SMALLINT        NOT NULL DEFAULT 100,

    -- Tipo de ubicación
    location_type   VARCHAR(30)     NOT NULL DEFAULT 'office',
    -- office | warehouse | client | remote | field | other

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_work_locations_updated_at
    BEFORE UPDATE ON hr.work_locations
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_work_locations_company
    ON hr.work_locations (company_id);

CREATE INDEX IF NOT EXISTS idx_work_locations_active
    ON hr.work_locations (company_id) WHERE is_active = true;

COMMENT ON TABLE  hr.work_locations                IS 'Ubicaciones de trabajo con geofence. Si el fichaje cae dentro del radio, se asocia automáticamente.';
COMMENT ON COLUMN hr.work_locations.radius_meters  IS 'Radio del geofence en metros. Default: 100m.';
COMMENT ON COLUMN hr.work_locations.location_type  IS 'office | warehouse | client | remote | field | other';

-- ── 3. Extender hr.time_punches ───────────────────────────────────────────────

-- 3a. Estado del fichaje
ALTER TABLE hr.time_punches
    ADD COLUMN IF NOT EXISTS punch_status VARCHAR(20) NOT NULL DEFAULT 'active';
-- 'active'    = fichaje válido y vigente
-- 'cancelled' = cancelado (error del empleado, lo puede pedir el propio empleado)
-- 'annulled'  = anulado administrativamente por admin o manager

COMMENT ON COLUMN hr.time_punches.punch_status
    IS 'active | cancelled | annulled';

ALTER TABLE hr.time_punches DROP CONSTRAINT IF EXISTS chk_punch_status;
ALTER TABLE hr.time_punches ADD CONSTRAINT chk_punch_status
    CHECK (punch_status IN ('active', 'cancelled', 'annulled'));

-- 3b. Auditoría de cancelación / anulación
ALTER TABLE hr.time_punches
    ADD COLUMN IF NOT EXISTS cancelled_by     BIGINT      REFERENCES hr.employees(id),
    ADD COLUMN IF NOT EXISTS cancelled_at     TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS cancel_reason    TEXT;

COMMENT ON COLUMN hr.time_punches.cancelled_by  IS 'Empleado (admin/manager/self) que canceló o anuló el fichaje';
COMMENT ON COLUMN hr.time_punches.cancel_reason IS 'Motivo de cancelación o anulación';

-- 3c. Auditoría de edición de hora por admin
ALTER TABLE hr.time_punches
    ADD COLUMN IF NOT EXISTS original_punched_at    TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS modified_by            BIGINT      REFERENCES hr.employees(id),
    ADD COLUMN IF NOT EXISTS modified_at            TIMESTAMPTZ;

COMMENT ON COLUMN hr.time_punches.original_punched_at IS 'Hora original antes de que un admin la editara. NULL = nunca editado.';
COMMENT ON COLUMN hr.time_punches.modified_by         IS 'Admin que modificó la hora del fichaje';
COMMENT ON COLUMN hr.time_punches.modified_at         IS 'Cuándo se modificó la hora';

-- 3d. Referencia a fichaje original (cuando este punch corrige otro)
ALTER TABLE hr.time_punches
    ADD COLUMN IF NOT EXISTS original_punch_id  BIGINT  REFERENCES hr.time_punches(id);

COMMENT ON COLUMN hr.time_punches.original_punch_id
    IS 'Si este fichaje es corrección de otro, apunta al punch original (que quedará cancelled).';

-- 3e. IP y geolocalización mejorada
ALTER TABLE hr.time_punches
    ADD COLUMN IF NOT EXISTS ip_address                 INET,
    ADD COLUMN IF NOT EXISTS location_id                BIGINT  REFERENCES hr.work_locations(id),
    ADD COLUMN IF NOT EXISTS location_match_distance_m  NUMERIC(8,2);

COMMENT ON COLUMN hr.time_punches.ip_address                IS 'IP del dispositivo desde donde se fichó';
COMMENT ON COLUMN hr.time_punches.location_id               IS 'Ubicación de trabajo reconocida por geofencing. NULL = fuera de zona conocida.';
COMMENT ON COLUMN hr.time_punches.location_match_distance_m IS 'Distancia en metros al centro de la ubicación reconocida.';

-- 3f. Actualizar enum de punch_type en el COMMENT (ya existían los nuevos tipos en API)
COMMENT ON COLUMN hr.time_punches.punch_type
    IS 'check_in | check_out | break_start | break_end | absence_start | absence_end | overtime_start | overtime_end';

-- 3g. Actualizar enum de source
COMMENT ON COLUMN hr.time_punches.source
    IS 'biometric | mobile_app | web | manual | nfc | qr | admin_created | admin_corrected';

-- ── 4. Índices adicionales ────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_time_punches_status
    ON hr.time_punches (punch_status);

CREATE INDEX IF NOT EXISTS idx_time_punches_location
    ON hr.time_punches (location_id) WHERE location_id IS NOT NULL;

-- Reemplaza el índice de unprocessed para usar punch_status en vez de is_valid
CREATE INDEX IF NOT EXISTS idx_time_punches_active_unprocessed
    ON hr.time_punches (employee_id, punched_at)
    WHERE punch_status = 'active' AND attendance_id IS NULL;

-- ── 5. Función: geofencing — busca la ubicación más cercana al punto de fichaje ─
-- Uso: SELECT * FROM hr.match_work_location(company_id, lat, lon);
-- Devuelve la ubicación dentro del radio más pequeño (NULL si ninguna coincide).

CREATE OR REPLACE FUNCTION hr.match_work_location(
    p_company_id    BIGINT,
    p_latitude      NUMERIC,
    p_longitude     NUMERIC
)
RETURNS TABLE (
    location_id     BIGINT,
    location_name   VARCHAR,
    distance_m      NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        wl.id,
        wl.name,
        ROUND(
            earth_distance(
                ll_to_earth(wl.latitude::float8, wl.longitude::float8),
                ll_to_earth(p_latitude::float8,  p_longitude::float8)
            )::NUMERIC,
            2
        ) AS distance_m
    FROM hr.work_locations wl
    WHERE wl.company_id = p_company_id
      AND wl.is_active  = true
      AND earth_distance(
            ll_to_earth(wl.latitude::float8,  wl.longitude::float8),
            ll_to_earth(p_latitude::float8,   p_longitude::float8)
          ) <= wl.radius_meters
    ORDER BY distance_m
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION hr.match_work_location IS
    'Dado un punto (lat, lon), devuelve la work_location más cercana dentro de su radio de geofence. NULL si ninguna coincide.';

COMMIT;
