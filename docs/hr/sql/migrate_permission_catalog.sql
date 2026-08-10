-- ============================================================
-- MIGRACIÓN: Catálogo de permisos + refactor hr.role_permissions
-- ============================================================
-- 1. hr.permission_catalog → todos los permisos posibles del sistema
-- 2. Refactorizar hr.role_permissions → FK al catálogo
-- 3. Re-insertar permisos de roles base apuntando al catálogo
-- ============================================================

BEGIN;

-- ── 1. hr.permission_catalog ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS hr.permission_catalog (
    id              BIGSERIAL       PRIMARY KEY,

    -- Clasificación del permiso
    module          VARCHAR(30)     NOT NULL,
    -- 'hr' | 'logistics' | 'sales' | 'finance' | 'production' | 'projects' | 'system'

    resource        VARCHAR(50)     NOT NULL,
    -- Qué entidad afecta: 'punches' | 'absences' | 'employees' | 'teams' |
    -- 'payroll' | 'schedules' | 'work_locations' | 'roles' | 'reports' |
    -- 'audit' | 'inventory' | 'orders' | 'invoices' | 'budgets' | etc.

    action          VARCHAR(50)     NOT NULL,
    -- Qué puede hacer: 'view_own' | 'view_team' | 'view_all' |
    -- 'create' | 'edit' | 'delete_soft' | 'cancel' | 'annul' |
    -- 'approve' | 'reject' | 'export' | 'import' | 'configure' | 'manage'

    -- Clave única generada: module.resource.action
    permission      VARCHAR(150)    NOT NULL UNIQUE,
    -- Ej: 'hr.punches.view_own', 'sales.orders.approve', 'system.roles.manage'

    -- Descripción legible para la UI del admin
    description     VARCHAR(300)    NOT NULL,

    -- Nivel de riesgo — para mostrar con colores en la UI
    risk_level      VARCHAR(10)     NOT NULL DEFAULT 'low',
    -- 'low'      → ver sus propias cosas (verde)
    -- 'medium'   → ver equipo, crear registros (azul)
    -- 'high'     → aprobar, cancelar, editar datos de otros (naranja)
    -- 'critical' → anular, exportar, configurar empresa, gestionar roles (rojo)

    -- Orden de visualización en la UI
    display_order   SMALLINT        NOT NULL DEFAULT 0,

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_permission_module CHECK (
        module IN ('hr', 'logistics', 'sales', 'finance', 'production', 'projects', 'system')
    ),
    CONSTRAINT chk_permission_risk CHECK (
        risk_level IN ('low', 'medium', 'high', 'critical')
    )
);

CREATE INDEX IF NOT EXISTS idx_perm_catalog_module   ON hr.permission_catalog (module);
CREATE INDEX IF NOT EXISTS idx_perm_catalog_resource ON hr.permission_catalog (module, resource);

COMMENT ON TABLE  hr.permission_catalog            IS 'Catálogo maestro de todos los permisos del sistema. Inmutable — solo Mantras añade permisos nuevos.';
COMMENT ON COLUMN hr.permission_catalog.permission IS 'Clave única: module.resource.action. Ej: hr.punches.cancel, sales.orders.approve';
COMMENT ON COLUMN hr.permission_catalog.risk_level IS 'low=verde | medium=azul | high=naranja | critical=rojo. Para UI del admin.';

-- ── 2. Insertar todos los permisos ────────────────────────────────────────────

INSERT INTO hr.permission_catalog (module, resource, action, permission, description, risk_level, display_order) VALUES

-- ══════════════════════════════════════════════════════════════
-- MÓDULO: HR
-- ══════════════════════════════════════════════════════════════

