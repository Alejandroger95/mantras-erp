# Mantras ERP — Contexto del Proyecto

## Qué es esto
ERP multi-tenant construido desde cero. Stack principal: Fastify 5 + TypeScript (API) y Next.js 15 App Router (frontend). Base de datos: PostgreSQL con esquema propio `hr.*`, `sales.*`, `logistics.*`, `finance.*`, `production.*`, `services.*`, `projects.*`, `surveys.*`.

## Estructura de carpetas
```
~/Proyectos/ERP/
├── mantras-api/          ← API REST (Fastify 5 + TypeScript + postgres.js)
│   ├── src/
│   │   ├── app.ts        ← buildApp(), registra todos los módulos
│   │   ├── core/
│   │   │   ├── db.ts     ← pool postgres.js (BIGINT→Number, snake→camelCase)
│   │   │   ├── config.ts ← env vars
│   │   │   └── errors.ts ← AppError, ZodError handler, errorHandler global
│   │   └── modules/
│   │       ├── auth/     ← POST /api/v1/auth/login, GET /api/v1/auth/me
│   │       ├── hr/       ← employees, punches, schedules, absences
│   │       ├── dashboard/← today + monthly KPIs
│   │       ├── catalog/  ← servicios del salón
│   │       └── appointments/
│   ├── docker-compose.yml← API en Docker, conecta a PostgreSQL LOCAL del Mac
│   └── .env              ← DATABASE_URL, JWT_SECRET, PORT=3000
│
├── mantras-web/          ← Frontend Next.js 15 (puerto 3001)
│   ├── src/
│   │   ├── app/
│   │   │   ├── login/    ← página de login
│   │   │   ├── dashboard/
│   │   │   └── rrhh/
│   │   │       ├── empleados/   ← lista de empleados
│   │   │       ├── cuadrantes/  ← horarios + turnos (hr.schedules + hr.shifts)
│   │   │       ├── fichajes/    ← time tracking con state machine + ausencias parciales
│   │   │       └── vacaciones/  ← ausencias aprobadas (full_day)
│   │   ├── lib/
│   │   │   ├── api.ts    ← axios con interceptor JWT
│   │   │   └── auth.tsx  ← AuthProvider (token en localStorage)
│   │   └── components/
│   │       └── Sidebar.tsx
│   └── .env.local        ← NEXT_PUBLIC_API_URL=http://localhost:3000
│
└── docs/
    └── hr/sql/           ← todos los SQLs del schema HR
        ├── run_hr.sh     ← ejecuta todos los SQLs en orden
        ├── seed_schedules.sql
        ├── migrate_absences_partial.sql   ← extiende hr.absences para parciales
        └── migrate_employee_hierarchy.sql ← añade reports_to + historial de jerarquía
```

## Cómo correr el proyecto

### Iniciar
```bash
# 1. API (Docker)
cd ~/Proyectos/ERP/mantras-api
docker compose up -d          # levanta API en :3000

# 2. Frontend (en otra terminal)
cd ~/Proyectos/ERP/mantras-web
npm run dev                   # corre en :3001
```

### Parar
```bash
# Detener API
cd ~/Proyectos/ERP/mantras-api
docker compose down

# Detener frontend → Ctrl+C en la terminal donde corre npm run dev
```

### Comandos útiles de API
```bash
docker compose restart api                        # recargar después de editar src/
docker logs mantras-api-api-1 --tail 50          # ver logs
```

### Migraciones pendientes (correr en orden)
```bash
psql -U postgres -d mantrasdb -f ~/Proyectos/ERP/docs/hr/sql/migrate_absences_partial.sql
psql -U postgres -d mantrasdb -f ~/Proyectos/ERP/docs/hr/sql/migrate_employee_hierarchy.sql
psql -U postgres -d mantrasdb -f ~/Proyectos/ERP/docs/hr/sql/migrate_time_punches_v2.sql
psql -U postgres -d mantrasdb -f ~/Proyectos/ERP/docs/hr/sql/migrate_rbac.sql
psql -U postgres -d mantrasdb -f ~/Proyectos/ERP/docs/hr/sql/migrate_permission_catalog.sql
psql -U postgres -d mantrasdb -f ~/Proyectos/ERP/docs/hr/sql/migrate_teams.sql
psql -U postgres -d mantrasdb -f ~/Proyectos/ERP/docs/hr/sql/migrate_notifications.sql
```

## Flujo de trabajo — siempre al terminar una sesión

### 1. Git commit + push
El sandbox de Claude no tiene credenciales de GitHub. Siempre correr desde la terminal del Mac:
```bash
cd ~/Proyectos/ERP
rm -f .git/HEAD.lock .git/index.lock   # si hay lock de sesión anterior
git add -A
git commit -m "descripción del cambio"
git push
```

### 2. Actualizar grafos Graphify → Obsidian
Doble clic en `update_graphify.command`, o desde terminal:
```bash
cd ~/Proyectos/ERP && bash update_graphify.command
```
- El script corre `graphify .` respetando `.graphifyignore` (excluye node_modules, venv, docs de módulos sin construir)
- Exporta los nodos a `graphify-out/obsidian/` que es el vault de Obsidian
- El vault de Obsidian apunta a `~/Proyectos/ERP/graphify-out/obsidian/`
- Después de correr el script, cerrar y reabrir Obsidian para que recargue el índice

