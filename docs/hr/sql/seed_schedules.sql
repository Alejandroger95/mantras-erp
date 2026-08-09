-- ============================================================
-- Seed: Horarios y turnos de ejemplo
-- Ejecutar DESPUÉS de run_all.sh
-- Uso: psql -U postgres -d mantrasdb -f seed_schedules.sql
-- ============================================================

DO $$
DECLARE
  v_company_id BIGINT;
  v_sched_1    BIGINT;
  v_sched_2    BIGINT;
  v_sched_3    BIGINT;
BEGIN
  -- Obtener la primera empresa
  SELECT id INTO v_company_id FROM hr.companies LIMIT 1;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'No hay empresas en hr.companies. Ejecuta run_all.sh primero.';
  END IF;

  -- ── Horario 1: Jornada completa L-V ──────────────────────
  INSERT INTO hr.schedules (company_id, name, description, weekly_hours, is_active)
  VALUES (v_company_id, 'Jornada completa L-V', 'Horario estándar de oficina lunes a viernes', 40, true)
  RETURNING id INTO v_sched_1;

  INSERT INTO hr.shifts (schedule_id, day_of_week, start_time, end_time, is_rest_day) VALUES
    (v_sched_1, 1, '09:00', '18:00', false),  -- Lun
    (v_sched_1, 2, '09:00', '18:00', false),  -- Mar
    (v_sched_1, 3, '09:00', '18:00', false),  -- Mié
    (v_sched_1, 4, '09:00', '18:00', false),  -- Jue
    (v_sched_1, 5, '09:00', '18:00', false),  -- Vie
    (v_sched_1, 6, '09:00', '09:00', true),   -- Sáb (descanso)
    (v_sched_1, 7, '09:00', '09:00', true);   -- Dom (descanso)

  -- ── Horario 2: Media jornada mañana ──────────────────────
  INSERT INTO hr.schedules (company_id, name, description, weekly_hours, is_active)
  VALUES (v_company_id, 'Media jornada mañana', 'Turno de mañana de lunes a sábado', 30, true)
  RETURNING id INTO v_sched_2;

  INSERT INTO hr.shifts (schedule_id, day_of_week, start_time, end_time, is_rest_day) VALUES
    (v_sched_2, 1, '08:00', '13:00', false),
    (v_sched_2, 2, '08:00', '13:00', false),
    (v_sched_2, 3, '08:00', '13:00', false),
    (v_sched_2, 4, '08:00', '13:00', false),
    (v_sched_2, 5, '08:00', '13:00', false),
    (v_sched_2, 6, '08:00', '13:00', false),
    (v_sched_2, 7, '08:00', '08:00', true);

  -- ── Horario 3: Turno tarde L-S ───────────────────────────
  INSERT INTO hr.schedules (company_id, name, description, weekly_hours, is_active)
  VALUES (v_company_id, 'Turno tarde L-S', 'Horario de tarde para servicio al cliente', 36, true)
  RETURNING id INTO v_sched_3;

  INSERT INTO hr.shifts (schedule_id, day_of_week, start_time, end_time, is_rest_day) VALUES
    (v_sched_3, 1, '14:00', '20:00', false),
    (v_sched_3, 2, '14:00', '20:00', false),
    (v_sched_3, 3, '14:00', '20:00', false),
    (v_sched_3, 4, '14:00', '20:00', false),
    (v_sched_3, 5, '14:00', '20:00', false),
    (v_sched_3, 6, '14:00', '20:00', false),
    (v_sched_3, 7, '14:00', '14:00', true);

  RAISE NOTICE 'Schedules creados: IDs %, %, %', v_sched_1, v_sched_2, v_sched_3;
END $$;
