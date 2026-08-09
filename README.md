# Mantras ERP 🐶

> Named after Mantras, a very good dog.

A modular, multi-tenant ERP system built on PostgreSQL — designed to work for any type of business, starting with Latin American companies.

**Goal:** a powerful, affordable alternative to SAP for small and mid-sized businesses in Peru and Latin America.

---

## Modules

| Module | Tables | Status |
|--------|--------|--------|
| HR (Human Resources) | 40 | ✅ Complete |
| Logistics / WMS | 92 | ✅ Complete |
| Sales | 71 | ✅ Complete |
| Finance | 50 | ✅ Complete |
| Production | 60 | ✅ Complete |
| Services | 19 | ✅ Complete |
| Projects | 10 | ✅ Complete |
| MRP / Planning | — | 🔜 Planned |
| CRM | — | 🔜 Planned |
| Payroll Engine | — | 🔜 Planned |

**Total: 342 tables across 7 schemas**

---

## HR Module

Full human resources schema with 38 tables covering:

- Multi-company architecture
- Persons & employees (supports rehires)
- Document history (NIE→DNI changes, renewals)
- All contract types + work reductions (paternity, maternity, medical)
- Schedules, shifts, holidays, time punches & attendance
- Full payroll (concepts, periods, line-by-line details)
- Equipment & asset management
- Access code rotation
- Disciplinary actions, performance reviews, trainings
- Universal document repository (polymorphic)
- System users, sessions & audit log

📖 See [`docs/hr/schema.md`](docs/hr/schema.md) for the full schema in English.  
📖 Ver [`docs/hr/schema_es.md`](docs/hr/schema_es.md) para el esquema completo en español.

---

## Logistics / WMS Module

Full warehouse management system with 92 tables covering the complete inbound → storage → outbound cycle:

- Multi-warehouse, multi-zone, multi-location (aisle-rack-level-position)
- Products, variants, barcodes, kits (physical & virtual)
- Lot tracking (FEFO/FIFO/LIFO), serial numbers, LPN containers
- Inbound: purchase orders, receipts, quality inspection, putaway rules
- Inventory ledger (immutable, signed quantities — source of truth)
- Wave picking: templates → waves → allocations → pick tasks
- Outbound: orders (B2B & B2C), pack tasks, shipments, routes, delivery proof
- Transfers & replenishment between zones and warehouses
- AMR/AGV robots: task queue, performance, battery management
- **Differentiators:** 🇵🇪 SUNAT GRE · 💬 WhatsApp/Push notifications · 📸 Photo verification · 🌿 Carbon footprint · 🌡️ IoT sensors

📖 Ver [`docs/logistics/schema_logistics_es.md`](docs/logistics/schema_logistics_es.md) para el esquema completo en español.

---

## Sales Module

Full sales cycle with 69 tables covering:

- Customers, addresses, contacts, credit limits
- Price lists, price scales, customer special prices
- Quotations (with versioning), sales orders, delivery schedules
- Invoicing (boleta/factura), credit notes, debit notes
- Collections, payment allocations, installment plans
- Sales reps, commissions, loyalty program
- Promotions: BOGO, bundles, % discount, rebates retroactivos
- POS: stores, terminals, sessions, transactions
- Returns & warranty (RMA, inspection, disposition)
- **Differentiators:** 🇵🇪 SUNAT e-invoicing · 💳 Multi-currency payments · 🎁 Rebate agreements · 📦 Cancellation reasons + anulación flow

---

## Finance Module

Full accounting and financial management with 50 tables covering:

- Chart of accounts: PCGE (Peru) + PGC (Spain) — multi-country
- Journal entries (double-entry) + General Ledger / Trial Balance views
- Accounts Payable: supplier invoices, payments, detracciones, retenciones
- Treasury & banking: bank accounts, reconciliation, petty cash, exchange rates
- Fixed assets: depreciation (SUNAT method), revaluations NIC 16, disposals
- Taxes: IGV/IR/IVA, PLE SUNAT (Libros de Ventas/Compras/Diario), fraccionamiento
- Budgets, cost centers, profit centers, cost allocation rules
- FX revaluation (NIC 21), intercompany transactions, period closing

---

## Production Module

Universal production management with 60 tables + 9 views covering any industry:

- **BOM types:** manufacturing · disassembly · refurbishment · recipe · kit · cutting_plan · configurable
- **Industries:** manufacturing · textiles · jewelry · food & beverage · restaurants/delivery · electronics · reverse logistics (trade-in)
- Work centers, machines, OEE tracking, IoT sensors, maintenance plans
- Routings with versioning (ECO), HACCP critical control points, parallel ops
- Production orders with full process-time traceability (started_at + completed_at per step)
- Work orders: setup / run / teardown / quality check timestamps — all GENERATED
- Quality control: plans, inspections, non-conformances, CAPA, CoA certificates
- Production areas dashboard: real-time tracking by area (factory floor or kitchen)
- Merma (waste) tracking with SUNAT classification (Art. 37 LIR: normal vs anormal)
- Standard vs actual costing, variances, WIP balances, SUNAT merma declarations
- Lot-to-lot genealogy (full backward/forward traceability for recalls)
- Restaurant features: kitchen stations, KDS tickets, temperature logs (HACCP)
- **Differentiators:** 🇵🇪 SUNAT Art.37 LIR merma/desmedro · 🍕 Restaurant/KDS · 📡 IoT sensors · ♻️ Reverse logistics · 💎 Precious metals · 👗 Cutting plans

📖 Ver [`docs/production/schema_production_es.md`](docs/production/schema_production_es.md) para el esquema completo en español.

