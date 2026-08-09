-- ============================================================
-- mantrasdb | Módulo Sales
-- Archivo: 12_returns.sql
-- Descripción: Devoluciones de clientes con flujo completo:
--   RMA → Inspección → Disposición → Nota de Crédito SUNAT
--
-- Conceptos implementados:
--   - return_authorizations: aprobación previa del RMA
--   - return_authorization_lines: qué productos se devuelven
--   - return_inspections: estado del producto al recibirlo
--   - return_dispositions: qué se hace con cada unidad
--   - warranty_claims: garantías de productos
--
-- Integración con otros módulos:
--   - Sales:    credit_notes (NC SUNAT por el valor devuelto)
--   - Logistics: customer_returns (recepción física en almacén)
--               inventory_transactions (reingreso de stock)
--   - Finance:  asiento de devolución y recuperación de valor
--
-- Casos reales cubiertos:
--   B2C tienda: cliente devuelve jean en 3 días → restock → NC boleta
--   B2B: empresa devuelve 30 de 50 cajas → NC factura parcial
--   Garantía: laptop falla a los 8 meses → envío al fabricante
--   Producto vencido: destrucción con acta SUNAT (merma autorizada)
--   Producto defectuoso de fábrica: devolución al proveedor
--   Devolución por error del vendedor: NC anulación + re-facturar correcto
-- ============================================================

-- ============================================================
-- 1. AUTORIZACIONES DE DEVOLUCIÓN (RMA)
--    El cliente notifica que quiere devolver.
--    El comercial / sistema aprueba el RMA.
--    Sin RMA aprobado, el almacén no recibe la mercadería.
-- ============================================================
CREATE TABLE sales.return_authorizations (
    id                      BIGSERIAL   PRIMARY KEY,
    company_id              BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    customer_id             BIGINT      NOT NULL REFERENCES sales.customers(id),

    -- Documentos de origen
    original_invoice_id     BIGINT      REFERENCES sales.invoices(id),
    original_order_id       BIGINT      REFERENCES sales.sales_orders(id),
    -- pos_transaction para devoluciones en tienda
    original_pos_tx_id      BIGINT      REFERENCES sales.pos_transactions(id),

    -- Numeración del RMA
    rma_number              VARCHAR(50) NOT NULL,
    -- formato: RMA-2026-001234

    -- Tipo de devolución
    return_type             VARCHAR(30) NOT NULL DEFAULT 'customer_request',
    -- customer_request   : el cliente decidió no quedarse con el producto
    -- defective          : producto defectuoso (falla de fabricación)
    -- wrong_item         : el vendedor despachó el producto equivocado
    -- wrong_quantity     : cantidad equivocada en el despacho
    -- expired            : producto llegó vencido o próximo a vencer
    -- damaged_in_transit : daño ocurrido durante el transporte
    -- warranty           : falla dentro del período de garantía
    -- excess_stock       : cliente tiene exceso de stock (devolución comercial)

    -- Descripción del motivo (para comunicación con el cliente y SUNAT)
    reason_description      TEXT,

    -- ─── Fechas ───────────────────────────────────────────────
    requested_date          DATE        NOT NULL DEFAULT CURRENT_DATE,
    authorized_date         DATE,
    expected_return_date    DATE,
    -- fecha en que el cliente enviará/traerá la mercadería

    actual_receipt_date     DATE,
    -- fecha en que el almacén realmente recibió la devolución

    -- ─── Estado del flujo ─────────────────────────────────────
    status                  VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending              : solicitado, esperando aprobación
    -- authorized           : aprobado, se comunicó al cliente
    -- partially_received   : recibido parcialmente en almacén
    -- fully_received       : todo recibido, en inspección
    -- inspected            : inspección completada
    -- closed               : NC emitida y proceso finalizado
    -- rejected             : RMA rechazado (fuera de plazo, no aplica, etc.)

    authorized_by           BIGINT,
    -- REFERENCES hr.employees(id)
    rejected_reason         TEXT,

    -- ─── Nota de Crédito ──────────────────────────────────────
    issue_credit_note       BOOLEAN     NOT NULL DEFAULT TRUE,
    -- TRUE = al cierre del RMA se emite NC a SUNAT
    -- FALSE = cambio por otro producto (sin NC monetaria)

    credit_note_id          BIGINT      REFERENCES sales.credit_notes(id),
    -- Se puebla cuando se emite la NC al cliente

    -- ─── Vinculación con Logistics ────────────────────────────
    customer_return_id      BIGINT      REFERENCES logistics.customer_returns(id),
    -- La recepción física en almacén está en logistics.customer_returns

    -- ─── Canal de comunicación con el cliente ─────────────────
    contact_method          VARCHAR(20) NOT NULL DEFAULT 'email',
    -- email | whatsapp | phone | in_store
    tracking_number_return  VARCHAR(100),
    -- número de guía del envío de devolución del cliente

    notes                   TEXT,
    internal_notes          TEXT,
    created_by              BIGINT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, rma_number)
);

