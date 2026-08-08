#!/usr/bin/env bash
# ============================================================
# mantrasdb | Módulo Logistics — Script de instalación
# Ejecuta los archivos SQL en orden estricto de dependencias.
#
# Uso:
#   chmod +x run_logistics.sh
#   ./run_logistics.sh [DATABASE_URL]
#
# Ejemplo:
#   ./run_logistics.sh postgresql://user:pass@localhost:5432/mantrasdb
#
# Si no pasas DATABASE_URL, usa la variable de entorno $DATABASE_URL
# ============================================================

set -euo pipefail

DB_URL="${1:-$DATABASE_URL}"

if [ -z "$DB_URL" ]; then
  echo "❌  Error: DATABASE_URL no definido."
  echo "    Uso: ./run_logistics.sh postgresql://user:pass@host:5432/db"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

run_sql() {
    local file="$1"
    echo "▶  Ejecutando: $(basename "$file")"
    psql "$DB_URL" -f "$file" -v ON_ERROR_STOP=1 --quiet
    echo "   ✅ OK"
}

echo ""
echo "🐶 mantrasdb — Módulo Logistics"
echo "================================================"
echo "  Base de datos: $DB_URL"
echo "================================================"
echo ""

# Nota: el módulo HR debe estar instalado previamente.
# Los scripts de HR crean hr.companies, hr.employees, etc.

run_sql "$SCRIPT_DIR/01_statuses_types.sql"
run_sql "$SCRIPT_DIR/02_suppliers_carriers.sql"
run_sql "$SCRIPT_DIR/03_products.sql"
run_sql "$SCRIPT_DIR/04_product_kits.sql"
run_sql "$SCRIPT_DIR/05_warehouses_locations.sql"
run_sql "$SCRIPT_DIR/06_inventory.sql"
run_sql "$SCRIPT_DIR/07_containers.sql"
run_sql "$SCRIPT_DIR/08_inbound.sql"
run_sql "$SCRIPT_DIR/09_waves_picking.sql"
run_sql "$SCRIPT_DIR/10_outbound.sql"
run_sql "$SCRIPT_DIR/11_transfers.sql"
run_sql "$SCRIPT_DIR/12_robots.sql"
run_sql "$SCRIPT_DIR/13_differentiators.sql"

echo ""
echo "================================================"
echo "🎉  Módulo Logistics instalado correctamente."
echo "    Tablas creadas en el schema: logistics"
echo "================================================"
echo ""
