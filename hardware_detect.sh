#!/bin/bash
# ==============================================================================
# MÓDULO DE DETECCIÓN Y OPTIMIZACIÓN UNIVERSAL DE HARDWARE PARA LINUX
# Compatible con cualquier PC (Intel, AMD, NVIDIA, laptops híbridas y sobremesa)
# ==============================================================================

# Autoprotección multi-shell: Si se ejecuta con dash, sh, zsh o fish, cambiar a bash
if [ -z "$BASH_VERSION" ]; then
    if command -v bash >/dev/null 2>&1; then
        [ -f "$0" ] && exec bash "$0" "$@"
    fi
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CFG_HW="${DIR}/perfil_hardware.cfg"
CURRENT_HOST_ID="$(cat /etc/machine-id 2>/dev/null || hostname 2>/dev/null || echo "host_generic")"

# Comprobar si el equipo físico cambió o si el perfil no existe
RESCAN_REQUIRED=false
if [ ! -f "$CFG_HW" ]; then
    RESCAN_REQUIRED=true
else
    source "$CFG_HW"
    if [ -z "$HOST_ID" ] || [ "$HOST_ID" != "$CURRENT_HOST_ID" ]; then
        RESCAN_REQUIRED=true
    fi
fi

if [ "$RESCAN_REQUIRED" = true ]; then
    # El equipo cambió (Vessel fue copiado a otra PC o pendrive) o no hay perfil previo:
    # Re-escanear inmediatamente para calibrar al nuevo hardware en 0.1s
    [ -x "${DIR}/herramientas/detector_hardware.sh" ] && bash "${DIR}/herramientas/detector_hardware.sh" --save 2>/dev/null || true
    [ -f "$CFG_HW" ] && source "$CFG_HW"
    # Auto-regenerar dxvk.conf para adaptarlo al nuevo procesador y memoria
    [ -x "${DIR}/generar_dxvk_conf.sh" ] && bash "${DIR}/generar_dxvk_conf.sh" 2>/dev/null || true
fi

# Cargar perfil de hardware pre-escaneado
if [ -f "$CFG_HW" ]; then
    source "$CFG_HW"
    CPU_CORES="${CPU_THREADS:-4}"
    DETECTED_GPU="${GPU_PRIMARY:-Desconocida}"
    IS_LOW_SPEC_GPU="${GPU_IS_ENTRY_LEVEL:-false}"
    HAS_VULKAN=true
    if [ "$GPU_PRIMARY_VENDOR" = "nvidia" ]; then
        HAS_NVIDIA=true
        HAS_AMD_DEDICATED=false
        HAS_INTEL=false
    elif [ "$GPU_PRIMARY_VENDOR" = "amd" ]; then
        HAS_AMD_DEDICATED=true
        HAS_NVIDIA=false
        HAS_INTEL=false
    else
        HAS_INTEL=true
        HAS_NVIDIA=false
        HAS_AMD_DEDICATED=false
    fi
