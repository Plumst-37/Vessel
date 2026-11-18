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

# Limpiar cualquier texto o pulsación residual de forma segura sin provocar bloqueos de señal SIGTTIN
[ -t 0 ] && command -v tcflush >/dev/null 2>&1 && tcflush 0 2>/dev/null || true

# Ampliar límite de descriptores de archivos para juegos pesados (GTA V, RE4, etc.)
ulimit -n 1048576 2>/dev/null || ulimit -n 65535 2>/dev/null || true

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DB_FILE="${DIR}/programas.db"

# 1. Cargar preferencias del usuario y detección de hardware universal
[ -f "${DIR}/config_rendimiento.cfg" ] && source "${DIR}/config_rendimiento.cfg"
source "${DIR}/hardware_detect.sh"

# 2. Aplicar optimizaciones dinámicas para el hardware real del equipo
aplicar_entorno_hardware

# 3. Procesar banderas opcionales (prefijo dedicado, modo aislado y runner custom)
CUSTOM_PREFIX=""
FORCE_ISOLATED=0
CUSTOM_RUNNER=""
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            CUSTOM_PREFIX="$2"
            shift 2
            ;;
        --isolated)
            FORCE_ISOLATED=1
            shift
            ;;
        --runner)
            CUSTOM_RUNNER="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "Uso: $0 [--prefix /ruta/al/prefijo] [--isolated] [--runner /ruta/a/wine] /ruta/al/programa.exe [argumentos]"
    exit 1
fi

TARGET="$1"
shift || true

# 4. Definir la ruta del WINEPREFIX (Soporte Dual: Prefijo Compartido o Prefijo Aislado por Juego)
if [ -n "$CUSTOM_PREFIX" ]; then
    export WINEPREFIX="$CUSTOM_PREFIX"
else
    # Comprobar en base de datos si el juego tiene configurado prefijo aislado
    PREF_TYPE="compartido"
    for db in "${DIR}/programas_usuario.db" "${DIR}/programas.db"; do
        if [ -f "$db" ]; then
            matched_line=$(grep -F "$TARGET" "$db" 2>/dev/null | head -n 1)
            [ -z "$matched_line" ] && matched_line=$(grep -F "$(basename "$TARGET")" "$db" 2>/dev/null | head -n 1)
            if [ -n "$matched_line" ]; then
                db_ptype=$(echo "$matched_line" | cut -d'|' -f3 | tr -d '\r\n ')
                [ -n "$db_ptype" ] && PREF_TYPE="$db_ptype"
                break
            fi
        fi
    done

    if [ "$PREF_TYPE" = "aislado" ] || [ "$FORCE_ISOLATED" -eq 1 ]; then
        SAFE_BASE=$(basename "$TARGET" | sed -E 's/[^a-zA-Z0-9_-]/_/g')
        HASH_RUTA=$(printf "%s" "$TARGET" | md5sum 2>/dev/null | cut -c1-6 || echo "000000")
        if [ -d "${DIR}/wineprefixes/${SAFE_BASE}" ] && [ ! -d "${DIR}/wineprefixes/${SAFE_BASE}_${HASH_RUTA}" ]; then
            SAFE_APP_ID="${SAFE_BASE}"
        else
            SAFE_APP_ID="${SAFE_BASE}_${HASH_RUTA}"
        fi
        export WINEPREFIX="${DIR}/wineprefixes/${SAFE_APP_ID}"
        echo "[🛡️] Prefijo Wine Aislado activo para: $(basename "$TARGET") [ID: ${SAFE_APP_ID}]"
    else
        export WINEPREFIX="${DIR}/wineprefix"
    fi
fi

# 4.0 Auto-reparación transparente de rutas inexistentes o movidas (ej. carpetas ZIP extraídas)
if [ ! -f "$TARGET" ] && [[ ! "$TARGET" =~ [Gg]ame[Rr]anger ]]; then
    CANDIDATE_PATH=""
    # 1. Probar eliminando /ZIP/ o /zip/ de la ruta
    NO_ZIP=$(echo "$TARGET" | sed -E 's|/[zZ][iI][pP]/|/|g')
    if [ -f "$NO_ZIP" ]; then
        CANDIDATE_PATH="$NO_ZIP"
    fi

    # 2. Si no existe, buscar en directorios padres o hermanos cercanos
    if [ -z "$CANDIDATE_PATH" ]; then
        BASE_NAME=$(basename "$TARGET")
        PARENT_DIR=$(dirname "$TARGET")
        SEARCH_ROOT=$(dirname "$PARENT_DIR" 2>/dev/null || echo "")
        if [ -d "$SEARCH_ROOT" ]; then
            FOUND=$(find "$SEARCH_ROOT" -maxdepth 4 -name "$BASE_NAME" 2>/dev/null | head -n 1)
            [ -n "$FOUND" ] && CANDIDATE_PATH="$FOUND"
        fi
    fi

    # 3. Si se encontró la ruta real, auto-reparar la base de datos y actualizar TARGET
    if [ -n "$CANDIDATE_PATH" ] && [ -f "$CANDIDATE_PATH" ]; then
        echo "[+] Ruta de juego reparada automáticamente:"
        echo "    - Anterior: $TARGET"
        echo "    - Nueva   : $CANDIDATE_PATH"
        for db in "${DIR}/programas_usuario.db" "${DIR}/programas.db"; do
            if [ -f "$db" ]; then
                sed -i "s|${TARGET}|${CANDIDATE_PATH}|g" "$db" 2>/dev/null || true
            fi
        done
        TARGET="$CANDIDATE_PATH"
    fi
fi

