# Módulo HR (Recursos Humanos) — Esquema de Base de Datos

**Base de datos:** `mantrasdb` *(en honor a Mantras 🐶)*  
**Motor:** PostgreSQL  
**Esquema:** `hr`  
**Arquitectura:** Multi-empresa (varias empresas en una sola base de datos)

---

## ¿Cómo están organizadas las tablas?

Las tablas están agrupadas en capas. Cada capa depende de la anterior, por eso el orden de creación importa.

```
Capa 1 — Estructura de la empresa
  companies → countries / states / cities → departments → positions

Capa 2 — La persona y su empleo
  persons ★ → employees → contract_types → contracts

Capa 3 — Tiempo, asistencia y festivos
  schedules → shifts → holidays → attendance → absence_types → absences

Capa 4 — Nómina
  payroll_concepts → payroll_periods → payroll_details

Capa 5 — Equipos y activos
  equipment_types → equipment → equipment_assignments

Capa 6 — Claves y accesos
  access_systems → access_codes → code_assignments

Capa 7 — Disciplina y desarrollo
  disciplinary_actions → performance_reviews → trainings

Capa 8 — Documentos (aplica a todo)
  document_categories → documents
```

> **Nota — Tareas de ingreso/salida:** Cuando alguien entra o sale de la empresa,
> hay tareas operativas como crear correo, asignar accesos o entregar equipos.
> Esas tareas van en el **Módulo de Workflows**, separado de RRHH. Ese módulo
> se conecta con `employees`, `code_assignments` y `equipment_assignments`.

---

## Tablas explicadas

### Capa 1 — Estructura de la empresa

| Tabla (en inglés) | Qué guarda |
|-------------------|-----------|
| `companies` | La empresa raíz. Todo en el sistema pertenece a una empresa. Como el "dueño" de todos los datos. |
| `countries` | Catálogo de países. |
| `states` | Estados o provincias de cada país. |
| `cities` | Ciudades de cada estado. |
| `departments` | Áreas o departamentos dentro de la empresa (Ventas, TI, Finanzas…). Soporta departamentos dentro de otros departamentos. |
| `positions` | Los puestos o cargos: Gerente, Analista, Técnico, etc. Incluye nivel jerárquico y banda de sueldo. |

### Capa 2 — La persona y su empleo

| Tabla (en inglés) | Qué guarda |
|-------------------|-----------|
| `persons` ★ | **La identidad real de la persona.** Nombre, documento, fecha de nacimiento. Esta tabla nunca cambia aunque la persona renuncie y regrese. Es el ancla permanente. |
| `employees` | **El período de trabajo.** Liga a la persona con la empresa y guarda las fechas de ingreso y baja. Si alguien renuncia y regresa, se crea un nuevo registro aquí pero apuntando al mismo `person_id`. |
| `contract_types` | Catálogo de tipos de contrato: planilla fija, por horas, por proyecto, honorarios/freelance. |
| `contracts` | El contrato en sí: qué empleado, qué puesto, qué tipo de contrato, con qué sueldo y desde cuándo. Guarda el historial completo. |

**Ejemplo de reingresos con `persons` y `employees`:**
```
persons → Juan Pérez (id=5, siempre el mismo)
  employees id=12 → ingresó 2020, se fue 2022
  employees id=47 → regresó 2024, activo hoy
```

### Capa 3 — Tiempo, asistencia y festivos

| Tabla (en inglés) | Qué guarda |
|-------------------|-----------|
| `schedules` | Los horarios de trabajo definidos (horario matutino, vespertino, etc.). |
| `shifts` | Los turnos específicos dentro de un horario (lunes 8am-4pm, etc.). |
| `holiday_types` | Tipos de festivo: nacional, regional, de la empresa, puente. |
| `holidays` | Los días festivos. Si `company_id` está vacío, aplica a todo el país. Permite indicar si es un festivo que se repite cada año y si se paga doble cuando se trabaja. |
| `attendance` | El registro de entrada y salida de cada empleado cada día. |
| `absence_types` | Tipos de ausencia: vacaciones, enfermedad, permiso con o sin goce, etc. |
| `absences` | Las ausencias de cada empleado: fecha, tipo, si fue aprobada, etc. |

### Capa 4 — Nómina

| Tabla (en inglés) | Qué guarda |
|-------------------|-----------|
| `payroll_concepts` | Catálogo de todo lo que puede aparecer en una nómina: salario base, bono, horas extra, deducciones, IMSS, ISR, etc. |
| `payroll_periods` | Los períodos de pago: semanales, quincenales o mensuales por empresa. |
| `payroll_details` | El detalle línea por línea de cada nómina: cuánto ganó o se le descontó a cada empleado en cada período. |

