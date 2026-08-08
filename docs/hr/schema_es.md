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
| `employees` | **El período de trabajo.** Liga a la persona con la empresa. Si alguien renuncia y regresa, se crea un nuevo registro aquí pero apuntando al mismo `person_id`. |
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
| `time_punches` | **Los fichajes.** Eventos individuales de entrada/salida tal como llegan del dispositivo: biométrico, app, NFC, QR o manual. Cada punch tiene tipo (`check_in`, `break_start`, etc.), origen y opcionalmente geolocalización. Son los datos brutos que alimentan `attendance`. |
| `attendance` | **Resumen diario de asistencia.** Calculado desde los fichajes: hora de entrada, salida, horas trabajadas, horas extra, estado del día. |
| `absence_types` | Tipos de ausencia: vacaciones, enfermedad, permiso con/sin goce, maternidad, etc. |
| `absences` | Ausencias con fechas, motivo y flujo de aprobación. |

**Ejemplo de fichajes en un día:**
```
08:01  check_in     (biometric)
10:00  break_start  (mobile_app)
10:15  break_end    (mobile_app)
14:00  break_start  (mobile_app)
14:30  break_end    (mobile_app)
17:03  check_out    (biometric)
→ attendance: 8.45h trabajadas, 0.45h descanso
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

- Todas las tablas tienen `id` (número único), `created_at` y `updated_at`.
- Ningún registro se elimina físicamente: `is_active = FALSE` lo desactiva.
- Los campos booleanos empiezan con `is_` (ej: `is_active`, `is_primary`).
- El esquema se llama `hr` y todas las tablas viven dentro de él.
- Comentarios en el SQL escritos en español.

---

## Orden de creación de tablas

```
01_companies.sql
02_geography.sql             ← países, estados, ciudades
03_departments.sql
04_positions.sql
05_persons.sql               ← identidad (sin campos de documento)
05b_person_documents.sql     ← historial de documentos
06_employees.sql
07_contract_types.sql
08_contracts.sql
08b_work_reductions.sql      ← reducciones de jornada
09_schedules_shifts.sql
10_holidays.sql
10b_time_punches.sql         ← fichajes brutos
11_attendance.sql
12_absence_types.sql
13_absences.sql
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

## Cómo correr todo desde la terminal (sin copy-paste)

```bash
# Primera vez
bash docs/hr/sql/run_hr.sh

# Si ya existe algo y quieres empezar de cero
bash docs/hr/sql/run_hr.sh --reset
```
