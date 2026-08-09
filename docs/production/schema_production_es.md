# Módulo Production — Esquema de Base de Datos

> **mantrasdb** | ERP Multi-tenant para PYMEs peruanas y latinoamericanas  
> Módulo: **Production** (Producción)  
> Schema PostgreSQL: `production`  
> Tablas: **60** | Vistas: **9**

---

## Filosofía de diseño

El módulo de Producción es **universal**: funciona para cualquier industria sin cambiar el código base. La diferencia entre fabricar un bolso de cuero, preparar un lomo saltado o reacondicionar un iPhone es solo de *configuración*, no de estructura.

**Principios clave:**

- **Multi-tenant**: `company_id` en cada tabla → empresas aisladas en un solo servidor.
- **Process-time traceability**: cada proceso tiene `started_at` + `completed_at`. El tiempo real es siempre medible.
- **GENERATED ALWAYS AS STORED**: duraciones, variaciones de costo, eficiencia, OEE — nunca desincronizados.
- **Inmutabilidad**: tablas de registro histórico (`order_process_log`, `time_entries`, `material_issues`, `merma_records`) no tienen `updated_at`. El pasado no se edita.
- **FK diferidas**: dependencias circulares resueltas con `DEFERRABLE INITIALLY DEFERRED`.
- **Bridge con Logistics**: `production_inventory_moves` vincula consumos y outputs de producción con `logistics.inventory_transactions`.
- **SUNAT-ready**: mermas clasificadas como normal/anormal (Art. 37 LIR), desmedros con datos de destrucción ante notario.

---

## Industrias soportadas

| Industria | Características clave |
|-----------|----------------------|
| 🏭 **Manufactura** | BOM multinivel, rutas estándar, OEE, centros de trabajo |
| 👗 **Textil / Confección** | BOM tipo `cutting_plan`, `fabric_width_cm`, merma de tela |
| 💎 **Joyería** | Metal precioso (`metal_purity_thousandths`), merma de fundición (`casting_loss_pct`) |
| 🍎 **Alimentos / Bebidas** | BOM tipo `recipe` con porcentajes, merma de cocción, shelf life |
| 🍕 **Restaurante / Delivery** | Comanda = OP, cocina = work center, tickets KDS por estación |
| 📱 **Electrónica / Refurbishment** | Diagnóstico, grading A/B/C/D/SCRAP, certificado de pruebas |
| ♻️ **Logística Inversa** | BOM tipo `disassembly` (trade-in Apple), recuperación de componentes |

---

## Flujo operativo

```
PRODUCCIÓN ESTÁNDAR
───────────────────────────────────────────────────────────────────
bom_header + routing
  → production_order (OP)
      → order_material_requirements  (explosión de BOM)
      → work_orders (1 WO por operación de la ruta)
          → work_order_time_entries  (tiempo operario / máquina)
          → material_issues          (consumo de MP → inventory_transaction)
          → work_order_outputs       (producción buena → inventory_transaction)
          → quality_inspections      (QC en línea)
      → order_process_log            (trazabilidad por proceso + área)
      → area_process_log             (tracking por área en tiempo real)
      → merma_records                (pérdidas clasificadas SUNAT)
  → production_inventory_moves       (bridge con logistics)
  → production_order_costs           (costos acumulados estándar vs real)
  → lot_genealogy                    (MP → PT, trazabilidad inversa)

RESTAURANTE / DELIVERY
───────────────────────────────────────────────────────────────────
sales_order (pedido del cliente)
  → production_order (comanda)
      → order_tickets (ticket por estación: cocina caliente, fría, bar)
          → kitchen_station_config (KDS, tiempo alerta)
          → temperature_logs      (HACCP, temperatura por estación)
      → area_process_log         (comanda: en cocina → en despacho → entregado)

LOGÍSTICA INVERSA / REFURBISHMENT
───────────────────────────────────────────────────────────────────
disassembly_bom (input: producto retornado → outputs: componentes)
  → production_order (tipo: disassembly / refurbishment)
      → work_orders (grading step → asigna refurbishment_grade)
      → work_order_outputs (output con grade_id A/B/C/D/SCRAP)
      → quality_certificates (test report / CoA)
      → lot_genealogy (serial retornado → componentes recuperados)
```

