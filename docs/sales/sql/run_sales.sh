#!/usr/bin/env bash
# ============================================================
# mantrasdb | Módulo Sales — Script de instalación
# Prerequisito: módulos HR y Logistics instalados.
#
# Uso:
#   chmod +x run_sales.sh
#   ./run_sales.sh [DATABASE_URL]
# ============================================================

set -euo pipefail

DB_URL="${1:-$DATABASE_URL}"

if [ -z "$DB_URL" ]; then
  echo "❌  Error: DATABASE_URL no definido."
  echo "    Uso: ./run_sales.sh postgresql://user@localhost:5432/mantrasdb"
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
echo "🐶 mantrasdb — Módulo Sales"
echo "================================================"

# Núcleo del módulo
run_sql "$SCRIPT_DIR/01_statuses_types.sql"
run_sql "$SCRIPT_DIR/02_customers.sql"
run_sql "$SCRIPT_DIR/03_pricing.sql"
run_sql "$SCRIPT_DIR/04_quotations.sql"
run_sql "$SCRIPT_DIR/05_sales_orders.sql"
run_sql "$SCRIPT_DIR/06_invoicing.sql"
run_sql "$SCRIPT_DIR/07_collections.sql"
run_sql "$SCRIPT_DIR/08_commissions.sql"
run_sql "$SCRIPT_DIR/09_differentiators.sql"
# 09 incluye: canales de venta, fidelización, forecast, motivos de anulación, FKs diferidas

# Extensiones avanzadas
run_sql "$SCRIPT_DIR/10_promotions.sql"
# Motor completo: BOGO, flash sale, bundles, rebaja peruana, rebates retroactivos

run_sql "$SCRIPT_DIR/11_pos_store.sql"
# Tiendas físicas, terminales POS, sesiones de caja, transacciones POS

run_sql "$SCRIPT_DIR/12_returns.sql"
# RMA, inspección, disposición (restock/destrucción/garantía), warranty claims

run_sql "$SCRIPT_DIR/13_customer_extensions.sql"
# Categorías de cliente + cuentas bancarias del cliente (multi-moneda, cuenta preferida)

echo ""
echo "================================================"
echo "🎉  Módulo Sales instalado correctamente."
echo "    Tablas creadas en el schema: sales"
echo "================================================"
echo ""
