-- ============================================================
-- MIGRACIÓN: RBAC — Roles y Permisos dinámicos
-- ============================================================
-- 1. Crear hr.roles          (catálogo de roles por empresa)
-- 2. Crear hr.role_permissions (permisos asignados a cada rol)
-- 3. Migrar hr.system_users  (role_id FK en vez de role VARCHAR)
-- 4. Insertar roles base con sus permisos
-- ============================================================

BEGIN;

-- ── 1. hr.roles ───────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS hr.roles (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    name            VARCHAR(100)    NOT NULL,   -- 'Administrador', 'Jefe de equipo', etc.
    description     TEXT,

    -- Nivel base del rol — define el alcance mínimo garantizado
    -- El admin siempre bypasea todo; los demás dependen de role_permissions
    base_level      VARCHAR(20)     NOT NULL DEFAULT 'employee',
    -- 'superadmin' → acceso total a todas las empresas (solo Mantras internamente)
    -- 'admin'      → acceso total a su empresa, bypasea permisos
    -- 'employee'   → accede según sus permisos asignados

    is_system       BOOLEAN         NOT NULL DEFAULT FALSE,
    -- TRUE = rol creado por Mantras, no se puede eliminar
    -- FALSE = rol creado por la empresa, personalizable

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_role_base_level CHECK (base_level IN ('superadmin', 'admin', 'employee')),
    UNIQUE (company_id, name)
);

CREATE TRIGGER trg_roles_updated_at
    BEFORE UPDATE ON hr.roles
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_roles_company ON hr.roles (company_id);

COMMENT ON TABLE  hr.roles            IS 'Catálogo de roles por empresa. Cada rol tiene un conjunto de permisos en hr.role_permissions.';
COMMENT ON COLUMN hr.roles.base_level IS 'superadmin | admin | employee. Admin bypasea permisos. Employee depende de role_permissions.';
COMMENT ON COLUMN hr.roles.is_system  IS 'TRUE = creado por Mantras, no se puede eliminar. FALSE = personalizable por la empresa.';

-- ── 2. hr.role_permissions ────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS hr.role_permissions (
    id              BIGSERIAL       PRIMARY KEY,
    role_id         BIGINT          NOT NULL REFERENCES hr.roles(id) ON DELETE CASCADE,

    permission      VARCHAR(100)    NOT NULL,
    -- Formato: modulo.accion
    -- Ejemplos:
    --   punches.view_own          → ver sus propios fichajes
    --   punches.view_team         → ver fichajes de su equipo
    --   punches.create_retroactive→ crear fichajes retroactivos
    --   punches.cancel            → cancelar fichajes
    --   punches.annul             → anular fichajes
    --   punches.edit_time         → editar hora de fichaje
    --   absences.view_own         → ver sus propias ausencias
    --   absences.view_team        → ver ausencias de su equipo
    --   absences.request          → solicitar ausencias
    --   absences.approve          → aprobar ausencias de su equipo
    --   absences.reject           → rechazar ausencias
    --   absences.manage_all       → gestionar ausencias de toda la empresa
    --   employees.view_team       → ver empleados de su equipo
    --   employees.view_all        → ver todos los empleados
    --   employees.edit            → editar datos de empleados
    --   reports.view_team         → reportes de su equipo
    --   reports.view_company      → reportes de toda la empresa
    --   audit.view                → ver log de auditoría
    --   company.settings          → configuración de empresa
    --   work_locations.manage     → gestionar ubicaciones de trabajo
    --   schedules.manage          → gestionar cuadrantes y horarios
    --   module.hr                 → acceso al módulo HR
    --   module.logistics          → acceso al módulo Logística
    --   module.sales              → acceso al módulo Ventas
    --   module.finance            → acceso al módulo Finanzas
    --   module.production         → acceso al módulo Producción
    --   module.projects           → acceso al módulo Proyectos

    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    -- No necesita updated_at — inmutable. Si cambia, se borra y recrea.

    UNIQUE (role_id, permission)
);

