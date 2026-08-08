-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.access_codes
-- Descripción: Registro de cada código/clave asignable dentro
--              de un sistema. Los códigos son reutilizables:
--              se reasignan a distintos empleados en el tiempo.
--              Ej: "pindi", "t7", "usr_045"
-- ============================================================

CREATE TABLE hr.access_codes (
    id          BIGSERIAL       PRIMARY KEY,
    system_id   BIGINT          NOT NULL REFERENCES hr.access_systems(id) ON DELETE RESTRICT,

    code        VARCHAR(100)    NOT NULL,       -- El código en sí: "pindi", "t7", "usr_045"
    description TEXT,
    code_type   VARCHAR(50),                   -- username | pin | token | license | other

    -- Estado actual
    status      VARCHAR(20)     NOT NULL DEFAULT 'available',
    -- available | assigned | suspended | decommissioned

    is_active   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_access_codes_system ON hr.access_codes (system_id);
CREATE INDEX idx_access_codes_status ON hr.access_codes (status);
CREATE UNIQUE INDEX idx_access_codes_code ON hr.access_codes (system_id, code);

CREATE TRIGGER trg_access_codes_updated_at
    BEFORE UPDATE ON hr.access_codes
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.access_codes        IS 'Códigos asignables dentro de un sistema (pindi, t7, usr_045). Reutilizables.';
COMMENT ON COLUMN hr.access_codes.code   IS 'El código literal que se asigna al empleado.';
COMMENT ON COLUMN hr.access_codes.status IS 'Estado: available | assigned | suspended | decommissioned';
