# Módulo Logistics — Esquema de Base de Datos

> **mantrasdb** | ERP Multi-tenant para PYMEs peruanas y latinoamericanas  
> Módulo: **Logistics / WMS**  
> Schema PostgreSQL: `logistics`

---

## Filosofía de diseño

El módulo de Logística es un **WMS completo** (Warehouse Management System) integrado al ERP. Está inspirado en Oracle WMS pero diseñado para PYMEs: sin licencias millonarias, con integraciones nativas para el mercado peruano (SUNAT) y latinoamericano.

**Principios clave:**

- **Multi-tenant**: cada tabla incluye `company_id` → un solo servidor, múltiples empresas aisladas.
- **Ledger de inventario**: `inventory_transactions` es inmutable (no tiene `updated_at`). Registra todo movimiento. La suma siempre da el stock actual.
- **Unificación operador**: humanos y robots usan el mismo patrón `performed_by_type` (human/robot/system) + `performed_by_id`. No hay tablas separadas para trazabilidad.
- **Columnas generadas**: `quantity_available`, `quantity_pending`, `short_qty`, `net_carbon_kg_co2` y otras son `GENERATED ALWAYS AS ... STORED` — nunca desincronizadas.
- **Soft delete**: `is_active BOOLEAN DEFAULT TRUE` en todas las tablas principales.
- **FK diferidas**: cuando hay dependencias circulares, se usa `BIGINT` sin FK y se agrega el `ALTER TABLE ... ADD CONSTRAINT` al final de `13_differentiators.sql`.

---

## Flujo operativo

```
INBOUND                           OUTBOUND
──────────────────────────────    ────────────────────────────────────
purchase_order                    outbound_order
  → receipt                         → wave (wave_template)
  → quality_inspection                → inventory_allocation  ← (reserva)
  → putaway_task                      → pick_task
  → inventory (+)                       → pick_task_detail
  → inventory_transaction               → inventory_transaction (pick -)
                                    → pack_task
                                      → pack_task_detail
TRANSFER                              → shipment
──────────                              → route
transfer_order                            → route_stop
  → transfer_order_lines                    → delivery_proof
  → inventory_transaction             → tracking_events
    (transfer_out / transfer_in)      → electronic_document (GRE SUNAT)
```

---

## Archivos SQL

| # | Archivo | Tablas principales |
|---|---------|-------------------|
| 01 | `01_statuses_types.sql` | `order_statuses`, `order_types`, `shipment_statuses`, `wave_statuses`, `pick_statuses`, `pack_statuses`, `transfer_statuses`, `adjustment_types`, `zone_types`, `location_types`, `kit_types`, `dock_appointment_statuses`, `inspection_statuses` |
| 02 | `02_suppliers_carriers.sql` | `suppliers`, `supplier_addresses`, `carriers`, `carrier_services` |
| 03 | `03_products.sql` | `product_categories`, `product_families`, `measurement_units`, `unit_conversions`, `products`, `product_variants`, `product_barcodes`, `product_suppliers` |
| 04 | `04_product_kits.sql` | `product_kits`, `product_kit_components`, `kit_assembly_orders`, `kit_assembly_order_lines` |
| 05 | `05_warehouses_locations.sql` | `warehouses`, `docks`, `warehouse_zones`, `rack_types`, `aisles`, `locations`, `location_sensors` |
| 06 | `06_inventory.sql` | `lots`, `serial_numbers`, `inventory`, `inventory_transactions`, `inventory_counts`, `inventory_count_details` |
| 07 | `07_containers.sql` | `containers`, `container_contents`, `container_movements` |
| 08 | `08_inbound.sql` | `purchase_orders`, `purchase_order_lines`, `receipts`, `receipt_lines`, `quality_inspections`, `quality_inspection_lines`, `putaway_tasks`, `putaway_rules`, `supplier_returns`, `supplier_return_lines` |
| 09 | `09_waves_picking.sql` | `wave_templates`, `waves`, `wave_orders`, `inventory_allocations`, `pick_tasks`, `pick_task_details` |
| 10 | `10_outbound.sql` | `outbound_orders`, `outbound_order_lines`, `pack_tasks`, `pack_task_details`, `shipments`, `shipment_lines`, `routes`, `route_stops`, `delivery_proofs`, `tracking_events`, `dock_appointments`, `customer_returns`, `customer_return_lines` |
| 11 | `11_transfers.sql` | `transfer_orders`, `transfer_order_lines`, `replenishment_tasks` |
| 12 | `12_robots.sql` | `robot_types`, `charging_stations`, `robots`, `robot_tasks`, `robot_performance`, `operator_profiles`, `operator_performance` |
| 13 | `13_differentiators.sql` | `electronic_documents`, `notification_queue`, `shipment_carbon_footprint`, `sensor_readings`, `system_alerts` + FKs diferidas |

---

