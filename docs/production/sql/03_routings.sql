-- ============================================================
-- mantrasdb | Módulo Production
-- Archivo: 03_routings.sql
-- Descripción: Rutas de Producción y Operaciones
--
-- La RUTA define la secuencia de pasos para fabricar un producto.
-- Cada paso = una OPERACIÓN en un CENTRO DE TRABAJO.
--
-- Módulos:
--   1. routings            — cabecera de ruta (versiones como BOM)
--   2. routing_operations  — operaciones (pasos) de la ruta
--   3. operation_tools     — herramientas/útiles por operación
--   4. operation_skills    — habilidades requeridas del operario
--   5. routing_bom_link    — vínculo ruta ↔ BOM (un producto puede
--                            tener múltiples rutas según planta/método)
--
-- Tiempos clave por operación:
--   setup_time  : preparación de la máquina/herramienta
--   run_time    : tiempo real de proceso por unidad
--   teardown_time: limpieza y desmontaje
--   wait_time   : tiempo de espera entre operaciones (curado, secado)
--   queue_time  : tiempo en cola esperando disponibilidad del centro
-- ============================================================

-- ============================================================
-- 1. ROUTINGS (Rutas de Producción)
-- ============================================================
CREATE TABLE production.routings (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Producto al que aplica esta ruta
    product_id          BIGINT      NOT NULL REFERENCES logistics.products(id),
    product_variant_id  BIGINT      REFERENCES logistics.product_variants(id),

    code                VARCHAR(30) NOT NULL,
    name                VARCHAR(200) NOT NULL,
    description         TEXT,

    routing_type        VARCHAR(20) NOT NULL DEFAULT 'manufacturing',
    -- manufacturing : proceso de fabricación estándar
    -- disassembly   : proceso de desarmado (logística inversa)
    -- refurbishment : proceso de reacondicionamiento
    -- repair        : proceso de reparación
    -- quality_check : inspección de calidad stand-alone

    -- Versión activa (FK diferida)
    active_version_id   BIGINT,

    status              VARCHAR(20) NOT NULL DEFAULT 'active',
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE TRIGGER trg_routing_updated_at
    BEFORE UPDATE ON production.routings
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

-- ============================================================
-- 2. ROUTING VERSIONS
-- ============================================================
CREATE TABLE production.routing_versions (
    id                  BIGSERIAL   PRIMARY KEY,
    routing_id          BIGINT      NOT NULL REFERENCES production.routings(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    version_number      SMALLINT    NOT NULL DEFAULT 1,
    version_name        VARCHAR(50),
    change_reason       TEXT,

    valid_from          DATE        NOT NULL DEFAULT CURRENT_DATE,
    valid_to            DATE,

    status              VARCHAR(20) NOT NULL DEFAULT 'draft',

    approved_by         BIGINT      REFERENCES hr.system_users(id),
    approved_at         TIMESTAMPTZ,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (routing_id, version_number)
);

CREATE TRIGGER trg_routver_updated_at
    BEFORE UPDATE ON production.routing_versions
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

ALTER TABLE production.routings
    ADD CONSTRAINT fk_routing_active_version
    FOREIGN KEY (active_version_id) REFERENCES production.routing_versions(id)
    DEFERRABLE INITIALLY DEFERRED;

-- ============================================================
-- 3. ROUTING OPERATIONS (Pasos de la Ruta)
-- ============================================================
CREATE TABLE production.routing_operations (
    id                  BIGSERIAL   PRIMARY KEY,
    routing_version_id  BIGINT      NOT NULL REFERENCES production.routing_versions(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    sequence            SMALLINT    NOT NULL,
    -- Número de paso: 10, 20, 30... (saltos de 10 para insertar pasos)

    operation_code      VARCHAR(30) NOT NULL,
    operation_name      VARCHAR(200) NOT NULL,
    description         TEXT,

    -- Centro de trabajo donde se realiza esta operación
    work_center_id      BIGINT      NOT NULL REFERENCES production.work_centers(id),

    -- Máquina específica (opcional, NULL = cualquier máquina del centro)
    machine_id          BIGINT      REFERENCES production.machines(id),

    -- ── Tiempos (en minutos) ──────────────────────────────────
    setup_time_min      NUMERIC(10,4) NOT NULL DEFAULT 0,
    -- Preparación: cambio de molde, calibración, limpieza previa

    run_time_min        NUMERIC(10,4) NOT NULL DEFAULT 0,
    -- Tiempo de proceso POR UNIDAD (o por lote si is_per_batch=TRUE)

    teardown_time_min   NUMERIC(10,4) NOT NULL DEFAULT 0,
    -- Desmontaje, limpieza posterior

    wait_time_min       NUMERIC(10,4) NOT NULL DEFAULT 0,
    -- Espera después de esta operación (curado de cemento, secado pintura,
    -- enfriamiento de fundición, fermentación, etc.)

    queue_time_min      NUMERIC(10,4) NOT NULL DEFAULT 0,
    -- Tiempo en cola esperando disponibilidad del centro

    -- ¿El tiempo de proceso es por lote o por unidad?
    is_time_per_batch   BOOLEAN     NOT NULL DEFAULT FALSE,

    -- ── Recursos humanos ─────────────────────────────────────
    -- Número de operarios necesarios en esta operación
    operators_required  SMALLINT    NOT NULL DEFAULT 1,

    -- Horas-hombre por unidad producida
    labor_time_min      NUMERIC(10,4) NOT NULL DEFAULT 0,

    -- ── Costos ───────────────────────────────────────────────
    -- Tasa de máquina (si es diferente a la del centro)
    machine_cost_per_hour NUMERIC(18,4),

    -- ── Control de calidad en línea ───────────────────────────
    -- ¿Esta operación incluye un punto de control de calidad?
    has_quality_check   BOOLEAN     NOT NULL DEFAULT FALSE,

    -- ¿Es un punto de control crítico (HACCP para alimentos)?
    is_critical_control_point BOOLEAN NOT NULL DEFAULT FALSE,

    -- ¿Es una operación de subcontratación?
    is_subcontracted    BOOLEAN     NOT NULL DEFAULT FALSE,
    subcontractor_id    BIGINT      REFERENCES logistics.suppliers(id),

    -- ── Para logística inversa / refurbishment ────────────────
    -- ¿Esta operación es de clasificación/grading?
    is_grading_step     BOOLEAN     NOT NULL DEFAULT FALSE,

    -- ¿Esta operación puede generar rechazo (enviar a otra ruta)?
    can_generate_scrap  BOOLEAN     NOT NULL DEFAULT FALSE,
    scrap_routing_id    BIGINT      REFERENCES production.routings(id),
    -- Si hay rechazo, ¿a qué ruta va? (ej: ruta de reproceso)

    -- ── Dependencias entre pasos ─────────────────────────────
    -- Esta operación no puede empezar hasta que terminen estas otras
    depends_on_operations BIGINT[],
    -- Array de routing_operations.id que deben completarse antes

    is_parallel         BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE = puede ejecutarse en paralelo con la operación anterior

    is_optional         BOOLEAN     NOT NULL DEFAULT FALSE,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (routing_version_id, sequence)
);

CREATE INDEX idx_routop_version    ON production.routing_operations (routing_version_id);
CREATE INDEX idx_routop_workcenter ON production.routing_operations (work_center_id);

CREATE TRIGGER trg_routop_updated_at
    BEFORE UPDATE ON production.routing_operations
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

COMMENT ON TABLE production.routing_operations IS 'Pasos de la ruta: secuencia de operaciones con tiempos setup/run/wait. Soporta paralelo, subcontratación y grading para refurbishment.';

-- ============================================================
-- 4. OPERATION TOOLS (Herramientas y Útiles)
--    Herramientas, moldes, troqueles, plantillas necesarias
--    para una operación específica.
-- ============================================================
CREATE TABLE production.operation_tools (
    id                  BIGSERIAL   PRIMARY KEY,
    routing_operation_id BIGINT     NOT NULL REFERENCES production.routing_operations(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    tool_product_id     BIGINT      REFERENCES logistics.products(id),
    -- El útil registrado como producto en el catálogo

    tool_description    VARCHAR(200),
    -- Para útiles no registrados como producto

    quantity_required   NUMERIC(10,4) NOT NULL DEFAULT 1,
    uom_id              BIGINT      REFERENCES logistics.measurement_units(id),

    -- ¿Es consumible (se gasta) o reutilizable?
    is_consumable       BOOLEAN     NOT NULL DEFAULT FALSE,

    is_required         BOOLEAN     NOT NULL DEFAULT TRUE,
    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 5. OPERATION SKILL REQUIREMENTS
--    Habilidades que debe tener el operario para esta operación.
--    Se cruza con los skills de los empleados (HR).
-- ============================================================
CREATE TABLE production.operation_skill_requirements (
    id                  BIGSERIAL   PRIMARY KEY,
    routing_operation_id BIGINT     NOT NULL REFERENCES production.routing_operations(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    skill_name          VARCHAR(100) NOT NULL,
    -- 'Soldadura TIG', 'Engaste de piedras', 'Costura en línea recta'

    skill_level         VARCHAR(20) NOT NULL DEFAULT 'basic',
    -- basic / intermediate / advanced / expert

    -- ¿Es obligatorio o solo preferible?
    is_mandatory        BOOLEAN     NOT NULL DEFAULT TRUE,

    -- Certificación necesaria (si aplica)
    certification_required VARCHAR(100),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 6. ROUTING ↔ BOM LINK
--    Vincula una ruta con un BOM.
--    Un producto puede tener múltiples combos ruta+BOM
--    según planta, método o configuración.
-- ============================================================
CREATE TABLE production.routing_bom_links (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    routing_id          BIGINT      NOT NULL REFERENCES production.routings(id),
    bom_header_id       BIGINT      NOT NULL REFERENCES production.bom_headers(id),

    -- ¿Es la combinación por defecto para este producto?
    is_default          BOOLEAN     NOT NULL DEFAULT FALSE,

    -- Planta/almacén donde aplica esta combinación
    warehouse_id        BIGINT      REFERENCES logistics.warehouses(id),
    -- NULL = aplica a todas las plantas

    valid_from          DATE,
    valid_to            DATE,

    notes               TEXT,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (routing_id, bom_header_id)
);

COMMENT ON TABLE production.routing_bom_links IS 'Vincula rutas con BOMs. Un producto puede tener distintas combinaciones ruta+BOM por planta o método.';

-- ============================================================
-- VIEW: Ruta completa con tiempos totales
-- ============================================================
CREATE VIEW production.routing_summary AS
SELECT
    r.id AS routing_id,
    r.company_id,
    r.code AS routing_code,
    r.name AS routing_name,
    r.routing_type,
    rv.id AS version_id,
    rv.version_number,
    COUNT(ro.id) AS total_operations,
    SUM(ro.setup_time_min) AS total_setup_min,
    SUM(ro.run_time_min) AS total_run_min,
    SUM(ro.teardown_time_min) AS total_teardown_min,
    SUM(ro.wait_time_min) AS total_wait_min,
    SUM(ro.queue_time_min) AS total_queue_min,
    SUM(ro.setup_time_min + ro.run_time_min + ro.teardown_time_min +
        ro.wait_time_min + ro.queue_time_min) AS total_lead_time_min,
    SUM(ro.labor_time_min * ro.operators_required) AS total_labor_min
FROM production.routings r
JOIN production.routing_versions rv ON rv.id = r.active_version_id
JOIN production.routing_operations ro ON ro.routing_version_id = rv.id
WHERE r.is_active = TRUE AND ro.is_active = TRUE
GROUP BY r.id, r.company_id, r.code, r.name, r.routing_type, rv.id, rv.version_number;

COMMENT ON VIEW production.routing_summary IS 'Resumen de la ruta activa: total de operaciones, tiempos de proceso, setup, espera y mano de obra.';
