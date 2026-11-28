#!/bin/bash
# ==============================================================================
# GENERADOR DINÁMICO UNIVERSAL DE CONFIGURACIÓN DXVK
# Optimizado para cualquier arquitectura: Intel, AMD Radeon y NVIDIA
# ==============================================================================

# Autoprotección multi-shell: Si se ejecuta con dash, sh, zsh o fish, cambiar inmediatamente a bash
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

CORE_DIR="${DIR}/core"
[ ! -d "$CORE_DIR" ] && CORE_DIR="${DIR}"

CONFIG_DIR="${DIR}/config"
[ ! -d "$CONFIG_DIR" ] && CONFIG_DIR="${DIR}"
mkdir -p "$CONFIG_DIR" 2>/dev/null || true

CONF_FILE="${CONFIG_DIR}/dxvk.conf"
DRIVERS_DXVK_CONF="${DIR}/drivers/dxvk/dxvk.conf"

CONFIG_USER="${CONFIG_DIR}/config_rendimiento.cfg"
[ ! -f "$CONFIG_USER" ] && CONFIG_USER="${DIR}/config_rendimiento.cfg"

# Cargar preferencias
[ -f "$CONFIG_USER" ] && source "$CONFIG_USER"

# Si las variables de hardware ya fueron cargadas y exportadas por el lanzador, evitar re-ejecutar hardware_detect.sh
if [ -z "${RAM_TOTAL_MB:-}" ] && [ -z "${HAS_NVIDIA:-}" ]; then
    if [ -f "${CORE_DIR}/hardware_detect.sh" ]; then
        source "${CORE_DIR}/hardware_detect.sh"
    elif [ -f "${DIR}/hardware_detect.sh" ]; then
        source "${DIR}/hardware_detect.sh"
    fi
fi

# Cargar gpu_env.conf si existe
if [ -f "${DIR}/drivers/gpu_env.conf" ]; then
    source "${DIR}/drivers/gpu_env.conf"
fi

# Calibración de recursos reales de hardware
NPROCS=$(nproc 2>/dev/null || echo "${CPU_CORES:-4}")
if [ "$NPROCS" -gt 8 ]; then
    REAL_THREADS=$((NPROCS / 2))
    [ "$REAL_THREADS" -gt 8 ] && REAL_THREADS=8
elif [ "$NPROCS" -gt 4 ]; then
    REAL_THREADS=3
elif [ "$NPROCS" -gt 2 ]; then
    REAL_THREADS=$((NPROCS - 1))
else
    REAL_THREADS=1
fi
if [ -n "${CPU_COMPILER_THREADS:-}" ] && [ "${CPU_COMPILER_THREADS}" != "auto" ]; then
    REAL_THREADS="${CPU_COMPILER_THREADS}"
fi

REAL_D3D9_MEM="2048"
if [ -n "$RAM_TOTAL_MB" ]; then
    if [ "$RAM_TOTAL_MB" -le 4608 ]; then
        REAL_D3D9_MEM="1024"
    elif [ "$RAM_TOTAL_MB" -gt 13312 ]; then
        REAL_D3D9_MEM="4096"
    fi
fi

REAL_DXGI_MEM="0"
if [ "${GPU_VRAM_MB:-0}" -gt 0 ] && [ "${GPU_VRAM_MB:-0}" -le 2048 ]; then
    REAL_DXGI_MEM="1800"
    REAL_D3D9_MEM="1800"
fi

REAL_CHUNK_SIZE="64"
if [ "${GPU_VRAM_MB:-0}" -le 2048 ]; then
    REAL_CHUNK_SIZE="32"
elif [ "${GPU_VRAM_MB:-0}" -gt 4096 ]; then
    REAL_CHUNK_SIZE="128"
fi

