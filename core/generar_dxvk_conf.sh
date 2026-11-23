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
CONFIG_USER="${CONFIG_DIR}/config_rendimiento.cfg"
[ ! -f "$CONFIG_USER" ] && CONFIG_USER="${DIR}/config_rendimiento.cfg"

# Cargar preferencias
[ -f "$CONFIG_USER" ] && source "$CONFIG_USER"
if [ -f "${CORE_DIR}/hardware_detect.sh" ]; then
    source "${CORE_DIR}/hardware_detect.sh"
else
    source "${DIR}/hardware_detect.sh"
fi

# Definir límite de FPS
FPS_VAL="0"
case "$LIMITE_FPS" in
    30) FPS_VAL="30" ;;
    60) FPS_VAL="60" ;;
    120) FPS_VAL="120" ;;
    *) FPS_VAL="0" ;;
esac

# Calibración de sincronización y latencia (VSync y Buffers)
VSYNC_ENABLED="${VSYNC_MODE:-1}"
if [ "$VSYNC_ENABLED" = "0" ]; then
    TEAR_FREE="False"
    SYNC_INT="0"
    NUM_BUFFERS="2"
    FRAME_LATENCY="1"
else
    TEAR_FREE="True"
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

# Calibración de memoria según RAM (Ahorro <= 4GB, Equilibrado 8GB-12GB, Extremo 16GB+)
D3D9_MEM="2048"
if [ -n "$RAM_TOTAL_MB" ]; then
    if [ "$RAM_TOTAL_MB" -le 4608 ]; then
        D3D9_MEM="1024"
    elif [ "$RAM_TOTAL_MB" -gt 13312 ]; then
        D3D9_MEM="4096"
    fi
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
d3d9.lenientClear = True
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
d3d11.maxTessellationFactor = ${MAX_TESSELLATION}
d3d9.memoryTrackTest = False
dxvk.enableNvapi = True

# Perfiles específicos por ejecutable para máxima fidelidad 3D, estabilidad y rendimiento
[GTA5.exe]
dxgi.maxFrameLatency = 2
dxgi.hideNvidiaGpu = False
d3d11.disableMsaa = True
d3d11.clampNegativeLodBias = True
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
d3d11.relaxedBarriers = False
d3d11.samplerAnisotropy = ${SAMPLER_ANISO}
dxvk.shrinkImageHeaps = ${SHRINK_HEAPS}
dxvk.allowMemoryOvercommit = ${ALLOW_OVERCOMMIT}
d3d11.maxTessellationFactor = ${MAX_TESSELLATION}
dxvk.gpl = ${GPL_VAL}
dxvk.allowFse = False
dxvk.tearFree = True
dxgi.syncInterval = 1

[PlayGTAV.exe]
dxgi.maxFrameLatency = 2
dxgi.hideNvidiaGpu = False
d3d11.disableMsaa = True
d3d11.clampNegativeLodBias = True
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
d3d11.relaxedBarriers = False
d3d11.samplerAnisotropy = ${SAMPLER_ANISO}
dxvk.shrinkImageHeaps = ${SHRINK_HEAPS}
dxvk.allowMemoryOvercommit = ${ALLOW_OVERCOMMIT}
d3d11.maxTessellationFactor = ${MAX_TESSELLATION}
dxvk.gpl = ${GPL_VAL}
dxvk.allowFse = False
dxvk.tearFree = True
dxgi.syncInterval = 1

[speed.exe]
d3d9.invariantPosition = True
d3d9.floatEmulation = Strict
d3d9.clampNegativeLodBias = True
d3d9.samplerAnisotropy = ${SAMPLER_ANISO}
d3d9.presentInterval = 1
dxvk.tearFree = True
dxvk.allowFse = False

[BH6.exe]
d3d9.invariantPosition = True
d3d9.floatEmulation = Strict
d3d9.clampNegativeLodBias = True
d3d9.samplerAnisotropy = ${SAMPLER_ANISO}
d3d9.lenientClear = True
d3d9.presentInterval = 1
dxvk.tearFree = True
dxvk.allowFse = False

[re4.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = 1
dxgi.maxFrameLatency = 2
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
d3d11.relaxedBarriers = False
dxvk.allowFse = False
dxvk.tearFree = True
dxvk.gpl = True

[re4_original.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = 1
dxgi.maxFrameLatency = 2
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
d3d11.relaxedBarriers = False
dxvk.allowFse = False
dxvk.tearFree = True
dxvk.gpl = True

[re2.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = 1
dxgi.maxFrameLatency = 2
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
d3d11.relaxedBarriers = False
dxvk.allowFse = False
dxvk.tearFree = True
dxvk.gpl = True

[re3.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = 1
dxgi.maxFrameLatency = 2
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
d3d11.relaxedBarriers = False
dxvk.allowFse = False
dxvk.tearFree = True
dxvk.gpl = True

[re7.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = 1
dxgi.maxFrameLatency = 2
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
d3d11.relaxedBarriers = False
dxvk.allowFse = False
dxvk.tearFree = True
dxvk.gpl = True

[re8.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = 1
dxgi.maxFrameLatency = 2
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
d3d11.relaxedBarriers = False
dxvk.allowFse = False
dxvk.tearFree = True
dxvk.gpl = True

[dmc5.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = 1
dxgi.maxFrameLatency = 2
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
d3d11.relaxedBarriers = False
dxvk.allowFse = False
dxvk.tearFree = True
dxvk.gpl = True

[gta_sa.exe]
d3d9.invariantPosition = True
d3d9.floatEmulation = Strict
d3d9.clampNegativeLodBias = True
d3d9.samplerAnisotropy = ${SAMPLER_ANISO}
d3d9.presentInterval = 1
dxvk.tearFree = True
dxvk.allowFse = False

[Swat4.exe]
d3d9.invariantPosition = True
d3d9.floatEmulation = Strict
d3d9.clampNegativeLodBias = True
d3d9.samplerAnisotropy = ${SAMPLER_ANISO}
d3d9.presentInterval = 1
dxvk.tearFree = True
dxvk.allowFse = False

# GameRanger: cliente de lobby 2D / chat con Chromium CEF y ANGLE
# Evita fallos de swapchains Vulkan (VK_ERROR_OUT_OF_HOST_MEMORY) en subventanas de CEF
[GameRanger.exe]
dxvk.tearFree = False
dxgi.syncInterval = 1
dxgi.deferSurfaceCreation = True
dxgi.numBackBuffers = 1
d3d9.numBackBuffers = 1
dxvk.allowFse = False
d3d11.maxTessFactor = 1

[GameRangerSetup.exe]
dxvk.tearFree = False
dxgi.syncInterval = 1
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
