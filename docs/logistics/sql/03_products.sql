-- ============================================================
-- mantrasdb | Módulo Logistics
-- Archivo: 03_products.sql
-- Descripción: Maestro de productos — catálogo completo con
--              jerarquía de categorías, familias, variantes,
--              unidades de medida y códigos de barras.
-- ============================================================

-- ============================================================
-- Categorías de producto (jerarquía multinivel)
-- ============================================================
CREATE TABLE logistics.product_categories (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    parent_id       BIGINT          REFERENCES logistics.product_categories(id),
    -- NULL = categoría raíz. Ej: Electrónica > Celulares > Smartphones

    code            VARCHAR(50)     NOT NULL,
    name            VARCHAR(200)    NOT NULL,
    description     TEXT,
    image_url       VARCHAR(500),

    -- Nivel en la jerarquía (1=raíz, 2=subcategoría, etc.)
    level           INTEGER         NOT NULL DEFAULT 1,

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE INDEX idx_product_categories_company  ON logistics.product_categories (company_id);
CREATE INDEX idx_product_categories_parent   ON logistics.product_categories (parent_id);

CREATE TRIGGER trg_product_categories_updated_at
    BEFORE UPDATE ON logistics.product_categories
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.product_categories           IS 'Jerarquía de categorías de productos. Soporta múltiples niveles vía parent_id.';
COMMENT ON COLUMN logistics.product_categories.parent_id IS 'NULL = categoría raíz. Permite árbol de categorías de cualquier profundidad.';

-- ============================================================
-- Familias de producto
-- ============================================================
CREATE TABLE logistics.product_families (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    category_id     BIGINT          REFERENCES logistics.product_categories(id),

    code            VARCHAR(50)     NOT NULL,
    name            VARCHAR(200)    NOT NULL,
    description     TEXT,

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE INDEX idx_product_families_company  ON logistics.product_families (company_id);

CREATE TRIGGER trg_product_families_updated_at
    BEFORE UPDATE ON logistics.product_families
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.product_families IS 'Agrupación de productos por familia dentro de una categoría.';

-- ============================================================
-- Unidades de medida
-- ============================================================
CREATE TABLE logistics.measurement_units (
    id              SERIAL          PRIMARY KEY,
    company_id      BIGINT          REFERENCES hr.companies(id),
    -- NULL = unidad global del sistema

    code            VARCHAR(20)     NOT NULL,
    -- UN, KG, LT, MT, M2, M3, BOX, PAL, etc.
    name            VARCHAR(100)    NOT NULL,
    unit_type       VARCHAR(30)     NOT NULL DEFAULT 'unit',
    -- unit | weight | volume | length | area | time

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

INSERT INTO logistics.measurement_units (code, name, unit_type) VALUES
    ('UN',   'Unidad',           'unit'),
    ('PAR',  'Par',              'unit'),
    ('DOC',  'Docena',           'unit'),
    ('CJA',  'Caja',            'unit'),
    ('PAL',  'Pallet',          'unit'),
    ('PKT',  'Paquete',         'unit'),
    ('KG',   'Kilogramo',       'weight'),
    ('G',    'Gramo',           'weight'),
    ('TN',   'Tonelada',        'weight'),
    ('LB',   'Libra',           'weight'),
    ('LT',   'Litro',           'volume'),
    ('ML',   'Mililitro',       'volume'),
    ('M3',   'Metro cúbico',    'volume'),
    ('MT',   'Metro',           'length'),
    ('CM',   'Centímetro',      'length'),
    ('M2',   'Metro cuadrado',  'area');

COMMENT ON TABLE logistics.measurement_units IS 'Catálogo de unidades de medida: unidad, peso, volumen, longitud.';

-- ============================================================
-- Conversiones entre unidades
-- ============================================================
CREATE TABLE logistics.unit_conversions (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id),
    from_unit_id        INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),
    to_unit_id          INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),
    conversion_factor   NUMERIC(18,8)   NOT NULL,
    -- Ej: 1 CJA = 12 UN → factor = 12
    notes               TEXT,

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, from_unit_id, to_unit_id)
);

COMMENT ON TABLE logistics.unit_conversions IS 'Conversiones entre unidades: 1 caja = 12 unidades, 1 pallet = 60 cajas, etc.';