## Auth de desarrollo
- Login: `admin@mantras.pe` / password = valor de `cognito_user_id` en la tabla `hr.system_users`
- JWT contiene: `{ userId, companyId, email, role }`
- En producción se usará AWS Cognito JWT; en dev se compara directamente con `cognito_user_id`

## Decisiones técnicas importantes

### BIGINT → string bug (RESUELTO)
postgres.js devuelve BIGINT/BIGSERIAL como string en algunos contextos. Fix en `db.ts`:
```typescript
types: { bigint: { to: 20, from: [20], serialize: x => x.toString(), parse: x => Number(x) } }
```
Y en rutas que reciben IDs: usar `z.coerce.number()` en vez de `z.number()`.

### Docker + Mac (hot-reload no funciona)
Los eventos de filesystem no se propagan de Mac → Docker. Después de editar `src/`, siempre hacer `docker compose restart api`.

### Multi-tenancy
Cada query recibe `companyId` desde `req.user.companyId` (extraído del JWT). NUNCA hacer queries sin filtrar por `company_id`.

### Schema HR — columnas reales (no inventadas)
- `hr.persons`: tiene `personal_phone`, NO `phone`
- `hr.system_users`: tiene `cognito_user_id`, NO `password_hash`
- `hr.schedules`: tiene `weekly_hours`, NO `total_hours_per_week`. Los días/horas están en `hr.shifts` (tabla separada)
- `hr.time_punches`: columna `punched_at` (no `punch_time`)
- `hr.companies`: tiene `trade_name` y `country`, NO `legal_name` ni `country_code`
- `hr.employees`: tiene `reports_to` (jefe actual, BIGINT FK a hr.employees)
- `hr.absences`: tiene `absence_scope` ('partial' | 'full_day'), `start_time`, `end_time`, `duration_minutes`, `requested_by`, `reviewed_by`, `reviewed_at`
- `hr.absence_types`: tiene `applies_to` ('partial' | 'full_day' | 'both')
- `hr.work_locations`: zonas de trabajo con geofence (`latitude`, `longitude`, `radius_meters`)
- `hr.time_punches`: tiene `punch_status` ('active' | 'cancelled' | 'annulled'), `cancelled_by`, `cancelled_at`, `cancel_reason`, `original_punched_at`, `modified_by`, `modified_at`, `original_punch_id`, `ip_address`, `location_id` (FK → work_locations), `location_match_distance_m`

### Tipos de fichaje (state machine)
Columna `punch_type` en `hr.time_punches` es VARCHAR(20).

Estados y transiciones:
```
not_started → check_in      → [working]
[working]   → break_start   → [on_break]   → break_end   → [working]
[working]   → absence_start → [on_absence] → absence_end → [working]
[working]   → check_out     → [finished]
```

Desde `working` hay 3 acciones disponibles simultáneamente (almuerzo, ausencia, salida).
`absence_start` y `absence_end` aceptan `punchedAt` opcional (ISO con offset) para registrar con hora personalizada.

Queries de estado solo leen `WHERE punch_status = 'active'`. Los cancelados/anulados se conservan para auditoría.

Función geofencing: `SELECT * FROM hr.match_work_location(company_id, lat, lon)` — devuelve la work_location dentro del radio más pequeño, o NULL si ninguna coincide.

### Ausencias — dos scopes en una misma tabla (hr.absences)
- **partial**: ausencia dentro de la jornada (1-2h). Tiene `start_time`, `end_time`, `duration_minutes`. `start_date = end_date`.
- **full_day**: ausencia de día(s) completo(s) (vacaciones, baja, etc.). `start_time` y `end_time` son NULL.

Flujo de aprobación: `pending → approved | rejected | cancelled`
- `requested_by` = quien creó la solicitud
- `reviewed_by` = quien aprobó o rechazó (referencia a hr.employees, no a hr.system_users)
- Para saber quién era el jefe cuando se revisó una ausencia, consultar `hr.employee_reporting_history` por fecha.

### Jerarquía de empleados
- `hr.employees.reports_to` → jefe actual (conveniencia, para queries rápidas)
- `hr.employee_reporting_history` → historial completo con `effective_from` / `effective_to`
  - `effective_to IS NULL` = relación vigente actualmente
  - Unique index garantiza solo un registro vigente por empleado
- Para cambiar jefe usar la función: `SELECT hr.set_employee_manager(employee_id, new_manager_id, 'motivo', created_by_id)`

### Query útil: jefe de un empleado en una fecha concreta
```sql
SELECT r.reports_to, p.first_name || ' ' || p.last_name AS manager_name
FROM hr.employee_reporting_history r
JOIN hr.employees e ON e.id = r.reports_to
JOIN hr.persons p ON p.id = e.person_id
WHERE r.employee_id = :employee_id
  AND r.effective_from <= :fecha
  AND (r.effective_to IS NULL OR r.effective_to >= :fecha)
```

