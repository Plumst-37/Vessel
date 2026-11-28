#!/bin/bash
# ==============================================================================
# VESSEL - GESTOR MODULAR DE CONTROLADORES Y TRADUCTORES GRÁFICOS (OPEN-SOURCE)
# DXVK (D3D8-11), VKD3D-Proton (D3D12), DXVK-NVAPI, Mesa Zink y Optimizaciones
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

    # Soporte Mesa Zink (Traductor oficial OpenGL -> Vulkan)
    case "${OPENGL_TRANSLATION:-auto}" in
        zink)
            export MESA_LOADER_DRIVER_OVERRIDE=zink
            export GALLIUM_DRIVER=zink
            ;;
        native)
            unset MESA_LOADER_DRIVER_OVERRIDE 2>/dev/null || true
            unset GALLIUM_DRIVER 2>/dev/null || true
            ;;
        auto|*)
            # Modo automático: se mantiene el driver nativo con aceleración por defecto
            ;;
    esac

    # Topología de CPU y compilación en segundo plano (100% de núcleos e hilos)
    local num_threads="${CPU_COMPILER_THREADS:-auto}"
    if [ "$num_threads" = "auto" ] || [ -z "$num_threads" ]; then
        local detected_threads
        detected_threads=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
        export DXVK_NUM_COMPILER_THREADS="$detected_threads"
    else
        export DXVK_NUM_COMPILER_THREADS="$num_threads"
    fi

    # Selección Dinámica de GPU Dedicada / Híbrida (NVIDIA / AMD / Intel Arc)
    local force_ded="${GPU_FORCE_DEDICATED:-auto}"
    if [ "$force_ded" = "auto" ] || [ "$force_ded" = "1" ]; then
        local has_nvidia=0
        local has_amd=0
        local has_intel_arc=0
        local is_hybrid=0

        # Contar adaptadores gráficos sin invocar lspci 5 veces (usa datos cacheados o sysfs)
        local drm_cards=0
        for _card in /sys/class/drm/card[0-9]; do
            [ -d "$_card" ] && drm_cards=$((drm_cards + 1))
        done
        [ "$drm_cards" -gt 1 ] && is_hybrid=1

        if [ "${VESSEL_HW_LOADED:-0}" = "1" ]; then
            [ "${HAS_NVIDIA:-false}" = true ] || [ -d "/proc/driver/nvidia" ] && has_nvidia=1
            [ "${HAS_AMD_DEDICATED:-false}" = true ] && has_amd=1
            if [ "${HAS_INTEL:-false}" = true ] && echo "${DETECTED_GPU:-}" | grep -qiE "arc|dg[1-2]|alchemist|battlemage"; then
                has_intel_arc=1
            fi
        else
            local lspci_vga
            lspci_vga=$(lspci 2>/dev/null | grep -Ei "vga|3d controller|display" || true)
            local vga_count
            vga_count=$(echo "$lspci_vga" | grep -c . || true)
            [ "$vga_count" -gt 1 ] && is_hybrid=1
            if echo "$lspci_vga" | grep -qi "nvidia" || [ -d "/proc/driver/nvidia" ]; then
                has_nvidia=1
            fi
            if echo "$lspci_vga" | grep -qiE "amd|radeon|advanced micro devices"; then
                has_amd=1
            fi
            if echo "$lspci_vga" | grep -qi "intel" && echo "$lspci_vga" | grep -qiE "arc|dg[1-2]|alchemist|battlemage"; then
                has_intel_arc=1
            fi
        fi

        # Inyectar variables de alto rendimiento si se forzó o si es sistema híbrido
        if [ "$force_ded" = "1" ] || [ "$is_hybrid" -eq 1 ]; then
            if [ "$has_nvidia" -eq 1 ]; then
                export __NV_PRIME_RENDER_OFFLOAD=1
                export __GLX_VENDOR_LIBRARY_NAME=nvidia
                export __VK_LAYER_NV_optimus=NVIDIA_only
                if [ -n "${DXVK_DEVICE_FILTER:-}" ] && [ "${DXVK_DEVICE_FILTER}" != "auto" ]; then
                    export DXVK_FILTER_DEVICE_NAME="${DXVK_DEVICE_FILTER}"
                fi
            elif [ "$has_amd" -eq 1 ]; then
                export DRI_PRIME=1
                export AMD_VULKAN_ICD=RADV
                export RADV_PERFTEST=gpl,sam
                if [ -n "${DXVK_DEVICE_FILTER:-}" ] && [ "${DXVK_DEVICE_FILTER}" != "auto" ]; then
                    export DXVK_FILTER_DEVICE_NAME="${DXVK_DEVICE_FILTER}"
                fi
            elif [ "$has_intel_arc" -eq 1 ]; then
                export DRI_PRIME=1
                export ANV_QUEUE_THREAD_DISABLE=0
                if [ -n "${DXVK_DEVICE_FILTER:-}" ] && [ "${DXVK_DEVICE_FILTER}" != "auto" ]; then
                    export DXVK_FILTER_DEVICE_NAME="${DXVK_DEVICE_FILTER}"
                fi
            fi
        fi
    fi

    # Filtro específico en capa Mesa si el usuario lo configuró explícitamente
    if [ -n "${MESA_DEVICE_SELECT_OVERRIDE:-}" ] && [ "${MESA_DEVICE_SELECT_OVERRIDE}" != "auto" ]; then
        export MESA_VK_DEVICE_SELECT="${MESA_DEVICE_SELECT_OVERRIDE}"
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
        if curl -fsSL -k --retry 3 --connect-timeout 10 --max-time 120 "https://github.com/doitsujin/dxvk/releases/download/v2.6/dxvk-2.6.tar.gz" -o "$tmp_tar"; then
            if [ -s "$tmp_tar" ]; then
                mkdir -p "$tmp_extract"
                tar -xzf "$tmp_tar" -C "$tmp_extract" 2>/dev/null || true
                local extracted_dir
                extracted_dir=$(find "$tmp_extract" -maxdepth 1 -type d -name "dxvk-*" | head -n 1)
                if [ -d "$extracted_dir" ]; then
                    cp -f "$extracted_dir/x64"/*.dll "${dxvk_base}/x64/" 2>/dev/null || true
                    cp -f "$extracted_dir/x32"/*.dll "${dxvk_base}/x32/" 2>/dev/null || true
                    echo -e "${GREEN}  ✓ DXVK v2.6 instalado correctamente en drivers/dxvk/${RESET}"
                fi
                rm -rf "$tmp_extract"
            fi
            rm -f "$tmp_tar"
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
        local dl_ok=0
        if curl -fsSL -k --retry 3 --connect-timeout 10 --max-time 120 "https://github.com/HansKristian-Work/vkd3d-proton/releases/download/v2.14.1/vkd3d-proton-2.14.1.tar.zst" -o "$tmp_tar"; then
            if [ -s "$tmp_tar" ]; then
                mkdir -p "$tmp_extract"
                if command -v tar &>/dev/null && tar --help 2>&1 | grep -q -- "--zstd"; then
                    tar --zstd -xf "$tmp_tar" -C "$tmp_extract" 2>/dev/null && dl_ok=1
                elif command -v zstd >/dev/null 2>&1; then
                    zstd -dc "$tmp_tar" | tar -xf - -C "$tmp_extract" 2>/dev/null && dl_ok=1
                else
                    echo -e "${RED}  ✗ No se puede descomprimir .tar.zst: falta la utilidad zstd en el sistema.${RESET}"
                    echo -e "${YELLOW}  👉 Instala zstd con: sudo apt install zstd (Debian/Ubuntu) o sudo pacman -S zstd (Arch)${RESET}"
                fi

                if [ "$dl_ok" -eq 1 ]; then
                    local extracted_dir
                    extracted_dir=$(find "$tmp_extract" -maxdepth 1 -type d -name "vkd3d-*" | head -n 1)
                    if [ -d "$extracted_dir" ]; then
                        cp -f "$extracted_dir/x64"/*.dll "${vkd3d_base}/x64/" 2>/dev/null || true
                        cp -f "$extracted_dir/x86"/*.dll "${vkd3d_base}/x32/" 2>/dev/null || true
                        echo -e "${GREEN}  ✓ VKD3D-Proton instalado correctamente en drivers/vkd3d-proton/${RESET}"
                    fi
                fi
                rm -rf "$tmp_extract"
            fi
            rm -f "$tmp_tar"
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
        if curl -fsSL -k --retry 3 --connect-timeout 10 --max-time 60 "https://github.com/jp7677/dxvk-nvapi/releases/download/v0.9.3/dxvk-nvapi-v0.9.3.tar.gz" -o "$tmp_tar"; then
            if [ -s "$tmp_tar" ]; then
                mkdir -p "$tmp_extract"
                tar -xzf "$tmp_tar" -C "$tmp_extract" 2>/dev/null || true
                if [ -d "$tmp_extract/x64" ]; then
                    cp -f "$tmp_extract/x64"/*.dll "${nvapi_base}/x64/" 2>/dev/null || true
                    cp -f "$tmp_extract/x32"/*.dll "${nvapi_base}/x32/" 2>/dev/null || true
                    echo -e "${GREEN}  ✓ DXVK-NVAPI v0.9.3 instalado en drivers/dxvk-nvapi/${RESET}"
                else
                    local extracted_dir
                    extracted_dir=$(find "$tmp_extract" -maxdepth 1 -type d -name "dxvk-nvapi-*" | head -n 1)
                    if [ -d "$extracted_dir" ]; then
                        cp -f "$extracted_dir/x64"/*.dll "${nvapi_base}/x64/" 2>/dev/null || true
                        cp -f "$extracted_dir/x32"/*.dll "${nvapi_base}/x32/" 2>/dev/null || true
                        echo -e "${GREEN}  ✓ DXVK-NVAPI v0.9.3 instalado en drivers/dxvk-nvapi/${RESET}"
                    fi
                fi
                rm -rf "$tmp_extract"
            fi
            rm -f "$tmp_tar"
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
# 5. CONFIGURACIÓN PROFUNDA DE COMPATIBILIDAD WINDOWS 10 22H2 (SERVICIOS, MMCSS, DLLS)
# ==============================================================================
configurar_compatibilidad_windows10() {
    local target_prefix="${1:-${DIR}/wineprefix}"
    if [ -f "${target_prefix}/.vessel_win_full_v4" ]; then
        return 0
    fi
    echo -e "${CYAN}🪟 [ WINDOWS 10 ] Calibrando compatibilidad profunda Windows 10 Pro 22H2...${RESET}"

    if [ ! -d "$target_prefix" ]; then
        mkdir -p "${target_prefix}/drive_c/windows/system32" "${target_prefix}/drive_c/windows/syswow64" 2>/dev/null || true
    fi

    # Determinar binario de Wine
    local wine_bin="wine"
    if [ -x "${DIR}/wine/bin/wine" ]; then
        wine_bin="${DIR}/wine/bin/wine"
    elif command -v wine >/dev/null 2>&1; then
        wine_bin="$(command -v wine)"
    fi

    # 1. Detección de VRAM para Direct3D
    local vram_mb=""
    if command -v nvidia-smi &>/dev/null; then
        vram_mb=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1)
    fi
    if [ -z "$vram_mb" ]; then
        for f in /sys/class/drm/card*/device/mem_info_vram_total; do
            if [ -f "$f" ]; then
                local b
                b=$(cat "$f" 2>/dev/null)
                if [ -n "$b" ] && [ "$b" -gt 0 ]; then
                    vram_mb=$((b / 1048576))
                    break
                fi
            fi
        done
    fi
    if [ -z "$vram_mb" ] && command -v glxinfo &>/dev/null; then
        vram_mb=$(glxinfo -B 2>/dev/null | grep -iE "video memory|total available memory" | head -n 1 | grep -oE "[0-9]+" | head -n 1)
    fi
    if [ -z "$vram_mb" ]; then
        local ram_sys
        ram_sys=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
        if [ "${ram_sys:-0}" -ge 12000 ]; then vram_mb=4096; elif [ "${ram_sys:-0}" -ge 6000 ]; then vram_mb=2048; else vram_mb=1024; fi
    fi
    [ -z "$vram_mb" ] && vram_mb=2048

    # 2. Generar archivo de registro completo
    local reg_win10
    reg_win10=$(mktemp "${TMPDIR:-/tmp}/vessel_win10_XXXXXX.reg" 2>/dev/null || echo "/tmp/vessel_win10_$$.reg")
    cat << EOF > "$reg_win10"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Wine]