-- ============================================================
-- Productos (maestro / SKU)
-- ============================================================
CREATE TABLE logistics.products (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    category_id         BIGINT          REFERENCES logistics.product_categories(id),
    family_id           BIGINT          REFERENCES logistics.product_families(id),

    -- Identificación
    sku                 VARCHAR(100)    NOT NULL,
    -- Stock Keeping Unit — código interno único
    name                VARCHAR(300)    NOT NULL,
    description         TEXT,
    short_description   VARCHAR(500),
    internal_code       VARCHAR(100),
    -- código interno adicional (legado, contabilidad, etc.)

    -- Unidades
    base_unit_id        INTEGER         NOT NULL REFERENCES logistics.measurement_units(id),
    -- unidad de almacenamiento base (UN, KG, LT...)
    purchase_unit_id    INTEGER         REFERENCES logistics.measurement_units(id),
    -- unidad de compra (puede diferir, ej: compra en CJA, almacena en UN)
    sales_unit_id       INTEGER         REFERENCES logistics.measurement_units(id),
    -- unidad de venta

    -- Dimensiones físicas (para cálculo de almacenaje y transporte)
    weight_kg           NUMERIC(10,4),
    length_cm           NUMERIC(8,2),
    width_cm            NUMERIC(8,2),
    height_cm           NUMERIC(8,2),
    volume_m3           NUMERIC(10,6)
        GENERATED ALWAYS AS (
            CASE WHEN length_cm IS NOT NULL AND width_cm IS NOT NULL AND height_cm IS NOT NULL
                 THEN ROUND((length_cm * width_cm * height_cm / 1000000)::NUMERIC, 6)
                 ELSE NULL END
        ) STORED,
    -- volumen calculado automáticamente en m³

    -- Costos y precios
    cost                NUMERIC(18,4),
    -- costo promedio ponderado actual
    list_price          NUMERIC(18,4),
    currency            VARCHAR(10)     NOT NULL DEFAULT 'PEN',

    -- Control de inventario
    is_serialized       BOOLEAN         NOT NULL DEFAULT FALSE,
    -- TRUE = requiere número de serie por unidad
    is_lot_tracked      BOOLEAN         NOT NULL DEFAULT FALSE,
    -- TRUE = requiere número de lote
    is_perishable       BOOLEAN         NOT NULL DEFAULT FALSE,
    -- TRUE = tiene fecha de vencimiento
    shelf_life_days     INTEGER,
    -- días de vida útil desde fabricación

    -- Umbrales de stock
    min_stock           NUMERIC(18,4)   DEFAULT 0,
    max_stock           NUMERIC(18,4),
    reorder_point       NUMERIC(18,4),
    -- cuando el stock cae a este nivel, se genera alerta de reabastecimiento
    reorder_qty         NUMERIC(18,4),
    -- cantidad sugerida a ordenar

    -- Estrategia de almacenaje
    picking_strategy    VARCHAR(20)     NOT NULL DEFAULT 'FEFO',
    -- FIFO | FEFO | LIFO
    -- FIFO = primera entrada primera salida
    -- FEFO = primera en vencer primera salida (para perecederos)
    -- LIFO = última entrada primera salida

    -- Clasificación ABC por rotación
    abc_classification  VARCHAR(1),
    -- A=alta rotación, B=media, C=baja

    -- Multimedia
    image_url           VARCHAR(500),

    -- Tipo (para kits)
    is_kit              BOOLEAN         NOT NULL DEFAULT FALSE,

    -- Control
    is_purchasable      BOOLEAN         NOT NULL DEFAULT TRUE,
    is_saleable         BOOLEAN         NOT NULL DEFAULT TRUE,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    notes               TEXT,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, sku)
);

CREATE INDEX idx_products_company     ON logistics.products (company_id);
CREATE INDEX idx_products_category    ON logistics.products (category_id);
CREATE INDEX idx_products_sku         ON logistics.products (company_id, sku);
CREATE INDEX idx_products_active      ON logistics.products (company_id) WHERE is_active = TRUE;

CREATE TRIGGER trg_products_updated_at
    BEFORE UPDATE ON logistics.products
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE  logistics.products                    IS 'Maestro de productos (SKU). Centro del módulo de logística.';
COMMENT ON COLUMN logistics.products.sku                IS 'Stock Keeping Unit — código único de identificación del producto.';
COMMENT ON COLUMN logistics.products.volume_m3          IS 'Volumen calculado automáticamente: largo × ancho × alto ÷ 1,000,000.';
COMMENT ON COLUMN logistics.products.picking_strategy   IS 'FIFO: primera entrada primera salida. FEFO: primero en vencer. LIFO: última entrada primera salida.';
COMMENT ON COLUMN logistics.products.reorder_point      IS 'Nivel de stock que dispara alerta de reabastecimiento.';
COMMENT ON COLUMN logistics.products.abc_classification IS 'A=alta rotación (20% productos, 80% movimientos), B=media, C=baja rotación.';

