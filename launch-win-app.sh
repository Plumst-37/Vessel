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

# 6. Optimización de captura de ratón en 3D (elimina giros bruscos, saltos de cámara y límites de rotación)
if [ -f "${WINEPREFIX}/user.reg" ] && ! grep -q "MouseWarpOverride" "${WINEPREFIX}/user.reg" 2>/dev/null; then
    wine reg add "HKEY_CURRENT_USER\Software\Wine\DirectInput" /v MouseWarpOverride /t REG_SZ /d force /f >/dev/null 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v UseTakeFocus /t REG_SZ /d N /f >/dev/null 2>&1 || true
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
# AUTO-OPTIMIZACIÓN UNIVERSAL DE GRÁFICOS 3D, RESOLUCIÓN Y CERO TEARING
# - Adapta automáticamente la resolución nativa del monitor en cualquier PC
# - Elimina tirones y desgarro horizontal (VSync activo y frame pacing suave)
# - Elimina desenfoque de movimiento molesto (Motion Blur desactivado)
# - Fuerza máxima nitidez de texturas 3D en ángulos (Filtrado Anisotrópico 16x)
# - Optimiza Capcom MT Framework, Rockstar Games, Unreal Engine y motores 3D
# ==============================================================================
auto_optimizar_juegos_3d() {
    # 1. Detectar resolución óptima del monitor principal en cualquier PC (Intel, AMD, NVIDIA)
    local best_res
    if command -v xrandr &>/dev/null; then
        best_res=$(xrandr 2>/dev/null | grep -E ' connected primary' | grep -oE '[0-9]{3,4}x[0-9]{3,4}' | head -n 1)
        [ -z "$best_res" ] && best_res=$(xrandr 2>/dev/null | grep -E '\bconnected\b' | grep -oE '[0-9]{3,4}x[0-9]{3,4}' | head -n 1)
    fi
    if [ -z "$best_res" ]; then
        best_res=$(cat /sys/class/drm/*/modes 2>/dev/null | grep -oE '^[0-9]{3,4}x[0-9]{3,4}' | head -n 1)
    fi
    [ -z "$best_res" ] && best_res="1280x720"

    local best_w best_h
    best_w=$(echo "$best_res" | cut -dx -f1)
    best_h=$(echo "$best_res" | cut -dx -f2)

    # 2. CAPCOM MT FRAMEWORK (Resident Evil 4/5/6, Revelations, DMC4, etc.)
    local capcom_dir="$HOME/Documentos/CAPCOM"
    [ ! -d "$capcom_dir" ] && capcom_dir="${WINEPREFIX}/drive_c/users/${USER}/Documents/CAPCOM"

    if [[ "$TARGET" =~ (Resident\ Evil|BH6|re6|RE6) ]] || [[ "$TARGET_DIR" =~ (Resident\ Evil|BH6|re6|RE6) ]]; then
        mkdir -p "${capcom_dir}/RESIDENT EVIL 6"
        local re6_cfg="${capcom_dir}/RESIDENT EVIL 6/config.ini"
        if [ ! -f "$re6_cfg" ]; then
            cat <<EOF > "$re6_cfg"
[GAME]
MouseBaseSpeed=1.500000
[GRAPHICS]
HDR=DEFAULT
AntiAlias=FXAA3HQ
AltAntiAlias=FXAA3HQ
DeferredLightingLight=APPROXIMATE_SPECULAR
ScreenQuality=HIGH
SLI=OFF
Stereo=OFF
MotionBlurEnabled=OFF
ShadowsQuality=HIGH
FrameRate=VARIABLE
TextureDetail=HIGH
TextureMipLimite=2
[DISPLAY]
Resolution=${best_res}
Aspect=16:9
RefreshRate=60.00Hz
FullScreen=OFF
VSYNC=OFF
[SOUNDS]
SeVoiceNum=128
[CPU]
JobThread=7
RenderingThread=ON
[Window]
MainX=0
MainY=0
EOF
            echo "[+] Configuración de alta fidelidad 3D generada para Resident Evil 6 (${best_res}, nitidez total)."
        fi
    fi

    # Corregir configs existentes de Capcom para máxima calidad 3D, nitidez y cero tirones:
    local dirs_a_buscar=("$capcom_dir")
    [ -d "${TARGET_DIR}/gamedata/optimization" ] && dirs_a_buscar+=("${TARGET_DIR}/gamedata/optimization")
    [ -d "${TARGET_DIR}/optimization" ] && dirs_a_buscar+=("${TARGET_DIR}/optimization")

    for dir_c in "${dirs_a_buscar[@]}"; do
        if [ -d "$dir_c" ]; then
            find "$dir_c" -name "config.ini" 2>/dev/null | while read -r cini; do
                sed -i 's/^FullScreen=ON/FullScreen=OFF/' "$cini" 2>/dev/null || true
                sed -i 's/^VSYNC=ON/VSYNC=OFF/' "$cini" 2>/dev/null || true
                sed -i 's/^MotionBlurEnabled=ON/MotionBlurEnabled=OFF/' "$cini" 2>/dev/null || true
                sed -i "s/^Resolution=.*/Resolution=${best_res}/" "$cini" 2>/dev/null || true
                sed -i 's/^AntiAlias=.*/AntiAlias=FXAA3HQ/' "$cini" 2>/dev/null || true
                sed -i 's/^AltAntiAlias=.*/AltAntiAlias=FXAA3HQ/' "$cini" 2>/dev/null || true
                sed -i 's/^ShadowsDisable=ON/ShadowsDisable=OFF/' "$cini" 2>/dev/null || true
                sed -i 's/^TextureDetail=LOWEST/TextureDetail=HIGH/' "$cini" 2>/dev/null || true
                sed -i 's/^ScreenQuality=LOW/ScreenQuality=HIGH/' "$cini" 2>/dev/null || true
                sed -i 's/^Aspect=DEFAULT/Aspect=16:9/' "$cini" 2>/dev/null || true
                sed -i 's/^MouseBaseSpeed=.*/MouseBaseSpeed=1.500000/' "$cini" 2>/dev/null || true
                sed -i 's/^MainX=.*/MainX=0/' "$cini" 2>/dev/null || true
                sed -i 's/^MainY=.*/MainY=0/' "$cini" 2>/dev/null || true
            done
        fi
    done

    # 3. ROCKSTAR GAMES (GTA V, GTA IV, Max Payne 3, etc.)
    local rsg_dir="$HOME/Documentos/Rockstar Games"
    [ ! -d "$rsg_dir" ] && rsg_dir="${WINEPREFIX}/drive_c/users/${USER}/Documents/Rockstar Games"
    if [ -d "$rsg_dir" ]; then
        find "$rsg_dir" -name "settings.xml" 2>/dev/null | while read -r sxml; do
            sed -i "s/<ScreenWidth value=\"[0-9]*\"/<ScreenWidth value=\"${best_w}\"/" "$sxml" 2>/dev/null || true
            sed -i "s/<ScreenHeight value=\"[0-9]*\"/<ScreenHeight value=\"${best_h}\"/" "$sxml" 2>/dev/null || true
            sed -i 's/<VSync value="[0-9]*"/<VSync value="0"/' "$sxml" 2>/dev/null || true
            sed -i 's/<AnisotropicFiltering value="[0-9]*"/<AnisotropicFiltering value="16"/' "$sxml" 2>/dev/null || true
            sed -i 's/<FXAA_Enabled value="false"/<FXAA_Enabled value="true"/' "$sxml" 2>/dev/null || true
            sed -i 's/<LodScale value="0.000000"/<LodScale value="1.000000"/' "$sxml" 2>/dev/null || true
            if [ -n "$GPU_NAME" ]; then
                sed -i "s|<VideoCardDescription>.*</VideoCardDescription>|<VideoCardDescription>${GPU_NAME}</VideoCardDescription>|" "$sxml" 2>/dev/null || true
            fi
        done
    fi

    # 4. UNREAL ENGINE 1/2/2.5 (SWAT 4, Deus Ex, Bioshock, etc.)
    local target_system_dir="$TARGET_DIR"
    [ -d "${TARGET_DIR}/System" ] && target_system_dir="${TARGET_DIR}/System"
    [ -d "${TARGET_DIR}/Content/System" ] && target_system_dir="${TARGET_DIR}/Content/System"
    find "$target_system_dir" -maxdepth 1 -name "*.ini" 2>/dev/null | while read -r ueini; do
        if grep -q "\[WinDrv.WindowsClient\]" "$ueini" 2>/dev/null; then
            sed -i "s/^FullscreenViewportX=[0-9]*/FullscreenViewportX=${best_w}/" "$ueini" 2>/dev/null || true
            sed -i "s/^FullscreenViewportY=[0-9]*/FullscreenViewportY=${best_h}/" "$ueini" 2>/dev/null || true
            sed -i "s/^WindowedViewportX=[0-9]*/WindowedViewportX=${best_w}/" "$ueini" 2>/dev/null || true
            sed -i "s/^WindowedViewportY=[0-9]*/WindowedViewportY=${best_h}/" "$ueini" 2>/dev/null || true
        fi
        if grep -q "\[D3DDrv.D3DRenderDevice\]" "$ueini" 2>/dev/null; then
            sed -i 's/^UseVSync=True/UseVSync=False/' "$ueini" 2>/dev/null || true
            sed -i 's/^LevelOfAnisotropy=[0-9]*/LevelOfAnisotropy=16/' "$ueini" 2>/dev/null || true
            sed -i 's/^Use16bit=True/Use16bit=False/' "$ueini" 2>/dev/null || true
            sed -i 's/^Use16bitTextures=True/Use16bitTextures=False/' "$ueini" 2>/dev/null || true
            sed -i 's/^ReduceMouseLag=False/ReduceMouseLag=True/' "$ueini" 2>/dev/null || true
        fi
    done
}
auto_optimizar_juegos_3d

# ==============================================================================
# AUTO-ACTIVACIÓN DE MODS, ASI LOADERS, RESHADE, ENB Y TRADUCCIONES
# Detecta automáticamente librerías de mods locales y activa el override nativo (n,b)
# para que funcionen inmediatamente sin tocar winecfg
# ==============================================================================
MOD_HOOKS=("ddraw" "d3d8" "d3d9" "d3d11" "d3d12" "dxgi" "dinput8" "dinput" "dsound" "dplayx" "dpnet" "version" "winmm" "xinput1_3" "xinput1_4" "xinput9_1_0" "x3daudio1_7" "binkw32" "binkw64" "bink2w64" "dbghelp" "msimg32" "opengl32")
MODS_ACTIVADOS=()

for hook in "${MOD_HOOKS[@]}"; do
    if [ -f "${hook}.dll" ] || [ -f "${hook}.DLL" ]; then
        export WINEDLLOVERRIDES="${hook}=n,b;${WINEDLLOVERRIDES}"
        MODS_ACTIVADOS+=("${hook}.dll")
    fi
done

CANT_ASI=$(ls -1 *.asi scripts/*.asi plugins/*.asi 2>/dev/null | wc -l)

# Detección de resolución para modo Escritorio Virtual
RES_PRIMARIA=$(xrandr 2>/dev/null | grep -E ' connected primary' | grep -oE '[0-9]{3,4}x[0-9]{3,4}' | head -n 1)
[ -z "$RES_PRIMARIA" ] && RES_PRIMARIA=$(xrandr 2>/dev/null | grep -E '\bconnected\b' | grep -oE '[0-9]{3,4}x[0-9]{3,4}' | head -n 1)
[ -z "$RES_PRIMARIA" ] && RES_PRIMARIA=$(cat /sys/class/drm/*/modes 2>/dev/null | grep -oE '^[0-9]{3,4}x[0-9]{3,4}' | head -n 1)
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
