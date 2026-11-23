#!/bin/bash
# ==============================================================================
# VESSEL - GESTOR MODULAR DE CONTROLADORES Y TRADUCTORES GRÁFICOS (OPEN-SOURCE)
# DXVK (D3D8-11), VKD3D-Proton (D3D12), DXVK-NVAPI y Optimizaciones de GPU/CPU
# Compatible 100% con GNU GPL-3.0 - Descargas limpias y dinamismo modular
# ==============================================================================

# Autoprotección multi-shell: Si se ejecuta con dash, sh, zsh o fish, cambiar a bash
if [ -z "$BASH_VERSION" ]; then
    if command -v bash >/dev/null 2>&1; then
        if [ -f "$0" ]; then
            exec bash "$0" "$@"
        fi
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../menu-win.sh" ]; then
    DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
    DIR="$SCRIPT_DIR"
fi

DRIVERS_DIR="${DIR}/drivers"
[ ! -d "$DRIVERS_DIR" ] && mkdir -p "$DRIVERS_DIR" 2>/dev/null || true

# Colores de interfaz
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ==============================================================================
# 1. CARGA DE CONFIGURACIÓN DEL ENTORNO DE DRIVERS
# ==============================================================================
cargar_gpu_env() {
    local env_conf="${DRIVERS_DIR}/gpu_env.conf"
    if [ -f "$env_conf" ]; then
        source "$env_conf"
    fi

    # Exportar rutas de configuración DXVK y VKD3D
    if [ -f "${DRIVERS_DIR}/dxvk/dxvk.conf" ]; then
        export DXVK_CONFIG_FILE="${DRIVERS_DIR}/dxvk/dxvk.conf"
    fi
    if [ -f "${DRIVERS_DIR}/vkd3d-proton/vkd3d.conf" ]; then
        export VKD3D_CONFIG_FILE="${DRIVERS_DIR}/vkd3d-proton/vkd3d.conf"
    fi

    # Habilitación de Vulkan Graphics Pipeline Library (GPL)
    if [ "${ENABLE_VULKAN_GPL:-1}" = "1" ]; then
        export HAS_VULKAN_GPL=true
    fi

    # Forzado de GPU dedicada (NVIDIA PRIME / AMD DRI_PRIME)
    if [ "${GPU_FORCE_DEDICATED:-1}" = "1" ]; then
        export __NV_PRIME_RENDER_OFFLOAD=1
        export __GLX_VENDOR_LIBRARY_NAME=nvidia
        export __VK_LAYER_NV_optimus=NVIDIA_only
        export DXVK_FILTER_DEVICE_NAME="${DXVK_DEVICE_FILTER:-NVIDIA}"
        if [ -n "${MESA_DEVICE_SELECT_OVERRIDE:-}" ]; then
            export MESA_VK_DEVICE_SELECT="${MESA_DEVICE_SELECT_OVERRIDE}"
        fi
    fi

    # Control de Hilos de CPU
    if [ -n "${CPU_COMPILER_THREADS:-}" ]; then
        export DXVK_NUM_COMPILER_THREADS="${CPU_COMPILER_THREADS}"
    fi
}

