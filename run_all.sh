#!/usr/bin/env bash
# ============================================================
# mantrasdb — Script maestro de instalación completa
# Instala todos los módulos en orden de dependencias.
#
# Uso:
#   chmod +x run_all.sh
#   ./run_all.sh
#
# Variables de entorno opcionales:
#   DB_HOST  (default: localhost)
#   DB_PORT  (default: 5432)
#   DB_USER  (default: postgres)
#   DB_NAME  (default: mantrasdb)
#
# Ejemplos:
#   ./run_all.sh
#   DB_USER=alejandro ./run_all.sh
#   DB_HOST=192.168.1.10 DB_USER=admin DB_NAME=mantrasdb ./run_all.sh
#
# Para borrar todo y reinstalar desde cero:
#   ./run_all.sh --reset
# ============================================================

set -euo pipefail

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-mantrasdb}"
RESET=false

for arg in "$@"; do
  case $arg in
    --reset) RESET=true ;;
  esac
done

# Construir DATABASE_URL para los scripts que lo usan
export DATABASE_URL="postgresql://${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Colores ──────────────────────────────────────────────────
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}${CYAN}================================================${NC}"
echo -e "${BOLD}${CYAN}  🐶 mantrasdb — Instalación completa${NC}"
echo -e "${BOLD}${CYAN}  Host : ${DB_HOST}:${DB_PORT}${NC}"
echo -e "${BOLD}${CYAN}  DB   : ${DB_NAME}   User: ${DB_USER}${NC}"
echo -e "${BOLD}${CYAN}================================================${NC}"
echo ""

# ── Verificar conexión ───────────────────────────────────────
psql "$DATABASE_URL" -c "SELECT 1;" > /dev/null 2>&1 || {
  echo -e "${RED}✗ No se pudo conectar a la base de datos.${NC}"
  echo -e "  Verifica que PostgreSQL esté corriendo y que la DB '${DB_NAME}' exista."
  echo -e "  Crear la DB: ${YELLOW}createdb -U ${DB_USER} ${DB_NAME}${NC}"
  exit 1
}
echo -e "${GREEN}✓ Conexión OK${NC}"
echo ""

# ── Reset opcional ───────────────────────────────────────────
if [ "$RESET" = true ]; then
  echo -e "${YELLOW}⚠  Modo --reset: eliminando todos los schemas...${NC}"
  # Cada DROP en su propia transacción para no superar max_locks_per_transaction
  psql "$DATABASE_URL" -c "DROP SCHEMA IF EXISTS venues     CASCADE;" --quiet
  psql "$DATABASE_URL" -c "DROP SCHEMA IF EXISTS mrp        CASCADE;" --quiet
  psql "$DATABASE_URL" -c "DROP SCHEMA IF EXISTS payroll    CASCADE;" --quiet
  psql "$DATABASE_URL" -c "DROP SCHEMA IF EXISTS crm        CASCADE;" --quiet
  psql "$DATABASE_URL" -c "DROP SCHEMA IF EXISTS surveys    CASCADE;" --quiet
  psql "$DATABASE_URL" -c "DROP SCHEMA IF EXISTS projects   CASCADE;" --quiet
  psql "$DATABASE_URL" -c "DROP SCHEMA IF EXISTS services   CASCADE;" --quiet
  psql "$DATABASE_URL" -c "DROP SCHEMA IF EXISTS production CASCADE;" --quiet
  psql "$DATABASE_URL" -c "DROP SCHEMA IF EXISTS finance    CASCADE;" --quiet
  psql "$DATABASE_URL" -c "DROP SCHEMA IF EXISTS sales      CASCADE;" --quiet
  psql "$DATABASE_URL" -c "DROP SCHEMA IF EXISTS logistics  CASCADE;" --quiet
  psql "$DATABASE_URL" -c "DROP SCHEMA IF EXISTS hr         CASCADE;" --quiet
  echo -e "${GREEN}✓ Schemas eliminados${NC}"
  echo ""
fi

# ── Módulo HR ────────────────────────────────────────────────
echo -e "${BOLD}▶  Módulo: HR (Human Resources)${NC}"
echo -e "   35 tablas — base para todos los demás módulos"
echo ""

DB_HOST="$DB_HOST" DB_PORT="$DB_PORT" DB_USER="$DB_USER" DB_NAME="$DB_NAME" \
  bash "${ROOT_DIR}/docs/hr/sql/run_hr.sh"

echo ""

# ── Módulo Logistics ─────────────────────────────────────────
echo -e "${BOLD}▶  Módulo: Logistics / WMS${NC}"
echo -e "   92 tablas — WMS completo con flujos inbound/outbound"
echo ""

bash "${ROOT_DIR}/docs/logistics/sql/run_logistics.sh" "$DATABASE_URL"

echo ""

# ── Módulo Sales ─────────────────────────────────────────────
echo -e "${BOLD}▶  Módulo: Sales (Ventas)${NC}"
echo -e "   72+ tablas — cotizaciones, órdenes, facturación SUNAT, cobranzas,"
echo -e "   promociones, POS/tiendas, devoluciones/garantías, cuentas bancarias"
echo ""

bash "${ROOT_DIR}/docs/sales/sql/run_sales.sh" "$DATABASE_URL"

echo ""