"Version"="win10"

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion]
"ProductName"="Windows 10 Pro"
"CurrentBuild"="19045"
"CurrentBuildNumber"="19045"
"ReleaseId"="22H2"
"DisplayVersion"="22H2"
"BuildBranch"="vb_release"
"BuildLab"="19041.vb_release.191206-1406"
"BuildLabEx"="19041.1.amd64fre.vb_release.191206-1406"
"CurrentMajorVersionNumber"=dword:0000000a
"CurrentMinorVersionNumber"=dword:00000000
"CurrentVersion"="6.3"
"UBR"=dword:00000ef2
"EditionID"="Professional"
"InstallationType"="Client"
"CompositionVersion"="10.0.19045.3826"
"CSDVersion"=""
"PathName"="C:\\Windows"
"SystemRoot"="C:\\Windows"
"ProgramFilesDir"="C:\\Program Files"
"ProgramFilesDir (x86)"="C:\\Program Files (x86)"
"CommonFilesDir"="C:\\Program Files\\Common Files"
"CommonFilesDir (x86)"="C:\\Program Files (x86)\\Common Files"

[HKEY_LOCAL_MACHINE\Software\WOW6432Node\Microsoft\Windows NT\CurrentVersion]
"ProductName"="Windows 10 Pro"
"CurrentBuild"="19045"
"CurrentBuildNumber"="19045"
"ReleaseId"="22H2"
"DisplayVersion"="22H2"
"BuildBranch"="vb_release"
"BuildLab"="19041.vb_release.191206-1406"
"BuildLabEx"="19041.1.amd64fre.vb_release.191206-1406"
"CurrentMajorVersionNumber"=dword:0000000a
"CurrentMinorVersionNumber"=dword:00000000
"CurrentVersion"="6.3"
"UBR"=dword:00000ef2
"EditionID"="Professional"
"InstallationType"="Client"
"CompositionVersion"="10.0.19045.3826"
"CSDVersion"=""
"PathName"="C:\\Windows"
"SystemRoot"="C:\\Windows"
"ProgramFilesDir"="C:\\Program Files"
"ProgramFilesDir (x86)"="C:\\Program Files (x86)"
"CommonFilesDir"="C:\\Program Files\\Common Files"
"CommonFilesDir (x86)"="C:\\Program Files (x86)\\Common Files"

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Windows]
"CSDVersion"=dword:00000000

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\ProductOptions]
"ProductType"="WinNT"

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile]
"SystemResponsiveness"=dword:00000000
"NetworkThrottlingIndex"=dword:ffffffff
"NoLazyMode"=dword:00000001
"AlwaysOn"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games]
"Affinity"=dword:00000000
"Background Only"="False"
"Clock Rate"=dword:00002710
"GPU Priority"=dword:00000008
"Priority"=dword:00000006
"Scheduling Category"="High"
"SFIO Priority"="High"
"Latency Sensitive"="True"

