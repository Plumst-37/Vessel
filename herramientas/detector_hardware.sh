#!/bin/bash
# ==============================================================================
# VESSEL - DETECTOR UNIVERSAL DE HARDWARE (ULTRALIGERO Y PRECISO)
# Detecta CPU, hilos, GPU primaria/secundaria, RAM y servidor gráfico en < 0.1s
# ==============================================================================

# Autoprotección multi-shell
if [ -z "$BASH_VERSION" ]; then
    command -v bash >/dev/null 2>&1 && exec bash "$0" "$@"
fi

# 1. Detección de CPU e Hilos
CPU_CORES=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 4)
CPU_MODEL=$(grep -m 1 -E 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(lscpu 2>/dev/null | grep -iE 'model name|nombre del modelo' | cut -d: -f2 | xargs | head -n 1)
[ -z "$CPU_MODEL" ] && CPU_MODEL="Procesador Genérico (${CPU_CORES} hilos)"

# 2. Detección de Memoria RAM y Nivel de Optimización
RAM_TOTAL_KB=$(grep -i 'MemTotal' /proc/meminfo 2>/dev/null | awk '{print $2}')
if [ -n "$RAM_TOTAL_KB" ]; then
    RAM_TOTAL_MB=$((RAM_TOTAL_KB / 1024))
    RAM_TOTAL_GB=$(( (RAM_TOTAL_MB + 512) / 1024 ))
else
    RAM_TOTAL_MB=8192
    RAM_TOTAL_GB=8
fi

# Asignación de Nivel de RAM:
# <= 4GB: Ahorro | 8GB (4097 a 12288 MB): Equilibrado | 16GB+ (> 12288 MB): Extremo
if [ "$RAM_TOTAL_MB" -le 4608 ]; then
    RAM_TIER="ahorro"
    RAM_DESC="4 GB o menos (Modo Ahorro / Memoria Controlada)"
elif [ "$RAM_TOTAL_MB" -le 13312 ]; then
    RAM_TIER="equilibrado"
    RAM_DESC="${RAM_TOTAL_GB} GB RAM (Modo Equilibrado / Caché Estándar)"
else
    RAM_TIER="extremo"
    RAM_DESC="${RAM_TOTAL_GB} GB RAM (Modo Extremo / Caché Shaders en RAM)"
fi

# 3. Detección de Servidor Gráfico (Wayland o X11)
DISPLAY_SERVER="X11"
if [ "$XDG_SESSION_TYPE" = "wayland" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    DISPLAY_SERVER="Wayland"
fi

# 4. Detección de GPUs (Primaria, Secundaria e Integrada)
LSPCI_DATA=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' || true)
HAS_NVIDIA=false
HAS_AMD=false
HAS_INTEL=false
GPU_PRIMARY="Desconocida"
GPU_INTEGRATED=""
IS_LOW_SPEC_GPU=false

# NVIDIA
if echo "$LSPCI_DATA" | grep -qi 'nvidia'; then
    HAS_NVIDIA=true
    NVIDIA_LINE=$(echo "$LSPCI_DATA" | grep -i 'nvidia' | head -n 1 | cut -d: -f3 | xargs)
    GPU_PRIMARY="NVIDIA: ${NVIDIA_LINE}"
    # Detección de gama de entrada móvil (MX110, MX130, MX150, MX230, GT, etc.)
    if echo "$NVIDIA_LINE" | grep -qiE 'MX[0-9]{3}|GT[0-9]{3}|GTX\s*(750|850|950)'; then
        IS_LOW_SPEC_GPU=true
    fi
fi

# AMD
if echo "$LSPCI_DATA" | grep -qiE 'amd|radeon'; then
    HAS_AMD=true
    AMD_LINE=$(echo "$LSPCI_DATA" | grep -iE 'amd|radeon' | head -n 1 | cut -d: -f3 | xargs)
    if [ "$HAS_NVIDIA" = false ]; then
        GPU_PRIMARY="AMD: ${AMD_LINE}"
        if echo "$AMD_LINE" | grep -qiE 'vega\s*[0-9]|radeon\s*graphics'; then
            IS_LOW_SPEC_GPU=true
        fi
    else
        GPU_INTEGRATED="AMD: ${AMD_LINE}"
    fi
fi

# Intel
if echo "$LSPCI_DATA" | grep -qi 'intel'; then
    HAS_INTEL=true
    INTEL_LINE=$(echo "$LSPCI_DATA" | grep -i 'intel' | head -n 1 | cut -d: -f3 | xargs)
    if [ "$HAS_NVIDIA" = false ] && [ "$HAS_AMD" = false ]; then
        GPU_PRIMARY="Intel: ${INTEL_LINE}"
        IS_LOW_SPEC_GPU=true
    else
        GPU_INTEGRATED="Intel: ${INTEL_LINE}"
    fi
fi

# Resumen de GPU para mostrar
if [ -n "$GPU_INTEGRATED" ] && [ "$GPU_PRIMARY" != "Desconocida" ]; then
    GPU_DISPLAY="${GPU_PRIMARY} + ${GPU_INTEGRATED}"
else
    GPU_DISPLAY="${GPU_PRIMARY}"
fi

# 5. Detección de sincronización del Kernel (NTSync -> Fsync -> Esync)
SYNC_TYPE="Esync"
if [ -e "/dev/ntsync" ] || [ -c "/dev/ntsync" ]; then
    SYNC_TYPE="NTSync"
elif [ -f "/sys/kernel/debug/sched/futex_waitv" ] || [ "$(uname -r | cut -d. -f1)" -ge 6 ] || \
     { [ "$(uname -r | cut -d. -f1)" -eq 5 ] && [ "$(uname -r | cut -d. -f2)" -ge 16 ]; }; then
    SYNC_TYPE="Fsync"
fi

# 6. Salidas según argumento
FLAG="${1:-}"

if [ "$FLAG" = "--bash" ]; then
    echo "HW_CPU_MODEL=\"${CPU_MODEL}\""
    echo "HW_CPU_CORES=\"${CPU_CORES}\""
    echo "HW_RAM_MB=\"${RAM_TOTAL_MB}\""
    echo "HW_RAM_GB=\"${RAM_TOTAL_GB}\""
    echo "HW_RAM_TIER=\"${RAM_TIER}\""
    echo "HW_GPU_PRIMARY=\"${GPU_PRIMARY}\""
    echo "HW_GPU_INTEGRATED=\"${GPU_INTEGRATED}\""
    echo "HW_GPU_DISPLAY=\"${GPU_DISPLAY}\""
    echo "HW_IS_LOW_SPEC=\"$([ "$IS_LOW_SPEC_GPU" = true ] && echo 1 || echo 0)\""
    echo "HW_SERVER=\"${DISPLAY_SERVER}\""
    echo "HW_SYNC=\"${SYNC_TYPE}\""
elif [ "$FLAG" = "--json" ]; then
    cat <<JSON
{
  "cpu_model": "${CPU_MODEL}",
  "cpu_cores": ${CPU_CORES},
  "ram_mb": ${RAM_TOTAL_MB},
  "ram_gb": ${RAM_TOTAL_GB},
  "ram_tier": "${RAM_TIER}",
  "gpu_primary": "${GPU_PRIMARY}",
  "gpu_integrated": "${GPU_INTEGRATED}",
  "gpu_display": "${GPU_DISPLAY}",
  "is_low_spec": $([ "$IS_LOW_SPEC_GPU" = true ] && echo true || echo false),
  "display_server": "${DISPLAY_SERVER}",
  "sync_type": "${SYNC_TYPE}"
}
JSON
elif [ "$FLAG" = "--summary" ]; then
    echo "CPU: ${CPU_MODEL} (${CPU_CORES} Hilos) | RAM: ${RAM_TOTAL_GB} GB (${RAM_TIER}) | GPU: ${GPU_PRIMARY} | Display: ${DISPLAY_SERVER}"
else
    # Modo legible por defecto
    echo "  PC Detectado:"
    echo "  ├─ Procesador : ${CPU_MODEL} (${CPU_CORES} Hilos detectados)"
    echo "  ├─ Gráficos   : ${GPU_DISPLAY}"
    echo "  └─ Memoria    : ${RAM_TOTAL_GB} GB RAM (${RAM_TIER}) | Servidor Gráfico: ${DISPLAY_SERVER}"
fi
