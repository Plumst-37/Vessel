#!/usr/bin/env bash
# ==============================================================================
# VESSEL - LANZADOR UNIVERSAL INTELIGENTE (TERMINAL / ESCRITORIO)
# ==============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Si se ejecuta desde una terminal interactiva (stdin y stdout son TTY), ejecutar directo
if [ -t 0 ] && [ -t 1 ]; then
    exec bash "${DIR}/menu-win.sh" "$@"
fi

# Si se ejecuta desde el entorno gráfico (doble clic en acceso directo o menú de aplicaciones),
# buscar el emulador de terminal adecuado disponible en el sistema del usuario:
for term in konsole gnome-terminal ptyxis xfce4-terminal mate-terminal tilix alacritty kitty foot qterminal terminator x-terminal-emulator xterm; do
    if command -v "$term" &>/dev/null; then
        case "$term" in
            konsole)
                exec konsole --workdir "$DIR" -e bash "${DIR}/menu-win.sh" "$@"
                ;;
            gnome-terminal|tilix|ptyxis)
                exec "$term" --working-directory="$DIR" -- bash "${DIR}/menu-win.sh" "$@"
                ;;
            xfce4-terminal|mate-terminal)
                exec "$term" --working-directory="$DIR" -e "bash \"${DIR}/menu-win.sh\" $*"
                ;;
            alacritty)
                exec alacritty --working-directory "$DIR" -e bash "${DIR}/menu-win.sh" "$@"
                ;;
            kitty)
                exec kitty --directory "$DIR" bash "${DIR}/menu-win.sh" "$@"
                ;;
            foot)
                exec foot -D "$DIR" bash "${DIR}/menu-win.sh" "$@"
                ;;
            qterminal)
                exec qterminal -d "$DIR" -e bash "${DIR}/menu-win.sh" "$@"
                ;;
            terminator)
                exec terminator --working-directory="$DIR" -e "bash \"${DIR}/menu-win.sh\" $*"
                ;;
            *)
                exec "$term" -e bash "${DIR}/menu-win.sh" "$@"
                ;;
        esac
    fi
done

# Fallback si no se detectó ningún emulador gráfico conocido:
# Si se ejecutó sin TTY interactivo (ej. doble clic en el escritorio) y no hay emulador gráfico,
# emitir una ventana visual informativa (Zenity/KDialog/Notify-Send/xmessage) en vez de cerrarse en silencio.
if [ ! -t 0 ]; then
    msg="Vessel requiere una ventana de terminal para mostrar su menú interactivo.\n\nNo se encontró un emulador de terminal gráfico compatible (Konsole, GNOME Terminal, Alacritty, XFCE Terminal, XTerm, etc.).\n\nPuedes abrir tu terminal habitual e iniciar Vessel escribiendo:\n  bash \"${DIR}/vessel.sh\""
    if command -v zenity &>/dev/null; then
        zenity --warning --title="Vessel - Terminal Requerida" --text="$msg" --width=450 2>/dev/null || true
        exit 1
    elif command -v kdialog &>/dev/null; then
        kdialog --sorry "$msg" --title "Vessel - Terminal Requerida" 2>/dev/null || true
        exit 1
    elif command -v notify-send &>/dev/null; then
        notify-send -u critical "Vessel" "Abre una terminal y ejecuta: bash '${DIR}/vessel.sh'" 2>/dev/null || true
        exit 1
    elif command -v xmessage &>/dev/null; then
        xmessage -center "$msg" 2>/dev/null || true
        exit 1
    fi
fi

exec bash "${DIR}/menu-win.sh" "$@"