# 4.0.1 Normalizar rutas relativas y resolución automática de GameRanger predeterminado
if [[ "$TARGET" != /* ]] && [ -f "${DIR}/${TARGET}" ]; then
    TARGET="${DIR}/${TARGET}"
fi

# 4.0.2 Priorizar el binario óptimo (.exe) sobre scripts .bat/.cmd para evitar cuelgues de wmic/cacls en Wine
if [[ "$TARGET" =~ \.([bB][aA][tT]|[cC][mM][dD])$ ]]; then
    BAT_DIR=$(dirname "$TARGET")
    for cand in "GTA5.exe" "PlayGTAV.exe" "gta_sa.exe" "speed.exe" "BH6.exe" "re4.exe" "biohazard4.exe" "Swat4.exe"; do
        FOUND_EXE=$(find "$BAT_DIR" -maxdepth 3 -iname "$cand" 2>/dev/null | head -n 1)
        if [ -n "$FOUND_EXE" ] && [ -f "$FOUND_EXE" ]; then
            echo "[+] Binario nativo óptimo detectado: $(basename "$FOUND_EXE") (priorizado sobre $(basename "$TARGET"))"
            TARGET="$FOUND_EXE"
            break
        fi
    done
fi

# 4.0.3 Redirigir wrappers/launchers inestables al binario principal del juego (ej. PlayGTAV.exe -> GTA5.exe)
if [[ "$TARGET" =~ PlayGTAV\.exe$ ]]; then
    PLAY_DIR=$(dirname "$TARGET")
    if [ -f "${PLAY_DIR}/GTA5.exe" ]; then
        echo "[+] Redirigiendo launcher PlayGTAV.exe -> Binario principal estable: GTA5.exe"
        TARGET="${PLAY_DIR}/GTA5.exe"
    fi
fi
if [[ "$TARGET" =~ [Gg]ame[Rr]anger ]] || [ ! -f "$TARGET" ]; then
    if [[ "$TARGET" =~ [Gg]ame[Rr]anger ]]; then
        TARGET_USER="${SUDO_USER:-$USER}"
        GR_ROAMING="${WINEPREFIX}/drive_c/users/${TARGET_USER}/AppData/Roaming/GameRanger/GameRanger"
        GR_PREFS="${WINEPREFIX}/drive_c/users/${TARGET_USER}/AppData/Roaming/GameRanger/GameRanger Prefs"
        FOUND_GR=$(find "${WINEPREFIX}/drive_c/users" -name "GameRanger.exe" 2>/dev/null | head -n 1)
        [ -z "$FOUND_GR" ] && [ -f "${WINEPREFIX}/drive_c/Program Files/GameRanger/GameRanger.exe" ] && FOUND_GR="${WINEPREFIX}/drive_c/Program Files/GameRanger/GameRanger.exe"
        if [ -z "$FOUND_GR" ] && [ -f "${DIR}/GameRanger/GameRanger.exe" ]; then
            mkdir -p "$GR_ROAMING" "$GR_PREFS" "${WINEPREFIX}/drive_c/Program Files/GameRanger"
            cp -r "${DIR}/GameRanger"/* "$GR_ROAMING/" 2>/dev/null || true
            cp -r "${DIR}/GameRanger"/* "${WINEPREFIX}/drive_c/Program Files/GameRanger/" 2>/dev/null || true
            FOUND_GR="${GR_ROAMING}/GameRanger.exe"
        fi

        # Restaurar preferencias y sesión guardada del usuario en cualquier perfil existente
        if [ -d "${DIR}/.gameranger_prefs_backup" ]; then
            mkdir -p "$GR_PREFS"
            if [ ! -s "${GR_PREFS}/Settings" ] || ! grep -q "SessMail" "${GR_PREFS}/Settings" 2>/dev/null; then
                cp -rf "${DIR}/.gameranger_prefs_backup"/* "$GR_PREFS/" 2>/dev/null || true
            fi
            for u_dir in "${WINEPREFIX}/drive_c/users"/*; do
                if [ -d "$u_dir" ] && [ "$(basename "$u_dir")" != "Public" ]; then
                    u_prefs="${u_dir}/AppData/Roaming/GameRanger/GameRanger Prefs"
                    mkdir -p "$u_prefs"
                    if [ ! -s "${u_prefs}/Settings" ] || ! grep -q "SessMail" "${u_prefs}/Settings" 2>/dev/null; then
                        cp -rf "${DIR}/.gameranger_prefs_backup"/* "$u_prefs/" 2>/dev/null || true
                    fi
                fi
            done
        fi

        if [ -n "$FOUND_GR" ] && [ -f "$FOUND_GR" ]; then
            TARGET="$FOUND_GR"
        elif [ -f "${DIR}/GameRangerSetup.exe" ]; then
            echo "[*] Instalando GameRanger oficial en el entorno..."
            WINEPREFIX="${WINEPREFIX}" WINEDLLOVERRIDES="winemenubuilder.exe=d;dxgi=b;d3d11=b;d3d10core=b;d3d9=b;" wine "${DIR}/GameRangerSetup.exe" 2>/dev/null || true
            FOUND_GR=$(find "${WINEPREFIX}/drive_c" -name "GameRanger.exe" 2>/dev/null | head -n 1)
            [ -n "$FOUND_GR" ] && TARGET="$FOUND_GR"
        elif command -v curl &>/dev/null; then
            echo "[*] Descargando GameRanger oficial..."
            curl -fsSL https://www.gameranger.com/download/GameRangerSetup.exe -o "${DIR}/GameRangerSetup.exe" 2>/dev/null || true
            if [ -f "${DIR}/GameRangerSetup.exe" ]; then
                WINEPREFIX="${WINEPREFIX}" WINEDLLOVERRIDES="winemenubuilder.exe=d;dxgi=b;d3d11=b;d3d10core=b;d3d9=b;" wine "${DIR}/GameRangerSetup.exe" 2>/dev/null || true
                FOUND_GR=$(find "${WINEPREFIX}/drive_c" -name "GameRanger.exe" 2>/dev/null | head -n 1)
                [ -n "$FOUND_GR" ] && TARGET="$FOUND_GR"
            fi
        fi
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

# 5. Detección de entorno gráfico: Wayland vs X11
IS_WAYLAND=0
if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    IS_WAYLAND=1
    export SDL_VIDEODRIVER="wayland,x11"
fi

# 6. Detección y activación del ejecutable de Wine (Runner portable, Lutris, Heroic, Wine-TKG o del sistema)
WINE_CMD=""
RUNNER_LABEL=""

if [ -n "$CUSTOM_RUNNER" ] && [ -x "$CUSTOM_RUNNER" ]; then
    WINE_CMD="$CUSTOM_RUNNER"
    RUNNER_LABEL="Personalizado ($(basename "$WINE_CMD"))"
elif [ -n "$VESSEL_WINE_RUNNER" ] && [ -x "$VESSEL_WINE_RUNNER" ]; then
    WINE_CMD="$VESSEL_WINE_RUNNER"
    RUNNER_LABEL="Variable de Entorno ($(basename "$WINE_CMD"))"
fi

# Runners portables locales en runners/ (Wine-GE, Kron4ek, Proton-GE, etc.)
if [ -z "$WINE_CMD" ] && [ -d "${DIR}/runners" ]; then
    for r_cand in "${DIR}/runners"/*/bin/wine "${DIR}/runners"/wine/bin/wine; do
        if [ -f "$r_cand" ] && [ -x "$r_cand" ]; then
            WINE_CMD="$r_cand"
            RUNNER_LABEL="Portable ($(basename "$(dirname "$(dirname "$r_cand")")"))"
            break
        fi
    done
fi

# Runners de Lutris instalados en el sistema del usuario
if [ -z "$WINE_CMD" ] && [ -d "$HOME/.local/share/lutris/runners/wine" ]; then
    for l_cand in "$HOME/.local/share/lutris/runners/wine"/*/bin/wine; do
        if [ -f "$l_cand" ] && [ -x "$l_cand" ]; then
            WINE_CMD="$l_cand"
            RUNNER_LABEL="Lutris ($(basename "$(dirname "$(dirname "$l_cand")")"))"
            break
        fi
    done
fi

# Runners de Heroic Games Launcher
if [ -z "$WINE_CMD" ]; then
    for h_dir in "$HOME/.config/heroic/tools/wine" "$HOME/.config/heroic/tools/proton"; do
        if [ -d "$h_dir" ]; then
            for h_cand in "$h_dir"/*/bin/wine; do
                if [ -f "$h_cand" ] && [ -x "$h_cand" ]; then
                    WINE_CMD="$h_cand"
                    RUNNER_LABEL="Heroic ($(basename "$(dirname "$(dirname "$h_cand")")"))"
                    break 2
                fi
            done
        fi
    done
fi

# Wine-TKG compilado localmente
if [ -z "$WINE_CMD" ] && [ -f "${DIR}/wine-tkg-build/bin/wine" ]; then
    WINE_CMD="${DIR}/wine-tkg-build/bin/wine"
    RUNNER_LABEL="Wine-TKG Custom Build"
fi

# Fallback a Wine del sistema
if [ -z "$WINE_CMD" ] && command -v wine &> /dev/null; then
    WINE_CMD="wine"
    RUNNER_LABEL="Wine del Sistema ($(wine --version 2>/dev/null || echo "Estándar"))"
fi

if [ -z "$WINE_CMD" ]; then
    echo "[-] Error: No se encontró ningún binario de Wine instalado en el sistema ni en runners/."
    echo "    Ejecuta el instalador con: ./instalar.sh"
    exit 1
fi

# Configuración de variables de entorno para runners portables
WINESERVER_CMD="wineserver"
if [ "$WINE_CMD" != "wine" ]; then
    RUNNER_BIN_DIR="$(dirname "$WINE_CMD")"
    RUNNER_BASE_DIR="$(cd "$RUNNER_BIN_DIR/.." && pwd)"
    export PATH="${RUNNER_BIN_DIR}:${PATH}"
    [ -x "${RUNNER_BIN_DIR}/wineserver" ] && export WINESERVER="${RUNNER_BIN_DIR}/wineserver" && WINESERVER_CMD="${RUNNER_BIN_DIR}/wineserver"
    [ -x "${RUNNER_BIN_DIR}/wine64" ] && export WINE64="${RUNNER_BIN_DIR}/wine64"
    [ -x "${RUNNER_BIN_DIR}/wine" ] && export WINELOADER="${RUNNER_BIN_DIR}/wine"

    if [ -d "${RUNNER_BASE_DIR}/lib64" ] || [ -d "${RUNNER_BASE_DIR}/lib" ]; then
        export LD_LIBRARY_PATH="${RUNNER_BASE_DIR}/lib64:${RUNNER_BASE_DIR}/lib:${LD_LIBRARY_PATH:-}"
    fi
fi

# 7. Auto-inicialización del prefijo con wineboot nativo y dosdevices íntegros
find "${WINEPREFIX}/drive_c/windows" -xtype l -delete 2>/dev/null || true
if [ ! -f "${WINEPREFIX}/system.reg" ]; then
    echo "[*] Creando sandbox limpio e íntegro para el juego..."
    mkdir -p "$WINEPREFIX"
    WINEPREFIX="$WINEPREFIX" "$WINE_CMD" wineboot -u >/dev/null 2>&1 || true
    mkdir -p "${WINEPREFIX}/dosdevices"
    [ ! -e "${WINEPREFIX}/dosdevices/c:" ] && ln -s ../drive_c "${WINEPREFIX}/dosdevices/c:" 2>/dev/null || true
    [ ! -e "${WINEPREFIX}/dosdevices/z:" ] && ln -s / "${WINEPREFIX}/dosdevices/z:" 2>/dev/null || true
    if command -v dxvk-setup &>/dev/null && [ "$RENDERER_IN_USE" != "WineD3D (OpenGL Compatibilidad)" ]; then
        dxvk-setup install -y 2>/dev/null || true
    fi
fi

# 8. Configuración de pantalla completa universal, ratón ultra-fluido, estabilidad 3D y supresión de crash dialogs
if [ ! -f "${WINEPREFIX}/.vessel_reg_v4" ]; then
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\WineDbg" /v ShowCrashDialog /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\AeDebug" /v Auto /t REG_SZ /d 0 /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\DirectInput" /v MouseWarpOverride /t REG_SZ /d enable /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v UseTakeFocus /t REG_SZ /d N /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v GrabFullscreen /t REG_SZ /d Y /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v Decorated /t REG_SZ /d N /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v Managed /t REG_SZ /d Y /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v csmt /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v StrictDrawOrdering /t REG_SZ /d disabled /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v AlwaysOffscreen /t REG_SZ /d enabled /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v CheckDepthStencil /t REG_SZ /d enabled /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\X11 Driver" /v Decorated /t REG_SZ /d Y /f >/dev/null 2>&1 || true
    touch "${WINEPREFIX}/.vessel_reg_v4" 2>/dev/null || true
fi

# 9. Generar archivo DXVK optimizado según la CPU y límite de FPS configurado
if [ "$RENDERER_IN_USE" != "WineD3D (OpenGL Compatibilidad)" ]; then
    export DXVK_CONFIG_FILE="${DIR}/dxvk.conf"
    if [ -x "${DIR}/generar_dxvk_conf.sh" ]; then
        "${DIR}/generar_dxvk_conf.sh"
    fi
else
    unset DXVK_CONFIG_FILE
fi

# 10. Soporte para AMD FSR (FidelityFX Super Resolution - Reescalado de FPS)
if [ "$ACTIVAR_FSR" = "1" ]; then
    export WINE_FULLSCREEN_FSR=1
    export WINE_FULLSCREEN_FSR_STRENGTH="${FSR_STRENGTH:-2}"
fi

# 11. Uso condicional de GameMode según perfil
GAMEMODE=""
if [ "$PERFIL_RENDIMIENTO" != "ahorro" ] && command -v gamemoderun &> /dev/null; then
    GAMEMODE="gamemoderun"
fi

# 11. Obtener directorio y nombre del archivo
TARGET_DIR="$(cd "$(dirname "$TARGET")" && pwd)"
TARGET_FILE="$(basename "$TARGET")"

# ==============================================================================
# OPTIMIZACIÓN UNIVERSAL DE RED Y MULTIJUGADOR PARA WINE
# - Permite a todos los programas y juegos conectarse a Internet y servidores online
# - Configura resolución DNS limpia con hostname dinámico dentro del prefijo Wine
# - Configura sondas NCSI en el registro para que Windows detecte 100% de conectividad
# ==============================================================================
optimizar_red_y_wifi() {
    # 1. Asegurar archivo hosts y resolución de servidores en el prefijo (dinámico por equipo)
    local etc_dir="${WINEPREFIX}/drive_c/windows/system32/drivers/etc"
    mkdir -p "$etc_dir"
    local my_host
    my_host="$(hostname 2>/dev/null || echo "localhost")"
    cat << EOF > "${etc_dir}/hosts"
127.0.0.1 localhost ${my_host}
::1 localhost ip6-localhost ip6-loopback
EOF

    # 4. Asegurar parámetros de red e Internet (NCSI / NLA / DNS) en el registro de Wine
    if [ ! -f "${WINEPREFIX}/.vessel_net_ok" ]; then
        wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters" /v NameServer /t REG_SZ /d "1.1.1.1,8.8.8.8" /f >/dev/null 2>&1 || true
        wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters" /v DhcpNameServer /t REG_SZ /d "1.1.1.1,8.8.8.8" /f >/dev/null 2>&1 || true
        wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters" /v EnableDHCP /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
        wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\Default" /v NameServer /t REG_SZ /d "1.1.1.1,8.8.8.8" /f >/dev/null 2>&1 || true
        wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\Default" /v DhcpNameServer /t REG_SZ /d "1.1.1.1,8.8.8.8" /f >/dev/null 2>&1 || true
        wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\Default" /v EnableDHCP /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true

        # Sondas NCSI (Windows Network Connectivity Status Indicator) para que todos los juegos y launchers detecten conexión activa a Internet
        "$WINE_CMD" reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v EnableActiveProbing /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v ActiveWebProbeHost /t REG_SZ /d "www.msftncsi.com" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v ActiveWebProbeContent /t REG_SZ /d "Microsoft NCSI" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v ActiveDnsProbeHost /t REG_SZ /d "dns.msftncsi.com" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v ActiveDnsProbeContent /t REG_SZ /d "131.107.255.255" /f >/dev/null 2>&1 || true

        "$WINE_CMD" reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" /v NoActiveProbe /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" /v DisablePassivePolling /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true

        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v GlobalUserOffline /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v CertificateRevocation /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true

        touch "${WINEPREFIX}/.vessel_net_ok" 2>/dev/null || true
    fi

    # 5. Apertura de puertos Firewall para Multiplayer y GameRanger
    if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        sudo -n firewall-cmd --add-port=16000/udp --add-port=2300-2400/udp --add-port=2300-2400/tcp --add-port=47624/tcp --add-port=10480-10483/udp --add-port=7777/udp 2>/dev/null || true
        sudo -n firewall-cmd --permanent --add-port=16000/udp --add-port=2300-2400/udp --add-port=2300-2400/tcp --add-port=47624/tcp --add-port=10480-10483/udp --add-port=7777/udp 2>/dev/null || true
        sudo -n firewall-cmd --reload 2>/dev/null || true
    fi
    if command -v ufw &>/dev/null && sudo -n ufw status 2>/dev/null | grep -qi "active"; then
        sudo -n ufw allow 16000/udp 2>/dev/null || true
        sudo -n ufw allow 2300:2400/udp 2>/dev/null || true
        sudo -n ufw allow 2300:2400/tcp 2>/dev/null || true
        sudo -n ufw allow 47624/tcp 2>/dev/null || true
        sudo -n ufw allow 10480:10483/udp 2>/dev/null || true
        sudo -n ufw allow 7777/udp 2>/dev/null || true
    fi
}
optimizar_red_y_wifi

# Overrides universales de gráficos 3D, red, sockets, SSL/TLS, DirectPlay y librerías base
export WINEDLLOVERRIDES="winemenubuilder.exe=d;dxgi=n,b;d3d11=n,b;d3d10core=n,b;d3d9=n,b;d3d8=n,b;ddraw=n,b;dplayx=n,b;dpnet=n,b;dpwsockx=n,b;secur32=n,b;wininet=n,b;winhttp=n,b;ws2_32=n,b;iphlpapi=n,b;dnsapi=n,b;${WINEDLLOVERRIDES}"

# 11.1 Configuración específica para el cliente de lobby GameRanger
EXTRA_APP_ARGS=""
if [[ "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]]; then
    # GameRanger es una aplicación de escritorio/chat con interfaz Chromium CEF / ANGLE embebida.
    # Sus subventanas web no son superficies 3D exclusivas y fallan con swapchains Vulkan (VK_ERROR_OUT_OF_HOST_MEMORY).
    # Desactivamos DXVK para GameRanger y usamos WineD3D nativo, eliminando cualquier cuelgue de UI.
    export RENDERER_IN_USE="WineD3D (Lobby Compatibilidad)"
    export PROTON_USE_WINED3D=1
    export WINEDLLOVERRIDES="winemenubuilder.exe=d;dxgi=b;d3d11=b;d3d10core=b;d3d9=b;dnsapi=b;dplayx=n,b;dpnet=n,b;dpwsockx=n,b;riched20=n,b;riched32=n,b;ws2_32=b;wininet=b;iphlpapi=b;secur32=b;winhttp=b"
    unset DXVK_CONFIG_FILE
    unset DXVK_STATE_CACHE_PATH
    unset DXVK_ASYNC
    unset DXVK_GPLASYNCCACHE

    # Desactivar gamemode para evitar mensajes en consola (GameRanger es una app de chat 2D)
    GAMEMODE=""

    # Forzar modo Windows 7 y renderer GL en registro Wine AppDefaults para GameRanger
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe" /v "Version" /t REG_SZ /d "win7" /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\Direct3D" /v "renderer" /t REG_SZ /d "gl" /f >/dev/null 2>&1 || true

    # CEF interno en GameRanger renderiza limpiamente con GDI/WineD3D sin flags conflictivas
    EXTRA_APP_ARGS=""
fi

# Moverse al directorio donde reside el juego (vital para rutas relativas y DLLs)
cd "$TARGET_DIR"

# Asegurar permisos de escritura para que los mods puedan guardar configs, logs y partidas
[ -w "$TARGET_DIR" ] || chmod -R u+w "$TARGET_DIR" 2>/dev/null || true

# ==============================================================================
# DETECCIÓN DE PANTALLA ACTIVA Y RESOLUCIÓN NATIVA DEL MONITOR
# - Detecta en qué monitor se encuentra el cursor del usuario (multimonitor)
# - Determina ancho, alto y desplazamiento X, Y para evitar que el juego se abra en pantallas inactivas
# ==============================================================================
detectar_pantalla_activa() {
    ACTIVE_MON_W=""
    ACTIVE_MON_H=""
    ACTIVE_MON_X=0
    ACTIVE_MON_Y=0

    if command -v xrandr &>/dev/null; then
        local mouse_x=-1 mouse_y=-1
        if command -v xdotool &>/dev/null; then
            eval "$(xdotool getmouselocation --shell 2>/dev/null || true)"
            [ -n "$X" ] && mouse_x="$X"
            [ -n "$Y" ] && mouse_y="$Y"
        fi

        local prim_w="" prim_h="" prim_x=0 prim_y=0
        local max_w="" max_h="" max_x=0 max_y=0 max_area=0
        local cur_found=0

        while read -r line; do
            if [[ "$line" =~ ([0-9]{3,4})x([0-9]{3,4})\+([0-9]+)\+([0-9]+) ]]; then
                local mw="${BASH_REMATCH[1]}"
                local mh="${BASH_REMATCH[2]}"
                local mx_off="${BASH_REMATCH[3]}"
                local my_off="${BASH_REMATCH[4]}"
                local area=$((mw * mh))

                if [ "$mouse_x" -ge "$mx_off" ] && [ "$mouse_x" -lt $((mx_off + mw)) ] &&                    [ "$mouse_y" -ge "$my_off" ] && [ "$mouse_y" -lt $((my_off + mh)) ]; then
                    ACTIVE_MON_W="$mw"
                    ACTIVE_MON_H="$mh"
                    ACTIVE_MON_X="$mx_off"
                    ACTIVE_MON_Y="$my_off"
                    cur_found=1
                fi

                if echo "$line" | grep -q "primary"; then
                    prim_w="$mw"
                    prim_h="$mh"
                    prim_x="$mx_off"
                    prim_y="$my_off"
                fi

                if [ "$area" -gt "$max_area" ]; then
                    max_area="$area"
                    max_w="$mw"
                    max_h="$mh"
                    max_x="$mx_off"
                    max_y="$my_off"
                fi
            fi
        done < <(xrandr 2>/dev/null | grep -E 'connected')

        if [ "$cur_found" -eq 0 ]; then
            if [ -n "$prim_w" ]; then
                ACTIVE_MON_W="$prim_w"
                ACTIVE_MON_H="$prim_h"
                ACTIVE_MON_X="$prim_x"
                ACTIVE_MON_Y="$prim_y"
            elif [ -n "$max_w" ]; then
                ACTIVE_MON_W="$max_w"
                ACTIVE_MON_H="$max_h"
                ACTIVE_MON_X="$max_x"
                ACTIVE_MON_Y="$max_y"
            fi
        fi
    fi

    if [ -z "$ACTIVE_MON_W" ]; then
        local raw_res
        raw_res=$(cat /sys/class/drm/*/modes 2>/dev/null | grep -oE '^[0-9]{3,4}x[0-9]{3,4}' | head -n 1)
        if [ -n "$raw_res" ]; then
            ACTIVE_MON_W=$(echo "$raw_res" | cut -dx -f1)
            ACTIVE_MON_H=$(echo "$raw_res" | cut -dx -f2)
        else
            ACTIVE_MON_W=1920
            ACTIVE_MON_H=1080
        fi
        ACTIVE_MON_X=0
        ACTIVE_MON_Y=0
    fi

    best_w="$ACTIVE_MON_W"
    best_h="$ACTIVE_MON_H"
    best_res="${best_w}x${best_h}"
    export ACTIVE_MON_W ACTIVE_MON_H ACTIVE_MON_X ACTIVE_MON_Y best_w best_h best_res
}
detectar_pantalla_activa

# ==============================================================================
# ARQUITECTURA MODULAR DE PERFILES AISLADOS POR MOTOR Y JUEGO
# - Identificación inteligente por ejecutable, carpetas de datos y firmas de motor
# - Limpia procesos zombies EXCLUSIVAMENTE del juego seleccionado para evitar bloqueos por mutex
# - Ajusta variables de entorno, DLL overrides y configs de pantalla completa y FOV 3D
#   de manera 100% aislada para NUNCA degradar el rendimiento o compatibilidad de otros juegos
# ==============================================================================
# Función segura para limpiar procesos zombies de Wine sin matarse a sí mismo
limpiar_zombies_juego() {
    local target_pat="$1"
    for p in $(pgrep -f "$target_pat" 2>/dev/null || true); do
        if [ "$p" != "$$" ] && [ "$p" != "$PPID" ]; then
            local cmdline
            cmdline=$(cat "/proc/$p/cmdline" 2>/dev/null | tr '\0' ' ' || true)
            if ! echo "$cmdline" | grep -qiE 'launch-win-app|menu_tui|menu-win|bash|python' && \
               echo "$cmdline" | grep -qiE 'wine|\.exe'; then
                kill -9 "$p" 2>/dev/null || true
            fi
        fi
    done
}

aplicar_perfil_aislado_juego() {
    local perfil_id="generico"

    if [[ "$TARGET_FILE" =~ (GTA5|PlayGTAV|gta5) ]] || [[ "$TARGET_DIR" =~ (GTA\ V|Grand\ Theft\ Auto\ V|gta_data) ]]; then
        perfil_id="rockstar_gta5"
    elif [[ "$TARGET_FILE" =~ (gta_sa|gta-sa|gtasa) ]] || [[ "$TARGET_DIR" =~ (GTA\ San\ Andreas|Grand\ Theft\ Auto\ San\ Andreas) ]]; then
        perfil_id="rockstar_gtasa"
    elif [[ "$TARGET_FILE" =~ (speed|speed2|nfs) ]] || [[ "$TARGET_DIR" =~ (Need\ for\ Speed|NFS) ]]; then
        perfil_id="ea_nfs"
    elif [[ "$TARGET_FILE" =~ (re4|re2|re3|re7|re8|dmc5) ]] && find "$TARGET_DIR" -maxdepth 3 -name "*config*.ini" 2>/dev/null | grep -q .; then
        perfil_id="capcom_re_engine"
    elif [[ "$TARGET_FILE" =~ (BH6|biohazard4|re6|RE6|re5|RE5|dmc4) ]] || [[ "$TARGET_DIR" =~ (Resident\ Evil|BH6|re6|RE6|Capcom) ]]; then
        perfil_id="capcom_mt_framework"
    elif [[ "$TARGET_FILE" =~ (Swat4|Swat4X|Bioshock|DeusEx) ]] || [ -d "${TARGET_DIR}/System" ] || [ -d "${TARGET_DIR}/Content/System" ]; then
        perfil_id="unreal_engine"
    elif [ -f "${TARGET_DIR}/ddraw.ini" ] || [[ "$TARGET_FILE" =~ (empires2|age2_x1|starcraft|ra2) ]]; then
        perfil_id="classic_directdraw"
    elif [ -d "${TARGET_DIR}/${TARGET_FILE%.*}_Data" ] || [ -f "${TARGET_DIR}/UnityPlayer.dll" ]; then
        perfil_id="unity_engine"
    elif [ -f "${TARGET_DIR}/tier0.dll" ] || [ -f "${TARGET_DIR}/bin/tier0.dll" ]; then
        perfil_id="source_engine"
    elif [[ "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]]; then
        perfil_id="gameranger"
    fi

    echo "[*] Perfil de compatibilidad detectado: [$perfil_id]"

    case "$perfil_id" in
        rockstar_gta5)
            echo "[+] Perfil Activo: Rockstar Games (Grand Theft Auto V) [Aislado]"
            # 1. Limpiar procesos zombies previos de GTA V de forma segura (sin matar el script)
            limpiar_zombies_juego "GTA5\.exe|PlayGTAV\.exe"
            sleep 0.2

            # Determinar resolución óptima según GPU (720p para GPUs de entrada/móviles como MX130 / Intel, nativa para gama alta)
            local gta_w="$best_w"
            local gta_h="$best_h"
            if [ "$IS_LOW_SPEC_GPU" = true ]; then
                gta_w="1280"
                gta_h="720"
                echo "    - Modo GPU de Entrada detectado: Ajustando resolución de renderizado a 1280x720 para 60 FPS estables."
            fi

            # 2. Configuración en Rockstar Games / GTA V / settings.xml
            local rsg_doc="$HOME/Documentos/Rockstar Games/GTA V"
            [ ! -d "$rsg_doc" ] && rsg_doc="${WINEPREFIX}/drive_c/users/${USER}/Documents/Rockstar Games/GTA V"
            mkdir -p "$rsg_doc"
            for sxml in "$rsg_doc/settings.xml" "${TARGET_DIR}/settings.xml" "${WINEPREFIX}/drive_c/users/${USER}/Documents/Rockstar Games/GTA V/settings.xml"; do
                if [ -f "$sxml" ]; then
                    sed -i "s/<ScreenWidth value=\"[0-9]*\"/<ScreenWidth value=\"${gta_w}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<ScreenHeight value=\"[0-9]*\"/<ScreenHeight value=\"${gta_h}\"/" "$sxml" 2>/dev/null || true
                    sed -i 's/<Windowed value="[0-9]*"/<Windowed value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<VSync value="[0-9]*"/<VSync value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<ShadowQuality value="[0-9]*"/<ShadowQuality value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<GrassQuality value="[0-9]*"/<GrassQuality value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<ShaderQuality value="[0-9]*"/<ShaderQuality value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<ReflectionQuality value="[0-9]*"/<ReflectionQuality value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<PauseOnFocusLoss value="[0-9]*"/<PauseOnFocusLoss value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<AspectRatio value="[0-9]*"/<AspectRatio value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<FXAA_Enabled value="false"/<FXAA_Enabled value="true"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<PedVarietyMultiplier value="[0-9\.]*"/<PedVarietyMultiplier value="0.200000"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<VehicleVarietyMultiplier value="[0-9\.]*"/<VehicleVarietyMultiplier value="0.200000"/' "$sxml" 2>/dev/null || true
                    if [ -n "$GPU_NAME" ]; then
                        sed -i "s|<VideoCardDescription>.*</VideoCardDescription>|<VideoCardDescription>${GPU_NAME}</VideoCardDescription>|" "$sxml" 2>/dev/null || true
                    fi
                fi
            done

            # 3. Optimización en commandline.txt
            local gta_cmdline="${TARGET_DIR}/commandline.txt"
            cat <<EOF > "$gta_cmdline"
-width ${gta_w}
-height ${gta_h}
-fullscreen
-novsync
-FrameQueueLimit 1
-disablespecular
-reflectionBlur 0
-reflection_MipBlur 0
-noInGameDOF
-StraightIntoFreemode
-ignoreDifferentVideoCard
-ShadowQuality 0
-ReflectionQuality 0
-ShaderQuality 0
-GrassQuality 0
-WaterQuality 0
-TextureQuality 0
-ParticleQuality 0
-Tessellation 0
-pedLodBias 0.2
-vehicleLodBias 0.2
-shadowSoftness 0
EOF
            echo "[+] GTA V optimizado: Pantalla completa nativa, sin VSync artificial y configuración 60 FPS aplicada."

            # Overrides específicos de DirectX 11, Bink Video, Social Club y ASI Loader
            export WINEDLLOVERRIDES="bink2w64=n,b;asiloader=n,b;d3dcompiler_46=n,b;d3dcompiler_43=n,b;d3dcsx_46=n,b;socialclub=n,b;steam_api64=n,b;dxgi=n,b;d3d11=n,b;d3d9=n,b;${WINEDLLOVERRIDES}"
            ;;

        rockstar_gtasa)
            echo "[+] Perfil Activo: Rockstar Games (GTA San Andreas / Trilogy) [Aislado]"
            limpiar_zombies_juego "gta_sa\.exe"
            # Desactivar ventana forzada de mods para garantizar pantalla completa nativa
            find "$TARGET_DIR" -iname "III.VC.SA.WindowedMode.ini" 2>/dev/null | while read -r wm_ini; do
                sed -i "s/^ShowBorder = .*/ShowBorder = 0/" "$wm_ini" 2>/dev/null || true
            done
            find "$TARGET_DIR" -iname "III.VC.SA.WindowedMode.asi" 2>/dev/null | while read -r wm_asi; do
                mv "$wm_asi" "${wm_asi}.disabled" 2>/dev/null || true
            done
            # Configurar Widescreen Fix
            find "$TARGET_DIR" -maxdepth 3 -iname "*widescreen*.ini" 2>/dev/null | while read -r wf_ini; do
                sed -i "s/^ResX = .*/ResX = ${best_w}/" "$wf_ini" 2>/dev/null || true
                sed -i "s/^ResY = .*/ResY = ${best_h}/" "$wf_ini" 2>/dev/null || true
                sed -i "s/^ForceAspectRatio = .*/ForceAspectRatio = auto/" "$wf_ini" 2>/dev/null || true
            done
            # Desactivar mesa_glthread para prevenir microtirones con D3D9 y ASI Loader
            export mesa_glthread=false
            export WINEDLLOVERRIDES="vorbisfile=n,b;vorbishooked=n,b;vorbis=n,b;ogg=n,b;bass=n,b;eax=n,b;dinput8=n,b;d3d9=n,b;dsound=n,b;libcurl=n,b;${WINEDLLOVERRIDES}"
            ;;

        ea_nfs)
            echo "[+] Perfil Activo: EA Games (Need For Speed) [Aislado]"
            find "$TARGET_DIR" -maxdepth 3 -iname "*widescreen*.ini" 2>/dev/null | while read -r wf_ini; do
                sed -i "s/^ResX = .*/ResX = ${best_w}/" "$wf_ini" 2>/dev/null || true
                sed -i "s/^ResY = .*/ResY = ${best_h}/" "$wf_ini" 2>/dev/null || true
                sed -i "s/^ForceAspectRatio = .*/ForceAspectRatio = auto/" "$wf_ini" 2>/dev/null || true
            done
            export WINEDLLOVERRIDES="dinput8=n,b;d3d9=n,b;scripts=n,b;${WINEDLLOVERRIDES}"
            ;;

        capcom_re_engine)
            echo "[+] Perfil Activo: Capcom RE Engine [Aislado]"
            limpiar_zombies_juego "re4\.exe|re2\.exe|re3\.exe|re7\.exe|re8\.exe|dmc5\.exe"
            find "$TARGET_DIR" -maxdepth 3 -name "*config*.ini" 2>/dev/null | while read -r re_ini; do
                if grep -q "\[AppRender\]" "$re_ini" 2>/dev/null || grep -q "\[RenderConfig\]" "$re_ini" 2>/dev/null; then
                    sed -i 's/^FullScreenMode=.*/FullScreenMode=true/' "$re_ini" 2>/dev/null || true
                    sed -i 's/^WindowMode=.*/WindowMode=FullScreen/' "$re_ini" 2>/dev/null || true
                    sed -i 's/^AppWindowMode=.*/AppWindowMode=0/' "$re_ini" 2>/dev/null || true
                    sed -i 's/^AppRenderingMethod=.*/AppRenderingMethod=1/' "$re_ini" 2>/dev/null || true
                    sed -i 's/^AppLensDistorsion=.*/AppLensDistorsion=0/' "$re_ini" 2>/dev/null || true
                    sed -i 's/^AppMotionBlur=.*/AppMotionBlur=0/' "$re_ini" 2>/dev/null || true
                    sed -i 's/^AppFilmGrainNoise=.*/AppFilmGrainNoise=0/' "$re_ini" 2>/dev/null || true
                    sed -i 's/^AppVsync=.*/AppVsync=0/' "$re_ini" 2>/dev/null || true
                    local dm_idx
                    dm_idx=$(grep -B 1 "DisplayMode[0-9]*_Height=${best_h}" "$re_ini" 2>/dev/null | grep -E "DisplayMode[0-9]*_Width=${best_w}" | head -n 1 | grep -oE "DisplayMode[0-9]+" | tr -d 'DisplayMode')
                    if [ -n "$dm_idx" ]; then
                        sed -i "s/^AppResolution=.*/AppResolution=${dm_idx}/" "$re_ini" 2>/dev/null || true
                        sed -i "s/^FullScreenDisplayMode=.*/FullScreenDisplayMode=${dm_idx}/" "$re_ini" 2>/dev/null || true
                    fi
                fi
            done
            export WINEDLLOVERRIDES="dxgi=n,b;d3d12=n,b;d3d11=n,b;d3dcompiler_47=n,b;xinput1_3=n,b;xinput1_4=n,b;${WINEDLLOVERRIDES}"
            ;;

        capcom_mt_framework)
            echo "[+] Perfil Activo: Capcom MT Framework (Resident Evil Series) [Aislado]"
            limpiar_zombies_juego "BH6\.exe|biohazard4\.exe|re6\.exe|re5dx9\.exe|re5dx10\.exe"
            local capcom_dir="$HOME/Documentos/CAPCOM"
            [ ! -d "$capcom_dir" ] && capcom_dir="${WINEPREFIX}/drive_c/users/${USER}/Documents/CAPCOM"
            local dirs_a_buscar=("$capcom_dir" "$TARGET_DIR")
            [ -d "${TARGET_DIR}/gamedata/optimization" ] && dirs_a_buscar+=("${TARGET_DIR}/gamedata/optimization")
            [ -d "${TARGET_DIR}/optimization" ] && dirs_a_buscar+=("${TARGET_DIR}/optimization")

            for dir_c in "${dirs_a_buscar[@]}"; do
                if [ -d "$dir_c" ]; then
                    find "$dir_c" -maxdepth 3 -name "config.ini" 2>/dev/null | while read -r cini; do
                        if grep -q "\[GRAPHICS\]" "$cini" 2>/dev/null || grep -q "\[DISPLAY\]" "$cini" 2>/dev/null; then
                            sed -i 's/^FullScreen=OFF/FullScreen=ON/' "$cini" 2>/dev/null || true
                            sed -i 's/^VSYNC=ON/VSYNC=OFF/' "$cini" 2>/dev/null || true
                            sed -i 's/^MotionBlurEnabled=ON/MotionBlurEnabled=OFF/' "$cini" 2>/dev/null || true
                            sed -i 's/^Aspect=.*/Aspect=DEFAULT/' "$cini" 2>/dev/null || true
                            sed -i "s/^Resolution=.*/Resolution=${best_res}/" "$cini" 2>/dev/null || true
                            sed -i 's/^RefreshRate=.*/RefreshRate=60.00Hz/' "$cini" 2>/dev/null || true
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
                        fi
                    done
                fi
            done
            ;;

        unreal_engine)
            echo "[+] Perfil Activo: Unreal Engine (SWAT 4 / Clásicos 3D) [Aislado]"
            limpiar_zombies_juego "Swat4\.exe|Swat4X\.exe|Bioshock\.exe"
            local target_system_dir="$TARGET_DIR"
            [ -d "${TARGET_DIR}/System" ] && target_system_dir="${TARGET_DIR}/System"
            [ -d "${TARGET_DIR}/Content/System" ] && target_system_dir="${TARGET_DIR}/Content/System"

            local target_fov="100.000000"
            if [ "$best_h" -gt 0 ]; then
                local aspect_ratio_int=$(( (best_w * 100) / best_h ))
                if [ "$aspect_ratio_int" -ge 170 ]; then
                    target_fov="100.000000"
                elif [ "$aspect_ratio_int" -ge 150 ]; then
                    target_fov="95.000000"
                else
                    target_fov="85.000000"
                fi
            fi

            find "$target_system_dir" -maxdepth 2 -name "*.ini" 2>/dev/null | while read -r ueini; do
                if grep -q "\[WinDrv.WindowsClient\]" "$ueini" 2>/dev/null; then
                    sed -i 's/^StartupFullscreen=False/StartupFullscreen=True/' "$ueini" 2>/dev/null || true
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
                if grep -q "\[/Script/Engine.GameUserSettings\]" "$ueini" 2>/dev/null; then
                    sed -i 's/^FullscreenMode=[0-9]*/FullscreenMode=0/' "$ueini" 2>/dev/null || true
                    sed -i 's/^PreferredFullscreenMode=[0-9]*/PreferredFullscreenMode=0/' "$ueini" 2>/dev/null || true
                    sed -i 's/^LastConfirmedFullscreenMode=[0-9]*/LastConfirmedFullscreenMode=0/' "$ueini" 2>/dev/null || true
                    sed -i "s/^ResolutionSizeX=[0-9]*/ResolutionSizeX=${best_w}/" "$ueini" 2>/dev/null || true
                    sed -i "s/^ResolutionSizeY=[0-9]*/ResolutionSizeY=${best_h}/" "$ueini" 2>/dev/null || true
                fi
                if grep -q "DesiredFOV=" "$ueini" 2>/dev/null || grep -q "DefaultFOV=" "$ueini" 2>/dev/null; then
                    sed -i "s/^DesiredFOV=.*/DesiredFOV=${target_fov}/" "$ueini" 2>/dev/null || true
                    sed -i "s/^DefaultFOV=.*/DefaultFOV=${target_fov}/" "$ueini" 2>/dev/null || true
                fi
                if grep -q "FirstPersonFOV=" "$ueini" 2>/dev/null; then
                    sed -i "s/^FirstPersonFOV=.*/FirstPersonFOV=${target_fov}/" "$ueini" 2>/dev/null || true
                fi
                if grep -q "FovAngleDegrees=" "$ueini" 2>/dev/null; then
                    sed -i "s/^FovAngleDegrees=.*/FovAngleDegrees=${target_fov}/" "$ueini" 2>/dev/null || true
                fi
            done
            [ -d "${TARGET_DIR}/Engine" ] || [ -d "${TARGET_DIR}/Binaries" ] && EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -fullscreen"
            ;;

        classic_directdraw)
            echo "[+] Perfil Activo: Clásico DirectDraw (cnc-ddraw) [Aislado]"
            find "$TARGET_DIR" -maxdepth 2 -iname "ddraw.ini" 2>/dev/null | while read -r ddini; do
                sed -i 's/^fullscreen=.*/fullscreen=true/' "$ddini" 2>/dev/null || true
                sed -i 's/^windowed=.*/windowed=false/' "$ddini" 2>/dev/null || true
                sed -i "s/^width=.*/width=${best_w}/" "$ddini" 2>/dev/null || true
                sed -i "s/^height=.*/height=${best_h}/" "$ddini" 2>/dev/null || true
                sed -i 's/^boxing=.*/boxing=false/' "$ddini" 2>/dev/null || true
                sed -i 's/^maintas=.*/maintas=false/' "$ddini" 2>/dev/null || true
            done
            export WINEDLLOVERRIDES="ddraw=n,b;dsound=n,b;${WINEDLLOVERRIDES}"
            ;;

        unity_engine)
            echo "[+] Perfil Activo: Unity Engine [Aislado]"
            EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -screen-fullscreen 1 -screen-width ${best_w} -screen-height ${best_h}"
            ;;

        source_engine)
            echo "[+] Perfil Activo: Valve Source Engine [Aislado]"
            EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -fullscreen -w ${best_w} -h ${best_h}"
            ;;

        gameranger)
            echo "[+] Perfil Activo: GameRanger Desktop Client [Aislado]"
            ;;

        *)
            echo "[+] Perfil Activo: Aplicación Genérica [Aislado]"
            ;;
    esac
}
aplicar_perfil_aislado_juego