-- Fichajes (punches)
('hr', 'punches', 'view_own',           'hr.punches.view_own',           'Ver sus propios fichajes del día y historial',                     'low',      10),
('hr', 'punches', 'view_team',          'hr.punches.view_team',          'Ver fichajes de los miembros de su equipo',                         'medium',   11),
('hr', 'punches', 'view_all',           'hr.punches.view_all',           'Ver fichajes de todos los empleados de la empresa',                 'medium',   12),
('hr', 'punches', 'create',             'hr.punches.create',             'Registrar fichaje en nombre de un empleado (en tiempo real)',        'high',     13),
('hr', 'punches', 'create_retroactive', 'hr.punches.create_retroactive', 'Crear fichaje retroactivo en fechas pasadas',                       'high',     14),
('hr', 'punches', 'edit_time',          'hr.punches.edit_time',          'Modificar la hora de un fichaje existente',                         'high',     15),
('hr', 'punches', 'cancel',             'hr.punches.cancel',             'Cancelar un fichaje erróneo (queda en historial)',                   'high',     16),
('hr', 'punches', 'annul',              'hr.punches.annul',              'Anular un fichaje administrativamente (acción crítica)',             'critical', 17),
('hr', 'punches', 'export',             'hr.punches.export',             'Exportar fichajes a Excel/CSV',                                     'high',     18),

-- Ausencias (absences)
('hr', 'absences', 'view_own',          'hr.absences.view_own',          'Ver sus propias solicitudes de ausencia en todos los estados',       'low',      20),
('hr', 'absences', 'view_team',         'hr.absences.view_team',         'Ver ausencias de los miembros de su equipo',                         'medium',   21),
('hr', 'absences', 'view_all',          'hr.absences.view_all',          'Ver ausencias de todos los empleados de la empresa',                 'medium',   22),
('hr', 'absences', 'request',           'hr.absences.request',           'Solicitar una ausencia (parcial o día completo)',                    'low',      23),
('hr', 'absences', 'approve',           'hr.absences.approve',           'Aprobar solicitudes de ausencia de su equipo',                      'high',     24),
('hr', 'absences', 'reject',            'hr.absences.reject',            'Rechazar solicitudes de ausencia de su equipo',                     'high',     25),
('hr', 'absences', 'cancel',            'hr.absences.cancel',            'Cancelar una ausencia ya aprobada',                                 'high',     26),
('hr', 'absences', 'manage_all',        'hr.absences.manage_all',        'Gestionar ausencias de cualquier empleado sin restricción de equipo','critical', 27),
('hr', 'absences', 'export',            'hr.absences.export',            'Exportar ausencias a Excel/CSV',                                    'high',     28),

-- Empleados (employees)
('hr', 'employees', 'view_own',         'hr.employees.view_own',         'Ver su propio perfil de empleado',                                  'low',      30),
('hr', 'employees', 'view_team',        'hr.employees.view_team',        'Ver perfiles de los miembros de su equipo',                         'medium',   31),
('hr', 'employees', 'view_all',         'hr.employees.view_all',         'Ver perfiles de todos los empleados de la empresa',                 'medium',   32),
('hr', 'employees', 'create',           'hr.employees.create',           'Crear nuevos empleados en el sistema',                              'high',     33),
('hr', 'employees', 'edit',             'hr.employees.edit',             'Editar datos de empleados (cargo, departamento, etc.)',              'high',     34),
('hr', 'employees', 'edit_sensitive',   'hr.employees.edit_sensitive',   'Editar datos sensibles: salario, contrato, documentos',             'critical', 35),
('hr', 'employees', 'deactivate',       'hr.employees.deactivate',       'Dar de baja a un empleado',                                        'critical', 36),
('hr', 'employees', 'export',           'hr.employees.export',           'Exportar listado de empleados',                                    'high',     37),

-- Equipos (teams)
('hr', 'teams', 'view_own',             'hr.teams.view_own',             'Ver los equipos a los que pertenece',                               'low',      40),
('hr', 'teams', 'view_all',             'hr.teams.view_all',             'Ver todos los equipos de la empresa',                               'medium',   41),
('hr', 'teams', 'manage',               'hr.teams.manage',               'Crear, editar equipos y gestionar sus miembros',                    'high',     42),

-- Cuadrantes y horarios (schedules)
('hr', 'schedules', 'view_own',         'hr.schedules.view_own',         'Ver su propio cuadrante y horario asignado',                        'low',      50),
('hr', 'schedules', 'view_team',        'hr.schedules.view_team',        'Ver cuadrantes de su equipo',                                       'medium',   51),
('hr', 'schedules', 'view_all',         'hr.schedules.view_all',         'Ver todos los cuadrantes de la empresa',                            'medium',   52),
('hr', 'schedules', 'manage',           'hr.schedules.manage',           'Crear y editar cuadrantes y turnos',                                'high',     53),

