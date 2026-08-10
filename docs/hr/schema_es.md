# Módulo HR (Recursos Humanos) — Esquema de Base de Datos

**Base de datos:** `mantrasdb` *(en honor a Mantras 🐶)*  
**Motor:** PostgreSQL  
**Esquema:** `hr`  
**Arquitectura:** Multi-empresa

---

## ¿Cómo están organizadas las tablas?

```
Capa 1 — Estructura de la empresa
  companies → countries / states / cities → departments → positions

Capa 2 — La persona y su empleo
  persons ★ → person_documents → employees → contract_types → contracts → work_reductions

Capa 3 — Tiempo, asistencia y festivos
  schedules → shifts → holidays → time_punches → attendance → absence_types → absences

Capa 4 — Nómina
  payroll_concepts → payroll_periods → payroll_details

Capa 5 — Equipos y activos
  equipment_types → equipment → equipment_assignments

Capa 6 — Claves y accesos
  access_systems → access_codes → code_assignments

Capa 7 — Disciplina y desarrollo
  disciplinary_actions → performance_reviews → trainings / training_participants

Capa 8 — Documentos (aplica a todo)
  document_categories → documents
```

> **Tareas de ingreso/salida** (crear correo, asignar accesos, entregar equipos)
> van en el **Módulo de Workflows**, separado de HR.

---

## Tablas explicadas

### Capa 1 — Estructura de la empresa

| Tabla | Qué guarda |
|-------|-----------|
| `companies` | La empresa raíz. Todo en el sistema pertenece a una empresa. |
| `countries` | Países con código ISO, moneda y código telefónico. |
| `states` | Estados o provincias por país. |
| `cities` | Ciudades por estado. |
| `departments` | Departamentos o áreas. Soporta jerarquía: departamentos dentro de departamentos. |
| `positions` | Puestos o cargos con nivel jerárquico, banda salarial y a quién le reporta. |

### Capa 2 — La persona y su empleo

| Tabla | Qué guarda |
|-------|-----------|
| `persons` ★ | **La identidad real.** Nombre, contacto, dirección. Sin campos de documento — eso va en `person_documents`. |
| `person_documents` | **Historial de documentos de identidad.** Cuando alguien cambia de NIE a DNI, el NIE queda como histórico y el DNI queda activo (`is_primary=TRUE`). También registra renovaciones, pérdidas y cambios de nombre. |
| `employees` | **El período de trabajo.** Liga a la persona con la empresa. Si alguien renuncia y regresa, se crea un nuevo registro aquí pero apuntando al mismo `person_id`. Tiene `reports_to` (FK a sí misma) con el jefe directo actual. |
| `employee_reporting_history` | **Historial de jerarquía.** Cada fila es un período en el que un empleado reportaba a un jefe (`effective_from` / `effective_to`). `effective_to IS NULL` = vigente hoy. Función helper: `hr.set_employee_manager()`. |
| `teams` | **Equipos operativos de trabajo.** Separado de `reports_to` (aprobaciones) y de `project_members` (proyectos). Tipos: `operational`, `shift`, `functional`. Tiene `leader_id` como conveniencia. |
| `team_members` | **Historial de asignaciones a equipos.** `joined_at` / `left_at` (NULL = activo hoy). Nunca se borran filas. Un empleado puede estar en múltiples equipos a la vez. Unique index: solo un líder activo por equipo. `is_cancelled` para errores sin perder historial. Funciones: `hr.assign_team_member()`, `hr.remove_team_member()`, `hr.cancel_team_member()`. |
| `contract_types` | Tipos de contrato: planilla fija, por horas, por proyecto, honorarios. |
| `contracts` | El contrato: qué empleado, qué puesto, qué tipo, con qué sueldo y desde cuándo. Historial completo. |
| `work_reductions` | **Reducción de jornada temporal.** Paternidad, maternidad, médica, cuidado familiar. Guarda las horas originales, las reducidas, el porcentaje calculado automáticamente, si el salario baja proporcionalmente y el respaldo legal (artículo de ley). |

**Ejemplo de documentos con cambio NIE → DNI:**
```
persons → Juan García (id=5)
  person_documents: NIE X1234567A  España  2018→2023  is_primary=FALSE (histórico)
  person_documents: DNI 12345678Z  España  2023→hoy   is_primary=TRUE  (activo)
```

**Ejemplo de reducción de jornada por paternidad:**
```
work_reductions → Juan García (employee_id=47)
  reason: paternity
  original: 40h/sem  →  reduced: 20h/sem  →  50% reduction
  salary_adjusted: TRUE  →  adjusted_salary: 1000 (era 2000)
  start_date: 2025-03-01  end_date: 2025-09-01
```

### Capa 3 — Tiempo, asistencia y festivos

