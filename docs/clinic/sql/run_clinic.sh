#!/usr/bin/env bash
# ============================================================
# mantrasdb — Módulo Clinic
# Instala el expediente clínico: pacientes, consultas,
# diagnósticos, recetas, laboratorio, imágenes, vacunas,
# cirugías y registros externos.
#
# Uso:
#   chmod +x run_clinic.sh
#   ./run_clinic.sh
#   ./run_clinic.sh postgresql://postgres@localhost:5432/mantrasdb
# ============================================================

set -euo pipefail

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-mantrasdb}"

DATABASE_URL="${1:-${DATABASE_URL:-postgresql://${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}}}"

DIR="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

run_file() {
  local label="$1"
  local file="$2"
  psql "$DATABASE_URL" \
    --single-transaction \
    --set ON_ERROR_STOP=1 \
    -f "$file" \
    --quiet && \
    echo -e "   ${GREEN}✓${NC} $label" || {
      echo -e "   ${RED}✗ ERROR en $label${NC}"
      exit 1
    }
}

echo ""
echo "   Módulo: Clinic (Expediente Clínico)"
echo ""

run_file "01_patients.sql      — Pacientes, antecedentes, alergias, seguro"  "$DIR/01_patients.sql"
run_file "02_consultations.sql — Consultas, Rx, lab, imágenes, cirugías, externos"  "$DIR/02_consultations.sql"

echo ""