## Tablas clave en detalle

### `logistics.products`
El catálogo central de productos. Campos destacados:

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `sku` | VARCHAR | SKU único por empresa |
| `picking_strategy` | VARCHAR | FEFO / FIFO / LIFO |
| `is_kit` | BOOLEAN | Producto kit (físico o virtual) |
| `is_serialized` | BOOLEAN | Requiere número de serie |
| `is_lot_tracked` | BOOLEAN | Requiere control por lote |
| `abc_classification` | VARCHAR | A/B/C para ciclo de conteo |
| `volume_m3` | GENERATED | Calculado de dimensiones |

### `logistics.inventory`
Stock en tiempo real por ubicación + lote.

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `quantity_on_hand` | NUMERIC | Stock físico real |
| `quantity_reserved` | NUMERIC | Bloqueado por waves activas |
| `quantity_available` | GENERATED | on_hand - reserved |

### `logistics.inventory_transactions` — LEDGER CENTRAL
Inmutable. Registra cada movimiento con cantidad firmada:
- **Positivo** = entrada (receipt, return, kit_assembly_in)
- **Negativo** = salida (pick, ship, kit_assembly_out, scrap)

### `logistics.inventory_allocations`
La tabla de "asignación" del WMS. Antes de que el picker toque el producto, la allocation reserva el stock. Si `short_qty > 0`, hubo un short pick.

### `logistics.wave_templates`
Configuración de la ola de picking:
- `picking_method`: zone / batch / cluster / discrete
- `sort_method`: location_sequence / order_priority
- `inclusion_criteria` JSONB: qué órdenes entran
- `zone_sequence` JSONB: en qué orden visitar las zonas

---

## Diferenciadores vs SAP / Oracle WMS

| Funcionalidad | mantrasdb | SAP WM | Oracle WMS |
|--------------|-----------|--------|------------|
| SUNAT GRE electrónica | ✅ Nativo | ❌ Add-on costoso | ❌ Localización limitada |
| WhatsApp notifications | ✅ Nativo | ❌ No | ❌ No |
| Robots AMR integrados | ✅ Nativo | ⚠️ SAP EWM premium | ⚠️ Módulo adicional |
| Foto en pick/pack | ✅ Nativo | ❌ No | ❌ No |
| Huella de carbono | ✅ Por envío | ⚠️ SAP Sustainability | ❌ No |
| Gamificación operadores | ✅ Nativo | ❌ No | ❌ No |
| Sensores IoT integrados | ✅ Nativo | ⚠️ IoT Toolkit | ⚠️ Separado |
| Kits físicos y virtuales | ✅ Nativo | ⚠️ Complejo | ✅ Parcial |
| Multi-tenant SaaS | ✅ Por diseño | ❌ | ❌ |
| Código abierto | ✅ | ❌ | ❌ |

---

## Integración RR.HH. → Logística

Los operadores del almacén son **empleados de `hr.employees`**. No hay cuentas duplicadas.

```
hr.employees (id: 42, nombre: "Juan Quispe")
    │
    └── logistics.operator_profiles
        ├── warehouse_id: Almacén Lima Norte
        ├── device_type: rf_gun
        ├── gamification_level: senior
        └── default_zone_id: Zona A

-- En cualquier operación:
pick_tasks.performed_by_type = 'human'
pick_tasks.performed_by_id   = 42  → hr.employees.id

-- Para robots:
pick_tasks.performed_by_type = 'robot'
pick_tasks.performed_by_id   = 5   → logistics.robots.id
```

---

## Instalación

```bash
# 1. Instalar módulo HR primero (prerequisito)
cd docs/hr/sql
./run_hr.sh postgresql://user:pass@localhost:5432/mantrasdb

# 2. Instalar módulo Logistics
cd docs/logistics/sql
chmod +x run_logistics.sh
./run_logistics.sh postgresql://user:pass@localhost:5432/mantrasdb
```

---

## Estado del módulo

| Sección | Estado |
|---------|--------|
| Catálogos y tipos | ✅ Completo |
| Proveedores y carriers | ✅ Completo |
| Productos y kits | ✅ Completo |
| Almacenes y ubicaciones | ✅ Completo |
| Inventario y ledger | ✅ Completo |
| Contenedores (LPN/SSCC) | ✅ Completo |
| Flujo inbound | ✅ Completo |
| Waves y picking | ✅ Completo |
| Flujo outbound y envíos | ✅ Completo |
| Transferencias y replenishment | ✅ Completo |
| Robots AMR y operadores | ✅ Completo |
| SUNAT GRE | ✅ Completo |
| Notificaciones WhatsApp | ✅ Completo |
| Huella de carbono | ✅ Completo |
| Sensores IoT | ✅ Completo |
| Alertas del sistema | ✅ Completo |

---

*Construido con ❤️ en Perú. Para Mantras 🐶*
