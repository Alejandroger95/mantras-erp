#!/usr/bin/env bash
# ============================================================
# mantrasdb — Módulo Gifts
# Instala: gift cards, campañas de premios y reconocimientos al personal.
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
echo "   Módulo: Gifts (Tarjetas de consumo, premios y reconocimientos)"
echo ""

run_file "01_gift_cards.sql        — Gift cards y tarjetas de consumo"   "$DIR/01_gift_cards.sql"
run_file "02_campaigns_rewards.sql — Concursos, premios y reconocimientos al personal" "$DIR/02_campaigns_rewards.sql"

echo ""
