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
| Surveys | 6 | ✅ Complete |
| CRM | 6 | ✅ Complete |
| Payroll Engine | 8 | ✅ Complete |
| MRP / Planning | 6 | ✅ Complete |
| Venues | 11 | ✅ Complete |

**Total: 379 tables across 12 schemas**

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

## CRM Module

Sales pipeline management with 6 tables + 2 views:

- Configurable pipelines with stages and win-probability per stage
- Leads (unqualified prospects) with source tracking, lead score, and disqualification flow
- Opportunities with expected revenue, weighted revenue (auto-computed), and expected close date
- Multi-contact support per opportunity with decision-maker roles
- Activity log: calls, emails, meetings, demos, WhatsApp, notes with outcome tracking
- Linked to `sales.quotations` and `sales.sales_orders` when opportunity is won
- Views: `pipeline_view` (open opps by stage + sales rep), `sales_funnel_view` (win rate + avg days to close per stage)

---

## Payroll Engine Module

Payroll calculation engine with 8 tables + 2 views — extends the basic HR payroll tables:

- Rule categories: earnings, deductions, employer contributions, informational
- Calculation rules: fixed amount, % of basic, % of another rule, or free formula — covers Peru: ESSALUD (9%), AFP, ONP (13%), 5ta categoría
- Salary structures: group rules by contract type (e.g., "Planilla Perú", "Recibo por Honorarios")
- Payroll runs: draft → computed → validated → paid workflow with period reference
- Run lines: immutable computed values per employee per rule (full audit trail)
- Payslips with day-level tracking (days worked, absent) and payment method/bank account
- Payslip lines: snapshot of rule name/code at time of payment (never changes)
- Views: `run_summary_view` (totals + employer cost per run), `slip_detail_view` (per-employee detail with department/position)

---

## Venues Module

Recintos, eventos y membresías con 11 tables + 5 views — genérico para clubs campestres, piscinas, salas de conciertos, estadios y centros de convenciones:

- Recintos (`venues`) con tipo (club/concert_hall/stadium/pool/coworking/convention) y flags `requires_membership` + `has_ticketing`
- Zonas/sectores (`venue_zones`): general, VIP, premium, pool, court, field, stage, parking — con aforo propio, precio base y soporte de asientos numerados
- Amenidades del recinto (estacionamiento, vestuarios, bar, WiFi) — INMUTABLE
- Eventos (`events`) con tipo (regular/concert/sport/private/festival/class), artista, horario puertas/inicio/fin, estado y control de reingreso
- Aforo por zona por evento (`event_zone_capacity`): capacidad, tickets vendidos, disponibles y `is_sold_out` — todo GENERATED
- Tickets individuales con QR único, asiento numerado opcional, precio pagado, soporte de cortesía y transferencia entre clientes
- Log de accesos INMUTABLE (`access_logs`): entry/exit/reentry/denied, por QR o tarjeta de membresía, con snapshot de aforo al momento
- Tipos de membresía: Bronze/Plata/Oro/Familiar, periodicidad de cobro, matrícula, límite de visitas, pases de invitado, congelamiento
- Membresías individuales con estado (active/frozen/expired/cancelled), vigencia, renovación automática y referidos
- Beneficios por tipo de membresía: zone_access, service_discount, guest_pass, priority_booking, free_class — INMUTABLE
- Facturación periódica de membresías con referencia a `sales.invoices`
- Views: `event_occupancy_view` (aforo en tiempo real), `upcoming_events_view` (próximos eventos con disponibilidad), `membership_status_view` (socios + MRR estimado), `daily_access_view` (quién está dentro ahora), `membership_revenue_view` (ingresos por período)
- **Differentiators:** 🎟️ Tickets con QR · 🏊 Membresías con congelamiento · 🎭 Conciertos + clubs en mismo módulo · 📊 MRR estimado · 🚦 Aforo en tiempo real

---

## MRP Module

Material Requirements Planning with 6 tables + 2 views:

- Per-product planning parameters: reorder point, min/max stock, MOQ, lead time, supply method (buy/manufacture)
- Demand forecasts with accuracy tracking (forecast vs actual, auto-computed %)
- MRP runs with configurable planning horizon; tracks products analyzed and orders created
- Planned orders (purchase or manufacture) with date_required and date_planned_start (date_required − lead_time)
- Material requirements breakdown per planned order, with is_covered and qty_to_supply (GENERATED)
- Views: `coverage_view` (stock level + days of coverage + replenishment signal), `purchase_suggestions_view` (what to buy, by when, from whom)

---

## Surveys Module

Customer satisfaction measurement with 6 tables + 4 views — works across all modules:

- **NPS** (Net Promoter Score, 0–10): promoter / passive / detractor classification, auto-computed
- **CSAT** (1–5 stars): per-question and averaged across the response
- **CES** (Customer Effort Score, 1–7) and custom numeric scales
- Free-text questions, multiple-choice with configurable options (including "Other: ___")
- Boolean (yes/no) questions with conditional display logic (e.g., show follow-up only if NPS ≤ 6)
- Survey templates per company: trigger on appointment completion, sales order delivery, project close, or manual send
- Configurable send delay (e.g., 1 hour after the appointment), link expiry (days), and auto-reminder rules
- Invitations with unique tokens, delivery status tracking (sent / delivered / read / failed) and WhatsApp Business API integration-ready
- Responses are immutable; NPS score and CSAT avg are denormalized on the response header for fast dashboards
- Views: `nps_summary_view` (NPS score by month), `csat_summary_view` (CSAT avg + satisfied %), `response_detail_view` (full response with client + source event), `pending_invitations_view` (who hasn't responded + reminder eligibility)
- Linked to: `services.appointments`, `sales.sales_orders`, `projects.projects`, `sales.invoices`
- **Differentiators:** 📊 NPS auto-category · ⭐ CSAT avg · 🔗 Multi-module triggers · 📱 WhatsApp-ready · ⏰ Configurable delays & reminders

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
# Install all 12 modules in order (takes ~40s)
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
bash docs/surveys/sql/run_surveys.sh
bash docs/crm/sql/run_crm.sh
bash docs/payroll/sql/run_payroll.sh
bash docs/mrp/sql/run_mrp.sh
bash docs/venues/sql/run_venues.sh
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
    sql/                          ← 5 SQL files + run_projects.sh
      01_projects.sql             ← Tipos, proyectos, fases, hitos
      02_tasks_team.sql           ← Equipo, tareas, time entries (IMMUTABLE)
      03_documents_risks.sql      ← Documentos + registro de riesgos + log de estados
      04_views_kpis.sql           ← Vistas: dashboard, utilización equipo, pipeline de facturación
      05_hr_bridge.sql            ← Puente HR: carga por empleado/departamento, sobrecarga
      run_projects.sh
  surveys/
    sql/                          ← 2 SQL files + run_surveys.sh
      01_surveys.sql              ← Schema, templates, preguntas y opciones
      02_responses.sql            ← Invitaciones, respuestas, respuestas por pregunta + vistas NPS/CSAT
      run_surveys.sh
  crm/
    sql/                          ← 1 SQL file + run_crm.sh
      01_crm.sql                  ← Pipelines, stages, leads, opportunities, contacts, activities + vistas
      run_crm.sh
  payroll/
    sql/                          ← 1 SQL file + run_payroll.sh
      01_payroll_engine.sql       ← Reglas, estructuras, runs, boletas + vistas
      run_payroll.sh
  mrp/
    sql/                          ← 1 SQL file + run_mrp.sh
      01_mrp.sql                  ← Parámetros, pronósticos, runs, órdenes planificadas + vistas
      run_mrp.sh
  venues/
    sql/                          ← 3 SQL files + run_venues.sh
      01_venues.sql               ← Recintos, zonas, amenidades
      02_events.sql               ← Eventos, aforo por zona, tickets, access logs
      03_memberships.sql          ← Tipos de membresía, membresías, beneficios, facturación
      run_venues.sh
run_all.sh                        ← Master installer (all 12 modules)
```

---

*Built with ❤️ in Peru.*