-- Ubicaciones de trabajo (work_locations)
('hr', 'work_locations', 'view',        'hr.work_locations.view',        'Ver las ubicaciones de trabajo configuradas',                       'low',      60),
('hr', 'work_locations', 'manage',      'hr.work_locations.manage',      'Crear, editar y desactivar ubicaciones de trabajo',                 'high',     61),

-- Nóminas (payroll)
('hr', 'payroll', 'view_own',           'hr.payroll.view_own',           'Ver sus propias boletas de pago',                                   'low',      70),
('hr', 'payroll', 'view_team',          'hr.payroll.view_team',          'Ver nóminas de su equipo',                                          'high',     71),
('hr', 'payroll', 'view_all',           'hr.payroll.view_all',           'Ver nóminas de todos los empleados',                                'critical', 72),
('hr', 'payroll', 'manage',             'hr.payroll.manage',             'Calcular, aprobar y cerrar períodos de nómina',                     'critical', 73),
('hr', 'payroll', 'export',             'hr.payroll.export',             'Exportar nóminas a Excel/PDF',                                      'critical', 74),

-- Reportes HR (reports)
('hr', 'reports', 'view_team',          'hr.reports.view_team',          'Ver reportes de asistencia y ausencias de su equipo',               'medium',   80),
('hr', 'reports', 'view_all',           'hr.reports.view_all',           'Ver reportes de toda la empresa',                                   'high',     81),
('hr', 'reports', 'export',             'hr.reports.export',             'Exportar reportes a Excel/PDF',                                     'high',     82),

-- ══════════════════════════════════════════════════════════════
-- MÓDULO: LOGÍSTICA / WMS
-- ══════════════════════════════════════════════════════════════

('logistics', 'inventory', 'view',           'logistics.inventory.view',           'Ver stock e inventario',                                'low',      110),
('logistics', 'inventory', 'view_costs',     'logistics.inventory.view_costs',     'Ver costos de inventario (valor del stock)',             'high',     111),
('logistics', 'inventory', 'adjust',         'logistics.inventory.adjust',         'Realizar ajustes de inventario',                        'critical', 112),
('logistics', 'inventory', 'transfer',       'logistics.inventory.transfer',       'Transferir stock entre almacenes o ubicaciones',         'high',     113),
('logistics', 'inventory', 'export',         'logistics.inventory.export',         'Exportar reporte de inventario',                        'high',     114),

('logistics', 'purchase_orders', 'view',     'logistics.purchase_orders.view',     'Ver órdenes de compra',                                 'low',      120),
('logistics', 'purchase_orders', 'create',   'logistics.purchase_orders.create',   'Crear órdenes de compra',                               'medium',   121),
('logistics', 'purchase_orders', 'approve',  'logistics.purchase_orders.approve',  'Aprobar órdenes de compra',                             'high',     122),
('logistics', 'purchase_orders', 'receive',  'logistics.purchase_orders.receive',  'Recepcionar mercancía contra una OC',                   'medium',   123),
('logistics', 'purchase_orders', 'cancel',   'logistics.purchase_orders.cancel',   'Cancelar órdenes de compra',                            'high',     124),

('logistics', 'shipments', 'view',           'logistics.shipments.view',           'Ver envíos y despachos',                                'low',      130),
('logistics', 'shipments', 'create',         'logistics.shipments.create',         'Crear y despachar envíos',                              'medium',   131),
('logistics', 'shipments', 'manage',         'logistics.shipments.manage',         'Gestión completa de envíos (editar, cancelar)',          'high',     132),

('logistics', 'warehouses', 'view',          'logistics.warehouses.view',          'Ver almacenes y ubicaciones',                           'low',      140),
('logistics', 'warehouses', 'manage',        'logistics.warehouses.manage',        'Configurar almacenes, zonas y ubicaciones',              'critical', 141),

