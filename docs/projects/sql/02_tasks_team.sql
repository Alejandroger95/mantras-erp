-- ============================================================
-- mantrasdb | Módulo Projects
-- Archivo: 02_tasks_team.sql
-- Descripción: Equipo de proyecto, tareas y registro de horas.
--
-- Tablas:
--   1. project_members  — miembros del equipo por proyecto
--   2. project_tasks    — tareas granulares (con soporte agile)
--   3. time_entries     — horas registradas por miembro (IMMUTABLE)
-- ============================================================

-- ============================================================
-- 1. PROJECT MEMBERS (Equipo del proyecto)
-- ============================================================
CREATE TABLE projects.project_members (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    project_id          BIGINT          NOT NULL REFERENCES projects.projects(id) ON DELETE RESTRICT,
    employee_id         BIGINT          NOT NULL REFERENCES hr.employees(id) ON DELETE RESTRICT,

    -- Rol dentro del proyecto
    role                VARCHAR(30)     NOT NULL DEFAULT 'developer',
    -- project_manager | tech_lead | developer | qa | analyst
    -- | designer | consultant | scrum_master | other

    -- Tarifa horaria para proyectos T&M
    hourly_rate         NUMERIC(10,4),
    -- NULL = utilizar la tarifa del empleado; se captura en time_entries

    -- Planificación de horas
    allocated_hours     NUMERIC(10,2),
    -- Horas planificadas para este miembro en el proyecto

    -- Vigencia en el proyecto
    start_date          DATE,
    end_date            DATE,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_members_role
        CHECK (role IN ('project_manager','tech_lead','developer','qa','analyst',
                        'designer','consultant','scrum_master','other')),
    CONSTRAINT chk_members_dates
        CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date),
    CONSTRAINT uq_project_member
        UNIQUE (project_id, employee_id)
);

CREATE INDEX idx_members_project    ON projects.project_members (project_id);
CREATE INDEX idx_members_employee   ON projects.project_members (employee_id);
CREATE INDEX idx_members_company    ON projects.project_members (company_id);
CREATE INDEX idx_members_active     ON projects.project_members (project_id) WHERE is_active;

CREATE TRIGGER trg_project_members_updated_at
    BEFORE UPDATE ON projects.project_members
    FOR EACH ROW EXECUTE FUNCTION projects.set_updated_at();

COMMENT ON TABLE  projects.project_members              IS 'Miembros del equipo asignados a un proyecto. Un empleado puede estar en múltiples proyectos.';
COMMENT ON COLUMN projects.project_members.role         IS 'project_manager | tech_lead | developer | qa | analyst | designer | consultant | scrum_master | other';
COMMENT ON COLUMN projects.project_members.hourly_rate  IS 'Tarifa horaria para facturación T&M. Si NULL, se toma de la configuración del empleado o del proyecto.';
COMMENT ON COLUMN projects.project_members.allocated_hours IS 'Horas planificadas (capacidad reservada) para este miembro en el proyecto.';

-- ============================================================
-- 2. PROJECT TASKS (Tareas granulares)
-- ============================================================
CREATE TABLE projects.project_tasks (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    project_id          BIGINT          NOT NULL REFERENCES projects.projects(id) ON DELETE RESTRICT,
    phase_id            BIGINT          REFERENCES projects.project_phases(id),
    -- NULL = tarea no asociada a una fase específica

    -- Jerarquía de tareas (subtareas)
    parent_task_id      BIGINT          REFERENCES projects.project_tasks(id),
    -- NULL = tarea raíz; con valor = subtarea

    -- Identificación
    task_number         VARCHAR(20),
    -- Ej: "PROJ-001-T042". Generado por la aplicación.
    name                VARCHAR(300)    NOT NULL,
    description         TEXT,

    -- Asignación
    assigned_to_id      BIGINT          REFERENCES hr.employees(id),

    -- Estado y prioridad
    status              VARCHAR(20)     NOT NULL DEFAULT 'backlog',
    -- backlog | todo | in_progress | review | done | cancelled
    priority            VARCHAR(10)     NOT NULL DEFAULT 'medium',
    -- low | medium | high | critical

    -- Estimación de tiempo
    estimated_hours     NUMERIC(8,2),

    -- Fechas planificadas y reales
    planned_start       DATE,
    planned_end         DATE,
    actual_start        DATE,
    actual_end          DATE,

    -- Agile
    story_points        SMALLINT,
    -- Puntos de historia para equipos que usan Scrum/Kanban

    -- Etiquetas
    tags                VARCHAR(50)[]   NOT NULL DEFAULT '{}',

    -- Auditoría
    created_by          BIGINT          REFERENCES hr.system_users(id),
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_tasks_status
        CHECK (status IN ('backlog','todo','in_progress','review','done','cancelled')),
    CONSTRAINT chk_tasks_priority
        CHECK (priority IN ('low','medium','high','critical')),
    CONSTRAINT chk_tasks_dates
        CHECK (planned_end IS NULL OR planned_start IS NULL OR planned_end >= planned_start),
    CONSTRAINT chk_tasks_no_self_parent
        CHECK (parent_task_id IS NULL OR parent_task_id <> id)
);