[HKEY_CURRENT_USER\System\GameConfigStore]
"GameDVR_Enabled"=dword:00000000
"GameDVR_FSEBehaviorMode"=dword:00000002
"GameDVR_HonorUserFSEBehaviorMode"=dword:00000001
"GameDVR_DXGIHonorFSEWindowsCompatible"=dword:00000001
"GameDVR_EFSEFeatureFlags"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\GameDVR]
"AllowGameDVR"=dword:00000000

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management]
"LargeSystemCache"=dword:00000001
"DisablePagingExecutive"=dword:00000001

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\AudioEndpointBuilder]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Audiosrv]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\winebus]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\mountmgr]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\RpcSs]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\PlugPlay]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\CryptSvc]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\NlaSvc]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet]
"EnableActiveProbing"=dword:00000001
"ActiveWebProbeHost"="www.msftncsi.com"
"ActiveWebProbePath"="ncsi.txt"
"ActiveWebProbeContent"="Microsoft NCSI"
"ActiveDnsProbeHost"="dns.msftncsi.com"
"ActiveDnsProbeContent"="131.107.255.255"

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Tcpip]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\BFE]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Dnscache]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\EventLog]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\FontCache]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\LanmanWorkstation]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\DirectDraw]
"EmulationOnly"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Direct3D\Drivers]
"UsePrecompiledShaders"=dword:00000001