### Capa 5 — Equipos y activos

| Tabla (en inglés) | Qué guarda |
|-------------------|-----------|
| `equipment_types` | Tipos de equipo: laptop, teléfono celular, tablet, vehículo, herramienta, etc. |
| `equipment` | El inventario de equipos: número de serie, marca, modelo, estado (disponible, asignado, en reparación), valor y garantía. |
| `equipment_assignments` | Historial de a quién se le asignó cada equipo, en qué estado se entregó, cuándo se devolvió y en qué estado quedó. Guarda las actas firmadas. |

### Capa 6 — Claves y accesos

| Tabla (en inglés) | Qué guarda |
|-------------------|-----------|
| `access_systems` | Los sistemas que dan claves a los empleados: Telefónica, VPN, SAP, Active Directory, etc. Incluye la política de rotación (cada cuánto se cambia la clave). |
| `access_codes` | Los códigos en sí: "pindi", "t7", "usr_045". Son reutilizables y se pueden reasignar. |
| `code_assignments` | Historial de quién tuvo qué código y cuándo. Cuando se rota la clave, el registro anterior se cierra y se crea uno nuevo. |

### Capa 7 — Disciplina y desarrollo

| Tabla (en inglés) | Qué guarda |
|-------------------|-----------|
| `disciplinary_actions` | Las amonestaciones formales: gravedad (leve/grave/crítica), motivo, si el empleado la firmó, si apeló, y si genera descuento en nómina. Los documentos PDF van en `documents`. |
| `performance_reviews` | Las evaluaciones de desempeño periódicas de cada empleado. |
| `trainings` | Capacitaciones: cursos, fechas, quiénes participaron y los resultados. |

### Capa 8 — Documentos (aplica a todas las demás tablas)

| Tabla (en inglés) | Qué guarda |
|-------------------|-----------|
| `document_categories` | Catálogo de tipos de documento: contrato, certificado médico, amonestación, identificación, etc. |
| `documents` | El repositorio central de todos los archivos. Cualquier entidad del sistema puede tener varios documentos. Guarda la URL del archivo (en S3, Google Cloud, etc.) y soporta versiones: si se sube una nueva versión, la anterior queda como historial. |

**¿Cómo funciona la relación polimórfica de `documents`?**

En vez de tener una tabla de documentos por cada módulo, hay una sola tabla con dos campos clave:
- `entity_type`: dice a qué tipo de registro pertenece el documento
- `entity_id`: dice el número de ese registro específico

```
entity_type = 'employee'            → CV, INE, CURP del empleado 7
entity_type = 'contract'            → Contrato firmado del contrato 45
entity_type = 'absence'             → Certificado médico de la ausencia 12
entity_type = 'disciplinary_action' → Acta de amonestación 3
entity_type = 'equipment_assignment'→ Acta de entrega del equipo 8
```

---

## Reglas generales del sistema

- Todas las tablas tienen un campo `id` que es el número único de cada registro.
- Todas tienen `created_at` (cuándo se creó) y `updated_at` (cuándo se modificó por última vez).
- Ningún registro se elimina físicamente. En su lugar existe `is_active`: cuando vale `FALSE`, el registro está "desactivado" pero sigue en la base de datos para mantener el historial.
- El esquema se llama `hr` (Human Resources) y todas las tablas viven dentro de él.
- Los comentarios en el código SQL están escritos en español.

---

## Orden en que se deben crear las tablas en la base de datos

```
01_companies.sql            ← primero siempre la empresa
02_geography.sql            ← países, estados, ciudades
03_departments.sql          ← departamentos
04_positions.sql            ← puestos
05_persons.sql              ← la identidad de la persona (antes que employees)
06_employees.sql            ← el período de empleo
07_contract_types.sql       ← tipos de contrato
08_contracts.sql            ← los contratos
09_schedules_shifts.sql     ← horarios y turnos
10_holidays.sql             ← festivos
11_attendance.sql           ← asistencia
12_absence_types.sql        ← tipos de ausencia
13_absences.sql             ← ausencias
14_payroll_concepts.sql     ← conceptos de nómina
15_payroll_periods.sql      ← períodos de pago
16_payroll_details.sql      ← detalle de nómina
17_equipment_types.sql      ← tipos de equipo
18_equipment.sql            ← inventario de equipos
19_equipment_assignments.sql← asignación de equipos
20_access_systems.sql       ← sistemas de claves
21_access_codes.sql         ← los códigos (pindi, t7…)
22_code_assignments.sql     ← asignación de códigos
23_disciplinary_actions.sql ← amonestaciones
24_performance_reviews.sql  ← evaluaciones
25_trainings.sql            ← capacitaciones
26_documents.sql            ← documentos (siempre al final)
```