CREATE INDEX IF NOT EXISTS idx_role_permissions_role ON hr.role_permissions (role_id);

COMMENT ON TABLE  hr.role_permissions            IS 'Permisos asignados a cada rol. Inmutable por fila — si cambia un permiso se elimina y se inserta de nuevo.';
COMMENT ON COLUMN hr.role_permissions.permission IS 'String en formato modulo.accion. Ej: punches.approve, absences.view_team, module.hr';

-- ── 3. Migrar hr.system_users ─────────────────────────────────────────────────

-- Añadir role_id (el nuevo campo)
ALTER TABLE hr.system_users
    ADD COLUMN IF NOT EXISTS role_id BIGINT REFERENCES hr.roles(id);

COMMENT ON COLUMN hr.system_users.role_id IS 'Rol asignado al usuario. Define sus permisos via hr.role_permissions.';

-- Nota: mantenemos temporalmente la columna "role" varchar para migración
-- Se puede eliminar después de validar que todo funciona con role_id

-- ── 4. Insertar roles base para cada empresa ──────────────────────────────────
-- Roles de sistema (is_system = TRUE) que Mantras crea automáticamente

INSERT INTO hr.roles (company_id, name, description, base_level, is_system)
SELECT
    c.id,
    r.name,
    r.description,
    r.base_level,
    TRUE
FROM hr.companies c
CROSS JOIN (VALUES
    (
        'Administrador',
        'Acceso total a la empresa. Puede auditar, configurar y gestionar todo.',
        'admin'
    ),
    (
        'Supervisor',
        'Gestiona su equipo: aprueba ausencias, revisa fichajes, ve reportes de equipo.',
        'employee'
    ),
    (
        'Jefe de equipo',
        'Ve a su equipo en modo lectura. No puede aprobar ni gestionar.',
        'employee'
    ),
    (
        'Empleado',
        'Acceso básico: sus propios fichajes, sus propias ausencias.',
        'employee'
    ),
    (
        'RRHH',
        'Gestión completa del módulo HR: empleados, ausencias, fichajes de toda la empresa.',
        'employee'
    ),
    (
        'Solo lectura',
        'Puede ver datos pero no modificar nada.',
        'employee'
    )
) AS r(name, description, base_level)
WHERE NOT EXISTS (
    SELECT 1 FROM hr.roles ro
    WHERE ro.company_id = c.id AND ro.name = r.name
);

-- ── 5. Insertar permisos por rol ──────────────────────────────────────────────

-- Empleado base
INSERT INTO hr.role_permissions (role_id, permission)
SELECT r.id, p.permission
FROM hr.roles r
CROSS JOIN (VALUES
    ('module.hr'),
    ('punches.view_own'),
    ('absences.view_own'),
    ('absences.request')
) AS p(permission)
WHERE r.name = 'Empleado'
  AND r.is_system = TRUE
ON CONFLICT (role_id, permission) DO NOTHING;

-- Jefe de equipo (lectura de equipo, sin aprobaciones)
INSERT INTO hr.role_permissions (role_id, permission)
SELECT r.id, p.permission
FROM hr.roles r
CROSS JOIN (VALUES
    ('module.hr'),
    ('punches.view_own'),
    ('punches.view_team'),
    ('absences.view_own'),
    ('absences.view_team'),
    ('absences.request'),
    ('employees.view_team'),
    ('reports.view_team')
) AS p(permission)
WHERE r.name = 'Jefe de equipo'
  AND r.is_system = TRUE
ON CONFLICT (role_id, permission) DO NOTHING;

