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

# 3. Procesar banderas opcionales (prefijo dedicado, modo aislado, runner custom, versión de Windows y AMD FSR)
CUSTOM_PREFIX=""
FORCE_ISOLATED=0
CUSTOM_RUNNER=""
CUSTOM_WINVER=""
CUSTOM_FSR=""
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
        --winver)
            CUSTOM_WINVER="$2"
            shift 2
            ;;
        --fsr)
            CUSTOM_FSR="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "Uso: $0 [--prefix /ruta/al/prefijo] [--isolated] [--runner /ruta/a/wine] [--winver win10|win7|winxp] [--fsr off|quality|performance] /ruta/al/programa.exe [argumentos]"
    exit 1
fi

TARGET="$1"
shift || true

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

# 4.1 Resolver accesos directos de Windows (.lnk o .ink) al ejecutable real
if [[ "$TARGET" =~ \.([lL][nN][kK]|[iI][nN][kK])$ ]] && [ -f "$TARGET" ]; then
    echo "[*] Acceso directo detectado: $(basename "$TARGET"). Resolviendo ejecutable real..."
    if [ -f "${DIR}/resolver_lnk.py" ]; then
        RESOLVED_RES=$(python3 "${DIR}/resolver_lnk.py" "$TARGET" "${WINEPREFIX:-${DIR}/wineprefix}" 2>/dev/null || true)
        RESOLVED_STATUS=$(echo "$RESOLVED_RES" | grep '^STATUS=' | cut -d= -f2-)
        RESOLVED_PATH=$(echo "$RESOLVED_RES" | grep '^RESOLVED_PATH=' | cut -d= -f2-)
        if [ "$RESOLVED_STATUS" = "RESOLVED" ] && [ -f "$RESOLVED_PATH" ]; then
            echo "[+] Acceso directo resuelto a: $RESOLVED_PATH"
            TARGET="$RESOLVED_PATH"
        fi
    fi
fi

# 4.2 Resolver scripts por lotes (.bat o .cmd) para omitir bucles infinitos de CPU
if [ -f "${DIR}/herramientas/gamecontrollerdb.txt" ]; then
    export SDL_GAMECONTROLLERCONFIG_FILE="${DIR}/herramientas/gamecontrollerdb.txt"
fi

ORIGINAL_TARGET="$TARGET"
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

# 4.0.2 Priorizar el binario nativo óptimo (.exe) sobre scripts .bat/.cmd para evitar cuelgues de wmic/cacls en Wine
if [[ "$TARGET" =~ \.([bB][aA][tT]|[cC][mM][dD])$ ]]; then
    BAT_DIR=$(dirname "$TARGET")
    for cand in "PlayGTAV.exe" "GTA5.exe" "gta_sa.exe" "speed.exe" "BH6.exe" "re4.exe" "biohazard4.exe" "Swat4.exe"; do
        FOUND_EXE=$(find "$BAT_DIR" -maxdepth 3 -iname "$cand" 2>/dev/null | head -n 1)
        if [ -n "$FOUND_EXE" ] && [ -f "$FOUND_EXE" ]; then
            echo "[+] Binario nativo óptimo detectado: $(basename "$FOUND_EXE") (priorizado sobre $(basename "$TARGET"))"
            TARGET="$FOUND_EXE"
            break
        fi
    done
fi

# Redirección inteligente de ejecutables subordinados a sus launchers requeridos (ej. GTA5.exe -> PlayGTAV.exe)
if [[ "$(basename "$TARGET")" =~ ^(GTA5\.exe|gta5\.exe)$ ]] && [ -f "$(dirname "$TARGET")/PlayGTAV.exe" ]; then
    echo "[+] Launcher nativo detectado: PlayGTAV.exe (requerido para túnel IPC/pipe de GTA V, priorizado sobre GTA5.exe)"
    TARGET="$(dirname "$TARGET")/PlayGTAV.exe"
fi

# 4. Definir la ruta del WINEPREFIX (Soporte Dual: Prefijo Compartido o Prefijo Aislado por Juego)
if [ -n "$CUSTOM_PREFIX" ]; then
    export WINEPREFIX="$CUSTOM_PREFIX"
