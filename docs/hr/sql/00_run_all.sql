-- ============================================================
-- mantrasdb | Módulo HR — Script maestro
-- Descripción: Ejecuta todas las tablas del módulo HR en orden.
--
-- INSTRUCCIONES:
--   1. En DBeaver, conectarse a la base de datos mantrasdb
--   2. Abrir este archivo
--   3. Ctrl+A para seleccionar todo
--   4. Alt+X para ejecutar como script completo
-- ============================================================

-- ── Capa 1: Estructura organizacional ────────────────────────
\ir 01_companies.sql
\ir 02_geography.sql
\ir 03_departments.sql
\ir 04_positions.sql

-- ── Capa 2: Identidad y empleo ───────────────────────────────
\ir 05_persons.sql
\ir 06_employees.sql
\ir 07_contract_types.sql
\ir 08_contracts.sql

-- ── Capa 3: Tiempo, asistencia y festivos ────────────────────
\ir 09_schedules_shifts.sql
\ir 10_holidays.sql
\ir 11_attendance.sql
\ir 12_absence_types.sql
\ir 13_absences.sql

-- ── Capa 4: Nómina ───────────────────────────────────────────
\ir 14_payroll_concepts.sql
\ir 15_payroll_periods.sql
\ir 16_payroll_details.sql

-- ── Capa 5: Equipos y activos ────────────────────────────────
\ir 17_equipment_types.sql
\ir 18_equipment.sql
\ir 19_equipment_assignments.sql

-- ── Capa 6: Claves y accesos ─────────────────────────────────
\ir 20_access_systems.sql
\ir 21_access_codes.sql
\ir 22_code_assignments.sql

-- ── Capa 7: Disciplina y desarrollo ─────────────────────────
\ir 23_disciplinary_actions.sql
\ir 24_performance_reviews.sql
\ir 25_trainings.sql

-- ── Capa 8: Documentos (transversal) ────────────────────────
\ir 26_documents.sql

-- ============================================================
-- Verificación: lista todas las tablas creadas en el schema hr
-- ============================================================
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'hr'
ORDER BY table_name;
