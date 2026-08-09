-- ============================================================
-- mantrasdb | Módulo HR
-- Archivo: 99_system_users_audit.sql
-- Descripción: Usuarios del sistema + auditoría completa.
--
-- IMPORTANTE — Seguridad:
--   Las contraseñas NO se guardan aquí.
--   La autenticación la maneja AWS Cognito.
--   Solo guardamos el cognito_user_id (UUID) para enlazar
--   al usuario con sus datos en nuestra base de datos.
--
-- Patrón de auditoría:
--   Todas las tablas tienen:
--     created_by_user_id BIGINT → quién creó el registro
--     updated_by_user_id BIGINT → quién hizo el último cambio
--   La función set_audit_user() los llena automáticamente
--   via trigger, leyendo el ID del usuario de la sesión PG.
-- ============================================================

-- ============================================================
-- 1. USUARIOS DEL SISTEMA
-- ============================================================
CREATE TABLE hr.system_users (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- Enlace a la persona (datos personales en hr.persons)
    person_id           BIGINT      REFERENCES hr.persons(id),

    -- Enlace al empleado (si el usuario es empleado de la empresa)
    employee_id         BIGINT,
    -- REFERENCES hr.employees(id) — FK diferida para evitar circular

    -- Identidad de login (manejada por AWS Cognito)
    cognito_user_id     VARCHAR(100) NOT NULL UNIQUE,
    -- UUID que devuelve Cognito al crear el usuario
    -- Ejemplo: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"

    email               VARCHAR(255) NOT NULL,
    -- email del usuario (sincronizado con Cognito)

    -- Nombre para mostrar en la UI (puede diferir del legal)
    display_name        VARCHAR(200) NOT NULL,

    -- Rol principal del usuario en esta empresa
    role                VARCHAR(30)  NOT NULL DEFAULT 'user',
    -- super_admin   : acceso total al sistema (Alejandro 🐶)
    -- admin         : administrador de la empresa
    -- accountant    : módulo Finance
    -- warehouse     : módulo Logistics/WMS
    -- sales_rep     : módulo Sales (solo sus ventas)
    -- sales_manager : módulo Sales (todo el equipo)
    -- hr_manager    : módulo HR
    -- viewer        : solo lectura en todos los módulos

    -- Permisos por módulo (más granular que el rol)
    can_access_hr       BOOLEAN NOT NULL DEFAULT FALSE,
    can_access_logistics BOOLEAN NOT NULL DEFAULT FALSE,
    can_access_sales    BOOLEAN NOT NULL DEFAULT FALSE,
    can_access_finance  BOOLEAN NOT NULL DEFAULT FALSE,
    can_access_production BOOLEAN NOT NULL DEFAULT FALSE,
    can_access_projects BOOLEAN NOT NULL DEFAULT FALSE,
    can_approve_discounts BOOLEAN NOT NULL DEFAULT FALSE,
    -- puede aprobar rebajas en sales.ad_hoc_price_overrides
    can_approve_payments  BOOLEAN NOT NULL DEFAULT FALSE,
    -- puede aprobar pagos en finance
    can_close_periods     BOOLEAN NOT NULL DEFAULT FALSE,
    -- puede cerrar períodos contables

    -- Último acceso
    last_login_at       TIMESTAMPTZ,
    last_login_ip       VARCHAR(45),
    -- IPv4 o IPv6

    -- Estado
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    is_locked           BOOLEAN NOT NULL DEFAULT FALSE,
    -- bloqueado manualmente por el admin (diferente al bloqueo de Cognito)

    -- Preferencias de UI
    preferred_language  VARCHAR(10) NOT NULL DEFAULT 'es',
    -- 'es' | 'en'
    preferred_currency  VARCHAR(10) NOT NULL DEFAULT 'PEN',
    timezone            VARCHAR(50)  NOT NULL DEFAULT 'America/Lima',

    -- Auditoría del propio registro
    created_by_user_id  BIGINT      REFERENCES hr.system_users(id),
    -- NULL si es el primer admin (se creó solo)

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (company_id, email)
);

CREATE INDEX idx_su_company  ON hr.system_users (company_id);
CREATE INDEX idx_su_cognito  ON hr.system_users (cognito_user_id);
CREATE INDEX idx_su_email    ON hr.system_users (email);
CREATE INDEX idx_su_active   ON hr.system_users (is_active) WHERE is_active = TRUE;

CREATE TRIGGER trg_su_updated_at
    BEFORE UPDATE ON hr.system_users
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

