-- ============================================================
-- mantrasdb | Módulo Services
-- Archivo: 02_staff_services.sql
-- Descripción: Personal de Servicios — Skills y Disponibilidad
--
-- El personal de servicios son empleados de HR, pero necesitan
-- configuración adicional:
--   - Qué servicios pueden realizar (skills)
--   - A qué nivel (junior/senior/master)
--   - En qué horarios están disponibles para citas
--   - Sus pausas y días libres específicos
--   - Qué precio cobran según su nivel
--
-- Módulos:
--   1. staff_profiles           — perfil de servicios del empleado
--   2. staff_service_skills     — qué servicios puede hacer y a qué nivel
--   3. staff_availability       — horario de disponibilidad para citas
--   4. staff_time_off           — días/horas no disponibles (vacas, personal)
-- ============================================================

-- ============================================================
-- 1. STAFF PROFILES (Perfil de Servicios del Empleado)
--    Extiende hr.employees con config específica de servicios.
-- ============================================================
CREATE TABLE services.staff_profiles (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),
    employee_id         BIGINT      NOT NULL,
    -- REFERENCES hr.employees(id) — FK diferida

    -- Nivel profesional (afecta precio y comisión)
    staff_level         VARCHAR(20) NOT NULL DEFAULT 'junior',
    -- junior   : recién iniciado
    -- senior   : con experiencia
    -- master   : especialista / top
    -- trainee  : en formación (puede hacer servicios supervisados)

    -- Nombre artístico/profesional (el que ve el cliente)
    display_name        VARCHAR(100),
    bio                 TEXT,
    -- Descripción breve para el booking online

    photo_url           TEXT,

    -- ¿Acepta reservas online?
    accept_online_booking BOOLEAN   NOT NULL DEFAULT TRUE,

    -- Color en el calendario de citas
    calendar_color_hex  VARCHAR(7),

    -- Comisión base del empleado (puede sobreescribir la del servicio)
    commission_pct_override NUMERIC(7,4),
    -- NULL = usa el % del servicio

    -- Máximo de citas simultáneas (normalmente 1)
    max_concurrent_appointments SMALLINT NOT NULL DEFAULT 1,

    -- Tiempo mínimo entre citas (para trasladarse, prepararse)
    min_gap_between_appointments_min SMALLINT NOT NULL DEFAULT 0,

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, employee_id)
);

CREATE TRIGGER trg_staffprof_updated_at
    BEFORE UPDATE ON services.staff_profiles
    FOR EACH ROW EXECUTE FUNCTION services.set_updated_at();

COMMENT ON TABLE services.staff_profiles IS 'Perfil de servicios de cada empleado: nivel, color de calendario, comisión y límite de citas. Extiende hr.employees.';

