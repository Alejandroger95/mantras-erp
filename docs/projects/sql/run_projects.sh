#!/usr/bin/env bash
# ============================================================
# run_projects.sh — Módulo Projects de mantrasdb
# ============================================================
# Instala el módulo Projects en orden de dependencias:
#   01 — Schema, tipos y proyectos (núcleo)
#   02 — Equipo, tareas y registro de horas
#   03 — Documentos, riesgos y log de estados
#   04 — Vistas analíticas y KPIs
#
# Uso:
#   chmod +x run_projects.sh
#   ./run_projects.sh
#   ./run_projects.sh --reset          # elimina schema y reinstala
#
# Variables de entorno:
#   DATABASE_URL  (default: postgresql://localhost:5432/mantrasdb)
#
# Ejemplos:
#   DATABASE_URL=postgresql://user:pass@host:5432/mantrasdb ./run_projects.sh
#   ./run_projects.sh postgres://localhost/mantrasdb
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# DATABASE_URL puede venir del entorno, del primer argumento (si no es --reset),
# o usa el valor por defecto.
if [[ "${1:-}" != "--reset" && -n "${1:-}" ]]; then
    DATABASE_URL="${1}"
fi
DATABASE_URL="${DATABASE_URL:-postgresql://localhost:5432/mantrasdb}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${CYAN}[Projects]${NC} $1"; }
ok()   { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

# ── Reset opcional ───────────────────────────────────────────
if [[ "${1:-}" == "--reset" ]] || [[ "${2:-}" == "--reset" ]]; then
    echo -e "${YELLOW}⚠  Eliminando schema projects...${NC}"
    psql "$DATABASE_URL" -c "DROP SCHEMA IF EXISTS projects CASCADE;" --quiet
    ok "Schema projects eliminado."
    echo ""
fi

# ── Función auxiliar para ejecutar SQL ───────────────────────
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

# ── Banner ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       mantrasdb — Módulo Projects                ║${NC}"
echo -e "${BOLD}║       Schema: projects                           ║${NC}"
echo -e "${BOLD}║                                                  ║${NC}"
echo -e "${BOLD}║   Para: agencias de software, consultoras,       ║${NC}"
echo -e "${BOLD}║         constructoras, cualquier negocio de      ║${NC}"
echo -e "${BOLD}║         proyectos.                               ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# ── Verificar conexión ───────────────────────────────────────
psql "$DATABASE_URL" -c "SELECT 1;" > /dev/null 2>&1 || {
    echo -e "${RED}✗ No se pudo conectar a la base de datos.${NC}"
    echo -e "  DATABASE_URL: ${DATABASE_URL}"
    echo -e "  Verifica que PostgreSQL esté corriendo y que la DB exista."
    exit 1
}
ok "Conexión OK"
echo ""

# ── Ejecutar archivos en orden ───────────────────────────────
run_sql "01_projects.sql"        "01 — Schema, tipos de proyecto, proyectos, fases e hitos"
run_sql "02_tasks_team.sql"      "02 — Miembros del equipo, tareas y registro de horas"
run_sql "03_documents_risks.sql" "03 — Documentos, riesgos y log de estados"
run_sql "04_views_kpis.sql"      "04 — Vistas analíticas y KPIs (dashboard, utilización, billing)"
run_sql "05_hr_bridge.sql"       "05 — Puente HR: carga por empleado/departamento, sobrecarga"

# ── Resultado ────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}✔ Módulo Projects instalado correctamente.${NC}"
echo ""

psql "$DATABASE_URL" --quiet -c "
SELECT
    tipo,
    cantidad
FROM (
    SELECT
        'Tablas'    AS tipo,
        COUNT(*)    AS cantidad,
        1           AS ord
    FROM information_schema.tables
    WHERE table_schema = 'projects'
      AND table_type = 'BASE TABLE'
    UNION ALL
    SELECT
        'Vistas',
        COUNT(*),
        2
    FROM information_schema.views
    WHERE table_schema = 'projects'
) t
ORDER BY ord;
"
echo ""