COMMENT ON TABLE  hr.system_users IS 'Usuarios del sistema. Las contraseñas las maneja AWS Cognito — aquí solo guardamos cognito_user_id para enlazar al usuario con sus datos.';
COMMENT ON COLUMN hr.system_users.cognito_user_id IS 'UUID generado por AWS Cognito al crear el usuario. Nunca se guarda la contraseña en nuestra DB.';
COMMENT ON COLUMN hr.system_users.role IS 'Rol principal del usuario. Los permisos granulares se controlan con los campos can_access_*.';

-- ============================================================
-- 2. SESIONES DE USUARIO
--    Registro de cada vez que un usuario inicia sesión.
--    Útil para auditoría de seguridad y detectar accesos
--    inusuales (IP desconocida, horario fuera de lo normal).
-- ============================================================
CREATE TABLE hr.user_sessions (
    id                  BIGSERIAL   PRIMARY KEY,
    system_user_id      BIGINT      NOT NULL REFERENCES hr.system_users(id),
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id),

    session_start       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    session_end         TIMESTAMPTZ,

    ip_address          VARCHAR(45),
    user_agent          VARCHAR(500),
    -- browser / app que usó para conectarse
    device_type         VARCHAR(20),
    -- web | mobile | tablet | api

    -- ¿Desde dónde se conectó?
    country             VARCHAR(5),
    city                VARCHAR(100),

    -- JWT token identifier (para invalidar sesiones)
    jwt_jti             VARCHAR(100) UNIQUE,
    -- JWT ID claim — permite revocar un token específico

    is_active           BOOLEAN NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- Inmutable
);

CREATE INDEX idx_usess_user    ON hr.user_sessions (system_user_id);
CREATE INDEX idx_usess_active  ON hr.user_sessions (is_active) WHERE is_active = TRUE;

COMMENT ON TABLE hr.user_sessions IS 'Registro de sesiones de usuario. Permite auditoría de seguridad, detección de accesos inusuales y revocación de tokens JWT.';

-- ============================================================
-- 3. LOG DE AUDITORÍA GLOBAL
--    Registro inmutable de TODAS las operaciones importantes:
--    quién hizo qué, cuándo, en qué tabla, qué cambió.
--    Es el "diario de auditoría" del sistema.
-- ============================================================
CREATE TABLE hr.audit_log (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      REFERENCES hr.companies(id),
    system_user_id      BIGINT      REFERENCES hr.system_users(id),

    -- Qué operación se hizo
    action              VARCHAR(20) NOT NULL,
    -- INSERT | UPDATE | DELETE | LOGIN | LOGOUT |
    -- APPROVE | REJECT | PRINT | EXPORT | VIEW_SENSITIVE

    -- En qué tabla/registro
    table_schema        VARCHAR(50),
    table_name          VARCHAR(100),
    record_id           BIGINT,
    -- ID del registro afectado

    -- Qué cambió (para UPDATE)
    old_values          JSONB,
    -- {"status": "draft", "amount": 1000}
    new_values          JSONB,
    -- {"status": "confirmed", "amount": 1500}

    -- Contexto adicional
    description         VARCHAR(500),
    -- descripción legible del cambio

    -- Desde dónde se hizo
    ip_address          VARCHAR(45),
    user_agent          VARCHAR(500),
    session_id          BIGINT      REFERENCES hr.user_sessions(id),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- SIEMPRE INMUTABLE — nunca se modifica ni elimina
);

CREATE INDEX idx_auditlog_company   ON hr.audit_log (company_id);
CREATE INDEX idx_auditlog_user      ON hr.audit_log (system_user_id);
CREATE INDEX idx_auditlog_table     ON hr.audit_log (table_schema, table_name, record_id);
CREATE INDEX idx_auditlog_action    ON hr.audit_log (action);
CREATE INDEX idx_auditlog_date      ON hr.audit_log (created_at);

COMMENT ON TABLE hr.audit_log IS 'Log de auditoría global e inmutable. Registra quién hizo qué y cuándo en todo el sistema. old_values/new_values en JSONB muestran exactamente qué cambió.';