# ==============================================================================
# AUTO-ACTIVACIÓN DE MODS, ASI LOADERS, RESHADE, ENB Y TRADUCCIONES
# Detecta automáticamente librerías de mods locales y activa el override nativo (n,b)
# para que funcionen inmediatamente sin tocar winecfg
# ==============================================================================
MOD_HOOKS=("ddraw" "d3d8" "d3d9" "d3d11" "d3d12" "dxgi" "dinput8" "dinput" "dsound" "dplayx" "dpnet" "version" "winmm" "vorbisfile" "vorbishooked" "vorbis" "ogg" "bass" "eax" "xinput1_3" "xinput1_4" "xinput9_1_0" "x3daudio1_7" "xaudio2_7" "binkw32" "binkw64" "bink2w64" "dbghelp" "msimg32" "opengl32" "d3dcompiler_43" "d3dcompiler_46" "d3dcompiler_47" "d3dcsx_46" "socialclub" "libcurl")
MODS_ACTIVADOS=()

for hook in "${MOD_HOOKS[@]}"; do
    found_hook=$(find . -maxdepth 2 -iname "${hook}.dll" 2>/dev/null | head -n 1)
    if [ -n "$found_hook" ]; then
        export WINEDLLOVERRIDES="${hook}=n,b;${WINEDLLOVERRIDES}"
        MODS_ACTIVADOS+=("$(basename "$found_hook")")
    fi