-- ============================================================
-- 2. STAFF SERVICE SKILLS (Skills por Empleado)
--    Define qué servicios puede realizar cada empleado
--    y a qué nivel.
-- ============================================================
CREATE TABLE services.staff_service_skills (
    id                  BIGSERIAL   PRIMARY KEY,
    staff_profile_id    BIGINT      NOT NULL REFERENCES services.staff_profiles(id) ON DELETE CASCADE,
    service_id          BIGINT      NOT NULL REFERENCES services.services(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Nivel en este servicio específico
    skill_level         VARCHAR(20) NOT NULL DEFAULT 'qualified',
    -- trainee   : en formación, requiere supervisión
    -- qualified : puede realizarlo solo
    -- expert    : especialista (precio premium)

    -- Precio personalizado para este empleado en este servicio
    -- NULL = usa el precio base del servicio o la variante
    price_override      NUMERIC(18,4),

    -- Duración personalizada (algunos son más rápidos/lentos)
    duration_override_min SMALLINT,
    -- NULL = usa la duración estándar del servicio

    -- ¿Es el servicio preferido/destacado de este empleado?
    is_featured         BOOLEAN     NOT NULL DEFAULT FALSE,

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (staff_profile_id, service_id)
);

CREATE INDEX idx_skills_service ON services.staff_service_skills (service_id);

CREATE TRIGGER trg_skills_updated_at
    BEFORE UPDATE ON services.staff_service_skills
    FOR EACH ROW EXECUTE FUNCTION services.set_updated_at();

COMMENT ON TABLE services.staff_service_skills IS 'Qué servicios puede hacer cada empleado y a qué nivel. Permite precio y duración personalizada por empleado.';

-- ============================================================
-- 3. STAFF AVAILABILITY (Horario de Disponibilidad)
--    Define cuándo está disponible el empleado para recibir citas.
--    Es más flexible que el horario laboral de HR porque puede
--    variar semana a semana y tiene soporte de múltiples turnos.
-- ============================================================
CREATE TABLE services.staff_availability (
    id                  BIGSERIAL   PRIMARY KEY,
    staff_profile_id    BIGINT      NOT NULL REFERENCES services.staff_profiles(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- ¿Es una disponibilidad recurrente o de una fecha específica?
    availability_type   VARCHAR(20) NOT NULL DEFAULT 'recurring',
    -- recurring : aplica cada semana en los días indicados
    -- specific  : solo en una fecha concreta

    -- Para disponibilidad recurrente
    day_of_week         SMALLINT,
    -- 1=Lunes, 2=Martes ... 7=Domingo. NULL si es 'specific'.

    -- Para disponibilidad específica
    specific_date       DATE,

    -- Horario del bloque de disponibilidad
    start_time          TIME        NOT NULL,
    end_time            TIME        NOT NULL,

    -- Vigencia de la disponibilidad recurrente
    valid_from          DATE,
    valid_to            DATE,
    -- NULL valid_to = disponibilidad indefinida

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_avail_staff   ON services.staff_availability (staff_profile_id);
CREATE INDEX idx_avail_dow     ON services.staff_availability (day_of_week);
CREATE INDEX idx_avail_date    ON services.staff_availability (specific_date);

COMMENT ON TABLE services.staff_availability IS 'Horarios disponibles para citas por empleado. Soporta recurrencia semanal y fechas específicas.';

-- ============================================================
-- 4. STAFF TIME OFF (Ausencias y Bloqueos de Agenda)
--    Días u horas en que el empleado NO está disponible para citas.
--    Más granular que las ausencias de HR (que son por día completo).
-- ============================================================
CREATE TABLE services.staff_time_off (
    id                  BIGSERIAL   PRIMARY KEY,
    staff_profile_id    BIGINT      NOT NULL REFERENCES services.staff_profiles(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    time_off_type       VARCHAR(20) NOT NULL DEFAULT 'personal',
    -- personal    : libre personal
    -- vacation    : vacaciones
    -- sick        : enfermedad
    -- training    : capacitación
    -- lunch       : pausa de almuerzo (bloqueo diario)
    -- blocked     : bloqueo manual por admin

    -- Período bloqueado
    start_datetime      TIMESTAMPTZ NOT NULL,
    end_datetime        TIMESTAMPTZ NOT NULL,

    reason              VARCHAR(200),

    -- ¿Las citas ya agendadas en este período deben notificarse?
    notify_affected_clients BOOLEAN NOT NULL DEFAULT TRUE,

    approved_by         BIGINT      REFERENCES hr.system_users(id),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_timeoff_staff    ON services.staff_time_off (staff_profile_id);
CREATE INDEX idx_timeoff_dates    ON services.staff_time_off (start_datetime, end_datetime);

COMMENT ON TABLE services.staff_time_off IS 'Bloqueos de agenda del empleado: vacaciones, enfermedad, almuerzo, capacitación. Más granular que hr.absences.';

-- ============================================================
-- VIEW: Disponibilidad del personal para hoy
-- ============================================================
CREATE VIEW services.staff_available_today AS
SELECT
    sp.id AS staff_profile_id,
    sp.company_id,
    sp.display_name,
    sp.staff_level,
    sp.calendar_color_hex,
    sa.start_time,
    sa.end_time,
    -- ¿Tiene algún bloqueo hoy?
    EXISTS (
        SELECT 1 FROM services.staff_time_off t
        WHERE t.staff_profile_id = sp.id
          AND t.start_datetime::DATE <= CURRENT_DATE
          AND t.end_datetime::DATE >= CURRENT_DATE
    ) AS has_time_off_today
FROM services.staff_profiles sp
JOIN services.staff_availability sa ON sa.staff_profile_id = sp.id
WHERE sp.is_active = TRUE
  AND (
      (sa.availability_type = 'recurring' AND sa.day_of_week = EXTRACT(ISODOW FROM CURRENT_DATE))
      OR
      (sa.availability_type = 'specific' AND sa.specific_date = CURRENT_DATE)
  )
  AND (sa.valid_from IS NULL OR sa.valid_from <= CURRENT_DATE)
  AND (sa.valid_to IS NULL OR sa.valid_to >= CURRENT_DATE);

COMMENT ON VIEW services.staff_available_today IS 'Personal disponible para citas hoy con su horario y si tiene algún bloqueo.';