('logistics', 'reports', 'view',             'logistics.reports.view',             'Ver reportes de logística',                             'medium',   150),
('logistics', 'reports', 'export',           'logistics.reports.export',           'Exportar reportes de logística',                        'high',     151),

-- ══════════════════════════════════════════════════════════════
-- MÓDULO: VENTAS
-- ══════════════════════════════════════════════════════════════

('sales', 'customers', 'view',               'sales.customers.view',               'Ver clientes y su información',                         'low',      210),
('sales', 'customers', 'create',             'sales.customers.create',             'Crear nuevos clientes',                                 'medium',   211),
('sales', 'customers', 'edit',               'sales.customers.edit',               'Editar datos de clientes',                              'medium',   212),
('sales', 'customers', 'view_sensitive',     'sales.customers.view_sensitive',     'Ver datos sensibles: crédito, historial de deuda',       'high',     213),

('sales', 'quotes', 'view_own',              'sales.quotes.view_own',              'Ver sus propias cotizaciones',                          'low',      220),
('sales', 'quotes', 'view_all',              'sales.quotes.view_all',              'Ver todas las cotizaciones de la empresa',              'medium',   221),
('sales', 'quotes', 'create',               'sales.quotes.create',               'Crear cotizaciones',                                    'medium',   222),
('sales', 'quotes', 'approve_discount',     'sales.quotes.approve_discount',     'Aprobar descuentos en cotizaciones',                    'high',     223),

('sales', 'orders', 'view_own',              'sales.orders.view_own',              'Ver sus propias órdenes de venta',                      'low',      230),
('sales', 'orders', 'view_all',              'sales.orders.view_all',              'Ver todas las órdenes de venta',                        'medium',   231),
('sales', 'orders', 'create',               'sales.orders.create',               'Crear órdenes de venta',                                'medium',   232),
('sales', 'orders', 'approve',              'sales.orders.approve',              'Aprobar órdenes de venta',                              'high',     233),
('sales', 'orders', 'cancel',               'sales.orders.cancel',               'Cancelar órdenes de venta',                             'high',     234),

('sales', 'invoices', 'view_own',            'sales.invoices.view_own',            'Ver sus propias facturas',                              'low',      240),
('sales', 'invoices', 'view_all',            'sales.invoices.view_all',            'Ver todas las facturas',                                'medium',   241),
('sales', 'invoices', 'create',             'sales.invoices.create',             'Emitir facturas',                                       'high',     242),
('sales', 'invoices', 'cancel',             'sales.invoices.cancel',             'Anular facturas (acción crítica)',                       'critical', 243),

('sales', 'pos', 'operate',                  'sales.pos.operate',                  'Operar punto de venta (abrir caja, vender)',             'medium',   250),
('sales', 'pos', 'close',                    'sales.pos.close',                    'Cerrar caja y cuadrar POS',                             'high',     251),
('sales', 'pos', 'view_all_sessions',        'sales.pos.view_all_sessions',        'Ver sesiones de caja de todos los cajeros',             'high',     252),

('sales', 'reports', 'view_own',             'sales.reports.view_own',             'Ver sus propios reportes de ventas',                    'low',      260),
('sales', 'reports', 'view_all',             'sales.reports.view_all',             'Ver reportes de ventas de toda la empresa',             'high',     261),
('sales', 'reports', 'export',               'sales.reports.export',               'Exportar reportes de ventas',                           'high',     262),

-- ══════════════════════════════════════════════════════════════
-- MÓDULO: FINANZAS
-- ══════════════════════════════════════════════════════════════

('finance', 'journal_entries', 'view',       'finance.journal_entries.view',       'Ver asientos contables',                                'medium',   310),
('finance', 'journal_entries', 'create',     'finance.journal_entries.create',     'Crear asientos contables',                              'high',     311),
('finance', 'journal_entries', 'approve',    'finance.journal_entries.approve',    'Aprobar y confirmar asientos contables',                'critical', 312),

('finance', 'invoices', 'view',              'finance.invoices.view',              'Ver facturas de proveedores',                           'medium',   320),
('finance', 'invoices', 'create',            'finance.invoices.create',            'Registrar facturas de proveedores',                     'high',     321),
('finance', 'invoices', 'approve',           'finance.invoices.approve',           'Aprobar facturas de proveedores para pago',             'critical', 322),