[HKEY_CURRENT_USER\Software\Wine\Direct3D]
"VideoMemorySize"="${vram_mb}"
"StrictDrawOrdering"="disabled"
"AlwaysOffscreen"="enabled"
"OffscreenRenderingMode"="fbo"
"Multisampling"="enabled"
"CheckFloatConstants"="disabled"
"CheckDepthStencil"="disabled"
"DirectDrawRenderer"="opengl"
"ShaderBackend"="glsl"
"csmt"=dword:00000001
"MaxVersionGL"=dword:00040006

[HKEY_CURRENT_USER\Software\Wine\X11 Driver]
"UseXVidMode"="N"
"GrabPointer"="Y"
"UseTakeFocus"="N"

[HKEY_CURRENT_USER\Software\Wine\Direct2D]
"max_version_factory"=dword:00000001

[HKEY_CURRENT_USER\Control Panel\Desktop]
"FontSmoothing"="2"
"FontSmoothingType"=dword:00000002
"FontSmoothingGamma"=dword:00000578
"FontSmoothingOrientation"=dword:00000001

[HKEY_CURRENT_USER\Software\Wine\Fonts\Replacements]
"Segoe UI"="Liberation Sans"
"Calibri"="Liberation Sans"
"Arial"="Liberation Sans"
"Times New Roman"="Liberation Serif"
"Courier New"="Liberation Mono"
"Consolas"="Liberation Mono"
"Tahoma"="Liberation Sans"
"MS Sans Serif"="Liberation Sans"

