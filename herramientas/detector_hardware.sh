#!/bin/bash
# ==============================================================================
# VESSEL - ESCÁNER UNIVERSAL DE HARDWARE (ULTRARRÁPIDO Y PRECISO)
# Genera y consulta perfil_hardware.cfg en < 0.001s para zero-lag en arranque
# ==============================================================================

# Autoprotección multi-shell
if [ -z "$BASH_VERSION" ]; then
    command -v bash >/dev/null 2>&1 && exec bash "$0" "$@"
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
CONFIG_DIR="${DIR}/config"
mkdir -p "$CONFIG_DIR" 2>/dev/null || true
CFG_FILE="${CONFIG_DIR}/perfil_hardware.cfg"
[ ! -f "$CFG_FILE" ] && [ -f "${DIR}/perfil_hardware.cfg" ] && CFG_FILE="${DIR}/perfil_hardware.cfg"

FLAG="${1:-}"

# Si se solicita leer desde caché y el archivo existe, salir de inmediato en 0.0005s
if [ "$FLAG" = "--cached" ] && [ -f "$CFG_FILE" ]; then
    cat "$CFG_FILE"
    exit 0
fi

HOST_ID="$(cat /etc/machine-id 2>/dev/null || hostname 2>/dev/null || echo "host_generic")"

# 1. CPU, Núcleos Físicos, Hilos y Extensiones
CPU_CORES=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 4)
CPU_MODEL=$(grep -m 1 -E 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(lscpu 2>/dev/null | grep -iE 'model name|nombre del modelo' | cut -d: -f2 | xargs | head -n 1)
[ -z "$CPU_MODEL" ] && CPU_MODEL="Procesador Genérico"

CPU_PHYSICAL_CORES=$(lscpu -p 2>/dev/null | grep -v '^#' | awk -F, '{print $2}' | sort -u | wc -l 2>/dev/null || echo "$CPU_CORES")
[ -z "$CPU_PHYSICAL_CORES" ] || [ "$CPU_PHYSICAL_CORES" -le 0 ] && CPU_PHYSICAL_CORES="$CPU_CORES"

CPU_FLAGS=$(grep -m 1 '^flags' /proc/cpuinfo 2>/dev/null | cut -d: -f2 || true)
CPU_HAS_AVX=false
CPU_HAS_AVX2=false
CPU_HAS_SSE4_2=false
echo "$CPU_FLAGS" | grep -qw 'avx' && CPU_HAS_AVX=true
echo "$CPU_FLAGS" | grep -qw 'avx2' && CPU_HAS_AVX2=true
echo "$CPU_FLAGS" | grep -qw 'sse4_2' && CPU_HAS_SSE4_2=true

# Clasificación de Gama del Procesador
if [ "$CPU_CORES" -le 4 ] || echo "$CPU_MODEL" | grep -qiE 'Atom|Celeron|Pentium|Athlon|Sempron|Core\(TM\)2'; then
    CPU_TIER="baja"
elif [ "$CPU_CORES" -le 8 ]; then
    CPU_TIER="media"
elif [ "$CPU_CORES" -le 16 ]; then
    CPU_TIER="alta"
else
    CPU_TIER="extrema"
fi

# 2. Memoria RAM (Total en MB) y Clasificación
RAM_TOTAL_KB=$(grep -i 'MemTotal' /proc/meminfo 2>/dev/null | awk '{print $2}')
if [ -n "$RAM_TOTAL_KB" ]; then
    RAM_TOTAL_MB=$((RAM_TOTAL_KB / 1024))
else
    RAM_TOTAL_MB=8192
fi

if [ "$RAM_TOTAL_MB" -le 6144 ]; then
    RAM_TIER="baja"
elif [ "$RAM_TOTAL_MB" -le 14336 ]; then
    RAM_TIER="media"
elif [ "$RAM_TOTAL_MB" -le 30720 ]; then
    RAM_TIER="alta"
else
    RAM_TIER="extrema"
fi

# 3. Detección de GPUs (NVIDIA, AMD, Intel, Genéricas) y VRAM
LSPCI_DATA=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' || true)
GPU_VENDOR="desconocido"
GPU_PRIMARY="Desconocida"
GPU_VRAM_MB=2048
GPU_IS_ENTRY_LEVEL=false

if echo "$LSPCI_DATA" | grep -qi 'nvidia'; then
    GPU_VENDOR="nvidia"
    NVIDIA_LINE=$(echo "$LSPCI_DATA" | grep -i 'nvidia' | head -n 1 | cut -d: -f3 | xargs)
    if echo "$NVIDIA_LINE" | grep -q '\['; then
        clean_nv=$(echo "$NVIDIA_LINE" | sed -n 's/.*\[\(.*\)\].*/\1/p' | sed 's/ (rev.*)//')
        [ -n "$clean_nv" ] && GPU_PRIMARY="NVIDIA ${clean_nv}" || GPU_PRIMARY="NVIDIA ${NVIDIA_LINE}"
    else
        GPU_PRIMARY="NVIDIA ${NVIDIA_LINE}"
    fi

    # VRAM real de NVIDIA
    VRAM_NV=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1 | tr -d ' ')
    if [ -n "$VRAM_NV" ] && [ "$VRAM_NV" -gt 0 ] 2>/dev/null; then
        GPU_VRAM_MB="$VRAM_NV"
    fi

    # Clasificación de gama de entrada (<= 2048 MB o modelos MX/GT/GTX de bajo consumo)
    if [ "$GPU_VRAM_MB" -le 2048 ] || echo "$NVIDIA_LINE" | grep -qiE 'MX[0-9]{3}|GT[0-9]{3}|GTX\s*(750|850|950)'; then
        GPU_IS_ENTRY_LEVEL=true
    fi
