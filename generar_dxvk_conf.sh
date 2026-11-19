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

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CONF_FILE="${DIR}/dxvk.conf"
CONFIG_USER="${DIR}/config_rendimiento.cfg"

# Cargar preferencias
[ -f "$CONFIG_USER" ] && source "$CONFIG_USER"
source "${DIR}/hardware_detect.sh"

# Definir límite de FPS
FPS_VAL="0"
case "$LIMITE_FPS" in
    30) FPS_VAL="30" ;;
    60) FPS_VAL="60" ;;
    120) FPS_VAL="120" ;;
    *) FPS_VAL="0" ;;
esac

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
# Perfil: ${PERFIL_RENDIMIENTO:-maximo}
# ==============================================================================

# Compilación de Shaders en paralelo con todos los hilos del CPU
dxvk.numCompilerThreads = ${CPU_CORES}

# Control de Tasa de Refresco / FPS (D3D9 y D3D11/DXGI)
dxgi.maxFrameRate = ${FPS_VAL}
d3d9.maxFrameRate = ${FPS_VAL}

# Reducción drástica de tirones y stuttering (Shaders Asíncronos / GPL)
dxvk.enableAsync = true
dxvk.gpl = True

# Modo Pantalla Completa: False para compatibilidad universal (evita fallos de EDID/swapchains en Wayland/PRIME)
dxvk.allowFse = False

# Precisión geométrica universal: elimina deformaciones, estiramientos y z-fighting en modelos 3D
d3d9.invariantPosition = True
d3d11.invariantPosition = True
d3d9.longMad = True
d3d9.floatEmulation = Strict
d3d11.floatEmulation = Strict
d3d9.clampNegativeLodBias = True
d3d11.clampNegativeLodBias = True
d3d9.samplerAnisotropy = 16
d3d11.samplerAnisotropy = 16
d3d11.constantBufferRangeCheck = True
d3d9.lenientClear = True
d3d9.maxAvailableMemory = ${D3D9_MEM}

# Modo Mailbox Present (Triple Buffering Tear-Free de Ultra-Baja Latencia)
# Elimina desgarro de pantalla (tearing) SIN caídas bruscas a 30 FPS ni tirones de cámara
# Garantiza movimiento de cámara 1:1 ultra-suave y respuesta inmediata
dxvk.tearFree = True
dxgi.syncInterval = 0
d3d9.presentInterval = 0
dxgi.numBackBuffers = 3
d3d9.numBackBuffers = 3
d3d9.maxFrameLatency = 1
dxgi.maxFrameLatency = 1

# Optimizaciones de memoria y pipelines DXVK 2.6
dxvk.trackPipelineLifetime = True
d3d9.memoryTrackTest = False

# Perfiles específicos por ejecutable para máxima fidelidad 3D, estabilidad y rendimiento
[GTA5.exe]
dxgi.maxFrameLatency = 1
d3d11.clampNegativeLodBias = True
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
dxvk.enableAsync = true
dxvk.gpl = True
dxvk.allowFse = False
dxgi.syncInterval = 0

[PlayGTAV.exe]
dxgi.maxFrameLatency = 1
d3d11.clampNegativeLodBias = True
d3d11.constantBufferRangeCheck = True
d3d11.invariantPosition = True
dxvk.enableAsync = true
dxvk.gpl = True
dxvk.allowFse = False
dxgi.syncInterval = 0

[speed.exe]
d3d9.invariantPosition = True
d3d9.longMad = True
d3d9.floatEmulation = Auto
d3d9.clampNegativeLodBias = True
d3d9.samplerAnisotropy = 16
dxvk.allowFse = False

[BH6.exe]
d3d9.invariantPosition = True
d3d9.longMad = True
d3d9.floatEmulation = Auto
d3d9.clampNegativeLodBias = True
d3d9.samplerAnisotropy = 16
d3d9.lenientClear = True
dxvk.allowFse = False

[re4.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = 0
dxgi.maxFrameLatency = 1
d3d11.constantBufferRangeCheck = True
dxvk.allowFse = False
dxvk.enableAsync = true
dxvk.gpl = True

[re4_original.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = 0
dxgi.maxFrameLatency = 1
d3d11.constantBufferRangeCheck = True
dxvk.allowFse = False
dxvk.enableAsync = true
dxvk.gpl = True

[re2.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = 0
dxgi.maxFrameLatency = 1
dxvk.allowFse = False
dxvk.enableAsync = true
dxvk.gpl = True

[re3.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = 0
dxgi.maxFrameLatency = 1
dxvk.allowFse = False
dxvk.enableAsync = true
dxvk.gpl = True

[re7.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = 0
dxgi.maxFrameLatency = 1
dxvk.allowFse = False
dxvk.enableAsync = true
dxvk.gpl = True

[re8.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = 0
dxgi.maxFrameLatency = 1
dxvk.allowFse = False
dxvk.enableAsync = true
dxvk.gpl = True

[dmc5.exe]
dxgi.hideNvidiaGpu = False
dxgi.syncInterval = 0
dxgi.maxFrameLatency = 1
dxvk.allowFse = False
dxvk.enableAsync = true
dxvk.gpl = True

[gta_sa.exe]
d3d9.invariantPosition = True
d3d9.longMad = True
d3d9.floatEmulation = Auto
d3d9.clampNegativeLodBias = True
d3d9.samplerAnisotropy = 16
dxvk.allowFse = False

[Swat4.exe]
d3d9.invariantPosition = True
d3d9.longMad = True
d3d9.floatEmulation = Strict
d3d9.clampNegativeLodBias = True
d3d9.samplerAnisotropy = 16
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
