-- ============================================================
-- mantrasdb | Módulo HR
-- Tabla: hr.disciplinary_actions
-- Descripción: Registro de acciones disciplinarias formales.
--              Los documentos PDF asociados (acta firmada, apelación)
--              se guardan en hr.documents con entity_type = 'disciplinary_action'.
-- ============================================================

CREATE TABLE hr.disciplinary_actions (
    id                  BIGSERIAL       PRIMARY KEY,
    company_id          BIGINT          NOT NULL REFERENCES hr.companies(id),
    employee_id         BIGINT          NOT NULL REFERENCES hr.employees(id),

    -- Clasificación
    severity            VARCHAR(20)     NOT NULL DEFAULT 'minor',
    -- minor | major | critical
    reason              VARCHAR(100)    NOT NULL,
    -- repeated_tardiness | unjustified_absence | inappropriate_conduct |
    -- policy_violation | asset_damage | resource_misuse | other
    description         TEXT            NOT NULL,

    -- Fechas
    incident_date       DATE            NOT NULL,
    notification_date   DATE            NOT NULL DEFAULT CURRENT_DATE,

    -- Impacto económico
    has_deduction       BOOLEAN         NOT NULL DEFAULT FALSE,
    deduction_amount    NUMERIC(12,2),
    payroll_period_id   BIGINT          REFERENCES hr.payroll_periods(id),
    -- Período de nómina donde se aplica el descuento

    -- Proceso de firma
    signed_by_employee  BOOLEAN         NOT NULL DEFAULT FALSE,
    signed_at           DATE,
    refused_to_sign     BOOLEAN         NOT NULL DEFAULT FALSE,
    -- TRUE = el empleado se negó a firmar (igual es válida, se registran testigos)

    -- Apelación
    appealed            BOOLEAN         NOT NULL DEFAULT FALSE,
    appeal_date         DATE,
    appeal_result       VARCHAR(20),
    -- pending | accepted | rejected
    appeal_notes        TEXT,

    -- Responsable
    issued_by           BIGINT          NOT NULL REFERENCES hr.employees(id),

    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_disc_actions_employee  ON hr.disciplinary_actions (employee_id);
CREATE INDEX idx_disc_actions_company   ON hr.disciplinary_actions (company_id);
CREATE INDEX idx_disc_actions_date      ON hr.disciplinary_actions (incident_date);
CREATE INDEX idx_disc_actions_severity  ON hr.disciplinary_actions (severity);

CREATE TRIGGER trg_disciplinary_actions_updated_at
    BEFORE UPDATE ON hr.disciplinary_actions
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.disciplinary_actions                IS 'Acciones disciplinarias formales. PDFs en hr.documents (entity_type=disciplinary_action).';
COMMENT ON COLUMN hr.disciplinary_actions.severity       IS 'Gravedad: minor (leve) | major (grave) | critical (muy grave)';
COMMENT ON COLUMN hr.disciplinary_actions.refused_to_sign IS 'Si el empleado se negó a firmar, la acción sigue siendo válida.';
COMMENT ON COLUMN hr.disciplinary_actions.payroll_period_id IS 'Período de nómina donde se aplica el descuento si corresponde.';