elif echo "$LSPCI_DATA" | grep -qiE 'amd|radeon'; then
    GPU_VENDOR="amd"
    AMD_LINE=$(echo "$LSPCI_DATA" | grep -iE 'amd|radeon' | head -n 1 | cut -d: -f3 | xargs)
    if echo "$AMD_LINE" | grep -q '\['; then
        clean_amd=$(echo "$AMD_LINE" | sed -n 's/.*\[\(.*\)\].*/\1/p' | sed 's/ (rev.*)//')
        [ -n "$clean_amd" ] && GPU_PRIMARY="AMD ${clean_amd}" || GPU_PRIMARY="AMD ${AMD_LINE}"
    else
        GPU_PRIMARY="AMD ${AMD_LINE}"
    fi

    # VRAM de AMD en sysfs si está disponible (escanea todas las tarjetas card0, card1 para detectar GPUs dedicadas)
    for card_vram in /sys/class/drm/card*/device/mem_info_vram_total; do
        if [ -f "$card_vram" ]; then
            vram_bytes=$(cat "$card_vram" 2>/dev/null || echo 0)
            if [ "$vram_bytes" -gt 0 ] 2>/dev/null; then
                c_mb=$((vram_bytes / 1024 / 1024))
                [ "$c_mb" -gt "$GPU_VRAM_MB" ] && GPU_VRAM_MB="$c_mb"
            fi
        fi
    done

    if [ "$GPU_VRAM_MB" -le 2048 ] || echo "$AMD_LINE" | grep -qiE 'vega\s*[0-9]|radeon\s*graphics'; then
        GPU_IS_ENTRY_LEVEL=true
    fi
elif echo "$LSPCI_DATA" | grep -qi 'intel'; then
    GPU_VENDOR="intel"
    INTEL_LINE=$(echo "$LSPCI_DATA" | grep -i 'intel' | head -n 1 | cut -d: -f3 | xargs)
    if echo "$INTEL_LINE" | grep -q '\['; then
        clean_intel=$(echo "$INTEL_LINE" | sed -n 's/.*\[\(.*\)\].*/\1/p' | sed 's/ (rev.*)//')
        [ -n "$clean_intel" ] && GPU_PRIMARY="Intel ${clean_intel}" || GPU_PRIMARY="Intel ${INTEL_LINE}"
    else
        GPU_PRIMARY="Intel ${INTEL_LINE}"
    fi
    GPU_VRAM_MB=1536
    GPU_IS_ENTRY_LEVEL=true

    # Comprobar si es Intel Arc dedicada con VRAM propia
    for card_vram in /sys/class/drm/card*/device/mem_info_vram_total; do
        if [ -f "$card_vram" ]; then
            vram_bytes=$(cat "$card_vram" 2>/dev/null || echo 0)
            if [ "$vram_bytes" -gt 0 ] 2>/dev/null; then
                c_mb=$((vram_bytes / 1024 / 1024))
                if [ "$c_mb" -gt "$GPU_VRAM_MB" ]; then
                    GPU_VRAM_MB="$c_mb"
                    GPU_IS_ENTRY_LEVEL=false
                fi
            fi
        fi
    done