[HKEY_CURRENT_USER\Software\Wine\DirectInput]
"MouseWarpOverride"="enable"

[HKEY_CURRENT_USER\Software\Wine\WineDbg]
"ShowCrashDialog"=dword:00000000

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\AeDebug]
"Auto"="0"

[HKEY_CURRENT_USER\Software\Wine\Drivers]
"Audio"="pulse"

[HKEY_CURRENT_USER\Software\Wine\DllOverrides]
"d3d11"="native,builtin"
"dxgi"="native,builtin"
"d3d12"="native,builtin"
"d3d12core"="native,builtin"
"d3d10core"="native,builtin"
"d3d9"="native,builtin"
"d3d8"="native,builtin"
"nvapi"="native,builtin"
"nvapi64"="native,builtin"
"d3dcompiler_47"="native,builtin"
"d3dcompiler_46"="native,builtin"
"d3dcompiler_43"="native,builtin"
"d3dx11_43"="native,builtin"
"d3dx10_43"="native,builtin"
"d3dx9_43"="native,builtin"
"vcruntime140"="native,builtin"
"vcruntime140_1"="native,builtin"
"msvcp140"="native,builtin"
"msvcp140_1"="native,builtin"
"msvcp140_2"="native,builtin"
"msvcp140_codecvt_ids"="native,builtin"
"msvcp140_atomic_wait"="native,builtin"
"concrt140"="native,builtin"
"vcomp140"="native,builtin"
"ucrtbase"="native,builtin"
"xinput1_4"="native,builtin"
"xinput1_3"="native,builtin"
"xinput9_1_0"="native,builtin"
"dinput8"="native,builtin"
"riched20"="native,builtin"
"riched32"="native,builtin"
"msftedit"="native,builtin"
"msxml3"="native,builtin"
"msxml4"="native,builtin"
"msxml6"="native,builtin"
"gdiplus"="native,builtin"
"windowscodecs"="native,builtin"
"mscms"="native,builtin"
"actxprxy"="native,builtin"
"wbemprox"="native,builtin"
"wbemdisp"="native,builtin"
"wmiutils"="native,builtin"
"schannel"="native,builtin"
"crypt32"="native,builtin"
"secur32"="native,builtin"
"wininet"="native,builtin"
"urlmon"="native,builtin"
"dwrite"="native,builtin"
"mfplat"="native,builtin"
"mf"="native,builtin"
"mfreadwrite"="native,builtin"
"evr"="native,builtin"
"quartz"="builtin,native"
"devenum"="builtin,native"
"qedit"="builtin,native"
"wmasf"="native,builtin"
"wmvcore"="native,builtin"
"winegstreamer"="builtin"
"xaudio2_7"="builtin"
"xaudio2_8"="builtin"
"xaudio2_9"="builtin"
"x3daudio1_7"="builtin"
"openal32"="native,builtin"
"dmusic"="native,builtin"
"dmsynth"="native,builtin"
"dmime"="native,builtin"
"dmloader"="native,builtin"
"dmband"="native,builtin"
EOF

    if command -v "$wine_bin" >/dev/null 2>&1 && [ -d "${target_prefix}" ]; then
        WINEPREFIX="${target_prefix}" WINEDEBUG="-all" DISPLAY="" "$wine_bin" regedit /s "$reg_win10" >/dev/null 2>&1 || true
        touch "${target_prefix}/.vessel_win_full_v4" 2>/dev/null || true
        echo -e "${GREEN}  ✓ Registro de Windows 10 22H2, servicios de sistema y DllOverrides aplicados.${RESET}"
    fi
    rm -f "$reg_win10" 2>/dev/null || true
}

