-- ============================================================
-- mantrasdb | Módulo Finance
-- Archivo: 05_fixed_assets.sql
-- Descripción: Activos Fijos y Depreciación.
--
-- Módulos:
--   1. asset_categories     — categorías con tasas máximas SUNAT (Perú)
--   2. fixed_assets         — registro de activos individuales
--   3. asset_acquisitions   — cómo se adquirió el activo
--   4. depreciation_schedules — tabla de depreciación proyectada
--   5. depreciation_runs    — ejecuciones mensuales de depreciación
--   6. asset_revaluations   — revaluaciones (NIC 16)
--   7. asset_disposals      — bajas y ventas de activos
--
-- Métodos de depreciación:
--   🇵🇪 Línea recta (SUNAT solo acepta línea recta como máximo)
--      Para efectos tributarios las tasas máximas son fijas.
--      Para efectos financieros (NIC/NIIF) se puede usar otro método.
--   📊 Saldo decreciente (financial reporting)
--   ⚙️ Unidades producidas (machinery con hora-máquina)
--
-- Tasas SUNAT (Artículo 22 LIR Perú):
--   Inmuebles (no terrenos): 5%
--   Ganado de trabajo y reproducción: 25%
--   Vehículos de transporte de personas: 20%
--   Maquinaria y equipo de uso general: 10%
--   Equipos de procesamiento de datos: 25%
--   Maquinaria y equipo para minería: 20%
--   Otros bienes del activo fijo: 10%
-- ============================================================

-- ============================================================
-- 1. CATEGORÍAS DE ACTIVOS FIJOS
-- ============================================================
CREATE TABLE finance.asset_categories (
    id                  SERIAL      PRIMARY KEY,
    company_id          BIGINT      REFERENCES hr.companies(id),
    -- NULL = categoría del sistema (pre-cargada con tasas SUNAT)

    code                VARCHAR(20) NOT NULL,
    name                VARCHAR(200) NOT NULL,
    description         TEXT,

    country_code        VARCHAR(5)  NOT NULL DEFAULT 'PE',

    -- Tasas de depreciación (% anual)
    -- Máximo tributario (SUNAT Perú / Agencia Tributaria España)
    max_tax_depreciation_rate NUMERIC(5,2) NOT NULL,
    -- Tasa usada por defecto para efectos financieros (NIC 16)
    default_financial_rate    NUMERIC(5,2),

    -- Método por defecto
    default_method      VARCHAR(20) NOT NULL DEFAULT 'straight_line',
    -- straight_line      : línea recta
    -- declining_balance  : saldo decreciente
    -- units_of_production: unidades producidas

    -- Vida útil estimada en meses
    default_useful_life_months INTEGER NOT NULL DEFAULT 120,

    -- Cuenta contable de costo (activo)
    asset_account_id    BIGINT      REFERENCES finance.accounts(id),
    -- ej: 33301 IME - Maquinaria (PCGE Perú)

    -- Cuenta de depreciación acumulada
    accumulated_depreciation_account_id BIGINT REFERENCES finance.accounts(id),
    -- ej: 39131 Dep. Acumulada - IME

    -- Cuenta de gasto de depreciación
    depreciation_expense_account_id BIGINT REFERENCES finance.accounts(id),
    -- ej: 68131 Depreciación - IME

    -- ¿Los terrenos nunca se deprecian? TRUE para terrenos
    is_depreciable      BOOLEAN     NOT NULL DEFAULT TRUE,

    sunat_category_code VARCHAR(10),
    -- código de categoría SUNAT para declaración

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    is_template         BOOLEAN     NOT NULL DEFAULT FALSE
);

CREATE UNIQUE INDEX uq_asset_categories
    ON finance.asset_categories (COALESCE(company_id, 0::BIGINT), country_code, code);

-- SUNAT Perú — categorías con tasas máximas (Artículo 22 LIR)
INSERT INTO finance.asset_categories
    (company_id, code, name, country_code, max_tax_depreciation_rate, default_financial_rate, default_useful_life_months, default_method, is_template) VALUES