CREATE INDEX idx_rma_company    ON sales.return_authorizations (company_id);
CREATE INDEX idx_rma_customer   ON sales.return_authorizations (customer_id);
CREATE INDEX idx_rma_invoice    ON sales.return_authorizations (original_invoice_id)
    WHERE original_invoice_id IS NOT NULL;
CREATE INDEX idx_rma_status     ON sales.return_authorizations (status);

CREATE TRIGGER trg_rma_updated_at
    BEFORE UPDATE ON sales.return_authorizations
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.return_authorizations               IS 'RMA: autorización previa para que el cliente devuelva mercadería. Sin RMA aprobado, logistics no recibe.';
COMMENT ON COLUMN sales.return_authorizations.return_type   IS 'Tipo: customer_request | defective | wrong_item | wrong_quantity | expired | damaged_in_transit | warranty | excess_stock.';
COMMENT ON COLUMN sales.return_authorizations.status        IS 'Flujo: pending → authorized → partially_received → fully_received → inspected → closed (o rejected).';

-- ============================================================
-- 2. LÍNEAS DEL RMA (qué productos se esperan devolver)
-- ============================================================
CREATE TABLE sales.return_authorization_lines (
    id                          BIGSERIAL   PRIMARY KEY,
    return_authorization_id     BIGINT      NOT NULL REFERENCES sales.return_authorizations(id) ON DELETE CASCADE,

    product_id                  BIGINT      NOT NULL REFERENCES logistics.products(id),
    variant_id                  BIGINT      REFERENCES logistics.product_variants(id),
    unit_id                     INTEGER     NOT NULL REFERENCES logistics.measurement_units(id),

    -- Referencia a la línea original (para calcular el crédito exacto)
    original_order_line_id      BIGINT      REFERENCES sales.sales_order_lines(id),
    original_invoice_line_id    BIGINT      REFERENCES sales.invoice_lines(id),
    original_pos_line_id        BIGINT      REFERENCES sales.pos_transaction_lines(id),

    -- Cantidades (soporta decimales: 2.5 kg, 1.5 jabas)
    quantity_authorized         NUMERIC(18,4) NOT NULL,
    quantity_received           NUMERIC(18,4) NOT NULL DEFAULT 0,
    quantity_pending            NUMERIC(18,4)
        GENERATED ALWAYS AS (quantity_authorized - quantity_received) STORED,

    -- Precio de referencia (para calcular el crédito)
    unit_price                  NUMERIC(18,6) NOT NULL DEFAULT 0,
    -- igual al precio de la factura original
    total_credit_amount         NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- = quantity_authorized × unit_price (calculado al autorizar)

    -- Motivo específico de esta línea
    return_reason               TEXT,

    -- Trazabilidad de lote y serie
    lot_number                  VARCHAR(100),
    serial_numbers              TEXT,
    -- lista separada por comas si son múltiples series

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_rma_lines_rma     ON sales.return_authorization_lines (return_authorization_id);
CREATE INDEX idx_rma_lines_product ON sales.return_authorization_lines (product_id);

COMMENT ON TABLE  sales.return_authorization_lines                   IS 'Productos y cantidades esperados en la devolución. quantity_pending = autorizado - recibido.';
COMMENT ON COLUMN sales.return_authorization_lines.quantity_pending  IS 'Calculado: autorizado - recibido. Pendiente de recibir del cliente.';
COMMENT ON COLUMN sales.return_authorization_lines.total_credit_amount IS 'Monto del crédito para esta línea = quantity_authorized × unit_price de la factura original.';

-- ============================================================
-- 3. INSPECCIÓN DE LA DEVOLUCIÓN
--    El almacén recibe y revisa el estado de la mercadería.
--    Clasifica las unidades: buen estado / dañado / defectuoso / vencido.
--    El resultado determina la disposición.
-- ============================================================
CREATE TABLE sales.return_inspections (
    id                      BIGSERIAL   PRIMARY KEY,
    return_auth_line_id     BIGINT      NOT NULL REFERENCES sales.return_authorization_lines(id),
    company_id              BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- Resultado de la inspección por estado de calidad
    quantity_received       NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- total recibido en esta inspección

    quantity_good           NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- en buen estado → puede ir a restock
    quantity_damaged        NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- dañado (golpe, roto, empaque roto) → 2da calidad o destrucción
    quantity_defective      NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- defecto de fábrica → devolución al proveedor o garantía
    quantity_expired        NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- vencido → destrucción obligatoria

    -- CHECK: suma de clasificaciones = quantity_received
    CONSTRAINT ck_inspection_quantities CHECK (
        quantity_good + quantity_damaged + quantity_defective + quantity_expired
        <= quantity_received + 0.001
        -- pequeño margen por redondeo en decimales
    ),

    -- Notas de la inspección
    condition_notes         TEXT,
    -- "Caja en buen estado, contenido sin daños"
    -- "2 unidades con golpes en las esquinas"

    -- Evidencia fotográfica (JSON array de URLs)
    photos                  JSONB,
    -- [{"url": "https://...", "description": "Caja golpeada derecha"}]

    -- Quién inspeccionó y cuándo
    inspected_by            BIGINT      NOT NULL,
    -- REFERENCES hr.employees(id)
    inspected_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE: sin updated_at
);

CREATE INDEX idx_inspections_rma_line ON sales.return_inspections (return_auth_line_id);

COMMENT ON TABLE  sales.return_inspections                       IS 'Inspección del producto devuelto: cuántas unidades en buen estado, dañadas, defectuosas o vencidas. Determina la disposición de cada unidad.';
COMMENT ON COLUMN sales.return_inspections.quantity_good         IS 'Buen estado → candidato a restock en inventario.';
COMMENT ON COLUMN sales.return_inspections.quantity_damaged      IS 'Dañado (golpe, empaque roto) → puede venderse como 2da calidad (regrade) o destruirse.';
COMMENT ON COLUMN sales.return_inspections.quantity_defective    IS 'Defecto de fábrica → devolver al proveedor o procesar bajo garantía.';
COMMENT ON COLUMN sales.return_inspections.quantity_expired      IS 'Vencido → destrucción obligatoria. En Perú se requiere acta de merma para SUNAT.';

-- ============================================================
-- 4. DISPOSICIÓN DE LA DEVOLUCIÓN
--    Qué se hace con cada unidad recibida.
--    Una inspección puede generar múltiples disposiciones
--    (ej: 5 unidades → restock, 2 → destrucción, 1 → garantía).
-- ============================================================
CREATE TABLE sales.return_dispositions (
    id                      BIGSERIAL   PRIMARY KEY,
    return_auth_line_id     BIGINT      NOT NULL REFERENCES sales.return_authorization_lines(id),
    inspection_id           BIGINT      REFERENCES sales.return_inspections(id),
    company_id              BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    quantity                NUMERIC(18,4) NOT NULL,
    -- cantidad sujeta a esta disposición

    disposition             VARCHAR(30) NOT NULL,
    -- restock          : vuelve al inventario de venta (buen estado)
    -- scrap            : destrucción (vencido, sin recuperación posible)
    -- refurbish        : reacondicionamiento antes de revender
    -- regrade          : vender como 2da calidad con precio reducido
    -- return_to_supplier: devolver al proveedor (defecto de fábrica)
    -- warranty_repair  : enviar a reparación bajo garantía
    -- donate           : donación (para merma con beneficio tributario)
    -- on_hold          : en espera de decisión superior

    -- ─── Para restock ─────────────────────────────────────────
    warehouse_id            BIGINT      REFERENCES logistics.warehouses(id),
    -- almacén destino del restock

    -- ─── Para scrap / destrucción (SUNAT requiere acta) ───────
    destruction_cert_number VARCHAR(100),
    -- número del acta de destrucción o merma
    destruction_date        DATE,
    destruction_witnessed_by VARCHAR(300),
    -- nombre del notario o representante SUNAT que presenció

    -- ─── Para devolución al proveedor ─────────────────────────
    supplier_id             BIGINT      REFERENCES logistics.suppliers(id),
    supplier_return_ref     VARCHAR(100),
    -- referencia de la devolución en el sistema del proveedor

    -- ─── Para garantía / reparación ───────────────────────────
    warranty_claim_id       BIGINT,
    -- REFERENCES sales.warranty_claims(id) — FK diferida

    -- ─── Valor de recuperación ────────────────────────────────
    estimated_recovery_value NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- valor estimado que se recuperará de esta disposición
    -- restock: valor de venta | scrap: 0 | refurbish: precio reducido

    -- ─── Vinculación con Logistics ────────────────────────────
    -- La entrada de inventario se hace via logistics.inventory_transactions
    inventory_transaction_id BIGINT,
    -- REFERENCES logistics.inventory_transactions(id) — sin FK para no crear dependencia circular

    notes                   TEXT,
    processed_by            BIGINT      NOT NULL,
    -- REFERENCES hr.employees(id)
    processed_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- INMUTABLE: sin updated_at
);

CREATE INDEX idx_dispositions_rma_line   ON sales.return_dispositions (return_auth_line_id);
CREATE INDEX idx_dispositions_inspection ON sales.return_dispositions (inspection_id)
    WHERE inspection_id IS NOT NULL;
CREATE INDEX idx_dispositions_warehouse  ON sales.return_dispositions (warehouse_id)
    WHERE warehouse_id IS NOT NULL;
CREATE INDEX idx_dispositions_supplier   ON sales.return_dispositions (supplier_id)
    WHERE supplier_id IS NOT NULL;

COMMENT ON TABLE  sales.return_dispositions                         IS 'Qué se hace con cada unidad devuelta: restock | scrap | refurbish | regrade | return_to_supplier | warranty_repair | donate.';
COMMENT ON COLUMN sales.return_dispositions.disposition             IS 'Destino: restock=inventario | scrap=destrucción | refurbish=reacondicionamiento | regrade=2da calidad | return_to_supplier=proveedor | warranty_repair=garantía | donate=donación.';
COMMENT ON COLUMN sales.return_dispositions.destruction_cert_number IS 'Número del acta de merma o destrucción. Requerido por SUNAT para productos vencidos o destruidos.';
COMMENT ON COLUMN sales.return_dispositions.estimated_recovery_value IS 'Valor que se recuperará de esta unidad. Base para el asiento contable de recuperación de merma.';

-- ============================================================
-- 5. GARANTÍAS (WARRANTY CLAIMS)
--    Gestión de productos que fallan dentro del período
--    de garantía. Puede resultar en reparación, reemplazo
--    o devolución de dinero.
-- ============================================================
CREATE TABLE sales.warranty_claims (
    id                      BIGSERIAL   PRIMARY KEY,
    company_id              BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    customer_id             BIGINT      NOT NULL REFERENCES sales.customers(id),
    product_id              BIGINT      NOT NULL REFERENCES logistics.products(id),
    variant_id              BIGINT      REFERENCES logistics.product_variants(id),

    -- Compra original
    original_invoice_id     BIGINT      REFERENCES sales.invoices(id),
    serial_number           VARCHAR(200),
    -- número de serie del producto en garantía

    -- Numeración de la reclamación
    claim_number            VARCHAR(50) NOT NULL,

    -- Tipo de resolución esperada
    resolution_type         VARCHAR(20) NOT NULL DEFAULT 'repair',
    -- repair         : reparar y devolver al cliente
    -- replace        : cambiar por unidad nueva
    -- refund         : devolución de dinero
    -- partial_refund : devolución parcial (por depreciación o uso)
    -- credit         : nota de crédito para usar en futuras compras

    -- ─── Fechas ───────────────────────────────────────────────
    claim_date              DATE        NOT NULL DEFAULT CURRENT_DATE,
    received_date           DATE,
    -- fecha en que el producto llegó al servicio técnico
    promised_resolution_date DATE,
    -- fecha prometida de resolución
    resolution_date         DATE,
    -- fecha real de resolución

    -- Descripción del defecto
    defect_description      TEXT        NOT NULL,
    -- "La pantalla se apagó sin motivo aparente"
    -- "La cremallera se rompió al primer uso"
    technical_notes         TEXT,
    -- notas internas del técnico

    -- ─── Estado ───────────────────────────────────────────────
    status                  VARCHAR(20) NOT NULL DEFAULT 'open',
    -- open          : recibido, en evaluación
    -- in_diagnosis  : en diagnóstico técnico
    -- in_repair     : en reparación
    -- waiting_parts : esperando repuestos
    -- pending_replacement : esperando stock del reemplazo
    -- resolved      : resuelto (reparado/cambiado/reembolsado)
    -- rejected      : rechazado (fuera de garantía, daño por usuario)

    -- ¿Queda cubierto por la garantía del fabricante?
    covered_by_warranty     BOOLEAN     NOT NULL DEFAULT TRUE,
    warranty_rejection_reason TEXT,
    -- si no está cubierto, por qué (daño por usuario, mal uso, etc.)

    -- ─── Costos ───────────────────────────────────────────────
    repair_cost             NUMERIC(18,4) NOT NULL DEFAULT 0,
    cost_to_customer        NUMERIC(18,4) NOT NULL DEFAULT 0,
    -- si no está cubierto, cuánto paga el cliente

    -- ─── Resolución ───────────────────────────────────────────
    credit_note_id          BIGINT      REFERENCES sales.credit_notes(id),
    -- si la resolución es refund o partial_refund
    replacement_order_id    BIGINT      REFERENCES sales.sales_orders(id),
    -- si la resolución es replace (nueva orden de despacho)

    -- ─── RMA vinculado ────────────────────────────────────────
    return_authorization_id BIGINT      REFERENCES sales.return_authorizations(id),
    -- el RMA que autorizó la recepción del producto a garantía

    -- ─── Responsable ──────────────────────────────────────────
    handled_by              BIGINT,
    -- REFERENCES hr.employees(id) — técnico o representante

    notes                   TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, claim_number)
);