| Tabla | Qué guarda |
|-------|-----------|
| `schedules` | Horarios de trabajo (matutino, vespertino, nocturno, etc.). |
| `shifts` | Turnos por día dentro de un horario (lunes 8am-4pm, etc.). |
| `holiday_types` | Tipos de festivo: nacional, regional, de empresa, puente. |
| `holidays` | Días festivos. Si `company_id` está vacío aplica a todo el país. Soporta recurrencia anual y pago doble. |
| `work_locations` | **Zonas de trabajo con geofence.** Cada ubicación tiene `latitude`, `longitude` y `radius_meters`. Cuando el empleado ficha dentro del radio, se asocia automáticamente via `hr.match_work_location()`. |
| `time_punches` | **Los fichajes.** Eventos individuales con estado (`punch_status`: `active` / `cancelled` / `annulled`). Incluye auditoría completa: quién canceló, quién editó la hora, si corrige otro punch (`original_punch_id`), IP, geolocalización y ubicación reconocida por geofencing. |
| `attendance` | **Resumen diario de asistencia.** Calculado desde los fichajes: hora de entrada, salida, horas trabajadas, horas extra, estado del día. |
| `absence_types` | Tipos de ausencia con campo `applies_to`: `'partial'` (solo dentro de jornada), `'full_day'` (días completos) o `'both'`. |
| `absences` | **Una sola tabla para todos los tipos de ausencia.** Columna `absence_scope` distingue entre parciales (1-2h dentro de jornada, con `start_time`/`end_time`) y de día(s) completo(s) (vacaciones, baja, etc.). Flujo de aprobación: `pending → approved / rejected / cancelled`. |

**Columnas clave de `hr.absences`:**
```
absence_scope     'partial' | 'full_day'
start_date        fecha de inicio (= end_date para parciales)
end_date          fecha de fin
start_time        solo parciales: hora inicio  (NULL en full_day)
end_time          solo parciales: hora fin     (NULL en full_day)
duration_minutes  solo parciales: minutos calculados
status            pending | approved | rejected | cancelled
requested_by      FK hr.employees — quién creó la solicitud
reviewed_by       FK hr.employees — quién aprobó/rechazó
reviewed_at       timestamp de la revisión
```

**Ejemplo de fichajes en un día (state machine completa):**
```
08:01  check_in       → estado: working
10:00  absence_start  → estado: on_absence  (ausencia parcial registrada con hora custom)
11:00  absence_end    → estado: working
14:00  break_start    → estado: on_break    (almuerzo, opcional)
14:30  break_end      → estado: working
17:03  check_out      → estado: finished
→ attendance: horas trabajadas descontando ausencia y almuerzo
```

**Transiciones válidas de fichaje (`punch_type`):**
```
not_started → check_in      → [working]
[working]   → break_start   → [on_break]    → break_end   → [working]
[working]   → absence_start → [on_absence]  → absence_end → [working]
[working]   → check_out     → [finished]
```
Desde `working` las tres acciones (almuerzo, ausencia, salida) son opcionales y simultáneas.
`absence_start` y `absence_end` aceptan `punchedAt` personalizado (ISO con offset).

**Estados de un fichaje (`punch_status`):**
```
active    = fichaje válido y vigente (única que cuentan para attendance)
cancelled = error del empleado; cancelado por él mismo o por manager/admin
annulled  = anulado administrativamente por admin/manager
```

**Flujo de corrección de fichaje erróneo:**
```
1. Empleado ficha mal → punch_status = 'active'
2. Admin crea nuevo punch correcto → original_punch_id apunta al erróneo
3. Admin cancela el erróneo       → punch_status = 'cancelled', cancel_reason
4. Todas las queries filtran      → WHERE punch_status = 'active'
```

**Fichaje retroactivo por admin:**
```
source = 'admin_created', recorded_by = admin_id
punched_at = fecha/hora que corresponde (puede ser ayer o antes)
notes = 'Empleado olvidó fichar entrada del 2026-08-09'
```

**Edición de hora por admin:**
```
original_punched_at = hora original (backup)
punched_at          = hora corregida
modified_by         = admin_id
modified_at         = NOW()
```

**Geofencing (`hr.match_work_location`):**
```sql
-- La API llama esto al registrar un fichaje con coordenadas:
SELECT * FROM hr.match_work_location(company_id, latitude, longitude);
-- Devuelve: location_id, location_name, distance_m
-- NULL si el punto está fuera de todas las zonas definidas
```

### Capa 4 — Nómina

| Tabla | Qué guarda |
|-------|-----------|
| `payroll_concepts` | Catálogo de todo lo que puede aparecer en una nómina: salario base, bono, horas extra, deducciones, IMSS, ISR, etc. |
| `payroll_periods` | Los períodos de pago: semanal, quincenal o mensual. |
| `payroll_details` | El detalle línea por línea de cada nómina por empleado y período. |

### Capa 5 — Equipos y activos

| Tabla | Qué guarda |
|-------|-----------|
| `equipment_types` | Tipos: laptop, celular, tablet, vehículo, herramienta, etc. |
| `equipment` | Inventario con número de serie, estado, valor, garantía y código de activo fijo. |
| `equipment_assignments` | Historial de asignaciones: quién, cuándo, en qué condición se entregó y se devolvió. |

### Capa 6 — Claves y accesos