if [ -f "$DRIVERS_DXVK_CONF" ] && [ -s "$DRIVERS_DXVK_CONF" ]; then
    # Procesar configuración modular preservando ediciones del usuario e inyectando valores dinámicos
    cp -f "$DRIVERS_DXVK_CONF" "$CONF_FILE" 2>/dev/null || true
    if grep -qE "=\s*auto" "$CONF_FILE" 2>/dev/null; then
        sed -i "s/dxvk.numCompilerThreads\s*=\s*auto/dxvk.numCompilerThreads = ${REAL_THREADS}/" "$CONF_FILE" 2>/dev/null || true
        sed -i "s/dxgi.maxDeviceMemory\s*=\s*auto/dxgi.maxDeviceMemory = ${REAL_DXGI_MEM}/" "$CONF_FILE" 2>/dev/null || true
        sed -i "s/d3d9.maxAvailableMemory\s*=\s*auto/d3d9.maxAvailableMemory = ${REAL_D3D9_MEM}/" "$CONF_FILE" 2>/dev/null || true
        sed -i "s/dxvk.maxChunkSize\s*=\s*auto/dxvk.maxChunkSize = ${REAL_CHUNK_SIZE}/" "$CONF_FILE" 2>/dev/null || true
    fi
    exit 0
fi

# Definir límite de FPS
FPS_VAL="0"
case "$LIMITE_FPS" in
    30) FPS_VAL="30" ;;
    60) FPS_VAL="60" ;;
    120) FPS_VAL="120" ;;
    *) FPS_VAL="0" ;;
esac

# Calibración de sincronización y latencia (VSync desactivado por defecto para >60 FPS)
VSYNC_ENABLED="${VSYNC_MODE:-0}"
if [ "$VSYNC_ENABLED" = "0" ]; then
    TEAR_FREE="False"
    SYNC_INT="0"
    NUM_BUFFERS="2"
    FRAME_LATENCY="1"
else
    TEAR_FREE="False"
    SYNC_INT="1"
    NUM_BUFFERS="3"
    FRAME_LATENCY="2"
fi

# Calibración de hilos de compilación según la arquitectura del procesador
if [ "${CPU_CORES:-4}" -le 2 ]; then
    DXVK_COMPILER_THREADS=1
elif [ "${CPU_CORES:-4}" -le 4 ]; then
    DXVK_COMPILER_THREADS=3
elif [ "${CPU_CORES:-4}" -le 8 ]; then
    DXVK_COMPILER_THREADS="${CPU_CORES:-4}"
elif [ "${CPU_CORES:-4}" -le 16 ]; then
    DXVK_COMPILER_THREADS=$((CPU_CORES - 2))
else
    DXVK_COMPILER_THREADS=16
fi

# Calibración multiescala según la Gama de Hardware (Baja, Media, Alta, Extrema)
case "${VESSEL_HARDWARE_TIER:-baja}" in
    baja)
        MAX_CHUNK_SIZE="32"
        SHRINK_HEAPS="True"
        ALLOW_OVERCOMMIT="True"
        SAMPLER_ANISO="8"
        [ "${RAM_TOTAL_MB:-8192}" -le 4608 ] && SAMPLER_ANISO="4"
        MAX_TESSELLATION="16"
        [ "$VSYNC_ENABLED" = "1" ] && FRAME_LATENCY="1" && NUM_BUFFERS="2"
        ;;
    media)
        MAX_CHUNK_SIZE="64"
        if [ "${GPU_VRAM_MB:-0}" -le 4096 ]; then
            SHRINK_HEAPS="True"
        else
            SHRINK_HEAPS="False"
        fi
        ALLOW_OVERCOMMIT="True"
        SAMPLER_ANISO="16"
        MAX_TESSELLATION="32"
        [ "$VSYNC_ENABLED" = "1" ] && FRAME_LATENCY="2" && NUM_BUFFERS="3"
        ;;
    alta|extrema)
        MAX_CHUNK_SIZE="128"
        SHRINK_HEAPS="False"
        ALLOW_OVERCOMMIT="False"
        SAMPLER_ANISO="16"
        MAX_TESSELLATION="0"
        [ "$VSYNC_ENABLED" = "1" ] && FRAME_LATENCY="2" && NUM_BUFFERS="3"
        ;;
    *)
        MAX_CHUNK_SIZE="64"
        SHRINK_HEAPS="True"
        ALLOW_OVERCOMMIT="True"
        SAMPLER_ANISO="8"
        MAX_TESSELLATION="16"
        ;;