# ── Módulo Finance ────────────────────────────────────────────
echo -e "${BOLD}▶  Módulo: Finance (Finanzas)${NC}"
echo -e "   Plan de Cuentas PCGE/PGC, doble partida, AP, tesorería,"
echo -e "   activos fijos SUNAT, PLE, presupuestos, centros de costo"
echo ""

bash "${ROOT_DIR}/docs/finance/sql/run_finance.sh" "$DATABASE_URL"

echo ""

# ── Módulo Production ────────────────────────────────────────
echo -e "${BOLD}▶  Módulo: Production (Producción)${NC}"
echo -e "   BOM universal, rutas, órdenes, QC, costeo, mermas SUNAT,"
echo -e "   IoT, genealogía de lotes, soporte restaurante/delivery"
echo ""

bash "${ROOT_DIR}/docs/production/sql/run_production.sh"

echo ""

# ── Módulo Services ──────────────────────────────────────────
echo -e "${BOLD}▶  Módulo: Services (Servicios)${NC}"
echo -e "   Salón de belleza, spa, clínica, veterinaria, gym, taller"
echo -e "   Citas, personal, skills, KPIs, historial cliente"
echo ""

bash "${ROOT_DIR}/docs/services/sql/run_services.sh"

echo ""

# ── Módulo Projects ──────────────────────────────────────────
echo -e "${BOLD}▶  Módulo: Projects (Proyectos)${NC}"
echo -e "   Consultoras, agencias, software — proyectos por fases,"
echo -e "   tareas, time entries, riesgos, facturación por hito o T&M"
echo ""

bash "${ROOT_DIR}/docs/projects/sql/run_projects.sh"

echo ""

# ── Módulo Surveys ───────────────────────────────────────────
echo -e "${BOLD}▶  Módulo: Surveys (Encuestas de Satisfacción)${NC}"
echo -e "   NPS, CSAT, CES — vinculado a citas, órdenes y proyectos"
echo ""

bash "${ROOT_DIR}/docs/surveys/sql/run_surveys.sh"

echo ""

# ── Módulo CRM ───────────────────────────────────────────────
echo -e "${BOLD}▶  Módulo: CRM (Customer Relationship Management)${NC}"
echo -e "   Pipelines, leads, oportunidades, actividades"
echo ""

bash "${ROOT_DIR}/docs/crm/sql/run_crm.sh"

echo ""

# ── Módulo Payroll Engine ────────────────────────────────────
echo -e "${BOLD}▶  Módulo: Payroll Engine (Motor de Nómina)${NC}"
echo -e "   Reglas de cálculo, estructuras salariales, boletas de pago"
echo ""

bash "${ROOT_DIR}/docs/payroll/sql/run_payroll.sh"

echo ""

# ── Módulo MRP ───────────────────────────────────────────────
echo -e "${BOLD}▶  Módulo: MRP (Material Requirements Planning)${NC}"
echo -e "   Parámetros, pronósticos, runs y órdenes planificadas"
echo ""

bash "${ROOT_DIR}/docs/mrp/sql/run_mrp.sh"

echo ""

# ── Módulo Venues ─────────────────────────────────────────────
echo -e "${BOLD}▶  Módulo: Venues (Recintos, Eventos, Membresías)${NC}"
echo -e "   Clubs, piscinas, estadios, salas de conciertos"
echo -e "   Eventos, aforo por zona, tickets, control de acceso, membresías"
echo ""

bash "${ROOT_DIR}/docs/venues/sql/run_venues.sh"

echo ""

# ── Auditoría global: created_by / updated_by en todas las tablas ────────────
echo -e "${BOLD}▶  Migración: columnas de auditoría (created_by / updated_by)${NC}"
echo -e "   Todas las tablas en todos los schemas"
echo ""

psql "$DATABASE_URL" \
    --single-transaction \
    --set ON_ERROR_STOP=1 \
    -f "${ROOT_DIR}/docs/hr/sql/00_audit_user_columns.sql" \
    --quiet && \
  echo -e "   ${GREEN}✓${NC} OK" || {
    echo -e "   ${RED}✗ ERROR en 00_audit_user_columns.sql${NC}"
    exit 1
  }

echo ""

# ── Resumen final ────────────────────────────────────────────
echo -e "${BOLD}${GREEN}================================================${NC}"
echo -e "${BOLD}${GREEN}  🎉 mantrasdb instalado correctamente${NC}"
echo -e "${BOLD}${GREEN}================================================${NC}"
echo ""

# Contar tablas por schema
psql "$DATABASE_URL" -t -A -c "
  SELECT '  ' || table_schema || ': ' || COUNT(*) || ' tablas'
  FROM information_schema.tables
  WHERE table_schema IN ('hr', 'logistics', 'sales', 'finance', 'production', 'services', 'projects', 'surveys', 'crm', 'payroll', 'mrp', 'venues')
    AND table_type = 'BASE TABLE'
  GROUP BY table_schema
  ORDER BY table_schema;
"
echo ""
echo -e "  Total:"
psql "$DATABASE_URL" -t -A -c "
  SELECT '  ' || COUNT(*) || ' tablas en total'
  FROM information_schema.tables
  WHERE table_schema IN ('hr', 'logistics', 'sales', 'finance', 'production', 'services', 'projects', 'surveys', 'crm', 'payroll', 'mrp', 'venues')
    AND table_type = 'BASE TABLE';
"
echo ""
