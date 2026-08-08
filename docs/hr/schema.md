# HR Module — Database Schema

**Database:** `mantrasdb` *(named after Mantras 🐶)*  
**Engine:** PostgreSQL  
**Schema:** `hr`  
**Architecture:** Multi-company (multi-tenant)

---

## Layer Overview

```
Layer 1 — Organizational Structure
  companies → countries / states / cities → departments → positions

Layer 2 — Identity & Employment
  persons ★ → employees → contract_types → contracts

Layer 3 — Time, Attendance & Holidays
  schedules → shifts → holidays → attendance → absence_types → absences

Layer 4 — Payroll
  payroll_concepts → payroll_periods → payroll_details

Layer 5 — Equipment & Assets
  equipment_types → equipment → equipment_assignments

Layer 6 — Access Codes
  access_systems → access_codes → code_assignments

Layer 7 — Discipline & Development
  disciplinary_actions → performance_reviews → trainings

Layer 8 — Documents (transversal)
  document_categories → documents
  (linked to: employees, contracts, absences, disciplinary_actions,
   equipment_assignments, performance_reviews)
```

> **Note — Onboarding/Offboarding:** Operational tasks triggered by employee
> entry/exit (create corporate email, assign access codes, deliver equipment)
> belong to the **Workflows Module**, separate from HR. That module references
> `employees`, `code_assignments`, and `equipment_assignments`.

---

## Tables by Layer

### Layer 1 — Organizational Structure

| Table | Description |
|-------|-------------|
| `companies` | Root tenant. Every entity in the ERP belongs to a company. |
| `countries` | Country catalog (ISO 3166). |
| `states` | States / provinces per country. |
| `cities` | Cities per state. |
| `departments` | Organizational units within a company. Supports parent hierarchy. |
| `positions` | Job positions with hierarchy level and salary band. |

### Layer 2 — Identity & Employment

| Table | Description |
|-------|-------------|
| `persons` ★ | Permanent, immutable identity. One person can have multiple employment periods (hired → resigned → rehired) always referencing the same `person_id`. |
| `employees` | Employment relationship: links person + company + period. Each rehire is a new record with the same `person_id`. |
| `contract_types` | Catalog: fixed salary, hourly, project-based, freelance/fees. |
| `contracts` | Links employee + position + type + economic conditions. Full history. |

### Layer 3 — Time, Attendance & Holidays

| Table | Description |
|-------|-------------|
| `schedules` | Work schedule definitions. |
| `shifts` | Specific time blocks within a schedule. |
| `holiday_types` | Catalog: national, regional, company, bridge. |
| `holidays` | Public and company holidays. `company_id` NULL = national. Supports annual recurrence and double pay. |
| `attendance` | Daily check-in / check-out records per employee. |
| `absence_types` | Catalog: vacation, sick leave, unpaid leave, etc. |
| `absences` | Absence requests and records. |

### Layer 4 — Payroll

| Table | Description |
|-------|-------------|
| `payroll_concepts` | Catalog of earnings, deductions, and contributions. |
| `payroll_periods` | Pay periods (weekly / biweekly / monthly) per company. |
| `payroll_details` | Payroll lines: what was paid/deducted per employee per period. |

### Layer 5 — Equipment & Assets

| Table | Description |
|-------|-------------|
| `equipment_types` | Catalog: laptop, phone, tablet, vehicle, tool, etc. |
| `equipment` | Inventory with serial number, status, value, and warranty. |
| `equipment_assignments` | Assignment history with delivery/return condition and signed receipts. |

### Layer 6 — Access Codes

| Table | Description |
|-------|-------------|
| `access_systems` | Catalog of platforms (Telefónica, VPN, SAP…) with rotation policy. |
| `access_codes` | The actual codes (pindi, t7, usr_045). Reusable across employees. |
| `code_assignments` | Assignment history with validity dates and next rotation date. |

### Layer 7 — Discipline & Development

| Table | Description |
|-------|-------------|
| `disciplinary_actions` | Formal disciplinary records: severity, reason, signature, appeal, payroll deduction. |
| `performance_reviews` | Periodic employee performance evaluations. |
| `trainings` | Courses, dates, participants, and results. |

### Layer 8 — Documents (transversal)

| Table | Description |
|-------|-------------|
| `document_categories` | Catalog: employment contract, medical certificate, disciplinary notice, ID, etc. |
| `documents` | Universal repository. Any entity can have N documents with full versioning. Polymorphic via `entity_type` + `entity_id`. |

---

## Key Relationships

```
persons ★
  └── employees (person_id)  ← misma persona, múltiples períodos de empleo

companies
  ├── departments, positions, employees
  ├── holidays, payroll_concepts, payroll_periods
  ├── equipment, access_systems

employees
  ├── contracts (position, contract_type, department)
  ├── attendance, absences
  ├── payroll_details
  ├── equipment_assignments, code_assignments
  ├── disciplinary_actions, performance_reviews, trainings

documents → (polymorphic)
  ├── employee, contract, absence
  ├── disciplinary_action, equipment_assignment
  └── performance_review, training
```

---

## Conventions

- All tables use `id BIGSERIAL PRIMARY KEY`.
- Timestamps: `created_at`, `updated_at` on every table.
- Soft delete: `is_active BOOLEAN DEFAULT TRUE` (no physical DELETE).
- Foreign keys use `ON DELETE RESTRICT` by default.
- Schema prefix: `hr.` on all objects.
- Boolean columns prefixed with `is_` (e.g. `is_active`, `is_current`).
- Comments on tables and columns are written in Spanish.

---

## SQL Execution Order

```
01_companies.sql
02_geography.sql              -- countries, states, cities
03_departments.sql
04_positions.sql
05_persons.sql                -- identity (must run before employees)
06_employees.sql
07_contract_types.sql
08_contracts.sql
09_schedules_shifts.sql
10_holidays.sql               -- holiday_types + holidays
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
26_documents.sql              -- transversal, always last
```
