-- ============================================================
-- mantrasdb | Módulo Production
-- Archivo: 06_quality_control.sql
-- Descripción: Control de Calidad + Trazabilidad por Área
--
-- Funciona para CUALQUIER industria y tipo de negocio:
--   🏭 Manufactura       — inspección en línea, muestreo AQL
--   🍎 Alimentos/Rest.   — HACCP, temperatura, higiene, tiempo de cocción
--   🍕 Restaurante/Food  — comanda por área: cocina caliente, fría, repostería
--   💎 Joyería           — prueba de pureza, peso, acabado
--   📱 Electrónica/Refurb— prueba funcional, diagnóstico, certificado
--   👗 Textil            — medidas, defectos visuales, color
--
-- Módulos:
--   1. production_areas       — áreas físicas de trabajo (cocina, calidad, despacho)
--   2. quality_plans          — plan de calidad por producto/proceso
--   3. quality_checkpoints    — puntos de control en la ruta
--   4. quality_inspections    — inspecciones realizadas (cabecera)
--   5. inspection_results     — resultados por característica medida
--   6. non_conformances       — no conformidades / defectos detectados
--   7. corrective_actions     — acciones correctivas y preventivas (CAPA)
--   8. certificates           — certificados de calidad / análisis (CoA)
-- ============================================================

