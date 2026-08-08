#!/bin/bash
# ============================================================
# mantrasdb | Módulo HR — Script de ejecución completo
# Uso: bash run_hr.sh
#
# Variables de entorno opcionales:
#   DB_HOST (default: localhost)
#   DB_PORT (default: 5432)
#   DB_USER (default: postgres)
#   DB_NAME (default: mantrasdb)
#
# Ejemplos:
#   bash run_hr.sh
#   DB_USER=alejandro bash run_hr.sh
#   DB_HOST=192.168.1.10 DB_USER=admin bash run_hr.sh
#
# Para resetear y recrear desde cero:
#   bash run_hr.sh --reset
# ============================================================

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-mantrasdb}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESET=false

# Parsear argumentos
for arg in "$@"; do
  case $arg in
    --reset) RESET=true ;;
  esac
done

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  mantrasdb — Módulo HR${NC}"
echo -e "${CYAN}  Host: $DB_HOST:$DB_PORT | DB: $DB_NAME${NC}"
echo -e "${CYAN}============================================${NC}"

# Verificar conexión
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo -e "${RED}✗ No se pudo conectar a $DB_NAME. Verifica host, puerto, usuario y que la DB exista.${NC}"
  exit 1
fi

# Reset opcional: elimina el schema y todo su contenido
if [ "$RESET" = true ]; then
  echo -e "${YELLOW}⚠  Modo --reset: eliminando schema hr...${NC}"
  psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -c "DROP SCHEMA IF EXISTS hr CASCADE;" 2>&1
  echo -e "${GREEN}✓ Schema hr eliminado${NC}"
fi

# Lista ordenada de archivos SQL
FILES=(
  "01_companies.sql"
  "02_geography.sql"
  "03_departments.sql"
  "04_positions.sql"
  "05_persons.sql"
  "05b_person_documents.sql"
  "06_employees.sql"
  "07_contract_types.sql"
  "08_contracts.sql"
  "08b_work_reductions.sql"
  "09_schedules_shifts.sql"
  "10_holidays.sql"
  "10b_time_punches.sql"
  "11_attendance.sql"
  "12_absence_types.sql"
  "13_absences.sql"
  "14_payroll_concepts.sql"
  "15_payroll_periods.sql"
  "16_payroll_details.sql"
  "17_equipment_types.sql"
  "18_equipment.sql"
  "19_equipment_assignments.sql"
  "20_access_systems.sql"
  "21_access_codes.sql"
  "22_code_assignments.sql"
  "23_disciplinary_actions.sql"
  "24_performance_reviews.sql"
  "25_trainings.sql"
  "26_documents.sql"
)

TOTAL=${#FILES[@]}
COUNT=0
ERRORS=0

echo ""
for FILE in "${FILES[@]}"; do
  COUNT=$((COUNT + 1))
  FILEPATH="$SCRIPT_DIR/$FILE"

  if [ ! -f "$FILEPATH" ]; then
    echo -e "  ${YELLOW}[$COUNT/$TOTAL] ⚠  $FILE — archivo no encontrado, omitiendo${NC}"
    continue
  fi

  printf "  [%02d/%02d] %-40s" "$COUNT" "$TOTAL" "$FILE"

  OUTPUT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -f "$FILEPATH" 2>&1)

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
  else
    echo -e "${RED}✗ ERROR${NC}"
    echo -e "${RED}$OUTPUT${NC}"
    ERRORS=$((ERRORS + 1))
    echo -e "${RED}Abortando en $FILE.${NC}"
    echo -e "${YELLOW}Tip: corre con --reset para empezar limpio: bash run_hr.sh --reset${NC}"
    exit 1
  fi
done

echo ""
if [ $ERRORS -eq 0 ]; then
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  ✓ Schema HR creado exitosamente ($TOTAL tablas)${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo ""
  echo "Tablas creadas en el schema hr:"
  psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -c "SELECT table_name FROM information_schema.tables WHERE table_schema = 'hr' ORDER BY table_name;"
fi