CREATE INDEX idx_warranty_customer ON sales.warranty_claims (customer_id);
CREATE INDEX idx_warranty_product  ON sales.warranty_claims (product_id);
CREATE INDEX idx_warranty_invoice  ON sales.warranty_claims (original_invoice_id)
    WHERE original_invoice_id IS NOT NULL;
CREATE INDEX idx_warranty_status   ON sales.warranty_claims (status);

CREATE TRIGGER trg_warranty_claims_updated_at
    BEFORE UPDATE ON sales.warranty_claims
    FOR EACH ROW EXECUTE FUNCTION sales.set_updated_at();

COMMENT ON TABLE  sales.warranty_claims                        IS 'Reclamaciones de garantía. Puede resultar en reparación, reemplazo o NC. Vinculado al RMA para el flujo físico del producto.';
COMMENT ON COLUMN sales.warranty_claims.resolution_type        IS 'repair | replace | refund | partial_refund | credit.';
COMMENT ON COLUMN sales.warranty_claims.covered_by_warranty    IS 'FALSE = no cubre garantía (daño por usuario). El cliente asume el costo de la reparación.';
COMMENT ON COLUMN sales.warranty_claims.replacement_order_id   IS 'Si la resolución es reemplazar la unidad, se crea una sales_order nueva para el despacho.';

-- ============================================================
-- 6. FK DIFERIDA: warranty_claims → return_dispositions
-- ============================================================
ALTER TABLE sales.return_dispositions
    ADD CONSTRAINT fk_dispositions_warranty
    FOREIGN KEY (warranty_claim_id)
    REFERENCES sales.warranty_claims(id)
    ON DELETE SET NULL;
