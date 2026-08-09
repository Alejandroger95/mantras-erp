-- ============================================================
-- mantrasdb | Módulo Venues
-- Archivo: 02_events.sql
-- Descripción: Eventos, aforo por zona y tickets
--
-- Tablas:
--   4. events               — Evento en el recinto
--   5. event_zone_capacity  — Aforo y precio por zona por evento
--   6. tickets              — Ticket/entrada individual
--   7. access_logs          — Registro de entradas y salidas
--
-- Vistas:
--   venues.event_occupancy_view  — Ocupación en tiempo real por zona
--   venues.upcoming_events_view  — Próximos eventos con disponibilidad
-- ============================================================

-- ============================================================
-- 4. EVENTS — Evento en el recinto
--    Puede ser un concierto único, un día de operación normal
--    del club, una fecha de temporada de piscina, etc.
-- ============================================================
CREATE TABLE venues.events (
    id                  BIGSERIAL   PRIMARY KEY,
    venue_id            BIGINT      NOT NULL REFERENCES venues.venues(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    name                VARCHAR(300) NOT NULL,
    -- Ej: "Concierto Bad Bunny 2026", "Apertura Temporada Piscina",
    --     "Torneo de Tenis Mayo", "Día de Socio - Sábado"

    event_type          VARCHAR(30)  NOT NULL DEFAULT 'regular',
    -- regular     : día normal de operación (club abierto, piscina abierta)
    -- concert     : concierto, show, espectáculo
    -- sport       : torneo, campeonato, partido
    -- private     : evento privado (cumpleaños, corporativo)
    -- festival    : festival multi-día
    -- class       : clase/taller (yoga, natación)

    -- Artista o presentador (para conciertos)
    artist_name         VARCHAR(200),

    description         TEXT,

    -- Fechas y horarios
    event_date          DATE        NOT NULL,
    doors_open_at       TIMESTAMPTZ,
    starts_at           TIMESTAMPTZ NOT NULL,
    ends_at             TIMESTAMPTZ,

    -- Aforo total del evento (puede ser menor que el del recinto)
    total_capacity      INTEGER     NOT NULL DEFAULT 0,

    -- Estado
    status              VARCHAR(20)  NOT NULL DEFAULT 'draft',
    -- draft / on_sale / sold_out / cancelled / completed / postponed

    -- ¿Requiere ticket?
    requires_ticket     BOOLEAN     NOT NULL DEFAULT TRUE,
    -- FALSE para días normales de club donde el acceso es por membresía

    -- Precio general (si no se diferencia por zona)
    general_price       NUMERIC(18,4),
    currency            VARCHAR(3)   NOT NULL DEFAULT 'PEN',

    -- Venta de tickets
    sale_starts_at      TIMESTAMPTZ,
    sale_ends_at        TIMESTAMPTZ,

    -- ¿Permite reingreso?
    allows_reentry      BOOLEAN     NOT NULL DEFAULT FALSE,

    -- Restricción de edad mínima
    min_age             SMALLINT,

    -- Imagen/banner del evento
    banner_url          VARCHAR(500),

    -- Referencia a orden de venta (para eventos vendidos como paquete)
    sales_order_id      BIGINT      REFERENCES sales.sales_orders(id),

    notes               TEXT,

    created_by          BIGINT      REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_event_venue  ON venues.events (venue_id, event_date);
CREATE INDEX idx_event_status ON venues.events (status, event_date);
CREATE TRIGGER trg_event_upd BEFORE UPDATE ON venues.events
    FOR EACH ROW EXECUTE FUNCTION venues.set_updated_at();
COMMENT ON TABLE venues.events IS
'Evento en el recinto: concierto, día de operación normal, torneo, clase o evento privado. Gestiona aforo, horarios y venta de tickets.';

-- ============================================================
-- 5. EVENT_ZONE_CAPACITY — Aforo y precio por zona por evento
--    Permite configurar capacidad y precio diferente por zona
--    para cada evento específico.
-- ============================================================
CREATE TABLE venues.event_zone_capacity (
    id                  BIGSERIAL   PRIMARY KEY,
    event_id            BIGINT      NOT NULL REFERENCES venues.events(id) ON DELETE CASCADE,
    zone_id             BIGINT      NOT NULL REFERENCES venues.venue_zones(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Aforo habilitado para este evento en esta zona
    -- (puede ser menor al aforo total de la zona)
    capacity            INTEGER     NOT NULL DEFAULT 0,

    -- Tickets vendidos (actualizado automáticamente)
    tickets_sold        INTEGER     NOT NULL DEFAULT 0,

    -- Tickets disponibles
    tickets_available   INTEGER     GENERATED ALWAYS AS (
        GREATEST(capacity - tickets_sold, 0)
    ) STORED,

    -- ¿Agotado?
    is_sold_out         BOOLEAN     GENERATED ALWAYS AS (
        tickets_sold >= capacity
    ) STORED,

    -- Precio para esta zona en este evento
    price               NUMERIC(18,4) NOT NULL DEFAULT 0,
    currency            VARCHAR(3)   NOT NULL DEFAULT 'PEN',

    -- Precio VIP o precio especial (early bird, etc.)
    early_bird_price    NUMERIC(18,4),
    early_bird_until    TIMESTAMPTZ,

    -- ¿Zona habilitada para este evento?
    is_enabled          BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX uq_event_zone ON venues.event_zone_capacity (event_id, zone_id);
CREATE TRIGGER trg_ezc_upd BEFORE UPDATE ON venues.event_zone_capacity
    FOR EACH ROW EXECUTE FUNCTION venues.set_updated_at();
COMMENT ON TABLE venues.event_zone_capacity IS
'Aforo y precio por zona por evento. Controla tickets disponibles con columna GENERATED (capacity - tickets_sold).';

-- ============================================================
-- 6. TICKETS — Ticket o entrada individual
--    Un ticket = acceso de una persona a un evento en una zona.
-- ============================================================
CREATE TABLE venues.tickets (
    id                  BIGSERIAL   PRIMARY KEY,
    event_id            BIGINT      NOT NULL REFERENCES venues.events(id),
    zone_id             BIGINT      NOT NULL REFERENCES venues.venue_zones(id),
    event_zone_id       BIGINT      NOT NULL REFERENCES venues.event_zone_capacity(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Titular del ticket
    customer_id         BIGINT      REFERENCES sales.customers(id),

    -- Número de ticket (generado por la app)
    ticket_number       VARCHAR(50)  NOT NULL,

    -- Código QR / código de barras para el acceso
    qr_code             VARCHAR(200) NOT NULL,

    -- Asiento (si la zona es numerada)
    row_label           VARCHAR(10),
    -- Ej: "A", "B", "12"
    seat_number         VARCHAR(10),
    -- Ej: "15", "7A"

    -- Precio pagado
    price_paid          NUMERIC(18,4) NOT NULL DEFAULT 0,
    currency            VARCHAR(3)   NOT NULL DEFAULT 'PEN',

    -- ¿Es ticket de cortesía?
    is_complimentary    BOOLEAN     NOT NULL DEFAULT FALSE,

    -- Estado del ticket
    status              VARCHAR(20)  NOT NULL DEFAULT 'active',
    -- active / used / cancelled / refunded / transferred

    -- Referencia a la venta
    invoice_id          BIGINT      REFERENCES sales.invoices(id),
    sales_order_id      BIGINT      REFERENCES sales.sales_orders(id),

    -- Veces que ha ingresado (para reingreso)
    entry_count         SMALLINT    NOT NULL DEFAULT 0,

    -- Transferencia (si se transfirió a otro cliente)
    transferred_from_ticket_id BIGINT REFERENCES venues.tickets(id),
    transferred_at      TIMESTAMPTZ,
    transferred_to_customer_id BIGINT REFERENCES sales.customers(id),

    purchased_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cancelled_at        TIMESTAMPTZ,
    cancellation_reason VARCHAR(200),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX uq_ticket_number ON venues.tickets (company_id, ticket_number);
CREATE UNIQUE INDEX uq_ticket_qr     ON venues.tickets (qr_code);
CREATE INDEX idx_ticket_event    ON venues.tickets (event_id, status);
CREATE INDEX idx_ticket_customer ON venues.tickets (customer_id);
CREATE INDEX idx_ticket_zone     ON venues.tickets (zone_id);
CREATE TRIGGER trg_ticket_upd BEFORE UPDATE ON venues.tickets
    FOR EACH ROW EXECUTE FUNCTION venues.set_updated_at();
COMMENT ON TABLE venues.tickets IS
'Ticket individual de acceso a un evento/zona. Tiene QR único, asiento opcional (numerado), precio pagado y soporte para transferencia entre clientes.';

-- ============================================================
-- 7. ACCESS_LOGS — Registro de entradas y salidas
--    INMUTABLE: cada evento de acceso queda registrado
--    permanentemente para auditoría y control de aforo.
-- ============================================================
CREATE TABLE venues.access_logs (
    id                  BIGSERIAL   PRIMARY KEY,
    event_id            BIGINT      NOT NULL REFERENCES venues.events(id),
    zone_id             BIGINT      NOT NULL REFERENCES venues.venue_zones(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Método de acceso
    access_method       VARCHAR(20)  NOT NULL DEFAULT 'qr',
    -- qr / barcode / rfid / facial / manual / membership_card

    -- Referencia al ticket escaneado
    ticket_id           BIGINT      REFERENCES venues.tickets(id),

    -- Para acceso por membresía (sin ticket)
    membership_id       BIGINT,
    -- REFERENCES venues.memberships(id) — se agrega en 03_memberships.sql

    customer_id         BIGINT      REFERENCES sales.customers(id),

    -- Tipo de movimiento
    movement_type       VARCHAR(10)  NOT NULL DEFAULT 'entry',
    -- entry / exit / reentry / denied

    -- Motivo de denegación
    denied_reason       VARCHAR(100),
    -- 'invalid_ticket' / 'expired' / 'zone_full' / 'age_restriction' / 'cancelled'

    -- Punto de acceso (torniquete, puerta)
    access_point        VARCHAR(50),
    -- Ej: "Puerta Norte", "Torniquete 3", "Entrada VIP"

    -- Aforo en el momento del acceso (snapshot)
    zone_occupancy_at_entry INTEGER,

    logged_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
    -- INMUTABLE
);
CREATE INDEX idx_access_event    ON venues.access_logs (event_id, logged_at);
CREATE INDEX idx_access_ticket   ON venues.access_logs (ticket_id);
CREATE INDEX idx_access_customer ON venues.access_logs (customer_id);
CREATE INDEX idx_access_zone     ON venues.access_logs (zone_id, movement_type);
COMMENT ON TABLE venues.access_logs IS
'Log inmutable de cada entrada/salida/denegación. Base para control de aforo en tiempo real y auditoría de accesos.';

-- ============================================================
-- VISTA 1: Ocupación por zona en tiempo real
-- ============================================================
CREATE OR REPLACE VIEW venues.event_occupancy_view AS
SELECT
    e.id                                                    AS event_id,
    e.company_id,
    e.name                                                  AS event_name,
    e.event_date,
    e.starts_at,
    e.status                                                AS event_status,

    vz.id                                                   AS zone_id,
    vz.name                                                 AS zone_name,
    vz.zone_type,

    ezc.capacity,
    ezc.tickets_sold,
    ezc.tickets_available,
    ezc.is_sold_out,
    ezc.price,

    -- Personas actualmente dentro (entries - exits)
    COALESCE(
        COUNT(al.id) FILTER (WHERE al.movement_type = 'entry')   +
        COUNT(al.id) FILTER (WHERE al.movement_type = 'reentry') -
        COUNT(al.id) FILTER (WHERE al.movement_type = 'exit')
    , 0)                                                    AS current_occupancy,

    -- % de ocupación actual
    ROUND(
        COALESCE(
            COUNT(al.id) FILTER (WHERE al.movement_type = 'entry') +
            COUNT(al.id) FILTER (WHERE al.movement_type = 'reentry') -
            COUNT(al.id) FILTER (WHERE al.movement_type = 'exit')
        , 0)::NUMERIC /
        NULLIF(ezc.capacity, 0) * 100
    , 1)                                                    AS occupancy_pct,

    -- ¿Está al límite de aforo?
    CASE
        WHEN COALESCE(
            COUNT(al.id) FILTER (WHERE al.movement_type = 'entry') +
            COUNT(al.id) FILTER (WHERE al.movement_type = 'reentry') -
            COUNT(al.id) FILTER (WHERE al.movement_type = 'exit')
        , 0) >= ezc.capacity
        THEN TRUE ELSE FALSE
    END                                                     AS at_capacity

FROM venues.events                e
INNER JOIN venues.event_zone_capacity ezc ON ezc.event_id  = e.id
INNER JOIN venues.venue_zones         vz  ON vz.id         = ezc.zone_id
LEFT  JOIN venues.access_logs         al  ON al.event_id   = e.id
                                         AND al.zone_id    = vz.id
                                         AND al.movement_type != 'denied'
WHERE ezc.is_enabled = TRUE
GROUP BY e.id, e.company_id, e.name, e.event_date, e.starts_at, e.status,
         vz.id, vz.name, vz.zone_type,
         ezc.capacity, ezc.tickets_sold, ezc.tickets_available,
         ezc.is_sold_out, ezc.price
ORDER BY e.event_date, vz.zone_type;

COMMENT ON VIEW venues.event_occupancy_view IS
'Ocupación en tiempo real por zona: cuántas personas están dentro ahora vs aforo máximo. Base para pantallas de control de acceso.';

-- ============================================================
-- VISTA 2: Próximos eventos con disponibilidad
-- ============================================================
CREATE OR REPLACE VIEW venues.upcoming_events_view AS
SELECT
    e.id                                                    AS event_id,
    e.company_id,
    v.name                                                  AS venue_name,
    v.venue_type,
    e.name                                                  AS event_name,
    e.event_type,
    e.artist_name,
    e.event_date,
    e.starts_at,
    e.ends_at,
    e.status,
    e.requires_ticket,
    e.total_capacity,

    -- Tickets totales vendidos (todas las zonas)
    COALESCE(SUM(ezc.tickets_sold), 0)                      AS total_tickets_sold,
    COALESCE(SUM(ezc.tickets_available), 0)                 AS total_tickets_available,

    -- ¿Agotado en todas las zonas?
    BOOL_AND(ezc.is_sold_out)                               AS fully_sold_out,

    -- Precio mínimo de entrada
    MIN(ezc.price)                                          AS price_from,

    e.general_price,
    e.currency,
    e.sale_starts_at,
    e.sale_ends_at,
    e.banner_url

FROM venues.events                e
INNER JOIN venues.venues               v   ON v.id  = e.venue_id
LEFT  JOIN venues.event_zone_capacity  ezc ON ezc.event_id = e.id
                                          AND ezc.is_enabled = TRUE
WHERE e.event_date >= CURRENT_DATE
  AND e.status IN ('on_sale', 'draft')
GROUP BY e.id, e.company_id, v.name, v.venue_type, e.name, e.event_type,
         e.artist_name, e.event_date, e.starts_at, e.ends_at, e.status,
         e.requires_ticket, e.total_capacity, e.general_price, e.currency,
         e.sale_starts_at, e.sale_ends_at, e.banner_url
ORDER BY e.event_date ASC;

COMMENT ON VIEW venues.upcoming_events_view IS
'Próximos eventos con disponibilidad de tickets por zona, precio mínimo y estado de venta. Para páginas de venta y apps.';