else
    # Comprobar en base de datos si el juego tiene configurado prefijo aislado, versión de Windows o FSR
    PREF_TYPE="compartido"
    GAME_WINVER="${CUSTOM_WINVER:-}"
    GAME_FSR="${CUSTOM_FSR:-}"
    for db in "${DIR}/programas_usuario.db" "${DIR}/programas.db"; do
        if [ -f "$db" ]; then
            matched_line=$(grep -F "$TARGET" "$db" 2>/dev/null | head -n 1)
            [ -z "$matched_line" ] && [ -n "$ORIGINAL_TARGET" ] && matched_line=$(grep -F "$ORIGINAL_TARGET" "$db" 2>/dev/null | head -n 1)
            [ -z "$matched_line" ] && matched_line=$(grep -F "$(basename "$TARGET")" "$db" 2>/dev/null | head -n 1)
            [ -z "$matched_line" ] && [ -n "$ORIGINAL_TARGET" ] && matched_line=$(grep -F "$(basename "$ORIGINAL_TARGET")" "$db" 2>/dev/null | head -n 1)
            if [ -n "$matched_line" ]; then
                db_ptype=$(echo "$matched_line" | cut -d'|' -f3 | tr -d '\r\n ')
                [ -n "$db_ptype" ] && PREF_TYPE="$db_ptype"
                if [ -z "$GAME_WINVER" ]; then
                    db_winver=$(echo "$matched_line" | cut -d'|' -f4 | tr -d '\r\n ')
                    [ -n "$db_winver" ] && GAME_WINVER="$db_winver"
                fi
                if [ -z "$GAME_FSR" ]; then
                    db_fsr=$(echo "$matched_line" | cut -d'|' -f5 | tr -d '\r\n ')
                    [ -n "$db_fsr" ] && GAME_FSR="$db_fsr"
                fi
                break
            fi
        fi
    done

    # 4.3 Análisis Inteligente de Cabezales Binarios PE (Arquitectura, Versión de Windows, APIs y Motor)
    PE_WINVER=""
    PE_BITS=""
    PE_API=""
    PE_ENGINE=""
    PE_SUBSYS=""
    PE_IS_64="0"
    PE_IS_PE="0"
    PE_HAS_DX12="0"
    PE_HAS_DX11="0"
    PE_HAS_DDRAW="0"

    if [ -f "${DIR}/analizador_pe.py" ] && [ -f "$TARGET" ]; then
        pe_eval=$(python3 "${DIR}/analizador_pe.py" --bash "$TARGET" 2>/dev/null || true)
        if [ -n "$pe_eval" ]; then
            eval "$pe_eval"
            # Si se resolvió un binario .exe real desde un script .bat/.lnk, actualizar TARGET si aún no lo estaba
            if [ -n "$PE_TARGET" ] && [ -f "$PE_TARGET" ] && [ "$TARGET" != "$PE_TARGET" ]; then
                TARGET="$PE_TARGET"
            fi
        fi
    fi

    # Detección inteligente de arquitectura (32-bit vs 64-bit) y APIs modernas (DirectX 12 / RE Engine)
    es_64bit=false
    if [ "$PE_IS_64" = "1" ] || file -b "$TARGET" 2>/dev/null | grep -qiE 'x86-64|PE32\+'; then
        es_64bit=true
    fi
    es_dx12=false
    if [ "$PE_HAS_DX12" = "1" ] || [ -f "$(dirname "$TARGET")/d3d12.dll" ] || [ -f "$(dirname "$TARGET")/d3d12core.dll" ] || \
       find "$(dirname "$TARGET")" -maxdepth 2 -iname "d3d12*.dll" 2>/dev/null | grep -q . || \
       find "$(dirname "$TARGET")" -maxdepth 3 -iname "*re_chunk_000*.pak" 2>/dev/null | grep -q .; then
        es_dx12=true
    fi

    # Auto-detección de versión de Windows óptima si no está especificada en la BD (Mejora 1)
    if [ -z "$GAME_WINVER" ]; then
        if [ -n "$PE_WINVER" ]; then
            GAME_WINVER="$PE_WINVER"
        else
            t_base=$(basename "$TARGET" | tr '[:upper:]' '[:lower:]')
            if [[ "$t_base" =~ ^(gameranger)\.exe$ ]]; then
                GAME_WINVER="win7"
            elif [ "$es_64bit" = true ] || [ "$es_dx12" = true ]; then
                # Los juegos de 64 bits y DirectX 12 NUNCA deben ejecutarse en Windows XP
                GAME_WINVER="win10"
            elif [[ "$t_base" =~ ^(empires2|age2_x1|starcraft|ra2|diablo|fallout|carmageddon)\.exe$ ]]; then
                # Solo clásicos 2D DirectDraw retro van a Windows XP para preservar paleta de 8 bits
                GAME_WINVER="winxp"
            else
                GAME_WINVER="win10"
            fi
        fi
    fi

    # Salvaguarda obligatoria universal: Si el binario es nativo de 64 bits o DirectX 12,
    # es técnicamente imposible que ejecute en Windows XP (D3D12CreateDevice no existe en XP).
    # Corregir automáticamente a Windows 10 para garantizar inicialización gráfica perfecta:
    if [ "$es_64bit" = true ] || [ "$es_dx12" = true ]; then
        if [ "$GAME_WINVER" = "winxp" ]; then
            echo "[!] Corrección de compatibilidad: Binario moderno de 64 bits / DirectX 12 detectado. Ajustando versión de Windows a Windows 10."
            GAME_WINVER="win10"
        fi
    fi

    # Salvaguarda DX12 para GPUs sin Ray Tracing por hardware (evita fallo D3D12CreateDevice):
    if [ "$es_dx12" = true ]; then
        if [ "$IS_LOW_SPEC_GPU" = true ] || [ "$GPU_IS_ENTRY_LEVEL" = true ] || ! echo "$DETECTED_GPU" | grep -qiE 'RTX|Radeon RX [6-9][0-9]{3}'; then
            [ -z "$VKD3D_CONFIG" ] && export VKD3D_CONFIG="nodxr"
            [ -z "$VKD3D_FEATURE_LEVEL" ] && export VKD3D_FEATURE_LEVEL="12_0"
        fi
    fi

    # Para GameRanger forzar siempre win7 (evita incompatibilidad de CEF y modo Win10)
    if [[ "$TARGET" =~ [Gg]ame[Rr]anger ]]; then
        GAME_WINVER="win7"
    fi

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
            if [ -f "${DIR}/.gameranger_prefs_backup/Settings" ] && { [ ! -s "${GR_PREFS}/Settings" ] || ! grep -q "SessMail" "${GR_PREFS}/Settings" 2>/dev/null; }; then
                cp -p "${DIR}/.gameranger_prefs_backup/Settings" "${GR_PREFS}/Settings" 2>/dev/null || true
            fi
            for u_dir in "${WINEPREFIX}/drive_c/users"/*; do
                if [ -d "$u_dir" ] && [ "$(basename "$u_dir")" != "Public" ]; then
                    u_prefs="${u_dir}/AppData/Roaming/GameRanger/GameRanger Prefs"
                    mkdir -p "$u_prefs"
                    if [ -f "${DIR}/.gameranger_prefs_backup/Settings" ] && { [ ! -s "${u_prefs}/Settings" ] || ! grep -q "SessMail" "${u_prefs}/Settings" 2>/dev/null; }; then
                        cp -p "${DIR}/.gameranger_prefs_backup/Settings" "${u_prefs}/Settings" 2>/dev/null || true
                    fi
                fi
            done
        fi

        # Sanitizar coordenadas de ventana y estado de descolapsado en Settings para evitar que GameRanger se abra fuera de pantalla o colapsado
        python3 -c "
import struct, glob, os
files = glob.glob('${WINEPREFIX}/drive_c/users/*/AppData/Roaming/GameRanger/GameRanger Prefs/Settings')
if os.path.exists('${DIR}/.gameranger_prefs_backup/Settings'):
    files.append('${DIR}/.gameranger_prefs_backup/Settings')
for sf in files:
    try:
        with open(sf, 'rb') as f:
            data = bytearray(f.read())
        mod = False
        # 1. Descolapsar lobby principal (ClpsMain = 0) para que la lista de salas y juegos aparezca visible
        c_idx = data.find(b'ClpsMain')
        if c_idx != -1 and len(data) > c_idx + 17:
            if data[c_idx + 17] != 0:
                data[c_idx + 17] = 0
                mod = True
        # 2. Sanitizar coordenadas de ventana para evitar que se abran fuera de pantalla o en modo oculto (SW_HIDE)
        for tag, dl, dt, dw, dh in [(b'WBndMain', 60, 60, 804, 553), (b'WBndBudd', 874, 60, 220, 553)]:
            idx = data.find(tag)
            if idx != -1:
                wp = idx + 16
                l, f, s, mx, my, mx2, my2, left, top, right, bottom = struct.unpack('<IIIiiiiiiii', data[wp:wp+44])
                if left < 0 or top < 0 or s != 1 or right <= left or bottom <= top or left > 1920:
                    data[wp:wp+44] = struct.pack('<IIIiiiiiiii', 44, 0, 1, -1, -1, -1, -1, dl, dt, dl+dw, dt+dh)
                    mod = True
        if mod:
            with open(sf, 'wb') as f:
                f.write(data)
    except Exception:
        pass