('finance', 'payments', 'view',              'finance.payments.view',              'Ver pagos realizados a proveedores',                    'medium',   330),
('finance', 'payments', 'create',            'finance.payments.create',            'Registrar pagos a proveedores',                         'critical', 331),

('finance', 'budgets', 'view',               'finance.budgets.view',               'Ver presupuestos',                                      'medium',   340),
('finance', 'budgets', 'manage',             'finance.budgets.manage',             'Crear y editar presupuestos',                           'high',     341),
('finance', 'budgets', 'approve',            'finance.budgets.approve',            'Aprobar presupuestos',                                  'critical', 342),

('finance', 'fixed_assets', 'view',          'finance.fixed_assets.view',          'Ver activos fijos',                                     'medium',   350),
('finance', 'fixed_assets', 'manage',        'finance.fixed_assets.manage',        'Gestionar activos fijos y depreciaciones',              'high',     351),

('finance', 'periods', 'close',              'finance.periods.close',              'Cerrar períodos contables (acción irreversible)',        'critical', 360),

('finance', 'reports', 'view',               'finance.reports.view',               'Ver reportes financieros (P&L, balance, flujo)',        'high',     370),
('finance', 'reports', 'export',             'finance.reports.export',             'Exportar reportes financieros',                         'critical', 371),

-- ══════════════════════════════════════════════════════════════
-- MÓDULO: PRODUCCIÓN
-- ══════════════════════════════════════════════════════════════

('production', 'orders', 'view',             'production.orders.view',             'Ver órdenes de producción',                             'low',      410),
('production', 'orders', 'create',           'production.orders.create',           'Crear órdenes de producción',                           'medium',   411),
('production', 'orders', 'manage',           'production.orders.manage',           'Gestionar órdenes: iniciar, pausar, cerrar',            'high',     412),

('production', 'bom', 'view',                'production.bom.view',                'Ver listas de materiales (BOM)',                         'low',      420),
('production', 'bom', 'manage',              'production.bom.manage',              'Crear y editar listas de materiales',                    'high',     421),

('production', 'quality', 'view',            'production.quality.view',            'Ver controles de calidad',                              'low',      430),
('production', 'quality', 'manage',          'production.quality.manage',          'Registrar y gestionar controles de calidad',            'high',     431),

('production', 'reports', 'view',            'production.reports.view',            'Ver reportes de producción',                            'medium',   440),
('production', 'reports', 'export',          'production.reports.export',          'Exportar reportes de producción',                       'high',     441),

-- ══════════════════════════════════════════════════════════════
-- MÓDULO: PROYECTOS
-- ══════════════════════════════════════════════════════════════

('projects', 'projects', 'view_own',         'projects.projects.view_own',         'Ver proyectos en los que participa',                    'low',      510),
('projects', 'projects', 'view_all',         'projects.projects.view_all',         'Ver todos los proyectos de la empresa',                 'medium',   511),
('projects', 'projects', 'create',           'projects.projects.create',           'Crear nuevos proyectos',                                'medium',   512),
('projects', 'projects', 'manage',           'projects.projects.manage',           'Gestionar proyectos: fases, equipo, presupuesto',       'high',     513),
('projects', 'projects', 'close',            'projects.projects.close',            'Cerrar proyectos',                                      'high',     514),

('projects', 'tasks', 'view_own',            'projects.tasks.view_own',            'Ver sus propias tareas',                                'low',      520),
('projects', 'tasks', 'view_all',            'projects.tasks.view_all',            'Ver todas las tareas de un proyecto',                   'medium',   521),
('projects', 'tasks', 'manage',              'projects.tasks.manage',              'Crear, editar y asignar tareas',                        'medium',   522),

('projects', 'time_entries', 'view_own',     'projects.time_entries.view_own',     'Ver sus propios registros de horas',                    'low',      530),
('projects', 'time_entries', 'view_all',     'projects.time_entries.view_all',     'Ver horas de todos los miembros del proyecto',          'high',     531),
('projects', 'time_entries', 'manage',       'projects.time_entries.manage',       'Editar o eliminar registros de horas de otros',         'critical', 532),

