-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.equipment_assignments
-- Descripción: Historial de asignación de equipos a empleados.
--              Un equipo puede ser reasignado; el historial se
--              conserva completo. returned_at NULL = asignación vigente.
-- ============================================================

CREATE TABLE hr.equipment_assignments (
    id                      BIGSERIAL       PRIMARY KEY,
    equipment_id            BIGINT          NOT NULL REFERENCES hr.equipment(id) ON DELETE RESTRICT,
    employee_id             BIGINT          NOT NULL REFERENCES hr.employees(id) ON DELETE RESTRICT,

    -- Vigencia
    assigned_at             DATE            NOT NULL DEFAULT CURRENT_DATE,
    returned_at             DATE,                       -- NULL = asignación actualmente vigente

    -- Condición del equipo al entregar y al devolver
    condition_on_delivery   VARCHAR(30)     DEFAULT 'good',  -- new | good | fair | damaged
    condition_on_return     VARCHAR(30),

    -- Evidencia
    delivery_document_url   TEXT,           -- Acta de entrega firmada
    return_document_url     TEXT,           -- Acta de devolución firmada

    notes                   TEXT,
    recorded_by             BIGINT          REFERENCES hr.employees(id), -- Quién registró la asignación

    is_active               BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_eq_assign_equipment ON hr.equipment_assignments (equipment_id);
CREATE INDEX idx_eq_assign_employee  ON hr.equipment_assignments (employee_id);
CREATE INDEX idx_eq_assign_active    ON hr.equipment_assignments (equipment_id) WHERE returned_at IS NULL;

CREATE TRIGGER trg_equipment_assignments_updated_at
    BEFORE UPDATE ON hr.equipment_assignments
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.equipment_assignments                      IS 'Historial de asignación de equipos. returned_at NULL = vigente.';
COMMENT ON COLUMN hr.equipment_assignments.condition_on_delivery IS 'Estado del equipo al entregarlo: new | good | fair | damaged';
COMMENT ON COLUMN hr.equipment_assignments.delivery_document_url IS 'URL del acta de entrega firmada por el empleado.';