(NULL, 'INMUEBLE',       'Edificios y Otras Construcciones',                'PE', 5.00,   5.00,  240, 'straight_line', TRUE),
(NULL, 'TERRENO',        'Terrenos',                                        'PE', 0.00,   0.00,    0, 'straight_line', TRUE),
-- No se deprecian
(NULL, 'GANADO_TRAB',    'Ganado de Trabajo y Reproducción',                'PE', 25.00,  25.00,  48, 'straight_line', TRUE),
(NULL, 'VEHICULO',       'Vehículos de Transporte de Personas',             'PE', 20.00,  20.00,  60, 'straight_line', TRUE),
(NULL, 'MAQUINARIA',     'Maquinaria y Equipo Adquirido a partir 2001',     'PE', 10.00,  10.00, 120, 'straight_line', TRUE),
(NULL, 'MAQUINARIA_PRE', 'Maquinaria y Equipo Adquirido antes 2001',        'PE', 10.00,  10.00, 120, 'straight_line', TRUE),
(NULL, 'EQUIPO_PROC',    'Equipos de Procesamiento de Datos',               'PE', 25.00,  25.00,  48, 'straight_line', TRUE),
(NULL, 'MAQUINARIA_MIN', 'Maquinaria y Equipo para Actividades Mineras',    'PE', 20.00,  20.00,  60, 'straight_line', TRUE),
(NULL, 'OTROS_AF',       'Otros Bienes del Activo Fijo',                    'PE', 10.00,  10.00, 120, 'straight_line', TRUE),
(NULL, 'INTANGIBLE_SW',  'Software / Programas de Computadora',             'PE', 100.00, 33.33,  36, 'straight_line', TRUE),
-- SUNAT permite depreciar software al 100% en 1 año
(NULL, 'MUEBLES',        'Muebles y Enseres',                               'PE', 10.00,  10.00, 120, 'straight_line', TRUE),

-- España (PGC / AEAT) — tasas según tablas oficiales
(NULL, 'INMUEBLE_ES',    'Edificios Industriales / Comerciales (España)',   'ES', 3.00,   3.00,  400, 'straight_line', TRUE),
(NULL, 'TERRENO_ES',     'Terrenos (España)',                               'ES', 0.00,   0.00,    0, 'straight_line', TRUE),
(NULL, 'MAQUINARIA_ES',  'Maquinaria en General (España)',                  'ES', 12.00,  12.00,  96, 'straight_line', TRUE),
(NULL, 'VEHICULO_ES',    'Turismos y Vehículos Todo Terreno (España)',      'ES', 16.00,  16.00,  72, 'straight_line', TRUE),
(NULL, 'EQUIPO_INF_ES',  'Equipos para Procesos de Información (España)',   'ES', 25.00,  25.00,  48, 'straight_line', TRUE),
(NULL, 'MOBILIARIO_ES',  'Mobiliario (España)',                             'ES', 10.00,  10.00, 120, 'straight_line', TRUE),
(NULL, 'OTROS_AF_ES',    'Otros Activos Fijos (España)',                    'ES', 10.00,  10.00, 120, 'straight_line', TRUE);

UPDATE finance.asset_categories
    SET is_depreciable = FALSE, default_useful_life_months = 0
    WHERE code IN ('TERRENO', 'TERRENO_ES');

COMMENT ON TABLE  finance.asset_categories IS 'Categorías de activos fijos con tasas máximas de depreciación (SUNAT Perú / AEAT España). company_id=NULL = plantilla del sistema.';
COMMENT ON COLUMN finance.asset_categories.max_tax_depreciation_rate IS '🇵🇪 Tasa máxima de depreciación tributaria permitida por SUNAT (Artículo 22 LIR). Empresas pueden usar una tasa menor.';

