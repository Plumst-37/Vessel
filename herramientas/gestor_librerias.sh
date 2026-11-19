#!/usr/bin/env bash
# ==============================================================================
# VESSEL - GESTOR MODULAR DE LIBRERÍAS Y MEJORAS DE CÓDIGO ABIERTO
# Descarga bajo demanda, instala y optimiza:
# 1. cnc-ddraw (Traductor DirectDraw a OpenGL/Vulkan para clásicos DirectX 1-7)
# 2. DSOAL + OpenAL Soft (Audio 3D Espacial y EAX binaural HRTF)
# 3. SDL2 GameControllerDB (Base de datos universal de 1000+ mandos USB/Bluetooth)
# 4. vkBasalt (Nitidez adaptativa AMD CAS y post-procesado Vulkan)
# 5. Gamescope (Micro-compositor de Valve para reescalado FSR de resolución fija)
# ==============================================================================

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="${DIR}/librerias_cache"
HERRAMIENTAS_DIR="${DIR}/herramientas"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

mkdir -p "$CACHE_DIR" "$HERRAMIENTAS_DIR"

# 1. ACTUALIZAR BASE DE DATOS DE MANDOS (gamecontrollerdb.txt)
actualizar_gamecontrollerdb() {
    echo -e "${CYAN}🎮 Actualizando base comunitaria de mandos (SDL_GameControllerDB)...${RESET}"
    local target_file="${HERRAMIENTAS_DIR}/gamecontrollerdb.txt"
    if curl -sL --connect-timeout 10 --max-time 30 "https://raw.githubusercontent.com/mdqinc/SDL_GameControllerDB/master/gamecontrollerdb.txt" -o "${target_file}.tmp"; then
        if [ -s "${target_file}.tmp" ]; then
            mv -f "${target_file}.tmp" "$target_file"
            echo -e "${GREEN}✓ Mapeos de mandos actualizados con éxito ($(wc -l < "$target_file") perfiles cargados).${RESET}"
            return 0
        fi
    fi
    rm -f "${target_file}.tmp" 2>/dev/null || true
    echo -e "${YELLOW}⚠ No se pudo descargar la última versión; conservando copia local existente.${RESET}"
    return 1
}

# 2. INSTALAR CNC-DDRAW (DirectDraw a OpenGL)
instalar_cnc_ddraw() {
    local target_dir="${1:-}"
    local ddraw_cache="${CACHE_DIR}/cnc-ddraw"
    mkdir -p "$ddraw_cache"

    if [ ! -f "${ddraw_cache}/ddraw.dll" ]; then
        echo -e "${CYAN}📦 Descargando cnc-ddraw (vía FunkyFr3sh/cnc-ddraw)...${RESET}"
        local zip_file="${ddraw_cache}/cnc-ddraw.zip"
        if curl -sL --connect-timeout 10 --max-time 60 "https://github.com/FunkyFr3sh/cnc-ddraw/releases/latest/download/cnc-ddraw.zip" -o "$zip_file"; then
            if command -v unzip &>/dev/null; then
                unzip -q -o "$zip_file" -d "$ddraw_cache"
                rm -f "$zip_file"
            else
                echo -e "${RED}✗ Error: Se requiere 'unzip' para desempaquetar cnc-ddraw.${RESET}"
                return 1
            fi
        else
            echo -e "${RED}✗ Error al descargar cnc-ddraw desde GitHub.${RESET}"
            return 1
        fi
    fi

    if [ -n "$target_dir" ] && [ -d "$target_dir" ]; then
        echo -e "${CYAN}🔧 Inyectando cnc-ddraw en: ${BOLD}${target_dir}${RESET}"
        cp -f "${ddraw_cache}/ddraw.dll" "${target_dir}/ddraw.dll"
        [ -d "${ddraw_cache}/shaders" ] && cp -rf "${ddraw_cache}/shaders" "${target_dir}/"

        # Configurar ddraw.ini optimizado para 100% compatibilidad multi-GPU
        cat << 'EOF' > "${target_dir}/ddraw.ini"
[ddraw]
renderer=opengl
windowed=false
fullscreen=true
maintas=true
boxing=false
vsync=true
adjrefreshrate=true
shader=shaders/interpolation/bilinear.glsl
fixchilds=2
hook=4
EOF
        echo -e "${GREEN}✓ cnc-ddraw inyectado y optimizado con renderizador OpenGL y filtrado bilinear.${RESET}"
    else
        echo -e "${GREEN}✓ cnc-ddraw listo en caché local de Vessel (${ddraw_cache}).${RESET}"
    fi
}

