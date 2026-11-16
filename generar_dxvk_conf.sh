#!/bin/bash
# Generador Dinámico de Configuración DXVK según Hardware y Preferencias

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

# Generar archivo dxvk.conf
cat <<EOF > "$CONF_FILE"
# ==============================================================================
# DXVK CONFIGURACIÓN GENERADA AUTOMÁTICAMENTE PARA MÁXIMO RENDIMIENTO
# CPU: ${CPU_MODEL} (${CPU_CORES} Hilos) | RAM: ${RAM_TOTAL_MB} MB
# Perfil: ${PERFIL_RENDIMIENTO:-maximo}
# ==============================================================================

# Compilación de Shaders en paralelo con todos los hilos del CPU
dxvk.numCompilerThreads = ${CPU_CORES}

# Control de Tasa de Refresco / FPS
dxgi.maxFrameRate = ${FPS_VAL}

# Reducción drástica de tirones y stuttering (Shaders Asíncronos / GPL)
dxvk.enableAsync = true
dxvk.gpl = True
dxvk.useRawSsbo = True

# Optimización de latencia y throughput de GPU
d3d11.relaxedBarriers = True
d3d11.maxTessellationFactor = 16
d3d11.samplerAnisotropy = 4

# Optimización para juegos DirectX 9 y DirectX 11 con Mods / ReShade
d3d9.deferSurfaceCreation = True
d3d9.maxFrameLatency = 1
dxgi.maxFrameLatency = 1
dxgi.syncInterval = 0
dxgi.deferSurfaceCreation = True
EOF

# Si el HUD de FPS está activado
if [ "$MOSTRAR_HUD_FPS" = "1" ]; then
    echo "dxvk.hud = fps,frametimes,drawcalls" >> "$CONF_FILE"
fi