-- ============================================================
-- 2. ACTIVOS FIJOS
-- ============================================================
CREATE TABLE finance.fixed_assets (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    asset_category_id   INTEGER     NOT NULL REFERENCES finance.asset_categories(id),

    -- Identificación
    asset_code          VARCHAR(30) NOT NULL,
    -- número de placa / código interno del activo
    name                VARCHAR(300) NOT NULL,
    description         TEXT,
    serial_number       VARCHAR(100),
    brand               VARCHAR(100),
    model               VARCHAR(100),

    -- Ubicación
    location            VARCHAR(200),
    warehouse_id        BIGINT,
    -- REFERENCES logistics.warehouses(id) — FK diferida

    responsible_employee_id BIGINT,
    -- REFERENCES hr.employees(id) — FK diferida

    -- Adquisición
    acquisition_date    DATE        NOT NULL,
    acquisition_cost    NUMERIC(18,2) NOT NULL,
    -- costo de adquisición (precio + gastos de instalación + fletes)

    currency            VARCHAR(10) NOT NULL DEFAULT 'PEN',
    exchange_rate       NUMERIC(18,8) NOT NULL DEFAULT 1.0,

    acquisition_cost_functional NUMERIC(18,2) NOT NULL,
    -- costo en moneda funcional de la empresa

    -- Revaluación (NIC 16)
    revalued_amount     NUMERIC(18,2),
    -- si hubo revaluación, este es el nuevo costo base
    last_revaluation_date DATE,

    -- Valor residual / valor de desecho
    residual_value      NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- al terminar la vida útil, valor esperado de recuperación

    -- Depreciación
    depreciation_method VARCHAR(20) NOT NULL DEFAULT 'straight_line',
    -- straight_line | declining_balance | units_of_production

    useful_life_months  INTEGER     NOT NULL,
    -- vida útil estimada en meses

    -- Tasa de depreciación financiera (puede ser menor al máximo SUNAT)
    financial_depreciation_rate NUMERIC(7,4) NOT NULL,
    -- % anual. Para línea recta: 100 / useful_life_years

    -- Tasa de depreciación tributaria (máximo SUNAT)
    tax_depreciation_rate NUMERIC(7,4) NOT NULL,

    -- Depreciación acumulada
    accumulated_depreciation NUMERIC(18,2) NOT NULL DEFAULT 0,
    accumulated_tax_depreciation NUMERIC(18,2) NOT NULL DEFAULT 0,

    -- Valor en libros actual
    book_value          NUMERIC(18,2) GENERATED ALWAYS AS (
        COALESCE(revalued_amount, acquisition_cost_functional)
        - accumulated_depreciation
    ) STORED,

    -- Valor tributario actual
    tax_value           NUMERIC(18,2) GENERATED ALWAYS AS (
        acquisition_cost_functional - accumulated_tax_depreciation
    ) STORED,

    -- Estado del activo
    status              VARCHAR(20) NOT NULL DEFAULT 'active',
    -- active        : en uso
    -- idle          : paralizado / sin uso temporal
    -- under_repair  : en reparación
    -- disposed      : dado de baja
    -- sold          : vendido

    -- Referencia a la compra (supplier_invoice)
    supplier_invoice_id BIGINT      REFERENCES finance.supplier_invoices(id),
    purchase_order_id   BIGINT,
    -- REFERENCES logistics.purchase_orders(id) — FK diferida

    -- Asiento de activación
    activation_journal_entry_id BIGINT REFERENCES finance.journal_entries(id),

    -- Garantía
    warranty_expiry_date DATE,
    warranty_notes       TEXT,

    -- Para equipos con unidades de producción
    total_expected_units NUMERIC(18,2),
    -- total de unidades/horas de vida estimada

    units_used_to_date  NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- unidades/horas usadas hasta la fecha

    -- Fecha inicio depreciación (puede ser diferente a acquisition_date)
    depreciation_start_date DATE,

    -- Fecha fin de depreciación
    depreciation_end_date DATE,

    -- Notas SUNAT (para declaración)
    sunat_asset_type    VARCHAR(10),
    -- código del tipo de bien SUNAT

    notes               TEXT,
    created_by          BIGINT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, asset_code)
);

CREATE INDEX idx_fa_company   ON finance.fixed_assets (company_id);
CREATE INDEX idx_fa_category  ON finance.fixed_assets (asset_category_id);
CREATE INDEX idx_fa_status    ON finance.fixed_assets (status);
CREATE INDEX idx_fa_location  ON finance.fixed_assets (warehouse_id) WHERE warehouse_id IS NOT NULL;

CREATE TRIGGER trg_fa_updated_at
    BEFORE UPDATE ON finance.fixed_assets
    FOR EACH ROW EXECUTE FUNCTION finance.set_updated_at();

COMMENT ON TABLE  finance.fixed_assets           IS 'Registro de activos fijos individuales. Mantiene tanto el valor financiero (NIC 16) como el tributario (SUNAT) para diferencias temporarias.';
COMMENT ON COLUMN finance.fixed_assets.book_value IS 'Valor en libros = (costo/revaluación) - depreciación acumulada. GENERADO automáticamente.';
COMMENT ON COLUMN finance.fixed_assets.tax_value  IS 'Valor tributario = costo original - depreciación tributaria acumulada. SUNAT no acepta revaluaciones para efectos del IR.';