" 2>/dev/null || true

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


# 4.3 Obtener directorio y nombre base del archivo objetivo de ejecución
TARGET_DIR="$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd || dirname "$TARGET")"
TARGET_FILE="$(basename "$TARGET")"

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
    mkdir -p "$WINEPREFIX"
    if [ -f "${DIR}/wineprefix/system.reg" ] && [ "$WINEPREFIX" != "${DIR}/wineprefix" ]; then
        echo "[*] Inicializando sandbox aislado de forma ultrarrápida a partir de la plantilla base..."
        cp -a "${DIR}/wineprefix"/* "${WINEPREFIX}/" 2>/dev/null || true
    else
        echo "[*] Creando sandbox limpio e íntegro para el juego..."
        DISPLAY="" WINEDLLOVERRIDES="mscoree,mshtml=;winemenubuilder.exe=d;" WINEPREFIX="$WINEPREFIX" "$WINE_CMD" wineboot -u >/dev/null 2>&1 || true
    fi
    mkdir -p "${WINEPREFIX}/dosdevices"
    [ ! -e "${WINEPREFIX}/dosdevices/c:" ] && ln -s ../drive_c "${WINEPREFIX}/dosdevices/c:" 2>/dev/null || true
    [ ! -e "${WINEPREFIX}/dosdevices/z:" ] && ln -s / "${WINEPREFIX}/dosdevices/z:" 2>/dev/null || true
fi

# 7.1 Auto-verificación e integración de DXVK (DirectX 9/10/11 -> Vulkan) en el prefijo activo
if [ "$RENDERER_IN_USE" != "WineD3D (OpenGL Compatibilidad)" ]; then
    if [ ! -L "${WINEPREFIX}/drive_c/windows/system32/d3d11.dll" ] && [ -d "${WINEPREFIX}/drive_c/windows/system32" ]; then
        if command -v dxvk-setup &>/dev/null; then
            echo "[*] Instalando y vinculando librerías DXVK (DirectX -> Vulkan) en el prefijo..."
            WINEPREFIX="$WINEPREFIX" dxvk-setup install -y >/dev/null 2>&1 || true
        elif [ -d "/usr/lib/dxvk/wine64" ]; then
            for dll in d3d11 d3d10core d3d9 dxgi; do
                [ -f "/usr/lib/dxvk/wine64/${dll}.dll.so" ] && ln -sf "/usr/lib/dxvk/wine64/${dll}.dll.so" "${WINEPREFIX}/drive_c/windows/system32/${dll}.dll" 2>/dev/null || true
                [ -f "/usr/lib/dxvk/wine32/${dll}.dll.so" ] && ln -sf "/usr/lib/dxvk/wine32/${dll}.dll.so" "${WINEPREFIX}/drive_c/windows/syswow64/${dll}.dll" 2>/dev/null || true
            done
        fi
    fi
fi

# 7.2 Inyección silenciosa de runtimes esenciales (Visual C++, MFC, DirectX) desde la plantilla base (Mejora 3)
if [ -d "${DIR}/wineprefix/drive_c/windows" ] && [ "$WINEPREFIX" != "${DIR}/wineprefix" ]; then
    for r_dll in mfc42.dll vcruntime140.dll vcruntime140_1.dll msvcp140.dll d3dx9_43.dll d3dcompiler_43.dll d3dcompiler_47.dll xinput1_3.dll; do
        if [ -f "${DIR}/wineprefix/drive_c/windows/syswow64/${r_dll}" ] && [ ! -f "${WINEPREFIX}/drive_c/windows/syswow64/${r_dll}" ]; then
            cp -n "${DIR}/wineprefix/drive_c/windows/syswow64/${r_dll}" "${WINEPREFIX}/drive_c/windows/syswow64/" 2>/dev/null || true
        fi
        if [ -f "${DIR}/wineprefix/drive_c/windows/system32/${r_dll}" ] && [ ! -f "${WINEPREFIX}/drive_c/windows/system32/${r_dll}" ]; then
            cp -n "${DIR}/wineprefix/drive_c/windows/system32/${r_dll}" "${WINEPREFIX}/drive_c/windows/system32/" 2>/dev/null || true
        fi
    done
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

# 8.1 Configuración de Versión de Windows por juego en AppDefaults (Mejora 1: win10 / win7 / winxp)
if [ -n "$GAME_WINVER" ]; then
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${TARGET_FILE}" /v "Version" /t REG_SZ /d "$GAME_WINVER" /f >/dev/null 2>&1 || true
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

# 10. Soporte para AMD FSR (FidelityFX Super Resolution - Reescalado de FPS) (Mejora 4)
ACTIVAR_FSR_FINAL=0
MODO_FSR_FINAL="quality"
if [ -n "$GAME_FSR" ] && [ "$GAME_FSR" != "off" ] && [ "$GAME_FSR" != "0" ]; then
    ACTIVAR_FSR_FINAL=1
    MODO_FSR_FINAL="$GAME_FSR"
elif [ "$ACTIVAR_FSR" = "1" ]; then
    ACTIVAR_FSR_FINAL=1
    MODO_FSR_FINAL="${FSR_MODE:-quality}"
fi

if [ "$ACTIVAR_FSR_FINAL" -eq 1 ]; then
    export WINE_FULLSCREEN_FSR=1
    export WINE_FULLSCREEN_FSR_MODE="$MODO_FSR_FINAL"
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
export WINEDLLOVERRIDES="winemenubuilder.exe=d;dinput8=n,b;dxgi=n,b;d3d11=n,b;d3d10core=n,b;d3d9=n,b;d3d8=n,b;ddraw=n,b;dplayx=n,b;dpnet=n,b;dpwsockx=n,b;vorbisfile=n,b;vorbishooked=n,b;dsound=n,b;secur32=b;wininet=b;winhttp=b;ws2_32=b;iphlpapi=b;dnsapi=b;${WINEDLLOVERRIDES}"

# 11.1 Configuración específica para el cliente de lobby GameRanger
EXTRA_APP_ARGS=""
if [[ "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]]; then
    # GameRanger es una aplicación de escritorio/chat con interfaz Win32 GDI y CEF ligero.
    # Sus configuraciones específicas de GDI y DllOverrides están aisladas en AppDefaults\GameRanger.exe
    # para permitir que los juegos 3D (Need for Speed, GTA, etc.) disfruten de DXVK y pantalla completa al 100%.
    export RENDERER_IN_USE="GDI / Nativo (Modo Ventana) + 3D DXVK para Juegos"
    unset PROTON_USE_WINED3D
    unset LIBGL_ALWAYS_SOFTWARE
    export WINEDLLOVERRIDES="winemenubuilder.exe=d;dinput8=n,b;d3d9=n,b;d3d8=n,b;dxgi=n,b;d3d11=n,b;ddraw=n,b;dplayx=n,b;dpnet=n,b;dpwsockx=n,b;vorbisfile=n,b;vorbishooked=n,b;dsound=n,b;mfc42=n,b;mfc42u=n,b;riched20=n,b;riched32=n,b;${WINEDLLOVERRIDES}"
    unset DXVK_CONFIG_FILE
    unset DXVK_STATE_CACHE_PATH
    unset DXVK_ASYNC
    unset DXVK_GPLASYNCCACHE

    # Auto-optimizar pantalla completa y resolución nativa para todos los juegos de la biblioteca de GameRanger
    for db in "${DIR}/programas_usuario.db" "${DIR}/programas.db"; do
        if [ -f "$db" ]; then
            while IFS='|' read -r _pname ppath _rest; do
                [ -z "$ppath" ] && continue
                pdir="$(dirname "$ppath" 2>/dev/null || true)"
                if [ -d "$pdir" ]; then
                    find "$pdir" -maxdepth 3 -iname "*widescreen*.ini" 2>/dev/null | while read -r wf_ini; do
                        sed -i "s/^ResX = .*/ResX = ${best_w}/" "$wf_ini" 2>/dev/null || true
                        sed -i "s/^ResY = .*/ResY = ${best_h}/" "$wf_ini" 2>/dev/null || true
                        sed -i "s/^WindowedMode = .*/WindowedMode = 4/" "$wf_ini" 2>/dev/null || true
                        sed -i "s/^ForceAspectRatio = .*/ForceAspectRatio = auto/" "$wf_ini" 2>/dev/null || true
                    done
                fi
            done < "$db"
        fi
    done

    # Desactivar gamemode para evitar mensajes en consola (GameRanger es una app de chat 2D)
    GAMEMODE=""

    # Registro de GameRanger: garantizar MODO VENTANA nativa (decoraciones completas, sin captura fullscreen ni escritorio virtual)
    if [ ! -f "${WINEPREFIX}/.gameranger_reg_v6" ]; then
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe" /v "Version" /t REG_SZ /d "win7" /f >/dev/null 2>&1 || true
        # Eliminar cualquier contenedor virtual o renderer GL forzado que cause ventana negra de fondo
        "$WINE_CMD" reg delete "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\X11 Driver" /v "Desktop" /f >/dev/null 2>&1 || true
        # Forzar renderer GDI en Direct3D para que CEF y GameRanger no intenten crear contextos GL conflictivos
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\Direct3D" /v "renderer" /t REG_SZ /d "gdi" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\Direct3D" /v "MaxVersionGL" /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true
        # Limpiar overrides que interfieren con la red Winsock nativa de Wine
        "$WINE_CMD" reg delete "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "dnsapi" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg delete "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "iphlpapi" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg delete "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "ws2_32" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg delete "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "wininet" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg delete "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "secur32" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "dxgi" /t REG_SZ /d "builtin" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "d3d11" /t REG_SZ /d "builtin" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "d3d9" /t REG_SZ /d "builtin" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "d3d10core" /t REG_SZ /d "builtin" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "mfc42" /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "mfc42u" /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\X11 Driver" /v "Decorated" /t REG_SZ /d "Y" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\X11 Driver" /v "Managed" /t REG_SZ /d "Y" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\X11 Driver" /v "GrabFullscreen" /t REG_SZ /d "N" /f >/dev/null 2>&1 || true
        # Asegurar hooks de mods y ASI loaders universales en el registro de Wine para juegos
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v "dinput8" /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v "d3d9" /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v "d3d8" /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v "dxgi" /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v "d3d11" /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v "vorbisfile" /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v "vorbishooked" /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v "dsound" /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
        # Optimización de red e Internet para máxima compatibilidad con servidores antiguos de GameRanger y certificados TLS
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v "CertificateRevocation" /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v "WarnonBadCertRecving" /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v "SecureProtocols" /t REG_DWORD /d 2720 /f >/dev/null 2>&1 || true
        touch "${WINEPREFIX}/.gameranger_reg_v6" 2>/dev/null || true
    fi

    # GameRanger es un programa/lobby de escritorio, debe ejecutarse en MODO VENTANA (NUNCA en pantalla completa)
    ESCRITORIO_VIRTUAL="0"
    EXTRA_APP_ARGS="--disable-gpu --disable-gpu-compositing"
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
            if [ -n "$max_w" ]; then
                ACTIVE_MON_W="$max_w"
                ACTIVE_MON_H="$max_h"
                ACTIVE_MON_X="$max_x"
                ACTIVE_MON_Y="$max_y"
            elif [ -n "$prim_w" ]; then
                ACTIVE_MON_W="$prim_w"
                ACTIVE_MON_H="$prim_h"
                ACTIVE_MON_X="$prim_x"
                ACTIVE_MON_Y="$prim_y"
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

