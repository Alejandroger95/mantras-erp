-- ============================================================
-- mantrasdb | Módulo Projects
-- Archivo: 01_projects.sql
-- Descripción: Proyectos — núcleo del módulo.
--
-- Sirve para cualquier negocio basado en proyectos:
--   🖥  Agencia de software    — sprints, épicas, historias de usuario
--   💼 Consultoría IT          — fases, entregables, control de horas
--   📣 Agencia de marketing    — campañas, creativos, lanzamientos
--   🏗  Construcción            — fases de obra, hitos de avance
--   📋 Auditoría / contabilidad — fieldwork, revisión, cierre
--   🎓 Proyectos de formación   — módulos, evaluaciones, certificación
--
-- Tablas:
--   1. project_types      — catálogo de tipos de proyecto
--   2. projects           — entidad principal del proyecto
--   3. project_phases     — fases / etapas dentro de un proyecto
--   4. project_milestones — hitos de entrega o facturación
-- ============================================================

CREATE SCHEMA IF NOT EXISTS projects;

-- Función reutilizable para updated_at automático
CREATE OR REPLACE FUNCTION projects.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- ============================================================
-- 1. PROJECT TYPES (Catálogo de tipos de proyecto)
-- ============================================================
CREATE TABLE projects.project_types (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    name            VARCHAR(100)    NOT NULL,
    -- Ej: Software Development, IT Consulting, Marketing Campaign,
    --     Construction, Audit, Training
    description     TEXT,
    icon            VARCHAR(50),
    -- Ej: 'laptop-code', 'briefcase', 'megaphone', 'hard-hat', 'clipboard-check'
    color_hex       CHAR(7),
    -- Color de la tarjeta en el tablero (#RRGGBB)
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_project_types_name
    ON projects.project_types (company_id, UPPER(name));

CREATE INDEX idx_project_types_company
    ON projects.project_types (company_id);

CREATE TRIGGER trg_project_types_updated_at
    BEFORE UPDATE ON projects.project_types
    FOR EACH ROW EXECUTE FUNCTION projects.set_updated_at();

COMMENT ON TABLE  projects.project_types           IS 'Catálogo de tipos de proyecto. Ej: Software Dev, Consultoría, Construcción.';
COMMENT ON COLUMN projects.project_types.icon      IS 'Nombre de ícono (FontAwesome o Material Icons) para uso en la UI.';
COMMENT ON COLUMN projects.project_types.color_hex IS 'Color hexadecimal para identificar visualmente el tipo en tableros y calendarios.';

-- ============================================================
-- 2. PROJECTS (Entidad principal)
-- ============================================================
CREATE TABLE projects.projects (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- Identificación
    code                VARCHAR(30)     NOT NULL,
    -- Formato sugerido: "PROJ-2024-001" | "CLI-0042" | "INT-2024-003"
    name                VARCHAR(200)    NOT NULL,
    description         TEXT,

    -- Clasificación
    project_type_id     BIGINT          REFERENCES projects.project_types(id),

    -- Relaciones externas
    customer_id         BIGINT          REFERENCES sales.customers(id),
    -- NULL = proyecto interno (is_internal = TRUE)
    sales_order_id      BIGINT          REFERENCES sales.sales_orders(id),
    -- Orden de venta que originó el proyecto (nullable)

    -- Responsable
    project_manager_id  BIGINT          REFERENCES hr.employees(id),

    -- Estado del ciclo de vida
    status              VARCHAR(20)     NOT NULL DEFAULT 'draft',
    -- draft | planning | active | on_hold | completed | cancelled

    -- Tipo de facturación
    billing_type        VARCHAR(20)     NOT NULL DEFAULT 'fixed_price',
    -- fixed_price | time_and_materials | milestone | retainer | pro_bono

    -- Presupuesto y finanzas
    currency            CHAR(3)         NOT NULL DEFAULT 'PEN',
    budget_hours        NUMERIC(10,2),
    -- Total de horas planificadas del proyecto
    budget_amount       NUMERIC(18,4),
    -- Presupuesto total en moneda del proyecto
    actual_cost         NUMERIC(18,4)   NOT NULL DEFAULT 0,
    -- Se actualiza conforme se registran time_entries

    -- Fechas planificadas y reales
    planned_start       DATE,
    planned_end         DATE,
    actual_start        DATE,
    actual_end          DATE,

    -- Progreso
    progress_pct        NUMERIC(5,2)    NOT NULL DEFAULT 0
                        CHECK (progress_pct BETWEEN 0 AND 100),
    -- Porcentaje de avance: 0.00 – 100.00

    -- Flags
    is_internal         BOOLEAN         NOT NULL DEFAULT FALSE,
    -- TRUE = proyecto interno, no se factura al cliente
    priority            VARCHAR(10)     NOT NULL DEFAULT 'medium',
    -- low | medium | high | critical
    tags                VARCHAR(50)[]   NOT NULL DEFAULT '{}',
    -- Etiquetas libres para búsqueda y filtrado

    -- Auditoría
    created_by          BIGINT          REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_projects_status
        CHECK (status IN ('draft','planning','active','on_hold','completed','cancelled')),
    CONSTRAINT chk_projects_billing_type
        CHECK (billing_type IN ('fixed_price','time_and_materials','milestone','retainer','pro_bono')),
    CONSTRAINT chk_projects_priority
        CHECK (priority IN ('low','medium','high','critical')),
    CONSTRAINT chk_projects_dates
        CHECK (planned_end IS NULL OR planned_start IS NULL OR planned_end >= planned_start),
    CONSTRAINT chk_projects_actual_dates
        CHECK (actual_end IS NULL OR actual_start IS NULL OR actual_end >= actual_start)
);

-- Código de proyecto único por empresa
CREATE UNIQUE INDEX idx_projects_code
    ON projects.projects (company_id, code);

CREATE INDEX idx_projects_company      ON projects.projects (company_id);
CREATE INDEX idx_projects_customer     ON projects.projects (customer_id);
CREATE INDEX idx_projects_manager      ON projects.projects (project_manager_id);
CREATE INDEX idx_projects_status       ON projects.projects (company_id, status);
CREATE INDEX idx_projects_type         ON projects.projects (project_type_id);
CREATE INDEX idx_projects_order        ON projects.projects (sales_order_id);
CREATE INDEX idx_projects_active       ON projects.projects (company_id, planned_end)
    WHERE status IN ('active','planning');

CREATE TRIGGER trg_projects_updated_at
    BEFORE UPDATE ON projects.projects
    FOR EACH ROW EXECUTE FUNCTION projects.set_updated_at();

COMMENT ON TABLE  projects.projects                IS 'Entidad principal del módulo Projects. Multi-tenant (company_id).';
COMMENT ON COLUMN projects.projects.code           IS 'Código único por empresa. Ej: PROJ-2024-001. Se recomienda generarlo desde la aplicación.';
COMMENT ON COLUMN projects.projects.billing_type   IS 'fixed_price: precio fijo | time_and_materials: horas*tarifa | milestone: por hito | retainer: cuota mensual | pro_bono: sin costo.';
COMMENT ON COLUMN projects.projects.actual_cost    IS 'Costo real acumulado. Actualizado por trigger o aplicación al registrar time_entries y gastos.';
COMMENT ON COLUMN projects.projects.is_internal    IS 'TRUE = proyecto interno (I+D, mejora de procesos, etc.). customer_id suele ser NULL.';
COMMENT ON COLUMN projects.projects.tags           IS 'Arreglo de etiquetas libres. Ej: {\"agile\",\"backend\",\"cliente-vip\"}.';

-- ============================================================
-- 3. PROJECT PHASES (Fases del proyecto)
-- ============================================================
CREATE TABLE projects.project_phases (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    project_id          BIGINT          NOT NULL REFERENCES projects.projects(id) ON DELETE RESTRICT,

    -- Ordenamiento dentro del proyecto
    phase_number        SMALLINT        NOT NULL,
    -- Ej: 1=Análisis, 2=Diseño, 3=Desarrollo, 4=QA, 5=Deploy
    name                VARCHAR(100)    NOT NULL,
    description         TEXT,

    -- Estado
    status              VARCHAR(20)     NOT NULL DEFAULT 'planned',
    -- planned | in_progress | completed | cancelled

    -- Fechas planificadas y reales
    planned_start       DATE,
    planned_end         DATE,
    actual_start        DATE,
    actual_end          DATE,

    -- Progreso y presupuesto
    progress_pct        NUMERIC(5,2)    NOT NULL DEFAULT 0
                        CHECK (progress_pct BETWEEN 0 AND 100),
    estimated_hours     NUMERIC(10,2),
    budget_amount       NUMERIC(18,4),

    -- Facturación
    is_billable         BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_phases_status
        CHECK (status IN ('planned','in_progress','completed','cancelled')),
    CONSTRAINT chk_phases_dates
        CHECK (planned_end IS NULL OR planned_start IS NULL OR planned_end >= planned_start),
    CONSTRAINT uq_phase_number
        UNIQUE (project_id, phase_number)
);

CREATE INDEX idx_phases_project    ON projects.project_phases (project_id);
CREATE INDEX idx_phases_company    ON projects.project_phases (company_id);
CREATE INDEX idx_phases_status     ON projects.project_phases (project_id, status);

CREATE TRIGGER trg_project_phases_updated_at
    BEFORE UPDATE ON projects.project_phases
    FOR EACH ROW EXECUTE FUNCTION projects.set_updated_at();

COMMENT ON TABLE  projects.project_phases              IS 'Fases o etapas del proyecto. Ej: Análisis, Diseño, Desarrollo, QA, Deploy.';
COMMENT ON COLUMN projects.project_phases.phase_number IS 'Orden secuencial de la fase dentro del proyecto. Unique (project_id, phase_number).';
COMMENT ON COLUMN projects.project_phases.is_billable  IS 'FALSE para fases de gestión interna que no se facturan al cliente.';

-- ============================================================
-- 4. PROJECT MILESTONES (Hitos de entrega o facturación)
-- ============================================================
CREATE TABLE projects.project_milestones (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    project_id          BIGINT          NOT NULL REFERENCES projects.projects(id) ON DELETE RESTRICT,
    phase_id            BIGINT          REFERENCES projects.project_phases(id),
    -- NULL = hito global del proyecto, no asociado a una fase

    -- Identificación
    name                VARCHAR(200)    NOT NULL,
    description         TEXT,

    -- Fecha objetivo
    due_date            DATE            NOT NULL,

    -- Tipo de hito
    milestone_type      VARCHAR(20)     NOT NULL DEFAULT 'delivery',
    -- delivery | billing | review | sign_off | go_live

    -- Para hitos de facturación
    amount              NUMERIC(18,4),
    -- Monto a facturar cuando se alcanza el hito

    -- Estado de cumplimiento
    is_reached          BOOLEAN         NOT NULL DEFAULT FALSE,
    reached_at          TIMESTAMPTZ,
    -- Fecha/hora en que se marcó como alcanzado

    -- Factura generada al alcanzar el hito
    invoice_id          BIGINT          REFERENCES sales.invoices(id)
                        DEFERRABLE INITIALLY DEFERRED,
    -- FK diferida: la factura puede crearse después de marcar el hito

    notes               TEXT,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_milestones_type
        CHECK (milestone_type IN ('delivery','billing','review','sign_off','go_live')),
    CONSTRAINT chk_milestones_reached
        CHECK (NOT is_reached OR reached_at IS NOT NULL)
    -- Si is_reached=TRUE, reached_at debe estar establecido
);

CREATE INDEX idx_milestones_project   ON projects.project_milestones (project_id);
CREATE INDEX idx_milestones_company   ON projects.project_milestones (company_id);
CREATE INDEX idx_milestones_phase     ON projects.project_milestones (phase_id);
CREATE INDEX idx_milestones_due       ON projects.project_milestones (project_id, due_date);
CREATE INDEX idx_milestones_unbilled  ON projects.project_milestones (project_id)
    WHERE is_reached AND invoice_id IS NULL AND milestone_type = 'billing';

CREATE TRIGGER trg_project_milestones_updated_at
    BEFORE UPDATE ON projects.project_milestones
    FOR EACH ROW EXECUTE FUNCTION projects.set_updated_at();

COMMENT ON TABLE  projects.project_milestones              IS 'Hitos de entrega, facturación, revisión o go-live del proyecto.';
COMMENT ON COLUMN projects.project_milestones.amount       IS 'Monto a cobrar en hitos de tipo billing. NULL para hitos de entrega sin valor económico.';
COMMENT ON COLUMN projects.project_milestones.invoice_id   IS 'FK a la factura emitida. DEFERRABLE para permitir crear la factura en la misma transacción.';
COMMENT ON COLUMN projects.project_milestones.reached_at   IS 'Timestamp de cuando el hito fue marcado como alcanzado.';