-- ============================================================
-- 3. TABLA DE DEPRECIACIÓN PROYECTADA
--    Línea por mes, por activo — calculada al activar el activo.
-- ============================================================
CREATE TABLE finance.depreciation_schedules (
    id                  BIGSERIAL   PRIMARY KEY,
    fixed_asset_id      BIGINT      NOT NULL REFERENCES finance.fixed_assets(id) ON DELETE CASCADE,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    period_number       INTEGER     NOT NULL,
    -- mes 1, mes 2, ..., mes N (vida útil en meses)

    schedule_date       DATE        NOT NULL,
    -- primer día del mes al que corresponde

    -- Depreciación financiera del mes
    depreciation_amount NUMERIC(18,2) NOT NULL,
    opening_book_value  NUMERIC(18,2) NOT NULL,
    closing_book_value  NUMERIC(18,2) NOT NULL,

    -- Depreciación tributaria del mes
    tax_depreciation_amount NUMERIC(18,2) NOT NULL,
    opening_tax_value   NUMERIC(18,2) NOT NULL,
    closing_tax_value   NUMERIC(18,2) NOT NULL,

    -- ¿Se ejecutó ya este período?
    is_posted           BOOLEAN     NOT NULL DEFAULT FALSE,
    posted_at           TIMESTAMPTZ,
    journal_entry_id    BIGINT      REFERENCES finance.journal_entries(id),

    UNIQUE (fixed_asset_id, period_number)
);

CREATE INDEX idx_depsch_asset    ON finance.depreciation_schedules (fixed_asset_id);
CREATE INDEX idx_depsch_date     ON finance.depreciation_schedules (schedule_date);
CREATE INDEX idx_depsch_pending  ON finance.depreciation_schedules (schedule_date) WHERE is_posted = FALSE;

COMMENT ON TABLE finance.depreciation_schedules IS 'Tabla de amortización proyectada por activo. Se genera al activar el activo. is_posted=TRUE cuando se ejecutó el asiento del mes.';

-- ============================================================
-- 4. EJECUCIONES DE DEPRECIACIÓN (DEPRECIATION RUNS)
--    Proceso mensual que genera todos los asientos de
--    depreciación para un período.
-- ============================================================
CREATE TABLE finance.depreciation_runs (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    accounting_period_id BIGINT     NOT NULL REFERENCES finance.accounting_periods(id),

    run_date            DATE        NOT NULL,
    run_type            VARCHAR(20) NOT NULL DEFAULT 'standard',
    -- standard    : depreciación mensual normal
    -- correction  : corrección de un período anterior
    -- closing     : depreciación de cierre

    status              VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending   : pendiente de ejecución
    -- running   : en proceso
    -- completed : ejecutado correctamente
    -- failed    : error en la ejecución
    -- reversed  : revertido

    total_assets        INTEGER     NOT NULL DEFAULT 0,
    total_depreciation  NUMERIC(18,2) NOT NULL DEFAULT 0,
    total_tax_depreciation NUMERIC(18,2) NOT NULL DEFAULT 0,

    error_message       TEXT,
    executed_by         BIGINT,
    executed_at         TIMESTAMPTZ,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, accounting_period_id, run_type)
);

COMMENT ON TABLE finance.depreciation_runs IS 'Ejecuciones mensuales del proceso de depreciación. Agrupa todos los asientos de depreciación del período.';

-- ============================================================
-- 5. REVALUACIONES DE ACTIVOS (NIC 16)
--    Cuando se ajusta el valor de un activo a su valor
--    razonable (inmuebles, principalmente).
-- ============================================================
CREATE TABLE finance.asset_revaluations (
    id                  BIGSERIAL   PRIMARY KEY,
    fixed_asset_id      BIGINT      NOT NULL REFERENCES finance.fixed_assets(id) ON DELETE RESTRICT,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    revaluation_date    DATE        NOT NULL,
    revaluation_type    VARCHAR(20) NOT NULL,
    -- increase    : incremento (excedente de revaluación → 57x Patrimonio)
    -- decrease    : deterioro (pérdida → 68x Gasto)

    previous_cost       NUMERIC(18,2) NOT NULL,
    previous_accumulated_depreciation NUMERIC(18,2) NOT NULL,
    previous_book_value NUMERIC(18,2) NOT NULL,

    new_fair_value      NUMERIC(18,2) NOT NULL,
    -- valor razonable determinado por tasador

    revaluation_surplus NUMERIC(18,2) NOT NULL,
    -- diferencia: new_fair_value - previous_book_value

    -- Asignación de la diferencia
    surplus_to_equity   NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- va a cta. 57 Excedente de Revaluación (si es ganancia)
    surplus_to_expense  NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- va a cta. 68 si revierte una pérdida anterior

    -- Nombre del tasador
    appraiser_name      VARCHAR(200),
    appraisal_report_number VARCHAR(50),

    journal_entry_id    BIGINT      REFERENCES finance.journal_entries(id),

    notes               TEXT,
    created_by          BIGINT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- Inmutable
);