# ==============================================================================
# 2. INSTALACIÓN Y VINCULACIÓN DE DXVK (DirectX 9/10/11 -> Vulkan)
# ==============================================================================
instalar_dxvk_modular() {
    local target_prefix="${1:-${DIR}/wineprefix}"
    local dxvk_base="${DRIVERS_DIR}/dxvk"
    mkdir -p "${dxvk_base}/x64" "${dxvk_base}/x32"

    echo -e "${CYAN}📦 [ DRIVERS ] Verificando librerías DXVK (DirectX 9/10/11 -> Vulkan)...${RESET}"

    # Si no están en drivers/, buscar en librerías del sistema (/usr/lib/dxvk)
    if [ ! -f "${dxvk_base}/x64/d3d11.dll" ] && [ -d "/usr/lib/dxvk/wine64" ]; then
        echo -e "${BLUE}  🔗 Vinculando DXVK de alto rendimiento desde el sistema (/usr/lib/dxvk)...${RESET}"
        for dll in d3d11 d3d10core d3d9 d3d8 dxgi; do
            [ -f "/usr/lib/dxvk/wine64/${dll}.dll.so" ] && ln -sf "/usr/lib/dxvk/wine64/${dll}.dll.so" "${dxvk_base}/x64/${dll}.dll" 2>/dev/null || true
            [ -f "/usr/lib/dxvk/wine32/${dll}.dll.so" ] && ln -sf "/usr/lib/dxvk/wine32/${dll}.dll.so" "${dxvk_base}/x32/${dll}.dll" 2>/dev/null || true
        done
    fi

    # Si aún no están disponibles, descargar versión oficial de código abierto desde GitHub
    if [ ! -f "${dxvk_base}/x64/d3d11.dll" ]; then
        echo -e "${YELLOW}  🌐 Descargando DXVK oficial v2.6 desde GitHub...${RESET}"
        local tmp_tar="/tmp/dxvk_vessel_temp.tar.gz"
        local tmp_extract="/tmp/dxvk_vessel_extract"
        if curl -sL --connect-timeout 10 --max-time 120 "https://github.com/doitsujin/dxvk/releases/download/v2.6/dxvk-2.6.tar.gz" -o "$tmp_tar"; then
            mkdir -p "$tmp_extract"
            tar -xzf "$tmp_tar" -C "$tmp_extract" 2>/dev/null || true
            local extracted_dir
            extracted_dir=$(find "$tmp_extract" -maxdepth 1 -type d -name "dxvk-*" | head -n 1)
            if [ -d "$extracted_dir" ]; then
                cp -f "$extracted_dir/x64"/*.dll "${dxvk_base}/x64/" 2>/dev/null || true
                cp -f "$extracted_dir/x32"/*.dll "${dxvk_base}/x32/" 2>/dev/null || true
                echo -e "${GREEN}  ✓ DXVK v2.6 instalado correctamente en drivers/dxvk/${RESET}"
            fi
            rm -rf "$tmp_tar" "$tmp_extract"
        fi
    fi

    # Aplicar al prefijo de Wine activo
    if [ -d "${target_prefix}/drive_c/windows/system32" ]; then
        echo -e "${BLUE}  ⚙ Inyectando DXVK en el prefijo (${target_prefix})...${RESET}"
        for dll in d3d11 d3d10core d3d9 d3d8 dxgi; do
            if [ -f "${dxvk_base}/x64/${dll}.dll" ]; then
                ln -sf "${dxvk_base}/x64/${dll}.dll" "${target_prefix}/drive_c/windows/system32/${dll}.dll" 2>/dev/null || true
            fi
            if [ -f "${dxvk_base}/x32/${dll}.dll" ]; then
                ln -sf "${dxvk_base}/x32/${dll}.dll" "${target_prefix}/drive_c/windows/syswow64/${dll}.dll" 2>/dev/null || true
            fi
        done
    fi
}

# ==============================================================================
# 3. INSTALACIÓN Y VINCULACIÓN DE VKD3D-PROTON (DirectX 12 -> Vulkan)
# ==============================================================================
instalar_vkd3d_modular() {
    local target_prefix="${1:-${DIR}/wineprefix}"
    local vkd3d_base="${DRIVERS_DIR}/vkd3d-proton"
    mkdir -p "${vkd3d_base}/x64" "${vkd3d_base}/x32"

    echo -e "${CYAN}📦 [ DRIVERS ] Verificando librerías VKD3D-Proton (DirectX 12 -> Vulkan)...${RESET}"

    if [ ! -f "${vkd3d_base}/x64/d3d12.dll" ]; then
        echo -e "${YELLOW}  🌐 Descargando VKD3D-Proton oficial desde GitHub...${RESET}"
        local tmp_tar="/tmp/vkd3d_vessel_temp.tar.zst"
        local tmp_extract="/tmp/vkd3d_vessel_extract"
        # Intentar paquete de release oficial
        if curl -sL --connect-timeout 10 --max-time 120 "https://github.com/HansKristian-Work/vkd3d-proton/releases/download/v2.14.1/vkd3d-proton-2.14.1.tar.zst" -o "$tmp_tar"; then
            if command -v tar &>/dev/null && tar --help 2>&1 | grep -q "zstd"; then
                mkdir -p "$tmp_extract"
                tar --zstd -xf "$tmp_tar" -C "$tmp_extract" 2>/dev/null || true
                local extracted_dir
                extracted_dir=$(find "$tmp_extract" -maxdepth 1 -type d -name "vkd3d-*" | head -n 1)
                if [ -d "$extracted_dir" ]; then
                    cp -f "$extracted_dir/x64"/*.dll "${vkd3d_base}/x64/" 2>/dev/null || true
                    cp -f "$extracted_dir/x86"/*.dll "${vkd3d_base}/x32/" 2>/dev/null || true
                    echo -e "${GREEN}  ✓ VKD3D-Proton instalado correctamente en drivers/vkd3d-proton/${RESET}"
                fi
                rm -rf "$tmp_tar" "$tmp_extract"
            fi
        fi
    fi

    # Inyectar en prefijo activo
    if [ -d "${target_prefix}/drive_c/windows/system32" ]; then
        for dll in d3d12 d3d12core; do
            if [ -f "${vkd3d_base}/x64/${dll}.dll" ]; then
                ln -sf "${vkd3d_base}/x64/${dll}.dll" "${target_prefix}/drive_c/windows/system32/${dll}.dll" 2>/dev/null || true
            fi
            if [ -f "${vkd3d_base}/x32/${dll}.dll" ]; then
                ln -sf "${vkd3d_base}/x32/${dll}.dll" "${target_prefix}/drive_c/windows/syswow64/${dll}.dll" 2>/dev/null || true
            fi
        done
    fi
}

# ==============================================================================
# 4. INSTALACIÓN Y VINCULACIÓN DE DXVK-NVAPI (Puente NVIDIA GeForce Reflex/DLSS)
# ==============================================================================
instalar_nvapi_modular() {
    local target_prefix="${1:-${DIR}/wineprefix}"
    local nvapi_base="${DRIVERS_DIR}/dxvk-nvapi"
    mkdir -p "${nvapi_base}/x64" "${nvapi_base}/x32"

    echo -e "${CYAN}📦 [ DRIVERS ] Verificando DXVK-NVAPI (Puente NVIDIA GeForce)...${RESET}"

    # Copiar de caché local si existe
    if [ ! -f "${nvapi_base}/x64/nvapi64.dll" ] && [ -d "${DIR}/librerias_cache/dxvk-nvapi" ]; then
        cp -rf "${DIR}/librerias_cache/dxvk-nvapi/x64"/* "${nvapi_base}/x64/" 2>/dev/null || true
        cp -rf "${DIR}/librerias_cache/dxvk-nvapi/x32"/* "${nvapi_base}/x32/" 2>/dev/null || true
    fi

    # Si falta, descargar de GitHub
    if [ ! -f "${nvapi_base}/x64/nvapi64.dll" ]; then
        echo -e "${YELLOW}  🌐 Descargando DXVK-NVAPI oficial desde GitHub...${RESET}"
        local tmp_tar="/tmp/nvapi_vessel_temp.tar.gz"
        local tmp_extract="/tmp/nvapi_vessel_extract"
        if curl -sL --connect-timeout 10 --max-time 60 "https://github.com/jp7677/dxvk-nvapi/releases/download/v0.9.3/dxvk-nvapi-v0.9.3.tar.gz" -o "$tmp_tar"; then
            mkdir -p "$tmp_extract"
            tar -xzf "$tmp_tar" -C "$tmp_extract" 2>/dev/null || true
            local extracted_dir
            extracted_dir=$(find "$tmp_extract" -maxdepth 1 -type d -name "dxvk-nvapi-*" | head -n 1)
            if [ -d "$extracted_dir" ]; then
                cp -f "$extracted_dir/x64"/*.dll "${nvapi_base}/x64/" 2>/dev/null || true
                cp -f "$extracted_dir/x32"/*.dll "${nvapi_base}/x32/" 2>/dev/null || true
                echo -e "${GREEN}  ✓ DXVK-NVAPI v0.9.3 instalado en drivers/dxvk-nvapi/${RESET}"
            fi
            rm -rf "$tmp_tar" "$tmp_extract"
        fi
    fi

    # Inyectar en prefijo activo
    if [ -d "${target_prefix}/drive_c/windows/system32" ]; then
        if [ -f "${nvapi_base}/x64/nvapi64.dll" ]; then
            ln -sf "${nvapi_base}/x64/nvapi64.dll" "${target_prefix}/drive_c/windows/system32/nvapi64.dll" 2>/dev/null || true
        fi
        if [ -f "${nvapi_base}/x32/nvapi.dll" ]; then
            ln -sf "${nvapi_base}/x32/nvapi.dll" "${target_prefix}/drive_c/windows/syswow64/nvapi.dll" 2>/dev/null || true
        fi
    fi
}

# ==============================================================================
# 5. SINCRONIZACIÓN Y TARGETING DE PANTALLA PARA JUEGOS (eDP-1 / 1280x720)
# ==============================================================================
sincronizar_pantalla_juego() {
    local target_game="${1:-}"
    local target_dir="${2:-}"
    cargar_gpu_env

    local mon="${TARGET_MONITOR:-eDP-1}"
    local target_w="1280"
    local target_h="720"
    local target_x="1920"
    local target_y="0"

    # Si se especificó HDMI-A-1 o auto, calibrar coordenadas
    if [ "$mon" = "HDMI-A-1" ]; then
        target_w="1920"
        target_h="1080"
        target_x="0"
        target_y="0"
    elif [ -n "${FORCE_RESOLUTION:-}" ]; then
        target_w=$(echo "$FORCE_RESOLUTION" | cut -dx -f1)
        target_h=$(echo "$FORCE_RESOLUTION" | cut -dx -f2)
    fi

    export ACTIVE_MON_W="$target_w"
    export ACTIVE_MON_H="$target_h"
    export ACTIVE_MON_X="$target_x"
    export ACTIVE_MON_Y="$target_y"
    export best_w="$target_w"
    export best_h="$target_h"
    export best_res="${target_w}x${target_h}"

    # Sincronización específica para GTA V / PlayGTAV
    if [[ "$target_game" =~ [Gg][Tt][Aa]5|[Pp]lay[Gg][Tt][Aa] ]]; then
        # 1. commandline.txt
        local cmdline="${target_dir}/commandline.txt"
        if [ -f "$cmdline" ]; then
            sed -i "s/-width [0-9]*/-width ${target_w}/" "$cmdline" 2>/dev/null || true
            sed -i "s/-height [0-9]*/-height ${target_h}/" "$cmdline" 2>/dev/null || true
            grep -q -- "-windowed" "$cmdline" || echo "-windowed" >> "$cmdline"
            grep -q -- "-borderless" "$cmdline" || echo "-borderless" >> "$cmdline"
        fi

        # 2. settings.xml
        local rsg_doc="$HOME/Documentos/Rockstar Games/GTA V"
        [ ! -d "$rsg_doc" ] && rsg_doc="${WINEPREFIX:-${DIR}/wineprefix}/drive_c/users/${USER}/Documents/Rockstar Games/GTA V"
        for sxml in "$rsg_doc/settings.xml" "${target_dir}/settings.xml" "${WINEPREFIX:-${DIR}/wineprefix}/drive_c/users/${USER}/Documents/Rockstar Games/GTA V/settings.xml"; do
            if [ -f "$sxml" ]; then
                sed -i "s/<ScreenWidth value=\"[0-9]*\"/<ScreenWidth value=\"${target_w}\"/" "$sxml" 2>/dev/null || true
                sed -i "s/<ScreenHeight value=\"[0-9]*\"/<ScreenHeight value=\"${target_h}\"/" "$sxml" 2>/dev/null || true
                sed -i 's/<Windowed value="[0-9]*"/<Windowed value="2"/' "$sxml" 2>/dev/null || true
            fi
        done
    fi
}

