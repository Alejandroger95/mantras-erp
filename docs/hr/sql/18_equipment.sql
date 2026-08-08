-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.equipment
-- Descripción: Inventario de equipos y activos de la empresa.
-- ============================================================

CREATE TABLE hr.equipment (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    equipment_type_id   BIGINT          NOT NULL REFERENCES hr.equipment_types(id) ON DELETE RESTRICT,

    -- Identificación del equipo
    name                VARCHAR(150)    NOT NULL,   -- Ej: "Dell Laptop #12", "iPhone 14 Pro"
    brand               VARCHAR(100),
    model               VARCHAR(150),
    serial_number       VARCHAR(150),               -- Número de serie del fabricante
    inventory_number    VARCHAR(100),               -- Código interno de la empresa
    asset_code          VARCHAR(100),               -- Código contable / activo fijo

    -- Estado actual
    status              VARCHAR(30)     NOT NULL DEFAULT 'available',
    -- available | assigned | under_repair | decommissioned | lost

    -- Valores y compra
    purchase_date       DATE,
    purchase_value      NUMERIC(14,2),
    currency            CHAR(3)         DEFAULT 'USD',
    supplier            VARCHAR(200),
    warranty_until      DATE,

    -- Notas
    description         TEXT,
    notes               TEXT,
    image_url           TEXT,

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_equipment_company       ON hr.equipment (company_id);
CREATE INDEX idx_equipment_type          ON hr.equipment (equipment_type_id);
CREATE INDEX idx_equipment_status        ON hr.equipment (status);
CREATE UNIQUE INDEX idx_equipment_serial ON hr.equipment (company_id, serial_number)    WHERE serial_number IS NOT NULL;
CREATE UNIQUE INDEX idx_equipment_inv    ON hr.equipment (company_id, inventory_number)  WHERE inventory_number IS NOT NULL;

CREATE TRIGGER trg_equipment_updated_at
    BEFORE UPDATE ON hr.equipment
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.equipment                   IS 'Inventario de equipos y activos asignables a empleados.';
COMMENT ON COLUMN hr.equipment.status            IS 'Estado: available | assigned | under_repair | decommissioned | lost';
COMMENT ON COLUMN hr.equipment.serial_number     IS 'Número de serie del fabricante.';
COMMENT ON COLUMN hr.equipment.inventory_number  IS 'Código interno de inventario de la empresa.';
COMMENT ON COLUMN hr.equipment.asset_code        IS 'Código contable para activos fijos.';