# Candado 3: Respaldo atómico seguro antes de modificar cualquier archivo de configuración de juego
crear_respaldo_seguro() {
    local arch="$1"
    if [ -f "$arch" ]; then
        [ ! -f "${arch}.vessel_orig" ] && cp -p "$arch" "${arch}.vessel_orig" 2>/dev/null || true
        [ ! -f "${arch}.vessel_bak" ] && cp -p "$arch" "${arch}.vessel_bak" 2>/dev/null || true
    fi
}

aplicar_perfil_aislado_juego() {
    local perfil_id="generico"

    if [ -n "$PE_ENGINE" ] && [ "$PE_ENGINE" != "generico" ]; then
        perfil_id="$PE_ENGINE"
    elif [[ "$TARGET_FILE" =~ (GTA5|PlayGTAV|gta5) ]] || [[ "$TARGET_DIR" =~ (GTA\ V|Grand\ Theft\ Auto\ V|gta_data) ]]; then
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
    elif [ -f "${TARGET_DIR}/ddraw.ini" ] || [ -f "${TARGET_DIR}/ddraw.dll" ] || \
         [[ "$TARGET_FILE" =~ (empires2|age2_x1|starcraft|ra2|diablo|fallout|carmageddon|totalannihilation|warcraft|war3|heroes3|homm3|civ3|simcity4|caesar3|pharaoh|zeus|tiberiansun|nox|dune2000|redalert|commandos|desperados) ]] || \
         { grep -qi -m 1 "ddraw\.dll" "$TARGET" 2>/dev/null && ! grep -qi -m 1 "d3d1[1-2]\.dll\|dxgi\.dll" "$TARGET" 2>/dev/null; }; then
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
                    crear_respaldo_seguro "$sxml"
                    sed -i "s/<ScreenWidth value=\"[0-9]*\"/<ScreenWidth value=\"${gta_w}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<ScreenHeight value=\"[0-9]*\"/<ScreenHeight value=\"${gta_h}\"/" "$sxml" 2>/dev/null || true
                    sed -i 's/<Windowed value="[0-9]*"/<Windowed value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<VSync value="[0-9]*"/<VSync value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<ShadowQuality value="[0-9]*"/<ShadowQuality value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<GrassQuality value="[0-9]*"/<GrassQuality value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<ShaderQuality value="[0-9]*"/<ShaderQuality value="1"/' "$sxml" 2>/dev/null || true
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

            # 3. Optimización en commandline.txt (priorizando -scOfflineOnly y máxima estabilidad geométrica 3D)
            local gta_cmdline="${TARGET_DIR}/commandline.txt"
            [ -f "$gta_cmdline" ] && crear_respaldo_seguro "$gta_cmdline"
            cat <<EOF > "$gta_cmdline"
-width ${gta_w}
-height ${gta_h}
-fullscreen
-novsync
-scOfflineOnly
-ignoreDifferentVideoCard
-ShadowQuality 0
-ReflectionQuality 0
-GrassQuality 0
-WaterQuality 0
-ParticleQuality 0
-Tessellation 0
-shadowSoftness 0
EOF
            echo "[+] GTA V optimizado: Pantalla completa nativa, shaders estables y geometría 3D calibrada (sin deformación de mallas)."

            # Garantizar steam_settings completo para emulador Goldberg (evita bloqueos de red e inicialización de perfil)
            if [ ! -d "${TARGET_DIR}/steam_settings" ]; then
                mkdir -p "${TARGET_DIR}/steam_settings"
                cat <<'EOF_DEPOTS' > "${TARGET_DIR}/steam_settings/depots.txt"
228984 	
228990 	
271591 			
271592 	
271593 			
271594 			
271595
EOF_DEPOTS
                cat <<'EOF_DLC' > "${TARGET_DIR}/steam_settings/DLC.txt"
771300 = Grand Theft Auto V - Criminal Enterprise Starter Pack
413180 = Grand Theft Auto V – Bonus $500,000
362003 = Grand Theft Auto V
362002 = Grand Theft Auto V – Bonus $1,350,000
362001 = Grand Theft Auto V – Bonus $1,500,000
362000 = Grand Theft Auto V – Bonus $1,500,000 + GTA: San Andreas 
EOF_DLC
                echo "Player" > "${TARGET_DIR}/steam_settings/force_account_name.txt"
                [ ! -f "${TARGET_DIR}/steam_appid.txt" ] && echo "271590" > "${TARGET_DIR}/steam_appid.txt"
            fi

            # Auto-vincular partida guardada base si el prefijo no tiene partidas para evitar bucles de carga en prólogo
            local gta_save_dir="${WINEPREFIX}/drive_c/users/${USER}/AppData/Roaming/Goldberg SocialClub Emu Saves/GTA V/0F74F4C4"
            mkdir -p "$gta_save_dir"
            if ! ls "$gta_save_dir"/SGTA* >/dev/null 2>&1; then
                local cand_save
                cand_save=$(find "${TARGET_DIR}/.." -maxdepth 4 -iname "SGTA50015" 2>/dev/null | head -n 1)
                if [ -n "$cand_save" ] && [ -f "$cand_save" ]; then
                    echo "[+] Partida guardada base detectada e instalada para carga inmediata sin bucle de prólogo."
                    cp -n "$(dirname "$cand_save")"/SGTA* "$gta_save_dir/" 2>/dev/null || true
                fi
            fi

            # Overrides específicos de DirectX 11, Bink Video, Social Club y ASI Loader
            export WINEDLLOVERRIDES="bink2w64=n,b;asiloader=n,b;dinput8=n,b;d3dcompiler_46=n,b;d3dcompiler_43=n,b;d3dcsx_46=n,b;socialclub=n,b;steam_api64=n,b;dxgi=n,b;d3d11=n,b;d3d9=n,b;${WINEDLLOVERRIDES}"
            ;;

        rockstar_gtasa)
            echo "[+] Perfil Activo: Rockstar Games (GTA San Andreas / Trilogy) [Aislado]"
            limpiar_zombies_juego "gta_sa\.exe"
            # Desactivar ventana forzada de mods para garantizar pantalla completa nativa
            find "$TARGET_DIR" -iname "III.VC.SA.WindowedMode.ini" 2>/dev/null | while read -r wm_ini; do
                crear_respaldo_seguro "$wm_ini"
                sed -i "s/^ShowBorder = .*/ShowBorder = 0/" "$wm_ini" 2>/dev/null || true
            done
            find "$TARGET_DIR" -iname "III.VC.SA.WindowedMode.asi" 2>/dev/null | while read -r wm_asi; do
                mv "$wm_asi" "${wm_asi}.disabled" 2>/dev/null || true
            done
            # Configurar Widescreen Fix
            find "$TARGET_DIR" -maxdepth 3 -iname "*widescreen*.ini" 2>/dev/null | while read -r wf_ini; do
                crear_respaldo_seguro "$wf_ini"
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
                crear_respaldo_seguro "$wf_ini"
                sed -i "s/^ResX = .*/ResX = ${best_w}/" "$wf_ini" 2>/dev/null || true
                sed -i "s/^ResY = .*/ResY = ${best_h}/" "$wf_ini" 2>/dev/null || true
                sed -i "s/^ForceAspectRatio = .*/ForceAspectRatio = auto/" "$wf_ini" 2>/dev/null || true
            done
            export WINEDLLOVERRIDES="dinput8=n,b;d3d9=n,b;scripts=n,b;${WINEDLLOVERRIDES}"
            ;;

        capcom_re_engine)
            echo "[+] Perfil Activo: Capcom RE Engine [Aislado]"
            # RE Engine es un motor moderno (DirectX 12 / 64-bit), asegurar modo Windows 10 en Wine
            "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${TARGET_FILE}" /v "Version" /t REG_SZ /d "win10" /f >/dev/null 2>&1 || true
            GAME_WINVER="win10"
            limpiar_zombies_juego "re4\.exe|re2\.exe|re3\.exe|re7\.exe|re8\.exe|dmc5\.exe"

            # 1. Auto-vincular o copiar DLLs de VKD3D-Proton (DirectX 12) a la raíz si están en subcarpetas
            for sub_vkd3d in "${TARGET_DIR}/dxvk" "${TARGET_DIR}/vkd3d" "${TARGET_DIR}/_CommonRedist"; do
                if [ -d "$sub_vkd3d" ]; then
                    if [ -f "${sub_vkd3d}/d3d12.dll" ]; then
                        if [ ! -f "${TARGET_DIR}/d3d12.dll" ] || [ ! -s "${TARGET_DIR}/d3d12.dll" ]; then
                            cp -f "${sub_vkd3d}/d3d12.dll" "${TARGET_DIR}/" 2>/dev/null || true
                        fi
                        if [ -f "${sub_vkd3d}/d3d12core.dll" ] && { [ ! -f "${TARGET_DIR}/d3d12core.dll" ] || [ ! -s "${TARGET_DIR}/d3d12core.dll" ]; }; then
                            cp -f "${sub_vkd3d}/d3d12core.dll" "${TARGET_DIR}/" 2>/dev/null || true
                        fi
                        if [ -d "${TARGET_DIR}/D3D12" ] && [ -f "${sub_vkd3d}/d3d12core.dll" ]; then
                            cp -f "${sub_vkd3d}/d3d12core.dll" "${TARGET_DIR}/D3D12/D3D12Core.dll" 2>/dev/null || true
                        fi
                    fi
                fi
            done
            # Reemplazar la DLL oficial de Microsoft Windows por la de Vulkan en D3D12/ si existe d3d12core.dll
            if [ -d "${TARGET_DIR}/D3D12" ] && [ -f "${TARGET_DIR}/d3d12core.dll" ]; then
                cp -f "${TARGET_DIR}/d3d12core.dll" "${TARGET_DIR}/D3D12/D3D12Core.dll" 2>/dev/null || true
            fi

            # 2. Desactivar Ray Tracing (DXR) para evitar fallo D3D12CreateDevice en GPUs sin RT (Maxwell/Pascal/Intel)
            export VKD3D_CONFIG="nodxr"
            export VKD3D_FEATURE_LEVEL="12_0"

            # 3. Copiar configuración limpia si existe en opti/local_config.ini
            if [ -f "${TARGET_DIR}/opti/local_config.ini" ] && [ ! -f "${TARGET_DIR}/local_config.ini" ]; then
                cp -p "${TARGET_DIR}/opti/local_config.ini" "${TARGET_DIR}/local_config.ini" 2>/dev/null || true
            fi

            # 4. Limpiar adaptadores gráficos ajenos hardcodeados en local_config.ini / *config*.ini
            find "$TARGET_DIR" -maxdepth 3 -iname "*config*.ini" 2>/dev/null | while read -r c_ini; do
                if grep -qi "\[Render/Adapter\]" "$c_ini" 2>/dev/null || grep -qi "VendorId=" "$c_ini" 2>/dev/null; then
                    crear_respaldo_seguro "$c_ini"
                    sed -i '/\[Render\/Adapter\]/,/^\[/ { /^\[Render\/Adapter\]/d; /^Description=/d; /^VendorId=/d; /^DeviceId=/d; }' "$c_ini" 2>/dev/null || true
                    sed -i '/^Description=.*Graphics/d; /^VendorId=[0-9]*/d; /^DeviceId=[0-9]*/d' "$c_ini" 2>/dev/null || true
                fi
            done

            # 5. Configurar visualización óptima en configs de RE Engine
            find "$TARGET_DIR" -maxdepth 3 -name "*config*.ini" 2>/dev/null | while read -r re_ini; do
                if grep -q "\[AppRender\]" "$re_ini" 2>/dev/null || grep -q "\[RenderConfig\]" "$re_ini" 2>/dev/null; then
                    crear_respaldo_seguro "$re_ini"
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
            export WINEDLLOVERRIDES="d3d12=n,b;d3d12core=n,b;dxgi=n,b;d3d11=n,b;d3dcompiler_47=n,b;xinput1_3=n,b;xinput1_4=n,b;${WINEDLLOVERRIDES}"
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
                            crear_respaldo_seguro "$cini"
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
                if grep -q "\[WinDrv.WindowsClient\]\|\[D3DDrv.D3DRenderDevice\]\|\[/Script/Engine.GameUserSettings\]" "$ueini" 2>/dev/null; then
                    crear_respaldo_seguro "$ueini"
                fi
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
            echo "[+] Perfil Activo: Clásico DirectDraw Universal (OpenGL / Multi-GPU) [Aislado]"
            # 1. Modo Windows XP automático en Wine AppDefaults para este juego (elimina incompatibilidad de paleta en Win10)
            "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${TARGET_FILE}" /v "Version" /t REG_SZ /d "winxp" /f >/dev/null 2>&1 || true

            # 2. Conmutación universal a OpenGL (compatible al 100% en Intel, AMD y NVIDIA sin fallos de paleta 8-bit)
            export PROTON_USE_WINED3D=1
            export RENDERER_IN_USE="OpenGL Universal (DirectDraw Clásico)"
            unset DXVK_CONFIG_FILE
            export DXVK_HUD=0

            # 2.1 Auto-inyección de cnc-ddraw si está disponible en caché local y no en el juego
            if [ ! -f "${TARGET_DIR}/ddraw.dll" ] && [ -f "${DIR}/librerias_cache/cnc-ddraw/ddraw.dll" ]; then
                echo "[+] Inyectando cnc-ddraw desde caché de Vessel para compatibilidad DirectX 1-7 perfecta..."
                cp -p "${DIR}/librerias_cache/cnc-ddraw/ddraw.dll" "${TARGET_DIR}/ddraw.dll" 2>/dev/null || true
                [ -d "${DIR}/librerias_cache/cnc-ddraw/shaders" ] && cp -rn "${DIR}/librerias_cache/cnc-ddraw/shaders" "${TARGET_DIR}/" 2>/dev/null || true
                [ -f "${DIR}/librerias_cache/cnc-ddraw/ddraw.ini" ] && cp -n "${DIR}/librerias_cache/cnc-ddraw/ddraw.ini" "${TARGET_DIR}/ddraw.ini" 2>/dev/null || true
            fi

            # 3. Optimización automática de cnc-ddraw en OpenGL
            find "$TARGET_DIR" -maxdepth 2 -iname "ddraw.ini" 2>/dev/null | while read -r ddini; do
                crear_respaldo_seguro "$ddini"
                sed -i 's/^renderer=.*/renderer=opengl/' "$ddini" 2>/dev/null || true
                sed -i 's/^fullscreen=.*/fullscreen=true/' "$ddini" 2>/dev/null || true
                sed -i 's/^windowed=.*/windowed=false/' "$ddini" 2>/dev/null || true
                sed -i "s/^width=.*/width=${best_w}/" "$ddini" 2>/dev/null || true
                sed -i "s/^height=.*/height=${best_h}/" "$ddini" 2>/dev/null || true
                sed -i 's/^boxing=.*/boxing=false/' "$ddini" 2>/dev/null || true
                sed -i 's/^maintas=.*/maintas=false/' "$ddini" 2>/dev/null || true
                if [ -f "${TARGET_DIR}/Shaders/interpolation/catmull-rom-bilinear.glsl" ]; then
                    sed -i 's|^shader=.*|shader=Shaders\\interpolation\\catmull-rom-bilinear.glsl|' "$ddini" 2>/dev/null || true
                else
                    sed -i 's|^shader=.*|shader=Bilinear|' "$ddini" 2>/dev/null || true
                fi
            done

            # 4. Configurar DirectDraw nativo en el registro de Wine (para juegos sin cnc-ddraw)
            "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "DirectDrawRenderer" /t REG_SZ /d "opengl" /f >/dev/null 2>&1 || true
            "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "OffscreenRenderingMode" /t REG_SZ /d "fbo" /f >/dev/null 2>&1 || true

            # 5. Overrides seguros: ddraw y dsound nativos (para cnc-ddraw), y librerías 3D a builtin (WineD3D OpenGL)
            export WINEDLLOVERRIDES="ddraw=n,b;dsound=n,b;d3d9=b;d3d11=b;dxgi=b;d3d8=b;${WINEDLLOVERRIDES}"
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