done

CANT_ASI=$(ls -1 *.asi scripts/*.asi plugins/*.asi 2>/dev/null | wc -l)

# Modo Pantalla Nativo Directo en Hardware (sin capas virtuales)
ESCRITORIO_VIRTUAL="0"
RUN_PREFIX=""

echo ""
echo "[+] Ejecutando con Perfil [${PERFIL_RENDIMIENTO:-maximo}]..."
echo "    - CPU: ${CPU_MODEL} (${CPU_CORES} Hilos)"
echo "    - GPU: ${DETECTED_GPU}"
echo "    - Renderizador: ${RENDERER_IN_USE:-DXVK (Vulkan)}"
echo "    - Fsync/Esync: $([ "$WINEFSYNC" = "1" ] && echo "Fsync Activo" || echo "Esync Activo")"
echo "    - Límite de FPS: ${LIMITE_FPS:-60} FPS"
echo "    - AMD FSR Upscaling: $([ "$ACTIVAR_FSR" = "1" ] && echo "Activado" || echo "Desactivado")"
if [[ "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]]; then
    echo "    - GameMode: Desactivado (Aplicación de Escritorio / Lobby)"
    echo "    - Modo Pantalla: Ventana de Escritorio (Lobby / Multijugador)"
    echo "    - Red / Multijugador: Puertos 16000 UDP y DirectPlay Abiertos (100% Conectado)"
else
    echo "    - GameMode: $([ -n "$GAMEMODE" ] && echo "Activo" || echo "Inactivo")"
    echo "    - Modo Pantalla: Pantalla Completa Nativa Directa (Hardware)"
    echo "    - Caché de Shaders: NVMe SSD (~/.cache/dxvk)"
fi
echo "    - Runner Wine: ${RUNNER_LABEL}"
echo "    - Prefijo Wine: ${WINEPREFIX}"
if [ ${#MODS_ACTIVADOS[@]} -gt 0 ] || [ "$CANT_ASI" -gt 0 ]; then
    echo "    - Mods / Hooks Activos: $([ ${#MODS_ACTIVADOS[@]} -gt 0 ] && echo "${MODS_ACTIVADOS[*]}" || echo "Ninguna DLL especial")"
    [ "$CANT_ASI" -gt 0 ] && echo "    - Plugins ASI / Scripts: ${CANT_ASI} archivo(s) detectado(s)"
fi

# Argumentos de pantalla completa y resolución adaptativa según el motor del juego
if [[ ! "$TARGET_FILE" =~ ([Gg]ame[Rr]anger|winecfg|regedit|cmd|notepad) ]]; then
    # Unity Engine (ej. *_Data o UnityPlayer.dll)
    if [ -d "${TARGET_DIR}/${TARGET_FILE%.*}_Data" ] || [ -f "${TARGET_DIR}/UnityPlayer.dll" ]; then
        EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -screen-fullscreen 1 -screen-width ${best_w} -screen-height ${best_h}"
    # Source Engine (Half-Life 2, L4D, Portal, etc.)
    elif [ -f "${TARGET_DIR}/tier0.dll" ] || [ -f "${TARGET_DIR}/bin/tier0.dll" ]; then
        EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -fullscreen -w ${best_w} -h ${best_h}"
    # Unreal Engine 3/4
    elif [ -d "${TARGET_DIR}/Engine" ] || [ -d "${TARGET_DIR}/Binaries" ]; then
        EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -fullscreen"
    fi
fi

# Guardián en segundo plano para asegurar pantalla completa universal al detectar la ventana (solo X11)
WATCHDOG_PID=""
if [ "$IS_WAYLAND" -eq 0 ] && [ -n "${DISPLAY:-}" ] && [[ ! "$TARGET_FILE" =~ ([Gg]ame[Rr]anger|winecfg|regedit|cmd|notepad) ]]; then
    (
        for i in $(seq 1 30); do
            sleep 0.5
            if command -v wmctrl &>/dev/null; then
                wmctrl -l 2>/dev/null | grep -iE 'Wine|Resident|Grand Theft|GTA|SWAT|Age of Empires|BioShock|Unreal|Speed|NFS' | grep -viE 'GameRanger|Winecfg|Error|Debug' | while read -r wid rest; do
                    wmctrl -i -r "$wid" -e "0,${ACTIVE_MON_X},${ACTIVE_MON_Y},${best_w},${best_h}" 2>/dev/null || true
                    wmctrl -i -r "$wid" -b add,fullscreen 2>/dev/null || true
                done
            elif command -v xwininfo &>/dev/null && command -v xprop &>/dev/null; then
                xwininfo -root -tree 2>/dev/null | grep -iE '("Resident Evil|"GTA|"Grand Theft|"Swat|"PlayGTAV|"BH6|"re4|"Age of Empires|"Wine)' | grep -viE 'GameRanger|Winecfg' | grep -oE '0x[0-9a-fA-F]+' | head -n 3 | while read -r wid; do
                    xprop -id "$wid" -f _NET_WM_STATE 32a -set _NET_WM_STATE _NET_WM_STATE_FULLSCREEN 2>/dev/null || true
                done
            fi
        done
    ) &
    WATCHDOG_PID=$!
fi

# Guardián inteligente en segundo plano para GameRanger
GR_WATCHDOG_PID=""
if [[ "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]]; then
    (
        for i in $(seq 1 60); do
            sleep 1
            if [ "$IS_WAYLAND" -eq 0 ] && [ -n "${DISPLAY:-}" ]; then
                if command -v xdotool &>/dev/null; then
                    for gr_w in $(xdotool search --class "gameranger" 2>/dev/null); do
                        xdotool windowmap "$gr_w" 2>/dev/null || true
                        xdotool windowraise "$gr_w" 2>/dev/null || true
                    done
                fi
                if command -v wmctrl &>/dev/null; then
                    wmctrl -l 2>/dev/null | grep -iE 'GameRanger|Friends|Assistant' | while read -r wid dtop host wtitle; do
                        wmctrl -i -r "$wid" -b remove,hidden,remove,shaded 2>/dev/null || true
                        wmctrl -i -a "$wid" 2>/dev/null || true
                    done
                fi
            fi

            # Auto-respaldo dinámico de la sesión en cuanto el usuario inicie sesión
            for u_dir in "${WINEPREFIX}/drive_c/users"/*; do
                if [ -d "$u_dir" ] && [ "$(basename "$u_dir")" != "Public" ]; then
                    u_s="${u_dir}/AppData/Roaming/GameRanger/GameRanger Prefs/Settings"
                    if [ -s "$u_s" ] && grep -q "SessMail" "$u_s" 2>/dev/null; then
                        mkdir -p "${DIR}/.gameranger_prefs_backup"
                        cp -rf "${u_dir}/AppData/Roaming/GameRanger/GameRanger Prefs"/* "${DIR}/.gameranger_prefs_backup/" 2>/dev/null || true
                    fi
                fi
            done
        done
    ) &
    GR_WATCHDOG_PID=$!
fi

# Función para limpiar procesos en caso de interrupción del usuario (Ctrl+C o terminal cerrada)
limpiar_procesos_al_interrumpir() {
    [ -n "$WATCHDOG_PID" ] && kill "$WATCHDOG_PID" 2>/dev/null || true
    [ -n "$GR_WATCHDOG_PID" ] && kill "$GR_WATCHDOG_PID" 2>/dev/null || true
    if [[ "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]]; then
        for u_dir in "${WINEPREFIX}/drive_c/users"/*; do
            if [ -d "$u_dir" ] && [ "$(basename "$u_dir")" != "Public" ]; then
                u_prefs="${u_dir}/AppData/Roaming/GameRanger/GameRanger Prefs"
                if [ -d "$u_prefs" ] && [ -s "${u_prefs}/Settings" ] && grep -q "SessMail" "${u_prefs}/Settings" 2>/dev/null; then
                    mkdir -p "${DIR}/.gameranger_prefs_backup"
                    cp -rf "$u_prefs"/* "${DIR}/.gameranger_prefs_backup/" 2>/dev/null || true
                fi
            fi
        done
    fi
    "$WINESERVER_CMD" -k 2>/dev/null || wineserver -k 2>/dev/null || true
}
trap limpiar_procesos_al_interrumpir INT TERM

# Sincronizar buffers de disco y optimizar prioridad de proceso
sync 2>/dev/null || true
renice -n -5 $$ 2>/dev/null || true

# Desactivar 'set -e' antes de la ejecución para garantizar que salidas con código != 0 no interrumpan la limpieza
set +e

if [[ "$TARGET_FILE" =~ \.(msi|MSI)$ ]]; then
    $GAMEMODE "$WINE_CMD" msiexec /i "$TARGET_FILE" "$@"
elif [[ "$TARGET_FILE" =~ \.(lnk|ink|LNK|INK)$ ]]; then
    if [ -n "$RUN_PREFIX" ]; then
        $GAMEMODE "$WINE_CMD" $RUN_PREFIX start /unix "$TARGET" "$@"
    else
        $GAMEMODE "$WINE_CMD" start /unix "$TARGET" "$@"
    fi
elif [[ "$TARGET_FILE" =~ \.([bB][aA][tT]|[cC][mM][dD])$ ]]; then
    if [ -n "$RUN_PREFIX" ]; then
        $GAMEMODE "$WINE_CMD" $RUN_PREFIX cmd /c "$TARGET_FILE" "$@"
    else
        $GAMEMODE "$WINE_CMD" cmd /c "$TARGET_FILE" "$@"
    fi
elif [[ "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]]; then
    # GameRanger: silenciar logs ruidosos de CEF/Chromium hacia log dedicado y ejecutar fluidamente
    "$WINE_CMD" "$TARGET_FILE" "$@" $EXTRA_APP_ARGS 2>"${WINEPREFIX}/gameranger_cef.log"
else
    if [ -n "$RUN_PREFIX" ]; then
        $GAMEMODE "$WINE_CMD" $RUN_PREFIX "$TARGET_FILE" "$@" $EXTRA_APP_ARGS
    else
        $GAMEMODE "$WINE_CMD" "$TARGET_FILE" "$@" $EXTRA_APP_ARGS
    fi
fi
EXIT_STATUS=$?

# Terminar vigilantes en segundo plano si siguen activos
[ -n "$WATCHDOG_PID" ] && kill "$WATCHDOG_PID" 2>/dev/null || true
[ -n "$GR_WATCHDOG_PID" ] && kill "$GR_WATCHDOG_PID" 2>/dev/null || true

# Respaldar sesión de GameRanger para asegurar persistencia permanente
if [[ "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]]; then
    for u_dir in "${WINEPREFIX}/drive_c/users"/*; do
        if [ -d "$u_dir" ] && [ "$(basename "$u_dir")" != "Public" ]; then
            u_prefs="${u_dir}/AppData/Roaming/GameRanger/GameRanger Prefs"
            if [ -d "$u_prefs" ] && [ -s "${u_prefs}/Settings" ] && grep -q "SessMail" "${u_prefs}/Settings" 2>/dev/null; then
                mkdir -p "${DIR}/.gameranger_prefs_backup"
                cp -rf "$u_prefs"/* "${DIR}/.gameranger_prefs_backup/" 2>/dev/null || true
            fi
        fi
    done
fi

# Esperar sincronización limpia de los subprocesos de Wine sin matarlos abruptamente
"$WINESERVER_CMD" -w 2>/dev/null || wineserver -w 2>/dev/null || true
exit $EXIT_STATUS
