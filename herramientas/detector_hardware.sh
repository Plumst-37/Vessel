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

# 1. CPU e Hilos Reales
CPU_CORES=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 4)
CPU_MODEL=$(grep -m 1 -E 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(lscpu 2>/dev/null | grep -iE 'model name|nombre del modelo' | cut -d: -f2 | xargs | head -n 1)
[ -z "$CPU_MODEL" ] && CPU_MODEL="Procesador Genérico"

# 2. Memoria RAM (Total en MB)
RAM_TOTAL_KB=$(grep -i 'MemTotal' /proc/meminfo 2>/dev/null | awk '{print $2}')
if [ -n "$RAM_TOTAL_KB" ]; then
    RAM_TOTAL_MB=$((RAM_TOTAL_KB / 1024))
else
    RAM_TOTAL_MB=8192
fi

# 3. Detección de GPUs (NVIDIA, AMD, Intel) y VRAM
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
fi

# 4. Servidor Gráfico (Wayland / X11)
DISPLAY_SERVER="x11"
if [ "$XDG_SESSION_TYPE" = "wayland" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    DISPLAY_SERVER="wayland"
fi

# 5. Resolución Nativa de Pantalla y Resolución Recomendada para Juegos
NATIVE_RES=$(cat /sys/class/drm/*/modes 2>/dev/null | head -n 1)
[ -z "$NATIVE_RES" ] && NATIVE_RES=$(xrandr 2>/dev/null | grep -E ' connected primary| connected' | head -n 1 | grep -oE '[0-9]+x[0-9]+' | head -n 1)
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

# 6. Sincronización del Kernel (NTSync / Fsync / Esync)
HAS_NTSYNC=false
[ -e "/dev/ntsync" ] && HAS_NTSYNC=true

HAS_FSYNC=false
if [ -f "/sys/kernel/debug/sched/futex_waitv" ] || [ "$(uname -r | cut -d. -f1)" -ge 6 ] || \
   { [ "$(uname -r | cut -d. -f1)" -eq 5 ] && [ "$(uname -r | cut -d. -f2)" -ge 16 ]; }; then
    HAS_FSYNC=true
fi

# 7. Extras de Gaming en el Sistema
HAS_GAMEMODE=false
command -v gamemoderun &>/dev/null && HAS_GAMEMODE=true

HAS_GAMESCOPE=false
command -v gamescope &>/dev/null && HAS_GAMESCOPE=true

HAS_PIPEWIRE=false
pgrep -x pipewire &>/dev/null && HAS_PIPEWIRE=true

# 8. Guardar perfil_hardware.cfg si se solicita o si no existe
if [ "$FLAG" = "--save" ] || [ "$FLAG" = "--refresh" ] || [ ! -f "$CFG_FILE" ]; then
    cat <<EOF > "$CFG_FILE"
# Generado automáticamente por Vessel Hardware Scanner
HOST_ID="${HOST_ID}"
CPU_MODEL="${CPU_MODEL}"
CPU_THREADS=${CPU_CORES}
RAM_TOTAL_MB=${RAM_TOTAL_MB}
GPU_PRIMARY="${GPU_PRIMARY}"
GPU_PRIMARY_VENDOR="${GPU_VENDOR}"
GPU_VRAM_MB=${GPU_VRAM_MB}
GPU_IS_ENTRY_LEVEL=${GPU_IS_ENTRY_LEVEL}
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

# 9. Formatos de Salida
if [ "$FLAG" = "--bash" ]; then
    cat "$CFG_FILE"
elif [ "$FLAG" = "--json" ]; then
    cat <<JSON
{
  "cpu_model": "${CPU_MODEL}",
  "cpu_threads": ${CPU_CORES},
  "ram_total_mb": ${RAM_TOTAL_MB},
  "gpu_primary": "${GPU_PRIMARY}",
  "gpu_primary_vendor": "${GPU_VENDOR}",
  "gpu_vram_mb": ${GPU_VRAM_MB},
  "gpu_is_entry_level": ${GPU_IS_ENTRY_LEVEL},
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
    echo "CPU: ${CPU_MODEL} (${CPU_CORES} Hilos) | GPU: ${GPU_PRIMARY} (${GPU_VRAM_MB} MB) | Res: ${RECOMMENDED_GAME_W}x${RECOMMENDED_GAME_H} | Fsync: ${HAS_FSYNC}"
else
    # Modo legible por defecto
    echo "  ╔══════════════════════════════════════════════════════════════════╗"
    echo "  ║            VESSEL HARDWARE PROFILE (Autocalibrado)               ║"
    echo "  ╠══════════════════════════════════════════════════════════════════╣"
    echo "  ║ • Procesador : ${CPU_MODEL} (${CPU_CORES} Hilos)"
    echo "  ║ • Gráficos   : ${GPU_PRIMARY} (${GPU_VRAM_MB} MB VRAM)"
    echo "  ║ • Memoria    : ${RAM_TOTAL_MB} MB RAM Total"
    echo "  ║ • Pantalla   : Nativa ${NATIVE_RES_W}x${NATIVE_RES_H} ➔ Óptima Juego: ${RECOMMENDED_GAME_W}x${RECOMMENDED_GAME_H}"
    echo "  ║ • Kernel/Sync: Fsync: ${HAS_FSYNC} | NTSync: ${HAS_NTSYNC} | GameMode: ${HAS_GAMEMODE}"
    echo "  ╚══════════════════════════════════════════════════════════════════╝"
fi
