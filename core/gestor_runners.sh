#!/bin/bash
# ==============================================================================
# GESTOR Y DESCARGADOR DE RUNNERS PORTABLES DE WINE PARA VESSEL
# Permite utilizar versiones modernas de Wine (Wine-GE, Kron4ek Staging)
# en cualquier distribución Linux (Debian, Ubuntu, Arch, Fedora, SteamOS)
# sin depender de los paquetes del sistema.
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../menu-win.sh" ]; then
    DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
    DIR="$SCRIPT_DIR"
fi
RUNNERS_DIR="${DIR}/runners"
mkdir -p "$RUNNERS_DIR"

PURPLE="\033[38;2;224;86;253m"
CYAN="\033[38;2;0;164;239m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
WHITE="\033[1;37m"
RESET="\033[0m"
BOLD="\033[1m"

listar_runners() {
    echo -e "${PURPLE}══════════════════════════════════════════════════════════════════════${RESET}"
    echo -e "  ${BOLD}${WHITE}RUNNERS DE WINE DISPONIBLES EN VESSEL${RESET}"
    echo -e "${PURPLE}══════════════════════════════════════════════════════════════════════${RESET}\n"

    local count=0
    # 1. Runners locales en runners/
    if [ -d "$RUNNERS_DIR" ]; then
        for r in "$RUNNERS_DIR"/*; do
            if [ -d "$r" ] && [ -x "$r/bin/wine" ]; then
                count=$((count + 1))
                local ver
                ver=$("$r/bin/wine" --version 2>/dev/null || echo "Desconocida")
                echo -e "  ${GREEN}[$count]${RESET} ${BOLD}$(basename "$r")${RESET} -> ${CYAN}${ver}${RESET}"
                echo -e "      ${WHITE}Ruta:${RESET} $r/bin/wine"
            fi
        done
    fi

    # 2. Wine-TKG
    if [ -x "${DIR}/wine-tkg-build/bin/wine" ]; then
        count=$((count + 1))
        local ver
        ver=$("${DIR}/wine-tkg-build/bin/wine" --version 2>/dev/null || echo "Desconocida")
        echo -e "  ${GREEN}[$count]${RESET} ${BOLD}Wine-TKG Custom Build${RESET} -> ${CYAN}${ver}${RESET}"
        echo -e "      ${WHITE}Ruta:${RESET} ${DIR}/wine-tkg-build/bin/wine"
    fi

    # 3. Lutris runners
    if [ -d "$HOME/.local/share/lutris/runners/wine" ]; then
        for r in "$HOME/.local/share/lutris/runners/wine"/*; do
            if [ -d "$r" ] && [ -x "$r/bin/wine" ]; then
                count=$((count + 1))
                local ver
                ver=$("$r/bin/wine" --version 2>/dev/null || echo "Desconocida")
                echo -e "  ${GREEN}[$count]${RESET} ${BOLD}Lutris: $(basename "$r")${RESET} -> ${CYAN}${ver}${RESET}"
                echo -e "      ${WHITE}Ruta:${RESET} $r/bin/wine"
            fi
        done
    fi

    # 4. Wine del sistema
    if command -v wine &>/dev/null; then
        count=$((count + 1))
        local ver
        ver=$(wine --version 2>/dev/null || echo "Desconocida")
        echo -e "  ${GREEN}[$count]${RESET} ${BOLD}Wine del Sistema Host${RESET} -> ${CYAN}${ver}${RESET}"
        echo -e "      ${WHITE}Ruta:${RESET} $(command -v wine)"
    fi

    if [ "$count" -eq 0 ]; then
        echo -e "  ${YELLOW}⚠️  No se encontró ningún runner instalado.${RESET}\n"
    fi
    echo ""
}

descargar_runner_kron4ek() {
    local version="${1:-10.0}"
    echo -e "\n${CYAN}══════════════════════════════════════════════════════════════════════${RESET}"
    echo -e "  ${BOLD}${WHITE}DESCARGANDO WINE RUNNER PORTABLE (Kron4ek Staging WOW64 ${version})${RESET}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════${RESET}\n"
    echo -e "  ${WHITE}Este runner incluye compatibilidad completa de 32 y 64 bits, DX12, Media Foundation y Esync/Fsync.${RESET}\n"

    local filename="wine-${version}-staging-amd64-wow64.tar.xz"
    local url="https://github.com/Kron4ek/Wine-Builds/releases/download/${version}/${filename}"
    local dest_archive="/tmp/${filename}"
    local target_dir="${RUNNERS_DIR}/wine-${version}-staging-wow64"

    if [ -d "$target_dir" ] && [ -x "$target_dir/bin/wine" ]; then
        echo -e "  ${GREEN}✔ El runner ya se encuentra instalado en:${RESET} $target_dir\n"
        return 0
    fi

    echo -e "  ${YELLOW}➤ Descargando ${filename}...${RESET}"
    if command -v curl &>/dev/null; then
        curl -fSL --progress-bar "$url" -o "$dest_archive"
    elif command -v wget &>/dev/null; then
        wget -q --show-progress "$url" -O "$dest_archive"
    else
        echo -e "  ${RED}❌ Error: curl o wget son requeridos para descargar.${RESET}"
        return 1
    fi

    echo -e "\n  ${YELLOW}➤ Descomprimiendo en ${target_dir}...${RESET}"
    mkdir -p "$target_dir"
    tar -xf "$dest_archive" -C "$target_dir" --strip-components=1
    rm -f "$dest_archive"

    if [ -x "$target_dir/bin/wine" ]; then
        echo -e "  ${GREEN}✔ ¡Runner instalado y listo para usar!${RESET}"
        echo -e "  ${WHITE}Versión:${RESET} $("$target_dir/bin/wine" --version 2>/dev/null || echo "OK")\n"
    else
        echo -e "  ${RED}❌ Ocurrió un error al extraer el runner.${RESET}\n"
        return 1
    fi
}

descargar_runner_wine_ge() {
    local tag="GE-Proton8-26"
    echo -e "\n${CYAN}══════════════════════════════════════════════════════════════════════${RESET}"
    echo -e "  ${BOLD}${WHITE}DESCARGANDO WINE RUNNER PORTABLE (GloriousEggroll ${tag})${RESET}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════${RESET}\n"

    local filename="wine-lutris-${tag}-x86_64.tar.xz"
    local url="https://github.com/GloriousEggroll/wine-ge-custom/releases/download/${tag}/${filename}"
    local dest_archive="/tmp/${filename}"
    local target_dir="${RUNNERS_DIR}/${tag}"

    if [ -d "$target_dir" ] && [ -x "$target_dir/bin/wine" ]; then
        echo -e "  ${GREEN}✔ El runner Wine-GE ya se encuentra instalado en:${RESET} $target_dir\n"
        return 0
    fi

    echo -e "  ${YELLOW}➤ Descargando ${filename}...${RESET}"
    if command -v curl &>/dev/null; then
        curl -fSL --progress-bar "$url" -o "$dest_archive"
    elif command -v wget &>/dev/null; then
        wget -q --show-progress "$url" -O "$dest_archive"
    else
        echo -e "  ${RED}❌ Error: curl o wget son requeridos.${RESET}"
        return 1
    fi

    echo -e "\n  ${YELLOW}➤ Descomprimiendo en ${target_dir}...${RESET}"
    mkdir -p "$target_dir"
    tar -xf "$dest_archive" -C "$target_dir" --strip-components=1
    rm -f "$dest_archive"

    if [ -x "$target_dir/bin/wine" ]; then
        echo -e "  ${GREEN}✔ ¡Wine-GE instalado y listo para usar!${RESET}\n"
    else
        echo -e "  ${RED}❌ Ocurrió un error al extraer el runner.${RESET}\n"
        return 1
    fi
}

recomendar_runner() {
    local motivo="${1:-dx12}"
    echo -e "\n${YELLOW}💡 [ RECOMENDACIÓN DE RUNNER ]${RESET}"
    if [ "$motivo" = "dx12" ]; then
        echo -e "  ${WHITE}Este juego utiliza ${BOLD}DirectX 12 / D3D12${RESET}${WHITE}.${RESET}"
    elif [ "$motivo" = "video" ]; then
        echo -e "  ${WHITE}Este juego requiere códecs de video ${BOLD}Media Foundation (MFPlat)${RESET}${WHITE}.${RESET}"
    fi
    echo -e "  ${WHITE}Para garantizar 60 FPS estables y reproducción de cinemáticas, se recomienda usar un runner moderno.${RESET}"
    echo -e "  ${CYAN}• Instalar Kron4ek Staging WoW64:${RESET} ${BOLD}vessel runner --kron4ek${RESET}"
    echo -e "  ${CYAN}• Instalar GloriousEggroll Wine-GE:${RESET} ${BOLD}vessel runner --wine-ge${RESET}\n"
}

case "${1:-list}" in
    --list|list)
        listar_runners
        ;;
    --kron4ek)
        descargar_runner_kron4ek "${2:-10.0}"
        ;;
    --wine-ge)
        descargar_runner_wine_ge
        ;;
    --recommend|recommend)
        recomendar_runner "${2:-dx12}"
        ;;
    *)
        listar_runners
        echo "Uso: $0 [--list | --kron4ek [version] | --wine-ge | --recommend [dx12|video]]"
        ;;
esac
