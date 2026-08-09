#!/usr/bin/env bash
# ============================================================
# run_surveys.sh — Módulo Surveys de mantrasdb
# ============================================================
# Instala el módulo de Encuestas de Satisfacción al Cliente.
# Debe correr DESPUÉS de hr, sales, services y projects.
#
# Uso:
#   chmod +x run_surveys.sh
#   ./run_surveys.sh
#   ./run_surveys.sh --reset
#
# Variables de entorno:
#   DATABASE_URL  (default: postgresql://localhost:5432/mantrasdb)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" != "--reset" && -n "${1:-}" ]]; then
    DATABASE_URL="${1}"
fi
DATABASE_URL="${DATABASE_URL:-postgresql://localhost:5432/mantrasdb}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${CYAN}[Surveys]${NC} $1"; }
ok()   { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

if [[ "${1:-}" == "--reset" ]] || [[ "${2:-}" == "--reset" ]]; then
    echo -e "${YELLOW}⚠  Eliminando schema surveys...${NC}"
    psql "$DATABASE_URL" -c "DROP SCHEMA IF EXISTS surveys CASCADE;" --quiet
    ok "Schema surveys eliminado."
    echo ""
fi

run_sql() {
    local file="$1" label="$2"
    [[ -f "${SCRIPT_DIR}/${file}" ]] || fail "No encontrado: ${SCRIPT_DIR}/${file}"
    log "Ejecutando: ${label}..."
    psql "$DATABASE_URL" \
        --single-transaction \
        --set ON_ERROR_STOP=1 \
        -f "${SCRIPT_DIR}/${file}" \
        --quiet
    ok "${label} completado."
}

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       mantrasdb — Módulo Surveys                 ║${NC}"
echo -e "${BOLD}║       Schema: surveys                            ║${NC}"
echo -e "${BOLD}║                                                  ║${NC}"
echo -e "${BOLD}║   Encuestas de satisfacción: NPS, CSAT, CES      ║${NC}"
echo -e "${BOLD}║   Vincula citas, órdenes y proyectos             ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""

psql "$DATABASE_URL" -c "SELECT 1;" > /dev/null 2>&1 || {
    echo -e "${RED}✗ No se pudo conectar a la base de datos.${NC}"
    exit 1
}
ok "Conexión OK"
echo ""

run_sql "01_surveys.sql"   "01 — Schema, templates y preguntas"
run_sql "02_responses.sql" "02 — Invitaciones, respuestas y vistas analíticas"

echo ""
echo -e "${GREEN}${BOLD}✔ Módulo Surveys instalado correctamente.${NC}"
echo ""

psql "$DATABASE_URL" --quiet -c "
SELECT tipo, cantidad
FROM (
    SELECT 'Tablas' AS tipo, COUNT(*) AS cantidad, 1 AS ord
    FROM information_schema.tables
    WHERE table_schema = 'surveys' AND table_type = 'BASE TABLE'
    UNION ALL
    SELECT 'Vistas', COUNT(*), 2
    FROM information_schema.views
    WHERE table_schema = 'surveys'
) t
ORDER BY ord;
"
echo ""
