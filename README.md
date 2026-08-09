# Mantras ERP 🐶

> Named after Mantras, a very good dog.

A modular, multi-tenant ERP system built on PostgreSQL — designed to work for any type of business, starting with Latin American companies.

**Goal:** a powerful, affordable alternative to SAP for small and mid-sized businesses in Peru and Latin America.

---

## Modules

| Module | Status |
|--------|--------|
| HR (Human Resources) | ✅ Complete |
| Logistics / WMS | ✅ Complete |
| Sales | ✅ Complete |
| Finance | ✅ Complete |
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

## Logistics / WMS Module

Full warehouse management system with 65+ tables covering the complete inbound → storage → outbound cycle:

- Multi-warehouse, multi-zone, multi-location (aisle-rack-level-position)
- Products, variants, barcodes, kits (physical & virtual), BOM
- Lot tracking (FEFO/FIFO/LIFO), serial numbers, LPN containers
- Inbound: purchase orders, receipts, quality inspection, putaway rules
- Inventory ledger (immutable, signed quantities — the source of truth)
- Wave picking: templates → waves → allocations → pick tasks (zone/batch/cluster/discrete)
- Outbound: orders (B2B & B2C), pack tasks, shipments, routes, route stops
- Transfers & replenishment tasks between zones and warehouses
- AMR/AGV robots: task queue, performance tracking, battery management
- Operator profiles linked to HR employees — no duplicate accounts
- **Differentiators vs SAP/Oracle:**
  - 🇵🇪 SUNAT GRE (electronic transport docs, required in Peru)
  - 💬 WhatsApp / SMS / Push notifications
  - 📸 Photo verification at pick and pack
  - 🌿 Carbon footprint tracking per shipment
  - 🎮 Operator gamification (points, levels, accuracy)
  - 🌡️ IoT sensor readings (temperature, humidity, weight)
  - 🚨 System-wide alert center

📖 Ver [`docs/logistics/schema_logistics_es.md`](docs/logistics/schema_logistics_es.md) para el esquema completo en español.

---

## Tech Stack

- **Database:** PostgreSQL
- **Schemas:** `hr`, `logistics` (more to come)
- **Database name:** `mantrasdb`
- **Architecture:** Multi-tenant (company-scoped via `company_id` on every table)

---

## Running the schemas

```bash
# HR module (run first — logistics depends on it)
bash docs/hr/sql/run_hr.sh postgresql://user:pass@localhost:5432/mantrasdb

# Logistics / WMS module
bash docs/logistics/sql/run_logistics.sh postgresql://user:pass@localhost:5432/mantrasdb
```

Requirements: PostgreSQL running locally, `psql` in PATH, database `mantrasdb` created.

---

## Project structure

```
docs/
  hr/
    sql/                    ← SQL files + run_hr.sh
    schema.md               ← English documentation
    schema_es.md            ← Spanish documentation
  logistics/
    sql/                    ← 13 SQL files + run_logistics.sh
      01_statuses_types.sql
      02_suppliers_carriers.sql
      03_products.sql
      04_product_kits.sql
      05_warehouses_locations.sql
      06_inventory.sql
      07_containers.sql
      08_inbound.sql
      09_waves_picking.sql
      10_outbound.sql
      11_transfers.sql
      12_robots.sql
      13_differentiators.sql
      run_logistics.sh
    schema_logistics_es.md  ← Spanish documentation
  sales/
    sql/                    ← 13 SQL files + run_sales.sh
      01_statuses_types.sql
      02_customers.sql
      03_pricing.sql        ← precios + escalas + precios especiales + product_sales_config
      04_quotations.sql
      05_sales_orders.sql
      06_invoicing.sql
      07_collections.sql
      08_commissions.sql
      09_differentiators.sql  ← canales, loyalty, forecast, motivos anulación, FKs
      10_promotions.sql       ← BOGO, bundles, rebaja peruana, rebates retroactivos
      11_pos_store.sql        ← tiendas físicas, POS, sesiones de caja
      12_returns.sql          ← RMA, inspección, disposición, garantías
      13_customer_extensions.sql ← categorías cliente + cuentas bancarias multi-moneda
      run_sales.sh
  finance/
    sql/                    ← 8 SQL files + run_finance.sh
      01_accounts_periods.sql  ← plan de cuentas PCGE Perú + PGC España + fiscal_years + períodos
      02_journal_entries.sql   ← asientos doble partida + Libro Mayor/Diario/Balance de Comprobación
      03_accounts_payable.sql  ← facturas proveedor + pagos AP + detracciones + retenciones
      04_treasury_banking.sql  ← cuentas bancarias + conciliación + caja chica + tipos de cambio
      05_fixed_assets.sql      ← activos fijos + depreciación SUNAT + revaluaciones NIC 16 + bajas
      06_taxes_ple.sql         ← IGV/IR/IVA + PLE SUNAT (Ventas/Compras/Diario) + fraccionamiento
      07_budgets_cost_centers.sql ← presupuestos + centros de costo + distribución analítica
      08_closing_intercompany.sql ← revaluación FX NIC 21 + intercompany + cierre de ejercicio
      run_finance.sh
```

---

*Built with ❤️ in Peru.*
