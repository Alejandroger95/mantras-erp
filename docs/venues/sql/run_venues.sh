#!/usr/bin/env bash
# ============================================================
# mantrasdb — Módulo Venues
# Instala el esquema completo de recintos, eventos y membresías.
#
# Uso:
#   chmod +x run_venues.sh
#   ./run_venues.sh
#   ./run_venues.sh postgresql://postgres@localhost:5432/mantrasdb
# ============================================================

set -euo pipefail

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-mantrasdb}"

# Aceptar DATABASE_URL como argumento posicional o variable de entorno
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
echo "   Módulo: Venues (Recintos, Eventos, Membresías)"
echo ""

run_file "01_venues.sql    — Recintos, zonas, amenidades"              "$DIR/01_venues.sql"
run_file "02_events.sql    — Eventos, aforo por zona, tickets, logs"   "$DIR/02_events.sql"
run_file "03_memberships.sql — Tipos, membresías, beneficios, cobros"  "$DIR/03_memberships.sql"

echo ""
