#!/usr/bin/env bash
# ==============================================================================
# VESSEL - LANZADOR PRINCIPAL (ENRUTADOR UNIVERSAL)
# Redirige limpiamente a la implementación modular en core/launch-win-app.sh
# ==============================================================================
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${DIR}/core/launch-win-app.sh" ]; then
    exec bash "${DIR}/core/launch-win-app.sh" "$@"
else
    echo "[!] Error: No se encontró el componente central en: ${DIR}/core/launch-win-app.sh"
    exit 1
fi
