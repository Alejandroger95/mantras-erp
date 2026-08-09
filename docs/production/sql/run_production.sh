#!/usr/bin/env bash
# ============================================================
# run_production.sh — Módulo Production de mantrasdb
# ============================================================
# Uso:
#   ./run_production.sh              # instala (no resetea)
#   ./run_production.sh --reset      # elimina el schema y reinstala
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colores ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

# ── Base de datos ─────────────────────────────────────────────
DATABASE_URL="${DATABASE_URL:-postgresql://localhost:5432/mantrasdb}"

log()    { echo -e "${CYAN}[Production]${NC} $1"; }
ok()     { echo -e "${GREEN}✓${NC} $1"; }
warn()   { echo -e "${YELLOW}⚠${NC} $1"; }
fail()   { echo -e "${RED}✗${NC} $1"; exit 1; }

# ── Reset opcional ────────────────────────────────────────────
if [[ "${1:-}" == "--reset" ]]; then
    warn "Eliminando schema production..."
    psql "$DATABASE_URL" -c "DROP SCHEMA IF EXISTS production CASCADE;" --quiet
    ok "Schema production eliminado."
fi

# ── Función de ejecución ──────────────────────────────────────
run_sql() {
    local file="$1"
    local label="$2"
    local filepath="${SCRIPT_DIR}/${file}"

    if [[ ! -f "$filepath" ]]; then
        fail "Archivo no encontrado: $filepath"
    fi

    log "Ejecutando: ${label}..."
    psql "$DATABASE_URL" \
        --single-transaction \
        --set ON_ERROR_STOP=1 \
        -f "$filepath" \
        --quiet

    ok "${label} completado."
}

# ── Ejecución en orden ────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       mantrasdb — Módulo Production              ║${NC}"
echo -e "${BOLD}║       Schema: production                         ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""

run_sql "01_bom.sql"              "01 — BOM (Bill of Materials) + Industrias"
run_sql "02_work_centers.sql"     "02 — Centros de Trabajo + Máquinas + OEE"
run_sql "03_routings.sql"         "03 — Rutas de Producción + Operaciones"
run_sql "04_production_orders.sql" "04 — Órdenes de Producción + Puente Logística"
run_sql "05_work_orders.sql"      "05 — Work Orders + Tiempos + Materiales"
run_sql "06_quality_control.sql"  "06 — Control de Calidad + Áreas + Mermas"
run_sql "07_costing.sql"          "07 — Costeo + WIP + Variaciones + SUNAT Mermas"
run_sql "08_differentiators.sql"  "08 — Genealogía + IoT + KPIs + Restaurante"

echo ""
echo -e "${GREEN}${BOLD}✔ Módulo Production instalado correctamente.${NC}"
echo ""

# Conteo de objetos creados
psql "$DATABASE_URL" --quiet -c "
SELECT
    'Tablas'  AS tipo,
    COUNT(*)  AS cantidad
FROM information_schema.tables
WHERE table_schema = 'production' AND table_type = 'BASE TABLE'
UNION ALL
SELECT 'Vistas', COUNT(*)
FROM information_schema.views
WHERE table_schema = 'production'
ORDER BY tipo;
"
echo ""
