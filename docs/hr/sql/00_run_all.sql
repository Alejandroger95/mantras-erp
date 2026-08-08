-- ============================================================
-- mantrasdb | Módulo HR — Script maestro (psql \ir)
-- Solo funciona con psql desde terminal. Para DBeaver usa run_hr.sh
--
-- Uso desde terminal:
--   psql -h localhost -U postgres -d mantrasdb -f 00_run_all.sql
--
-- Para resetear todo:
--   psql -h localhost -U postgres -d mantrasdb \
--     -c "DROP SCHEMA IF EXISTS hr CASCADE;" \
--     -f 00_run_all.sql
-- ============================================================

\ir 01_companies.sql
\ir 02_geography.sql
\ir 03_departments.sql
\ir 04_positions.sql
\ir 05_persons.sql
\ir 05b_person_documents.sql
\ir 06_employees.sql
\ir 07_contract_types.sql
\ir 08_contracts.sql
\ir 08b_work_reductions.sql
\ir 09_schedules_shifts.sql
\ir 10_holidays.sql
\ir 10b_time_punches.sql
\ir 11_attendance.sql
\ir 12_absence_types.sql
\ir 13_absences.sql
\ir 14_payroll_concepts.sql
\ir 15_payroll_periods.sql
\ir 16_payroll_details.sql
\ir 17_equipment_types.sql
\ir 18_equipment.sql
\ir 19_equipment_assignments.sql
\ir 20_access_systems.sql
\ir 21_access_codes.sql
\ir 22_code_assignments.sql
\ir 23_disciplinary_actions.sql
\ir 24_performance_reviews.sql
\ir 25_trainings.sql
\ir 26_documents.sql

-- Verificación final
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'hr'
ORDER BY table_name;
