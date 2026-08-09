-- ============================================================
-- mantrasdb | Módulo Services
-- Archivo: 04_ratings_kpis.sql
-- Descripción: Calificaciones, KPIs y run_services.sh
--
-- Módulos:
--   1. service_ratings       — calificaciones del cliente post-cita
--   2. client_service_history— historial del cliente (fórmulas, preferencias)
--   3. Views de KPIs:
--      - staff_performance_view   : productividad del personal
--      - service_popularity_view  : servicios más solicitados
--      - revenue_by_staff_view    : ingresos y comisiones por empleado
-- ============================================================

-- ============================================================
-- 1. SERVICE RATINGS (Calificaciones Post-Cita)
-- ============================================================
CREATE TABLE services.service_ratings (
    id                  BIGSERIAL   PRIMARY KEY,
    appointment_id      BIGINT      NOT NULL REFERENCES services.appointments(id),
    appointment_service_id BIGINT   REFERENCES services.appointment_services(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    customer_id         BIGINT      NOT NULL REFERENCES sales.customers(id),
    staff_profile_id    BIGINT      REFERENCES services.staff_profiles(id),

    -- Calificación general (1-5 estrellas)
    overall_rating      SMALLINT    NOT NULL CHECK (overall_rating BETWEEN 1 AND 5),

    -- Dimensiones específicas (opcionales)
    rating_quality      SMALLINT    CHECK (rating_quality BETWEEN 1 AND 5),
    -- Calidad del servicio
    rating_punctuality  SMALLINT    CHECK (rating_punctuality BETWEEN 1 AND 5),
    -- Puntualidad del personal
    rating_cleanliness  SMALLINT    CHECK (rating_cleanliness BETWEEN 1 AND 5),
    -- Limpieza del local
    rating_value        SMALLINT    CHECK (rating_value BETWEEN 1 AND 5),
    -- Relación calidad-precio

    comment             TEXT,

    -- ¿El cliente recomienda el servicio?
    would_recommend     BOOLEAN,

    -- ¿Es una reseña pública (para mostrar en booking online)?
    is_public           BOOLEAN     NOT NULL DEFAULT TRUE,

    -- Respuesta del negocio
    business_reply      TEXT,
    replied_at          TIMESTAMPTZ,
    replied_by          BIGINT      REFERENCES hr.system_users(id),

    rated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);

CREATE UNIQUE INDEX uq_rating_appt_svc
    ON services.service_ratings (appointment_id, COALESCE(appointment_service_id, 0::BIGINT));
CREATE INDEX idx_rating_staff    ON services.service_ratings (staff_profile_id);
CREATE INDEX idx_rating_customer ON services.service_ratings (customer_id);

COMMENT ON TABLE services.service_ratings IS 'Calificaciones post-cita del cliente: general (1-5) + dimensiones (calidad, puntualidad, limpieza, precio).';

-- ============================================================
-- 2. CLIENT SERVICE HISTORY (Historial del Cliente)
--    Guarda fórmulas, preferencias y observaciones por cliente
--    y servicio. Fundamental para salones de belleza.
--    Ej: "Coloración: Koleston 7/0 + 7/3, 1:1, 30min"
--        "Alérgica a productos con amoniaco"
--        "Prefiere agua tibia, sensible en el cuero cabelludo"
-- ============================================================
CREATE TABLE services.client_service_history (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),
    customer_id         BIGINT      NOT NULL REFERENCES sales.customers(id),
    service_id          BIGINT      NOT NULL REFERENCES services.services(id),
    staff_profile_id    BIGINT      REFERENCES services.staff_profiles(id),

    -- Referencia a la cita donde se registró esto
    appointment_id      BIGINT      REFERENCES services.appointments(id),

    -- Fórmula / protocolo usado
    formula             TEXT,
    -- "Koleston 7/0 50g + 7/3 20g + agua oxigenada 20vol, 35min"

    -- Resultado obtenido
    result_notes        TEXT,

    -- Preferencias del cliente
    preferences         TEXT,

    -- Alertas / contraindicaciones
    alerts              TEXT,
    -- "Alergia al amoniaco", "Piel sensible", "No usar calor directo"

    -- Foto del antes/después (URL)
    photo_before_url    TEXT,
    photo_after_url     TEXT,

    service_date        DATE        NOT NULL,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE: cada visita genera un registro nuevo
);

CREATE INDEX idx_csh_customer ON services.client_service_history (customer_id, service_id);
CREATE INDEX idx_csh_date     ON services.client_service_history (service_date DESC);

COMMENT ON TABLE services.client_service_history IS 'Historial de fórmulas y preferencias del cliente por servicio. Fundamental para salones: coloración, tratamientos, etc.';

