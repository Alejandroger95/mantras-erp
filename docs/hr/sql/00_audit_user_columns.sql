-- ============================================================
-- mantrasdb | Auditoría global
-- Archivo: 00_audit_user_columns.sql
-- Descripción: Agrega created_by_user_id y updated_by_user_id
--              a TODAS las tablas del sistema.
--
-- IMPORTANTE: ejecutar DESPUÉS de 99_system_users_audit.sql
-- ya que referencia hr.system_users(id).
--
-- Total tablas: 267 (246 originales + 19 services + 2 sales/promo_codes)
-- ============================================================

-- ── SCHEMA FINANCE ─────────────────────────────────────────

ALTER TABLE finance.account_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.accounting_periods
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.accounts
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.asset_categories
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.asset_disposals
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE finance.asset_revaluations
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE finance.bank_accounts
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.bank_reconciliation_items
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE finance.bank_reconciliations
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.bank_transactions
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.budget_lines
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.budgets
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.cash_flow_forecasts
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.closing_procedures
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.cost_allocation_rule_lines
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.cost_allocation_rules
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.cost_allocations
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE finance.cost_centers
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.currency_conversions
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE finance.currency_revaluations
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.depreciation_runs
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.depreciation_schedules
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE finance.detraction_records
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE finance.exchange_rates
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.expense_accruals
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.financial_statement_snapshots
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE finance.fiscal_years
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.fixed_assets
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.intercompany_transactions
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.internal_orders
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.journal_entries
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.journal_entry_lines
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE finance.petty_cash
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.petty_cash_transactions
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE finance.ple_journal_records
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE finance.ple_purchase_records
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE finance.ple_sales_records
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE finance.profit_centers
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.supplier_credit_note_applications
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE finance.supplier_document_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.supplier_invoice_lines
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.supplier_invoices
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.supplier_payment_allocations
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE finance.supplier_payments
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.tax_declarations
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.tax_installment_plans
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.tax_installments
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE finance.tax_periods
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.tax_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.withholding_records
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

-- ── SCHEMA HR ──────────────────────────────────────────────

ALTER TABLE hr.absence_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.absences
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.access_codes
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.access_systems
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.attendance
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.cities
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.code_assignments
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.companies
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.contract_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.contracts
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.countries
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.departments
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.disciplinary_actions
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.document_categories
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.documents
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.employees
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.equipment
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.equipment_assignments
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.equipment_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.holiday_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.holidays
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.payroll_concepts
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.payroll_details
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.payroll_periods
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.performance_reviews
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.person_documents
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.persons
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.positions
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.schedules
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.shifts
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.states
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.time_punches
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.training_participants
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.trainings
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.work_reductions
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

-- ── SCHEMA LOGISTICS ───────────────────────────────────────

ALTER TABLE logistics.adjustment_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.aisles
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.carrier_service_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.carrier_services
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.carriers
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.charging_stations
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.container_contents
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.container_movements
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.container_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.containers
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.customer_return_lines
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.customer_returns
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.delivery_proofs
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE logistics.dock_appointment_statuses
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.dock_appointments
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.docks
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.electronic_documents
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.inspection_statuses
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.inventory
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.inventory_allocations
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.inventory_count_details
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.inventory_counts
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.inventory_transactions
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE logistics.kit_assembly_order_lines
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.kit_assembly_orders
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.kit_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.location_sensors
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.location_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.locations
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.lots
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.measurement_units
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.notification_queue
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.operator_performance
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE logistics.operator_profiles
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.order_statuses
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.order_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.outbound_order_lines
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.outbound_orders
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.pack_statuses
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.pack_task_details
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.pack_tasks
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.pick_statuses
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.pick_task_details
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.pick_tasks
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.product_barcodes
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.product_categories
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.product_families
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.product_kit_components
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.product_kits
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.product_suppliers
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.product_variants
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.products
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.purchase_order_lines
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.purchase_orders
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.putaway_rules
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.putaway_tasks
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.quality_inspection_lines
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.quality_inspections
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.rack_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.receipt_lines
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.receipt_statuses
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.receipts
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.replenishment_tasks
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.robot_performance
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE logistics.robot_tasks
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.robot_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.robots
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.route_stops
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.routes
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.sensor_readings
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE logistics.serial_numbers
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.shipment_carbon_footprint
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.shipment_lines
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.shipment_statuses
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.shipments
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.supplier_addresses
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.supplier_return_lines
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.supplier_returns
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.suppliers
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.system_alerts
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.tracking_events
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE logistics.transfer_order_lines
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.transfer_orders
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.transfer_statuses
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.unit_conversions
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.warehouse_zones
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.warehouses
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.wave_orders
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.wave_statuses
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.wave_templates
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.waves
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.zone_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

