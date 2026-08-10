-- ============================================================
-- MIGRACIÓN: hr.teams + hr.team_members
-- ============================================================
-- Equipos operativos de trabajo — separado de:
--   · reports_to         → jerarquía de aprobación
--   · project_members    → equipos de proyecto
--
-- Reglas clave:
--   · Un empleado puede estar en MÚLTIPLES equipos simultáneamente
--   · Un empleado puede ser líder en un equipo y miembro en otros
--   · Un equipo puede existir SIN líder temporalmente
--   · Nunca se borran registros — is_cancelled para errores
--   · left_at IS NULL AND is_cancelled = FALSE → membresía activa
-- ============================================================

BEGIN;

-- ── 1. hr.teams ───────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS hr.teams (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    name            VARCHAR(150)    NOT NULL,
    description     TEXT,

    team_type       VARCHAR(30)     NOT NULL DEFAULT 'operational',
    -- 'operational' → equipo del día a día (Equipo Ventas Norte)
    -- 'shift'       → equipo por turno (Turno Mañana, Turno Noche)
    -- 'functional'  → equipo transversal (Comité de Calidad)

    -- Líder actual (conveniencia — puede ser NULL si no hay líder)
    -- Historial de líderes en hr.team_members WHERE role = 'leader'
    leader_id       BIGINT          REFERENCES hr.employees(id),

    department_id   BIGINT          REFERENCES hr.departments(id),

    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_team_type CHECK (
        team_type IN ('operational', 'shift', 'functional')
    ),
    UNIQUE (company_id, name)
);

CREATE TRIGGER trg_teams_updated_at
    BEFORE UPDATE ON hr.teams
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_teams_company    ON hr.teams (company_id);
CREATE INDEX IF NOT EXISTS idx_teams_leader     ON hr.teams (leader_id);
CREATE INDEX IF NOT EXISTS idx_teams_department ON hr.teams (department_id);
CREATE INDEX IF NOT EXISTS idx_teams_active     ON hr.teams (company_id) WHERE is_active = true;

COMMENT ON TABLE  hr.teams            IS 'Equipos operativos. Separado de reports_to (aprobaciones) y project_members (proyectos).';
COMMENT ON COLUMN hr.teams.leader_id  IS 'Líder actual (conveniencia). NULL = equipo sin líder. Historial en hr.team_members role=leader.';
COMMENT ON COLUMN hr.teams.team_type  IS 'operational | shift | functional';

-- ── 2. hr.team_members ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS hr.team_members (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    team_id         BIGINT          NOT NULL REFERENCES hr.teams(id) ON DELETE RESTRICT,
    employee_id     BIGINT          NOT NULL REFERENCES hr.employees(id) ON DELETE RESTRICT,

    role            VARCHAR(20)     NOT NULL DEFAULT 'member',
    -- 'leader' → coordina el equipo (no implica ser aprobador de ausencias)
    -- 'member' → integrante

    -- Período de pertenencia
    joined_at       DATE            NOT NULL DEFAULT CURRENT_DATE,
    left_at         DATE,
    -- NULL = aún activo en este equipo

    -- Cancelación por error (sin borrar el registro)
    is_cancelled        BOOLEAN     NOT NULL DEFAULT FALSE,
    cancel_reason       TEXT,
    cancelled_by        BIGINT      REFERENCES hr.employees(id),
    cancelled_at        TIMESTAMPTZ,

    -- Motivo del movimiento
    reason          VARCHAR(200),

    -- Quién registró el movimiento
    created_by      BIGINT          REFERENCES hr.employees(id),

    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_team_member_role CHECK (role IN ('leader', 'member')),
    CONSTRAINT chk_team_member_dates CHECK (
        left_at IS NULL OR left_at >= joined_at
    )
);

CREATE TRIGGER trg_team_members_updated_at
    BEFORE UPDATE ON hr.team_members
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

-- Solo un líder activo por equipo a la vez
-- (pero ese líder puede ser líder en otros equipos sin restricción)
CREATE UNIQUE INDEX IF NOT EXISTS idx_team_members_one_leader
    ON hr.team_members (team_id)
    WHERE role = 'leader' AND left_at IS NULL AND is_cancelled = FALSE;

-- NO hay unique en membresía activa por empleado por equipo:
-- un empleado puede estar en múltiples equipos simultáneamente

CREATE INDEX IF NOT EXISTS idx_team_members_team      ON hr.team_members (team_id);
CREATE INDEX IF NOT EXISTS idx_team_members_employee  ON hr.team_members (employee_id);
CREATE INDEX IF NOT EXISTS idx_team_members_company   ON hr.team_members (company_id);
-- Membresías activas (para dashboards y vistas de equipo)
CREATE INDEX IF NOT EXISTS idx_team_members_active
    ON hr.team_members (company_id, team_id, employee_id)
    WHERE left_at IS NULL AND is_cancelled = FALSE;

COMMENT ON TABLE  hr.team_members                IS 'Historial de asignaciones a equipos. Nunca se borran — usar is_cancelled para errores.';
COMMENT ON COLUMN hr.team_members.role           IS 'leader | member. Un empleado puede ser líder en un equipo y miembro en otros.';
COMMENT ON COLUMN hr.team_members.joined_at      IS 'Fecha de incorporación';
COMMENT ON COLUMN hr.team_members.left_at        IS 'Fecha de salida. NULL = activo.';
COMMENT ON COLUMN hr.team_members.is_cancelled   IS 'TRUE = asignación por error. Se conserva para auditoría pero no cuenta como activa.';
COMMENT ON COLUMN hr.team_members.cancel_reason  IS 'Motivo de la cancelación por error';