# ==============================================================================
# 6. ESTADO GENERAL DE LOS DRIVERS
# ==============================================================================
mostrar_estado_drivers() {
    cargar_gpu_env
    echo -e "\n${BOLD}${PURPLE}========================================================================${RESET}"
    echo -e "${BOLD}${CYAN}   VESSEL - PANEL DE ESTADO DE DRIVERS Y CAPAS DE TRADUCCIÓN${RESET}"
    echo -e "${BOLD}${PURPLE}========================================================================${RESET}\n"

    echo -e "${BOLD}Configuración Activa (drivers/gpu_env.conf):${RESET}"
    echo -e "  • Pantalla Objetivo:      ${GREEN}${TARGET_MONITOR:-eDP-1}${RESET} (${FORCE_RESOLUTION:-1280x720})"
    echo -e "  • GPU Forzada:            ${GREEN}${DXVK_DEVICE_FILTER:-NVIDIA}${RESET} (PRIME Offload al 100%)"
    echo -e "  • Vulkan GPL (Anti-stutter): ${GREEN}$([ "${ENABLE_VULKAN_GPL:-1}" = "1" ] && echo "Activo (Caché dinámica)" || echo "Desactivado")${RESET}"
    echo -e "  • Hilos de CPU Compilador: ${GREEN}${CPU_COMPILER_THREADS:-8} Hilos${RESET}\n"

    echo -e "${BOLD}Librerías de Código Abierto Instaladas en drivers/:${RESET}"
    # DXVK
    if [ -f "${DRIVERS_DIR}/dxvk/x64/d3d11.dll" ]; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}DXVK (D3D8/9/10/11 -> Vulkan):${RESET} Instalado y Listo"
    else
        echo -e "  [${YELLOW}○${RESET}] ${BOLD}DXVK:${RESET} No encontrado localmente (se usará del sistema o descarga automática)"
    fi

    # VKD3D-Proton
    if [ -f "${DRIVERS_DIR}/vkd3d-proton/x64/d3d12.dll" ]; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}VKD3D-Proton (D3D12 -> Vulkan):${RESET} Instalado y Listo"
    else
        echo -e "  [${YELLOW}○${RESET}] ${BOLD}VKD3D-Proton:${RESET} Disponible para descarga bajo demanda"
    fi

    # DXVK-NVAPI
    if [ -f "${DRIVERS_DIR}/dxvk-nvapi/x64/nvapi64.dll" ]; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}DXVK-NVAPI (NVIDIA Reflex / DLSS Bridge):${RESET} Instalado y Listo"
    else
        echo -e "  [${YELLOW}○${RESET}] ${BOLD}DXVK-NVAPI:${RESET} No encontrado localmente"
    fi

    echo -e "\n${BOLD}${PURPLE}========================================================================${RESET}\n"
}

# ==============================================================================
# 7. EJECUCIÓN DIRECTA O PARÁMETROS
# ==============================================================================
case "${1:-}" in
    cargar_env)
        cargar_gpu_env
        ;;
    instalar_todo)
        cargar_gpu_env
        instalar_dxvk_modular "${2:-${DIR}/wineprefix}"
        instalar_vkd3d_modular "${2:-${DIR}/wineprefix}"
        instalar_nvapi_modular "${2:-${DIR}/wineprefix}"
        ;;
    sincronizar)
        sincronizar_pantalla_juego "${2:-}" "${3:-}"
        ;;
    estado)
        mostrar_estado_drivers
        ;;
    *)
        mostrar_estado_drivers
        ;;
esac
