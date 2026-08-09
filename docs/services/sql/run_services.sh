#!/usr/bin/env bash
# ============================================================
# run_services.sh — Módulo Services de mantrasdb
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATABASE_URL="${DATABASE_URL:-postgresql://localhost:5432/mantrasdb}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${CYAN}[Services]${NC} $1"; }
ok()   { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

if [[ "${1:-}" == "--reset" ]]; then
    echo -e "${YELLOW}⚠ Eliminando schema services...${NC}"
    psql "$DATABASE_URL" -c "DROP SCHEMA IF EXISTS services CASCADE;" --quiet
    ok "Schema services eliminado."
fi

run_sql() {
    local file="$1" label="$2"
    [[ -f "${SCRIPT_DIR}/${file}" ]] || fail "No encontrado: ${SCRIPT_DIR}/${file}"
    log "Ejecutando: ${label}..."
    psql "$DATABASE_URL" --single-transaction --set ON_ERROR_STOP=1 \
        -f "${SCRIPT_DIR}/${file}" --quiet
    ok "${label} completado."
}

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       mantrasdb — Módulo Services                ║${NC}"
echo -e "${BOLD}║       Schema: services                           ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""

run_sql "01_service_catalog.sql"  "01 — Catálogo de servicios, paquetes y recursos"
run_sql "02_staff_services.sql"   "02 — Personal: skills, disponibilidad y bloqueos"
run_sql "03_appointments.sql"     "03 — Citas, servicios, consumibles y lista de espera"
run_sql "04_ratings_kpis.sql"     "04 — Calificaciones, historial cliente y KPIs"

echo ""
echo -e "${GREEN}${BOLD}✔ Módulo Services instalado correctamente.${NC}"
echo ""

psql "$DATABASE_URL" --quiet -c "
SELECT
    'Tablas'  AS tipo, COUNT(*) AS cantidad
FROM information_schema.tables
WHERE table_schema = 'services' AND table_type = 'BASE TABLE'
UNION ALL
SELECT 'Vistas', COUNT(*)
FROM information_schema.views
WHERE table_schema = 'services'
ORDER BY tipo;
"
echo ""