esac

# Soporte adaptativo para Graphics Pipeline Library (GPL)
if [ "${HAS_VULKAN_GPL:-false}" = "true" ]; then
    GPL_VAL="True"
else
    GPL_VAL="False"
fi

# Calibración de memoria según RAM y límite estricto de VRAM en GPUs <= 2048 MB
D3D9_MEM="2048"
if [ -n "$RAM_TOTAL_MB" ]; then
    if [ "$RAM_TOTAL_MB" -le 4608 ]; then
        D3D9_MEM="1024"
    elif [ "$RAM_TOTAL_MB" -gt 13312 ]; then
        D3D9_MEM="4096"
    fi
fi
DXGI_MEM="0"
if [ "${GPU_VRAM_MB:-0}" -gt 0 ] && [ "${GPU_VRAM_MB:-0}" -le 2048 ]; then
    DXGI_MEM="1800"
    D3D9_MEM="1800"
fi

# Ocultar GPU integrada SOLO si coexiste con una GPU dedicada real (NVIDIA o AMD dedicada)
# Si la PC solo tiene gráficos integrados (Intel HD/UHD o AMD APU), DEBE ser False para no dejar al sistema sin GPU
if { [ "${HAS_NVIDIA:-false}" = "true" ] || [ "${HAS_AMD_DEDICATED:-false}" = "true" ]; } && { [ "${HAS_INTEL:-false}" = "true" ] || [ "${HAS_AMD_INTEGRATED:-false}" = "true" ]; }; then
    HIDE_IGPU="True"
else
    HIDE_IGPU="False"
fi

# Generar archivo dxvk.conf universal
cat <<EOF > "$CONF_FILE"
# ==============================================================================
# DXVK CONFIGURACIÓN UNIVERSAL GENERADA AUTOMÁTICAMENTE
# CPU: ${CPU_MODEL} (${CPU_CORES} Hilos) | RAM: ${RAM_TOTAL_MB} MB
# Gama Detectada: ${VESSEL_HARDWARE_TIER^^} | Perfil: ${PERFIL_RENDIMIENTO:-maximo}
# ==============================================================================

# Compilación de Shaders en paralelo con hilos óptimos de CPU
dxvk.numCompilerThreads = ${DXVK_COMPILER_THREADS}

# Control de Tasa de Refresco / FPS (D3D9 y D3D11/DXGI)
dxgi.maxFrameRate = ${FPS_VAL}
d3d9.maxFrameRate = ${FPS_VAL}

# Reducción drástica de tirones y stuttering (GPL adaptativo y State Cache universal)
dxvk.enableAsync = False
dxvk.gpl = ${GPL_VAL}
dxvk.enableGraphicsPipelineLibrary = ${GPL_VAL}
dxvk.enableStateCache = True

# Modo Pantalla Completa: False para compatibilidad universal (evita fallos de EDID/swapchains en Wayland/PRIME)
dxvk.allowFse = False

# Ocultar GPU integrada (solo en sistemas híbridos con GPU dedicada activa)
dxvk.hideIntegratedGraphics = ${HIDE_IGPU}

# No ocultar GPU de fabricante real
dxgi.hideNvidiaGpu = False
dxgi.hideAmdGpu = False
dxgi.hideIntelGpu = False

# Precisión geométrica universal con máxima fidelidad 3D (elimina deformación de mallas, estiramientos y z-fighting)
d3d9.invariantPosition = True
d3d11.invariantPosition = True
d3d9.floatEmulation = Strict
d3d11.floatEmulation = Strict
d3d9.clampNegativeLodBias = True
d3d11.clampNegativeLodBias = True
d3d9.samplerAnisotropy = ${SAMPLER_ANISO}
d3d11.samplerAnisotropy = ${SAMPLER_ANISO}
d3d11.constantBufferRangeCheck = True
d3d11.relaxedBarriers = False
d3d11.relaxedGraphicsBarriers = False
d3d9.lenientClear = True
dxgi.maxDeviceMemory = ${DXGI_MEM}
d3d9.maxAvailableMemory = ${D3D9_MEM}