('projects', 'reports', 'view',              'projects.reports.view',              'Ver reportes de avance y rentabilidad de proyectos',    'medium',   540),
('projects', 'reports', 'export',            'projects.reports.export',            'Exportar reportes de proyectos',                        'high',     541),

-- ══════════════════════════════════════════════════════════════
-- MÓDULO: SISTEMA (administración global)
-- ══════════════════════════════════════════════════════════════

('system', 'roles', 'view',                  'system.roles.view',                  'Ver roles y sus permisos',                              'medium',   610),
('system', 'roles', 'manage',                'system.roles.manage',                'Crear, editar roles y asignar permisos',                'critical', 611),
('system', 'roles', 'assign',                'system.roles.assign',                'Asignar roles a usuarios',                              'critical', 612),

('system', 'users', 'view',                  'system.users.view',                  'Ver usuarios del sistema',                              'medium',   620),
('system', 'users', 'manage',                'system.users.manage',                'Crear, editar y desactivar usuarios',                   'critical', 621),

('system', 'audit', 'view',                  'system.audit.view',                  'Ver el log de auditoría completo',                      'critical', 630),
('system', 'audit', 'export',                'system.audit.export',                'Exportar el log de auditoría',                          'critical', 631),

('system', 'company', 'settings',            'system.company.settings',            'Configurar parámetros de la empresa',                   'critical', 640),
('system', 'company', 'billing',             'system.company.billing',             'Ver y gestionar la facturación del plan Mantras',       'critical', 641),

('system', 'integrations', 'manage',         'system.integrations.manage',         'Configurar integraciones externas (Cognito, email...)', 'critical', 650),
('system', 'notifications', 'manage',        'system.notifications.manage',        'Configurar plantillas y canales de notificación',       'high',     651)

ON CONFLICT (permission) DO NOTHING;

-- ── 3. Refactorizar hr.role_permissions ───────────────────────────────────────
-- Añadir FK al catálogo manteniendo la columna permission como texto

ALTER TABLE hr.role_permissions
    ADD COLUMN IF NOT EXISTS permission_id BIGINT REFERENCES hr.permission_catalog(id);

-- Rellenar permission_id para registros existentes
UPDATE hr.role_permissions rp
SET permission_id = pc.id
FROM hr.permission_catalog pc
WHERE pc.permission = rp.permission
  AND rp.permission_id IS NULL;

COMMENT ON COLUMN hr.role_permissions.permission_id
    IS 'FK al catálogo de permisos. Garantiza que solo se asignan permisos válidos.';

-- ── 4. Re-insertar permisos de roles base apuntando al catálogo ───────────────

-- Limpiar permisos anteriores de roles de sistema para re-insertarlos correctamente
DELETE FROM hr.role_permissions
WHERE role_id IN (SELECT id FROM hr.roles WHERE is_system = TRUE)
  AND permission_id IS NULL;

-- Empleado base
INSERT INTO hr.role_permissions (role_id, permission, permission_id)
SELECT r.id, pc.permission, pc.id
FROM hr.roles r
CROSS JOIN hr.permission_catalog pc
WHERE r.name = 'Empleado' AND r.is_system = TRUE
  AND pc.permission IN (
    'hr.punches.view_own',
    'hr.absences.view_own',
    'hr.absences.request',
    'hr.employees.view_own',
    'hr.teams.view_own',
    'hr.schedules.view_own',
    'hr.payroll.view_own'
  )
ON CONFLICT (role_id, permission) DO UPDATE SET permission_id = EXCLUDED.permission_id;

-- Jefe de equipo
INSERT INTO hr.role_permissions (role_id, permission, permission_id)
SELECT r.id, pc.permission, pc.id
FROM hr.roles r
CROSS JOIN hr.permission_catalog pc
WHERE r.name = 'Jefe de equipo' AND r.is_system = TRUE
  AND pc.permission IN (
    'hr.punches.view_own',
    'hr.punches.view_team',
    'hr.absences.view_own',
    'hr.absences.view_team',
    'hr.absences.request',
    'hr.employees.view_own',
    'hr.employees.view_team',
    'hr.teams.view_own',
    'hr.teams.view_all',
    'hr.schedules.view_own',
    'hr.schedules.view_team',
    'hr.payroll.view_own',
    'hr.reports.view_team'
  )