| Tabla | Qué guarda |
|-------|-----------|
| `access_systems` | Sistemas que dan claves: Telefónica, VPN, SAP, Active Directory. Con política de rotación. |
| `access_codes` | Los códigos asignables: "pindi", "t7", "usr_045". Reutilizables. |
| `code_assignments` | Historial de quién tuvo qué código y cuándo. Al rotar, el registro anterior se cierra y se crea uno nuevo. |

### Capa 7 — Disciplina y desarrollo

| Tabla | Qué guarda |
|-------|-----------|
| `disciplinary_actions` | Amonestaciones formales: gravedad, motivo, si el empleado firmó, si apeló, si genera descuento en nómina. |
| `performance_reviews` | Evaluaciones de desempeño periódicas con calificación y comentarios. |
| `trainings` | Capacitaciones: nombre, proveedor, fechas, modalidad (presencial/online/híbrida) y costo. |
| `training_participants` | Quién participó en cada capacitación, si aprobó, calificación y certificado. |

### Capa 8 — Documentos (aplica a todas las demás tablas)

| Tabla | Qué guarda |
|-------|-----------|
| `document_categories` | Tipos de documento: contrato, certificado médico, amonestación, identificación, finiquito, etc. |
| `documents` | Repositorio central. Cualquier entidad puede tener varios documentos con versionado. Se ubica con `entity_type` + `entity_id`. |

---

## Reglas generales

- Todas las tablas tienen `id` (BIGSERIAL), `created_at` y `updated_at` (TIMESTAMPTZ, auto-actualizado por trigger).
- Ningún registro se elimina físicamente: `is_active = FALSE` lo desactiva.
- Los campos booleanos empiezan con `is_` (ej: `is_active`, `is_primary`).
- El esquema se llama `hr` y todas las tablas viven dentro de él.
- Comentarios en el SQL escritos en español.
- Multi-tenant: toda query filtra por `company_id`.

## Jerarquía de empleados

`hr.employees.reports_to` → jefe actual (conveniencia, para queries rápidas).
`hr.employee_reporting_history` → historial completo de cambios de jefe con `effective_from`/`effective_to`.

Para cambiar el jefe de un empleado, usar siempre la función helper (nunca actualizar `reports_to` directo):
```sql
SELECT hr.set_employee_manager(
  employee_id,      -- subordinado
  new_manager_id,   -- nuevo jefe (NULL = sin jefe)
  'reorganización', -- motivo
  created_by_id     -- quién hace el cambio
);
```

Para saber quién era el jefe en una fecha concreta:
```sql
SELECT r.reports_to, p.first_name || ' ' || p.last_name AS manager_name
FROM hr.employee_reporting_history r
JOIN hr.employees e ON e.id = r.reports_to
JOIN hr.persons   p ON p.id = e.person_id
WHERE r.employee_id  = :employee_id
  AND r.effective_from <= :fecha
  AND (r.effective_to IS NULL OR r.effective_to >= :fecha);
```

---

## Orden de creación de tablas

```
01_companies.sql
02_geography.sql             ← países, estados, ciudades
03_departments.sql
04_positions.sql
05_persons.sql               ← identidad (sin campos de documento)
05b_person_documents.sql     ← historial de documentos
06_employees.sql             ← incluye reports_to (jefe actual)
07_contract_types.sql
08_contracts.sql
08b_work_reductions.sql      ← reducciones de jornada
09_schedules_shifts.sql
10_holidays.sql
10b_time_punches.sql         ← fichajes brutos (punch_type incluye absence_start/end)
11_attendance.sql
12_absence_types.sql         ← incluye applies_to (partial|full_day|both)
13_absences.sql              ← unifica parciales y días completos (absence_scope)
14_payroll_concepts.sql
15_payroll_periods.sql
16_payroll_details.sql
17_equipment_types.sql
18_equipment.sql
19_equipment_assignments.sql
20_access_systems.sql
21_access_codes.sql
22_code_assignments.sql
23_disciplinary_actions.sql
24_performance_reviews.sql
25_trainings.sql
26_documents.sql             ← siempre al final
```

## Migraciones aplicadas sobre BD existente

```bash
# Extender hr.absences para ausencias parciales + categorías
psql -U postgres -d mantrasdb -f docs/hr/sql/migrate_absences_partial.sql

# Añadir reports_to a hr.employees + tabla hr.employee_reporting_history
psql -U postgres -d mantrasdb -f docs/hr/sql/migrate_employee_hierarchy.sql

# work_locations (geofencing) + mejoras a time_punches (estados, auditoría, IP)
psql -U postgres -d mantrasdb -f docs/hr/sql/migrate_time_punches_v2.sql

# RBAC — roles y permisos dinámicos
psql -U postgres -d mantrasdb -f docs/hr/sql/migrate_rbac.sql

# Equipos operativos con historial de asignaciones
psql -U postgres -d mantrasdb -f docs/hr/sql/migrate_teams.sql
```

## Cómo correr todo desde cero

```bash
# Primera vez
bash docs/hr/sql/run_hr.sh

# Si ya existe algo y quieres empezar de cero
bash docs/hr/sql/run_hr.sh --reset
```