-- ============================================================
-- 4. FUNCIÓN: SET AUDIT USER (para triggers)
--    Cada request de la API Node.js ejecuta al inicio:
--      SET LOCAL mantrasdb.current_user_id = '123';
--    Los triggers leen ese valor automáticamente y llenan
--    created_by_user_id y updated_by_user_id.
-- ============================================================
CREATE OR REPLACE FUNCTION hr.get_current_user_id()
RETURNS BIGINT LANGUAGE plpgsql AS $$
BEGIN
    -- Leer el ID del usuario de la variable de sesión PostgreSQL
    -- La API Node.js la setea al inicio de cada request:
    --   await client.query("SET LOCAL mantrasdb.current_user_id = $1", [userId])
    RETURN NULLIF(current_setting('mantrasdb.current_user_id', TRUE), '')::BIGINT;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION hr.set_audit_fields()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_user_id BIGINT;
BEGIN
    v_user_id := hr.get_current_user_id();

    IF TG_OP = 'INSERT' THEN
        -- Al crear: llenar created_by_user_id si la columna existe
        IF TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME IN (
            SELECT table_schema || '.' || table_name
            FROM information_schema.columns
            WHERE column_name = 'created_by_user_id'
        ) THEN
            NEW.created_by_user_id := COALESCE(NEW.created_by_user_id, v_user_id);
        END IF;
        NEW.updated_by_user_id := v_user_id;

    ELSIF TG_OP = 'UPDATE' THEN
        NEW.updated_by_user_id := v_user_id;
        NEW.updated_at := NOW();
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION hr.get_current_user_id IS 'Lee el ID del usuario actual desde la variable de sesión PG "mantrasdb.current_user_id". La API Node.js la setea al inicio de cada request.';
COMMENT ON FUNCTION hr.set_audit_fields   IS 'Trigger function que auto-rellena created_by_user_id y updated_by_user_id en INSERT/UPDATE. Requiere que la API setee mantrasdb.current_user_id.';

-- ============================================================
-- 5. AGREGAR COLUMNAS DE AUDITORÍA A TODAS LAS TABLAS
--    created_by_user_id → quién creó el registro
--    updated_by_user_id → quién hizo el último cambio
--
--    Las tablas INMUTABLES (sin updated_at) solo tienen
--    created_by_user_id.
-- ============================================================

-- ── SCHEMA HR ────────────────────────────────────────────────
ALTER TABLE hr.companies
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.persons
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.employees
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.contracts
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.payroll_periods
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE hr.payroll_entries
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

-- ── SCHEMA LOGISTICS ─────────────────────────────────────────
ALTER TABLE logistics.products
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.purchase_orders
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.shipments
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE logistics.warehouses
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

-- ── SCHEMA SALES ─────────────────────────────────────────────
ALTER TABLE sales.customers
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.quotations
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.sales_orders
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.invoices
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.pos_sessions
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE sales.pos_transactions
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
    -- inmutable: solo created

ALTER TABLE sales.return_authorizations
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

-- ── SCHEMA FINANCE ───────────────────────────────────────────
ALTER TABLE finance.journal_entries
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS confirmed_by_user_id BIGINT REFERENCES hr.system_users(id);
    -- inmutable al confirmar: no tiene updated_by

ALTER TABLE finance.supplier_invoices
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS approved_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.supplier_payments
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id);
    -- inmutable: solo created

ALTER TABLE finance.bank_reconciliations
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS approved_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.fixed_assets
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id);

ALTER TABLE finance.budgets
    ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS updated_by_user_id BIGINT REFERENCES hr.system_users(id),
    ADD COLUMN IF NOT EXISTS approved_by_user_id BIGINT REFERENCES hr.system_users(id);

-- ============================================================
-- 6. FK DIFERIDA: employees → system_users
-- ============================================================
ALTER TABLE hr.system_users
    ADD CONSTRAINT fk_su_employee
    FOREIGN KEY (employee_id) REFERENCES hr.employees(id);

-- ============================================================
-- 7. NOTA PARA LA API NODE.JS
-- ============================================================
COMMENT ON FUNCTION hr.get_current_user_id IS '
PATRÓN DE USO EN NODE.JS:

  // Al inicio de cada request autenticado:
  const userId = req.user.system_user_id; // del JWT decodificado
  await db.query("SET LOCAL mantrasdb.current_user_id = $1", [userId]);

  // A partir de ahí todos los INSERT/UPDATE auto-registran el usuario.
  // No necesitas pasar userId en cada query.

  // Ejemplo de middleware Express:
  app.use(async (req, res, next) => {
    if (req.user) {
      await req.db.query(
        "SET LOCAL mantrasdb.current_user_id = $1",
        [req.user.system_user_id]
      );
    }
    next();
  });
';