---

## Archivos SQL

| # | Archivo | Tablas principales |
|---|---------|-------------------|
| 01 | `01_bom.sql` | `industry_profiles`, `bom_headers`, `bom_versions`, `bom_lines`, `bom_substitutes`, `bom_by_products`, `bom_config_attributes`, `bom_config_values`, `bom_line_config_overrides`, `disassembly_bom`, `disassembly_bom_outputs`, `refurbishment_grade_scales`, `refurbishment_grades` |
| 02 | `02_work_centers.sql` | `work_center_types`, `work_centers`, `machines`, `work_center_capacity`, `work_center_calendar`, `maintenance_plans`, `machine_downtime` + view `machine_oee_summary` |
| 03 | `03_routings.sql` | `routings`, `routing_versions`, `routing_operations`, `operation_tools`, `operation_skill_requirements`, `routing_bom_links` + view `routing_summary` |
| 04 | `04_production_orders.sql` | `order_statuses`, `production_orders`, `order_material_requirements`, `production_inventory_moves`, `order_process_log` + view `production_order_status_view` |
| 05 | `05_work_orders.sql` | `work_orders`, `work_order_time_entries`, `material_issues`, `work_order_outputs` + view `operator_performance_view` |
| 06 | `06_quality_control.sql` | `production_areas`, `area_process_log`, `quality_plans`, `quality_characteristics`, `quality_inspections`, `inspection_results`, `non_conformances`, `corrective_actions`, `quality_certificates`, `merma_records` + views `area_dashboard`, `merma_by_order`, `merma_by_area` |
| 07 | `07_costing.sql` | `cost_versions`, `standard_costs`, `product_cost_breakdown`, `production_order_costs`, `cost_variances`, `wip_balances`, `sunat_merma_declarations`, `sunat_merma_declaration_lines` + view `order_cost_dashboard` |
| 08 | `08_differentiators.sql` | `lot_genealogy`, `production_alerts`, `kitchen_station_config`, `order_tickets`, `temperature_logs`, `production_kpis`, `iot_sensor_readings` + view `production_floor_view` |

---

## Tablas por módulo

### BOM (Bill of Materials)

| Tabla | Descripción |
|-------|-------------|
| `industry_profiles` | Perfil por empresa: activa/desactiva funcionalidades según industria (`track_precious_metals`, `use_cutting_plans`, `track_shelf_life`, `allow_disassembly_bom`). |
| `bom_headers` | Cabecera del BOM. Tipo: `manufacturing / disassembly / refurbishment / phantom / recipe / kit / subcontract / cutting_plan / configurable`. |
| `bom_versions` | Versionado del BOM con ECO (Engineering Change Order). |
| `bom_lines` | Componentes del BOM con cantidad, scrap%, método de consumo. Para textil: `fabric_width_cm`, `fabric_per_piece`. Para joyería: `metal_weight_grams`, `metal_purity`. |
| `bom_substitutes` | Materiales sustitutos con condición de uso (`stock_out / always / manual`). |
| `bom_by_products` | Subproductos y mermas del proceso. Flag `is_sunat_merma` + `sunat_merma_pct` para Art. 37 LIR. |
| `bom_config_attributes` | Atributos configurables (talla, color, quilates) para BOM tipo `configurable`. |
| `bom_config_values` | Valores de cada atributo (XS/S/M/L, 14k/18k, talla 7/8/9). |
| `bom_line_config_overrides` | Override de cantidad por combinación de atributos (talla L usa 15% más tela). |
| `disassembly_bom` | BOM de desarmado para logística inversa: `input_source` (return/trade_in/end_of_life). |
| `disassembly_bom_outputs` | Componentes recuperados en el desarmado con tipo y grado esperado. |
| `refurbishment_grade_scales` | Escala de grados de reacondicionamiento (A/B/C/D/SCRAP). |
| `refurbishment_grades` | Grados individuales: es vendible, descuento%, requiere reparación, requiere certificado. |