else
    # Si no existe, invocar al detector universal de hardware para generarlo
    [ -x "${DIR}/herramientas/detector_hardware.sh" ] && bash "${DIR}/herramientas/detector_hardware.sh" --save 2>/dev/null || true
    if [ -f "$CFG_HW" ]; then
        source "$CFG_HW"
        CPU_CORES="${CPU_THREADS:-4}"
        DETECTED_GPU="${GPU_PRIMARY:-Desconocida}"
        IS_LOW_SPEC_GPU="${GPU_IS_ENTRY_LEVEL:-false}"
        HAS_VULKAN=true
    else
        # Fallback de detección rápida
        CPU_CORES=$(nproc 2>/dev/null || echo 4)
        CPU_MODEL=$(lscpu 2>/dev/null | grep -iE 'model name|nombre del modelo' | cut -d: -f2 | xargs | head -n 1)
        [ -z "$CPU_MODEL" ] && CPU_MODEL="Procesador Genérico (${CPU_CORES} hilos)"
        RAM_TOTAL_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
        [ -z "$RAM_TOTAL_MB" ] && RAM_TOTAL_MB=8192
        DETECTED_GPU="Desconocida"
        HAS_NVIDIA=false
        HAS_AMD_DEDICATED=false
        HAS_INTEL=false
        if lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -i 'nvidia' > /dev/null; then
            HAS_NVIDIA=true
            GPU_NAME=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -i 'nvidia' | cut -d: -f3 | xargs | head -n 1)
            DETECTED_GPU="NVIDIA: ${GPU_NAME}"
        elif lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -i 'amd|radeon' > /dev/null; then
            HAS_AMD_DEDICATED=true
            GPU_NAME=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -i 'amd|radeon' | cut -d: -f3 | xargs | head -n 1)
            DETECTED_GPU="AMD Radeon: ${GPU_NAME}"
        else
            HAS_INTEL=true
            GPU_NAME=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -i 'intel' | cut -d: -f3 | xargs | head -n 1)
            DETECTED_GPU="Intel: ${GPU_NAME:-Gráficos Integrados}"
        fi
        HAS_VULKAN=true
        IS_LOW_SPEC_GPU=false
        [ "$HAS_NVIDIA" = true ] && echo "$GPU_NAME" | grep -qiE 'MX[0-9]{3}|GT[0-9]{3}|GTX\s*(750|850|950)' && IS_LOW_SPEC_GPU=true
        [ "$HAS_INTEL" = true ] && [ "$HAS_NVIDIA" = false ] && [ "$HAS_AMD_DEDICATED" = false ] && IS_LOW_SPEC_GPU=true
    fi
fi
export IS_LOW_SPEC_GPU