## Módulos frontend completados
- ✅ Login
- ✅ Dashboard (stub)
- ✅ RRHH: Empleados (lista), Cuadrantes, Vacaciones
- ✅ Fichajes: state machine completa + ausencias parciales con categoría, horas y motivo
- ⏳ Pendiente: detalle de empleado, nóminas, conectar cuadrante→fichaje

## Roles y permisos (RBAC)

Modelo de permisos dinámico — roles configurables por empresa:

- `hr.roles` → catálogo de roles por empresa (`base_level`: admin bypasea todo; employee depende de permisos)
- `hr.role_permissions` → permisos asignados a cada rol (strings `modulo.accion`)
- `hr.system_users.role_id` → FK al rol asignado

Roles base creados automáticamente por empresa: Administrador, Supervisor, Jefe de equipo, Empleado, RRHH, Solo lectura.

Permisos definidos en `hr.permission_catalog` — formato `module.resource.action`:
```
hr.punches.*        view_own | view_team | view_all | create | create_retroactive | edit_time | cancel | annul | export
hr.absences.*       view_own | view_team | view_all | request | approve | reject | cancel | manage_all | export
hr.employees.*      view_own | view_team | view_all | create | edit | edit_sensitive | deactivate | export
hr.teams.*          view_own | view_all | manage
hr.schedules.*      view_own | view_team | view_all | manage
hr.work_locations.* view | manage
hr.payroll.*        view_own | view_team | view_all | manage | export
hr.reports.*        view_team | view_all | export
logistics.*         inventory | purchase_orders | shipments | warehouses | reports
sales.*             customers | quotes | orders | invoices | pos | reports
finance.*           journal_entries | invoices | payments | budgets | fixed_assets | periods | reports
production.*        orders | bom | quality | reports
projects.*          projects | tasks | time_entries | reports
system.*            roles | users | audit | company | integrations | notifications
```

`risk_level`: `low` (verde) | `medium` (azul) | `high` (naranja) | `critical` (rojo) — para la UI del admin.
El Administrador recibe todos los permisos del catálogo automáticamente.

Regla de aprobación de ausencias: siempre va al `reports_to` del empleado (responsable directo), independiente del rol en el sistema.

## Equipos de trabajo (hr.teams)

Tres conceptos separados y distintos:
- `hr.employees.reports_to` → jerarquía de aprobación (quién aprueba ausencias/permisos)
- `hr.teams` + `hr.team_members` → agrupación operativa del día a día (Equipo Ventas Norte, Turno Mañana)
- `projects.project_members` → equipo de un proyecto concreto

`hr.teams`: catálogo de equipos con `team_type` (operational | shift | functional), `leader_id` (conveniencia, puede ser NULL).
`hr.team_members`: historial completo de asignaciones — `joined_at` / `left_at` (NULL = activo). Nunca se borran filas.
- Un empleado puede estar en **múltiples equipos simultáneamente** (sin restricción).
- Un empleado puede ser líder en un equipo y miembro en otros.
- Un equipo puede existir **sin líder** temporalmente.
- Membresía activa = `left_at IS NULL AND is_cancelled = FALSE`.
- `is_cancelled` / `cancel_reason` / `cancelled_by` / `cancelled_at` → cancelar asignaciones por error sin borrar historial.
- Unique index: **solo un líder activo por equipo** (`WHERE role = 'leader' AND left_at IS NULL AND is_cancelled = FALSE`).
- `hr.assign_team_member(team_id, employee_id, role, reason, created_by, joined_at)` → cierra membresía previa en ESE equipo, desplaza líder actual si role='leader'.
- `hr.remove_team_member(team_id, employee_id, reason, created_by)` → saca empleado del equipo. El equipo puede quedar sin líder.
- `hr.cancel_team_member(member_id, cancel_reason, cancelled_by)` → cancela asignación por error, audit trail completo.

## Notificaciones in-app (hr.notifications)

- `hr.notifications` → una fila por notificación, por destinatario. Campos: `recipient_id`, `sender_id` (NULL = sistema), `type`, `entity_type` + `entity_id` (deep-link), `title`, `body`, `is_read`, `read_at`.
- `hr.notification_preferences` → preferencias por empleado y tipo. Canal `in_app` activo ahora; `email` y `push` para el futuro.
- Las notificaciones se generan desde la API al ocurrir el evento (no hay cron ni cola).
- Tipos definidos: `absence_requested` | `absence_approved` | `absence_rejected` | `absence_cancelled` | `punch_cancelled` | `punch_annulled` | `punch_created_retro` | `punch_time_edited`

## Pendiente (próxima sesión)
1. Correr migraciones pendientes (ver arriba)
2. API + frontend para ausencias parciales con categorías y flujo de aprobación
3. Vista manager: aprobar/rechazar ausencias de su equipo
4. Página detalle empleado (`/rrhh/empleados/[id]`)
5. Módulo nóminas
6. Módulo Agenda (servicios del salón)
7. Frontend notificaciones: campana + badge de no leídas + lista