# Presentación y latencia de fotogramas (Adaptado dinámicamente)
dxvk.tearFree = ${TEAR_FREE}
dxgi.syncInterval = ${SYNC_INT}
d3d9.presentInterval = ${SYNC_INT}
dxgi.numBackBuffers = ${NUM_BUFFERS}
d3d9.numBackBuffers = ${NUM_BUFFERS}
d3d9.maxFrameLatency = ${FRAME_LATENCY}
dxgi.maxFrameLatency = ${FRAME_LATENCY}

# Optimizaciones de pipelines DXVK y memoria (Control adaptativo de RAM y VRAM)
dxvk.trackPipelineLifetime = False
dxvk.maxChunkSize = ${MAX_CHUNK_SIZE}
dxvk.shrinkImageHeaps = ${SHRINK_HEAPS}
dxvk.allowMemoryOvercommit = ${ALLOW_OVERCOMMIT}
dxvk.zeroMappedMemory = True
dxvk.enableMemoryDefrag = True
d3d11.maxTessFactor = ${MAX_TESSELLATION}
d3d9.memoryTrackTest = False
dxvk.enableNvapi = True
dxvk.enableNvRawAccessChains = True
dxvk.enableNvLowLatency2 = Auto

# Perfiles específicos por ejecutable para máxima fidelidad 3D, estabilidad y rendimiento
[GTA5.exe]
dxgi.maxFrameLatency = 1
dxgi.hideNvidiaGpu = False
d3d11.disableMsaa = True
d3d11.clampNegativeLodBias = True
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
d3d11.floatEmulation = Strict
d3d11.relaxedBarriers = False
d3d11.relaxedGraphicsBarriers = False
d3d11.samplerAnisotropy = ${SAMPLER_ANISO}
dxvk.shrinkImageHeaps = ${SHRINK_HEAPS}
dxvk.allowMemoryOvercommit = ${ALLOW_OVERCOMMIT}
dxvk.zeroMappedMemory = True
dxvk.enableMemoryDefrag = True
d3d11.maxTessFactor = ${MAX_TESSELLATION}
dxvk.gpl = ${GPL_VAL}
dxvk.allowFse = False
dxvk.tearFree = ${TEAR_FREE}
dxgi.syncInterval = ${SYNC_INT}

[PlayGTAV.exe]
dxgi.maxFrameLatency = 1
dxgi.hideNvidiaGpu = False
d3d11.disableMsaa = True
d3d11.clampNegativeLodBias = True
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
d3d11.floatEmulation = Strict
d3d11.relaxedBarriers = False
d3d11.relaxedGraphicsBarriers = False
d3d11.samplerAnisotropy = ${SAMPLER_ANISO}
dxvk.shrinkImageHeaps = ${SHRINK_HEAPS}
dxvk.allowMemoryOvercommit = ${ALLOW_OVERCOMMIT}
dxvk.zeroMappedMemory = True
dxvk.enableMemoryDefrag = True
d3d11.maxTessFactor = ${MAX_TESSELLATION}
dxvk.gpl = ${GPL_VAL}
dxvk.allowFse = False
dxvk.tearFree = ${TEAR_FREE}
dxgi.syncInterval = ${SYNC_INT}

[speed.exe]
d3d9.invariantPosition = True
d3d9.floatEmulation = Strict
d3d9.clampNegativeLodBias = True
d3d9.samplerAnisotropy = ${SAMPLER_ANISO}
d3d9.presentInterval = ${SYNC_INT}
dxvk.tearFree = ${TEAR_FREE}
dxvk.allowFse = False