ON CONFLICT (role_id, permission) DO UPDATE SET permission_id = EXCLUDED.permission_id;

-- Supervisor
INSERT INTO hr.role_permissions (role_id, permission, permission_id)
SELECT r.id, pc.permission, pc.id
FROM hr.roles r
CROSS JOIN hr.permission_catalog pc
WHERE r.name = 'Supervisor' AND r.is_system = TRUE
  AND pc.permission IN (
    'hr.punches.view_own',
    'hr.punches.view_team',
    'hr.punches.cancel',
    'hr.absences.view_own',
    'hr.absences.view_team',
    'hr.absences.request',
    'hr.absences.approve',
    'hr.absences.reject',
    'hr.employees.view_own',
    'hr.employees.view_team',
    'hr.employees.view_all',
    'hr.teams.view_own',
    'hr.teams.view_all',
    'hr.schedules.view_own',
    'hr.schedules.view_team',
    'hr.schedules.view_all',
    'hr.payroll.view_own',
    'hr.reports.view_team'
  )
ON CONFLICT (role_id, permission) DO UPDATE SET permission_id = EXCLUDED.permission_id;

-- RRHH
INSERT INTO hr.role_permissions (role_id, permission, permission_id)
SELECT r.id, pc.permission, pc.id
FROM hr.roles r
CROSS JOIN hr.permission_catalog pc
WHERE r.name = 'RRHH' AND r.is_system = TRUE
  AND pc.permission IN (
    'hr.punches.view_own',
    'hr.punches.view_team',
    'hr.punches.view_all',
    'hr.punches.create',
    'hr.punches.create_retroactive',
    'hr.punches.edit_time',
    'hr.punches.cancel',
    'hr.punches.annul',
    'hr.punches.export',
    'hr.absences.view_own',
    'hr.absences.view_team',
    'hr.absences.view_all',
    'hr.absences.request',
    'hr.absences.approve',
    'hr.absences.reject',
    'hr.absences.cancel',
    'hr.absences.manage_all',
    'hr.absences.export',
    'hr.employees.view_own',
    'hr.employees.view_team',
    'hr.employees.view_all',
    'hr.employees.create',
    'hr.employees.edit',
    'hr.employees.export',
    'hr.teams.view_own',
    'hr.teams.view_all',
    'hr.teams.manage',
    'hr.schedules.view_own',
    'hr.schedules.view_team',
    'hr.schedules.view_all',
    'hr.schedules.manage',
    'hr.work_locations.view',
    'hr.work_locations.manage',
    'hr.payroll.view_own',
    'hr.payroll.view_team',
    'hr.reports.view_team',
    'hr.reports.view_all',
    'hr.reports.export'
  )
ON CONFLICT (role_id, permission) DO UPDATE SET permission_id = EXCLUDED.permission_id;

-- Solo lectura
INSERT INTO hr.role_permissions (role_id, permission, permission_id)
SELECT r.id, pc.permission, pc.id
FROM hr.roles r
CROSS JOIN hr.permission_catalog pc
WHERE r.name = 'Solo lectura' AND r.is_system = TRUE
  AND pc.permission IN (
    'hr.punches.view_own',
    'hr.absences.view_own',
    'hr.employees.view_own',
    'hr.employees.view_all',
    'hr.teams.view_own',
    'hr.teams.view_all',
    'hr.schedules.view_own',
    'hr.payroll.view_own',
    'hr.reports.view_all'
  )
ON CONFLICT (role_id, permission) DO UPDATE SET permission_id = EXCLUDED.permission_id;

-- Administrador: todos los permisos
INSERT INTO hr.role_permissions (role_id, permission, permission_id)
SELECT r.id, pc.permission, pc.id
FROM hr.roles r
CROSS JOIN hr.permission_catalog pc
WHERE r.name = 'Administrador' AND r.is_system = TRUE
  AND pc.is_active = TRUE
ON CONFLICT (role_id, permission) DO UPDATE SET permission_id = EXCLUDED.permission_id;

COMMIT;