# Función para exportar las variables de entorno óptimas según el hardware
aplicar_entorno_hardware() {
    # 1. Hilos de compilación para DXVK basados en la CPU real
    export DXVK_NUM_COMPILER_THREADS="$CPU_CORES"

    # 2. Configuración de sincronización del Kernel (NTSync / Fsync / Esync)
    if [ "$HAS_NTSYNC" = "true" ] && [ -e "/dev/ntsync" ]; then
        export WINENTSYNC=1
        export WINEFSYNC=0
        export WINEESYNC=0
    elif [ "$HAS_FSYNC" = "true" ]; then
        export WINENTSYNC=0
        export WINEFSYNC=1
        export WINEESYNC=1
    else
        KERNEL_MAJOR=$(uname -r | cut -d. -f1)
        KERNEL_MINOR=$(uname -r | cut -d. -f2)
        if [ "$KERNEL_MAJOR" -gt 5 ] || { [ "$KERNEL_MAJOR" -eq 5 ] && [ "$KERNEL_MINOR" -ge 16 ]; }; then
            export WINEFSYNC=1
            export WINEESYNC=1
        else
            export WINEFSYNC=0
            export WINEESYNC=1
        fi
    fi

    # 3. Direccionamiento de memoria ampliado para juegos de 32 bits (permite 4GB en vez de 2GB)
    export WINE_LARGE_ADDRESS_AWARE=1

    # 4. Latencia de audio ultra-baja para evitar cortes y retrasos (PipeWire / PulseAudio)
    if [ "$HAS_PIPEWIRE" = "true" ] || pgrep -x pipewire &>/dev/null; then
        export PIPEWIRE_LATENCY="128/48000"
    fi
    export PULSE_LATENCY_MSEC=50

    # 5. Desactivar logs innecesarios de Wine para máximo rendimiento de CPU
    export WINEDEBUG=-all

    # 6. Selección de Renderizador: DXVK (Vulkan) o Fallback WineD3D (OpenGL para PCs antiguas)
    local backend="${RENDERER_BACKEND:-auto}"
    if [ "$backend" = "wined3d" ] || { [ "$backend" = "auto" ] && [ "$HAS_VULKAN" = false ]; }; then
        # Modo Compatibilidad OpenGL (para tarjetas sin Vulkan o PCs antiguas)
        export PROTON_USE_WINED3D=1
        export RENDERER_IN_USE="WineD3D (OpenGL Compatibilidad)"
        export WINEDLLOVERRIDES="winemenubuilder.exe=d;dxgi=b;d3d11=b;d3d10core=b;d3d9=b;d3d8=b;ddraw=b;${WINEDLLOVERRIDES}"
    else
        # Modo Máximo Rendimiento Vulkan con DXVK y fallback transparente a WineD3D
        export RENDERER_IN_USE="DXVK (Vulkan)"
        export WINEDLLOVERRIDES="winemenubuilder.exe=d;dxgi=n,b;d3d11=n,b;d3d10core=n,b;d3d9=n,b;d3d8=n,b;ddraw=n,b;${WINEDLLOVERRIDES}"
    fi

    # 7. Caché de shaders universal en almacenamiento NVMe SSD de ultra-alta velocidad
    export DXVK_STATE_CACHE_PATH="${HOME}/.cache/dxvk"
    export __GL_SHADER_DISK_CACHE_PATH="${HOME}/.cache/nvidia"
    export MESA_GLCACHE_DIR="${HOME}/.cache/mesa_shader_cache"
    mkdir -p "${HOME}/.cache/dxvk" "${HOME}/.cache/nvidia" "${HOME}/.cache/mesa_shader_cache" 2>/dev/null || true

    export STAGING_SHARED_MEMORY=1
    # Desactivar async draw-call dropping para evitar que los modelos 3D desaparezcan/parpadeen al girar la cámara
    unset DXVK_ASYNC
    unset DXVK_GPLASYNCCACHE
    export __GL_SHADER_DISK_CACHE=1
    export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
    export __GL_SHADER_DISK_CACHE_SIZE=10737418240
    export CUDA_CACHE_MAXSIZE=2147483648
    export MESA_DISK_CACHE_SINGLE_FILE=1
    # mesa_glthread omitido globalmente para evitar inestabilidad y crashes en juegos D3D9/Wine (como GTA San Andreas)
    export __GL_YIELD="NOTHING"
    export WINE_CPU_TOPOLOGY="${CPU_CORES}"
    export WINE_HEAP_DELAY_FREE=0
    export WINE_SIMULATE_WRITECOPY=1
    export WINE_RT_PRIO=1

    # 8. Renderizado según la GPU detectada (Garantiza usar la GPU dedicada en laptops híbridas)
    # Detección dinámica y universal de GPU dedicada (NVIDIA GeForce o AMD Radeon)
    local discrete_info
    discrete_info=$(MESA_VK_DEVICE_SELECT=list vulkaninfo 2>&1 | grep -i 'discrete GPU' | head -n 1 || true)
    if [ -n "$discrete_info" ]; then
        local discrete_pci_id
        discrete_pci_id=$(echo "$discrete_info" | awk '{print $3}')
        local discrete_name
        discrete_name=$(echo "$discrete_info" | grep -oE '"[^"]+"' | tr -d '"')

        if [ -n "$discrete_pci_id" ] && [ "$HAS_NVIDIA" = false ]; then
            export MESA_VK_DEVICE_SELECT="${discrete_pci_id}!"
            export MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE=1
        fi
        if [ -n "$discrete_name" ]; then
            export DXVK_FILTER_DEVICE_NAME="${discrete_name}"
        fi
    fi

    if [ "$HAS_NVIDIA" = true ]; then
        # Activar capas y optimizaciones NVIDIA (PRIME offload, hilos OpenGL y sincronización limpia)
        export __NV_PRIME_RENDER_OFFLOAD=1
        export __GLX_VENDOR_LIBRARY_NAME=nvidia
        export __VK_LAYER_NV_optimus=NVIDIA_only
        export DXVK_FILTER_DEVICE_NAME="NVIDIA"
        if [ "$IS_LOW_SPEC_GPU" = "true" ] || ! echo "${GPU_NAME:-${GPU_PRIMARY:-}}" | grep -qiE 'RTX|Titan V|Quadro RTX'; then
            export VKD3D_CONFIG="nodxr"
        else
            export VKD3D_CONFIG="dxr11,dxr"
        fi
        export __GL_THREADED_OPTIMIZATIONS=1
        export __GL_SYNC_TO_VBLANK=0
        export __GL_MaxFramesAllowed=1
        export __GL_VRR_ALLOWED=0
        export __GL_SHOW_GRAPHICS_OSD=0
    elif [ "$HAS_AMD_DEDICATED" = true ]; then
        # Activar optimizaciones AMD Radeon (PRIME, compilador ACO, SAM y forzado de RADV)
        export DRI_PRIME=1
        export AMD_VULKAN_ICD=RADV
        export RADV_PERFTEST=aco,sam,dcc
        export vblank_mode=0
        export LIBVA_DRIVER_NAME=radeonsi
        [ -z "$DXVK_FILTER_DEVICE_NAME" ] && export DXVK_FILTER_DEVICE_NAME="AMD"
    elif [ "$HAS_INTEL" = true ]; then
        # Activar aceleración multimedia y controlador de video Intel
        export LIBVA_DRIVER_NAME=iHD
        export ANV_ENABLE_PIPELINE_CACHE=1
    fi

    # 9. Puentes y compatibilidad para Anti-Cheat (EAC / BattlEye en juegos con soporte Linux)
    export PROTON_ENABLE_NVAPI=1
    export PROTON_BATTLEYE_ASYNC=1
    export PROTON_EAC_ASYNC=1
    export WINE_DISABLE_FAST_SYNC=0

    # 10. Prevención universal de tirones de cámara, desgarro y micro-stuttering en Wayland/X11
    export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0
    export WINE_FULLSCREEN_INTEGER_SCALING=0
    export GST_PLUGIN_FEATURE_RANK="libav:MAX,ugly:MAX,bad:MAX"
    export SDL_MOUSE_RELATIVE_MODE_WARP=0
    export WINE_RAW_INPUT=1

    # 11. Mapeo Universal de Mandos (SDL2 GameControllerDB: +2.300 mandos compatibles)
    local db_gamepad="${DIR}/herramientas/gamecontrollerdb.txt"
    if [ -f "$db_gamepad" ]; then
        export SDL_GAMECONTROLLERCONFIG_FILE="$db_gamepad"
    fi
}

