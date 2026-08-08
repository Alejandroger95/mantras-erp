# Mantras ERP 🐶

> Named after Mantras, a very good dog.

A modular, multi-tenant ERP system built on PostgreSQL — designed to work for any type of business, starting with Latin American companies.

**Goal:** a powerful, affordable alternative to SAP for small and mid-sized businesses in Peru and Latin America.

---

## Modules

| Module | Status |
|--------|--------|
| HR (Human Resources) | ✅ Complete |
| Logistics | 🔜 Planned |
| Sales | 🔜 Planned |
| Finance | 🔜 Planned |
| Production | 🔜 Planned |
| Projects | 🔜 Planned |
| Configuration | 🔜 Planned |

---

## HR Module

Full human resources schema with 26 tables covering:

- Multi-company architecture
- Persons & employees (supports rehires)
- Document history (NIE→DNI changes, renewals)
- All contract types + work reductions (paternity, maternity, medical)
- Schedules, shifts, holidays, time punches & attendance
- Full payroll (concepts, periods, line-by-line details)
- Equipment & asset management
- Access code rotation (pindi, t7, etc.)
- Disciplinary actions, performance reviews, trainings
- Universal document repository (polymorphic)

📖 See [`docs/hr/schema.md`](docs/hr/schema.md) for the full schema in English.  
📖 Ver [`docs/hr/schema_es.md`](docs/hr/schema_es.md) para el esquema completo en español.

---

## Tech Stack

- **Database:** PostgreSQL
- **Schema:** `hr` (more to come)
- **Database name:** `mantrasdb`
- **Architecture:** Multi-tenant (company-scoped)

---

## Running the HR schema

```bash
# First time
bash docs/hr/sql/run_hr.sh

# Reset and recreate from scratch
bash docs/hr/sql/run_hr.sh --reset
```

Requirements: PostgreSQL running locally, `psql` in PATH, database `mantrasdb` created.

---

## Project structure

```
docs/
  hr/
    sql/          ← 26 SQL files + run script
    schema.md     ← English documentation
    schema_es.md  ← Spanish documentation
  logistics/      ← coming soon
  sales/          ← coming soon
  finance/        ← coming soon
```

---

*Built with ❤️ in Peru.*