# 3. INSTALAR DSOAL + OPENAL SOFT (Audio 3D Espacial EAX)
instalar_dsoal() {
    local target_dir="${1:-}"
    local dsoal_cache="${CACHE_DIR}/dsoal"
    mkdir -p "$dsoal_cache"

    if [ ! -f "${dsoal_cache}/dsound.dll" ] || [ ! -f "${dsoal_cache}/dsoal-aldrv.dll" ]; then
        echo -e "${CYAN}📦 Descargando DSOAL (Audio 3D EAX binaural vía kcat/dsoal)...${RESET}"
        local zip_file="${dsoal_cache}/DSOAL.zip"
        if curl -sL --connect-timeout 10 --max-time 60 "https://github.com/kcat/dsoal/releases/download/latest-master/DSOAL.zip" -o "$zip_file"; then
            if command -v unzip &>/dev/null; then
                unzip -q -o "$zip_file" -d "$dsoal_cache"
                rm -f "$zip_file"
                # Si viene un zip anidado (ej. DSOAL_r697.zip), descomprimirlo también
                find "$dsoal_cache" -name "*.zip" -exec unzip -q -o {} -d "$dsoal_cache" \; 2>/dev/null || true
                # Aplanar estructura de DLLs de 32 bits (Win32) hacia la raíz de caché
                find "$dsoal_cache" -type f \( -iname "dsound.dll" -o -iname "dsoal-aldrv.dll" \) -exec cp -f {} "$dsoal_cache/" \; 2>/dev/null || true
                find "$dsoal_cache" -name "*.zip" -delete 2>/dev/null || true
            else
                echo -e "${RED}✗ Error: Se requiere 'unzip' para desempaquetar DSOAL.${RESET}"
                return 1
            fi
        else
            echo -e "${RED}✗ Error al descargar DSOAL desde GitHub.${RESET}"
            return 1
        fi
    fi

    # Configuración de OpenAL Soft con HRTF (Head-Related Transfer Function) para auriculares
    cat << 'EOF' > "${dsoal_cache}/alsoft.ini"
[general]
drivers = -dsound,
hrtf = true
default-reverb = true
resampler = sinc
stereo-mode = headphones
EOF

    if [ -n "$target_dir" ] && [ -d "$target_dir" ]; then
        echo -e "${CYAN}🔧 Inyectando DSOAL en: ${BOLD}${target_dir}${RESET}"
        cp -f "${dsoal_cache}/dsound.dll" "${target_dir}/dsound.dll"
        cp -f "${dsoal_cache}/dsoal-aldrv.dll" "${target_dir}/dsoal-aldrv.dll"
        cp -f "${dsoal_cache}/alsoft.ini" "${target_dir}/alsoft.ini"
        echo -e "${GREEN}✓ DSOAL inyectado: Sonido envolvente 3D binaural y EAX activo con HRTF.${RESET}"
    else
        echo -e "${GREEN}✓ DSOAL listo en caché local de Vessel (${dsoal_cache}).${RESET}"
    fi
}

# 4. CONFIGURAR VKBASALT (Nitidez AMD CAS en Vulkan)
configurar_vkbasalt() {
    local conf_dir="${HOME}/.config/vkBasalt"
    mkdir -p "$conf_dir"
    cat << 'EOF' > "${conf_dir}/vkBasalt.conf"
# Configuración Optimizada de Nitidez Ultra-HD AMD CAS para Vessel
effects = cas
casSharpness = 0.4
enableOnLaunch = True
toggleKey = Home
EOF
    echo -e "${GREEN}✓ Archivo de configuración de vkBasalt generado en: ${conf_dir}/vkBasalt.conf${RESET}"
    echo -e "    - Efecto Activo: AMD Contrast Adaptive Sharpening (CAS 0.4)"
    echo -e "    - Tecla rápida para activar/desactivar en tiempo real: ${BOLD}Inicio (Home)${RESET}"
}

