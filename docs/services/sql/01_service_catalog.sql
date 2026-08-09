-- ============================================================
-- mantrasdb | Módulo Services
-- Archivo: 01_service_catalog.sql
-- Descripción: Catálogo de Servicios
--
-- Funciona para CUALQUIER negocio de servicios:
--   💇 Salón de belleza  — corte, coloración, manicure, pedicure
--   💆 Spa / masajes     — tratamientos, faciales, aromaterapia
--   🏥 Clínica / médico  — consultas, procedimientos, terapias
--   🐾 Veterinaria       — consulta, baño, peluquería, cirugía
--   🏋️ Gym / entrenador  — clases, entrenamientos personales
--   🔧 Taller / técnico  — reparaciones, mantenimiento
--   🎓 Academia          — clases, tutorías, talleres
--
-- Módulos:
--   1. Schema + función set_updated_at
--   2. service_categories       — categorías de servicios
--   3. services                 — catálogo de servicios
--   4. service_variants         — variantes (corto/largo, 1hr/2hr)
--   5. service_packages         — paquetes/combos
--   6. service_package_items    — servicios dentro de un paquete
--   7. service_resources        — recursos físicos (sillas, cabinas)
--   8. service_resource_requirements — qué recurso necesita cada servicio
-- ============================================================

CREATE SCHEMA IF NOT EXISTS services;