# ==============================================================================
# 5. SINCRONIZACIÓN MODULAR DE PERFILES ESPECÍFICOS DE JUEGO (GTA V, etc.)
# ==============================================================================
sincronizar_perfil_especifico_juego() {
    local target_game="${1:-}"
    local target_dir="${2:-}"
    local target_w="${3:-1920}"
    local target_h="${4:-1080}"
    local is_forced_res="${5:-0}"

    # Sincronización para Grand Theft Auto V / PlayGTAV
    if [[ "$target_game" =~ [Gg][Tt][Aa]5|[Pp]lay[Gg][Tt][Aa] ]]; then
        # 1. commandline.txt
        local cmdline="${target_dir}/commandline.txt"
        if [ -f "$cmdline" ]; then
            if grep -qi -- "-width" "$cmdline"; then
                sed -i "s/-width [0-9]*/-width ${target_w}/I" "$cmdline" 2>/dev/null || true
            else
                echo "-width ${target_w}" >> "$cmdline"
            fi
            if grep -qi -- "-height" "$cmdline"; then
                sed -i "s/-height [0-9]*/-height ${target_h}/I" "$cmdline" 2>/dev/null || true
            else
                echo "-height ${target_h}" >> "$cmdline"
            fi
            grep -qi -- "-windowed" "$cmdline" 2>/dev/null || echo "-windowed" >> "$cmdline"
            grep -qi -- "-borderless" "$cmdline" 2>/dev/null || echo "-borderless" >> "$cmdline"
            grep -qi -- "-nopause" "$cmdline" 2>/dev/null || echo "-nopause" >> "$cmdline"
            grep -qi -- "-disallowResizeWindow" "$cmdline" 2>/dev/null || echo "-disallowResizeWindow" >> "$cmdline"
            grep -qi -- "-norestrictions" "$cmdline" 2>/dev/null || echo "-norestrictions" >> "$cmdline"
            grep -qi -- "-nomemrestrict" "$cmdline" 2>/dev/null || echo "-nomemrestrict" >> "$cmdline"
            # Eliminar directiva -DX10 obsoleta que causa corrupción de color y artefactos en Vulkan
            sed -i "/-DX10/Id; /-dx10/Id" "$cmdline" 2>/dev/null || true
        fi

        # 2. settings.xml
        local rsg_doc="$HOME/Documentos/Rockstar Games/GTA V"
        [ ! -d "$rsg_doc" ] && rsg_doc="${WINEPREFIX:-${DIR}/wineprefix}/drive_c/users/${USER}/Documents/Rockstar Games/GTA V"
        for sxml in "$rsg_doc/settings.xml" "${target_dir}/settings.xml" "${WINEPREFIX:-${DIR}/wineprefix}/drive_c/users/${USER}/Documents/Rockstar Games/GTA V/settings.xml"; do
            if [ -f "$sxml" ]; then
                sed -i "s/<ScreenWidth value=\"[0-9]*\"/<ScreenWidth value=\"${target_w}\"/" "$sxml" 2>/dev/null || true
                sed -i "s/<ScreenHeight value=\"[0-9]*\"/<ScreenHeight value=\"${target_h}\"/" "$sxml" 2>/dev/null || true
                sed -i 's/<Windowed value="[0-9]*"/<Windowed value="2"/' "$sxml" 2>/dev/null || true
                # Forzar DirectX 11 (value="2") para eliminar colores psicodélicos causados por el backend DX10
                sed -i 's/<DX_Version value="[0-1]"/<DX_Version value="2"/' "$sxml" 2>/dev/null || true
                # Blindaje geométrico 3D: curar valores de LOD negativos que deforman modelos y rompen mallas
                sed -i 's/<LodScale value="-[0-9\.]*"/<LodScale value="0.800000"/' "$sxml" 2>/dev/null || true
                sed -i 's/<MaxLodScale value="0.000000"/<MaxLodScale value="1.000000"/' "$sxml" 2>/dev/null || true
                sed -i 's/<PedLodBias value="-[0-9\.]*"/<PedLodBias value="0.500000"/' "$sxml" 2>/dev/null || true
                sed -i 's/<VehicleLodBias value="-[0-9\.]*"/<VehicleLodBias value="0.500000"/' "$sxml" 2>/dev/null || true
                sed -i 's/<Tessellation value="[1-9]"/<Tessellation value="0"/' "$sxml" 2>/dev/null || true
                sed -i 's/<MSAA value="[1-9]"/<MSAA value="0"/' "$sxml" 2>/dev/null || true
                sed -i 's/<TXAA_Enabled value="true"/<TXAA_Enabled value="false"/' "$sxml" 2>/dev/null || true
                sed -i 's/<FXAA_Enabled value="false"/<FXAA_Enabled value="true"/' "$sxml" 2>/dev/null || true
                sed -i 's/<DoF value="true"/<DoF value="false"/' "$sxml" 2>/dev/null || true
                sed -i 's/<InGameDepthOfField value="true"/<InGameDepthOfField value="false"/' "$sxml" 2>/dev/null || true
                sed -i 's/<MotionBlurStrength value="[0-9\.]*"/<MotionBlurStrength value="0.000000"/' "$sxml" 2>/dev/null || true
                sed -i 's/<Lighting_FogVolumes value="true"/<Lighting_FogVolumes value="false"/' "$sxml" 2>/dev/null || true
                sed -i 's/<PauseOnFocusLoss value="[1-9]"/<PauseOnFocusLoss value="0"/' "$sxml" 2>/dev/null || true
                sed -i 's/<Audio3d value="[a-zA-Z]*"/<Audio3d value="false"/' "$sxml" 2>/dev/null || true
            fi
        done
    fi
}