# 5. DIAGNÓSTICO DEL ECOSISTEMA DE MEJORAS
mostrar_estado() {
    echo -e "\n${BOLD}${BLUE}================================================================${RESET}"
    echo -e "${BOLD}${BLUE}    ESTADO DE LIBRERÍAS Y MEJORAS DE CÓDIGO ABIERTO EN VESSEL   ${RESET}"
    echo -e "${BOLD}${BLUE}================================================================${RESET}\n"

    # GameControllerDB
    if [ -f "${HERRAMIENTAS_DIR}/gamecontrollerdb.txt" ]; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}SDL2 GameControllerDB:${RESET} Presente ($(wc -l < "${HERRAMIENTAS_DIR}/gamecontrollerdb.txt") mandos soportados)"
    else
        echo -e "  [${YELLOW}✗${RESET}] ${BOLD}SDL2 GameControllerDB:${RESET} No encontrado (ejecuta actualización)"
    fi

    # cnc-ddraw
    if [ -f "${CACHE_DIR}/cnc-ddraw/ddraw.dll" ]; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}cnc-ddraw (DirectDraw -> OpenGL):${RESET} Descargado y listo en caché"
    else
        echo -e "  [${YELLOW}○${RESET}] ${BOLD}cnc-ddraw:${RESET} Descargable bajo demanda para juegos retro"
    fi

    # DSOAL
    if [ -f "${CACHE_DIR}/dsoal/dsound.dll" ]; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}DSOAL (Audio 3D Espacial / EAX):${RESET} Descargado y listo en caché"
    else
        echo -e "  [${YELLOW}○${RESET}] ${BOLD}DSOAL:${RESET} Descargable bajo demanda para juegos clásicos"
    fi

    # vkBasalt
    if command -v vkbasalt &>/dev/null || [ -f "/usr/lib/x86_64-linux-gnu/libvkbasalt.so" ] || [ -f "/usr/lib64/libvkbasalt.so" ] || [ -f "/usr/lib/libvkbasalt.so" ]; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}vkBasalt (Post-procesado Vulkan):${RESET} Instalado en el sistema"
    else
        echo -e "  [${YELLOW}○${RESET}] ${BOLD}vkBasalt:${RESET} No detectado en el sistema (opcional)"
    fi

    # Gamescope
    if command -v gamescope &>/dev/null; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}Gamescope (Micro-compositor Valve):${RESET} Instalado y listo ($(gamescope --version 2>&1 | head -n 1 || echo "Activo"))"
    else
        echo -e "  [${YELLOW}○${RESET}] ${BOLD}Gamescope:${RESET} No detectado en el sistema (opcional para reescalado FSR de resolución fija)"
    fi
    echo ""
}

# MODO INTERACTIVO O CLI
case "${1:-menu}" in
    actualizar_mandos)
        actualizar_gamecontrollerdb
        ;;
    instalar_ddraw)
        instalar_cnc_ddraw "${2:-}"
        ;;
    instalar_dsoal)
        instalar_dsoal "${2:-}"
        ;;
    configurar_vkbasalt)
        configurar_vkbasalt
        ;;
    estado)
        mostrar_estado
        ;;
    menu|*)
        mostrar_estado
        echo -e "${PURPLE}Opciones disponibles:${RESET}"
        echo "  [1] Actualizar base de datos de mandos (gamecontrollerdb.txt)"
        echo "  [2] Descargar / Preparar cnc-ddraw (DirectDraw OpenGL)"
        echo "  [3] Descargar / Preparar DSOAL (Audio 3D EAX)"
        echo "  [4] Generar configuración optimizada de vkBasalt (AMD CAS)"
        echo "  [5] Salir"
        echo ""
        read -rp "Selecciona una opción [1-5]: " opc
        case "$opc" in
            1) actualizar_gamecontrollerdb ;;
            2) instalar_cnc_ddraw ;;
            3) instalar_dsoal ;;
            4) configurar_vkbasalt ;;
            *) echo "Saliendo..." ;;
        esac
        ;;
esac