-- ── 3. hr.assign_team_member ─────────────────────────────────────────────────
-- Añade un empleado a un equipo.
-- Si ya tiene membresía activa en ese equipo, la cierra antes de abrir una nueva.
-- Si el rol es líder, desplaza al líder actual cerrando su período.
-- Un empleado puede estar en múltiples equipos — no cierra otras membresías.

CREATE OR REPLACE FUNCTION hr.assign_team_member(
    p_team_id       BIGINT,
    p_employee_id   BIGINT,
    p_role          VARCHAR(20)     DEFAULT 'member',
    p_reason        VARCHAR(200)    DEFAULT NULL,
    p_created_by    BIGINT          DEFAULT NULL,
    p_joined_at     DATE            DEFAULT CURRENT_DATE
)
RETURNS hr.team_members AS $$
DECLARE
    v_company_id    BIGINT;
    v_new_row       hr.team_members;
BEGIN
    SELECT company_id INTO v_company_id FROM hr.teams WHERE id = p_team_id;

    -- Cerrar membresía activa previa en ESTE equipo (si existe)
    UPDATE hr.team_members
       SET left_at    = p_joined_at - INTERVAL '1 day',
           reason     = COALESCE(reason, 'reingreso al equipo'),
           updated_at = NOW()
     WHERE team_id     = p_team_id
       AND employee_id = p_employee_id
       AND left_at     IS NULL
       AND is_cancelled = FALSE;

    -- Si el nuevo rol es líder, desplazar al líder actual
    IF p_role = 'leader' THEN
        UPDATE hr.team_members
           SET left_at    = p_joined_at - INTERVAL '1 day',
               reason     = COALESCE(reason, 'cambio de líder'),
               updated_at = NOW()
         WHERE team_id     = p_team_id
           AND role        = 'leader'
           AND left_at     IS NULL
           AND is_cancelled = FALSE
           AND employee_id != p_employee_id;

        -- Actualizar conveniencia en hr.teams
        UPDATE hr.teams SET leader_id = p_employee_id WHERE id = p_team_id;
    END IF;

    -- Insertar nueva membresía
    INSERT INTO hr.team_members
        (company_id, team_id, employee_id, role, joined_at, reason, created_by)
    VALUES
        (v_company_id, p_team_id, p_employee_id, p_role, p_joined_at, p_reason, p_created_by)
    RETURNING * INTO v_new_row;

    RETURN v_new_row;
END;
$$ LANGUAGE plpgsql;

-- ── 4. hr.remove_team_member ──────────────────────────────────────────────────
-- Saca a un empleado de un equipo cerrando su membresía activa.
-- Si era el líder, deja el equipo sin líder (leader_id = NULL).

CREATE OR REPLACE FUNCTION hr.remove_team_member(
    p_team_id       BIGINT,
    p_employee_id   BIGINT,
    p_reason        VARCHAR(200)    DEFAULT NULL,
    p_created_by    BIGINT          DEFAULT NULL,
    p_left_at       DATE            DEFAULT CURRENT_DATE
)
RETURNS VOID AS $$
BEGIN
    UPDATE hr.team_members
       SET left_at    = p_left_at,
           reason     = COALESCE(p_reason, reason),
           updated_at = NOW()
     WHERE team_id     = p_team_id
       AND employee_id = p_employee_id
       AND left_at     IS NULL
       AND is_cancelled = FALSE;

    -- Si era el líder, limpiar conveniencia
    UPDATE hr.teams
       SET leader_id = NULL
     WHERE id        = p_team_id
       AND leader_id = p_employee_id;
END;
$$ LANGUAGE plpgsql;

-- ── 5. hr.cancel_team_member ──────────────────────────────────────────────────
-- Cancela una asignación por error. No borra el registro.

CREATE OR REPLACE FUNCTION hr.cancel_team_member(
    p_member_id     BIGINT,
    p_cancel_reason TEXT            DEFAULT NULL,
    p_cancelled_by  BIGINT          DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_member hr.team_members;
BEGIN
    SELECT * INTO v_member FROM hr.team_members WHERE id = p_member_id;

    UPDATE hr.team_members
       SET is_cancelled  = TRUE,
           cancel_reason = p_cancel_reason,
           cancelled_by  = p_cancelled_by,
           cancelled_at  = NOW(),
           updated_at    = NOW()
     WHERE id = p_member_id;

    -- Si era líder activo, limpiar conveniencia en hr.teams
    IF v_member.role = 'leader' AND v_member.left_at IS NULL THEN
        UPDATE hr.teams
           SET leader_id = NULL
         WHERE id        = v_member.team_id
           AND leader_id = v_member.employee_id;
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION hr.assign_team_member  IS 'Añade empleado al equipo. Cierra membresía previa en ESE equipo. Si es líder, desplaza al actual. No toca otras membresías en otros equipos.';
COMMENT ON FUNCTION hr.remove_team_member  IS 'Saca empleado del equipo cerrando membresía activa. El equipo puede quedar sin líder.';
COMMENT ON FUNCTION hr.cancel_team_member  IS 'Cancela asignación por error sin borrar el registro. Audit trail completo.';

COMMIT;
