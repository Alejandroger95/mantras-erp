-- ============================================================
-- mantrasdb | Módulo Production
-- Archivo: 01_bom.sql
-- Descripción: Bill of Materials universal
--
-- Diseñado para cualquier industria:
--   🏭 Manufactura       — BOM clásico multi-nivel
--   👗 Textil/Moda       — plan de corte, tallas, rendimiento tela
--   💎 Joyería           — metales preciosos, merma en fundición
--   🍎 Alimentos/Bebidas — recetas, % de ingredientes, HACCP
--   📱 Electrónica       — refabricación, componentes reutilizables
--   ♻️  Logística inversa — desarmado de retornos → nuevas piezas
--   🔧 Refurbishment     — recepción → clasificación → reparación
--
-- Módulos:
--   1. industry_profiles   — perfiles por tipo de industria
--   2. bom_headers         — cabecera BOM (cualquier tipo)
--   3. bom_versions        — versionado / ECO
--   4. bom_lines           — componentes / ingredientes
--   5. bom_substitutes     — materiales alternativos
--   6. bom_by_products     — subproductos, mermas, co-productos
--   7. configurable_options— opciones variables (tallas, colores, quilates)
--   8. disassembly_bom     — BOM inverso (retorno → componentes)
--   9. refurbishment_grades— grados de clasificación de retornos
-- ============================================================

CREATE SCHEMA IF NOT EXISTS production;

CREATE OR REPLACE FUNCTION production.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

