#!/usr/bin/env bash
# ============================================================
# mantrasdb — Actualizar grafos Graphify + exportar a Obsidian
# Doble clic para ejecutar.
# ============================================================

export PAGER=''
export PSQL_PAGER=''

cd /Users/alejandro/Proyectos/ERP

echo ""
echo "🐶 mantrasdb — Actualizando grafos"
echo "================================================"
echo ""

# 1. Limpiar caché anterior para forzar re-análisis
echo "▶  Limpiando caché anterior..."
rm -rf graphify-out
echo "   ✅ OK"
echo ""

# 2. Extraer grafo SOLO de las carpetas relevantes
#    (no analizamos node_modules, venv, ni docs de módulos sin construir)
echo "▶  graphify (extrayendo nodos y aristas)..."
graphify \
    mantras-api/src \
    mantras-web/src \
    docs/hr/sql
echo ""

# 3. Clustering
echo "▶  graphify cluster-only (agrupando comunidades)..."
graphify cluster-only ~/Proyectos/ERP
echo ""

# 4. Exportar a Obsidian
echo "▶  Exportando a Obsidian..."
graphify export obsidian \
    --dir ./graphify-out/obsidian \
    --graph ./graphify-out/graph.json
echo ""

echo "================================================"
echo "✅ Grafos actualizados. Revisa Obsidian."
echo "================================================"
echo ""
read -p "   Presiona Enter para cerrar..." _
