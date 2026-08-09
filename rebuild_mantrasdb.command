#!/usr/bin/env bash
# ============================================================
# mantrasdb — Rebuild completo
# Doble clic en este archivo para ejecutar en Terminal.
# ============================================================

cd "$(dirname "$0")"

# Desactivar pager de psql para que no pare el script
export PAGER=''
export PSQL_PAGER=''

echo ""
echo "🐶 mantrasdb — Rebuild completo (--reset)"
echo "   Directorio: $(pwd)"
echo ""

# Detectar usuario de PostgreSQL
PG_USER="${DB_USER:-$(whoami)}"
echo "   PostgreSQL user: $PG_USER"
echo ""

DB_USER="$PG_USER" ./run_all.sh --reset

echo ""
echo "✅ Listo. Puedes cerrar esta ventana."
echo ""
read -p "   Presiona Enter para cerrar..." _
