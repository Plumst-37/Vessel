#!/usr/bin/env bash
# ==============================================================================
# VESSEL - EJECUTOR ULTRALIVIANO DE JUEGOS CON LIBERACIÓN TOTAL DE RAM
# Libera el proceso de Python de la memoria RAM (ahorro de ~25MB)
# y reabre el menú interactivo automáticamente al salir del juego.
# ==============================================================================
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="${DIR}/launch-win-app.sh"

# Si se solicitó HUD por variable o flag
if [ "${ENABLE_DXVK_HUD:-0}" = "1" ]; then
    export ENABLE_DXVK_HUD="1"
fi

# Ejecutar el juego a través del lanzador nativo de Vessel
bash "$LAUNCHER" "$@"
EXIT_CODE=$?

# Pausa interactiva para visualizar registros o estado de salida
echo ""
echo -e "\033[1;36m════════════════════════════════════════════════════════════════\033[0m"
if [ "$EXIT_CODE" -eq 0 ]; then
    echo -e "\033[1;32m✔ Sesión de juego finalizada correctamente.\033[0m"
else
    echo -e "\033[1;33mℹ El proceso del juego finalizó con código: ${EXIT_CODE}\033[0m"
fi
echo -e "\033[1;35mRestaurando entorno de Vessel...\033[0m"
echo -e "\033[1;36m════════════════════════════════════════════════════════════════\033[0m"
echo ""
read -rp "Presiona [Enter] para volver al Menú Principal... " dummy 2>/dev/null || true

# Limpiar variable temporal de HUD para el menú
unset ENABLE_DXVK_HUD

# Reabrir el menú interactivo TUI de Vessel reemplazando el proceso actual
if command -v python3 &>/dev/null && [ -f "${DIR}/menu_tui.py" ]; then
    exec python3 "${DIR}/menu_tui.py"
elif [ -f "${DIR}/menu-win.sh" ]; then
    exec bash "${DIR}/menu-win.sh"
fi