-- Supervisor (gestión completa de su equipo)
INSERT INTO hr.role_permissions (role_id, permission)
SELECT r.id, p.permission
FROM hr.roles r
CROSS JOIN (VALUES
    ('module.hr'),
    ('punches.view_own'),
    ('punches.view_team'),
    ('punches.cancel'),
    ('absences.view_own'),
    ('absences.view_team'),
    ('absences.request'),
    ('absences.approve'),
    ('absences.reject'),
    ('employees.view_team'),
    ('employees.view_all'),
    ('reports.view_team'),
    ('schedules.manage')
) AS p(permission)
WHERE r.name = 'Supervisor'
  AND r.is_system = TRUE
ON CONFLICT (role_id, permission) DO NOTHING;

-- RRHH (módulo HR completo, sin configuración de empresa)
INSERT INTO hr.role_permissions (role_id, permission)
SELECT r.id, p.permission
FROM hr.roles r
CROSS JOIN (VALUES
    ('module.hr'),
    ('punches.view_own'),
    ('punches.view_team'),
    ('punches.cancel'),
    ('punches.annul'),
    ('punches.create_retroactive'),
    ('punches.edit_time'),
    ('absences.view_own'),
    ('absences.view_team'),
    ('absences.request'),
    ('absences.approve'),
    ('absences.reject'),
    ('absences.manage_all'),
    ('employees.view_team'),
    ('employees.view_all'),
    ('employees.edit'),
    ('reports.view_team'),
    ('reports.view_company'),
    ('work_locations.manage'),
    ('schedules.manage')
) AS p(permission)
WHERE r.name = 'RRHH'
  AND r.is_system = TRUE
ON CONFLICT (role_id, permission) DO NOTHING;

-- Solo lectura
INSERT INTO hr.role_permissions (role_id, permission)
SELECT r.id, p.permission
FROM hr.roles r
CROSS JOIN (VALUES
    ('module.hr'),
    ('punches.view_own'),
    ('absences.view_own'),
    ('employees.view_all'),
    ('reports.view_company')
) AS p(permission)
WHERE r.name = 'Solo lectura'
  AND r.is_system = TRUE
ON CONFLICT (role_id, permission) DO NOTHING;

-- Administrador: base_level = 'admin', bypasea permisos → no necesita filas en role_permissions
-- Pero insertamos algunos para documentar qué puede hacer
INSERT INTO hr.role_permissions (role_id, permission)
SELECT r.id, p.permission
FROM hr.roles r
CROSS JOIN (VALUES
    ('module.hr'),
    ('module.logistics'),
    ('module.sales'),
    ('module.finance'),
    ('module.production'),
    ('module.projects'),
    ('punches.view_own'),
    ('punches.view_team'),
    ('punches.cancel'),
    ('punches.annul'),
    ('punches.create_retroactive'),
    ('punches.edit_time'),
    ('absences.view_own'),
    ('absences.view_team'),
    ('absences.approve'),
    ('absences.reject'),
    ('absences.manage_all'),
    ('employees.view_all'),
    ('employees.edit'),
    ('reports.view_company'),
    ('audit.view'),
    ('company.settings'),
    ('work_locations.manage'),
    ('schedules.manage')
) AS p(permission)
WHERE r.name = 'Administrador'
  AND r.is_system = TRUE
ON CONFLICT (role_id, permission) DO NOTHING;

-- ── 6. Asignar rol 'Empleado' a usuarios existentes sin role_id ───────────────
UPDATE hr.system_users su
SET role_id = (
    SELECT r.id FROM hr.roles r
    WHERE r.company_id = su.company_id
      AND r.name = 'Empleado'
      AND r.is_system = TRUE
    LIMIT 1
)
WHERE su.role_id IS NULL
  AND su.role NOT IN ('super_admin', 'admin');

-- Asignar rol 'Administrador' a los que tienen role = 'admin'
UPDATE hr.system_users su
SET role_id = (
    SELECT r.id FROM hr.roles r
    WHERE r.company_id = su.company_id
      AND r.name = 'Administrador'
      AND r.is_system = TRUE
    LIMIT 1
)
WHERE su.role_id IS NULL
  AND su.role IN ('super_admin', 'admin');

COMMIT;