CREATE INDEX idx_tasks_project      ON projects.project_tasks (project_id);
CREATE INDEX idx_tasks_phase        ON projects.project_tasks (phase_id);
CREATE INDEX idx_tasks_parent       ON projects.project_tasks (parent_task_id);
CREATE INDEX idx_tasks_assigned     ON projects.project_tasks (assigned_to_id);
CREATE INDEX idx_tasks_status       ON projects.project_tasks (project_id, status);
CREATE INDEX idx_tasks_company      ON projects.project_tasks (company_id);
CREATE INDEX idx_tasks_active       ON projects.project_tasks (project_id)
    WHERE status NOT IN ('done','cancelled');

CREATE TRIGGER trg_project_tasks_updated_at
    BEFORE UPDATE ON projects.project_tasks
    FOR EACH ROW EXECUTE FUNCTION projects.set_updated_at();

COMMENT ON TABLE  projects.project_tasks              IS 'Tareas granulares del proyecto. Soporta subtareas (parent_task_id) y metodologías agile (story_points).';
COMMENT ON COLUMN projects.project_tasks.task_number  IS 'Código legible generado por la aplicación. Ej: PROJ-001-T042.';
COMMENT ON COLUMN projects.project_tasks.story_points IS 'Puntos de historia para equipos Scrum/Kanban. NULL si no se usa agile.';
COMMENT ON COLUMN projects.project_tasks.tags         IS 'Etiquetas para clasificación y filtrado. Ej: {\"frontend\",\"bug\",\"sprint-3\"}.';

-- ============================================================
-- 3. TIME ENTRIES (Registro de horas — IMMUTABLE)
-- ============================================================
-- IMMUTABLE: los registros de tiempo no se modifican una vez guardados.
-- Para correcciones se usa una entrada negativa (ajuste) o anulación lógica.
CREATE TABLE projects.time_entries (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    project_id          BIGINT          NOT NULL REFERENCES projects.projects(id) ON DELETE RESTRICT,
    phase_id            BIGINT          REFERENCES projects.project_phases(id),
    task_id             BIGINT          REFERENCES projects.project_tasks(id),

    -- Quién registró las horas
    employee_id         BIGINT          NOT NULL REFERENCES hr.employees(id),
    member_id           BIGINT          REFERENCES projects.project_members(id),
    -- FK al registro de miembro (para tener la tarifa del período)

    -- Cuándo y cuánto
    entry_date          DATE            NOT NULL,
    hours               NUMERIC(5,2)    NOT NULL
                        CHECK (hours > 0 AND hours <= 24),
    description         TEXT,

    -- Facturación
    is_billable         BOOLEAN         NOT NULL DEFAULT TRUE,
    hourly_rate         NUMERIC(10,4),
    -- Snapshot de la tarifa en el momento del registro (T&M)

    -- Monto facturable calculado (GENERATED)
    billable_amount     NUMERIC(14,4)   GENERATED ALWAYS AS (
        CASE
            WHEN is_billable AND hourly_rate IS NOT NULL
            THEN hours * hourly_rate
            ELSE 0
        END
    ) STORED,

    -- Enlace a la línea de factura cuando se factura
    invoice_line_id     BIGINT          REFERENCES sales.invoice_lines(id)
                        DEFERRABLE INITIALLY DEFERRED,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
    -- IMMUTABLE: sin updated_at
);
-- IMMUTABLE

CREATE INDEX idx_time_entries_project    ON projects.time_entries (project_id);
CREATE INDEX idx_time_entries_employee   ON projects.time_entries (employee_id);
CREATE INDEX idx_time_entries_date       ON projects.time_entries (entry_date);
CREATE INDEX idx_time_entries_phase      ON projects.time_entries (phase_id);
CREATE INDEX idx_time_entries_task       ON projects.time_entries (task_id);
CREATE INDEX idx_time_entries_unbilled   ON projects.time_entries (project_id, entry_date)
    WHERE is_billable AND invoice_line_id IS NULL;
CREATE INDEX idx_time_entries_company    ON projects.time_entries (company_id, entry_date);

COMMENT ON TABLE  projects.time_entries                IS 'Registro de horas por miembro. IMMUTABLE: no se modifica; correcciones = nueva entrada.';
COMMENT ON COLUMN projects.time_entries.hours          IS 'Horas trabajadas en esta entrada. Debe ser > 0 y <= 24.';
COMMENT ON COLUMN projects.time_entries.hourly_rate    IS 'Snapshot de la tarifa horaria al momento del registro. Permite recalcular facturación histórica.';
COMMENT ON COLUMN projects.time_entries.billable_amount IS 'Calculado: hours * hourly_rate cuando is_billable=TRUE y hourly_rate IS NOT NULL. GENERATED STORED.';
COMMENT ON COLUMN projects.time_entries.invoice_line_id IS 'FK a la línea de factura. NULL = aún no facturado. DEFERRABLE para crear factura en la misma TX.';
