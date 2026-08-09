#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" != "--reset" && -n "${1:-}" ]]; then DATABASE_URL="${1}"; fi
DATABASE_URL="${DATABASE_URL:-postgresql://localhost:5432/mantrasdb}"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
if [[ "${1:-}" == "--reset" ]] || [[ "${2:-}" == "--reset" ]]; then
    echo -e "${YELLOW}⚠  Eliminando schema crm...${NC}"
    psql "$DATABASE_URL" -c "DROP SCHEMA IF EXISTS crm CASCADE;" --quiet
fi
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       mantrasdb — Módulo CRM                     ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}[CRM]${NC} Ejecutando: 01 — Pipelines, leads, oportunidades, actividades..."
psql "$DATABASE_URL" --single-transaction --set ON_ERROR_STOP=1 -f "${SCRIPT_DIR}/01_crm.sql" --quiet
echo -e "${GREEN}✓${NC} 01 — CRM completado."
echo ""
echo -e "${GREEN}${BOLD}✔ Módulo CRM instalado correctamente.${NC}"
psql "$DATABASE_URL" --quiet -c "
SELECT tipo, cantidad FROM (
    SELECT 'Tablas' AS tipo, COUNT(*) AS cantidad, 1 AS ord FROM information_schema.tables WHERE table_schema='crm' AND table_type='BASE TABLE'
    UNION ALL
    SELECT 'Vistas', COUNT(*), 2 FROM information_schema.views WHERE table_schema='crm'
) t ORDER BY ord;"
echo ""
