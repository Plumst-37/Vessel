#!/bin/bash
# ==============================================================================
# Lanzador Directo Optimizado para Grand Theft Auto V
# ==============================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GTA_DIR="/media/plumst/Disco duro/Juegos/GTA V LITE V13.2 OptiJuegos/GTA V LITE V13.2 OptiJuegos"

exec "${DIR}/launch-win-app.sh" "${GTA_DIR}/gta_data/PlayGTAV.exe" "$@"