-- ============================================================
-- 1. PRODUCTION AREAS (Áreas Físicas de Producción)
--    Agrupación de centros de trabajo por área.
--    Permite ver el estado de producción por área en tiempo real.
--
--    Manufactura: Área MP → Área Producción → Área QC → Área PT
--    Restaurante: Área Cocina Caliente → Área Cocina Fría →
--                 Área Repostería → Área Despacho → Área Delivery
--    Joyería:     Área Fundición → Área Laminado → Área Engaste
--                 → Área Pulido → Área Control → Área Caja
-- ============================================================
CREATE TABLE production.production_areas (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    code                VARCHAR(20) NOT NULL,
    name                VARCHAR(100) NOT NULL,
    description         TEXT,

    area_type           VARCHAR(20) NOT NULL DEFAULT 'production',
    -- input       : recepción de materias primas / retornos
    -- production  : proceso de fabricación / cocina
    -- quality     : control de calidad / inspección
    -- output      : salida de PT / despacho / entrega
    -- storage     : almacenamiento WIP (Work In Progress)
    -- shipping    : envío / delivery

    -- Orden de flujo (para visualizar el pipeline)
    flow_sequence       SMALLINT    NOT NULL DEFAULT 10,

    -- Vinculo con almacén/zona logística
    warehouse_id        BIGINT      REFERENCES logistics.warehouses(id),
    warehouse_zone_id   BIGINT      REFERENCES logistics.warehouse_zones(id),

    -- Supervisor del área
    supervisor_employee_id BIGINT,
    -- REFERENCES hr.employees(id) — FK diferida

    -- Para restaurantes: ¿es un área de cocina?
    is_kitchen_area     BOOLEAN     NOT NULL DEFAULT FALSE,

    -- ¿Esta área tiene control de temperatura? (HACCP)
    has_temperature_control BOOLEAN NOT NULL DEFAULT FALSE,
    min_temperature_c   NUMERIC(5,2),
    max_temperature_c   NUMERIC(5,2),

    color_hex           VARCHAR(7),
    -- Color para dashboard de producción en tiempo real

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE TRIGGER trg_area_updated_at
    BEFORE UPDATE ON production.production_areas
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

-- Asignar centros de trabajo a áreas
ALTER TABLE production.work_centers
    ADD COLUMN IF NOT EXISTS area_id BIGINT REFERENCES production.production_areas(id);

COMMENT ON TABLE production.production_areas IS 'Áreas físicas de producción: permite tracking de qué proceso está en qué área. Incluye soporte HACCP para temperatura en alimentos y restaurantes.';

-- ============================================================
-- 2. AREA PROCESS LOG
--    Registro en tiempo real de qué producción está en cada área.
--    Para restaurantes: muestra el estado de cada comanda por área.
--    Para manufactura: muestra el WIP por área.
-- ============================================================
CREATE TABLE production.area_process_log (
    id                  BIGSERIAL   PRIMARY KEY,
    production_order_id BIGINT      NOT NULL REFERENCES production.production_orders(id),
    work_order_id       BIGINT      REFERENCES production.work_orders(id),
    area_id             BIGINT      NOT NULL REFERENCES production.production_areas(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Cuándo entró al área
    entered_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Cuándo salió del área (va al siguiente)
    exited_at           TIMESTAMPTZ,

    duration_in_area_min NUMERIC(10,2) GENERATED ALWAYS AS (
        CASE WHEN exited_at IS NOT NULL
             THEN EXTRACT(EPOCH FROM (exited_at - entered_at)) / 60
             ELSE NULL END
    ) STORED,

    -- Tiempo objetivo en el área (para alertas de demora)
    target_duration_min NUMERIC(10,2),

    -- ¿Hay demora vs objetivo?
    is_delayed          BOOLEAN     GENERATED ALWAYS AS (
        CASE WHEN exited_at IS NULL AND target_duration_min IS NOT NULL
                  AND EXTRACT(EPOCH FROM (NOW() - entered_at)) / 60 > target_duration_min
             THEN TRUE
             ELSE FALSE END
    ) STORED,

    area_status         VARCHAR(20) NOT NULL DEFAULT 'active',
    -- active    : el proceso está actualmente en esta área
    -- completed : salió del área exitosamente
    -- skipped   : área omitida
    -- delayed   : en el área pero con demora

    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);

CREATE INDEX idx_apl_order  ON production.area_process_log (production_order_id);
CREATE INDEX idx_apl_area   ON production.area_process_log (area_id);
CREATE INDEX idx_apl_status ON production.area_process_log (area_status);
CREATE INDEX idx_apl_entered ON production.area_process_log (entered_at);

COMMENT ON TABLE production.area_process_log IS 'Tracking en tiempo real por área. Para restaurantes muestra el estado de cada comanda (en cocina caliente, en despacho, etc.).';

-- ============================================================
-- 3. QUALITY PLANS
--    Define qué se inspecciona, cómo y cuándo.
--    Puede estar vinculado a un producto, a una ruta o a ambos.
-- ============================================================
CREATE TABLE production.quality_plans (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    code                VARCHAR(30) NOT NULL,
    name                VARCHAR(200) NOT NULL,
    description         TEXT,

    -- ¿A qué aplica este plan?
    applies_to          VARCHAR(20) NOT NULL DEFAULT 'product',
    -- product   : a un producto específico
    -- routing   : a una ruta/proceso
    -- area      : a un área de producción
    -- supplier  : a un proveedor (calidad de recepción)
    -- customer  : criterios de aceptación por cliente

    product_id          BIGINT      REFERENCES logistics.products(id),
    routing_id          BIGINT      REFERENCES production.routings(id),
    area_id             BIGINT      REFERENCES production.production_areas(id),

    -- Tipo de control
    inspection_type     VARCHAR(20) NOT NULL DEFAULT 'in_process',
    -- receiving    : al recibir materia prima
    -- in_process   : durante el proceso de fabricación
    -- final        : inspección final antes de despacho
    -- outgoing     : al despachar al cliente
    -- haccp        : punto crítico de control (alimentos)

    -- Método de muestreo
    sampling_method     VARCHAR(20) NOT NULL DEFAULT 'by_quantity',
    -- 100pct      : inspección 100% (pieza por pieza)
    -- by_quantity : muestra fija (cada N unidades)
    -- aql         : Acceptance Quality Level (ISO 2859)
    -- skip_lot    : saltear lotes según historial

    -- AQL settings
    aql_level           VARCHAR(10),
    -- 'I', 'II', 'III' (nivel de inspección AQL)
    aql_acceptable_quality_level NUMERIC(5,3),
    -- ej: 1.0, 2.5, 4.0 (% defectos aceptables)

    -- Para restaurantes/HACCP: frecuencia de control de temperatura
    temperature_check_frequency_min SMALLINT,

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE TRIGGER trg_qplan_updated_at
    BEFORE UPDATE ON production.quality_plans
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

-- ============================================================
-- 4. QUALITY CHARACTERISTICS (Características a Medir)
--    Define cada parámetro a inspeccionar dentro de un plan.
-- ============================================================
CREATE TABLE production.quality_characteristics (
    id                  BIGSERIAL   PRIMARY KEY,
    quality_plan_id     BIGINT      NOT NULL REFERENCES production.quality_plans(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    characteristic_name VARCHAR(200) NOT NULL,
    -- Ej: 'Peso neto', 'Temperatura de cocción', 'Pureza oro', 'Color Pantone'

    characteristic_type VARCHAR(20) NOT NULL DEFAULT 'variable',
    -- variable    : valor numérico (peso, temperatura, dimensión)
    -- attribute   : pasa/falla (visual, funcional)
    -- descriptive : texto libre (color, sabor, olor)

    -- Para características variables: valores aceptables
    unit_of_measure     VARCHAR(30),
    -- 'g', '°C', 'mm', '%', 'pH', 'ppm'

    nominal_value       NUMERIC(18,6),
    -- Valor objetivo ideal

    min_value           NUMERIC(18,6),
    max_value           NUMERIC(18,6),
    -- Límites de tolerancia (LSL / USL)

    -- Para características de atributo: criterio de aceptación
    acceptance_criteria TEXT,

    -- ¿Es un punto crítico de control? (HACCP)
    is_critical         BOOLEAN     NOT NULL DEFAULT FALSE,

    -- ¿Requiere instrumento de medición?
    measurement_instrument VARCHAR(100),
    -- 'Balanza digital', 'Termómetro infrarrojo', 'Micrómetro', 'Refractómetro'

    -- ¿El resultado se registra con foto?
    requires_photo      BOOLEAN     NOT NULL DEFAULT FALSE,

    sequence            SMALLINT    NOT NULL DEFAULT 10,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE production.quality_characteristics IS 'Parámetros a medir en cada inspección: peso, temperatura, pureza, dimensiones, pasa/falla. Incluye límites tolerancia y flag HACCP.';

-- ============================================================
-- 5. QUALITY INSPECTIONS (Inspecciones Realizadas)
-- ============================================================
CREATE TABLE production.quality_inspections (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    inspection_number   VARCHAR(30) NOT NULL,

    quality_plan_id     BIGINT      REFERENCES production.quality_plans(id),

    -- ¿A qué está vinculada esta inspección?
    production_order_id BIGINT      REFERENCES production.production_orders(id),
    work_order_id       BIGINT      REFERENCES production.work_orders(id),
    area_id             BIGINT      REFERENCES production.production_areas(id),

    -- Lote / serie inspeccionada
    lot_id              BIGINT      REFERENCES logistics.lots(id),
    serial_id           BIGINT      REFERENCES logistics.serial_numbers(id),

    product_id          BIGINT      REFERENCES logistics.products(id),

    -- Cantidad inspeccionada
    inspected_quantity  NUMERIC(18,6) NOT NULL,
    accepted_quantity   NUMERIC(18,6) NOT NULL DEFAULT 0,
    rejected_quantity   NUMERIC(18,6) NOT NULL DEFAULT 0,

    -- Resultado global
    overall_result      VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending   : aún en proceso
    -- pass      : aprobado
    -- fail      : rechazado
    -- conditional: aprobado con observaciones

    -- Fecha y hora de la inspección
    inspection_date     DATE        NOT NULL DEFAULT CURRENT_DATE,
    started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at        TIMESTAMPTZ,

    duration_min        NUMERIC(10,2) GENERATED ALWAYS AS (
        CASE WHEN completed_at IS NOT NULL
             THEN EXTRACT(EPOCH FROM (completed_at - started_at)) / 60
             ELSE NULL END
    ) STORED,

    -- Inspector
    inspector_id        BIGINT      REFERENCES hr.system_users(id),

    -- ¿La inspección requirió parar la producción?
    production_halted   BOOLEAN     NOT NULL DEFAULT FALSE,

    disposition         VARCHAR(20),
    -- use_as_is   : usar como está
    -- rework      : reprocesar
    -- scrap       : desechar
    -- return_supplier: devolver al proveedor
    -- quarantine  : en cuarentena

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX uq_inspection_number
    ON production.quality_inspections (company_id, inspection_number);
CREATE INDEX idx_qi_order   ON production.quality_inspections (production_order_id);
CREATE INDEX idx_qi_area    ON production.quality_inspections (area_id);
CREATE INDEX idx_qi_result  ON production.quality_inspections (overall_result);

CREATE TRIGGER trg_qi_updated_at
    BEFORE UPDATE ON production.quality_inspections
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

-- ============================================================
-- 6. INSPECTION RESULTS (Resultados por Característica)
-- ============================================================
CREATE TABLE production.inspection_results (
    id                  BIGSERIAL   PRIMARY KEY,
    inspection_id       BIGINT      NOT NULL REFERENCES production.quality_inspections(id) ON DELETE CASCADE,
    characteristic_id   BIGINT      REFERENCES production.quality_characteristics(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    characteristic_name VARCHAR(200) NOT NULL,
    -- Copiado del plan para inmutabilidad del resultado

    -- Resultado medido
    measured_value      NUMERIC(18,6),
    -- Para características variables

    attribute_result    VARCHAR(20),
    -- pass / fail
    -- Para características de atributo

    text_result         TEXT,
    -- Para resultados descriptivos (color, sabor, olor)

    -- ¿Está dentro de tolerancia?
    is_within_spec      BOOLEAN,

    -- Desviación del valor nominal
    deviation           NUMERIC(18,6) GENERATED ALWAYS AS (
        CASE WHEN measured_value IS NOT NULL AND nominal_value IS NOT NULL
             THEN measured_value - nominal_value
             ELSE NULL END
    ) STORED,
    nominal_value       NUMERIC(18,6),
    -- Copiado del plan al momento de la inspección

    measurement_instrument VARCHAR(100),

    -- Foto del resultado (URL o referencia)
    photo_url           TEXT,

    -- Temperatura (para registros HACCP de alimentos)
    temperature_c       NUMERIC(6,2),
    temperature_measured_at TIMESTAMPTZ,

    notes               TEXT,

    measured_by         BIGINT      REFERENCES hr.system_users(id),
    measured_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE
);

CREATE INDEX idx_ir_inspection ON production.inspection_results (inspection_id);
CREATE INDEX idx_ir_spec       ON production.inspection_results (is_within_spec);

COMMENT ON TABLE production.inspection_results IS 'Resultados medidos por característica. Incluye temperatura HACCP, desviación del nominal y foto.';

-- ============================================================
-- 7. NON-CONFORMANCES (No Conformidades)
-- ============================================================
CREATE TABLE production.non_conformances (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    nc_number           VARCHAR(30) NOT NULL,

    inspection_id       BIGINT      REFERENCES production.quality_inspections(id),
    production_order_id BIGINT      REFERENCES production.production_orders(id),
    area_id             BIGINT      REFERENCES production.production_areas(id),
    product_id          BIGINT      REFERENCES logistics.products(id),
    lot_id              BIGINT      REFERENCES logistics.lots(id),

    -- Descripción del defecto
    defect_type         VARCHAR(50) NOT NULL,
    -- dimensional / visual / functional / contamination /
    -- temperature / weight / composition / packaging / other

    severity            VARCHAR(10) NOT NULL DEFAULT 'minor',
    -- critical  : riesgo de seguridad o incumplimiento regulatorio
    -- major     : falla funcional o de cliente
    -- minor     : desviación pequeña, no afecta uso

    defect_description  TEXT        NOT NULL,

    quantity_affected   NUMERIC(18,6),

    -- Disposición inmediata
    immediate_action    VARCHAR(20) NOT NULL DEFAULT 'quarantine',
    -- quarantine / rework / scrap / use_as_is / return_supplier

    -- Estado
    status              VARCHAR(20) NOT NULL DEFAULT 'open',
    -- open / under_analysis / corrective_action / closed / reopened

    detected_by         BIGINT      REFERENCES hr.system_users(id),
    detected_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    closed_at           TIMESTAMPTZ,
    closed_by           BIGINT      REFERENCES hr.system_users(id),

    root_cause          TEXT,
    root_cause_method   VARCHAR(20),
    -- fishbone / 5why / pareto / fmea

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX uq_nc_number
    ON production.non_conformances (company_id, nc_number);
CREATE INDEX idx_nc_order    ON production.non_conformances (production_order_id);
CREATE INDEX idx_nc_area     ON production.non_conformances (area_id);
CREATE INDEX idx_nc_severity ON production.non_conformances (severity);
CREATE INDEX idx_nc_status   ON production.non_conformances (status);

CREATE TRIGGER trg_nc_updated_at
    BEFORE UPDATE ON production.non_conformances
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

-- ============================================================
-- 8. CORRECTIVE ACTIONS (CAPA)
-- ============================================================
CREATE TABLE production.corrective_actions (
    id                  BIGSERIAL   PRIMARY KEY,
    non_conformance_id  BIGINT      NOT NULL REFERENCES production.non_conformances(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    action_type         VARCHAR(20) NOT NULL DEFAULT 'corrective',
    -- corrective  : elimina la causa del problema actual
    -- preventive  : evita que ocurra en el futuro

    action_description  TEXT        NOT NULL,

    responsible_id      BIGINT      REFERENCES hr.system_users(id),

    due_date            DATE        NOT NULL,
    completed_date      DATE,

    status              VARCHAR(20) NOT NULL DEFAULT 'open',
    -- open / in_progress / completed / verified / overdue

    verification_method TEXT,
    verification_result TEXT,
    verified_by         BIGINT      REFERENCES hr.system_users(id),
    verified_at         TIMESTAMPTZ,

    effectiveness_confirmed BOOLEAN NOT NULL DEFAULT FALSE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_capa_updated_at
    BEFORE UPDATE ON production.corrective_actions
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

-- ============================================================
-- 9. QUALITY CERTIFICATES (Certificados de Calidad / CoA)
--    Para industrias que requieren certificado por lote:
--    alimentos (CoA), farmacéutica (CoA), joyería (certificado de pureza)
--    electrónica (test report)
-- ============================================================
CREATE TABLE production.quality_certificates (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    cert_number         VARCHAR(50) NOT NULL,

    cert_type           VARCHAR(20) NOT NULL DEFAULT 'coa',
    -- coa         : Certificate of Analysis (alimentos, química, farmacéutica)
    -- purity      : Certificado de pureza (joyería, metales)
    -- test_report : Reporte de pruebas (electrónica, refurbishment)
    -- haccp       : Registro HACCP
    -- phytosanitary: Certificado fitosanitario (agroexportación)

    production_order_id BIGINT      REFERENCES production.production_orders(id),
    lot_id              BIGINT      REFERENCES logistics.lots(id),
    product_id          BIGINT      REFERENCES logistics.products(id),

    -- Fecha del certificado
    issue_date          DATE        NOT NULL DEFAULT CURRENT_DATE,
    expiry_date         DATE,

    -- Resultados resumidos en el certificado (JSONB flexible)
    certificate_data    JSONB,
    -- Ej joyería: {"pureza_millesimas": 750, "peso_gramos": 12.5, "piedras": [...]}
    -- Ej alimentos: {"ph": 4.2, "humedad_pct": 8.1, "coliformes": "ausente"}
    -- Ej electrónica: {"bateria_ciclos": 120, "pantalla": "A", "camara": "funcional"}

    -- Firmado/emitido por
    issued_by           BIGINT      REFERENCES hr.system_users(id),

    -- URL del PDF del certificado
    document_url        TEXT,

    is_valid            BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX uq_cert_number
    ON production.quality_certificates (company_id, cert_number);
CREATE INDEX idx_cert_lot     ON production.quality_certificates (lot_id);
CREATE INDEX idx_cert_order   ON production.quality_certificates (production_order_id);

COMMENT ON TABLE production.quality_certificates IS 'Certificados por lote: CoA (alimentos/química), pureza (joyería), test report (electrónica), HACCP. Datos en JSONB flexible por industria.';

-- ============================================================
-- VIEW: Dashboard de producción por área (tiempo real)
-- ============================================================
CREATE VIEW production.area_dashboard AS
SELECT
    a.id AS area_id,
    a.company_id,
    a.name AS area_name,
    a.area_type,
    a.flow_sequence,
    a.color_hex,
    -- Órdenes actualmente en esta área
    COUNT(apl.id) FILTER (WHERE apl.area_status = 'active') AS active_orders,
    -- Órdenes demoradas
    COUNT(apl.id) FILTER (WHERE apl.is_delayed = TRUE AND apl.area_status = 'active') AS delayed_orders,
    -- Tiempo promedio en el área (últimas 24h)
    ROUND(AVG(apl.duration_in_area_min) FILTER (
        WHERE apl.area_status = 'completed'
          AND apl.exited_at >= NOW() - INTERVAL '24 hours'), 2) AS avg_duration_min_24h,
    -- No conformidades abiertas en el área
    COUNT(nc.id) FILTER (WHERE nc.status = 'open') AS open_nc_count
FROM production.production_areas a
LEFT JOIN production.area_process_log apl ON apl.area_id = a.id
LEFT JOIN production.non_conformances nc ON nc.area_id = a.id
WHERE a.is_active = TRUE
GROUP BY a.id, a.company_id, a.name, a.area_type, a.flow_sequence, a.color_hex
ORDER BY a.flow_sequence;

COMMENT ON VIEW production.area_dashboard IS 'Dashboard en tiempo real por área: órdenes activas, demoradas, tiempo promedio y no conformidades abiertas. Funciona para fábricas y restaurantes.';

-- ============================================================
-- 10. MERMA RECORDS (Registro de Mermas)
--     Registra CADA merma detectada durante producción o QC.
--
--     Tipos de merma en Perú (SUNAT Art. 37 LIR):
--       - Merma normal: inherente al proceso (evaporación, corte,
--         moldeo, cocción). Acreditada = aceptada como gasto.
--       - Merma anormal: por descuido, accidente, mala calidad.
--         No deducible como gasto.
--
--     Orígenes de merma:
--       🍎 Alimentos: cocción (pérdida de humedad), pelado,
--                     limpieza, fermentación
--       👗 Textil:    restos de tela al cortar (tizado)
--       💎 Joyería:   polvo de limado, pérdida en fundición
--       🏭 Manufactura: recortes, rebabas, piezas rechazadas
--       📱 Electrónica: componentes defectuosos no reparables
-- ============================================================
CREATE TABLE production.merma_records (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Origen de la merma
    production_order_id BIGINT      REFERENCES production.production_orders(id),
    work_order_id       BIGINT      REFERENCES production.work_orders(id),
    inspection_id       BIGINT      REFERENCES production.quality_inspections(id),
    non_conformance_id  BIGINT      REFERENCES production.non_conformances(id),
    area_id             BIGINT      REFERENCES production.production_areas(id),

    -- Producto / material que se pierde
    product_id          BIGINT      NOT NULL REFERENCES logistics.products(id),
    lot_id              BIGINT      REFERENCES logistics.lots(id),

    -- Cantidad de merma
    quantity            NUMERIC(18,6) NOT NULL,
    uom_id              BIGINT      REFERENCES logistics.measurement_units(id),

    -- Costo unitario al momento del registro (para valorización)
    unit_cost           NUMERIC(18,4),
    total_cost          NUMERIC(18,4) GENERATED ALWAYS AS (quantity * unit_cost) STORED,
    cost_currency       VARCHAR(10) NOT NULL DEFAULT 'PEN',

    -- Clasificación de merma
    merma_type          VARCHAR(20) NOT NULL DEFAULT 'process',
    -- process     : inherente al proceso (normal)
    -- quality     : rechazada en QC
    -- handling    : manejo deficiente
    -- storage     : almacenamiento inadecuado
    -- expired     : vencimiento (alimentos, farmacéutica)
    -- cutting     : recorte de corte (textil, láminas)
    -- casting     : pérdida de fundición (joyería, metales)
    -- cooking     : merma de cocción (alimentos, restaurante)

    -- Para fines SUNAT (Perú)
    is_sunat_normal     BOOLEAN     NOT NULL DEFAULT TRUE,
    -- TRUE  = merma normal → deducible como gasto (Art. 37 LIR)
    -- FALSE = merma anormal → no deducible

    -- Informe técnico de merma acreditada (SUNAT exige informe)
    sunat_technical_report_ref VARCHAR(100),
    -- Número de referencia del informe técnico del tercero habilitado

    -- Porcentaje de merma sobre el insumo consumido
    merma_pct           NUMERIC(7,4),
    -- ej: 5.00 = 5% de pérdida en cocción
    -- Calculado: (quantity / insumo_consumido) * 100

    -- Destino de la merma
    disposition         VARCHAR(20) NOT NULL DEFAULT 'scrap',
    -- scrap       : chatarra / basura
    -- recycle     : reciclaje / venta como chatarra
    -- reprocess   : se puede reprocesar
    -- compost     : compostaje (orgánicos)
    -- incinerate  : incineración (residuos peligrosos)
    -- return_supplier: devuelve al proveedor
    -- donate      : donación

    -- ¿Generó movimiento de inventario?
    inventory_transaction_id BIGINT,
    -- REFERENCES logistics.inventory_transactions(id) — FK diferida

    -- Quién detectó / registró la merma
    detected_by         BIGINT      REFERENCES hr.system_users(id),
    detected_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE: los registros de merma no se editan
);

CREATE INDEX idx_merma_order    ON production.merma_records (production_order_id);
CREATE INDEX idx_merma_product  ON production.merma_records (product_id);
CREATE INDEX idx_merma_type     ON production.merma_records (merma_type);
CREATE INDEX idx_merma_sunat    ON production.merma_records (is_sunat_normal);
CREATE INDEX idx_merma_area     ON production.merma_records (area_id);
CREATE INDEX idx_merma_detected ON production.merma_records (detected_at);

COMMENT ON TABLE production.merma_records IS 'Registro de mermas por proceso/QC con clasificación SUNAT (normal/anormal, Art. 37 LIR). Cubre textil (corte), joyería (fundición), alimentos (cocción), manufactura (recortes).';

-- ============================================================
-- VIEW: Resumen de mermas por orden de producción
-- ============================================================
CREATE VIEW production.merma_by_order AS
SELECT
    m.production_order_id,
    m.company_id,
    m.product_id,
    COUNT(*)                                AS merma_events,
    SUM(m.quantity)                         AS total_merma_qty,
    ROUND(SUM(m.total_cost), 4)             AS total_merma_cost,
    ROUND(SUM(m.total_cost) FILTER (WHERE m.is_sunat_normal = TRUE), 4)
                                            AS costo_merma_deducible,
    ROUND(SUM(m.total_cost) FILTER (WHERE m.is_sunat_normal = FALSE), 4)
                                            AS costo_merma_no_deducible,
    ROUND(AVG(m.merma_pct), 4)              AS avg_merma_pct,
    STRING_AGG(DISTINCT m.merma_type, ', ' ORDER BY m.merma_type)
                                            AS merma_types
FROM production.merma_records m
GROUP BY m.production_order_id, m.company_id, m.product_id;

COMMENT ON VIEW production.merma_by_order IS 'Mermas agrupadas por OP: total, costo deducible vs no deducible (SUNAT Art. 37 LIR), promedio porcentual.';

-- ============================================================
-- VIEW: Mermas por área (para dashboard de área)
-- ============================================================
CREATE VIEW production.merma_by_area AS
SELECT
    a.id AS area_id,
    a.company_id,
    a.name AS area_name,
    DATE_TRUNC('month', m.detected_at) AS period_month,
    COUNT(*)                            AS merma_events,
    SUM(m.quantity)                     AS total_merma_qty,
    ROUND(SUM(m.total_cost), 4)         AS total_merma_cost,
    ROUND(AVG(m.merma_pct), 4)          AS avg_merma_pct
FROM production.merma_records m
JOIN production.production_areas a ON a.id = m.area_id
GROUP BY a.id, a.company_id, a.name, DATE_TRUNC('month', m.detected_at)
ORDER BY a.id, period_month DESC;

COMMENT ON VIEW production.merma_by_area IS 'Mermas por área por mes: permite identificar qué área genera más pérdidas.';
