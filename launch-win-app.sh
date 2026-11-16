#!/bin/bash
# ==============================================================================
# LANZADOR UNIVERSAL OPTIMIZADO PARA APLICACIONES Y JUEGOS DE WINDOWS
# Compatible con cualquier arquitectura de PC (Intel, AMD, NVIDIA, Integradas)
# Prefijo Wine Unificado con Compatibilidad Total de Gráficos y Videos
# ==============================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_FILE="${DIR}/programas.db"

# 1. Cargar preferencias del usuario y detección de hardware universal
[ -f "${DIR}/config_rendimiento.cfg" ] && source "${DIR}/config_rendimiento.cfg"
source "${DIR}/hardware_detect.sh"

# 2. Aplicar optimizaciones dinámicas para el hardware real del equipo
aplicar_entorno_hardware

# 3. Procesar banderas opcionales (compatibilidad)
if [ "$1" = "--prefix" ]; then
    shift
    shift || true
fi

if [ $# -eq 0 ]; then
    echo "Uso: $0 /ruta/al/programa.exe [argumentos]"
    exit 1
fi

TARGET="$1"
shift || true

# 4. Definir la ruta del WINEPREFIX unificado
export WINEPREFIX="${DIR}/wineprefix"

# 4.1 Resolver accesos directos de Windows (.lnk o .ink) al ejecutable real
if [[ "$TARGET" =~ \.([lL][nN][kK]|[iI][nN][kK])$ ]] && [ -f "$TARGET" ]; then
    echo "[*] Acceso directo detectado: $(basename "$TARGET"). Resolviendo ejecutable real..."
    if [ -f "${DIR}/resolver_lnk.py" ]; then
        RESOLVED_RES=$(python3 "${DIR}/resolver_lnk.py" "$TARGET" "${WINEPREFIX}" 2>/dev/null || true)
        RESOLVED_STATUS=$(echo "$RESOLVED_RES" | grep '^STATUS=' | cut -d= -f2-)
        RESOLVED_PATH=$(echo "$RESOLVED_RES" | grep '^RESOLVED_PATH=' | cut -d= -f2-)
        if [ "$RESOLVED_STATUS" = "RESOLVED" ] && [ -f "$RESOLVED_PATH" ]; then
            echo "[+] Acceso directo resuelto a: $RESOLVED_PATH"
            TARGET="$RESOLVED_PATH"
        fi
    fi
fi

# 5. Auto-inicialización del prefijo si es nuevo
if [ ! -f "${WINEPREFIX}/system.reg" ]; then
    echo "[*] Configurando nuevo entorno de Windows unificado..."
    mkdir -p "$WINEPREFIX"
    wineboot -u
    if command -v dxvk-setup &>/dev/null && [ "$RENDERER_IN_USE" != "WineD3D (OpenGL Compatibilidad)" ]; then
        dxvk-setup install -y 2>/dev/null || true
    fi
fi

# 7. Generar archivo DXVK optimizado según la CPU y límite de FPS configurado
if [ "$RENDERER_IN_USE" != "WineD3D (OpenGL Compatibilidad)" ]; then
    export DXVK_CONFIG_FILE="${DIR}/dxvk.conf"
    if [ -x "${DIR}/generar_dxvk_conf.sh" ]; then
        "${DIR}/generar_dxvk_conf.sh"
    fi
else
    unset DXVK_CONFIG_FILE
fi

# 8. Soporte para AMD FSR (FidelityFX Super Resolution - Reescalado de FPS)
if [ "$ACTIVAR_FSR" = "1" ]; then
    export WINE_FULLSCREEN_FSR=1
    export WINE_FULLSCREEN_FSR_STRENGTH="${FSR_STRENGTH:-2}"
fi

# 9. Detección del ejecutable de Wine (personalizado, Wine-TKG o del sistema)
if [ -f "${DIR}/wine-tkg-build/bin/wine" ]; then
    WINE_CMD="${DIR}/wine-tkg-build/bin/wine"
elif command -v wine &> /dev/null; then
    WINE_CMD="wine"
else
    echo "[-] Error: No se encontró ningún binario de Wine instalado en el sistema."
    echo "    Ejecuta el instalador con: ./instalar.sh"
    exit 1
fi

# 10. Uso condicional de GameMode según perfil
GAMEMODE=""
if [ "$PERFIL_RENDIMIENTO" != "ahorro" ] && command -v gamemoderun &> /dev/null; then
    GAMEMODE="gamemoderun"
fi

# 11. Obtener directorio y nombre del archivo
TARGET_DIR="$(cd "$(dirname "$TARGET")" && pwd)"
TARGET_FILE="$(basename "$TARGET")"

# Moverse al directorio donde reside el juego (vital para rutas relativas y DLLs)
cd "$TARGET_DIR"

# Asegurar permisos de escritura para que los mods puedan guardar configs, logs y partidas
[ -w "$TARGET_DIR" ] || chmod -R u+w "$TARGET_DIR" 2>/dev/null || true

# ==============================================================================
# AUTO-ACTIVACIÓN DE MODS, ASI LOADERS, RESHADE, ENB Y TRADUCCIONES
# Detecta automáticamente librerías de mods locales y activa el override nativo (n,b)
# para que funcionen inmediatamente sin tocar winecfg
# ==============================================================================
MOD_HOOKS=("dinput8" "dxgi" "d3d9" "d3d11" "d3d12" "version" "dsound" "winmm" "xinput1_3" "xinput1_4" "xinput9_1_0" "x3daudio1_7" "binkw32" "binkw64" "bink2w64" "dbghelp" "msimg32" "opengl32")
MODS_ACTIVADOS=()

for hook in "${MOD_HOOKS[@]}"; do
    if [ -f "${hook}.dll" ] || [ -f "${hook}.DLL" ]; then
        export WINEDLLOVERRIDES="${hook}=n,b;${WINEDLLOVERRIDES}"
        MODS_ACTIVADOS+=("${hook}.dll")
    fi
done

CANT_ASI=$(ls -1 *.asi scripts/*.asi plugins/*.asi 2>/dev/null | wc -l)

# Detección de resolución para modo Escritorio Virtual
RES_PRIMARIA=$(xrandr 2>/dev/null | grep -E ' connected primary| connected' | head -n 1 | grep -oE '[0-9]+x[0-9]+' | head -n 1)
[ -z "$RES_PRIMARIA" ] && RES_PRIMARIA="1280x720"
DESKTOP_RES="${RESOLUCION_ESCRITORIO:-$RES_PRIMARIA}"

RUN_PREFIX=""
if [ "$ESCRITORIO_VIRTUAL" = "1" ]; then
    RUN_PREFIX="explorer /desktop=Vessel,${DESKTOP_RES}"
fi

echo "[+] Ejecutando con Perfil [${PERFIL_RENDIMIENTO:-maximo}]..."
echo "    - CPU: ${CPU_MODEL} (${CPU_CORES} Hilos)"
echo "    - GPU: ${DETECTED_GPU}"
echo "    - Renderizador: ${RENDERER_IN_USE:-DXVK (Vulkan)}"
echo "    - Fsync/Esync: $([ "$WINEFSYNC" = "1" ] && echo "Fsync Activo" || echo "Esync Activo")"
echo "    - Límite de FPS: ${LIMITE_FPS:-60} FPS"
echo "    - AMD FSR Upscaling: $([ "$ACTIVAR_FSR" = "1" ] && echo "Activado" || echo "Desactivado")"
echo "    - GameMode: $([ -n "$GAMEMODE" ] && echo "Activo" || echo "Inactivo")"
echo "    - Modo Pantalla: $([ "$ESCRITORIO_VIRTUAL" = "1" ] && echo "Escritorio Virtual (${DESKTOP_RES})" || echo "Pantalla Completa Nativa")"
echo "    - Prefijo Wine: ${WINEPREFIX}"
if [ ${#MODS_ACTIVADOS[@]} -gt 0 ] || [ "$CANT_ASI" -gt 0 ]; then
    echo "    - Mods / Hooks Activos: $([ ${#MODS_ACTIVADOS[@]} -gt 0 ] && echo "${MODS_ACTIVADOS[*]}" || echo "Ninguna DLL especial")"
    [ "$CANT_ASI" -gt 0 ] && echo "    - Plugins ASI / Scripts: ${CANT_ASI} archivo(s) detectado(s)"
fi

# Función para limpiar procesos colgados al cerrar la ventana con [X] o Ctrl+C
limpiar_procesos_al_salir() {
    wineserver -k 2>/dev/null || true
}
trap limpiar_procesos_al_salir EXIT INT TERM

if [[ "$TARGET_FILE" =~ \.(msi|MSI)$ ]]; then
    $GAMEMODE "$WINE_CMD" msiexec /i "$TARGET_FILE" "$@"
elif [[ "$TARGET_FILE" =~ \.(lnk|ink|LNK|INK)$ ]]; then
    if [ -n "$RUN_PREFIX" ]; then
        $GAMEMODE "$WINE_CMD" $RUN_PREFIX start /unix "$TARGET" "$@"
    else
        $GAMEMODE "$WINE_CMD" start /unix "$TARGET" "$@"
    fi
else
    if [ -n "$RUN_PREFIX" ]; then
        $GAMEMODE "$WINE_CMD" $RUN_PREFIX "$TARGET_FILE" "$@"
    else
        $GAMEMODE "$WINE_CMD" "$TARGET_FILE" "$@"
    fi
fi
EXIT_STATUS=$?

limpiar_procesos_al_salir
exit $EXIT_STATUS