### Centros de Trabajo

| Tabla | Descripción |
|-------|-------------|
| `work_center_types` | Catálogo de tipos: ASSEMBLY, MACHINING, WELDING, CUTTING, SEWING, CASTING, TESTING, REPAIR, GRADING, MAQUILA, etc. |
| `work_centers` | Centros de trabajo con capacidad (machine/labor/pieces/weight), eficiencia%, costo por hora. Flag `is_bottleneck` para TOC. |
| `machines` | Máquinas individuales dentro de un centro. Soporte IoT (`iot_device_id`). Vinculo con `finance.fixed_assets`. |
| `work_center_capacity` | Capacidad por turno y día de la semana (horas disponibles, operarios, máquinas activas). |
| `work_center_calendar` | Excepciones al calendario: festivos, turnos extra, mantenimiento, averías. |
| `maintenance_plans` | Plan de mantenimiento preventivo por frecuencia: días calendario / horas máquina / ciclos de producción. |
| `machine_downtime` | Registro inmutable de paradas. `downtime_minutes` GENERATED. Base para cálculo de OEE. |

### Rutas de Producción

| Tabla | Descripción |
|-------|-------------|
| `routings` | Cabecera de ruta vinculada a un producto. Tipo: `manufacturing / disassembly / refurbishment / repair / quality_check`. |
| `routing_versions` | Versiones de la ruta con ECO. Solo una activa por ruta. |
| `routing_operations` | Pasos de la ruta: secuencia, centro de trabajo, tiempos (setup/run/teardown/wait/queue). Soporte HACCP (`is_critical_control_point`), grading, paralelo, subcontratación. |
| `operation_tools` | Herramientas y útiles necesarios por operación (consumibles y reutilizables). |
| `operation_skill_requirements` | Skills del operario requeridos por operación (basic/intermediate/advanced/expert). |
| `routing_bom_links` | Vincula ruta ↔ BOM. Un producto puede tener distintas combos por planta o método. |

### Órdenes de Producción

| Tabla | Descripción |
|-------|-------------|
| `order_statuses` | Catálogo de estados con color para dashboard (draft/confirmed/in_progress/quality_check/completed/closed/cancelled). |
| `production_orders` | OP principal. Tipo: `manufacturing / disassembly / refurbishment / rework / subcontract`. Campos de trazabilidad: `input_lot_id`, `input_serial_id`, `initial_grade_id`, `final_grade_id`. Costos estándar y reales GENERATED. |
| `order_material_requirements` | Explosión del BOM: materiales requeridos por OP con estado de aprovisionamiento. |
| `production_inventory_moves` | Bridge inmutable con `logistics.inventory_transactions`. Tipos: `production_consumption / production_output / production_scrap / disassembly_input / disassembly_output`. |
| `order_process_log` | Registro inmutable de cada transición de proceso por OP: área, operadores, resultado QC, `duration_min` y `time_variance_min` GENERATED. |

### Work Orders

| Tabla | Descripción |
|-------|-------------|
| `work_orders` | Una WO por operación de la ruta por OP. Timestamps para cada fase (queued/setup/production/teardown/quality_check). `actual_setup_min`, `actual_run_min`, `actual_total_min`, `time_efficiency_pct` GENERATED. |
| `work_order_time_entries` | Registro granular e inmutable del tiempo de cada operario y máquina. `duration_min` y `labor_cost` GENERATED. Base para OEE y costeo de MO. |
| `material_issues` | Entregas de material a producción (inmutable). Vinculado con `inventory_transactions`. Tipos: planned/additional/return/scrap. |
| `work_order_outputs` | Producción reportada (inmutable). Tipos: good/scrap/rework/byproduct. Genera movimiento a `inventory_transactions`. |