-- ============================================================
-- 1. INDUSTRY PROFILES
--    Define el comportamiento del módulo por tipo de industria.
--    Cada empresa puede tener su perfil configurado.
-- ============================================================
CREATE TABLE production.industry_profiles (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL UNIQUE REFERENCES hr.companies(id),

    industry_type       VARCHAR(30) NOT NULL DEFAULT 'manufacturing',
    -- manufacturing   : industria general
    -- textile         : textil / moda / confección
    -- jewelry         : joyería / orfebrería
    -- food_beverage   : alimentos y bebidas
    -- electronics     : electrónica / tecnología
    -- chemical        : química / farmacéutica / cosmética
    -- construction    : construcción / materiales
    -- mixed           : múltiples industrias

    -- Terminología personalizada (UI labels)
    bom_label           VARCHAR(50) NOT NULL DEFAULT 'BOM',
    -- 'BOM', 'Receta', 'Fórmula', 'Patrón', 'Ficha Técnica'

    production_order_label VARCHAR(50) NOT NULL DEFAULT 'Orden de Producción',
    -- 'Orden de Producción', 'Orden de Confección', 'Lote'

    -- ¿Trackea metales preciosos? (joyería)
    track_precious_metals   BOOLEAN NOT NULL DEFAULT FALSE,

    -- ¿Usa plan de corte? (textil)
    use_cutting_plans       BOOLEAN NOT NULL DEFAULT FALSE,

    -- ¿Gestiona shelf life? (alimentos)
    track_shelf_life        BOOLEAN NOT NULL DEFAULT FALSE,

    -- ¿Permite BOM de desarmado (logística inversa)?
    allow_disassembly_bom   BOOLEAN NOT NULL DEFAULT TRUE,

    -- ¿Permite refurbishment/reacondicionamiento?
    allow_refurbishment     BOOLEAN NOT NULL DEFAULT TRUE,

    -- ¿Usa % de ingredientes (recetas)? vs cantidades fijas
    use_formula_pct         BOOLEAN NOT NULL DEFAULT FALSE,

    -- Precisión decimal para cantidades de producción
    quantity_decimals       SMALLINT NOT NULL DEFAULT 4,

    -- Unidad de peso por defecto (joyería: gramos, manufactura: kg)
    default_weight_uom_id   BIGINT  REFERENCES logistics.measurement_units(id),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_indprofile_updated_at
    BEFORE UPDATE ON production.industry_profiles
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

COMMENT ON TABLE production.industry_profiles IS 'Perfil de industria por empresa. Activa/desactiva features según el sector.';

-- ============================================================
-- 2. BOM HEADERS
--    Cabecera universal del BOM. Soporta:
--    - BOM de fabricación estándar (multi-nivel)
--    - BOM de desarmado / logística inversa (retorno → piezas)
--    - BOM de refurbishment (recepción → grado → reparación)
--    - Receta/Fórmula (alimentos, química)
--    - Plan de corte (textil)
--    - Configurables por variante (joyería, moda)
-- ============================================================
CREATE TABLE production.bom_headers (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Producto que se PRODUCE (o se DESARMA en caso de disassembly)
    product_id          BIGINT      NOT NULL REFERENCES logistics.products(id),
    product_variant_id  BIGINT      REFERENCES logistics.product_variants(id),
    -- NULL = aplica a todas las variantes

    code                VARCHAR(30) NOT NULL,
    name                VARCHAR(200) NOT NULL,
    description         TEXT,

    -- ── Tipo de BOM ──────────────────────────────────────────
    bom_type            VARCHAR(30) NOT NULL DEFAULT 'manufacturing',
    -- manufacturing   : BOM clásico (componentes → producto terminado)
    -- disassembly     : BOM inverso (producto retornado → componentes reutilizables)
    --                   Ej: iPhone trade-in → pantalla + batería + carcasa
    -- refurbishment   : reacondicionamiento (retorno → clasificación → reparado)
    --                   Ej: laptop usada → grado A/B/C → limpieza → prueba → venta
    -- phantom         : ensamble intermedio sin stock propio
    -- recipe          : fórmula porcentual (alimentos, cosmética, química)
    -- kit             : kit de venta (no genera ODP, se desglosa en Ventas)
    -- subcontract     : producción en maquila/subcontratación
    -- cutting_plan    : plan de corte textil (tela → piezas por talla)
    -- configurable    : BOM con opciones variables (joyería: 14k/18k, talla 6/7/8)

    -- ── Cantidades ────────────────────────────────────────────
    base_quantity       NUMERIC(18,6) NOT NULL DEFAULT 1,
    base_uom_id         BIGINT      REFERENCES logistics.measurement_units(id),

    -- Rendimiento del proceso (% de la cantidad que sale buena)
    -- ej: 92.00 = de 100 kg procesados, 92 kg son producto aceptable
    yield_pct           NUMERIC(7,4) NOT NULL DEFAULT 100.00,

    -- ── Para recetas (alimentos, química, cosmética) ──────────
    -- Si TRUE, las cantidades en bom_lines son porcentajes (suman 100%)
    is_formula_pct      BOOLEAN     NOT NULL DEFAULT FALSE,

    -- Tamaño de lote de fabricación
    lot_size_type       VARCHAR(20) NOT NULL DEFAULT 'variable',
    -- variable : cualquier cantidad
    -- fixed    : solo múltiplos de min_lot_size
    -- min      : mínimo min_lot_size
    min_lot_size        NUMERIC(18,6),
    max_lot_size        NUMERIC(18,6),

    -- ── Para textil ───────────────────────────────────────────
    -- Eficiencia del plan de corte (% de tela aprovechada)
    cutting_efficiency_pct  NUMERIC(7,4),

    -- ── Para joyería ─────────────────────────────────────────
    -- Pureza del metal base (750 = 18k, 585 = 14k, 925 = plata esterlina)
    metal_purity_thousandths SMALLINT,
    -- Pérdida por fundición esperada (%)
    casting_loss_pct    NUMERIC(7,4),

    -- ── Control ───────────────────────────────────────────────
    active_version_id   BIGINT,
    -- FK diferida → bom_versions(id)

    warehouse_id        BIGINT      REFERENCES logistics.warehouses(id),
    -- NULL = aplica a todas las plantas

    status              VARCHAR(20) NOT NULL DEFAULT 'draft',
    -- draft / active / obsolete / archived

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE INDEX idx_bom_product  ON production.bom_headers (product_id);
CREATE INDEX idx_bom_company  ON production.bom_headers (company_id);
CREATE INDEX idx_bom_type     ON production.bom_headers (bom_type);

CREATE TRIGGER trg_bom_updated_at
    BEFORE UPDATE ON production.bom_headers
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

COMMENT ON TABLE production.bom_headers IS 'BOM universal: manufactura, desarmado, refurbishment, recetas, plan de corte, configurables.';

-- ============================================================
-- 3. BOM VERSIONS (Engineering Change Orders)
-- ============================================================
CREATE TABLE production.bom_versions (
    id                  BIGSERIAL   PRIMARY KEY,
    bom_header_id       BIGINT      NOT NULL REFERENCES production.bom_headers(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    version_number      SMALLINT    NOT NULL DEFAULT 1,
    version_name        VARCHAR(50),

    change_reason       TEXT,
    eco_number          VARCHAR(50),
    -- Engineering Change Order (nro de cambio de ingeniería)

    valid_from          DATE        NOT NULL DEFAULT CURRENT_DATE,
    valid_to            DATE,

    status              VARCHAR(20) NOT NULL DEFAULT 'draft',
    -- draft / active / superseded / obsolete

    approved_by         BIGINT      REFERENCES hr.system_users(id),
    approved_at         TIMESTAMPTZ,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (bom_header_id, version_number)
);

CREATE TRIGGER trg_bomver_updated_at
    BEFORE UPDATE ON production.bom_versions
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

-- FK diferida active_version_id
ALTER TABLE production.bom_headers
    ADD CONSTRAINT fk_bom_active_version
    FOREIGN KEY (active_version_id) REFERENCES production.bom_versions(id)
    DEFERRABLE INITIALLY DEFERRED;

-- ============================================================
-- 4. BOM LINES (Componentes / Ingredientes)
-- ============================================================
CREATE TABLE production.bom_lines (
    id                  BIGSERIAL   PRIMARY KEY,
    bom_version_id      BIGINT      NOT NULL REFERENCES production.bom_versions(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    component_product_id    BIGINT  NOT NULL REFERENCES logistics.products(id),
    component_variant_id    BIGINT  REFERENCES logistics.product_variants(id),

    sequence            SMALLINT    NOT NULL DEFAULT 10,

    -- Cantidad fija (cuando is_formula_pct = FALSE en el BOM)
    quantity            NUMERIC(18,6) NOT NULL DEFAULT 0,
    uom_id              BIGINT      REFERENCES logistics.measurement_units(id),

    -- % del total de la fórmula (cuando is_formula_pct = TRUE)
    formula_pct         NUMERIC(7,4),

    -- Merma esperada por componente
    scrap_pct           NUMERIC(7,4) NOT NULL DEFAULT 0,

    component_type      VARCHAR(20) NOT NULL DEFAULT 'component',
    -- component   : materia prima o semi-terminado
    -- phantom     : ensamble intermedio (se explota)
    -- by_product  : subproducto generado
    -- co_product  : co-producto
    -- packaging   : empaque y embalaje
    -- tool        : herramienta (no se consume)
    -- overhead    : costo indirecto (agua, energía)

    consumption_method  VARCHAR(20) NOT NULL DEFAULT 'manual',
    -- manual    : operario registra el consumo
    -- backflush : descuento automático al cerrar OP
    -- pick_list : almacén genera lista de picking

    -- Multi-nivel: referencia al BOM del componente (phantom / semi-terminado)
    sub_bom_id          BIGINT      REFERENCES production.bom_headers(id),
    bom_level           SMALLINT    NOT NULL DEFAULT 1,

    -- ── Para joyería ─────────────────────────────────────────
    -- Peso del metal precioso en este componente
    metal_weight_grams  NUMERIC(10,4),
    metal_purity        NUMERIC(7,4),
    -- Ej: 18.5g de oro a 750 (18k)

    -- ── Para textil ───────────────────────────────────────────
    -- Ancho del rollo y cantidad de tela por pieza
    fabric_width_cm     NUMERIC(8,2),
    fabric_per_piece    NUMERIC(10,4),

    -- ── Flags ─────────────────────────────────────────────────
    is_optional         BOOLEAN     NOT NULL DEFAULT FALSE,
    has_substitutes     BOOLEAN     NOT NULL DEFAULT FALSE,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_bomline_version   ON production.bom_lines (bom_version_id);
CREATE INDEX idx_bomline_component ON production.bom_lines (component_product_id);

CREATE TRIGGER trg_bomline_updated_at
    BEFORE UPDATE ON production.bom_lines
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

COMMENT ON TABLE production.bom_lines IS 'Componentes universales: soporta fórmulas %, metales preciosos, telas, backflush y multi-nivel.';

-- ============================================================
-- 5. BOM SUBSTITUTES
-- ============================================================
CREATE TABLE production.bom_substitutes (
    id                  BIGSERIAL   PRIMARY KEY,
    bom_line_id         BIGINT      NOT NULL REFERENCES production.bom_lines(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    substitute_product_id  BIGINT  NOT NULL REFERENCES logistics.products(id),
    substitute_variant_id  BIGINT  REFERENCES logistics.product_variants(id),

    conversion_factor   NUMERIC(10,6) NOT NULL DEFAULT 1.0,
    priority            SMALLINT    NOT NULL DEFAULT 1,

    -- Condición de uso del sustituto
    use_condition       VARCHAR(20) NOT NULL DEFAULT 'stock_out',
    -- stock_out    : usar cuando el principal no tiene stock
    -- always       : siempre usar este sustituto (reemplazó al principal)
    -- manual       : el planificador decide manualmente

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 6. BY-PRODUCTS (Subproductos / Co-productos / Mermas SUNAT)
-- ============================================================
CREATE TABLE production.bom_by_products (
    id                  BIGSERIAL   PRIMARY KEY,
    bom_version_id      BIGINT      NOT NULL REFERENCES production.bom_versions(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    by_product_type     VARCHAR(20) NOT NULL DEFAULT 'by_product',
    -- by_product  : subproducto secundario
    -- co_product  : co-producto de igual importancia
    -- scrap       : merma recuperable (tiene valor)
    -- waste       : desecho sin valor comercial
    -- rework      : material para reprocesar

    product_id          BIGINT      NOT NULL REFERENCES logistics.products(id),
    variant_id          BIGINT      REFERENCES logistics.product_variants(id),

    quantity            NUMERIC(18,6) NOT NULL,
    uom_id              BIGINT      REFERENCES logistics.measurement_units(id),

    cost_allocation_pct NUMERIC(7,4) NOT NULL DEFAULT 0,
    -- % del costo total absorbido por este co-producto

    -- Para SUNAT Perú — mermas acreditadas (Art. 37 LIR)
    is_sunat_merma      BOOLEAN     NOT NULL DEFAULT FALSE,
    sunat_merma_pct     NUMERIC(7,4),
    -- % merma declarada ante SUNAT (requiere informe técnico)
    sunat_merma_type    VARCHAR(20),
    -- normal    : merma inherente al proceso
    -- accidental: pérdida fortuita

    location_id         BIGINT      REFERENCES logistics.locations(id),

    notes               TEXT,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE production.bom_by_products IS 'Subproductos y mermas. Soporte especial para mermas SUNAT (Art. 37 LIR, informe técnico).';

-- ============================================================
-- 7. CONFIGURABLE BOM OPTIONS
--    Para productos con variantes complejas donde el BOM cambia
--    según la opción elegida.
--
--    Ej Joyería: anillo base → opción "quilates" (14k/18k/22k)
--                           → opción "talla" (6/7/8/9/10)
--                           → opción "piedra" (ninguna/rubí/esmeralda)
--
--    Ej Textil: camiseta → opción "talla" (XS/S/M/L/XL)
--                        → opción "color" (blanco/negro/rojo)
--
--    Cada combinación puede modificar cantidades de componentes.
-- ============================================================
CREATE TABLE production.bom_config_attributes (
    id                  BIGSERIAL   PRIMARY KEY,
    bom_header_id       BIGINT      NOT NULL REFERENCES production.bom_headers(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    attribute_name      VARCHAR(50) NOT NULL,
    -- 'Talla', 'Color', 'Quilates', 'Piedra', 'Material'

    attribute_type      VARCHAR(20) NOT NULL DEFAULT 'selection',
    -- selection  : lista de opciones (tallas, colores)
    -- numeric    : valor numérico (peso, longitud)

    is_required         BOOLEAN     NOT NULL DEFAULT TRUE,
    sequence            SMALLINT    NOT NULL DEFAULT 10,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE production.bom_config_values (
    id                  BIGSERIAL   PRIMARY KEY,
    attribute_id        BIGINT      NOT NULL REFERENCES production.bom_config_attributes(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    value_code          VARCHAR(30) NOT NULL,
    -- 'XS', 'S', 'M', 'L', 'XL', '14K', '18K', '6', '7', '8'

    value_label         VARCHAR(100) NOT NULL,
    sequence            SMALLINT    NOT NULL DEFAULT 10,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE production.bom_line_config_overrides (
    -- Cuando se elige una opción, esta tabla dice cómo cambia
    -- la cantidad de un componente.
    id                  BIGSERIAL   PRIMARY KEY,
    bom_line_id         BIGINT      NOT NULL REFERENCES production.bom_lines(id) ON DELETE CASCADE,
    config_value_id     BIGINT      NOT NULL REFERENCES production.bom_config_values(id),

    -- Reemplaza la cantidad de la línea base
    quantity_override   NUMERIC(18,6),
    -- Si NULL: la línea no cambia con esta opción

    -- Activa o desactiva el componente para esta opción
    is_active_for_option BOOLEAN    NOT NULL DEFAULT TRUE,
    -- ej: la piedra "ninguna" desactiva las líneas de engaste

    formula_pct_override NUMERIC(7,4),
    -- Para recetas: % que cambia con la opción

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (bom_line_id, config_value_id)
);

COMMENT ON TABLE production.bom_config_attributes IS 'Atributos configurables del BOM (talla, quilates, color, etc.). Para joyería y textil principalmente.';

-- ============================================================
-- 8. DISASSEMBLY BOM (BOM de Desarmado / Logística Inversa)
--    El proceso INVERSO de manufactura:
--    ENTRADA: 1 producto retornado (usado, roto, trade-in)
--    SALIDA:  N componentes recuperados para reutilizar
--
--    Ejemplo Apple trade-in:
--    - iPhone 13 retornado → pantalla OLED + batería + cámara + carcasa + SIM tray
--    - Componentes buenos → inventario para reparaciones
--    - Componentes malos → desecho / reciclaje
--
--    Ejemplo Joyería:
--    - Collar de oro retornado → fundir → lingote de oro → nuevo BOM
-- ============================================================
CREATE TABLE production.disassembly_bom (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Producto que ENTRA al desarmado (el retorno)
    input_product_id    BIGINT      NOT NULL REFERENCES logistics.products(id),
    input_variant_id    BIGINT      REFERENCES logistics.product_variants(id),

    code                VARCHAR(30) NOT NULL,
    name                VARCHAR(200) NOT NULL,

    -- Origen típico del retorno
    input_source        VARCHAR(20) NOT NULL DEFAULT 'return',
    -- return      : devolución de cliente
    -- trade_in    : programa de intercambio (Apple trade-in, etc.)
    -- end_of_life : fin de vida útil (reciclaje)
    -- warranty    : retorno por garantía
    -- internal    : retiro de producción (reproceso)

    -- Rendimiento del proceso de desarmado (% recuperable)
    recovery_yield_pct  NUMERIC(7,4) NOT NULL DEFAULT 80.00,

    status              VARCHAR(20) NOT NULL DEFAULT 'active',
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE TRIGGER trg_disbom_updated_at
    BEFORE UPDATE ON production.disassembly_bom
    FOR EACH ROW EXECUTE FUNCTION production.set_updated_at();

-- Componentes que SE RECUPERAN del desarmado
CREATE TABLE production.disassembly_bom_outputs (
    id                  BIGSERIAL   PRIMARY KEY,
    disassembly_bom_id  BIGINT      NOT NULL REFERENCES production.disassembly_bom(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    -- Componente que se recupera
    output_product_id   BIGINT      NOT NULL REFERENCES logistics.products(id),
    output_variant_id   BIGINT      REFERENCES logistics.product_variants(id),

    -- Cantidad esperada a recuperar por unidad de entrada
    expected_quantity   NUMERIC(18,6) NOT NULL,
    uom_id              BIGINT      REFERENCES logistics.measurement_units(id),

    -- Tasa de recuperación (% que sale en condición reutilizable)
    recovery_rate_pct   NUMERIC(7,4) NOT NULL DEFAULT 100.00,

    output_type         VARCHAR(20) NOT NULL DEFAULT 'component',
    -- component   : componente reutilizable → inventario de piezas
    -- material    : material recuperado (metal, plástico) → inventario MP
    -- scrap       : desecho → disposición
    -- hazardous   : residuo peligroso → gestión especial

    -- Calidad esperada del componente recuperado
    expected_grade      VARCHAR(10),
    -- 'A', 'B', 'C', 'Scrap'

    -- ¿Requiere prueba antes de entrar a inventario?
    requires_testing    BOOLEAN     NOT NULL DEFAULT FALSE,

    -- Destino del componente recuperado
    target_location_id  BIGINT      REFERENCES logistics.locations(id),

    sequence            SMALLINT    NOT NULL DEFAULT 10,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    notes               TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE production.disassembly_bom IS 'BOM inverso para logística inversa / trade-in / reciclaje. Define qué componentes se recuperan de un producto retornado.';

-- ============================================================
-- 9. REFURBISHMENT GRADES (Grados de Clasificación)
--    Estándar de calidad para clasificar productos retornados
--    antes y después del proceso de reacondicionamiento.
--
--    Ej electrónica: Grado A = como nuevo, B = marcas leves,
--                    C = funcional con daños visibles, D = solo piezas
--    Ej ropa: Nuevo c/etiqueta, Excelente, Bueno, Regular, Defectuoso
--    Ej autos: Certificado, Excelente, Aceptable, Solo repuestos
-- ============================================================
CREATE TABLE production.refurbishment_grade_scales (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    code                VARCHAR(20) NOT NULL,
    name                VARCHAR(100) NOT NULL,
    -- 'Electrónica GRADE', 'Ropa Grado', 'Joyas Condición'

    description         TEXT,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE TABLE production.refurbishment_grades (
    id                  BIGSERIAL   PRIMARY KEY,
    grade_scale_id      BIGINT      NOT NULL REFERENCES production.refurbishment_grade_scales(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    grade_code          VARCHAR(10) NOT NULL,
    -- 'A', 'B', 'C', 'D', 'SCRAP', 'NL' (nuevo con etiqueta)

    grade_name          VARCHAR(100) NOT NULL,
    description         TEXT,

    -- ¿Se puede vender? ¿Con descuento?
    is_sellable         BOOLEAN     NOT NULL DEFAULT TRUE,
    discount_pct        NUMERIC(7,4) NOT NULL DEFAULT 0,
    -- Descuento sobre precio nuevo por grado

    -- ¿Requiere reparación antes de vender?
    requires_repair     BOOLEAN     NOT NULL DEFAULT FALSE,

    -- ¿Requiere certificado de pruebas?
    requires_test_cert  BOOLEAN     NOT NULL DEFAULT FALSE,

    sequence            SMALLINT    NOT NULL DEFAULT 10,
    -- Orden de calidad (1 = mejor)

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (grade_scale_id, grade_code)
);

COMMENT ON TABLE production.refurbishment_grades IS 'Escalas de grados para clasificar retornos: A/B/C/D electrónica, NL/Excelente/Bueno ropa, etc.';
