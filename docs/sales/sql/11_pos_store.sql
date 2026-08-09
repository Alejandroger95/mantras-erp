-- ============================================================
-- mantrasdb | Módulo Sales
-- Archivo: 11_pos_store.sql
-- Descripción: Tiendas físicas y Punto de Venta (POS).
--
-- Conceptos implementados:
--   - stores       : tienda física vinculada a logistics.warehouses
--   - pos_terminals: cada caja/mostrador de la tienda
--   - pos_sessions : turno del cajero (apertura/cierre con conteo)
--   - pos_transactions    : cada venta en el mostrador
--   - pos_transaction_lines: líneas de la venta
--
-- Integración con otros módulos:
--   - Inventory: cada venta descuenta del warehouse de la tienda
--     via logistics.inventory_transactions (la lógica está en la
--     capa de negocio — el SQL solo registra el hecho)
--   - Invoicing: pos_transaction → invoice (boleta o factura)
--   - Logistics: restock desde CD central vía transfer_orders
--     cuando el stock de la tienda baja del mínimo
--
-- Casos reales cubiertos:
--   Tienda de ropa Lima: 3 cajas, abre turno, vende, cierra y cuadra caja
--   Ferretería: 1 mostrador, pago mixto (efectivo + Yape)
--   Supermercado: múltiples cajas, stock de tienda vs CD
--   Farmacia: venta con boleta, cliente puede ser anónimo
--   Tienda en mall: comisión del mall (platform_fee) por cada venta
-- ============================================================

-- ============================================================
-- 1. TIENDAS FÍSICAS
--    Cada tienda está vinculada a un logistics.warehouse
--    (la trastienda). Las ventas de la tienda descuentan
--    el inventario de ESE warehouse.
-- ============================================================
CREATE TABLE sales.stores (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- El almacén de la tienda (trastienda / stock de punto de venta)
    warehouse_id        BIGINT      NOT NULL REFERENCES logistics.warehouses(id),
    -- Cuando el stock de warehouse_id cae bajo mínimo,
    -- se genera transfer_order desde el CD central

    code                VARCHAR(30) NOT NULL,
    name                VARCHAR(200) NOT NULL,

    -- Ubicación
    address             TEXT,
    district            VARCHAR(100),
    city                VARCHAR(100),
    country_code        VARCHAR(5)  NOT NULL DEFAULT 'PE',
    phone               VARCHAR(50),
    email               VARCHAR(200),

    -- Facturación electrónica (SUNAT Perú)
    boleta_serie        VARCHAR(10),
    -- B001, B002 — serie de boleta asignada a esta tienda
    factura_serie       VARCHAR(10),
    -- F001, F002 — serie de factura asignada a esta tienda
    ticket_serie        VARCHAR(10),
    -- T001 — para tickets de bajo monto (sin datos del comprador)

    -- Horario (referencial, para reportes)
    opens_at            TIME,
    closes_at           TIME,

    -- Responsable de la tienda
    manager_id          BIGINT,
    -- REFERENCES hr.employees(id) — sin FK para no crear dependencia circular

    -- Comisión de la ubicación (si es tienda en mall o franquicia)
    location_fee_pct    NUMERIC(5,2) NOT NULL DEFAULT 0,
    -- % de comisión que se paga al mall/franquiciante por ventas

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, code)
);

CREATE INDEX idx_stores_company   ON sales.stores (company_id);
CREATE INDEX idx_stores_warehouse ON sales.stores (warehouse_id);

CREATE TRIGGER trg_stores_updated_at
    BEFORE UPDATE ON sales.stores
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.stores                 IS 'Tiendas físicas. Cada tienda está vinculada a un logistics.warehouse (trastienda). Las ventas descuentan del stock de ese warehouse.';
COMMENT ON COLUMN sales.stores.warehouse_id    IS 'Almacén de la tienda (trastienda). Ventas → inventory_transactions negativas en este warehouse.';
COMMENT ON COLUMN sales.stores.boleta_serie    IS 'Serie SUNAT de boleta electrónica de esta tienda (B001, B002, etc.).';
COMMENT ON COLUMN sales.stores.location_fee_pct IS '% de comisión del mall o franquiciante. Afecta el margen neto de la tienda.';