# ==============================================================================
# 6. DETECCIÓN DINÁMICA DE PANTALLA Y GEOMETRÍA UNIVERSAL
# ==============================================================================
sincronizar_pantalla_juego() {
    local target_game="${1:-}"
    local target_dir="${2:-}"
    cargar_gpu_env

    local mon_req="${TARGET_MONITOR:-auto}"
    local target_w=1920
    local target_h=1080
    local target_x=0
    local target_y=0
    local is_forced_res=0

    # 1. Detección dinámica de monitor y geometría con xrandr
    if command -v xrandr >/dev/null 2>&1; then
        local mon_line=""
        if [ "$mon_req" != "auto" ] && [ -n "$mon_req" ]; then
            # Buscar el monitor específico solicitado por el usuario
            mon_line=$(xrandr --current 2>/dev/null | grep -E "^${mon_req} connected" | head -n 1)
        fi

        # Si mon_req es "auto" o el monitor solicitado no fue encontrado
        if [ -z "$mon_line" ]; then
            mon_line=$(xrandr --current 2>/dev/null | grep -E " connected primary [0-9]+x[0-9]+" | head -n 1)
            [ -z "$mon_line" ] && mon_line=$(xrandr --current 2>/dev/null | grep -E " connected [0-9]+x[0-9]+" | head -n 1)
        fi

        if [ -n "$mon_line" ]; then
            local geom
            geom=$(echo "$mon_line" | grep -oE "[0-9]+x[0-9]+\+[0-9]+\+[0-9]+" | head -n 1)
            if [ -n "$geom" ]; then
                target_w=$(echo "$geom" | cut -dx -f1)
                target_h=$(echo "$geom" | cut -dx -f2 | cut -d+ -f1)
                target_x=$(echo "$geom" | cut -d+ -f2)
                target_y=$(echo "$geom" | cut -d+ -f3)
            fi
        fi
    elif [ -f "/sys/class/drm/*/modes" ]; then
        # Fallback a sysfs de DRM
        local raw_res
        raw_res=$(head -n 1 /sys/class/drm/*/modes 2>/dev/null | head -n 1)
        if [ -n "$raw_res" ]; then
            target_w=$(echo "$raw_res" | cut -dx -f1)
            target_h=$(echo "$raw_res" | cut -dx -f2)
        fi
    fi

    # 2. Resolución Forzada si el usuario la fijó expresamente
    if [ -n "${FORCE_RESOLUTION:-}" ] && [ "${FORCE_RESOLUTION}" != "auto" ]; then
        target_w=$(echo "$FORCE_RESOLUTION" | cut -dx -f1)
        target_h=$(echo "$FORCE_RESOLUTION" | cut -dx -f2)
        is_forced_res=1
    fi

    export ACTIVE_MON_W="$target_w"
    export ACTIVE_MON_H="$target_h"
    export ACTIVE_MON_X="$target_x"
    export ACTIVE_MON_Y="$target_y"
    export best_w="$target_w"
    export best_h="$target_h"
    export best_res="${target_w}x${target_h}"

    # 3. Aplicar perfil específico de juego desacoplado
    sincronizar_perfil_especifico_juego "$target_game" "$target_dir" "$target_w" "$target_h" "$is_forced_res"
}

# ==============================================================================
# 7. ESTADO GENERAL DE LOS DRIVERS Y CAPAS DE TRADUCCIÓN
# ==============================================================================
mostrar_estado_drivers() {
    cargar_gpu_env
    echo -e "\n${BOLD}${PURPLE}========================================================================${RESET}"
    echo -e "${BOLD}${CYAN}   VESSEL - PANEL DE ESTADO DE DRIVERS Y CAPAS DE TRADUCCIÓN${RESET}"
    echo -e "${BOLD}${PURPLE}========================================================================${RESET}\n"

    # Detección en caliente del monitor actual
    local active_mon_name="Desconocido"
    local active_geom="1920x1080"
    if command -v xrandr >/dev/null 2>&1; then
        local ml
        ml=$(xrandr --current 2>/dev/null | grep -E " connected primary [0-9]+x[0-9]+" | head -n 1)
        [ -z "$ml" ] && ml=$(xrandr --current 2>/dev/null | grep -E " connected [0-9]+x[0-9]+" | head -n 1)
        if [ -n "$ml" ]; then
            active_mon_name=$(echo "$ml" | awk '{print $1}')
            active_geom=$(echo "$ml" | grep -oE "[0-9]+x[0-9]+\+[0-9]+\+[0-9]+" | head -n 1)
        fi
    fi

    echo -e "${BOLD}Configuración de Hardware y Entorno (drivers/gpu_env.conf):${RESET}"
    echo -e "  • Monitor Activo / Objetivo:  ${GREEN}${active_mon_name}${RESET} [Configurado: ${TARGET_MONITOR:-auto}]"
    echo -e "  • Resolución Nativa / Forzada: ${GREEN}${active_geom}${RESET} [Configurado: ${FORCE_RESOLUTION:-auto}]"
    
    # GPU y Offload
    local gpu_summary="Auto-detección"
    if [ "${__NV_PRIME_RENDER_OFFLOAD:-0}" = "1" ]; then
        gpu_summary="NVIDIA GeForce (PRIME Offload Activo)"
    elif [ "${DRI_PRIME:-0}" = "1" ]; then
        gpu_summary="AMD Radeon / Intel Arc (DRI_PRIME Activo)"
    elif [ "${GPU_FORCE_DEDICATED:-auto}" = "0" ]; then
        gpu_summary="GPU Integrada (Bajo Consumo)"
    fi
    echo -e "  • GPU Seleccionada:           ${GREEN}${gpu_summary}${RESET}"

    # Zink
    local zink_info="Desactivado (Nativo)"
    if [ "${MESA_LOADER_DRIVER_OVERRIDE:-}" = "zink" ] || [ "${GALLIUM_DRIVER:-}" = "zink" ]; then
        zink_info="Mesa Zink (OpenGL sobre Vulkan ACTIVO)"
    fi
    echo -e "  • Traducción OpenGL:          ${GREEN}${zink_info}${RESET} [Configurado: ${OPENGL_TRANSLATION:-auto}]"

    # Vulkan GPL y Hilos de CPU
    echo -e "  • Vulkan GPL (Anti-stutter):  ${GREEN}$([ "${ENABLE_VULKAN_GPL:-1}" = "1" ] && echo "Activo (Caché dinámica)" || echo "Desactivado")${RESET}"
    echo -e "  • Hilos de CPU Compilador:    ${GREEN}${DXVK_NUM_COMPILER_THREADS:-$(nproc 2>/dev/null || echo 4)} Hilos${RESET} (100% de CPU física)\n"

    echo -e "${BOLD}Librerías de Código Abierto Instaladas en drivers/:${RESET}"
    # DXVK
    if [ -f "${DRIVERS_DIR}/dxvk/x64/d3d11.dll" ]; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}DXVK (D3D8/9/10/11 -> Vulkan):${RESET} Instalado y Listo"
    else
        echo -e "  [${YELLOW}○${RESET}] ${BOLD}DXVK:${RESET} No encontrado localmente (se usará del sistema o descarga bajo demanda)"
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

    # Compatibilidad Windows 10
    local win10_status="${YELLOW}○ Pendiente de calibrar${RESET}"
    if [ -f "${DIR}/wineprefix/.vessel_win_full_v4" ] || [ -f "${DIR}/wineprefix/.vessel_win_full_v3" ]; then
        win10_status="${GREEN}✓ Windows 10 Pro 22H2 (Build 19045.3826) | MMCSS y Servicios Core Activos${RESET}"
    fi
    echo -e "  • Compatibilidad Windows 10:  ${win10_status}"
    echo -e "  • Acelerador Turbo Hardware:  ${GREEN}$([ "${ENABLE_CPU_TURBO:-1}" = "1" ] && echo "Activo (CPU/GPU Clocks Máximos en Vivo)" || echo "Estándar")${RESET}"
    echo -e "  • Transparent Huge Pages THP: ${GREEN}$([ "${ENABLE_THP:-1}" = "1" ] && echo "Activo (Cero tirones de caché TLB)" || echo "Desactivado")${RESET}"

    echo -e "\n${BOLD}${PURPLE}========================================================================${RESET}\n"
}

# ==============================================================================
# 8. EJECUCIÓN DIRECTA O PARÁMETROS
# ==============================================================================
case "${1:-}" in
    cargar_env)
        cargar_gpu_env
        ;;
    optimizar_win10)
        configurar_compatibilidad_windows10 "${2:-${DIR}/wineprefix}"
        ;;
    instalar_todo)
        cargar_gpu_env
        instalar_dxvk_modular "${2:-${DIR}/wineprefix}"
        instalar_vkd3d_modular "${2:-${DIR}/wineprefix}"
        instalar_nvapi_modular "${2:-${DIR}/wineprefix}"
        configurar_compatibilidad_windows10 "${2:-${DIR}/wineprefix}"
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