COMMENT ON TABLE finance.asset_revaluations IS 'Revaluaciones de activos fijos bajo NIC 16. Los incrementos van a Patrimonio (57x), las disminuciones a Gastos (68x) salvo que reviertan una ganancia previa.';

-- ============================================================
-- 6. BAJAS Y VENTAS DE ACTIVOS (ASSET DISPOSALS)
-- ============================================================
CREATE TABLE finance.asset_disposals (
    id                  BIGSERIAL   PRIMARY KEY,
    fixed_asset_id      BIGINT      NOT NULL REFERENCES finance.fixed_assets(id) ON DELETE RESTRICT,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    disposal_date       DATE        NOT NULL,

    disposal_type       VARCHAR(20) NOT NULL,
    -- sale         : venta a tercero
    -- scrap        : desecho / chatarra
    -- donate       : donación
    -- theft        : robo / siniestro
    -- obsolete     : obsolescencia
    -- transfer     : transferencia a otra empresa del grupo

    -- Valores al momento de la baja
    book_value_at_disposal      NUMERIC(18,2) NOT NULL,
    accumulated_depreciation_at NUMERIC(18,2) NOT NULL,
    original_cost               NUMERIC(18,2) NOT NULL,

    -- Para ventas
    sale_price          NUMERIC(18,2) NOT NULL DEFAULT 0,
    sale_currency       VARCHAR(10) NOT NULL DEFAULT 'PEN',

    -- Factura de venta del activo
    sales_invoice_id    BIGINT,
    -- REFERENCES sales.invoices(id) — FK diferida

    -- Resultado de la baja
    gain_loss           NUMERIC(18,2) GENERATED ALWAYS AS (
        sale_price - book_value_at_disposal
    ) STORED,
    -- positivo = ganancia / negativo = pérdida

    -- Cuentas de resultado (por defecto de la categoría, sobreescribible)
    gain_account_id     BIGINT      REFERENCES finance.accounts(id),
    -- ej: 75501 Ganancia en venta de IME
    loss_account_id     BIGINT      REFERENCES finance.accounts(id),
    -- ej: 65501 Pérdida en baja de IME

    -- 🇵🇪 Para destrucciones: certificado de destrucción SUNAT
    -- (mermas y desmedros — evita desconocimiento del costo como gasto)
    destruction_cert_number VARCHAR(50),
    destruction_date    DATE,
    destruction_witnessed_by VARCHAR(200),
    sunat_merma_type    VARCHAR(20),
    -- merma | desmedro

    journal_entry_id    BIGINT      REFERENCES finance.journal_entries(id),

    notes               TEXT,
    authorized_by       BIGINT,
    created_by          BIGINT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- Inmutable
);

CREATE INDEX idx_disposal_asset   ON finance.asset_disposals (fixed_asset_id);
CREATE INDEX idx_disposal_company ON finance.asset_disposals (company_id);
CREATE INDEX idx_disposal_date    ON finance.asset_disposals (disposal_date);

COMMENT ON TABLE  finance.asset_disposals           IS 'Bajas y ventas de activos fijos. Calcula automáticamente la ganancia o pérdida en la baja.';
COMMENT ON COLUMN finance.asset_disposals.gain_loss IS 'Ganancia (>0) o pérdida (<0) en la baja: precio_venta - valor_en_libros. GENERADO automáticamente.';
COMMENT ON COLUMN finance.asset_disposals.destruction_cert_number IS '🇵🇪 Para desmedros: número del Acta de Destrucción que demuestra a SUNAT la baja del inventario/activo. Sin esto SUNAT puede rechazar el gasto.';

