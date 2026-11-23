#!/usr/bin/env bash
# ==============================================================================
# VESSEL v1.3 - INSTALADOR UNIVERSAL EN 1-CLIC PARA GNU/LINUX
# ==============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"

if [ -f "${DIR}/core/instalar.sh" ]; then
    exec bash "${DIR}/core/instalar.sh" "$@"
else
    # Fallback para ejecución remota por curl / wget
    REAL_USER="${SUDO_USER:-$USER}"
    REAL_HOME=$(eval echo "~$REAL_USER")
    TARGET_DIR="$REAL_HOME/Vessel"

    echo -e "\033[1;36m[+] Descargando y preparando Vessel v1.3 en: ${TARGET_DIR}...\033[0m"
    if ! command -v git &>/dev/null; then
        if command -v apt-get &>/dev/null; then
            sudo apt-get update && sudo apt-get install -y git curl
        elif command -v pacman &>/dev/null; then
            sudo pacman -Sy --noconfirm git curl
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y git curl
        elif command -v zypper &>/dev/null; then
            sudo zypper --non-interactive install git curl
        fi
    fi

    if [ ! -d "$TARGET_DIR" ]; then
        git clone https://github.com/Plumst-37/Vessel.git "$TARGET_DIR"
    else
        git -C "$TARGET_DIR" pull origin main || true
    fi

    if [ -f "$TARGET_DIR/core/instalar.sh" ]; then
        exec bash "$TARGET_DIR/core/instalar.sh" "$@"
    else
        echo "Error: no se pudo ubicar el script core/instalar.sh"
        exit 1
    fi
fi
