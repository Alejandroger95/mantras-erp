#!/usr/bin/env bash
# ============================================================
# mantrasdb — Módulo Finance
# Instala todos los scripts del módulo Finance en orden.
#
# Uso:
#   bash run_finance.sh [DATABASE_URL]
#
# Ejemplo:
#   bash run_finance.sh postgresql://alejandro@localhost:5432/mantrasdb
#
# Módulos:
#   01 — Plan de Cuentas (PCGE Perú + PGC España) + Períodos
#   02 — Asientos Contables (journal_entries + doble partida)
#   03 — Cuentas por Pagar (AP) + detracciones + retenciones
#   04 — Tesorería y Bancos + caja chica + tipos de cambio
#   05 — Activos Fijos + depreciación + revaluaciones + bajas
#   06 — Impuestos + PLE SUNAT + detracciones + fraccionamiento
#   07 — Presupuestos + Centros de Costo + distribución
#   08 — Revaluación FX + Intercompany + Cierre de ejercicio
# ============================================================

set -euo pipefail

# Obtener DATABASE_URL desde argumento o variables de entorno
if [ $# -ge 1 ]; then
    DATABASE_URL="$1"
elif [ -n "${DATABASE_URL:-}" ]; then
    : # ya está definido
else
    DB_HOST="${DB_HOST:-localhost}"
    DB_PORT="${DB_PORT:-5432}"
    DB_USER="${DB_USER:-postgres}"
    DB_NAME="${DB_NAME:-mantrasdb}"
    DATABASE_URL="postgresql://${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Colores ──────────────────────────────────────────────────
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

run_sql() {
    local file="$1"
    local desc="$2"
    echo -e "   ${CYAN}→${NC} $desc"
    psql "$DATABASE_URL" \
        --single-transaction \
        --set ON_ERROR_STOP=1 \
        -f "$SCRIPT_DIR/$file" \
        --quiet
    echo -e "   ${GREEN}✓${NC} OK"
}

echo ""
echo -e "${BOLD}${CYAN}================================================${NC}"
echo -e "${BOLD}${CYAN}  💰 mantrasdb — Módulo Finance${NC}"
echo -e "${BOLD}${CYAN}  DB: ${DATABASE_URL}${NC}"
echo -e "${BOLD}${CYAN}================================================${NC}"
echo ""

echo -e "${BOLD}▶  Verificando conexión...${NC}"
psql "$DATABASE_URL" -c "SELECT 1;" > /dev/null 2>&1 || {
    echo -e "${RED}✗ No se pudo conectar a la base de datos.${NC}"
    exit 1
}
echo -e "   ${GREEN}✓ Conexión OK${NC}"
echo ""

echo -e "${BOLD}▶  Instalando Finance...${NC}"
echo ""

run_sql "01_accounts_periods.sql"    "01 — Plan de Cuentas (PCGE Perú + PGC España) + Períodos"
run_sql "02_journal_entries.sql"     "02 — Asientos contables (doble partida + vistas Libro Mayor)"
run_sql "03_accounts_payable.sql"    "03 — Cuentas por Pagar (AP) + detracciones + retenciones"
run_sql "04_treasury_banking.sql"    "04 — Tesorería y Bancos + caja chica + tipos de cambio"
run_sql "05_fixed_assets.sql"        "05 — Activos Fijos + depreciación SUNAT + revaluaciones"
run_sql "06_taxes_ple.sql"           "06 — Impuestos + PLE SUNAT + detracciones + fraccionamiento"
run_sql "07_budgets_cost_centers.sql""07 — Presupuestos + Centros de Costo + distribución"
run_sql "08_closing_intercompany.sql""08 — Revaluación FX + Intercompany + Cierre de ejercicio"

echo ""
echo -e "${BOLD}${GREEN}================================================${NC}"
echo -e "${BOLD}${GREEN}  ✅ Módulo Finance instalado${NC}"
echo -e "${BOLD}${GREEN}================================================${NC}"
echo ""

# Contar tablas del schema finance
TABLE_COUNT=$(psql "$DATABASE_URL" -t -A -c "
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = 'finance' AND table_type = 'BASE TABLE';" 2>/dev/null || echo "?")

VIEW_COUNT=$(psql "$DATABASE_URL" -t -A -c "
    SELECT COUNT(*) FROM information_schema.views
    WHERE table_schema = 'finance';" 2>/dev/null || echo "?")

echo -e "   Tablas finance:   ${BOLD}${TABLE_COUNT}${NC}"
echo -e "   Vistas finance:   ${BOLD}${VIEW_COUNT}${NC}"
echo ""
