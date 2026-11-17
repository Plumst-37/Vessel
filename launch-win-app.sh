#!/bin/bash
# ==============================================================================
# LANZADOR UNIVERSAL OPTIMIZADO PARA APLICACIONES Y JUEGOS DE WINDOWS
# Compatible con cualquier arquitectura de PC (Intel, AMD, NVIDIA, Integradas)
# Prefijo Wine Unificado con Compatibilidad Total de Gráficos y Videos
# ==============================================================================

# Autoprotección multi-shell: Si se ejecuta con dash, sh, zsh o fish, cambiar inmediatamente a bash
if [ -z "$BASH_VERSION" ]; then
    if command -v bash >/dev/null 2>&1; then
        if [ -f "$0" ]; then
            exec bash "$0" "$@"
        fi
    fi
fi

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
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

# 4.0 Normalizar rutas relativas y resolución automática de GameRanger predeterminado
if [[ "$TARGET" != /* ]] && [ -f "${DIR}/${TARGET}" ]; then
    TARGET="${DIR}/${TARGET}"
fi
if [ ! -f "$TARGET" ] && [[ "$TARGET" =~ [Gg]ame[Rr]anger ]]; then
    FOUND_GR=$(find "${DIR}" "${WINEPREFIX}/drive_c" -name "GameRanger.exe" 2>/dev/null | head -n 1)
    if [ -n "$FOUND_GR" ] && [ -f "$FOUND_GR" ]; then
        TARGET="$FOUND_GR"
    elif [ -f "${DIR}/GameRangerSetup.exe" ]; then
        echo "[*] GameRanger no encontrado en este equipo. Ejecutando instalador predeterminado..."
        wine "${DIR}/GameRangerSetup.exe" 2>/dev/null || true
        FOUND_GR=$(find "${WINEPREFIX}/drive_c" -name "GameRanger.exe" 2>/dev/null | head -n 1)
        [ -n "$FOUND_GR" ] && TARGET="$FOUND_GR"
    fi
fi

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

# 4.2 Resolver scripts por lotes (.bat o .cmd) para omitir bucles infinitos de CPU
if [[ "$TARGET" =~ \.([bB][aA][tT]|[cC][mM][dD])$ ]] && [ -f "$TARGET" ]; then
    echo "[*] Script por lotes (.bat/.cmd) detectado: $(basename "$TARGET")."
    if [ -f "${DIR}/resolver_bat.py" ]; then
        RESOLVED_BAT=$(python3 "${DIR}/resolver_bat.py" "$TARGET" 2>/dev/null || true)
        BAT_STATUS=$(echo "$RESOLVED_BAT" | grep '^STATUS=' | cut -d= -f2-)
        BAT_PATH=$(echo "$RESOLVED_BAT" | grep '^RESOLVED_PATH=' | cut -d= -f2-)
        if [ "$BAT_STATUS" = "RESOLVED" ] && [ -f "$BAT_PATH" ]; then
            echo "[+] Ejecutable real detectado y aislado para máximo rendimiento: $BAT_PATH"
            echo "[+] Omitiendo bucles innecesarios de Windows (tasklist/wmic) para liberar el 100% de la CPU."
            TARGET="$BAT_PATH"
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

# 6. Configuración de ratón ultra-fluido (movimiento libre 1:1 por toda la pantalla sin bloqueos)
wine reg add "HKEY_CURRENT_USER\Software\Wine\DirectInput" /v MouseWarpOverride /t REG_SZ /d enable /f >/dev/null 2>&1 || true
wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v UseTakeFocus /t REG_SZ /d Y /f >/dev/null 2>&1 || true
wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v GrabFullscreen /t REG_SZ /d Y /f >/dev/null 2>&1 || true
wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v Decorated /t REG_SZ /d Y /f >/dev/null 2>&1 || true
wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v Managed /t REG_SZ /d Y /f >/dev/null 2>&1 || true

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

# 11.1 Configuración específica para el cliente de lobby GameRanger
if [[ "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]]; then
    # GameRanger es una aplicación de escritorio/chat con interfaz Chromium CEF / ANGLE embebida.
    # Sus subventanas web no son superficies 3D exclusivas y fallan con swapchains Vulkan (VK_ERROR_OUT_OF_HOST_MEMORY).
    # Desactivamos DXVK para GameRanger y usamos WineD3D nativo, eliminando cualquier cuelgue de UI.
    export RENDERER_IN_USE="WineD3D (Lobby Compatibilidad)"
    export PROTON_USE_WINED3D=1
    export WINEDLLOVERRIDES="$(echo "$WINEDLLOVERRIDES" | sed -E 's/(dxgi|d3d11|d3d10core|d3d9)=n/\1=b/g')"
    unset DXVK_CONFIG_FILE
    unset DXVK_STATE_CACHE_PATH
    unset DXVK_ASYNC
    unset DXVK_GPLASYNCCACHE
fi

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

    # Calcular relación de aspecto matemática exacta según la pantalla
    local best_aspect="DEFAULT"
    if [ -n "$best_w" ] && [ -n "$best_h" ] && [ "$best_h" -gt 0 ]; then
        local ratio_x100=$(( best_w * 100 / best_h ))
        if [ "$ratio_x100" -ge 170 ] && [ "$ratio_x100" -le 185 ]; then
            best_aspect="16:9"
        elif [ "$ratio_x100" -ge 155 ] && [ "$ratio_x100" -le 165 ]; then
            best_aspect="16:10"
        elif [ "$ratio_x100" -ge 130 ] && [ "$ratio_x100" -le 138 ]; then
            best_aspect="4:3"
        fi
    fi

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
AntiAlias=NONE
AltAntiAlias=FXAA3HQ
DeferredLightingLight=APPROXIMATE_SPECULAR
ScreenQuality=HIGH
SLI=OFF
Stereo=OFF
MotionBlurEnabled=OFF
ShadowsQuality=MEDIUM
FrameRate=VARIABLE
TextureDetail=HIGH
TextureMipLimite=0
[DISPLAY]
Resolution=${best_res}
Aspect=${best_aspect}
RefreshRate=60.00Hz
FullScreen=ON
VSYNC=OFF
[SOUNDS]
SeVoiceNum=128
[CPU]
JobThread=3
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
                sed -i 's/^FullScreen=OFF/FullScreen=ON/' "$cini" 2>/dev/null || true
                sed -i 's/^VSYNC=ON/VSYNC=OFF/' "$cini" 2>/dev/null || true
                sed -i 's/^MotionBlurEnabled=ON/MotionBlurEnabled=OFF/' "$cini" 2>/dev/null || true
                
                # Calibrar resolución universalmente: preservar si es compatible, o ajustar a la pantalla si no existe o es inválida
                local cur_res
                cur_res=$(grep -E '^Resolution=' "$cini" 2>/dev/null | cut -d'=' -f2 | tr -d '\r\n ')
                if [ -z "$cur_res" ] || [ "$cur_res" = "Unknown" ] || [ "$cur_res" = "0x0" ] || ! echo "$cur_res" | grep -qE '^[0-9]+x[0-9]+$'; then
                    sed -i "s/^Resolution=.*/Resolution=${best_res}/" "$cini" 2>/dev/null || true
                elif command -v xrandr &>/dev/null && ! xrandr 2>/dev/null | grep -q "\b${cur_res}\b"; then
                    # Si la resolución guardada no existe en este monitor (evita ERR09: Unsupported function de Capcom)
                    sed -i "s/^Resolution=.*/Resolution=${best_res}/" "$cini" 2>/dev/null || true
                fi
                
                sed -i 's/^RefreshRate=.*/RefreshRate=60.00Hz/' "$cini" 2>/dev/null || true
                sed -i "s/^Aspect=.*/Aspect=${best_aspect}/" "$cini" 2>/dev/null || true
                sed -i 's/^AntiAlias=.*/AntiAlias=NONE/' "$cini" 2>/dev/null || true
                sed -i 's/^AltAntiAlias=.*/AltAntiAlias=FXAA3HQ/' "$cini" 2>/dev/null || true
                sed -i 's/^ShadowsDisable=ON/ShadowsDisable=OFF/' "$cini" 2>/dev/null || true
                sed -i 's/^ShadowsQuality=HIGH/ShadowsQuality=MEDIUM/' "$cini" 2>/dev/null || true
                sed -i 's/^ShadowsQuality=MIDDLE/ShadowsQuality=MEDIUM/' "$cini" 2>/dev/null || true
                sed -i 's/^JobThread=.*/JobThread=3/' "$cini" 2>/dev/null || true
                sed -i 's/^RenderingThread=OFF/RenderingThread=ON/' "$cini" 2>/dev/null || true
                sed -i 's/^TextureDetail=LOWEST/TextureDetail=HIGH/' "$cini" 2>/dev/null || true
                sed -i 's/^ScreenQuality=LOW/ScreenQuality=HIGH/' "$cini" 2>/dev/null || true
                sed -i 's/^TextureMipLimite=.*/TextureMipLimite=0/' "$cini" 2>/dev/null || true
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
            if grep -q '<ScreenWidth value="0"' "$sxml" 2>/dev/null || ! grep -q '<ScreenWidth' "$sxml" 2>/dev/null; then
                sed -i "s/<ScreenWidth value=\"[0-9]*\"/<ScreenWidth value=\"${best_w}\"/" "$sxml" 2>/dev/null || true
                sed -i "s/<ScreenHeight value=\"[0-9]*\"/<ScreenHeight value=\"${best_h}\"/" "$sxml" 2>/dev/null || true
            fi
            sed -i 's/<VSync value="[0-9]*"/<VSync value="0"/' "$sxml" 2>/dev/null || true
            sed -i 's/<Windowed value="[0-9]*"/<Windowed value="2"/' "$sxml" 2>/dev/null || true
            sed -i 's/<PauseOnFocusLoss value="[0-9]*"/<PauseOnFocusLoss value="0"/' "$sxml" 2>/dev/null || true
            sed -i 's/<AspectRatio value="[0-9]*"/<AspectRatio value="0"/' "$sxml" 2>/dev/null || true
            sed -i 's/<AnisotropicFiltering value="[0-9]*"/<AnisotropicFiltering value="16"/' "$sxml" 2>/dev/null || true
            sed -i 's/<FXAA_Enabled value="false"/<FXAA_Enabled value="true"/' "$sxml" 2>/dev/null || true
            sed -i 's/<LodScale value="0.000000"/<LodScale value="1.000000"/' "$sxml" 2>/dev/null || true
            sed -i 's/<PedLodBias value="0.000000"/<PedLodBias value="0.200000"/' "$sxml" 2>/dev/null || true
            sed -i 's/<VehicleLodBias value="0.000000"/<VehicleLodBias value="0.200000"/' "$sxml" 2>/dev/null || true
            if [ -n "$GPU_NAME" ]; then
                sed -i "s|<VideoCardDescription>.*</VideoCardDescription>|<VideoCardDescription>${GPU_NAME}</VideoCardDescription>|" "$sxml" 2>/dev/null || true
            fi
        done
    fi

    # 3.1 OPTIMIZACIÓN ESPECÍFICA GTA V (Carga rápida sin cuelgues ni saturación de hilos)
    if [[ "$TARGET_FILE" =~ (GTA5|PlayGTAV|gta5) ]] || [[ "$TARGET_DIR" =~ (GTA|gta) ]]; then
        local gta_cmdline="${TARGET_DIR}/commandline.txt"
        if [ -f "$gta_cmdline" ]; then
            sed -i 's/^-FrameQueueLimit 0/-FrameQueueLimit 1/' "$gta_cmdline" 2>/dev/null || true
            sed -i '/^-hdr/d' "$gta_cmdline" 2>/dev/null || true
            grep -q '^-StraightIntoFreemode' "$gta_cmdline" || echo "-StraightIntoFreemode" >> "$gta_cmdline"
            grep -q '^-scOfflineOnly' "$gta_cmdline" || echo "-scOfflineOnly" >> "$gta_cmdline"
            grep -q '^-novsync' "$gta_cmdline" || echo "-novsync" >> "$gta_cmdline"
            grep -q '^-disablespecular' "$gta_cmdline" || echo "-disablespecular" >> "$gta_cmdline"
            echo "[+] Archivo commandline.txt de GTA V optimizado (Carga inmediata sin bloqueos de render thread)."
        fi
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
MOD_HOOKS=("ddraw" "d3d8" "d3d9" "d3d11" "d3d12" "dxgi" "dinput8" "dinput" "dsound" "dplayx" "dpnet" "version" "winmm" "vorbisfile" "xinput1_3" "xinput1_4" "xinput9_1_0" "x3daudio1_7" "binkw32" "binkw64" "bink2w64" "dbghelp" "msimg32" "opengl32")
MODS_ACTIVADOS=()

for hook in "${MOD_HOOKS[@]}"; do
    if [ -f "${hook}.dll" ] || [ -f "${hook}.DLL" ]; then
        export WINEDLLOVERRIDES="${hook}=n,b;${WINEDLLOVERRIDES}"
        MODS_ACTIVADOS+=("${hook}.dll")
    fi
done

CANT_ASI=$(ls -1 *.asi scripts/*.asi plugins/*.asi 2>/dev/null | wc -l)

# Modo Pantalla Nativo Directo en Hardware (sin capas virtuales)
ESCRITORIO_VIRTUAL="0"
RUN_PREFIX=""

echo "[+] Ejecutando con Perfil [${PERFIL_RENDIMIENTO:-maximo}]..."
echo "    - CPU: ${CPU_MODEL} (${CPU_CORES} Hilos)"
echo "    - GPU: ${DETECTED_GPU}"
echo "    - Renderizador: ${RENDERER_IN_USE:-DXVK (Vulkan)}"
echo "    - Fsync/Esync: $([ "$WINEFSYNC" = "1" ] && echo "Fsync Activo" || echo "Esync Activo")"
echo "    - Límite de FPS: ${LIMITE_FPS:-60} FPS"
echo "    - AMD FSR Upscaling: $([ "$ACTIVAR_FSR" = "1" ] && echo "Activado" || echo "Desactivado")"
echo "    - GameMode: $([ -n "$GAMEMODE" ] && echo "Activo" || echo "Inactivo")"
echo "    - Modo Pantalla: Pantalla Completa Nativa Directa (Hardware)"
echo "    - Caché de Shaders: NVMe SSD (~/.cache/dxvk)"
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

# Sincronizar buffers de disco y optimizar prioridad de proceso
sync 2>/dev/null || true
renice -n -5 $$ 2>/dev/null || true

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
