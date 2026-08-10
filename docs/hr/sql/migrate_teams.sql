-- ============================================================
-- MIGRACIÓN: hr.teams + hr.team_members
-- ============================================================
-- Equipos operativos de trabajo — separado de la jerarquía de
-- aprobación (reports_to) y de los equipos de proyecto.
--
-- hr.teams        → catálogo de equipos por empresa
-- hr.team_members → asignación de empleados con historial completo
--
-- Principio: igual que hr.employee_reporting_history
--   · Nunca se borran registros
--   · left_at IS NULL = miembro activo hoy
--   · Historial completo de movimientos de cada empleado
-- ============================================================

BEGIN;

-- ── 1. hr.teams ───────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS hr.teams (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    name            VARCHAR(150)    NOT NULL,
    description     TEXT,

    -- Tipo de equipo
    team_type       VARCHAR(30)     NOT NULL DEFAULT 'operational',
    -- 'operational' → equipo de trabajo del día a día (Equipo Ventas Norte)
    -- 'shift'       → equipo por turno (Turno Mañana, Turno Noche)
    -- 'functional'  → equipo funcional transversal (Equipo Calidad)

    -- Líder actual del equipo (conveniencia, igual que reports_to)
    -- El historial de líderes está en hr.team_members con role = 'leader'
    leader_id       BIGINT          REFERENCES hr.employees(id),

    -- Departamento al que pertenece el equipo (opcional)
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

COMMENT ON TABLE  hr.teams             IS 'Equipos operativos de trabajo. Separado de reports_to (aprobaciones) y de project_members (proyectos).';
COMMENT ON COLUMN hr.teams.leader_id   IS 'Líder actual del equipo (conveniencia). Historial completo en hr.team_members con role=leader.';
COMMENT ON COLUMN hr.teams.team_type   IS 'operational | shift | functional';

-- ── 2. hr.team_members ────────────────────────────────────────────────────────
-- Historial completo de asignaciones. Nunca se borran filas.
-- joined_at / left_at definen el período de pertenencia.

CREATE TABLE IF NOT EXISTS hr.team_members (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    team_id         BIGINT          NOT NULL REFERENCES hr.teams(id) ON DELETE RESTRICT,
    employee_id     BIGINT          NOT NULL REFERENCES hr.employees(id) ON DELETE RESTRICT,

    -- Rol dentro del equipo
    role            VARCHAR(20)     NOT NULL DEFAULT 'member',
    -- 'leader' → coordina el equipo (puede coincidir o no con el aprobador)
    -- 'member' → integrante del equipo

    -- Período de pertenencia
    joined_at       DATE            NOT NULL DEFAULT CURRENT_DATE,
    left_at         DATE,
    -- NULL = miembro activo hoy

    -- Motivo del movimiento (entrada o salida)
    reason          VARCHAR(200),
    -- 'incorporación', 'reorganización', 'cambio de turno', 'baja del equipo'

    -- Quién hizo el movimiento
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
CREATE UNIQUE INDEX IF NOT EXISTS idx_team_members_one_leader
    ON hr.team_members (team_id)
    WHERE role = 'leader' AND left_at IS NULL;

-- Solo una membresía activa por empleado por equipo
CREATE UNIQUE INDEX IF NOT EXISTS idx_team_members_active
    ON hr.team_members (team_id, employee_id)
    WHERE left_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_team_members_team     ON hr.team_members (team_id);
CREATE INDEX IF NOT EXISTS idx_team_members_employee ON hr.team_members (employee_id);
CREATE INDEX IF NOT EXISTS idx_team_members_company  ON hr.team_members (company_id);
CREATE INDEX IF NOT EXISTS idx_team_members_active_all
    ON hr.team_members (company_id, employee_id)
    WHERE left_at IS NULL;

COMMENT ON TABLE  hr.team_members            IS 'Historial de asignaciones a equipos. Nunca se borran — left_at IS NULL = miembro activo.';
COMMENT ON COLUMN hr.team_members.role       IS 'leader | member';
COMMENT ON COLUMN hr.team_members.joined_at  IS 'Fecha de incorporación al equipo';
COMMENT ON COLUMN hr.team_members.left_at    IS 'Fecha de salida del equipo. NULL = activo hoy.';
COMMENT ON COLUMN hr.team_members.reason     IS 'Motivo del movimiento: incorporación, reorganización, cambio de turno, etc.';
COMMENT ON COLUMN hr.team_members.created_by IS 'Admin o manager que registró el movimiento';

-- ── 3. Función helper: añadir empleado a un equipo ───────────────────────────
-- Si ya tiene una membresía activa en ese equipo, la cierra primero.
-- Uso: SELECT hr.assign_team_member(team_id, employee_id, 'member', 'reorganización', created_by_id);

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

    -- Si hay membresía activa en este equipo, cerrarla
    UPDATE hr.team_members
       SET left_at = p_joined_at - INTERVAL '1 day',
           reason  = COALESCE(reason, p_reason)
     WHERE team_id     = p_team_id
       AND employee_id = p_employee_id
       AND left_at     IS NULL;

    -- Si el nuevo rol es líder, cerrar el líder actual
    IF p_role = 'leader' THEN
        UPDATE hr.team_members
           SET left_at = p_joined_at - INTERVAL '1 day',
               reason  = COALESCE(reason, 'cambio de líder')
         WHERE team_id = p_team_id
           AND role    = 'leader'
           AND left_at IS NULL
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

-- ── 4. Función helper: sacar empleado de un equipo ───────────────────────────
-- Uso: SELECT hr.remove_team_member(team_id, employee_id, 'baja del equipo', created_by_id);

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
       AND left_at     IS NULL;

    -- Si era el líder, limpiar la conveniencia en hr.teams
    UPDATE hr.teams
       SET leader_id = NULL
     WHERE id = p_team_id
       AND leader_id = p_employee_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION hr.assign_team_member IS
    'Asigna un empleado a un equipo. Cierra membresía anterior si existe. Si role=leader, desplaza al líder actual.';
COMMENT ON FUNCTION hr.remove_team_member IS
    'Saca a un empleado de un equipo cerrando su membresía (left_at). No borra el registro histórico.';

COMMIT;