### Control de Calidad

| Tabla | Descripción |
|-------|-------------|
| `production_areas` | Áreas físicas de producción (input/production/quality/output/storage/shipping). Para restaurantes: cocina caliente, fría, despacho. Soporte de temperatura HACCP. |
| `area_process_log` | Tracking en tiempo real por área: cuándo entró y cuándo salió cada OP de cada área. `duration_in_area_min` GENERATED. |
| `quality_plans` | Plan de calidad: qué inspeccionar, cómo y cuándo. Muestreo: 100%, AQL, skip-lot. |
| `quality_characteristics` | Características a medir: variables (peso, temperatura, pH), atributos (pasa/falla), descriptivas. Límites de tolerancia LSL/USL. Flag `is_critical` para HACCP. |
| `quality_inspections` | Cabecera de inspección con resultado global (pass/fail/conditional), disposición y `duration_min` GENERATED. |
| `inspection_results` | Resultados medidos por característica. `deviation` del nominal GENERATED. Registro de temperatura para HACCP. |
| `non_conformances` | No conformidades detectadas. Severidad: critical/major/minor. Disposición inmediata. Análisis de causa raíz (5why/fishbone/FMEA). |
| `corrective_actions` | Acciones correctivas y preventivas (CAPA) con responsable, fecha límite y verificación de efectividad. |
| `quality_certificates` | Certificados por lote: CoA (alimentos/química), pureza (joyería), test report (electrónica), HACCP. Datos en JSONB flexible. |
| `merma_records` | Registro inmutable de cada merma por proceso o QC. Tipos: process/quality/cutting/casting/cooking/expired. `is_sunat_normal` para deducibilidad Art. 37 LIR. |

### Costeo de Producción

| Tabla | Descripción |
|-------|-------------|
| `cost_versions` | Versiones de costo estándar por año fiscal: standard/budget/simulation/actual. |
| `standard_costs` | Costo estándar por producto: MP + MOD + GIF + subcontratación + merma. `std_total_cost` GENERATED. |
| `product_cost_breakdown` | Desglose nivel a nivel del costo: qué componente u operación aporta cuánto. Generado por rollup de BOM. |
| `production_order_costs` | Costos acumulados por OP: estándar vs real, variaciones, eficiencia de costo, costo unitario real. Todo GENERATED. |
| `cost_variances` | Variaciones al cierre de OP: precio de material, cantidad, tasa MO, eficiencia, volumen GIF, merma. |
| `wip_balances` | Balance WIP mensual por OP: apertura + cargos (MP+MO+GIF) - transferidos a PT. Para cierre contable. |
| `sunat_merma_declarations` | Declaraciones formales de merma/desmedro (Art. 37 LIR Perú). Merma → informe técnico de perito habilitado. Desmedro → destrucción ante notario + comunicación previa 6 días hábiles a SUNAT. |
| `sunat_merma_declaration_lines` | Vínculo entre la declaración y los registros individuales de merma. |

### Diferenciadores

| Tabla | Descripción |
|-------|-------------|
| `lot_genealogy` | Trazabilidad lote-a-lote: de qué MP vino cada PT. Permite rastreo backward (recalls) y forward (alertas). |
| `production_alerts` | Alertas automáticas: demoras, falta material, fallos QC, averías, temperatura HACCP, merma excesiva. |
| `kitchen_station_config` | Configuración de estación de cocina: tipo (hot_kitchen/cold_kitchen/pastry/bar/dispatch), KDS, tiempo alerta. |
| `order_tickets` | Tickets de comanda por estación de cocina. Timestamps: created/acknowledged/started/ready/dispatched. `prep_time_min` y `total_time_min` GENERATED. |
| `temperature_logs` | Registros HACCP de temperatura por área/máquina/lote. `is_within_range` GENERATED. Genera alerta si sale de rango. |
| `production_kpis` | KPIs cacheados por período y nivel: OTD%, FPY%, Scrap Rate%, Utilización%. `otd_pct`, `fpy_pct`, `scrap_rate_pct`, `utilization_pct` GENERATED. |
| `iot_sensor_readings` | Lecturas de sensores IoT (temperatura, presión, vibración, velocidad, corriente). Solo anomalías y promedios para controlar volumen. |