-- ============================================================
-- Variantes de producto (talla, color, etc.)
-- ============================================================
CREATE TABLE logistics.product_variants (
    id              BIGSERIAL       PRIMARY KEY,
    product_id      BIGINT          NOT NULL REFERENCES logistics.products(id) ON DELETE RESTRICT,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id),

    sku_variant     VARCHAR(150)    NOT NULL,
    -- SKU de la variante: CAMISA-001-ROJO-M
    name            VARCHAR(300)    NOT NULL,

    -- Atributos de variante (flexible)
    attribute_1_name  VARCHAR(50),   -- "Color"
    attribute_1_value VARCHAR(100),  -- "Rojo"
    attribute_2_name  VARCHAR(50),   -- "Talla"
    attribute_2_value VARCHAR(100),  -- "M"
    attribute_3_name  VARCHAR(50),
    attribute_3_value VARCHAR(100),

    -- Diferencias físicas respecto al producto base
    weight_kg       NUMERIC(10,4),
    cost            NUMERIC(18,4),
    list_price      NUMERIC(18,4),
    image_url       VARCHAR(500),

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, sku_variant)
);

CREATE INDEX idx_product_variants_product ON logistics.product_variants (product_id);

CREATE TRIGGER trg_product_variants_updated_at
    BEFORE UPDATE ON logistics.product_variants
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.product_variants IS 'Variantes de un mismo producto: talla, color, modelo. Cada variante tiene su propio SKU.';

-- ============================================================
-- Códigos de barras por producto
-- ============================================================
CREATE TABLE logistics.product_barcodes (
    id              BIGSERIAL       PRIMARY KEY,
    product_id      BIGINT          NOT NULL REFERENCES logistics.products(id) ON DELETE RESTRICT,
    variant_id      BIGINT          REFERENCES logistics.product_variants(id),
    -- NULL si aplica al producto base, no a una variante específica

    barcode_type    VARCHAR(30)     NOT NULL DEFAULT 'EAN13',
    -- EAN13 | EAN8 | UPC | QR | CODE128 | ITF14 | DATAMATRIX
    barcode         VARCHAR(200)    NOT NULL,
    unit_id         INTEGER         REFERENCES logistics.measurement_units(id),
    -- a qué unidad representa este código (UN, CJA, PAL)

    is_primary      BOOLEAN         NOT NULL DEFAULT FALSE,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_product_barcodes_unique
    ON logistics.product_barcodes (barcode) WHERE is_active = TRUE;
CREATE INDEX idx_product_barcodes_product ON logistics.product_barcodes (product_id);

COMMENT ON TABLE logistics.product_barcodes IS 'Códigos de barras por producto y unidad. Permite múltiples tipos: EAN13, UPC, QR, CODE128.';

-- ============================================================
-- Relación producto-proveedor
-- ============================================================
CREATE TABLE logistics.product_suppliers (
    id                  BIGSERIAL       PRIMARY KEY,
    product_id          BIGINT          NOT NULL REFERENCES logistics.products(id) ON DELETE RESTRICT,
    supplier_id         BIGINT          NOT NULL REFERENCES logistics.suppliers(id) ON DELETE RESTRICT,

    supplier_sku        VARCHAR(150),
    -- código que usa el proveedor para este producto
    supplier_name       VARCHAR(300),
    -- nombre que usa el proveedor para este producto

    -- Condiciones
    purchase_unit_id    INTEGER         REFERENCES logistics.measurement_units(id),
    min_order_qty       NUMERIC(18,4)   DEFAULT 1,
    lead_time_days      INTEGER,
    last_cost           NUMERIC(18,4),
    currency            VARCHAR(10)     DEFAULT 'PEN',

    is_preferred        BOOLEAN         NOT NULL DEFAULT FALSE,
    -- TRUE = proveedor preferido para este producto
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (product_id, supplier_id)
);

CREATE INDEX idx_product_suppliers_product  ON logistics.product_suppliers (product_id);
CREATE INDEX idx_product_suppliers_supplier ON logistics.product_suppliers (supplier_id);

CREATE TRIGGER trg_product_suppliers_updated_at
    BEFORE UPDATE ON logistics.product_suppliers
    FOR EACH ROW EXECUTE FUNCTION logistics.set_updated_at();

COMMENT ON TABLE logistics.product_suppliers IS 'Qué proveedores suministran cada producto, con su SKU propio, precio y lead time.';