CREATE OR REPLACE FUNCTION services.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- ============================================================
-- 1. SERVICE CATEGORIES
-- ============================================================
CREATE TABLE services.service_categories (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    parent_id           BIGINT      REFERENCES services.service_categories(id),
    -- Jerarquía: Cabello → Corte / Coloración / Tratamiento

    code                VARCHAR(20) NOT NULL,
    name                VARCHAR(100) NOT NULL,
    description         TEXT,
    icon                VARCHAR(50),
    -- Ej: 'scissors', 'spa', 'nail', 'massage'
    color_hex           VARCHAR(7),
    -- Para el calendario de citas

    display_order       SMALLINT    NOT NULL DEFAULT 10,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE TRIGGER trg_svccat_updated_at
    BEFORE UPDATE ON services.service_categories
    FOR EACH ROW EXECUTE FUNCTION services.set_updated_at();

-- ============================================================
-- 2. SERVICES (Catálogo de Servicios)
-- ============================================================
CREATE TABLE services.services (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),
    category_id         BIGINT      REFERENCES services.service_categories(id),

    -- Vínculo con logistics.products (is_service = TRUE)
    -- Al venderse en Sales, se usa este product_id para la línea de factura
    product_id          BIGINT      REFERENCES logistics.products(id),

    code                VARCHAR(30) NOT NULL,
    name                VARCHAR(200) NOT NULL,
    description         TEXT,

    -- ── Tiempo ───────────────────────────────────────────────
    duration_min        SMALLINT    NOT NULL DEFAULT 60,
    -- Duración estándar en minutos

    buffer_after_min    SMALLINT    NOT NULL DEFAULT 0,
    -- Tiempo de limpieza/preparación después del servicio
    -- No se puede agendar otro cliente en este tiempo

    -- ── Precio base ──────────────────────────────────────────
    base_price          NUMERIC(18,4) NOT NULL DEFAULT 0,
    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',

    -- ¿El precio varía según el personal? (ej: junior vs senior)
    price_by_staff_level BOOLEAN    NOT NULL DEFAULT FALSE,

    -- ── Tipo de servicio ──────────────────────────────────────
    service_type        VARCHAR(20) NOT NULL DEFAULT 'appointment',
    -- appointment : requiere cita previa (salón, clínica)
    -- walk_in     : sin cita (barbería, taller rápido)
    -- class       : clase grupal (yoga, pilates, academia)
    -- subscription: suscripción (gym mensual)

    -- ── Capacidad ────────────────────────────────────────────
    max_clients_per_session SMALLINT NOT NULL DEFAULT 1,
    -- 1 = servicio individual, >1 = clase grupal

    -- ── Comisiones del personal ───────────────────────────────
    staff_commission_pct NUMERIC(7,4) NOT NULL DEFAULT 0,
    -- % de la venta que va al técnico/estilista

    -- ── Online booking ───────────────────────────────────────
    allow_online_booking BOOLEAN    NOT NULL DEFAULT TRUE,
    online_booking_advance_min SMALLINT NOT NULL DEFAULT 0,
    -- Mínimo de minutos de anticipación para reservar online

    -- ── Consumibles estándar ──────────────────────────────────
    -- Los consumibles reales se registran en appointment_consumables
    -- pero aquí se puede definir un consumo estándar esperado

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    display_order       SMALLINT    NOT NULL DEFAULT 10,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE INDEX idx_svc_category ON services.services (category_id);
CREATE INDEX idx_svc_product  ON services.services (product_id);

CREATE TRIGGER trg_svc_updated_at
    BEFORE UPDATE ON services.services
    FOR EACH ROW EXECUTE FUNCTION services.set_updated_at();

COMMENT ON TABLE services.services IS 'Catálogo de servicios. Vinculado a logistics.products para facturación. Soporta citas, walk-in, clases grupales y suscripciones.';

-- ============================================================
-- 3. SERVICE VARIANTS (Variantes del Servicio)
--    Ej: Corte cabello → Corto / Medio / Largo
--        Masaje → 30 min / 60 min / 90 min
--        Manicure → Básico / Gel / Acrilico
-- ============================================================
CREATE TABLE services.service_variants (
    id                  BIGSERIAL   PRIMARY KEY,
    service_id          BIGINT      NOT NULL REFERENCES services.services(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    name                VARCHAR(100) NOT NULL,
    -- 'Cabello Corto', '60 minutos', 'Gel'

    duration_min        SMALLINT,
    -- NULL = usa la duración del servicio padre

    price_override      NUMERIC(18,4),
    -- NULL = usa el precio base del servicio padre

    -- Para precios por nivel de personal
    -- (si price_by_staff_level = TRUE en el servicio)
    price_junior        NUMERIC(18,4),
    price_senior        NUMERIC(18,4),
    price_master        NUMERIC(18,4),

    display_order       SMALLINT    NOT NULL DEFAULT 10,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE services.service_variants IS 'Variantes de un servicio: duración, precio o nivel diferente. Ej: corte corto/largo, masaje 30/60/90 min.';

-- ============================================================
-- 4. SERVICE PACKAGES (Paquetes / Combos)
--    Ej: "Paquete Novia" = Maquillaje + Peinado + Manicure
--        "Combo Relax"   = Masaje 60min + Facial + Hidratación
-- ============================================================
CREATE TABLE services.service_packages (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    product_id          BIGINT      REFERENCES logistics.products(id),
    -- Para facturar el paquete como un ítem en Sales

    code                VARCHAR(30) NOT NULL,
    name                VARCHAR(200) NOT NULL,
    description         TEXT,

    package_price       NUMERIC(18,4) NOT NULL,
    -- Precio del paquete (generalmente menor que la suma individual)

    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',

    -- ¿Los servicios del paquete deben tomarse en la misma cita?
    same_appointment    BOOLEAN     NOT NULL DEFAULT FALSE,

    -- Vigencia del paquete (para paquetes con vencimiento)
    validity_days       SMALLINT,
    -- NULL = no vence

    -- ¿Cuántas veces se puede usar cada servicio del paquete?
    -- (para paquetes con sesiones múltiples: "10 sesiones de yoga")
    sessions_count      SMALLINT    NOT NULL DEFAULT 1,

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE TRIGGER trg_svcpkg_updated_at
    BEFORE UPDATE ON services.service_packages
    FOR EACH ROW EXECUTE FUNCTION services.set_updated_at();

-- ============================================================
-- 5. SERVICE PACKAGE ITEMS (Servicios dentro de un Paquete)
-- ============================================================
CREATE TABLE services.service_package_items (
    id                  BIGSERIAL   PRIMARY KEY,
    package_id          BIGINT      NOT NULL REFERENCES services.service_packages(id) ON DELETE CASCADE,
    service_id          BIGINT      NOT NULL REFERENCES services.services(id),
    service_variant_id  BIGINT      REFERENCES services.service_variants(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    quantity            SMALLINT    NOT NULL DEFAULT 1,
    -- Cuántas sesiones de este servicio incluye el paquete

    display_order       SMALLINT    NOT NULL DEFAULT 10,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 6. SERVICE RESOURCES (Recursos Físicos)
--    Sillas, cabinas, camillas, equipos.
--    La disponibilidad del recurso limita cuántas citas
--    pueden ser simultáneas, independientemente del personal.
-- ============================================================
CREATE TABLE services.service_resources (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    code                VARCHAR(20) NOT NULL,
    name                VARCHAR(100) NOT NULL,
    -- 'Silla 1', 'Cabina VIP', 'Camilla 3', 'Equipo Láser A'

    resource_type       VARCHAR(20) NOT NULL DEFAULT 'station',
    -- station   : puesto de trabajo (silla de salón, butaca)
    -- room      : sala o cabina
    -- equipment : equipo especial (láser, cavitación, etc.)
    -- vehicle   : para servicios a domicilio con vehículo

    -- Vínculo con activo fijo si aplica
    fixed_asset_id      BIGINT,
    -- REFERENCES finance.fixed_assets(id) — FK diferida

    location_description VARCHAR(100),
    -- 'Planta baja', 'Piso 2 - Cabina VIP'

    -- ¿Requiere asignación explícita o se asigna automáticamente?
    auto_assign         BOOLEAN     NOT NULL DEFAULT TRUE,

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE TRIGGER trg_svcres_updated_at
    BEFORE UPDATE ON services.service_resources
    FOR EACH ROW EXECUTE FUNCTION services.set_updated_at();

-- ============================================================
-- 7. SERVICE RESOURCE REQUIREMENTS
--    Qué recursos necesita cada servicio.
--    Ej: Coloración → necesita silla + estación de lavado
--        Masaje      → necesita camilla
--        Láser       → necesita equipo láser + cabina
-- ============================================================
CREATE TABLE services.service_resource_requirements (
    id                  BIGSERIAL   PRIMARY KEY,
    service_id          BIGINT      NOT NULL REFERENCES services.services(id) ON DELETE CASCADE,
    resource_id         BIGINT      NOT NULL REFERENCES services.service_resources(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    quantity_required   SMALLINT    NOT NULL DEFAULT 1,
    is_mandatory        BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (service_id, resource_id)
);

COMMENT ON TABLE services.service_resource_requirements IS 'Qué recursos físicos necesita cada servicio. Limita la capacidad simultánea de citas.';

-- ============================================================
-- FKs diferidas: sales.promo_codes → services.services
-- Se agregan aquí porque sales carga antes que services.
-- ============================================================
ALTER TABLE sales.promo_codes
    ADD CONSTRAINT fk_pc_free_service
        FOREIGN KEY (free_service_id)
        REFERENCES services.services(id),
    ADD CONSTRAINT fk_pc_applies_service
        FOREIGN KEY (applies_to_service_id)
        REFERENCES services.services(id);