-- ============================================================
-- 7. FUNCIÓN: CALCULAR DEPRECIACIÓN MENSUAL
--    Para línea recta. Genera la tabla de depreciación
--    completa para un activo.
-- ============================================================
CREATE OR REPLACE FUNCTION finance.calculate_depreciation_schedule(
    p_asset_id BIGINT
)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
    v_asset         finance.fixed_assets%ROWTYPE;
    v_cat           finance.asset_categories%ROWTYPE;
    v_monthly_dep   NUMERIC(18,2);
    v_monthly_tax   NUMERIC(18,2);
    v_open_book     NUMERIC(18,2);
    v_open_tax      NUMERIC(18,2);
    v_close_book    NUMERIC(18,2);
    v_close_tax     NUMERIC(18,2);
    v_period        INTEGER;
    v_sched_date    DATE;
    v_rows          INTEGER := 0;
BEGIN
    SELECT * INTO v_asset FROM finance.fixed_assets WHERE id = p_asset_id;
    IF v_asset.id IS NULL THEN
        RAISE EXCEPTION 'Activo % no encontrado', p_asset_id;
    END IF;

    SELECT * INTO v_cat FROM finance.asset_categories WHERE id = v_asset.asset_category_id;

    IF NOT v_cat.is_depreciable OR v_asset.useful_life_months = 0 THEN
        RETURN 0; -- No se deprecia (terrenos)
    END IF;

    -- Limpiar tabla previa si existe
    DELETE FROM finance.depreciation_schedules
    WHERE fixed_asset_id = p_asset_id AND is_posted = FALSE;

    -- Costo base
    v_open_book := COALESCE(v_asset.revalued_amount, v_asset.acquisition_cost_functional)
                   - v_asset.accumulated_depreciation;
    v_open_tax  := v_asset.acquisition_cost_functional - v_asset.accumulated_tax_depreciation;

    -- Depreciación mensual (línea recta)
    -- (Costo - Valor Residual) / Vida útil en meses
    v_monthly_dep := ROUND(
        (COALESCE(v_asset.revalued_amount, v_asset.acquisition_cost_functional)
         - v_asset.residual_value)
        / v_asset.useful_life_months
    , 2);

    v_monthly_tax := ROUND(
        (v_asset.acquisition_cost_functional - v_asset.residual_value)
        * (v_asset.tax_depreciation_rate / 100.0)
        / 12.0
    , 2);

    -- Fecha inicio
    v_sched_date := COALESCE(v_asset.depreciation_start_date, v_asset.acquisition_date);
    v_sched_date := DATE_TRUNC('month', v_sched_date)::DATE;

    -- Insertar líneas
    FOR v_period IN 1..v_asset.useful_life_months LOOP
        -- Último período: ajustar para que cierre exacto en 0
        IF v_period = v_asset.useful_life_months THEN
            v_monthly_dep := GREATEST(v_open_book - v_asset.residual_value, 0);
            v_monthly_tax := GREATEST(v_open_tax  - v_asset.residual_value, 0);
        END IF;

        -- No depreciar más que el valor en libros
        v_monthly_dep := LEAST(v_monthly_dep, GREATEST(v_open_book - v_asset.residual_value, 0));
        v_monthly_tax := LEAST(v_monthly_tax, GREATEST(v_open_tax  - v_asset.residual_value, 0));

        v_close_book := v_open_book - v_monthly_dep;
        v_close_tax  := v_open_tax  - v_monthly_tax;

        INSERT INTO finance.depreciation_schedules (
            fixed_asset_id, company_id, period_number, schedule_date,
            depreciation_amount, opening_book_value, closing_book_value,
            tax_depreciation_amount, opening_tax_value, closing_tax_value
        ) VALUES (
            p_asset_id, v_asset.company_id, v_period, v_sched_date,
            v_monthly_dep, v_open_book, v_close_book,
            v_monthly_tax, v_open_tax,  v_close_tax
        )
        ON CONFLICT (fixed_asset_id, period_number) DO NOTHING;

        v_open_book  := v_close_book;
        v_open_tax   := v_close_tax;
        v_sched_date := (v_sched_date + INTERVAL '1 month')::DATE;
        v_rows       := v_rows + 1;
    END LOOP;

    RETURN v_rows;
END;
$$;

COMMENT ON FUNCTION finance.calculate_depreciation_schedule IS 'Genera la tabla de depreciación mensual (línea recta) para un activo. Retorna el número de períodos creados. Llamar al activar un activo.';