[BH6.exe]
d3d9.invariantPosition = True
d3d9.floatEmulation = Strict
d3d9.clampNegativeLodBias = True
d3d9.samplerAnisotropy = ${SAMPLER_ANISO}
d3d9.lenientClear = True
d3d9.presentInterval = ${SYNC_INT}
dxvk.tearFree = ${TEAR_FREE}
dxvk.allowFse = False

[re4.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = ${SYNC_INT}
dxgi.maxFrameLatency = 2
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
d3d11.relaxedBarriers = False
dxvk.allowFse = False
dxvk.tearFree = ${TEAR_FREE}
dxvk.gpl = True

[re4_original.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = ${SYNC_INT}
dxgi.maxFrameLatency = 2
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
d3d11.relaxedBarriers = False
dxvk.allowFse = False
dxvk.tearFree = ${TEAR_FREE}
dxvk.gpl = True

[re2.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = ${SYNC_INT}
dxgi.maxFrameLatency = 2
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
d3d11.relaxedBarriers = False
dxvk.allowFse = False
dxvk.tearFree = ${TEAR_FREE}
dxvk.gpl = True

[re3.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = ${SYNC_INT}
dxgi.maxFrameLatency = 2
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
d3d11.relaxedBarriers = False
dxvk.allowFse = False
dxvk.tearFree = ${TEAR_FREE}
dxvk.gpl = True

[re7.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = ${SYNC_INT}
dxgi.maxFrameLatency = 2
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
d3d11.relaxedBarriers = False
dxvk.allowFse = False
dxvk.tearFree = ${TEAR_FREE}
dxvk.gpl = True

[re8.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = ${SYNC_INT}
dxgi.maxFrameLatency = 2
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
d3d11.relaxedBarriers = False
dxvk.allowFse = False
dxvk.tearFree = ${TEAR_FREE}
dxvk.gpl = True

[dmc5.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = ${SYNC_INT}
dxgi.maxFrameLatency = 2
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
d3d11.relaxedBarriers = False
dxvk.allowFse = False
dxvk.tearFree = ${TEAR_FREE}
dxvk.gpl = True

[gta_sa.exe]
d3d9.invariantPosition = True
d3d9.floatEmulation = Strict
d3d9.clampNegativeLodBias = True
d3d9.samplerAnisotropy = ${SAMPLER_ANISO}
d3d9.presentInterval = ${SYNC_INT}
dxvk.tearFree = ${TEAR_FREE}
dxvk.allowFse = False

[Swat4.exe]
d3d9.invariantPosition = True
d3d9.floatEmulation = Strict
d3d9.clampNegativeLodBias = True
d3d9.samplerAnisotropy = ${SAMPLER_ANISO}
d3d9.presentInterval = ${SYNC_INT}
dxvk.tearFree = ${TEAR_FREE}
dxvk.allowFse = False

# GameRanger: cliente de lobby 2D / chat con Chromium CEF y ANGLE
# Evita fallos de swapchains Vulkan (VK_ERROR_OUT_OF_HOST_MEMORY) en subventanas de CEF
[GameRanger.exe]
dxvk.tearFree = ${TEAR_FREE}
dxgi.syncInterval = ${SYNC_INT}
dxgi.deferSurfaceCreation = True
dxgi.numBackBuffers = 1
d3d9.numBackBuffers = 1
dxvk.allowFse = False
d3d11.maxTessFactor = 1

[GameRangerSetup.exe]
dxvk.tearFree = ${TEAR_FREE}
dxgi.syncInterval = ${SYNC_INT}
dxgi.deferSurfaceCreation = True
dxgi.numBackBuffers = 1
d3d9.numBackBuffers = 1
dxvk.allowFse = False
d3d11.maxTessFactor = 1
EOF

# Si el HUD de FPS está activado
if [ "$MOSTRAR_HUD_FPS" = "1" ]; then
    echo "dxvk.hud = fps,frametimes,drawcalls" >> "$CONF_FILE"
fi

# Copia de compatibilidad en la raíz
if [ "$CONF_FILE" != "${DIR}/dxvk.conf" ]; then
    cp -f "$CONF_FILE" "${DIR}/dxvk.conf" 2>/dev/null || true
fi
