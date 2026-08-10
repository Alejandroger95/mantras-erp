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
| `employees` | Employment period: links person + company. Each rehire = new record with same `person_id`. Has `reports_to` (FK to self) for current direct manager. |
| `employee_reporting_history` | Full manager-history per employee. Each row = one period (`effective_from`/`effective_to`). `effective_to IS NULL` = currently active. Use `hr.set_employee_manager()` to change manager. |
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
| `absence_types` | Catalog with `applies_to`: `'partial'` (within shift), `'full_day'` (whole days), or `'both'`. |
| `absences` | **Single table for all absence types.** `absence_scope` column separates partial (1–2h during shift, with `start_time`/`end_time`) from full-day (vacation, sick leave, etc.). Approval flow: `pending → approved / rejected / cancelled`. Fields: `requested_by`, `reviewed_by`, `reviewed_at`. |

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

**Punch state machine (time_punches.punch_type):**
```
not_started → check_in      → [working]
[working]   → break_start   → [on_break]    → break_end   → [working]
[working]   → absence_start → [on_absence]  → absence_end → [working]
[working]   → check_out     → [finished]
```
From `working`, all three actions (break, absence, check-out) are optional and available simultaneously. `absence_start`/`absence_end` accept an optional `punchedAt` (ISO with offset) for retroactive registration.

**absences (single table, two scopes):** Rather than separate tables, one `hr.absences` table with `absence_scope = 'partial' | 'full_day'`. Partial absences have `start_time`/`end_time`/`duration_minutes`; full-day absences leave those NULL. CHECK constraints enforce consistency. This simplifies reporting (total time-off per employee = sum of both scopes).

**employee_reporting_history:** `hr.employees.reports_to` holds the current manager for fast queries. `hr.employee_reporting_history` holds the full period-based history. A unique partial index ensures only one active record per employee (`effective_to IS NULL`). Always use `hr.set_employee_manager()` to change managers — it closes the previous period and opens a new one atomically.

**work_reductions:** Dedicated table (not just a contract field) because reductions have their own legal basis, approval flow, start/end dates, and salary impact that must be tracked independently.

**documents (polymorphic):** One table serves all entities via `entity_type` + `entity_id`. Avoids dozens of duplicate document tables across modules.

---

## Conventions

- `id BIGSERIAL PRIMARY KEY` on all tables.
- `created_at TIMESTAMPTZ`, `updated_at TIMESTAMPTZ` on all tables (auto-updated via trigger `hr.set_updated_at()`).
- Soft delete: `is_active BOOLEAN DEFAULT TRUE`.
- Boolean columns prefixed with `is_` (e.g. `is_active`, `is_primary`, `is_current`).
- Foreign keys: `ON DELETE RESTRICT` by default.
- Schema prefix: `hr.` on all objects.
- SQL comments written in Spanish.
- Multi-tenant: every query must filter by `company_id`.

---

## SQL Execution Order

```
01_companies.sql
02_geography.sql              -- countries, states, cities
03_departments.sql
04_positions.sql
05_persons.sql                -- identity (no document fields)
05b_person_documents.sql      -- document history per person
06_employees.sql              -- includes reports_to (current manager)
07_contract_types.sql
08_contracts.sql
08b_work_reductions.sql       -- temporary hour reductions
09_schedules_shifts.sql
10_holidays.sql
10b_time_punches.sql          -- raw clock events (includes absence_start/end types)
11_attendance.sql
12_absence_types.sql          -- includes applies_to (partial|full_day|both)
13_absences.sql               -- unified partial + full_day via absence_scope
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

## Migrations (applied on existing DB)

```bash
# Extend hr.absences for partial absences + add absence categories
psql -U postgres -d mantrasdb -f docs/hr/sql/migrate_absences_partial.sql

# Add reports_to to hr.employees + create hr.employee_reporting_history
psql -U postgres -d mantrasdb -f docs/hr/sql/migrate_employee_hierarchy.sql
```

## Running the full schema from scratch

```bash
# First time
bash docs/hr/sql/run_hr.sh

# Reset and recreate from scratch
bash docs/hr/sql/run_hr.sh --reset
```
