-- ============================================================
-- MIGRACIÓN: Extender hr.absences y hr.absence_types
-- para soportar ausencias parciales (dentro de jornada)
-- además de las ausencias de día(s) completo(s).
-- ============================================================

BEGIN;

-- ── 1. hr.absence_types: indicar a qué scope aplica cada tipo ─────────────────
--   'partial'  → solo ausencias parciales (médico 1h, gestión personal…)
--   'full_day' → solo ausencias de día(s) completo(s) (vacaciones, baja…)
--   'both'     → aplica a ambos (ej: permiso personal puede ser parcial o total)

ALTER TABLE hr.absence_types
  ADD COLUMN IF NOT EXISTS applies_to VARCHAR(10) NOT NULL DEFAULT 'full_day';
  -- 'partial' | 'full_day' | 'both'

COMMENT ON COLUMN hr.absence_types.applies_to
  IS 'partial = solo parciales | full_day = solo días completos | both = ambos';

-- ── 2. hr.absences: añadir columnas para parciales ───────────────────────────

-- Scope: ¿es ausencia parcial (dentro de jornada) o de día(s) completo(s)?
ALTER TABLE hr.absences
  ADD COLUMN IF NOT EXISTS absence_scope VARCHAR(10) NOT NULL DEFAULT 'full_day';
  -- 'partial' | 'full_day'

COMMENT ON COLUMN hr.absences.absence_scope
  IS 'partial = ausencia dentro de la jornada | full_day = día(s) completo(s)';

-- Para parciales: la fecha exacta (start_date ya existe, usamos esa)
-- start_time y end_time del tramo de ausencia dentro del día
ALTER TABLE hr.absences
  ADD COLUMN IF NOT EXISTS start_time TIME,
  ADD COLUMN IF NOT EXISTS end_time   TIME;

COMMENT ON COLUMN hr.absences.start_time IS 'Solo ausencias parciales: hora de inicio';
COMMENT ON COLUMN hr.absences.end_time   IS 'Solo ausencias parciales: hora de fin';

-- Duración en minutos (calculado al insertar/actualizar)
ALTER TABLE hr.absences
  ADD COLUMN IF NOT EXISTS duration_minutes SMALLINT;

COMMENT ON COLUMN hr.absences.duration_minutes
  IS 'Para parciales: minutos de ausencia. Para full_day: NULL (usar total_days)';

-- Quién hizo la solicitud (puede ser el propio empleado, un jefe o admin)
ALTER TABLE hr.absences
  ADD COLUMN IF NOT EXISTS requested_by BIGINT REFERENCES hr.employees(id);

COMMENT ON COLUMN hr.absences.requested_by
  IS 'Empleado que creó la solicitud (puede diferir de employee_id si la crea un manager)';

-- ── 3. Renombrar approved_by → reviewed_by (más neutro, cubre reject también) ─
-- Solo si aún no se ha renombrado
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'hr' AND table_name = 'absences' AND column_name = 'approved_by'
  ) THEN
    ALTER TABLE hr.absences RENAME COLUMN approved_by  TO reviewed_by;
    ALTER TABLE hr.absences RENAME COLUMN approved_at  TO reviewed_at;
  END IF;
END $$;

COMMENT ON COLUMN hr.absences.reviewed_by IS 'Empleado que aprobó o rechazó la solicitud';
COMMENT ON COLUMN hr.absences.reviewed_at IS 'Fecha y hora de la revisión';

-- ── 4. Índice para consultas por scope y fecha ────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_absences_scope  ON hr.absences (absence_scope);
CREATE INDEX IF NOT EXISTS idx_absences_day    ON hr.absences (start_date, absence_scope);

-- ── 5. CHECK constraints para coherencia de datos ────────────────────────────
ALTER TABLE hr.absences DROP CONSTRAINT IF EXISTS chk_absences_partial_times;
ALTER TABLE hr.absences ADD CONSTRAINT chk_absences_partial_times CHECK (
  (absence_scope = 'partial'  AND start_time IS NOT NULL AND end_time IS NOT NULL AND end_time > start_time)
  OR
  (absence_scope = 'full_day' AND start_time IS NULL     AND end_time IS NULL)
);

ALTER TABLE hr.absences DROP CONSTRAINT IF EXISTS chk_absences_scope_values;
ALTER TABLE hr.absences ADD CONSTRAINT chk_absences_scope_values CHECK (
  absence_scope IN ('partial', 'full_day')
);

ALTER TABLE hr.absence_types DROP CONSTRAINT IF EXISTS chk_absence_types_applies_to;
ALTER TABLE hr.absence_types ADD CONSTRAINT chk_absence_types_applies_to CHECK (
  applies_to IN ('partial', 'full_day', 'both')
);

-- ── 6. Insertar categorías para ausencias parciales (si no existen) ───────────
-- Ajusta company_id según tu entorno
INSERT INTO hr.absence_types (company_id, name, code, description, is_paid, requires_document, applies_to)
SELECT
  c.id,
  t.name,
  t.code,
  t.description,
  t.is_paid,
  t.requires_document,
  t.applies_to
FROM hr.companies c
CROSS JOIN (VALUES
  ('Médico / Sanitario',      'MED',  'Consulta médica, urgencia o trámite sanitario', TRUE,  FALSE, 'partial'),
  ('Gestión personal',        'GEST', 'Banco, notaría, administración…',                TRUE,  FALSE, 'partial'),
  ('Formación externa',       'FORM', 'Curso, seminario o certificación',               TRUE,  FALSE, 'partial'),
  ('Emergencia familiar',     'EMFAM','Imprevisto urgente con familiar',                TRUE,  FALSE, 'partial'),
  ('Error de registro',       'ERR',  'Ausencia registrada por error, para cancelar',  TRUE,  FALSE, 'partial'),
  ('Vacaciones',              'VAC',  NULL,                                             TRUE,  FALSE, 'full_day'),
  ('Enfermedad / Baja médica','SICK', NULL,                                             TRUE,  TRUE,  'full_day'),
  ('Permiso sin goce',        'UNPL', NULL,                                             FALSE, FALSE, 'full_day'),
  ('Maternidad',              'MAT',  NULL,                                             TRUE,  TRUE,  'full_day'),
  ('Paternidad',              'PAT',  NULL,                                             TRUE,  TRUE,  'full_day'),
  ('Permiso personal',        'PERS', NULL,                                             TRUE,  FALSE, 'both')
) AS t(name, code, description, is_paid, requires_document, applies_to)
WHERE NOT EXISTS (
  SELECT 1 FROM hr.absence_types at2
  WHERE at2.company_id = c.id AND at2.code = t.code
);

COMMIT;
