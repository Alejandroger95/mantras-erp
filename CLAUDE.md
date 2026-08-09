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
│   │   │       ├── fichajes/    ← time tracking con state machine
│   │   │       └── vacaciones/  ← ausencias aprobadas
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
        └── seed_schedules.sql ← datos de prueba para hr.schedules + hr.shifts
```

## Cómo correr el proyecto
```bash
# API (Docker)
cd ~/Proyectos/ERP/mantras-api
docker compose up -d          # levanta API en :3000
docker compose restart api    # recarga cuando editas src/ (hot-reload Mac+Docker no es confiable)
docker logs mantras-api-api-1 --tail 50  # ver logs

# Frontend
cd ~/Proyectos/ERP/mantras-web
npm run dev                   # corre en :3001

# Seed de cuadrantes (solo una vez)
psql -U postgres -d mantrasdb -f ~/Proyectos/ERP/docs/hr/sql/seed_schedules.sql
```

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

### Tipos de fichaje (state machine)
`null → check_in → break_start → break_end → check_out`
Columna `punch_type` en `hr.time_punches` es VARCHAR(20).

## Módulos frontend completados
- ✅ Login
- ✅ Dashboard (stub)
- ✅ RRHH: Empleados (lista), Cuadrantes, Fichajes (funcional), Vacaciones
- ⏳ Pendiente: detalle de empleado, nóminas, conectar cuadrante→fichaje

## Pendiente (próxima sesión)
1. Correr seed: `psql -U postgres -d mantrasdb -f docs/hr/sql/seed_schedules.sql`
2. Página detalle empleado (`/rrhh/empleados/[id]`)
3. Módulo nóminas
4. Validar cuadrante asignado al hacer fichaje
5. Módulo Agenda (servicios del salón)
