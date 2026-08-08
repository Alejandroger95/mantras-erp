-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.equipment_types
-- Descripción: Catálogo de tipos de equipo/activo asignable.
-- ============================================================

CREATE TABLE hr.equipment_types (
    id          BIGSERIAL       PRIMARY KEY,
    company_id  BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    name        VARCHAR(100)    NOT NULL,   -- Laptop, Mobile Phone, Tablet, Vehicle, Tool, etc.
    description TEXT,
    icon        VARCHAR(50),               -- Nombre de ícono para la UI (opcional)

    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_equipment_types_company ON hr.equipment_types (company_id);

CREATE TRIGGER trg_equipment_types_updated_at
    BEFORE UPDATE ON hr.equipment_types
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE hr.equipment_types IS 'Catálogo de categorías de equipo: laptop, celular, vehículo, herramienta, etc.';