-- ── SCHEMA SALES ───────────────────────────────────────────

ALTER TABLE sales.ad_hoc_price_overrides
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.cancellation_reasons
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.collection_reminders
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.collection_statuses
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.commission_calculations
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.commission_periods
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.commission_rules
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.company_bank_accounts
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.credit_note_lines
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.credit_notes
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.customer_addresses
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.customer_bank_accounts
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.customer_categories
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.customer_contacts
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.customer_credit_history
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.customer_groups
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.customer_payments
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.customer_price_list_assignments
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.customer_special_prices
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.customers
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.debit_notes
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.delivery_schedules
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.discount_rules
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.discount_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.document_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.invoice_installments
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.invoice_lines
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.invoice_statuses
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.invoices
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.loyalty_rules
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.loyalty_transactions
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE sales.order_statuses
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.order_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.payment_allocations
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.payment_methods
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.payment_statuses
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.payment_terms_catalog
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.pos_sessions
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.pos_terminals
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.pos_transaction_lines
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE sales.pos_transactions
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.price_list_items
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.price_lists
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.price_scales
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.product_sales_config
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.promotion_bundles
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.promotion_conditions
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.promotion_effects
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.promotions
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.promotions_applied
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE sales.quotation_lines
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.quotation_statuses
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.quotation_versions
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.quotations
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.rebate_accruals
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- inmutable: sin updated_by_user_id

ALTER TABLE sales.rebate_agreements
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.return_authorization_lines
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.return_authorizations
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.return_dispositions
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.return_inspections
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.sales_channels
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.sales_forecasts
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.sales_order_lines
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.sales_orders
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.sales_rep_discount_limits
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.sales_reps
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.stores
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.tax_rates
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.warranty_claims
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

-- ── SCHEMA SALES (extensión: promo codes) ──────────────────

ALTER TABLE sales.promo_codes
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.promo_code_redemptions
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- INMUTABLE: sin updated_by_user_id

-- ── SCHEMA SERVICES ────────────────────────────────────────

-- Tablas mutables (tienen updated_at)
ALTER TABLE services.service_categories
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE services.services
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE services.service_variants
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE services.service_packages
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE services.service_package_items
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE services.service_resources
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE services.service_resource_requirements
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE services.staff_profiles
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE services.staff_service_skills
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE services.staff_availability
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE services.staff_time_off
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE services.appointments
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE services.appointment_services
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE services.waitlist
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

-- Tablas inmutables (solo created_by_user_id)
ALTER TABLE services.appointment_time_log
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE services.appointment_consumables
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE services.appointment_reminders
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE services.service_ratings
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE services.client_service_history
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);

-- ── SCHEMA HR (extensión: training assessments) ────────────

ALTER TABLE hr.training_assessments
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.assessment_results
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
-- INMUTABLE: sin updated_by_user_id

-- ── SCHEMA PROJECTS ────────────────────────────────────────

-- Tablas mutables
ALTER TABLE projects.project_types
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE projects.projects
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE projects.project_phases
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE projects.project_milestones
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE projects.project_members
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE projects.project_tasks
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE projects.project_documents
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE projects.project_risks
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

-- Tablas inmutables
ALTER TABLE projects.time_entries
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE projects.project_status_log
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