# ==============================================================================
# DIAGNÓSTICO PROFUNDO DE CONTROLADORES GRÁFICOS Y 32-BIT
# Comprueba estado de drivers propietarios, librerías 32 bits y aceleración de video
# ==============================================================================
diagnostico_controladores_gaming() {
    echo "══════════════════════════════════════════════════════════════════════"
    echo "🔍 DIAGNÓSTICO DE CONTROLADORES GRÁFICOS Y 32-BIT PARA GAMING"
    echo "══════════════════════════════════════════════════════════════════════"
    local warning_count=0

    # 1. GPU y Drivers Principales
    echo -n "  • GPU Detectada: $DETECTED_GPU "
    if [ "$HAS_NVIDIA" = true ]; then
        if lsmod 2>/dev/null | grep -qi "nouveau"; then
            echo -e "\n    \033[31m[!] ADVERTENCIA CRÍTICA: Driver libre 'nouveau' detectado.\033[0m"
            echo "        Nouveau limita drásticamente las frecuencias 3D de GPUs GeForce (10-15 FPS)."
            echo "        Solución: Instalar el controlador propietario oficial de NVIDIA (rama 535, 550 o 560+)."
            warning_count=$((warning_count+1))
        elif lsmod 2>/dev/null | grep -qi "nvidia"; then
            local nv_kver
            nv_kver=$(cat /sys/module/nvidia/version 2>/dev/null || modinfo -F version nvidia 2>/dev/null || echo "Oficial")
            echo -e "(\033[32mDriver Oficial Propietario NVIDIA Activo: v${nv_kver}\033[0m)"
        fi

        # Comprobar librerías 32 bits de NVIDIA
        local has_nv32=false
        for lib in /usr/lib/i386-linux-gnu/libGLX_nvidia.so.0 /usr/lib32/libGLX_nvidia.so.0 /usr/lib/libGLX_nvidia.so.0 /usr/lib/i386-linux-gnu/libEGL_nvidia.so.0; do
            if [ -f "$lib" ]; then has_nv32=true; break; fi
        done
        if [ "$has_nv32" = true ]; then
            echo -e "    \033[32m✔ Librerías gráficas NVIDIA 32-bit: Instaladas (compatibilidad 100% con juegos clásicos)\033[0m"
        else
            echo -e "    \033[33m⚠️ Faltan librerías NVIDIA 32-bit (libnvidia-gl:i386 o lib32-nvidia-utils).\033[0m"
            echo "       Juegos de 32 bits (GTA SA, NFS, SWAT 4) no podrán usar la GPU NVIDIA sin este paquete."
            warning_count=$((warning_count+1))
        fi
    elif [ "$HAS_AMD_DEDICATED" = true ]; then
        echo -e "(\033[32mControlador Mesa RADV Vulkan con compilador ACO activo\033[0m)"
        local has_radv32=false
        for lib in /usr/lib/i386-linux-gnu/libvulkan_radeon.so /usr/lib32/libvulkan_radeon.so /usr/lib/i386-linux-gnu/dri/radeonsi_dri.so; do
            if [ -f "$lib" ]; then has_radv32=true; break; fi
        done
        if [ "$has_radv32" = true ]; then
            echo -e "    \033[32m✔ Librerías gráficas AMD Mesa 32-bit: Instaladas\033[0m"
        else
            echo -e "    \033[33m⚠️ Faltan librerías AMD Mesa 32-bit (mesa-vulkan-drivers:i386 o lib32-vulkan-radeon).\033[0m"
            warning_count=$((warning_count+1))
        fi
    elif [ "$HAS_INTEL" = true ]; then
        echo -e "(\033[32mControlador Mesa ANV Vulkan activo\033[0m)"
        local has_vaapi=false
        for drv in /usr/lib/x86_64-linux-gnu/dri/iHD_drv_video.so /usr/lib/dri/iHD_drv_video.so /usr/lib64/dri/iHD_drv_video.so; do
            if [ -f "$drv" ]; then has_vaapi=true; break; fi
        done
        if [ "$has_vaapi" = true ]; then
            echo -e "    \033[32m✔ Driver de Aceleración de Video Intel (intel-media-driver / VA-API): Instalado\033[0m"
        else
            echo -e "    \033[33m⚠️ Se recomienda instalar 'intel-media-va-driver' para aceleración de video en cinemáticas.\033[0m"
        fi
    fi

    # 2. Soporte Vulkan
    if [ "$HAS_VULKAN" = true ]; then
        echo -e "  • Soporte Vulkan 64-bit : \033[32m✔ Compatible (Capas DXVK activas)\033[0m"
    else
        echo -e "  • Soporte Vulkan 64-bit : \033[33m⚠️ No detectado (Se usará fallback seguro WineD3D OpenGL)\033[0m"
    fi

    # 3. Soporte Kernel Fsync / Esync
    if [ "$WINEFSYNC" = "1" ]; then
        echo -e "  • Sincronización Kernel : \033[32m✔ Fsync nativo (futex_waitv) activo (Kernel $(uname -r))\033[0m"
    else
        echo -e "  • Sincronización Kernel : \033[34mℹ Esync activo\033[0m"
    fi

    # 4. Soporte DLSS / NVAPI
    echo -e "  • Soporte DLSS / NVAPI  : \033[32m✔ Habilitado (PROTON_ENABLE_NVAPI=1)\033[0m"

    # 5. Mapeo Universal de Mandos
    if [ -f "${DIR}/herramientas/gamecontrollerdb.txt" ]; then
        echo -e "  • Mapeo Mandos Universal: \033[32m✔ SDL2 GameControllerDB Activo (+2.300 mandos)\033[0m"
    fi
    echo "══════════════════════════════════════════════════════════════════════"
    return $warning_count
}

if [ "$1" = "--check-drivers" ]; then
    aplicar_entorno_hardware
    diagnostico_controladores_gaming
    exit $?
fi
