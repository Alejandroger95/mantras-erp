-- ============================================================
-- mantrasdb | Módulo Venues
-- Archivo: 01_venues.sql
-- Descripción: Recintos, zonas y gestión de aforo
--
-- Genérico para:
--   - Clubes campestres, piscinas, gimnasios
--   - Salas de conciertos, teatros, estadios
--   - Centros de convenciones, coworkings
--
-- Tablas:
--   1. venues           — Recinto físico
--   2. venue_zones      — Zonas/sectores del recinto
--   3. venue_amenities  — Servicios del recinto (vestuario, estacionamiento)
--   4. events           — Evento en el recinto (concierto, torneo, día normal)
--   5. event_zone_capacity — Aforo por zona por evento
-- ============================================================

CREATE SCHEMA IF NOT EXISTS venues;

CREATE OR REPLACE FUNCTION venues.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

-- ============================================================
-- 1. VENUES — Recinto físico
-- ============================================================
CREATE TABLE venues.venues (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    name                VARCHAR(200) NOT NULL,
    -- Ej: "Club Campestre Las Palmas", "Teatro Municipal", "Estadio Nacional"

    venue_type          VARCHAR(30)  NOT NULL DEFAULT 'club',
    -- club        : club campestre, social, deportivo
    -- concert_hall: sala de conciertos, teatro
    -- stadium     : estadio, coliseo
    -- pool        : piscina pública o privada
    -- coworking   : espacio de trabajo compartido
    -- convention  : centro de convenciones, salones de eventos
    -- multipurpose: uso mixto

    address             VARCHAR(300),
    city_id             BIGINT      REFERENCES hr.cities(id),
    latitude            NUMERIC(10,7),
    longitude           NUMERIC(10,7),

    -- Aforo total del recinto (suma de todas las zonas)
    total_capacity      INTEGER     NOT NULL DEFAULT 0,

    -- Horarios de operación por defecto
    opens_at            TIME,
    closes_at           TIME,

    -- Contacto
    phone               VARCHAR(30),
    email               VARCHAR(200),
    website             VARCHAR(200),

    -- ¿Requiere membresía para ingresar?
    requires_membership BOOLEAN     NOT NULL DEFAULT FALSE,

    -- ¿Vende tickets por evento?
    has_ticketing       BOOLEAN     NOT NULL DEFAULT FALSE,

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_by          BIGINT      REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_venue_company ON venues.venues (company_id, is_active);
CREATE TRIGGER trg_venue_upd BEFORE UPDATE ON venues.venues
    FOR EACH ROW EXECUTE FUNCTION venues.set_updated_at();
COMMENT ON TABLE venues.venues IS
'Recinto físico. Genérico para clubs, piscinas, teatros, estadios o centros de convenciones.';

-- ============================================================
-- 2. VENUE_ZONES — Zonas o sectores del recinto
--    Ej: Piscina olímpica / Piscina infantil / Zona campestre
--    Ej: Platea / VIP / Balcón / General / Campo
-- ============================================================
CREATE TABLE venues.venue_zones (
    id                  BIGSERIAL   PRIMARY KEY,
    venue_id            BIGINT      NOT NULL REFERENCES venues.venues(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    name                VARCHAR(100) NOT NULL,
    -- Ej: "Zona VIP", "Piscina Olímpica", "Cancha de Tenis 1", "Platea Baja"

    code                VARCHAR(20),
    -- Código corto: VIP, POOL-A, TC-01, PLAT

    zone_type           VARCHAR(30)  NOT NULL DEFAULT 'general',
    -- general / vip / premium / pool / court / field /
    -- stage / backstage / parking / lounge

    capacity            INTEGER     NOT NULL DEFAULT 0,
    -- Aforo máximo de esta zona

    -- ¿Se pueden hacer reservas individuales (asientos numerados)?
    is_numbered         BOOLEAN     NOT NULL DEFAULT FALSE,
    -- FALSE: acceso general (piscina, general de concierto)
    -- TRUE : asientos numerados (fila A, asiento 12)

    -- Precio base de acceso a esta zona (para ticketing)
    base_price          NUMERIC(18,4) NOT NULL DEFAULT 0,

    -- Para zonas de piscina: temperatura del agua, tipo
    is_indoor           BOOLEAN     NOT NULL DEFAULT FALSE,

    sort_order          SMALLINT    NOT NULL DEFAULT 1,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_zone_venue ON venues.venue_zones (venue_id, sort_order);
CREATE TRIGGER trg_zone_upd BEFORE UPDATE ON venues.venue_zones
    FOR EACH ROW EXECUTE FUNCTION venues.set_updated_at();
COMMENT ON TABLE venues.venue_zones IS
'Zona o sector del recinto: VIP, piscina, cancha, platea, general. Tiene aforo propio y precio base.';

-- ============================================================
-- 3. VENUE_AMENITIES — Servicios disponibles en el recinto
-- ============================================================
CREATE TABLE venues.venue_amenities (
    id                  BIGSERIAL   PRIMARY KEY,
    venue_id            BIGINT      NOT NULL REFERENCES venues.venues(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    name                VARCHAR(100) NOT NULL,
    -- Ej: "Estacionamiento", "Vestuarios", "Bar/Restaurante", "WiFi"

    amenity_type        VARCHAR(30)  NOT NULL DEFAULT 'facility',
    -- facility / service / food_beverage / parking / accessibility

    is_free             BOOLEAN     NOT NULL DEFAULT TRUE,
    price               NUMERIC(18,4),
    -- NULL si is_free = TRUE

    capacity            INTEGER,
    -- Para estacionamiento: número de espacios

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);
CREATE INDEX idx_amenity_venue ON venues.venue_amenities (venue_id);
