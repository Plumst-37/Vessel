#!/bin/bash
# ==============================================================================
# GENERADOR DINÁMICO UNIVERSAL DE CONFIGURACIÓN DXVK
# Optimizado para cualquier arquitectura: Intel, AMD Radeon y NVIDIA
# ==============================================================================

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# Modo Pantalla Completa Exclusiva Nativa y compatibilidad DPI universal
dxvk.allowFse = True
d3d9.dpiAware = True

# Precisión geométrica universal: elimina deformaciones, estiramientos y z-fighting en modelos 3D
d3d9.invariantPosition = True
d3d11.invariantPosition = True
d3d9.longMad = True
d3d9.lenientClear = True
d3d9.maxAvailableMemory = 4096

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
d3d9.shaderModel = 3
EOF

# Si el HUD de FPS está activado
if [ "$MOSTRAR_HUD_FPS" = "1" ]; then
    echo "dxvk.hud = fps,frametimes,drawcalls" >> "$CONF_FILE"
fi