-- ============================================================
-- VIEW: Performance del personal (mes actual)
-- ============================================================
CREATE VIEW services.staff_performance_view AS
SELECT
    sp.id AS staff_profile_id,
    sp.company_id,
    sp.display_name,
    sp.staff_level,
    DATE_TRUNC('month', a.scheduled_date::TIMESTAMPTZ) AS period_month,
    -- Citas
    COUNT(DISTINCT a.id)                                AS total_appointments,
    COUNT(DISTINCT a.id) FILTER (WHERE a.status = 'completed') AS completed_appointments,
    COUNT(DISTINCT a.id) FILTER (WHERE a.status = 'no_show')   AS no_shows,
    -- Servicios realizados
    COUNT(asvc.id) FILTER (WHERE asvc.status = 'completed')     AS services_completed,
    -- Tiempo
    ROUND(SUM(asvc.actual_duration_min) FILTER (WHERE asvc.status = 'completed') / 60.0, 2)
                                                        AS total_hours_worked,
    -- Puntualidad: % de citas sin demora
    ROUND(
        COUNT(a.id) FILTER (WHERE a.delay_min <= 5 AND a.status = 'completed')::NUMERIC /
        NULLIF(COUNT(a.id) FILTER (WHERE a.status = 'completed'), 0) * 100
    , 2)                                                AS punctuality_pct,
    -- Eficiencia de tiempo
    ROUND(AVG(asvc.time_efficiency_pct) FILTER (WHERE asvc.status = 'completed'), 2)
                                                        AS avg_time_efficiency_pct,
    -- Ingresos generados
    ROUND(SUM(asvc.final_price) FILTER (WHERE asvc.status = 'completed'), 2)
                                                        AS total_revenue,
    -- Comisiones ganadas
    ROUND(SUM(asvc.staff_commission_amount) FILTER (WHERE asvc.status = 'completed'), 2)
                                                        AS total_commission,
    -- Calificación promedio
    ROUND(AVG(r.overall_rating), 2)                    AS avg_rating,
    COUNT(r.id)                                         AS total_ratings
FROM services.staff_profiles sp
LEFT JOIN services.appointment_services asvc ON asvc.staff_profile_id = sp.id
LEFT JOIN services.appointments a ON a.id = asvc.appointment_id
LEFT JOIN services.service_ratings r ON r.staff_profile_id = sp.id
    AND DATE_TRUNC('month', r.rated_at) = DATE_TRUNC('month', a.scheduled_date::TIMESTAMPTZ)
WHERE sp.is_active = TRUE
GROUP BY sp.id, sp.company_id, sp.display_name, sp.staff_level,
         DATE_TRUNC('month', a.scheduled_date::TIMESTAMPTZ)
ORDER BY sp.id, period_month DESC;

COMMENT ON VIEW services.staff_performance_view IS 'KPIs del personal por mes: citas, servicios, horas, ingresos, comisiones, puntualidad, eficiencia y calificación promedio.';

-- ============================================================
-- VIEW: Servicios más populares (últimos 30 días)
-- ============================================================
CREATE VIEW services.service_popularity_view AS
SELECT
    svc.id AS service_id,
    svc.company_id,
    svc.name AS service_name,
    cat.name AS category_name,
    COUNT(asvc.id) FILTER (WHERE asvc.status = 'completed')  AS times_completed,
    COUNT(asvc.id) FILTER (WHERE a.status = 'cancelled')      AS times_cancelled,
    ROUND(AVG(asvc.actual_duration_min) FILTER (WHERE asvc.status = 'completed'), 1)
                                                               AS avg_duration_min,
    ROUND(AVG(asvc.final_price) FILTER (WHERE asvc.status = 'completed'), 2)
                                                               AS avg_price,
    ROUND(SUM(asvc.final_price) FILTER (WHERE asvc.status = 'completed'), 2)
                                                               AS total_revenue,
    ROUND(AVG(r.overall_rating), 2)                           AS avg_rating
FROM services.services svc
LEFT JOIN services.service_categories cat ON cat.id = svc.category_id
LEFT JOIN services.appointment_services asvc ON asvc.service_id = svc.id
LEFT JOIN services.appointments a ON a.id = asvc.appointment_id
    AND a.scheduled_date >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN services.service_ratings r ON r.appointment_service_id = asvc.id
WHERE svc.is_active = TRUE
GROUP BY svc.id, svc.company_id, svc.name, cat.name
ORDER BY times_completed DESC;

COMMENT ON VIEW services.service_popularity_view IS 'Servicios más solicitados (últimos 30 días): veces completado, duración promedio, precio e ingresos.';

-- ============================================================
-- VIEW: Ingresos y ocupación por empleado (hoy)
-- ============================================================
CREATE VIEW services.staff_today_summary AS
SELECT
    sp.id AS staff_profile_id,
    sp.company_id,
    sp.display_name,
    sp.calendar_color_hex,
    COUNT(a.id) FILTER (WHERE a.status IN ('scheduled','confirmed','checked_in','in_progress'))
                                                AS pending_appointments,
    COUNT(a.id) FILTER (WHERE a.status = 'completed')
                                                AS completed_today,
    COUNT(a.id) FILTER (WHERE a.status = 'no_show')
                                                AS no_shows_today,
    -- Horas ocupadas hoy (planificadas, no reales para agenda futura)
    ROUND(SUM(a.scheduled_duration_min)::NUMERIC / 60, 2)
                                                AS scheduled_hours_today,
    -- Ingresos del día
    ROUND(SUM(asvc.final_price) FILTER (WHERE asvc.status = 'completed'), 2)
                                                AS revenue_today,
    -- Comisión del día
    ROUND(SUM(asvc.staff_commission_amount) FILTER (WHERE asvc.status = 'completed'), 2)
                                                AS commission_today
FROM services.staff_profiles sp
LEFT JOIN services.appointment_services asvc ON asvc.staff_profile_id = sp.id
LEFT JOIN services.appointments a ON a.id = asvc.appointment_id
    AND a.scheduled_date = CURRENT_DATE
WHERE sp.is_active = TRUE
GROUP BY sp.id, sp.company_id, sp.display_name, sp.calendar_color_hex;

COMMENT ON VIEW services.staff_today_summary IS 'Resumen del día por empleado: citas pendientes, completadas, horas agendadas, ingresos y comisión del día.';
