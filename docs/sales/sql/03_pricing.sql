-- ============================================================
-- mantrasdb | Módulo Sales
-- Archivo: 03_pricing.sql
-- Descripción: Listas de precios, reglas de descuento y
--              condiciones de pago.
--
-- Flujo de precio en una orden:
--   1. Buscar price_list_item para (product, unit, price_list)
--   2. Aplicar discount_rules que apliquen (cliente, grupo, volumen)
--   3. Precio final = precio_lista × (1 - descuento_total)
-- ============================================================

-- ============================================================
-- Listas de precios
-- ============================================================
CREATE TABLE sales.price_lists (
    id              BIGSERIAL   PRIMARY KEY,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    code            VARCHAR(30) NOT NULL,
    name            VARCHAR(200) NOT NULL,
    description     TEXT,

    currency        VARCHAR(10) NOT NULL DEFAULT 'PEN',
    -- PEN | USD | EUR

    -- Vigencia
    valid_from      DATE,
    valid_to        DATE,

    -- ¿Es la lista por defecto?
    is_default      BOOLEAN     NOT NULL DEFAULT FALSE,

    -- ¿Incluye IGV en los precios?
    prices_include_tax  BOOLEAN NOT NULL DEFAULT FALSE,
    -- TRUE = precios ya incluyen IGV | FALSE = precios son netos

    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE INDEX idx_price_lists_company ON sales.price_lists (company_id);

CREATE TRIGGER trg_price_lists_updated_at
    BEFORE UPDATE ON sales.price_lists
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.price_lists                     IS 'Listas de precios por moneda y vigencia. Un cliente puede tener asignada una lista específica.';
COMMENT ON COLUMN sales.price_lists.prices_include_tax  IS 'TRUE = precio ya incluye IGV (precio de vitrina). FALSE = precio neto + IGV.';

-- ============================================================
-- Ítems de lista de precios (precio por producto)
-- ============================================================
CREATE TABLE sales.price_list_items (
    id              BIGSERIAL   PRIMARY KEY,
    price_list_id   BIGINT      NOT NULL REFERENCES sales.price_lists(id) ON DELETE RESTRICT,
    product_id      BIGINT      NOT NULL REFERENCES logistics.products(id),
    variant_id      BIGINT      REFERENCES logistics.product_variants(id),
    unit_id         INTEGER     NOT NULL REFERENCES logistics.measurement_units(id),

    price           NUMERIC(18,6) NOT NULL,
    -- precio por unidad en la moneda de la lista

    -- Precio mínimo (no se puede vender por debajo)
    min_price       NUMERIC(18,6),

    -- Vigencia específica de este ítem (si difiere de la lista)
    valid_from      DATE,
    valid_to        DATE,

    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (price_list_id, product_id, variant_id, unit_id)
);

CREATE INDEX idx_price_items_list    ON sales.price_list_items (price_list_id);
CREATE INDEX idx_price_items_product ON sales.price_list_items (product_id);

CREATE TRIGGER trg_price_items_updated_at
    BEFORE UPDATE ON sales.price_list_items
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE sales.price_list_items IS 'Precio de cada producto por lista. UNIQUE en (lista, producto, variante, unidad).';

-- ============================================================
-- Asignación de lista de precios a cliente / grupo
-- ============================================================
CREATE TABLE sales.customer_price_list_assignments (
    id              BIGSERIAL   PRIMARY KEY,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    price_list_id   BIGINT      NOT NULL REFERENCES sales.price_lists(id),

    -- Asignar a cliente específico o a grupo completo
    customer_id     BIGINT      REFERENCES sales.customers(id),
    customer_group_id BIGINT    REFERENCES sales.customer_groups(id),

    valid_from      DATE,
    valid_to        DATE,
    priority        INTEGER     NOT NULL DEFAULT 100,
    -- menor número = mayor prioridad (cliente específico > grupo)

    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_cpla_customer ON sales.customer_price_list_assignments (customer_id);
CREATE INDEX idx_cpla_group    ON sales.customer_price_list_assignments (customer_group_id);

COMMENT ON TABLE sales.customer_price_list_assignments IS 'Qué lista de precios aplica a qué cliente o grupo. Priority determina cuál gana si hay más de una.';

-- ============================================================
-- Reglas de descuento
-- ============================================================
CREATE TABLE sales.discount_rules (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    discount_type_id    INTEGER     NOT NULL REFERENCES sales.discount_types(id),

    name                VARCHAR(200) NOT NULL,
    description         TEXT,

    -- Criterios de aplicación (se puede combinar)
    customer_id         BIGINT      REFERENCES sales.customers(id),
    customer_group_id   BIGINT      REFERENCES sales.customer_groups(id),
    product_id          BIGINT      REFERENCES logistics.products(id),
    category_id         BIGINT      REFERENCES logistics.product_categories(id),

    -- Condición de volumen
    min_quantity        NUMERIC(18,4),
    -- aplica solo si la línea tiene >= esta cantidad
    min_amount          NUMERIC(18,4),
    -- aplica solo si el total de la orden >= este monto

    -- Descuento
    discount_pct        NUMERIC(5,2),
    -- porcentaje de descuento (0-100)
    discount_amount     NUMERIC(18,4),
    -- monto fijo de descuento (alternativo a %)

    -- Vigencia
    valid_from          DATE,
    valid_to            DATE,

    priority            INTEGER     NOT NULL DEFAULT 100,
    -- menor número = mayor prioridad
    is_cumulative       BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE = se suma a otros descuentos | FALSE = excluye otros

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_discount_rules_company  ON sales.discount_rules (company_id);
CREATE INDEX idx_discount_rules_customer ON sales.discount_rules (customer_id);
CREATE INDEX idx_discount_rules_product  ON sales.discount_rules (product_id);

CREATE TRIGGER trg_discount_rules_updated_at
    BEFORE UPDATE ON sales.discount_rules
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.discount_rules              IS 'Reglas de descuento por cliente, grupo, producto o categoría. Soporta % o monto fijo.';
COMMENT ON COLUMN sales.discount_rules.is_cumulative IS 'TRUE = se acumula con otros descuentos. FALSE = la regla de mayor prioridad gana y excluye las demás.';

-- ============================================================
-- Condiciones de pago (catálogo)
-- ============================================================
CREATE TABLE sales.payment_terms_catalog (
    id              SERIAL      PRIMARY KEY,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    code            VARCHAR(30) NOT NULL,
    name            VARCHAR(100) NOT NULL,
    description     TEXT,

    -- Configuración
    days            INTEGER     NOT NULL DEFAULT 0,
    -- número de días de crédito (0 = contado)
    is_installment  BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE = pago en cuotas

    -- Para pagos en cuotas (JSONB flexible)
    installment_config JSONB,
    -- Ej: [{"pct": 30, "days": 0}, {"pct": 70, "days": 30}]
    -- 30% al contado, 70% a 30 días

    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE TRIGGER trg_payment_terms_updated_at
    BEFORE UPDATE ON sales.payment_terms_catalog
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

-- Datos pre-cargados para Perú
-- (company_id se asignará al configurar la empresa)
COMMENT ON TABLE  sales.payment_terms_catalog              IS 'Catálogo de condiciones de pago: contado, 30d, 60d, 30/70, cuotas.';
COMMENT ON COLUMN sales.payment_terms_catalog.installment_config IS 'JSON con cuotas: [{pct: 50, days: 0}, {pct: 50, days: 30}] = 50% ahora, 50% a 30 días.';

-- ============================================================
-- Impuestos (tasas aplicables)
-- ============================================================
CREATE TABLE sales.tax_rates (
    id              SERIAL      PRIMARY KEY,
    company_id      BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    code            VARCHAR(20) NOT NULL,
    name            VARCHAR(100) NOT NULL,
    -- "IGV 18%", "ISC 10%", "Exonerado", "Inafecto"

    tax_type        VARCHAR(20) NOT NULL DEFAULT 'VAT',
    -- VAT | excise | withholding | exempt | zero

    rate_pct        NUMERIC(5,2) NOT NULL DEFAULT 0,
    -- porcentaje (18 para IGV peruano)

    sunat_code      VARCHAR(10),
    -- código SUNAT del tipo de afectación del IGV

    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE TRIGGER trg_tax_rates_updated_at
    BEFORE UPDATE ON sales.tax_rates
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.tax_rates          IS 'Tasas de impuestos: IGV 18%, ISC, exonerado, inafecto. Configurable por empresa.';
COMMENT ON COLUMN sales.tax_rates.sunat_code IS 'Código de afectación del IGV según catálogo SUNAT (10=gravado, 20=exonerado, 30=inafecto, etc.).';

-- ============================================================
-- Configuración de ventas por producto
-- Sales-specific attributes. logistics.products = master catalog;
-- este tabla = overrides comerciales sin duplicar el catálogo.
-- ============================================================
CREATE TABLE sales.product_sales_config (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    product_id          BIGINT      NOT NULL REFERENCES logistics.products(id),

    -- Descripción comercial (puede diferir de la descripción logística)
    commercial_name         VARCHAR(500),
    commercial_description  TEXT,

    -- Garantía
    warranty_months         INTEGER,
    -- 0 = sin garantía, 12 = 1 año, 24 = 2 años, etc.

    -- Impuesto por defecto (sobreescribe el tax_rate del documento)
    tax_rate_id             INTEGER     REFERENCES sales.tax_rates(id),

    -- Detracción SUNAT (Perú — Sistema de Pago de Obligaciones Tributarias)
    applies_detraction      BOOLEAN     NOT NULL DEFAULT FALSE,
    detraction_code         VARCHAR(10),
    -- código del bien/servicio sujeto a detracción
    detraction_pct          NUMERIC(5,2),

    -- Código SUNAT del bien/servicio (para XML de factura electrónica)
    sunat_product_code      VARCHAR(20),
    -- código de la tabla SUNAT de bienes (tabla 25)

    -- Unidad preferida de venta (puede diferir de la unidad de almacén)
    preferred_sales_unit_id INTEGER     REFERENCES logistics.measurement_units(id),

    -- Precio mínimo de venta (no se puede vender por debajo sin autorización)
    min_sale_price          NUMERIC(18,6),

    -- ¿Se puede vender en cantidades fraccionarias?
    -- FALSE = solo enteros (laptops, cajas, unidades)
    -- TRUE  = acepta decimales (kilos, litros, metros, jabas a 2.5)
    allow_fractional_qty    BOOLEAN     NOT NULL DEFAULT FALSE,
    qty_precision           INTEGER     NOT NULL DEFAULT 0,
    -- decimales permitidos: 0=entero, 1=décimas, 3=gramos (0.001 kg)
    -- Ej: papa por kg → allow_fractional_qty=TRUE, qty_precision=3
    --     laptop        → allow_fractional_qty=FALSE, qty_precision=0
    --     jaba de huevo → allow_fractional_qty=TRUE,  qty_precision=1

    is_active               BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, product_id)
);

CREATE INDEX idx_prod_sales_cfg_product ON sales.product_sales_config (product_id);
CREATE INDEX idx_prod_sales_cfg_company ON sales.product_sales_config (company_id);

CREATE TRIGGER trg_prod_sales_cfg_updated_at
    BEFORE UPDATE ON sales.product_sales_config
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.product_sales_config                    IS 'Atributos comerciales del producto: descripción comercial, garantía, detracción SUNAT, unidad de venta, precio mínimo. Complementa logistics.products sin duplicar el catálogo.';
COMMENT ON COLUMN sales.product_sales_config.allow_fractional_qty IS 'TRUE = acepta decimales (kilos, litros, jabas parciales). FALSE = solo cantidades enteras.';
COMMENT ON COLUMN sales.product_sales_config.qty_precision       IS '0=entero | 1=décima | 2=centésima | 3=milésima. Controla el redondeo en POS y órdenes.';

-- ============================================================
-- Escalas de precio por volumen (price_scales)
-- Permite precios escalonados: 1-10 kg → S/5.00/kg,
--                              10.001-50 kg → S/4.50/kg, 50+ → S/4.00/kg
-- Soporta cantidades fraccionarias: 1.5 kg, 2.5 jabas, etc.
-- ============================================================
CREATE TABLE sales.price_scales (
    id                  BIGSERIAL   PRIMARY KEY,
    price_list_item_id  BIGINT      NOT NULL REFERENCES sales.price_list_items(id) ON DELETE CASCADE,

    -- Rango de cantidad (NUMERIC soporta fracciones: 1.5, 2.5, 0.5, etc.)
    min_quantity        NUMERIC(18,4) NOT NULL,
    -- la escala aplica si quantity_ordered >= min_quantity
    max_quantity        NUMERIC(18,4),
    -- la escala aplica si quantity_ordered < max_quantity (NULL = sin límite)

    -- Precio en este tramo (una de las dos columnas debe tener valor)
    scale_price         NUMERIC(18,6),
    -- precio por unidad en este tramo (reemplaza al precio base)
    scale_discount_pct  NUMERIC(5,2),
    -- % de descuento sobre el precio base (alternativa al precio fijo)

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CHECK (max_quantity IS NULL OR max_quantity > min_quantity),
    CHECK (scale_price IS NOT NULL OR scale_discount_pct IS NOT NULL),
    CHECK (min_quantity >= 0)
);

CREATE INDEX idx_price_scales_item ON sales.price_scales (price_list_item_id);

COMMENT ON TABLE  sales.price_scales              IS 'Precios escalonados por volumen. Ej: 0-9.99 kg → S/5/kg; 10-49.99 kg → S/4.50/kg; 50+ kg → S/4/kg. Soporta cantidades fraccionarias (1.5 kg, 2.5 jabas).';
COMMENT ON COLUMN sales.price_scales.min_quantity IS 'Cantidad mínima (inclusive) para este tramo. Soporta decimales.';
COMMENT ON COLUMN sales.price_scales.max_quantity IS 'Cantidad máxima (exclusiva) para este tramo. NULL = sin límite superior.';
COMMENT ON COLUMN sales.price_scales.scale_price  IS 'Precio fijo por unidad en este tramo. Tiene prioridad sobre scale_discount_pct.';

-- ============================================================
-- Precios especiales negociados por cliente
-- Precio acordado para un cliente específico + producto.
-- Tiene máxima prioridad en el waterfall de precio.
-- (Cliente VIP, contratos anuales, key accounts)
-- ============================================================
CREATE TABLE sales.customer_special_prices (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    customer_id         BIGINT      NOT NULL REFERENCES sales.customers(id),
    product_id          BIGINT      NOT NULL REFERENCES logistics.products(id),
    variant_id          BIGINT      REFERENCES logistics.product_variants(id),
    unit_id             INTEGER     NOT NULL REFERENCES logistics.measurement_units(id),

    -- Precio negociado (SIEMPRE neto, sin IGV)
    special_price       NUMERIC(18,6) NOT NULL,

    -- Cantidad mínima para aplicar el precio especial
    min_quantity        NUMERIC(18,4),
    -- NULL = aplica desde 1 unidad

    -- Vigencia
    valid_from          DATE,
    valid_to            DATE,

    -- Trazabilidad (imprescindible en key accounts)
    negotiated_by       BIGINT,
    -- REFERENCES hr.employees(id) — quién cerró el precio
    contract_reference  VARCHAR(100),
    -- número de contrato, cotización u OC de referencia
    notes               TEXT,

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, customer_id, product_id, variant_id, unit_id)
);

CREATE INDEX idx_cust_special_prices_customer ON sales.customer_special_prices (customer_id);
CREATE INDEX idx_cust_special_prices_product  ON sales.customer_special_prices (product_id);
CREATE INDEX idx_cust_special_prices_company  ON sales.customer_special_prices (company_id);

CREATE TRIGGER trg_cust_special_prices_updated_at
    BEFORE UPDATE ON sales.customer_special_prices
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.customer_special_prices              IS 'Precios negociados por cliente + producto. Máxima prioridad en el waterfall de precio. Para key accounts, contratos anuales y clientes VIP.';
COMMENT ON COLUMN sales.customer_special_prices.special_price IS 'Precio neto (sin IGV). El sistema calcula el impuesto sobre este valor.';
COMMENT ON COLUMN sales.customer_special_prices.negotiated_by IS 'Vendedor o gerente que negoció el precio. Para auditoría.';
COMMENT ON COLUMN sales.customer_special_prices.min_quantity  IS 'Cantidad mínima para aplicar el precio especial. NULL = desde 1 unidad.';