else
    GPU_VENDOR="generica"
    GPU_PRIMARY=$(echo "$LSPCI_DATA" | head -n 1 | cut -d: -f3 | xargs)
    [ -z "$GPU_PRIMARY" ] && GPU_PRIMARY="Gráficos Genéricos / Virtuales"
    GPU_VRAM_MB=1024
    GPU_IS_ENTRY_LEVEL=true
fi

# Clasificación de Gama de Tarjeta Gráfica
if [ "$GPU_VENDOR" = "intel" ]; then
    if echo "$GPU_PRIMARY" | grep -qiE 'Arc|DG2|A[357][0-9]{2}'; then
        if [ "$GPU_VRAM_MB" -gt 6144 ]; then
            GPU_TIER="alta"
            GPU_IS_ENTRY_LEVEL=false
        else
            GPU_TIER="media"
            GPU_IS_ENTRY_LEVEL=false
        fi
    else
        GPU_TIER="baja"
        GPU_IS_ENTRY_LEVEL=true
    fi
elif [ "$GPU_VRAM_MB" -le 2048 ] || [ "$GPU_IS_ENTRY_LEVEL" = true ]; then
    GPU_TIER="baja"
    GPU_IS_ENTRY_LEVEL=true
elif [ "$GPU_VRAM_MB" -le 6144 ]; then
    GPU_TIER="media"
    GPU_IS_ENTRY_LEVEL=false
elif [ "$GPU_VRAM_MB" -le 12288 ]; then
    GPU_TIER="alta"
    GPU_IS_ENTRY_LEVEL=false
else
    GPU_TIER="extrema"
    GPU_IS_ENTRY_LEVEL=false
fi

# Clasificación de Gama Global de la Máquina
if [ "$GPU_TIER" = "baja" ] || [ "$RAM_TIER" = "baja" ] || [ "$CPU_TIER" = "baja" ]; then
    VESSEL_HARDWARE_TIER="baja"
elif [ "$GPU_TIER" = "extrema" ] && [ "$RAM_TIER" != "media" ] && [ "$CPU_TIER" != "media" ]; then
    VESSEL_HARDWARE_TIER="extrema"
elif [ "$GPU_TIER" = "alta" ] && [ "$RAM_TIER" != "media" ] && [ "$CPU_TIER" != "media" ]; then
    VESSEL_HARDWARE_TIER="alta"
else
    VESSEL_HARDWARE_TIER="media"
fi

# 4. Servidor Gráfico (Wayland / X11)
DISPLAY_SERVER="x11"
if [ "$XDG_SESSION_TYPE" = "wayland" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    DISPLAY_SERVER="wayland"
fi

# 5. Resolución Nativa de Pantalla y Resolución Recomendada para Juegos
NATIVE_RES=$(xrandr --current 2>/dev/null | grep -E ' connected primary [0-9]+x[0-9]+' | head -n 1 | grep -oE '[0-9]+x[0-9]+' | head -n 1)
[ -z "$NATIVE_RES" ] && NATIVE_RES=$(xrandr --current 2>/dev/null | grep -E ' connected [0-9]+x[0-9]+' | head -n 1 | grep -oE '[0-9]+x[0-9]+' | head -n 1)
[ -z "$NATIVE_RES" ] && NATIVE_RES=$(cat /sys/class/drm/*/modes 2>/dev/null | head -n 1)
[ -z "$NATIVE_RES" ] && NATIVE_RES="1920x1080"

NATIVE_RES_W=$(echo "$NATIVE_RES" | cut -d'x' -f1)
NATIVE_RES_H=$(echo "$NATIVE_RES" | cut -d'x' -f2)

raw_hz=$(xrandr 2>/dev/null | grep -E '\*' | head -n 1 | awk '{for(i=1;i<=NF;i++) if($i ~ /\*/) print $i}' | tr -d '*+' | cut -d'.' -f1)
if [ -n "$raw_hz" ] && [ "$raw_hz" -gt 0 ] 2>/dev/null; then
    if [ "$raw_hz" -ge 58 ] && [ "$raw_hz" -le 62 ]; then
        SCREEN_HZ=60
    else
        SCREEN_HZ="$raw_hz"
    fi
else
    SCREEN_HZ=60
fi

