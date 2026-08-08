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
  persons ★ → person_documents → employees → contract_types → contracts → work_reductions

Layer 3 — Time, Attendance & Holidays
  schedules → shifts → holidays → time_punches → attendance → absence_types → absences

Layer 4 — Payroll
  payroll_concepts → payroll_periods → payroll_details

Layer 5 — Equipment & Assets
  equipment_types → equipment → equipment_assignments

Layer 6 — Access Codes
  access_systems → access_codes → code_assignments

Layer 7 — Discipline & Development
  disciplinary_actions → performance_reviews → trainings / training_participants

Layer 8 — Documents (transversal)
  document_categories → documents
```

> **Onboarding/Offboarding tasks** (create email, assign access codes, deliver equipment)
> belong to the **Workflows Module**, separate from HR.

---

## Tables

### Layer 1 — Organizational Structure

| Table | Description |
|-------|-------------|
| `companies` | Root tenant. Every entity in the ERP belongs to a company. |
| `countries` | Country catalog (ISO 3166) with currency and phone code. |
| `states` | States / provinces per country. |
| `cities` | Cities per state. |
| `departments` | Organizational units. Supports parent hierarchy via `parent_id`. |
| `positions` | Job positions with hierarchy level, salary band, and reporting line. |

### Layer 2 — Identity & Employment

| Table | Description |
|-------|-------------|
| `persons` ★ | Permanent identity. Name, contact, address. No document data here. |
| `person_documents` | Full document history per person. Supports NIE→DNI changes, renewals, and losses. `is_primary=TRUE` marks the current active document. |
| `employees` | Employment period: links person + company. Each rehire = new record with same `person_id`. |
| `contract_types` | Catalog: fixed salary, hourly, project-based, freelance. |
| `contracts` | Formal employment contract with position, type, salary, and hours. Full history. |
| `work_reductions` | Temporary work-hour reductions: paternity, maternity, medical, personal. Tracks original vs. reduced hours, reduction %, and salary impact. |

### Layer 3 — Time, Attendance & Holidays

| Table | Description |
|-------|-------------|
| `schedules` | Work schedule definitions (morning, night, etc.). |
| `shifts` | Daily time blocks within a schedule (Mon 9am–6pm, etc.). |
| `holiday_types` | Catalog: national, regional, company, bridge. |
| `holidays` | Public and company holidays. `company_id` NULL = national. Supports annual recurrence and double pay. |
| `time_punches` | Raw clock-in/out events (fichajes) from any source: biometric, app, NFC, QR, manual. Feed into attendance after processing. |
| `attendance` | Daily attendance summary per employee: check-in, check-out, worked hours, status. |
| `absence_types` | Catalog: vacation, sick leave, unpaid leave, maternity, etc. |
| `absences` | Absence requests with approval flow. |

### Layer 4 — Payroll

| Table | Description |
|-------|-------------|
| `payroll_concepts` | Catalog of earnings, deductions, and employer contributions. |
| `payroll_periods` | Pay periods (weekly / biweekly / monthly) per company. |
| `payroll_details` | Line-by-line payroll: what was paid/deducted per employee per period. |

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
| `access_codes` | The actual codes (pindi, t7, usr_045). Reusable. |
| `code_assignments` | Assignment history with validity dates and next rotation date. |

### Layer 7 — Discipline & Development

| Table | Description |
|-------|-------------|
| `disciplinary_actions` | Formal disciplinary records: severity, reason, signature, appeal, payroll deduction. |
| `performance_reviews` | Periodic employee performance evaluations. |
| `trainings` | Courses, dates, modality, cost. |
| `training_participants` | Per-employee result for each training: status, score, certificate. |

### Layer 8 — Documents (transversal)

| Table | Description |
|-------|-------------|
| `document_categories` | Catalog: employment contract, medical cert, disciplinary notice, ID, etc. |
| `documents` | Universal repository. Polymorphic via `entity_type` + `entity_id`. Supports versioning. |

---

## Key Design Decisions

**persons vs employees:** `persons` holds the immutable identity. `employees` holds the employment period. One person can have multiple employee records (rehires) without any data duplication.

**person_documents:** Separated from `persons` to support document changes (NIE→DNI, renewals, losses) with full audit history. `is_primary=TRUE` marks the active document.

**time_punches vs attendance:** `time_punches` stores raw clock events from any device. `attendance` is the computed daily summary. The system processes punches → generates attendance records.

**work_reductions:** Dedicated table (not just a contract field) because reductions have their own legal basis, approval flow, start/end dates, and salary impact that must be tracked independently.

**documents (polymorphic):** One table serves all entities via `entity_type` + `entity_id`. Avoids dozens of duplicate document tables across modules.

---

## Conventions

- `id BIGSERIAL PRIMARY KEY` on all tables.
- `created_at`, `updated_at` on all tables (auto-updated via trigger).
- Soft delete: `is_active BOOLEAN DEFAULT TRUE`.
- Boolean columns prefixed with `is_` (e.g. `is_active`, `is_primary`, `is_current`).
- Foreign keys: `ON DELETE RESTRICT` by default.
- Schema prefix: `hr.` on all objects.
- SQL comments written in Spanish.

---

## SQL Execution Order

```
01_companies.sql
02_geography.sql              -- countries, states, cities
03_departments.sql
04_positions.sql
05_persons.sql                -- identity (no document fields)
05b_person_documents.sql      -- document history per person
06_employees.sql
07_contract_types.sql
08_contracts.sql
08b_work_reductions.sql       -- temporary hour reductions
09_schedules_shifts.sql
10_holidays.sql
10b_time_punches.sql          -- raw clock-in/out events
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

## Running the full schema

```bash
# First time
bash docs/hr/sql/run_hr.sh

# Reset and recreate from scratch
bash docs/hr/sql/run_hr.sh --reset
```
