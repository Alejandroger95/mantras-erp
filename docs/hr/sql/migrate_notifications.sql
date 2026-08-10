-- ============================================================
-- MIGRACIÓN: Notificaciones in-app
-- ============================================================
-- hr.notifications             → notificaciones por usuario
-- hr.notification_preferences  → preferencias por tipo y canal
--
-- Por ahora solo canal 'in_app'. Email/push en el futuro.
-- Las notificaciones se generan desde la API al ocurrir el evento.
-- ============================================================

BEGIN;

-- ── 1. hr.notifications ───────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS hr.notifications (
    id              BIGSERIAL       PRIMARY KEY,
    company_id      BIGINT          NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,

    -- Destinatario
    recipient_id    BIGINT          NOT NULL REFERENCES hr.employees(id),

    -- Quién generó la notificación (NULL = sistema automático)
    sender_id       BIGINT          REFERENCES hr.employees(id),

    -- Tipo de notificación
    type            VARCHAR(60)     NOT NULL,
    -- Valores posibles:
    --   absence_requested      → empleado pidió ausencia (avisa al jefe)
    --   absence_approved       → ausencia aprobada (avisa al empleado)
    --   absence_rejected       → ausencia rechazada (avisa al empleado)
    --   absence_cancelled      → ausencia cancelada
    --   punch_cancelled        → fichaje cancelado (avisa al empleado)
    --   punch_annulled         → fichaje anulado (avisa al empleado)
    --   punch_created_retro    → fichaje retroactivo creado (avisa al empleado)
    --   punch_time_edited      → hora de fichaje editada (avisa al empleado)

    -- Entidad relacionada (para navegar desde la notificación)
    entity_type     VARCHAR(30),    -- 'absence' | 'punch' | 'employee' | etc.
    entity_id       BIGINT,

    -- Contenido
    title           VARCHAR(200)    NOT NULL,
    body            TEXT,

    -- Estado de lectura
    is_read         BOOLEAN         NOT NULL DEFAULT FALSE,
    read_at         TIMESTAMPTZ,

    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_notification_type CHECK (type IN (
        'absence_requested', 'absence_approved', 'absence_rejected', 'absence_cancelled',
        'punch_cancelled', 'punch_annulled', 'punch_created_retro', 'punch_time_edited'
    ))
);

CREATE TRIGGER trg_notifications_updated_at
    BEFORE UPDATE ON hr.notifications
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_notifications_recipient
    ON hr.notifications (company_id, recipient_id, is_read, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_entity
    ON hr.notifications (entity_type, entity_id);

COMMENT ON TABLE  hr.notifications              IS 'Notificaciones in-app. Generadas desde la API al ocurrir el evento.';
COMMENT ON COLUMN hr.notifications.type         IS 'Tipo de evento. Determina el ícono y el texto en el frontend.';
COMMENT ON COLUMN hr.notifications.entity_type  IS 'Tipo de entidad relacionada (absence, punch, etc.) para deep-link.';
COMMENT ON COLUMN hr.notifications.sender_id    IS 'NULL = sistema automático. Si un admin crea un fichaje retroactivo, sender_id = admin.';

-- ── 2. hr.notification_preferences ───────────────────────────────────────────

CREATE TABLE IF NOT EXISTS hr.notification_preferences (
    id                  BIGSERIAL   PRIMARY KEY,
    company_id          BIGINT      NOT NULL REFERENCES hr.companies(id) ON DELETE RESTRICT,
    employee_id         BIGINT      NOT NULL REFERENCES hr.employees(id),

    notification_type   VARCHAR(60) NOT NULL,
    channel             VARCHAR(20) NOT NULL DEFAULT 'in_app',
    -- 'in_app' → campana en el frontend (activo ahora)
    -- 'email'  → futuro
    -- 'push'   → futuro (app móvil)

    is_enabled          BOOLEAN     NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (employee_id, notification_type, channel)
);

CREATE TRIGGER trg_notification_prefs_updated_at
    BEFORE UPDATE ON hr.notification_preferences
    FOR EACH ROW EXECUTE FUNCTION hr.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_notif_prefs_employee
    ON hr.notification_preferences (employee_id);

COMMENT ON TABLE  hr.notification_preferences         IS 'Preferencias de notificación por empleado. Por defecto todas activas.';
COMMENT ON COLUMN hr.notification_preferences.channel IS 'in_app (activo) | email | push (futuro)';

COMMIT;
