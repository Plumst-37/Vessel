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

# Buffer de fotogramas para eliminar tirones (2 cuadros de cola suavizan el frametime)
d3d9.maxFrameLatency = 2
dxgi.maxFrameLatency = 2
EOF

# Filtro de GPU dedicada: Obliga a DXVK a elegir la GPU NVIDIA o AMD dedicada
# y evita que el juego caiga en la gráfica integrada débil (causa de tirones y baja VRAM)
if [ "$HAS_NVIDIA" = true ]; then
    echo "dxvk.deviceFilter = GeForce,NVIDIA" >> "$CONF_FILE"
elif [ "$HAS_AMD_DEDICATED" = true ]; then
    echo "dxvk.deviceFilter = Radeon,AMD" >> "$CONF_FILE"
fi

# Si el HUD de FPS está activado
if [ "$MOSTRAR_HUD_FPS" = "1" ]; then
    echo "dxvk.hud = fps,frametimes,drawcalls" >> "$CONF_FILE"
fi