if [ "$GPU_IS_ENTRY_LEVEL" = true ]; then
    RECOMMENDED_GAME_W=1280
    RECOMMENDED_GAME_H=720
else
    RECOMMENDED_GAME_W="$NATIVE_RES_W"
    RECOMMENDED_GAME_H="$NATIVE_RES_H"
fi

# 6. Detección Real de Soporte Vulkan y Graphics Pipeline Library (GPL)
HAS_VULKAN=false
if command -v vulkaninfo &>/dev/null; then
    if vulkaninfo --summary &>/dev/null || vulkaninfo &>/dev/null; then
        HAS_VULKAN=true
    fi
elif [ -d "/usr/share/vulkan/icd.d" ] && ls /usr/share/vulkan/icd.d/*.json &>/dev/null; then
    HAS_VULKAN=true
fi

HAS_VULKAN_GPL=false
if [ "$HAS_VULKAN" = true ]; then
    if vulkaninfo 2>/dev/null | grep -qi 'VK_EXT_graphics_pipeline_library'; then
        HAS_VULKAN_GPL=true
    elif [ "$GPU_VENDOR" = "nvidia" ] && echo "${GPU_PRIMARY}" | grep -qiE 'GTX\s*(16[0-9]{2})|RTX'; then
        HAS_VULKAN_GPL=true
    elif [ "$GPU_VENDOR" = "amd" ] && echo "${GPU_PRIMARY}" | grep -qiE 'RX\s*([5-7][0-9]{3}|Vega)'; then
        HAS_VULKAN_GPL=true
    fi
fi

# 7. Sincronización del Kernel (NTSync / Fsync / Esync)
HAS_NTSYNC=false
[ -e "/dev/ntsync" ] && HAS_NTSYNC=true

HAS_FSYNC=false
if [ -f "/sys/kernel/debug/sched/futex_waitv" ] || [ "$(uname -r | cut -d. -f1)" -ge 6 ] || \
   { [ "$(uname -r | cut -d. -f1)" -eq 5 ] && [ "$(uname -r | cut -d. -f2)" -ge 16 ]; }; then
    HAS_FSYNC=true
fi

# 8. Extras de Gaming en el Sistema
HAS_GAMEMODE=false
command -v gamemoderun &>/dev/null && HAS_GAMEMODE=true

HAS_GAMESCOPE=false
command -v gamescope &>/dev/null && HAS_GAMESCOPE=true

HAS_PIPEWIRE=false
pgrep -x pipewire &>/dev/null && HAS_PIPEWIRE=true

# 9. Guardar perfil_hardware.cfg universal con calibración completa de gamas
if [ "$FLAG" = "--save" ] || [ "$FLAG" = "--refresh" ] || [ ! -f "$CFG_FILE" ]; then
    cat <<EOF > "$CFG_FILE"
# Generado automáticamente por Vessel Hardware Scanner
HOST_ID="${HOST_ID}"
CPU_MODEL="${CPU_MODEL}"
CPU_THREADS=${CPU_CORES}
CPU_PHYSICAL_CORES=${CPU_PHYSICAL_CORES}
CPU_TIER="${CPU_TIER}"
CPU_HAS_AVX=${CPU_HAS_AVX}
CPU_HAS_AVX2=${CPU_HAS_AVX2}
CPU_HAS_SSE4_2=${CPU_HAS_SSE4_2}
RAM_TOTAL_MB=${RAM_TOTAL_MB}
RAM_TIER="${RAM_TIER}"
GPU_PRIMARY="${GPU_PRIMARY}"
GPU_PRIMARY_VENDOR="${GPU_VENDOR}"
GPU_VRAM_MB=${GPU_VRAM_MB}
GPU_TIER="${GPU_TIER}"
GPU_IS_ENTRY_LEVEL=${GPU_IS_ENTRY_LEVEL}
VESSEL_HARDWARE_TIER="${VESSEL_HARDWARE_TIER}"
HAS_VULKAN=${HAS_VULKAN}
HAS_VULKAN_GPL=${HAS_VULKAN_GPL}
DISPLAY_SERVER="${DISPLAY_SERVER}"
NATIVE_RES_W=${NATIVE_RES_W}
NATIVE_RES_H=${NATIVE_RES_H}
SCREEN_HZ=${SCREEN_HZ}
RECOMMENDED_GAME_W=${RECOMMENDED_GAME_W}
RECOMMENDED_GAME_H=${RECOMMENDED_GAME_H}
HAS_NTSYNC=${HAS_NTSYNC}
HAS_FSYNC=${HAS_FSYNC}
HAS_GAMEMODE=${HAS_GAMEMODE}
HAS_GAMESCOPE=${HAS_GAMESCOPE}
HAS_PIPEWIRE=${HAS_PIPEWIRE}
EOF
    [ -d "${DIR}/config" ] && cp -f "$CFG_FILE" "${DIR}/config/perfil_hardware.cfg" 2>/dev/null || true
    cp -f "$CFG_FILE" "${DIR}/perfil_hardware.cfg" 2>/dev/null || true
fi

# 10. Formatos de Salida
if [ "$FLAG" = "--bash" ]; then
    cat "$CFG_FILE"
elif [ "$FLAG" = "--json" ]; then
    cat <<JSON
{
  "cpu_model": "${CPU_MODEL}",
  "cpu_threads": ${CPU_CORES},
  "cpu_physical_cores": ${CPU_PHYSICAL_CORES},
  "cpu_tier": "${CPU_TIER}",
  "ram_total_mb": ${RAM_TOTAL_MB},
  "ram_tier": "${RAM_TIER}",
  "gpu_primary": "${GPU_PRIMARY}",
  "gpu_primary_vendor": "${GPU_VENDOR}",
  "gpu_vram_mb": ${GPU_VRAM_MB},
  "gpu_tier": "${GPU_TIER}",
  "gpu_is_entry_level": ${GPU_IS_ENTRY_LEVEL},
  "vessel_hardware_tier": "${VESSEL_HARDWARE_TIER}",
  "has_vulkan": ${HAS_VULKAN},
  "has_vulkan_gpl": ${HAS_VULKAN_GPL},
  "display_server": "${DISPLAY_SERVER}",
  "native_res_w": ${NATIVE_RES_W},
  "native_res_h": ${NATIVE_RES_H},
  "recommended_game_w": ${RECOMMENDED_GAME_W},
  "recommended_game_h": ${RECOMMENDED_GAME_H},
  "has_ntsync": ${HAS_NTSYNC},
  "has_fsync": ${HAS_FSYNC},
  "has_gamemode": ${HAS_GAMEMODE},
  "has_gamescope": ${HAS_GAMESCOPE},
  "has_pipewire": ${HAS_PIPEWIRE}
}
JSON
elif [ "$FLAG" = "--summary" ]; then
    echo "CPU: ${CPU_MODEL} (${CPU_PHYSICAL_CORES}C/${CPU_CORES}T) [${CPU_TIER^^}] | GPU: ${GPU_PRIMARY} (${GPU_VRAM_MB}MB) [${GPU_TIER^^}] | RAM: ${RAM_TOTAL_MB}MB [${RAM_TIER^^}] | Gama Vessel: ${VESSEL_HARDWARE_TIER^^} | Vulkan: ${HAS_VULKAN}"
else
    # Modo legible por defecto
    echo "  ╔══════════════════════════════════════════════════════════════════╗"
    echo "  ║            VESSEL HARDWARE PROFILE (Autocalibrado)               ║"
    echo "  ╠══════════════════════════════════════════════════════════════════╣"
    echo "  ║ • Procesador : ${CPU_MODEL} (${CPU_PHYSICAL_CORES}C / ${CPU_CORES}T) [Gama: ${CPU_TIER^^}]"
    echo "  ║ • Gráficos   : ${GPU_PRIMARY} (${GPU_VRAM_MB} MB VRAM) [Gama: ${GPU_TIER^^}]"
    echo "  ║ • Memoria    : ${RAM_TOTAL_MB} MB RAM Total [Gama: ${RAM_TIER^^}]"
    echo "  ║ • Gama Global: ${VESSEL_HARDWARE_TIER^^} | Vulkan: ${HAS_VULKAN} (GPL: ${HAS_VULKAN_GPL})"
    echo "  ║ • Pantalla   : Nativa ${NATIVE_RES_W}x${NATIVE_RES_H} ➔ Óptima Juego: ${RECOMMENDED_GAME_W}x${RECOMMENDED_GAME_H}"
    echo "  ║ • Kernel/Sync: Fsync: ${HAS_FSYNC} | NTSync: ${HAS_NTSYNC} | GameMode: ${HAS_GAMEMODE}"
    echo "  ╚══════════════════════════════════════════════════════════════════╝"
fi
