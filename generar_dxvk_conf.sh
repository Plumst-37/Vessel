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
dxvk.useRawSsbo = True

# Optimización de latencia y throughput de GPU
d3d11.relaxedBarriers = True
d3d11.maxTessellationFactor = 16

# Calidad y definición ultra-nítida de texturas 3D en cualquier ángulo (Filtrado Anisotrópico 16x)
d3d11.samplerAnisotropy = 16
d3d9.samplerAnisotropy = 16
d3d9.textureLodBias = 0

# Cero Desgarro de Pantalla (Tearing) y Cámara Fluida 1:1 sin Lag
# Latencia 1 cuadro elimina el retraso y movimiento pesado de la cámara 3D
d3d9.maxFrameLatency = 1
dxgi.maxFrameLatency = 1
d3d9.presentInterval = 1
dxgi.syncInterval = 1

# Compatibilidad con cambios de resolución y modo ventana/borde
d3d9.deferSurfaceCreation = True
EOF

# Si el HUD de FPS está activado
if [ "$MOSTRAR_HUD_FPS" = "1" ]; then
    echo "dxvk.hud = fps,frametimes,drawcalls" >> "$CONF_FILE"
fi