# Modo Pantalla Nativo Directo en Hardware (sin capas virtuales por defecto)
[ -z "$ESCRITORIO_VIRTUAL" ] && ESCRITORIO_VIRTUAL="0"
RUN_PREFIX=""
if [ "$ESCRITORIO_VIRTUAL" = "1" ]; then
    RUN_PREFIX="explorer /desktop=${DESKTOP_NAME:-GameRanger},${DESKTOP_RES:-1024x720}"
fi

GAMESCOPE_PREFIX=""
if [ "$PERFIL_RENDIMIENTO" = "extremo" ] && [[ ! "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]]; then
    if command -v gamescope &>/dev/null; then
        GAMESCOPE_PREFIX="gamescope -W ${best_w:-1280} -H ${best_h:-720} -r 60 -F fsr --"
    fi
fi

perf_label="${PERFIL_RENDIMIENTO:-inteligente}"
case "$perf_label" in
    inteligente|maximo) perf_label="Inteligente (Autocalibrado)" ;;
    estandar) perf_label="Estándar / Compatibilidad" ;;
    extremo) perf_label="Portátil Extremo (FSR Boost)" ;;
    ahorro) perf_label="Ahorro de Energía" ;;
esac

echo ""
echo "[+] Ejecutando con Perfil [${perf_label}] (Vessel v1.0)..."
echo "    - CPU: ${CPU_MODEL} (${CPU_CORES} Hilos)"
echo "    - GPU: ${DETECTED_GPU}"
echo "    - Versión de Vessel: v1.0 (Producción)"
echo "    - Renderizador: ${RENDERER_IN_USE:-DXVK (Vulkan)}"
echo "    - Fsync/Esync: $([ "$WINEFSYNC" = "1" ] && echo "Fsync Activo" || echo "Esync Activo")"
echo "    - Límite de FPS: ${LIMITE_FPS:-60} FPS"
fsr_banner="Desactivado"
if [ "$ACTIVAR_FSR_FINAL" -eq 1 ]; then
    fsr_banner="Activo [Modo: ${MODO_FSR_FINAL}, Nitidez: ${FSR_STRENGTH:-2}]"
