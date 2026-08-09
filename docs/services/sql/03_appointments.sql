-- ============================================================
-- mantrasdb | Módulo Services
-- Archivo: 03_appointments.sql
-- Descripción: Citas y Ejecución del Servicio
--
-- Una CITA (appointment) es el núcleo del módulo:
--   - Cliente + fecha/hora + uno o más servicios + personal
--   - Cada servicio en la cita tiene su propio tiempo real
--   - Al completarse genera automáticamente la venta en Sales
--
-- Módulos:
--   1. appointments             — cabecera de cita
--   2. appointment_services     — servicios dentro de la cita
--   3. appointment_time_log     — tiempo real de ejecución
--   4. appointment_consumables  — productos consumidos (→ inventory)
--   5. waitlist                 — lista de espera
--   6. appointment_reminders    — recordatorios enviados
-- ============================================================

-- ============================================================
-- 1. APPOINTMENTS (Citas)
-- ============================================================
CREATE TABLE services.appointments (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    appointment_number  VARCHAR(30) NOT NULL,

    -- Cliente
    customer_id         BIGINT      NOT NULL REFERENCES sales.customers(id),

    -- Canal de origen
    source              VARCHAR(20) NOT NULL DEFAULT 'walk_in',
    -- walk_in     : sin cita previa, llegó directo
    -- phone       : reservó por teléfono
    -- whatsapp    : reservó por WhatsApp
    -- online      : reservó por web/app
    -- pos         : generada desde la caja del salón
    -- referral    : referido por otro cliente

    -- Código promocional usado al reservar
    promo_code_id       BIGINT,
    -- REFERENCES sales.promo_codes(id) — FK diferida

    -- ── Fecha y hora ──────────────────────────────────────────
    scheduled_date      DATE        NOT NULL,
    scheduled_start     TIMESTAMPTZ NOT NULL,
    scheduled_end       TIMESTAMPTZ NOT NULL,

    scheduled_duration_min SMALLINT GENERATED ALWAYS AS (
        EXTRACT(EPOCH FROM (scheduled_end - scheduled_start))::INTEGER / 60
    ) STORED,

    -- Tiempos reales
    actual_start        TIMESTAMPTZ,
    actual_end          TIMESTAMPTZ,

    actual_duration_min SMALLINT    GENERATED ALWAYS AS (
        CASE WHEN actual_start IS NOT NULL AND actual_end IS NOT NULL
             THEN EXTRACT(EPOCH FROM (actual_end - actual_start))::INTEGER / 60
             ELSE NULL END
    ) STORED,

    -- Demora en el inicio
    delay_min           SMALLINT    GENERATED ALWAYS AS (
        CASE WHEN actual_start IS NOT NULL
             THEN EXTRACT(EPOCH FROM (actual_start - scheduled_start))::INTEGER / 60
             ELSE NULL END
    ) STORED,

    -- ── Estado ───────────────────────────────────────────────
    status              VARCHAR(20) NOT NULL DEFAULT 'scheduled',
    -- scheduled   : agendada, pendiente confirmación
    -- confirmed   : confirmada (cliente o admin)
    -- checked_in  : cliente llegó
    -- in_progress : servicio en curso
    -- completed   : servicio completado
    -- cancelled   : cancelada
    -- no_show     : no se presentó el cliente

    cancelled_at        TIMESTAMPTZ,
    cancellation_reason VARCHAR(200),
    cancelled_by        VARCHAR(20),
    -- 'client' / 'staff' / 'admin'

    -- ── Recordatorios ────────────────────────────────────────
    reminder_sent_24h   BOOLEAN     NOT NULL DEFAULT FALSE,
    reminder_sent_1h    BOOLEAN     NOT NULL DEFAULT FALSE,

    -- ── Pago y facturación ───────────────────────────────────
    -- Referencia a la venta generada al completar la cita
    sales_order_id      BIGINT      REFERENCES sales.sales_orders(id),
    invoice_id          BIGINT      REFERENCES sales.invoices(id),

    -- Depósito/señal pagada al reservar
    deposit_amount      NUMERIC(18,4) NOT NULL DEFAULT 0,
    deposit_paid_at     TIMESTAMPTZ,
    deposit_payment_method VARCHAR(20),

    -- ── Notas ────────────────────────────────────────────────
    client_notes        TEXT,
    -- Notas del cliente al reservar (alergias, preferencias)

    internal_notes      TEXT,
    -- Notas internas del personal

    created_by          BIGINT      REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX uq_appointment_number
    ON services.appointments (company_id, appointment_number);
CREATE INDEX idx_appt_customer  ON services.appointments (customer_id);
CREATE INDEX idx_appt_date      ON services.appointments (scheduled_date);
CREATE INDEX idx_appt_status    ON services.appointments (status);
CREATE INDEX idx_appt_start     ON services.appointments (scheduled_start);

CREATE TRIGGER trg_appt_updated_at
    BEFORE UPDATE ON services.appointments
    FOR EACH ROW EXECUTE FUNCTION services.set_updated_at();

COMMENT ON TABLE services.appointments IS 'Cita del cliente. Incluye tiempos reales vs planificados, estado, canal de origen, promo code y referencia a factura.';

-- ============================================================
-- 2. APPOINTMENT SERVICES (Servicios dentro de la Cita)
--    Una cita puede tener varios servicios:
--    Ej: Corte + Coloración + Tratamiento (3 servicios)
--    Cada uno puede ser atendido por un empleado diferente.
-- ============================================================
CREATE TABLE services.appointment_services (
    id                  BIGSERIAL   PRIMARY KEY,
    appointment_id      BIGINT      NOT NULL REFERENCES services.appointments(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    service_id          BIGINT      NOT NULL REFERENCES services.services(id),
    service_variant_id  BIGINT      REFERENCES services.service_variants(id),

    -- Empleado asignado a este servicio específico
    staff_profile_id    BIGINT      REFERENCES services.staff_profiles(id),

    -- Recurso físico asignado (silla, cabina, camilla)
    resource_id         BIGINT      REFERENCES services.service_resources(id),

    -- Secuencia dentro de la cita
    sequence            SMALLINT    NOT NULL DEFAULT 1,

    -- ── Tiempos planificados ─────────────────────────────────
    planned_start       TIMESTAMPTZ NOT NULL,
    planned_end         TIMESTAMPTZ NOT NULL,
    planned_duration_min SMALLINT   NOT NULL,

    -- ── Tiempos reales ────────────────────────────────────────
    actual_start        TIMESTAMPTZ,
    actual_end          TIMESTAMPTZ,
    actual_duration_min SMALLINT    GENERATED ALWAYS AS (
        CASE WHEN actual_start IS NOT NULL AND actual_end IS NOT NULL
             THEN EXTRACT(EPOCH FROM (actual_end - actual_start))::INTEGER / 60
             ELSE NULL END
    ) STORED,

    -- Eficiencia de tiempo: planificado / real
    time_efficiency_pct NUMERIC(7,2) GENERATED ALWAYS AS (
        CASE WHEN actual_start IS NOT NULL AND actual_end IS NOT NULL
                  AND EXTRACT(EPOCH FROM (actual_end - actual_start)) > 0
             THEN ROUND(
                 planned_duration_min::NUMERIC /
                 (EXTRACT(EPOCH FROM (actual_end - actual_start)) / 60) * 100
             , 2)
             ELSE NULL END
    ) STORED,

    -- ── Precio y comisión ────────────────────────────────────
    unit_price          NUMERIC(18,4) NOT NULL,
    -- Precio en el momento de la cita (puede diferir del catálogo)

    discount_amount     NUMERIC(18,4) NOT NULL DEFAULT 0,
    final_price         NUMERIC(18,4) GENERATED ALWAYS AS (unit_price - discount_amount) STORED,

    staff_commission_pct NUMERIC(7,4) NOT NULL DEFAULT 0,
    staff_commission_amount NUMERIC(18,4) GENERATED ALWAYS AS (
        (unit_price - discount_amount) * staff_commission_pct / 100
    ) STORED,

    -- ── Estado del servicio ───────────────────────────────────
    status              VARCHAR(20) NOT NULL DEFAULT 'scheduled',
    -- scheduled / in_progress / completed / skipped / cancelled

    -- ── Resultado del servicio ───────────────────────────────
    staff_notes         TEXT,
    -- Notas del estilista/técnico sobre el servicio realizado

    -- Para servicios con seguimiento (coloración: fórmula usada)
    service_formula     TEXT,
    -- Ej: "Koleston 7/0 + 7/3 en proporción 1:1, 30min"

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_appt_svc_appt  ON services.appointment_services (appointment_id);
CREATE INDEX idx_appt_svc_staff ON services.appointment_services (staff_profile_id);

CREATE TRIGGER trg_appt_svc_updated_at
    BEFORE UPDATE ON services.appointment_services
    FOR EACH ROW EXECUTE FUNCTION services.set_updated_at();

COMMENT ON TABLE services.appointment_services IS 'Servicios dentro de la cita. Cada uno tiene empleado, recurso, tiempos reales/planificados y comisión calculada.';

-- ============================================================
-- 3. APPOINTMENT TIME LOG (Registro Granular de Tiempo)
--    Para registrar pausas, interrupciones y etapas
--    dentro de la ejecución de un servicio.
--    Ej: Coloración → aplicar (20min) → esperar (30min) → lavar (10min)
-- ============================================================
CREATE TABLE services.appointment_time_log (
    id                  BIGSERIAL   PRIMARY KEY,
    appointment_service_id BIGINT   NOT NULL REFERENCES services.appointment_services(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    phase               VARCHAR(50) NOT NULL,
    -- Para salón: 'aplicacion' / 'espera_color' / 'lavado' / 'secado' / 'peinado'
    -- Para spa:   'preparacion' / 'tratamiento' / 'reposo'
    -- Para taller: 'diagnostico' / 'reparacion' / 'prueba'
    -- Libre: el negocio define sus propias fases

    started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at            TIMESTAMPTZ,

    duration_min        NUMERIC(8,2) GENERATED ALWAYS AS (
        CASE WHEN ended_at IS NOT NULL
             THEN EXTRACT(EPOCH FROM (ended_at - started_at)) / 60
             ELSE NULL END
    ) STORED,

    notes               TEXT,
    logged_by           BIGINT      REFERENCES hr.system_users(id),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);

CREATE INDEX idx_timelog_appt_svc ON services.appointment_time_log (appointment_service_id);

COMMENT ON TABLE services.appointment_time_log IS 'Fases de ejecución de un servicio: aplicar, esperar, lavar, secar. Permite medir cada etapa por separado.';

-- ============================================================
-- 4. APPOINTMENT CONSUMABLES (Productos Consumidos)
--    Productos usados durante el servicio que se descargan
--    del inventario de logistics.
--    Ej: tinte L'Oréal 7.0 (30g), shampoo hidratante (50ml),
--        esmalte Essie Bordeaux, acetona (10ml)
-- ============================================================
CREATE TABLE services.appointment_consumables (
    id                  BIGSERIAL   PRIMARY KEY,
    appointment_id      BIGINT      NOT NULL REFERENCES services.appointments(id) ON DELETE CASCADE,
    appointment_service_id BIGINT   REFERENCES services.appointment_services(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    product_id          BIGINT      NOT NULL REFERENCES logistics.products(id),
    lot_id              BIGINT      REFERENCES logistics.lots(id),

    quantity_used       NUMERIC(18,6) NOT NULL,
    uom_id              BIGINT      REFERENCES logistics.measurement_units(id),

    unit_cost           NUMERIC(18,4),
    total_cost          NUMERIC(18,4) GENERATED ALWAYS AS (quantity_used * unit_cost) STORED,

    -- ¿Se cobra al cliente como ítem adicional?
    charge_to_client    BOOLEAN     NOT NULL DEFAULT FALSE,
    client_price        NUMERIC(18,4),

    -- Referencia al movimiento de inventario generado
    inventory_transaction_id BIGINT,
    -- REFERENCES logistics.inventory_transactions(id) — FK diferida

    registered_by       BIGINT      REFERENCES hr.system_users(id),
    registered_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);

CREATE INDEX idx_consumables_appt    ON services.appointment_consumables (appointment_id);
CREATE INDEX idx_consumables_product ON services.appointment_consumables (product_id);

COMMENT ON TABLE services.appointment_consumables IS 'Productos consumidos en la cita (tinte, shampoo, esmalte). Descuenta del inventario y opcionalmente se cobra al cliente.';

-- ============================================================
-- 5. WAITLIST (Lista de Espera)
--    Cuando no hay disponibilidad para la fecha/hora deseada,
--    el cliente queda en lista de espera y se le notifica
--    automáticamente si se abre un espacio.
-- ============================================================
CREATE TABLE services.waitlist (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    customer_id         BIGINT      NOT NULL REFERENCES sales.customers(id),
    service_id          BIGINT      NOT NULL REFERENCES services.services(id),
    service_variant_id  BIGINT      REFERENCES services.service_variants(id),

    -- Preferencia del cliente
    preferred_staff_profile_id BIGINT REFERENCES services.staff_profiles(id),
    -- NULL = cualquier disponible

    preferred_date_from DATE        NOT NULL,
    preferred_date_to   DATE,

    preferred_time_from TIME,
    preferred_time_to   TIME,

    -- Estado de la lista de espera
    status              VARCHAR(20) NOT NULL DEFAULT 'waiting',
    -- waiting     : esperando disponibilidad
    -- notified    : se le notificó que hay espacio
    -- booked      : ya reservó la cita disponible
    -- expired     : venció sin booking
    -- cancelled   : canceló la espera

    -- Cita generada si booking exitoso
    appointment_id      BIGINT      REFERENCES services.appointments(id),

    notified_at         TIMESTAMPTZ,
    expires_at          TIMESTAMPTZ,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_waitlist_customer ON services.waitlist (customer_id);
CREATE INDEX idx_waitlist_service  ON services.waitlist (service_id);
CREATE INDEX idx_waitlist_status   ON services.waitlist (status);

-- ============================================================
-- 6. APPOINTMENT REMINDERS (Recordatorios)
--    Registro de recordatorios enviados al cliente.
-- ============================================================
CREATE TABLE services.appointment_reminders (
    id                  BIGSERIAL   PRIMARY KEY,
    appointment_id      BIGINT      NOT NULL REFERENCES services.appointments(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    channel             VARCHAR(20) NOT NULL DEFAULT 'whatsapp',
    -- whatsapp / sms / email / push

    reminder_type       VARCHAR(20) NOT NULL DEFAULT '24h',
    -- 24h / 1h / confirmation / cancellation / follow_up

    sent_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    delivered           BOOLEAN     NOT NULL DEFAULT FALSE,
    delivery_status     VARCHAR(20),
    -- sent / delivered / read / failed

    message_preview     TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);

-- ============================================================
-- VIEW: Agenda del día (para la pantalla principal del salón)
-- ============================================================
CREATE VIEW services.daily_schedule AS
SELECT
    a.id AS appointment_id,
    a.company_id,
    a.appointment_number,
    a.scheduled_date,
    a.scheduled_start,
    a.scheduled_end,
    a.scheduled_duration_min,
    a.actual_start,
    a.delay_min,
    a.status,
    a.client_notes,
    -- Cliente
    c.trade_name AS client_name,
    c.phone AS client_phone,
    -- Servicios (concatenados)
    STRING_AGG(
        svc.name || COALESCE(' - ' || sv.name, ''),
        ', ' ORDER BY asvc.sequence
    ) AS services_summary,
    -- Personal (concatenado)
    STRING_AGG(DISTINCT COALESCE(sp.display_name, 'Sin asignar'), ', ') AS staff_summary,
    -- Total de la cita
    SUM(asvc.final_price) AS total_price,
    -- Depósito
    a.deposit_amount
FROM services.appointments a
JOIN sales.customers c ON c.id = a.customer_id
LEFT JOIN services.appointment_services asvc ON asvc.appointment_id = a.id
LEFT JOIN services.services svc ON svc.id = asvc.service_id
LEFT JOIN services.service_variants sv ON sv.id = asvc.service_variant_id
LEFT JOIN services.staff_profiles sp ON sp.id = asvc.staff_profile_id
WHERE a.scheduled_date = CURRENT_DATE
  AND a.status NOT IN ('cancelled')
GROUP BY a.id, a.company_id, a.appointment_number, a.scheduled_date,
         a.scheduled_start, a.scheduled_end, a.scheduled_duration_min,
         a.actual_start, a.delay_min, a.status, a.client_notes,
         c.trade_name, c.phone, a.deposit_amount
ORDER BY a.scheduled_start;

COMMENT ON VIEW services.daily_schedule IS 'Agenda del día: todas las citas con cliente, servicios, personal y precio total. Vista principal del salón.';

-- ============================================================
-- FK diferida: sales.promo_code_redemptions → services.appointments
-- Se agrega aquí porque sales carga antes que services.
-- ============================================================
ALTER TABLE sales.promo_code_redemptions
    ADD CONSTRAINT fk_pcr_appointment
        FOREIGN KEY (appointment_id)
        REFERENCES services.appointments(id);