-- ============================================================
-- 2. TERMINALES POS (cajas / mostradores)
--    Cada terminal es una caja registradora o mostrador
--    dentro de la tienda.
-- ============================================================
CREATE TABLE sales.pos_terminals (
    id                  BIGSERIAL   PRIMARY KEY,
    store_id            BIGINT      NOT NULL REFERENCES sales.stores(id) ON DELETE RESTRICT,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    code                VARCHAR(30) NOT NULL,
    name                VARCHAR(100) NOT NULL,
    -- "Caja 1", "Mostrador Principal", "Caja Express", "Kiosco 3"

    terminal_type       VARCHAR(20) NOT NULL DEFAULT 'counter',
    -- counter    : mostrador clásico con cajero
    -- kiosk      : autoservicio (el cliente escanea solo)
    -- mobile     : tablet/móvil del vendedor (venta en piso)
    -- drive_thru : ventanilla sin bajar del auto

    -- Identificador del hardware (para auditoría de seguridad)
    device_id           VARCHAR(100),
    -- MAC address, UUID del dispositivo, número de serie, etc.

    -- Impresora conectada
    printer_ip          VARCHAR(50),
    -- IP de la impresora de tickets (para impresión directa)

    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (store_id, code)
);

CREATE INDEX idx_pos_terminals_store   ON sales.pos_terminals (store_id);
CREATE INDEX idx_pos_terminals_company ON sales.pos_terminals (company_id);

CREATE TRIGGER trg_pos_terminals_updated_at
    BEFORE UPDATE ON sales.pos_terminals
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE sales.pos_terminals IS 'Cajas y mostradores de la tienda. Cada terminal registra su device_id para auditoría de seguridad.';

