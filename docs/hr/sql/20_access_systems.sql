-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.access_systems
-- Descripción: Catálogo de sistemas o plataformas que emiten
--              códigos/claves de acceso a empleados.
--              Ej: Telefónica, VPN corporativa, SAP, Active Directory.
-- ============================================================

CREATE TABLE hr.access_systems (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    name                VARCHAR(150)    NOT NULL,   -- "Telefónica", "VPN", "SAP HR", "Active Directory"
    description         TEXT,
    type                VARCHAR(50),               -- platform | network | application | service | other
    access_url          TEXT,                      -- URL del sistema si aplica

    -- Política de rotación de códigos
    requires_rotation   BOOLEAN         DEFAULT FALSE,
    rotation_frequency  VARCHAR(20),               -- monthly | quarterly | biannual | annual | custom
    rotation_days       SMALLINT,                  -- Si es custom, cantidad de días entre rotaciones

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_access_systems_company ON hr.access_systems (company_id);

CREATE TRIGGER trg_access_systems_updated_at
    BEFORE UPDATE ON hr.access_systems
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.access_systems                    IS 'Catálogo de sistemas que emiten códigos a empleados (Telefónica, VPN, SAP, etc.).';
COMMENT ON COLUMN hr.access_systems.rotation_frequency IS 'Frecuencia de rotación: monthly | quarterly | biannual | annual | custom';
COMMENT ON COLUMN hr.access_systems.rotation_days      IS 'Días entre rotaciones cuando rotation_frequency = custom.';