---

## Projects Module

Project-based business management with 10 tables + 3 views — designed for consulting firms, software agencies, marketing teams, and any business that sells work by phase or by the hour:

- Project types catalog (software/consulting/marketing/construction/audit)
- Projects with billing types: fixed price, time & materials, milestone, retainer, pro bono
- Phases with progress tracking (planned vs actual start/end, estimated hours, budget)
- Billing milestones: trigger invoices when a phase or deliverable is reached
- Team roster with roles (PM/tech lead/developer/QA/analyst/designer) and per-member hourly rates
- Task management with subtask support, story points, priorities, status workflow
- Time entries (IMMUTABLE) with billable/non-billable distinction and T&M amount auto-computed
- Risk register with probability × impact matrix → auto-computed risk_level (low/medium/high/critical)
- Project documents with client-visibility flag (specs, deliverables, contracts, meeting notes)
- Immutable status change log for full audit trail
- Views: `project_dashboard_view` (progress, budget consumption, overdue milestones), `team_utilization_view` (hours by member/month), `billing_pipeline_view` (what's ready to invoice)
- Linked to `sales.sales_orders` (origin) → `sales.invoices` (billing per milestone or T&M)
- **Differentiators:** 📊 T&M auto-billing · 🎯 Milestone invoicing · ⚠️ Risk matrix · 🔗 CRM+Sales integration · 🕐 Time tracking with billable split

---

## Services Module

Appointment-based business management with 19 tables + 5 views — ideal for beauty salons, spas, clinics, gyms, veterinaries and any service business:

- Service catalog with categories, variants (by duration/price) and packages
- Resource management: stations, rooms, equipment, vehicles
- Staff profiles with skill levels (trainee/junior/senior/master) and price overrides per service
- Staff availability (recurring weekly + specific dates) + time-off blocks
- Appointments with source tracking (walk-in, WhatsApp, online, phone, POS)
- Per-service time logs (application / wait / rinse / dry phases) and consumables linked to inventory
- Waitlist with preferred staff, date/time preferences
- SMS/WhatsApp/email appointment reminders
- Client service history: color formulas, preferences, allergy alerts, before/after photos
- Staff KPI views: punctuality %, efficiency %, revenue, commission, avg rating by month
- Promo codes (Sales extension): VERANO20, BIENVENIDA10, birthday-personalized codes
- **Differentiators:** 💇 Formula history · ⏱️ Phase timing · 💊 Consumables → inventory · ⭐ Multi-dimension ratings · 📊 Staff KPIs

---

## Running the full ERP

```bash
# Install all 7 modules in order (takes ~20s)
./run_all.sh

# Full reset + reinstall from scratch
./run_all.sh --reset

# Individual modules
bash docs/hr/sql/run_hr.sh
bash docs/logistics/sql/run_logistics.sh
bash docs/sales/sql/run_sales.sh
bash docs/finance/sql/run_finance.sh
bash docs/production/sql/run_production.sh
bash docs/services/sql/run_services.sh
bash docs/projects/sql/run_projects.sh
```

Requirements: PostgreSQL running locally · `psql` in PATH · database `mantrasdb` created.

---

## Project structure

```
docs/
  hr/
    sql/                          ← 30 SQL files + run_hr.sh
    schema.md                     ← English documentation
    schema_es.md                  ← Spanish documentation
  logistics/
    sql/                          ← 13 SQL files + run_logistics.sh
    schema_logistics_es.md        ← Spanish documentation
  sales/
    sql/                          ← 13 SQL files + run_sales.sh
  finance/
    sql/                          ← 8 SQL files + run_finance.sh
  production/
    sql/                          ← 8 SQL files + run_production.sh
      01_bom.sql                  ← BOM universal (9 tipos) + logística inversa + refurbishment
      02_work_centers.sql         ← Centros de trabajo + máquinas + OEE + mantenimiento
      03_routings.sql             ← Rutas + versiones ECO + HACCP + operaciones paralelas
      04_production_orders.sql    ← OPs + bridge logistics + trazabilidad por proceso
      05_work_orders.sql          ← WOs + time entries + material issues + outputs
      06_quality_control.sql      ← Áreas + QC + inspecciones + CAPA + mermas SUNAT
      07_costing.sql              ← Costeo estándar/real + WIP + variaciones + SUNAT merma/desmedro
      08_differentiators.sql      ← Genealogía + IoT + KPIs + restaurante/KDS + temperatura HACCP
      run_production.sh
    schema_production_es.md       ← Spanish documentation
  services/
    sql/                          ← 4 SQL files + run_services.sh
      01_service_catalog.sql      ← Catálogo: servicios, variantes, paquetes, recursos
      02_staff_services.sql       ← Personal: skills, disponibilidad, bloqueos de agenda
      03_appointments.sql         ← Citas + servicios + consumibles + lista de espera + recordatorios
      04_ratings_kpis.sql         ← Calificaciones + historial cliente + vistas KPI
      run_services.sh
  projects/
    sql/                          ← 4 SQL files + run_projects.sh
      01_projects.sql             ← Tipos, proyectos, fases, hitos
      02_tasks_team.sql           ← Equipo, tareas, time entries (IMMUTABLE)
      03_documents_risks.sql      ← Documentos + registro de riesgos + log de estados
      04_views_kpis.sql           ← Vistas: dashboard, utilización equipo, pipeline de facturación
      run_projects.sh
run_all.sh                        ← Master installer (all 7 modules)
```

---

*Built with ❤️ in Peru.*