fi
echo "    - AMD FSR Upscaling: ${fsr_banner}"
echo "    - Versión de Windows: ${GAME_WINVER^^}"
if [ -n "$PE_BITS" ] && [ "$PE_BITS" != "0" ]; then
    echo "    - Arquitectura / Binario: ${PE_BITS}-bit (Subsystem ${PE_SUBSYS:-N/A}) | API: ${PE_API^^}"
fi
if [[ "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]]; then
    echo "    - GameMode: Desactivado (Aplicación de Escritorio / Lobby)"
    echo "    - Modo Pantalla: Ventana de Escritorio (No Pantalla Completa)"
    echo "    - Red / Multijugador: Puertos 16000 UDP y DirectPlay Abiertos (100% Conectado)"
else
    echo "    - GameMode: $([ -n "$GAMEMODE" ] && echo "Activo" || echo "Inactivo")"
    echo "    - Modo Pantalla: Pantalla Completa Nativa Directa (Hardware)"
    echo "    - Caché de Shaders: NVMe SSD (~/.cache/dxvk)"
fi
[ -f "${DIR}/herramientas/gamecontrollerdb.txt" ] && echo "    - Mapeo de Mandos: SDL2 GameControllerDB Activo (+2.300 mandos)"
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

# Guardián en segundo plano para asegurar pantalla completa en juegos retro que no manejan fullscreen nativo
WATCHDOG_PID=""
if [ -n "${DISPLAY:-}" ] && [[ ! "$TARGET_FILE" =~ ([Gg]ame[Rr]anger|winecfg|regedit|cmd|notepad|GTA|GTA5|PlayGTAV) ]]; then
    (
        for i in $(seq 1 30); do
            sleep 0.5
            if command -v wmctrl &>/dev/null; then
                wmctrl -l 2>/dev/null | grep -iE 'Resident|SWAT|Age of Empires|BioShock|Unreal|Speed|NFS' | grep -viE 'GameRanger|Winecfg|Error|Debug|GTA' | while read -r wid rest; do
                    wmctrl -i -r "$wid" -e "0,${ACTIVE_MON_X},${ACTIVE_MON_Y},${best_w},${best_h}" 2>/dev/null || true
                    wmctrl -i -r "$wid" -b add,fullscreen 2>/dev/null || true
                done
            elif command -v xwininfo &>/dev/null && command -v xprop &>/dev/null; then
                xwininfo -root -tree 2>/dev/null | grep -iE '("Resident Evil|"Swat|"BH6|"re4|"Age of Empires)' | grep -viE 'GameRanger|Winecfg|GTA' | grep -oE '0x[0-9a-fA-F]+' | head -n 3 | while read -r wid; do
                    xprop -id "$wid" -f _NET_WM_STATE 32a -set _NET_WM_STATE _NET_WM_STATE_FULLSCREEN 2>/dev/null || true
                done
            fi
        done
    ) &
    WATCHDOG_PID=$!
fi

# Guardián inteligente en segundo plano para GameRanger y juegos multijugador lanzados desde el lobby
GR_WATCHDOG_PID=""
if [[ "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]]; then
    (
        seen_wids=""
        for i in $(seq 1 7200); do
            sleep 1
            if [ -n "${DISPLAY:-}" ]; then
                if command -v wmctrl &>/dev/null; then
                    while read -r wid desk x y w h wmclass client title; do
                        [ -z "$wid" ] && continue

                        # 1. Ventanas de GameRanger (Asistente, Ventana Principal, Lista de Amigos, etc.)
                        if [[ "$wmclass" =~ [Gg]ame[Rr]anger ]] || [[ "$title" =~ ([Gg]ame[Rr]anger|[Aa]ccount [Aa]ssistant|[Ff]riends) ]]; then
                            if [[ ! "$seen_wids" =~ "$wid" ]]; then
                                # Quitar fullscreen o maximizado una sola vez cuando la ventana es creada
                                wmctrl -i -r "$wid" -b remove,fullscreen,maximized_vert,maximized_horz 2>/dev/null || true

                                # Determinar posición óptima según el tipo de ventana
                                target_x="$ACTIVE_MON_X"
                                target_y="$ACTIVE_MON_Y"

                                if [[ "$title" =~ [Aa]ssistant ]]; then
                                    # El asistente de inicio de sesión se centra en el monitor activo
                                    target_x=$((ACTIVE_MON_X + (ACTIVE_MON_W - w) / 2))
                                    target_y=$((ACTIVE_MON_Y + (ACTIVE_MON_H - h) / 2))
                                elif [[ "$title" =~ [Ff]riends ]]; then
                                    # La lista de amigos se ubica a la derecha del lobby principal
                                    target_x=$((ACTIVE_MON_X + 874))
                                    target_y=$((ACTIVE_MON_Y + 60))
                                elif [[ "$title" =~ [Gg]ame[Rr]anger ]]; then
                                    # El lobby principal se ubica en la posición principal
                                    target_x=$((ACTIVE_MON_X + 60))
                                    target_y=$((ACTIVE_MON_Y + 60))
                                else
                                    # Ventanas de salas, chat o ajustes
                                    target_x=$((ACTIVE_MON_X + 120))
                                    target_y=$((ACTIVE_MON_Y + 80))
                                fi

                                # Asegurar que la ventana quepa dentro del monitor activo
                                if [ $((target_x + w)) -gt $((ACTIVE_MON_X + ACTIVE_MON_W)) ]; then
                                    target_x=$((ACTIVE_MON_X + ACTIVE_MON_W - w - 20))
                                fi
                                [ "$target_x" -lt "$ACTIVE_MON_X" ] && target_x="$ACTIVE_MON_X"

                                if [ $((target_y + h)) -gt $((ACTIVE_MON_Y + ACTIVE_MON_H)) ]; then
                                    target_y=$((ACTIVE_MON_Y + ACTIVE_MON_H - h - 40))
                                fi
                                [ "$target_y" -lt "$ACTIVE_MON_Y" ] && target_y="$ACTIVE_MON_Y"

                                # Mover a la coordenada calculada
                                wmctrl -i -r "$wid" -e "0,$target_x,$target_y,-1,-1" 2>/dev/null || true

                                # Activar y enfocar la ventana en el monitor del usuario
                                wmctrl -i -a "$wid" 2>/dev/null || true
                                if command -v xdotool &>/dev/null; then
                                    xdotool windowactivate "$wid" 2>/dev/null || true
                                fi
                                seen_wids="$seen_wids $wid"
                            fi

                        # 2. Ventanas de JUEGOS lanzados desde GameRanger (Need for Speed, GTA, SWAT, Age of Empires, etc.)
                        elif [[ "$wmclass" =~ \.([eE][xX][eE]) ]] && [[ ! "$wmclass" =~ [Gg]ame[Rr]anger ]]; then
                            # Forzar pantalla completa nativa en el monitor activo para que llene el 100% de la pantalla
                            if [[ ! "$seen_wids" =~ "$wid" ]]; then
                                wmctrl -i -r "$wid" -e "0,${ACTIVE_MON_X},${ACTIVE_MON_Y},${best_w},${best_h}" 2>/dev/null || true
                                wmctrl -i -r "$wid" -b add,fullscreen 2>/dev/null || true
                                wmctrl -i -a "$wid" 2>/dev/null || true
                                if command -v xdotool &>/dev/null; then
                                    xdotool windowactivate "$wid" 2>/dev/null || true
                                fi
                                seen_wids="$seen_wids $wid"
                            fi
                        fi
                    done < <(wmctrl -l -x -G 2>/dev/null)
                fi
            fi

            # Auto-respaldo dinámico y ultraligero de la sesión cada 5 segundos
            if [ $((i % 5)) -eq 0 ]; then
                for u_dir in "${WINEPREFIX}/drive_c/users"/*; do
                    if [ -d "$u_dir" ] && [ "$(basename "$u_dir")" != "Public" ]; then
                        u_s="${u_dir}/AppData/Roaming/GameRanger/GameRanger Prefs/Settings"
                        if [ -s "$u_s" ] && grep -q "SessMail" "$u_s" 2>/dev/null; then
                            mkdir -p "${DIR}/.gameranger_prefs_backup"
                            cp -p "$u_s" "${DIR}/.gameranger_prefs_backup/Settings" 2>/dev/null || true
                        fi
                    fi
                done
            fi
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
                    cp -p "${u_prefs}/Settings" "${DIR}/.gameranger_prefs_backup/Settings" 2>/dev/null || true
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
    # GameRanger: Se ejecuta en MODO VENTANA NATIVA de escritorio (NUNCA en pantalla completa)
    # sin contenedor virtual para que flote en el escritorio como cualquier aplicación estándar
    "$WINE_CMD" "$TARGET_FILE" "$@" $EXTRA_APP_ARGS 2>"${WINEPREFIX}/gameranger_cef.log"
else
    if [ -n "$RUN_PREFIX" ]; then
        $GAMESCOPE_PREFIX $GAMEMODE "$WINE_CMD" $RUN_PREFIX "$TARGET_FILE" "$@" $EXTRA_APP_ARGS
    else
        $GAMESCOPE_PREFIX $GAMEMODE "$WINE_CMD" "$TARGET_FILE" "$@" $EXTRA_APP_ARGS
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
                cp -p "${u_prefs}/Settings" "${DIR}/.gameranger_prefs_backup/Settings" 2>/dev/null || true
            fi
        fi
    done
fi

# Esperar sincronización limpia de los subprocesos de Wine sin matarlos abruptamente
"$WINESERVER_CMD" -w 2>/dev/null || wineserver -w 2>/dev/null || true
exit $EXIT_STATUS