-- ============================================================
-- 3. SESIONES DE CAJA (turno del cajero)
--    El cajero abre la sesión con el efectivo inicial,
--    registra ventas, y al final del turno hace el cuadre.
--    La diferencia (sobrante/faltante) queda registrada.
-- ============================================================
CREATE TABLE sales.pos_sessions (
    id                  BIGSERIAL   PRIMARY KEY,
    terminal_id         BIGINT      NOT NULL REFERENCES sales.pos_terminals(id) ON DELETE RESTRICT,
    store_id            BIGINT      NOT NULL REFERENCES sales.stores(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- Cajero del turno
    cashier_id          BIGINT      NOT NULL,
    -- REFERENCES hr.employees(id) — el cajero

    -- Apertura
    opened_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    opening_cash        NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- fondo de caja con que inicia el turno
    opening_notes       TEXT,

    -- Cierre — conteo físico del cajero
    closed_at           TIMESTAMPTZ,
    closing_cash_counted    NUMERIC(18,4),
    -- efectivo que el cajero contó físicamente en el cajón
    closing_card_total      NUMERIC(18,4),
    -- total de ventas con tarjeta (débito + crédito)
    closing_yape_plin_total NUMERIC(18,4),
    -- total de ventas Yape/Plin/transferencia digital
    closing_transfer_total  NUMERIC(18,4),
    -- total de transferencias bancarias
    closing_other_total     NUMERIC(18,4),
    -- otros medios (voucher, gift card, etc.)

    -- Lo que el sistema dice que debería haber en efectivo
    -- = fondo inicial + ventas en efectivo - vueltos dados - retiros de caja
    expected_cash       NUMERIC(18,4),

    -- Diferencia automática (positivo=sobrante, negativo=faltante)
    cash_difference     NUMERIC(18,4)
        GENERATED ALWAYS AS (
            COALESCE(closing_cash_counted, 0) - COALESCE(expected_cash, 0)
        ) STORED,

    -- Retiros de caja durante el turno (para el banco o supervisor)
    cash_withdrawals    NUMERIC(18,4) NOT NULL DEFAULT 0,

    -- Totales de la sesión (acumulados automáticamente al registrar transacciones)
    total_sales         NUMERIC(18,4) NOT NULL DEFAULT 0,
    total_refunds       NUMERIC(18,4) NOT NULL DEFAULT 0,
    total_discounts     NUMERIC(18,4) NOT NULL DEFAULT 0,
    transaction_count   INTEGER       NOT NULL DEFAULT 0,
    refund_count        INTEGER       NOT NULL DEFAULT 0,

    status              VARCHAR(20) NOT NULL DEFAULT 'open',
    -- open         : turno activo
    -- closed       : turno cerrado por el cajero
    -- reconciled   : cuadrado y aprobado por el supervisor
    -- discrepancy  : diferencia detectada, en revisión

    closing_notes       TEXT,
    -- observaciones del cajero al cerrar

    reconciled_by       BIGINT,
    -- REFERENCES hr.employees(id) — supervisor que cuadró
    reconciled_at       TIMESTAMPTZ,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_pos_sessions_terminal  ON sales.pos_sessions (terminal_id);
CREATE INDEX idx_pos_sessions_cashier   ON sales.pos_sessions (cashier_id);
CREATE INDEX idx_pos_sessions_store     ON sales.pos_sessions (store_id);
CREATE INDEX idx_pos_sessions_status    ON sales.pos_sessions (status);
CREATE INDEX idx_pos_sessions_opened_at ON sales.pos_sessions (opened_at);

CREATE TRIGGER trg_pos_sessions_updated_at
    BEFORE UPDATE ON sales.pos_sessions
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.pos_sessions                    IS 'Sesión de caja: turno del cajero con apertura, ventas y cuadre. cash_difference = diferencia entre el conteo físico y lo que el sistema espera.';
COMMENT ON COLUMN sales.pos_sessions.opening_cash       IS 'Fondo de caja con que inicia el turno. No es una venta — es el "float" de efectivo para dar vueltos.';
COMMENT ON COLUMN sales.pos_sessions.cash_difference    IS 'Calculado: conteo_físico - efectivo_esperado. Positivo=sobrante, negativo=faltante. Diferencias relevantes deben investigarse.';
COMMENT ON COLUMN sales.pos_sessions.expected_cash      IS 'Calculado por la capa de negocio: fondo_inicial + ventas_efectivo - retiros_de_caja.';

-- ============================================================
-- 4. TRANSACCIONES POS (cada venta en el mostrador)
--    Una transacción puede ser venta, devolución, cambio o anulación.
--    Al completarse, genera una invoice (boleta/factura) y
--    descuenta el inventario del warehouse de la tienda.
-- ============================================================
CREATE TABLE sales.pos_transactions (
    id                      BIGSERIAL   PRIMARY KEY,
    session_id              BIGINT      NOT NULL REFERENCES sales.pos_sessions(id) ON DELETE RESTRICT,
    store_id                BIGINT      NOT NULL REFERENCES sales.stores(id),
    company_id              BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    transaction_number      VARCHAR(50) NOT NULL,
    -- numeración correlativa de la tienda (TRX-B001-000001)

    transaction_type        VARCHAR(20) NOT NULL DEFAULT 'sale',
    -- sale      : venta normal
    -- refund    : devolución de dinero
    -- exchange  : cambio de producto (misma sesión)
    -- void      : anulación de una transacción anterior

    -- Cliente (opcional en boleta — puede ser anónimo)
    customer_id             BIGINT      REFERENCES sales.customers(id),
    customer_name           VARCHAR(300),
    -- capturado al momento, para imprimir en el comprobante
    customer_tax_id         VARCHAR(20),
    -- DNI o RUC del cliente (necesario para facturas y boletas > S/700 en Perú)
    customer_tax_id_type    VARCHAR(10),
    -- DNI | RUC | CE | PASSPORT

    -- Tipo de comprobante a emitir
    document_type_id        INTEGER     REFERENCES sales.document_types(id),
    -- BOL=boleta, FAC=factura, TKT=ticket (bajo monto, anónimo)

    -- Factura generada (se puebla después de emitir)
    invoice_id              BIGINT,
    -- REFERENCES sales.invoices(id) — FK diferida

    -- Si es devolución/cambio, referencia a la venta original
    original_transaction_id BIGINT      REFERENCES sales.pos_transactions(id),
    original_invoice_id     BIGINT,
    -- REFERENCES sales.invoices(id) — FK diferida

    -- Totales
    subtotal                NUMERIC(18,4) NOT NULL DEFAULT 0,
    discount_amount         NUMERIC(18,4) NOT NULL DEFAULT 0,
    tax_amount              NUMERIC(18,4) NOT NULL DEFAULT 0,
    total_amount            NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- total_amount = subtotal - discount_amount + tax_amount

    -- ─── Forma de pago ─────────────────────────────────────
    -- Pago único (caso más común)
    payment_method          VARCHAR(20) NOT NULL DEFAULT 'cash',
    -- cash | card_debit | card_credit | yape | plin
    -- transfer | gift_card | mixed | on_account

    -- Pago mixto (cuando usa más de un medio)
    payment_detail          JSONB,
    -- [{"method":"cash","amount":50.00},{"method":"yape","amount":20.50}]
    -- Suma debe ser = total_amount

    -- Efectivo dado y vuelto (para pago en cash)
    cash_tendered           NUMERIC(18,4),
    change_given            NUMERIC(18,4),
    -- change_given = cash_tendered - total_amount

    -- ─── Estado ────────────────────────────────────────────
    status                  VARCHAR(20) NOT NULL DEFAULT 'completed',
    -- completed : transacción exitosa
    -- voided    : anulada (en el mismo turno)
    -- refunded  : devuelta (puede ser en otro turno)

    -- Anulación
    cancellation_reason_id  INTEGER     REFERENCES sales.cancellation_reasons(id),
    cancellation_notes      TEXT,
    cancelled_at            TIMESTAMPTZ,
    cancelled_by            BIGINT,
    -- REFERENCES hr.employees(id)

    -- Quién realizó la transacción
    cashier_id              BIGINT      NOT NULL,
    -- REFERENCES hr.employees(id)

    transacted_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, transaction_number)
);

CREATE INDEX idx_pos_tx_session      ON sales.pos_transactions (session_id);
CREATE INDEX idx_pos_tx_store        ON sales.pos_transactions (store_id);
CREATE INDEX idx_pos_tx_customer     ON sales.pos_transactions (customer_id)
    WHERE customer_id IS NOT NULL;
CREATE INDEX idx_pos_tx_date         ON sales.pos_transactions (transacted_at);
CREATE INDEX idx_pos_tx_status       ON sales.pos_transactions (status);
CREATE INDEX idx_pos_tx_original     ON sales.pos_transactions (original_transaction_id)
    WHERE original_transaction_id IS NOT NULL;

CREATE TRIGGER trg_pos_transactions_updated_at
    BEFORE UPDATE ON sales.pos_transactions
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.pos_transactions                      IS 'Cada venta, devolución o anulación en el mostrador. Genera invoice + descuenta stock del warehouse de la tienda.';
COMMENT ON COLUMN sales.pos_transactions.customer_tax_id      IS 'DNI o RUC. En Perú, boletas > S/700 deben llevar datos del comprador. Sin datos → boleta anónima hasta el límite.';
COMMENT ON COLUMN sales.pos_transactions.payment_detail       IS 'JSON para pago mixto. Ej: [{method:cash,amount:50},{method:yape,amount:20.50}]. La suma debe = total_amount.';
COMMENT ON COLUMN sales.pos_transactions.cash_tendered        IS 'Efectivo que entregó el cliente. change_given = cash_tendered - total_amount.';

-- ============================================================
-- 5. LÍNEAS DE LA TRANSACCIÓN POS
--    Cada ítem en la venta. Soporta cantidades fraccionarias
--    (1.5 kg de papa, 2.5 jabas de huevo) siempre que
--    product_sales_config.allow_fractional_qty = TRUE.
-- ============================================================
CREATE TABLE sales.pos_transaction_lines (
    id                  BIGSERIAL   PRIMARY KEY,
    transaction_id      BIGINT      NOT NULL REFERENCES sales.pos_transactions(id) ON DELETE RESTRICT,
    product_id          BIGINT      NOT NULL REFERENCES logistics.products(id),
    variant_id          BIGINT      REFERENCES logistics.product_variants(id),
    unit_id             INTEGER     NOT NULL REFERENCES logistics.measurement_units(id),

    line_number         INTEGER     NOT NULL,
    description         VARCHAR(500),
    -- Descripción comercial (de product_sales_config o free-text)

    -- Cantidad (NUMERIC soporta decimales: 1.5 kg, 2.5 jabas)
    quantity            NUMERIC(18,4) NOT NULL,
    -- El sistema valida contra product_sales_config.allow_fractional_qty
    -- y product_sales_config.qty_precision antes de guardar

    -- Precios (siempre netos, sin IGV)
    unit_price          NUMERIC(18,6) NOT NULL,
    -- precio de lista o especial que aplica al momento

    discount_pct        NUMERIC(5,2)  NOT NULL DEFAULT 0,
    discount_amount     NUMERIC(18,4) NOT NULL DEFAULT 0,
    net_price           NUMERIC(18,6) NOT NULL DEFAULT 0,
    -- net_price = unit_price × (1 - discount_pct/100)

    -- Impuesto
    tax_rate_id         INTEGER       REFERENCES sales.tax_rates(id),
    tax_pct             NUMERIC(5,2)  NOT NULL DEFAULT 18,

    -- Totales de la línea
    line_total_net      NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- line_total_net = net_price × quantity
    line_tax            NUMERIC(18,4) NOT NULL DEFAULT 0,
    line_total          NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- line_total = line_total_net + line_tax

    -- ─── Promoción aplicada ─────────────────────────────────
    promotion_id        BIGINT      REFERENCES sales.promotions(id),
    -- NULL si no hubo promo
    is_free_item        BOOLEAN     NOT NULL DEFAULT FALSE,
    -- TRUE = ítem gratis por promo (BOGO, free_item effect)

    -- Lote (para trazabilidad de alimentos, medicamentos)
    lot_id              BIGINT,
    -- REFERENCES logistics.lot_numbers(id)

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (transaction_id, line_number)
);

CREATE INDEX idx_pos_tx_lines_transaction ON sales.pos_transaction_lines (transaction_id);
CREATE INDEX idx_pos_tx_lines_product     ON sales.pos_transaction_lines (product_id);

COMMENT ON TABLE  sales.pos_transaction_lines             IS 'Líneas de cada venta POS. quantity acepta decimales (1.5 kg, 2.5 jabas) cuando product_sales_config.allow_fractional_qty = TRUE.';
COMMENT ON COLUMN sales.pos_transaction_lines.quantity    IS 'Cantidad vendida. Soporta decimales si el producto lo permite. El precio escalonado (price_scales) se evalúa con esta cantidad.';
COMMENT ON COLUMN sales.pos_transaction_lines.net_price   IS 'Precio neto (sin IGV): unit_price × (1 - discount_pct / 100). El IGV se calcula sobre este valor.';
COMMENT ON COLUMN sales.pos_transaction_lines.is_free_item IS 'TRUE = ítem gratis por promo (BOGO, free_item). Precio unitario = 0 pero se registra para trazabilidad de inventario.';

-- ============================================================
-- 6. FKs DIFERIDAS (ahora que pos_transactions existe)
-- ============================================================

-- pos_transactions → invoices
ALTER TABLE sales.pos_transactions
    ADD CONSTRAINT fk_pos_tx_invoice
    FOREIGN KEY (invoice_id)
    REFERENCES sales.invoices(id)
    ON DELETE SET NULL;

ALTER TABLE sales.pos_transactions
    ADD CONSTRAINT fk_pos_tx_original_invoice
    FOREIGN KEY (original_invoice_id)
    REFERENCES sales.invoices(id)
    ON DELETE SET NULL;