---

## Vistas

| Vista | Descripción |
|-------|-------------|
| `machine_oee_summary` | OEE por máquina en el mes actual: disponibilidad calculada con downtime real. |
| `routing_summary` | Tiempos totales por ruta activa: setup, run, teardown, wait, queue, labor. |
| `production_order_status_view` | Estado por OP: % completado, proceso actual, último proceso, costos. |
| `operator_performance_view` | Eficiencia por operario: tiempo productivo vs setup vs idle, unidades, costo MO. |
| `area_dashboard` | Dashboard por área: órdenes activas, demoradas (NOW()-entered_at > target), tiempo promedio, NC abiertas. |
| `merma_by_order` | Mermas agrupadas por OP: total, costo deducible vs no deducible SUNAT. |
| `merma_by_area` | Mermas por área por mes: identifica dónde se generan más pérdidas. |
| `order_cost_dashboard` | Resumen ejecutivo por OP: estándar vs real, variación, eficiencia, costo unitario y mermas SUNAT. |
| `production_floor_view` | Vista del piso en tiempo real: órdenes activas, tickets de cocina, alertas y violaciones de temperatura por área. |

---

## Integraciones con otros módulos

| Módulo | Relación |
|--------|----------|
| **HR** | `company_id`, `system_users` (auditoría), `employees` (operarios — FK diferida) |
| **Logistics** | `products`, `lots`, `serial_numbers`, `locations`, `warehouses`, `inventory_transactions` (bridge via `production_inventory_moves`) |
| **Finance** | `cost_centers` (GIF), `fixed_assets` (máquinas), `journal_entries` (cierre de costos y variaciones) |
| **Sales** | `sales_orders` como origen de OPs (campo `origin_id` + `origin_type`) |

---

## Diseño para SUNAT (Perú)

| Concepto SUNAT | Implementación |
|---------------|----------------|
| **Merma normal (Art. 37 LIR)** | `merma_records.is_sunat_normal = TRUE` + `sunat_merma_declarations` con `technical_report_number` y datos del perito habilitado |
| **Desmedro** | `sunat_merma_declarations.declaration_type = 'desmedro'` con `destruction_date`, `notary_name`, `sunat_notification_date` |
| **Informe técnico** | `technical_expert_name` + `technical_expert_cip` (colegiatura del profesional) |
| **Libros de Producción** | `order_process_log` + `merma_records` + `lot_genealogy` proveen la trazabilidad exigida |

---

## KPIs principales

| KPI | Fórmula | Tabla/Vista |
|-----|---------|-------------|
| **OEE Disponibilidad** | `1 - downtime / theoretical_minutes` | `machine_oee_summary` |
| **FPY (First Pass Yield)** | `good_qty / planned_qty × 100` | `production_kpis` |
| **OTD (On-Time Delivery)** | `on_time_orders / total_orders × 100` | `production_kpis` |
| **Scrap Rate** | `scrap_qty / planned_qty × 100` | `production_kpis` |
| **Eficiencia de tiempo WO** | `planned_run_min / actual_run_min × 100` | `work_orders` |
| **Variación de costo** | `actual_total - std_total` | `production_order_costs` |
| **Merma % SUNAT** | `merma_qty / insumo_consumido × 100` | `merma_records` |
| **Tiempo de preparación (KDS)** | `ready_at - started_at` | `order_tickets` |
