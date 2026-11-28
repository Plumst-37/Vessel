#!/usr/bin/env bash
# ==============================================================================
# VESSEL - LANZADOR DEL MENÚ PRINCIPAL TUI
# ==============================================================================
# Licencia GNU General Public License v3.0 (GNU GPL-3.0)
# Redirige de forma transparente al motor unificado core/menu_tui.py
# asegurando terminal interactiva y liberando memoria automáticamente.
# ==============================================================================

# Autoprotección multi-shell: Si se ejecuta con dash, sh, zsh o fish, cambiar a bash
if [ -z "$BASH_VERSION" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    fi
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CORE_DIR="${DIR}/core"
[ ! -d "$CORE_DIR" ] && CORE_DIR="${DIR}"

# 1. Si no hay TTY interactiva (ej. doble clic en el entorno gráfico), invocar terminal
if [ ! -t 0 ] || [ ! -t 1 ]; then
    for term in konsole gnome-terminal ptyxis xfce4-terminal mate-terminal tilix alacritty kitty foot qterminal terminator x-terminal-emulator xterm; do
        if command -v "$term" &>/dev/null; then
            case "$term" in
                konsole)
                    exec konsole --workdir "$DIR" -e bash "$0" "$@"
                    ;;
                gnome-terminal|tilix|ptyxis)
                    exec "$term" --working-directory="$DIR" -- bash "$0" "$@"
                    ;;
                xfce4-terminal|mate-terminal)
                    exec "$term" --working-directory="$DIR" -e "bash \"$0\" $*"
                    ;;
                alacritty)
                    exec alacritty --working-directory "$DIR" -e bash "$0" "$@"
                    ;;
                kitty)
                    exec kitty --directory "$DIR" bash "$0" "$@"
                    ;;
                foot)
                    exec foot -D "$DIR" bash "$0" "$@"
                    ;;
                qterminal)
                    exec qterminal -d "$DIR" -e bash "$0" "$@"
                    ;;
                terminator)
                    exec terminator --working-directory="$DIR" -e "bash \"$0\" $*"
                    ;;
                *)
                    exec "$term" -e bash "$0" "$@"
                    ;;
            esac
        fi
    done
fi

# 2. Iniciar el menú interactivo principal unificado en Python
if command -v python3 &>/dev/null; then
    if [ -f "${CORE_DIR}/menu_tui.py" ]; then
        exec python3 "${CORE_DIR}/menu_tui.py" "$@"
    elif [ -f "${DIR}/menu_tui.py" ]; then
        exec python3 "${DIR}/menu_tui.py" "$@"
    fi
fi

# 3. Fallback de emergencia si python3 no estuviera disponible
echo "[!] Python 3 no encontrado en el sistema. Ejecutando Vessel CLI..."
exec bash "${DIR}/vessel.sh" help
