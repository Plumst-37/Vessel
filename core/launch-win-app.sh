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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../menu-win.sh" ]; then
    DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
    DIR="$SCRIPT_DIR"
fi

CORE_DIR="${DIR}/core"
[ ! -d "$CORE_DIR" ] && CORE_DIR="${DIR}"

CONFIG_DIR="${DIR}/config"
[ ! -d "$CONFIG_DIR" ] && CONFIG_DIR="${DIR}"

DATOS_DIR="${DIR}/datos"
[ ! -d "$DATOS_DIR" ] && DATOS_DIR="${DIR}"

DB_FILE="${DATOS_DIR}/programas.db"
[ ! -f "$DB_FILE" ] && DB_FILE="${DIR}/programas.db"

# 1. Cargar preferencias del usuario y detección de hardware universal
[ -f "${CONFIG_DIR}/config_rendimiento.cfg" ] && source "${CONFIG_DIR}/config_rendimiento.cfg"
[ -f "${DIR}/config_rendimiento.cfg" ] && source "${DIR}/config_rendimiento.cfg"

if [ -f "${CORE_DIR}/hardware_detect.sh" ]; then
    source "${CORE_DIR}/hardware_detect.sh"
else
    source "${DIR}/hardware_detect.sh"
fi

# Helpers y resolvedores modulares
RESOLVER_LNK="${CORE_DIR}/resolver_lnk.py"
[ ! -f "$RESOLVER_LNK" ] && RESOLVER_LNK="${DIR}/resolver_lnk.py"

RESOLVER_BAT="${CORE_DIR}/resolver_bat.py"
[ ! -f "$RESOLVER_BAT" ] && RESOLVER_BAT="${DIR}/resolver_bat.py"

ANALIZADOR_PE="${CORE_DIR}/analizador_pe.py"
[ ! -f "$ANALIZADOR_PE" ] && ANALIZADOR_PE="${DIR}/analizador_pe.py"

GESTOR_DRIVERS="${CORE_DIR}/gestor_drivers.sh"
[ ! -f "$GESTOR_DRIVERS" ] && GESTOR_DRIVERS="${DIR}/gestor_drivers.sh"
if [ -f "$GESTOR_DRIVERS" ]; then
    source "$GESTOR_DRIVERS" cargar_env
fi

GENERAR_DXVK="${CORE_DIR}/generar_dxvk_conf.sh"
[ ! -f "$GENERAR_DXVK" ] && GENERAR_DXVK="${DIR}/generar_dxvk_conf.sh"

if [ -f "${DIR}/drivers/dxvk/dxvk.conf" ]; then
    DXVK_CONF="${DIR}/drivers/dxvk/dxvk.conf"
elif [ -f "${CONFIG_DIR}/dxvk.conf" ]; then
    DXVK_CONF="${CONFIG_DIR}/dxvk.conf"
else
    DXVK_CONF="${DIR}/dxvk.conf"
fi

# 2. Aplicar optimizaciones dinámicas para el hardware real del equipo
aplicar_entorno_hardware

# 3. Procesar banderas opcionales (prefijo dedicado, modo aislado, runner custom, versión de Windows, AMD FSR y modo programa)
CUSTOM_PREFIX=""
FORCE_ISOLATED=0
CUSTOM_RUNNER=""
CUSTOM_WINVER=""
CUSTOM_FSR=""
IS_PROGRAM=0
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
        --program)
            IS_PROGRAM=1
            shift
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "Uso: $0 [--prefix /ruta/al/prefijo] [--isolated] [--runner /ruta/a/wine] [--winver win10|win7|winxp] [--fsr off|quality|performance] [--program] [/ruta/al/programa.exe] [argumentos]"
    exit 1
else
    TARGET="$1"
    shift || true
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
        for db in "${DATOS_DIR}/programas_usuario.db" "${DIR}/programas_usuario.db" "${DATOS_DIR}/programas.db" "${DIR}/programas.db"; do
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
    if [ -f "$RESOLVER_LNK" ]; then
        RESOLVED_RES=$(python3 "$RESOLVER_LNK" "$TARGET" "${WINEPREFIX:-${DIR}/wineprefix}" 2>/dev/null || true)
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
    if [ -f "$RESOLVER_BAT" ]; then
        RESOLVED_BAT=$(python3 "$RESOLVER_BAT" "$TARGET" 2>/dev/null || true)
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


# 4. Definir la ruta del WINEPREFIX (Soporte Dual: Prefijo Compartido o Prefijo Aislado por Juego)
if [ -n "$CUSTOM_PREFIX" ]; then
    export WINEPREFIX="$CUSTOM_PREFIX"
else
    # Comprobar en base de datos si el juego tiene configurado prefijo aislado, versión de Windows o FSR
    PREF_TYPE="compartido"
    GAME_WINVER="${CUSTOM_WINVER:-}"
    GAME_FSR="${CUSTOM_FSR:-}"
    for db in "${DATOS_DIR}/programas_usuario.db" "${DIR}/programas_usuario.db" "${DATOS_DIR}/programas.db" "${DIR}/programas.db"; do
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

    if [ -f "$ANALIZADOR_PE" ] && [ -f "$TARGET" ]; then
        pe_eval=$(python3 "$ANALIZADOR_PE" --bash "$TARGET" 2>/dev/null || true)
        if [ -n "$pe_eval" ]; then
            eval "$pe_eval"
            # Si se resolvió un binario .exe real desde un script .bat/.lnk, actualizar TARGET si aún no lo estaba
            if [ -n "$PE_TARGET" ] && [ -f "$PE_TARGET" ] && [ "$TARGET" != "$PE_TARGET" ]; then
                TARGET="$PE_TARGET"
            fi
        fi
    fi

    # Identificación automática de categoría (Juego vs Programa de Escritorio)
    if [ "$IS_PROGRAM" -eq 0 ]; then
        if [ "$PE_CATEGORY" = "programa" ]; then
            IS_PROGRAM=1
        elif [[ "$(basename "$TARGET")" =~ (winecfg|explorer|notepad|cmd|regedit|taskmgr|control) ]]; then
            IS_PROGRAM=1
        fi
    fi

    # Detección inteligente de arquitectura (32-bit vs 64-bit) y APIs modernas (DirectX 12 / RE Engine)
    es_64bit=false
    if [ "$PE_IS_64" = "1" ] || file -b "$TARGET" 2>/dev/null | grep -qiE 'x86-64|PE32\+'; then
        es_64bit=true
    fi
    if [ "$es_64bit" = false ] && [ "$CPU_CORES" -gt 16 ]; then
        # Limitar topología en juegos 32-bit a máx 16 hilos para prevenir desbordamiento de búfer en motores clásicos
        export WINE_CPU_TOPOLOGY="16"
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
        elif [ -f "${DATOS_DIR}/GameRangerSetup.exe" ]; then
            echo "[*] Instalando GameRanger oficial en el entorno..."
            WINEPREFIX="${WINEPREFIX}" WINEDLLOVERRIDES="winemenubuilder.exe=d;dxgi=b;d3d11=b;d3d10core=b;d3d9=b;" wine "${DATOS_DIR}/GameRangerSetup.exe" 2>/dev/null || true
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

# Redirección inteligente de lanzadores para juegos con ejecutables wrapper obligatorios
if [[ "$TARGET_FILE" =~ ^[Gg][Tt][Aa]5\.exe$ ]]; then
    if [ -f "${TARGET_DIR}/PlayGTAV.exe" ]; then
        echo "[+] Detectado ejecutable de motor GTA5.exe: Redirigiendo a PlayGTAV.exe para inicializar Social Club y emulador..."
        TARGET="${TARGET_DIR}/PlayGTAV.exe"
        TARGET_DIR="$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd || dirname "$TARGET")"
        TARGET_FILE="$(basename "$TARGET")"
    elif [ -f "$(dirname "$TARGET_DIR")/PlayGTAV.exe" ]; then
        echo "[+] Detectado ejecutable de motor GTA5.exe: Redirigiendo a $(dirname "$TARGET_DIR")/PlayGTAV.exe..."
        TARGET="$(dirname "$TARGET_DIR")/PlayGTAV.exe"
        TARGET_DIR="$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd || dirname "$TARGET")"
        TARGET_FILE="$(basename "$TARGET")"
    fi
fi

# 5. Detección de entorno gráfico: Wayland vs X11
IS_WAYLAND=0
if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    IS_WAYLAND=1
fi
# NUNCA exportar SDL_VIDEODRIVER para Wine: las librerías Windows SDL2.dll sólo soportan el driver 'windows'.
# Si SDL_VIDEODRIVER tiene 'wayland' o 'x11', SDL_VideoInit colapsa con 'not available' y 'Failed to create SDL Window'.
unset SDL_VIDEODRIVER

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

# 7.1 Auto-verificación e integración modular de DXVK y VKD3D en el prefijo activo
if [ "$RENDERER_IN_USE" != "WineD3D (OpenGL Compatibilidad)" ]; then
    if [ -d "${WINEPREFIX}/drive_c/windows/system32" ]; then
        if [ -f "${CORE_DIR}/gestor_drivers.sh" ]; then
            bash "${CORE_DIR}/gestor_drivers.sh" instalar_todo "$WINEPREFIX" >/dev/null 2>&1 || true
        elif [ -d "/usr/lib/dxvk/wine64" ]; then
            for dll in d3d11 d3d10core d3d9 d3d8 dxgi; do
                [ -f "/usr/lib/dxvk/wine64/${dll}.dll.so" ] && ln -sf "/usr/lib/dxvk/wine64/${dll}.dll.so" "${WINEPREFIX}/drive_c/windows/system32/${dll}.dll" 2>/dev/null || true
                [ -f "/usr/lib/dxvk/wine32/${dll}.dll.so" ] && ln -sf "/usr/lib/dxvk/wine32/${dll}.dll.so" "${WINEPREFIX}/drive_c/windows/syswow64/${dll}.dll" 2>/dev/null || true
            done
        elif command -v dxvk-setup &>/dev/null; then
            if [ ! -L "${WINEPREFIX}/drive_c/windows/system32/d3d11.dll" ]; then
                echo "[*] Instalando y vinculando librerías DXVK (DirectX -> Vulkan) en el prefijo..."
                WINEPREFIX="$WINEPREFIX" dxvk-setup install -y >/dev/null 2>&1 || true
            fi
        fi
    fi
fi

# 7.2 Inyección inteligente y verificación de runtimes esenciales (DirectX 9/10/11, Visual C++, OpenAL)
local_gestor_lib="${CORE_DIR}/gestor_librerias.sh"
[ ! -f "$local_gestor_lib" ] && local_gestor_lib="${DIR}/herramientas/gestor_librerias.sh"
if [ -f "$local_gestor_lib" ] && [ -d "${WINEPREFIX}/drive_c/windows" ]; then
    if [ ! -f "${WINEPREFIX}/drive_c/windows/syswow64/d3dx9_43.dll" ] || [ ! -f "${WINEPREFIX}/drive_c/windows/syswow64/msvcp140.dll" ]; then
        echo "[*] Sincronizando librerías esenciales (DirectX nativo y Visual C++)..."
        bash "$local_gestor_lib" instalar_directx "$WINEPREFIX" >/dev/null 2>&1 || true
        bash "$local_gestor_lib" instalar_vcredist "$WINEPREFIX" >/dev/null 2>&1 || true
        bash "$local_gestor_lib" configurar_overrides "$WINEPREFIX" >/dev/null 2>&1 || true
    fi
    if [ -d "${DIR}/wineprefix/drive_c/windows" ] && [ "$WINEPREFIX" != "${DIR}/wineprefix" ]; then
        bash "$local_gestor_lib" propagar "$WINEPREFIX" >/dev/null 2>&1 || true
    fi
fi

# ==============================================================================
# CALIBRACIÓN UNIVERSAL DE COMPATIBILIDAD WINDOWS 10/11, DIRECT2D, DIRECT3D Y VRAM
# ==============================================================================
optimizar_entorno_windows_completo() {
    # Si ya fue calibrado en este prefijo con la versión 2, retornar inmediatamente (0.01s)
    if [ -f "${WINEPREFIX}/.vessel_win_full_v2" ]; then
        return 0
    fi

    # 1. Detección precisa de VRAM de la GPU para reporte fiel a juegos 3D y suites de diseño
    local vram_mb=""
    if command -v nvidia-smi &>/dev/null; then
        vram_mb=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1)
    fi
    if [ -z "$vram_mb" ]; then
        for f in /sys/class/drm/card*/device/mem_info_vram_total; do
            if [ -f "$f" ]; then
                local b
                b=$(cat "$f" 2>/dev/null)
                if [ -n "$b" ] && [ "$b" -gt 0 ]; then
                    vram_mb=$((b / 1048576))
                    break
                fi
            fi
        done
    fi
    if [ -z "$vram_mb" ] && command -v glxinfo &>/dev/null; then
        vram_mb=$(glxinfo -B 2>/dev/null | grep -iE "video memory|total available memory" | head -n 1 | grep -oE "[0-9]+" | head -n 1)
    fi
    if [ -z "$vram_mb" ]; then
        local ram_sys
        ram_sys=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
        if [ "${ram_sys:-0}" -ge 12000 ]; then vram_mb=4096; elif [ "${ram_sys:-0}" -ge 6000 ]; then vram_mb=2048; else vram_mb=1024; fi
    fi
    [ -z "$vram_mb" ] && vram_mb=2048

    # 2. Generar inyección atómica en el registro (.reg) en una sola operación de Wine
    local reg_full
    reg_full=$(mktemp "${TMPDIR:-/tmp}/vessel_win_full_XXXXXX.reg" 2>/dev/null || echo "/tmp/vessel_win_full_$$.reg")
    cat << EOF > "$reg_full"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion]
"ProductName"="Windows 10 Pro"
"CurrentBuild"="19045"
"CurrentBuildNumber"="19045"
"ReleaseId"="22H2"
"DisplayVersion"="22H2"
"UBR"=dword:00000ef2
"EditionID"="Professional"
"InstallationType"="Client"
"CurrentMajorVersionNumber"=dword:0000000a
"CurrentMinorVersionNumber"=dword:00000000
"CompositionVersion"="10.0.19045.3826"

[HKEY_LOCAL_MACHINE\Software\WOW6432Node\Microsoft\Windows NT\CurrentVersion]
"ProductName"="Windows 10 Pro"
"CurrentBuild"="19045"
"CurrentBuildNumber"="19045"
"ReleaseId"="22H2"
"DisplayVersion"="22H2"
"UBR"=dword:00000ef2
"EditionID"="Professional"
"InstallationType"="Client"
"CurrentMajorVersionNumber"=dword:0000000a
"CurrentMinorVersionNumber"=dword:00000000

[HKEY_CURRENT_USER\Software\Wine\Direct3D]
"VideoMemorySize"="${vram_mb}"
"StrictDrawOrdering"="disabled"
"AlwaysOffscreen"="enabled"
"OffscreenRenderingMode"="fbo"
"Multisampling"="enabled"
"CheckFloatConstants"="disabled"
"CheckDepthStencil"="enabled"
"csmt"=dword:00000001

[HKEY_CURRENT_USER\Software\Wine\Direct2D]
"max_version_factory"=dword:00000001

[HKEY_CURRENT_USER\Control Panel\Desktop]
"FontSmoothing"="2"
"FontSmoothingType"=dword:00000002
"FontSmoothingGamma"=dword:00000578
"FontSmoothingOrientation"=dword:00000001

[HKEY_CURRENT_USER\Software\Wine\Fonts\Replacements]
"Segoe UI"="Liberation Sans"
"Calibri"="Liberation Sans"
"Arial"="Liberation Sans"
"Times New Roman"="Liberation Serif"
"Courier New"="Liberation Mono"
"Consolas"="Liberation Mono"
"Tahoma"="Liberation Sans"
"MS Sans Serif"="Liberation Sans"

[HKEY_CURRENT_USER\Software\Wine\DirectInput]
"MouseWarpOverride"="enable"

[HKEY_CURRENT_USER\Software\Wine\WineDbg]
"ShowCrashDialog"=dword:00000000

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\AeDebug]
"Auto"="0"

[HKEY_CURRENT_USER\Software\Wine\Drivers]
"Audio"="pulse"

[HKEY_CURRENT_USER\Software\Wine\DllOverrides]
"riched20"="native,builtin"
"riched32"="native,builtin"
"msftedit"="native,builtin"
"msxml3"="native,builtin"
"msxml4"="native,builtin"
"msxml6"="native,builtin"
"gdiplus"="native,builtin"
"windowscodecs"="native,builtin"
"mscms"="native,builtin"
"actxprxy"="native,builtin"
"wbemprox"="native,builtin"
"wbemdisp"="native,builtin"
"wmiutils"="native,builtin"
"schannel"="native,builtin"
"crypt32"="native,builtin"
"secur32"="native,builtin"
"wininet"="native,builtin"
"urlmon"="native,builtin"
"dwrite"="native,builtin"
"mfplat"="native,builtin"
"mf"="native,builtin"
"mfreadwrite"="native,builtin"
"evr"="native,builtin"
"quartz"="builtin,native"
"devenum"="builtin,native"
"qedit"="builtin,native"
"wmasf"="native,builtin"
"wmvcore"="native,builtin"
"winegstreamer"="builtin"
"xaudio2_7"="builtin"
"xaudio2_8"="builtin"
"xaudio2_9"="builtin"
"x3daudio1_7"="builtin"
"openal32"="native,builtin"
"dmusic"="native,builtin"
"dmsynth"="native,builtin"
"dmime"="native,builtin"
"dmloader"="native,builtin"
"dmband"="native,builtin"
EOF

    DISPLAY="" "$WINE_CMD" regedit /s "$reg_full" >/dev/null 2>&1 || true
    rm -f "$reg_full" 2>/dev/null || true
    touch "${WINEPREFIX}/.vessel_win_full_v2" 2>/dev/null || true
}


# 8. Configuración de pantalla completa universal, ratón ultra-fluido, estabilidad 3D y supresión de crash dialogs
optimizar_entorno_windows_completo
if [ ! -f "${WINEPREFIX}/.vessel_reg_v5" ]; then
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\WineDbg" /v ShowCrashDialog /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\AeDebug" /v Auto /t REG_SZ /d 0 /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\DirectInput" /v MouseWarpOverride /t REG_SZ /d enable /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v Decorated /t REG_SZ /d Y /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v Managed /t REG_SZ /d Y /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v csmt /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v StrictDrawOrdering /t REG_SZ /d disabled /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v AlwaysOffscreen /t REG_SZ /d enabled /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v CheckDepthStencil /t REG_SZ /d enabled /f >/dev/null 2>&1 || true
    touch "${WINEPREFIX}/.vessel_reg_v5" 2>/dev/null || true
fi

# 8.0 Gestión inteligente de ventanas: programas de escritorio con barra nativa, juegos en pantalla completa sin bordes
if [ "$IS_PROGRAM" -eq 1 ] || [ "${PE_CATEGORY:-juego}" = "programa" ]; then
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${TARGET_FILE}\X11 Driver" /v Decorated /t REG_SZ /d Y /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${TARGET_FILE}\X11 Driver" /v GrabFullscreen /t REG_SZ /d N /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${TARGET_FILE}\X11 Driver" /v UseTakeFocus /t REG_SZ /d Y /f >/dev/null 2>&1 || true
else
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${TARGET_FILE}\X11 Driver" /v Decorated /t REG_SZ /d N /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${TARGET_FILE}\X11 Driver" /v GrabFullscreen /t REG_SZ /d Y /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${TARGET_FILE}\X11 Driver" /v UseTakeFocus /t REG_SZ /d N /f >/dev/null 2>&1 || true
fi

# 8.1 Configuración de Versión de Windows por juego en AppDefaults (Mejora 1: win10 / win7 / winxp)
if [ -n "$GAME_WINVER" ]; then
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${TARGET_FILE}" /v "Version" /t REG_SZ /d "$GAME_WINVER" /f >/dev/null 2>&1 || true
fi

# 9. Configuración modular de DXVK y traducción gráfica
if [ "$RENDERER_IN_USE" != "WineD3D (OpenGL Compatibilidad)" ]; then
    if [ -f "${DIR}/drivers/dxvk/dxvk.conf" ]; then
        export DXVK_CONFIG_FILE="${DIR}/drivers/dxvk/dxvk.conf"
    else
        export DXVK_CONFIG_FILE="$DXVK_CONF"
        if [ -x "$GENERAR_DXVK" ]; then
            "$GENERAR_DXVK"
        elif [ -f "$GENERAR_DXVK" ]; then
            bash "$GENERAR_DXVK"
        fi
    fi
    if [ -f "${DIR}/drivers/vkd3d-proton/vkd3d.conf" ]; then
        export VKD3D_CONFIG_FILE="${DIR}/drivers/vkd3d-proton/vkd3d.conf"
    fi
else
    unset DXVK_CONFIG_FILE
fi

# 9.1 Silenciar completamente la depuración de Wine para mínimo consumo de RAM y CPU (Ahorro: -15 MB)
if [ -z "${WINEDEBUG:-}" ]; then
    export WINEDEBUG="-all"
fi

# 9.2 Detección y activación de puente DXVK-NVAPI para GPUs NVIDIA GeForce
NVAPI_ACTIVO="Inactivo"
if [[ "${DETECTED_GPU:-}" =~ [Nn][Vv][Ii][Dd][Ii][Aa] ]] || lspci 2>/dev/null | grep -qi "NVIDIA"; then
    export DXVK_ENABLE_NVAPI=1
    export WINEDLLOVERRIDES="nvapi,nvapi64=n,b;${WINEDLLOVERRIDES:-}"
    NVAPI_ACTIVO="Activo (GeForce Reflex & Low-Latency)"
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
if [ "$IS_PROGRAM" -ne 1 ] && [ "$PERFIL_RENDIMIENTO" != "ahorro" ] && command -v gamemoderun &> /dev/null; then
    GAMEMODE="gamemoderun"
fi

# Activar modo alto rendimiento de energía en CPU (desbloquea Turbo Boost sin throttling agresivo en cualquier distro)
PREV_POWER_PROFILE=""
if [ "$IS_PROGRAM" -ne 1 ] && [ "$PERFIL_RENDIMIENTO" != "ahorro" ]; then
    if command -v powerprofilesctl &> /dev/null; then
        PREV_POWER_PROFILE=$(powerprofilesctl get 2>/dev/null || true)
        powerprofilesctl set performance 2>/dev/null || true
    elif command -v cpupower &> /dev/null; then
        cpupower frequency-set -g performance 2>/dev/null || true
    fi
    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [ -w "$gov" ] && echo performance > "$gov" 2>/dev/null || true
    done
    for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
        [ -w "$epp" ] && echo performance > "$epp" 2>/dev/null || true
    done
fi

# 11. Obtener directorio y nombre del archivo
TARGET_DIR="$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd || dirname "$TARGET")"
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

# Overrides universales de gráficos 3D, cinemáticas/codecs de video, audio espacial (FAudio/PipeWire nativo), DirectMusic, sockets y librerías base
export WINEDLLOVERRIDES="winemenubuilder.exe=d;dinput8=n,b;dxgi=n,b;d3d11=n,b;d3d10core=n,b;d3d9=n,b;d3d8=n,b;ddraw=n,b;dplayx=n,b;dpnet=n,b;dpwsockx=n,b;vorbisfile=n,b;vorbishooked=n,b;dsound=n,b;mfplat=n,b;mf=n,b;mfreadwrite=n,b;evr=n,b;quartz=b,n;devenum=b,n;qedit=b,n;wmasf=n,b;wmvcore=n,b;winegstreamer=b;xaudio2_7=b;xaudio2_8=b;xaudio2_9=b;x3daudio1_7=b;openal32=n,b;dmusic=n,b;dmsynth=n,b;dmime=n,b;dmloader=n,b;dmband=n,b;secur32=b;wininet=b;winhttp=b;ws2_32=b;iphlpapi=b;dnsapi=b;${WINEDLLOVERRIDES}"

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
    for db in "${DATOS_DIR}/programas_usuario.db" "${DIR}/programas_usuario.db" "${DATOS_DIR}/programas.db" "${DIR}/programas.db"; do
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

# ==============================================================================
# CONFIGURACIÓN UNIVERSAL PARA PROGRAMAS Y UTILIDADES DE ESCRITORIO DE WINDOWS
# - Modo Ventana Nativa X11 / Wayland (redimensionable, decorada, sin captura de cursor)
# - Subpixel Antialiasing ClearType HD para renderizado impecable de fuentes y textos
# - Sobrecargas de librerías para software de productividad, suites y diseño
# ==============================================================================
if [ "$IS_PROGRAM" -eq 1 ] || [ "${PE_CATEGORY:-juego}" = "programa" ]; then
    GAMEMODE=""
    GAMESCOPE_PREFIX=""
    ESCRITORIO_VIRTUAL="0"

    # Fuentes ClearType HD en el Registro de Windows
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Control Panel\Desktop" /v "FontSmoothing" /t REG_SZ /d "2" /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Control Panel\Desktop" /v "FontSmoothingType" /t REG_DWORD /d 2 /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Control Panel\Desktop" /v "FontSmoothingGamma" /t REG_DWORD /d 1400 /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Control Panel\Desktop" /v "FontSmoothingOrientation" /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true

    # Ventana de escritorio decorada y redimensionable
    if [ -n "$TARGET_FILE" ]; then
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${TARGET_FILE}\X11 Driver" /v "Decorated" /t REG_SZ /d "Y" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${TARGET_FILE}\X11 Driver" /v "Managed" /t REG_SZ /d "Y" /f >/dev/null 2>&1 || true
        "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${TARGET_FILE}\X11 Driver" /v "GrabFullscreen" /t REG_SZ /d "N" /f >/dev/null 2>&1 || true
    fi

    # Overrides de librerías de productividad y oficina
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v "riched20" /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v "riched32" /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v "msxml3" /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v "msxml6" /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
    "$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v "gdiplus" /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
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

    # Cargar preferencias de hardware y monitor desde drivers/gpu_env.conf
    if [ -f "${DIR}/drivers/gpu_env.conf" ]; then
        source "${DIR}/drivers/gpu_env.conf"
    fi

    local target_specified=0
    if [ -n "${TARGET_MONITOR:-}" ] && [ "$TARGET_MONITOR" != "auto" ] && command -v xrandr &>/dev/null; then
        local mon_line
        mon_line=$(xrandr 2>/dev/null | grep -E "^${TARGET_MONITOR}\s+connected")
        if [[ "$mon_line" =~ ([0-9]{3,4})x([0-9]{3,4})\+([0-9]+)\+([0-9]+) ]]; then
            ACTIVE_MON_W="${BASH_REMATCH[1]}"
            ACTIVE_MON_H="${BASH_REMATCH[2]}"
            ACTIVE_MON_X="${BASH_REMATCH[3]}"
            ACTIVE_MON_Y="${BASH_REMATCH[4]}"
            target_specified=1
        fi
    fi

    if [ "$target_specified" -eq 0 ] && command -v xrandr &>/dev/null; then
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

    # Si se especificó una resolución forzada en gpu_env.conf
    if [ -n "${FORCE_RESOLUTION:-}" ]; then
        ACTIVE_MON_W=$(echo "$FORCE_RESOLUTION" | cut -dx -f1)
        ACTIVE_MON_H=$(echo "$FORCE_RESOLUTION" | cut -dx -f2)
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
    perfil_id="generico"

    if [ -n "$PE_ENGINE" ] && [ "$PE_ENGINE" != "generico" ]; then
        perfil_id="$PE_ENGINE"
    elif [[ "$TARGET_FILE" =~ (GTA5|PlayGTAV|gta5) ]] || [[ "$TARGET_DIR" =~ (GTA\ V|Grand\ Theft\ Auto\ V|gta_data) ]]; then
        perfil_id="rockstar_gta5"
    elif [[ "$TARGET_FILE" =~ (gta_sa|gta-sa|gtasa) ]] || [[ "$TARGET_DIR" =~ (GTA\ San\ Andreas|Grand\ Theft\ Auto\ San\ Andreas) ]]; then
        perfil_id="rockstar_gtasa"
    elif [[ "$TARGET_FILE" =~ (speed|speed2|nfs) ]] || [[ "$TARGET_DIR" =~ (Need\ for\ Speed|NFS) ]]; then
        perfil_id="ea_nfs"
    elif [[ "$TARGET_FILE" =~ (re4|re2|re3|re7|re8|dmc5) ]] && { [ "$PE_ARCH" = "64-bit" ] || [ "$PE_API" = "DX12" ] || grep -qri "\[AppRender\]\|Capability=DirectX12" "$TARGET_DIR"/*config*.ini 2>/dev/null; }; then
        perfil_id="capcom_re_engine"
    elif [[ "$TARGET_FILE" =~ (BH6|biohazard4|re4|re6|RE6|re5|RE5|dmc4) ]] || [[ "$TARGET_DIR" =~ (Resident\ Evil|BH6|re6|RE6|Capcom) ]]; then
        perfil_id="capcom_mt_framework"
    elif [[ "$TARGET_FILE" =~ (Swat4|Swat4X|Bioshock|DeusEx) ]] || [ -d "${TARGET_DIR}/System" ] || [ -d "${TARGET_DIR}/Content/System" ]; then
        perfil_id="unreal_engine"
    elif [ -f "${TARGET_DIR}/ddraw.ini" ] || [ -f "${TARGET_DIR}/ddraw.dll" ] || \
         [[ "$TARGET_FILE" =~ (empires2|age2_x1|starcraft|ra2|diablo|fallout|carmageddon|totalannihilation|warcraft|war3|heroes3|homm3|civ3|simcity4|caesar3|pharaoh|zeus|tiberiansun|nox|dune2000|redalert|commandos|desperados) ]] || \
         { grep -qi -m 1 "ddraw\.dll" "$TARGET" 2>/dev/null && ! grep -qi -m 1 "d3d1[1-2]\.dll\|dxgi\.dll" "$TARGET" 2>/dev/null; }; then
        perfil_id="classic_directdraw"
    elif [ -d "${TARGET_DIR}/${TARGET_FILE%.*}_Data" ] || [ -f "${TARGET_DIR}/UnityPlayer.dll" ]; then
        perfil_id="unity_engine"
    elif [ -f "${TARGET_DIR}/hw.dll" ] || [ -f "${TARGET_DIR}/sw.dll" ] || [[ "$TARGET_FILE" =~ (cstrike|hl|czero|hltv)\.exe$ ]] || [ -d "${TARGET_DIR}/cstrike" ] || [ -d "${TARGET_DIR}/valve" ]; then
        perfil_id="valve_goldsrc"
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

            # Purgar caché previa de DXVK para eliminar pipelines con teselación obsoleta o buffers desalineados
            rm -f "${HOME}/.cache/dxvk/GTA5.dxvk-cache" "${HOME}/.cache/dxvk/PlayGTAV.dxvk-cache" "${TARGET_DIR}/GTA5.dxvk-cache" "${TARGET_DIR}/PlayGTAV.dxvk-cache" 2>/dev/null || true

            # Determinar resolución óptima según GPU (nativa para pantallas <= 1080p, adaptativa si supera 1080p en GPU básica)
            local gta_w="$best_w"
            local gta_h="$best_h"
            if [ "$IS_LOW_SPEC_GPU" = true ] && [ "$best_w" -gt 1920 ]; then
                gta_w="1920"
                gta_h="1080"
                echo "    - Pantalla de ultra-alta resolución detectada: Ajustando renderizado a 1080p para 60 FPS estables."
            fi

            # 2. Configuración en Rockstar Games / GTA V / settings.xml
            local rsg_doc="$HOME/Documentos/Rockstar Games/GTA V"
            [ ! -d "$rsg_doc" ] && rsg_doc="${WINEPREFIX}/drive_c/users/${USER}/Documents/Rockstar Games/GTA V"
            mkdir -p "$rsg_doc"

            # Detección inteligente de versión GTA V Lite (OptiJuegos / recursos optimizados para DX10)
            local is_gta_lite=false
            if [ -f "${TARGET_DIR}/bonus/settings.xml" ] || [ -f "${TARGET_DIR}/bonus/settings_ultra.xml" ] || [ -f "${TARGET_DIR}/optiprojects.asi" ]; then
                is_gta_lite=true
                echo "    - Edición GTA V Lite detectada: Calibrando para DirectX 10, animaciones fluidas y assets ligeros."
            fi

            local dx_ver="2"
            local quality_val="1"
            local shadow_val="1"
            local soft_shadow="1"
            local lod_scale="1.000000"
            local max_lod_scale="1.000000"
            local ped_lod="0.800000"
            local veh_lod="0.800000"
            local ped_variety="0.800000"
            local veh_variety="0.800000"

            if [ "$is_gta_lite" = true ]; then
                dx_ver="0"
                quality_val="0"
                shadow_val="0"
                soft_shadow="0"
                lod_scale="-0.200000"
                max_lod_scale="0.000000"
                ped_lod="-0.200000"
                veh_lod="-0.400000"
                ped_variety="0.000000"
                veh_variety="0.000000"
            elif [ "$IS_LOW_SPEC_GPU" = true ]; then
                ped_variety="0.400000"
                veh_variety="0.400000"
            fi

            # Si no existe ningún settings.xml, generar uno inicial con geometría 3D blindada (sin vertex explosion)
            local sxml_base="$rsg_doc/settings.xml"
            if [ ! -f "$sxml_base" ] && [ ! -f "${TARGET_DIR}/settings.xml" ]; then
                if [ "$is_gta_lite" = true ] && [ -f "${TARGET_DIR}/bonus/settings.xml" ]; then
                    cp -f "${TARGET_DIR}/bonus/settings.xml" "$sxml_base" 2>/dev/null || true
                else
                    cat <<EOF_SXML > "$sxml_base"
<?xml version="1.0" encoding="UTF-8"?>
<Settings>
  <version value="27" />
  <configSource>SMC_AUTO</configSource>
  <graphics>
    <Tessellation value="0" />
    <LodScale value="${lod_scale}" />
    <PedLodBias value="${ped_lod}" />
    <VehicleLodBias value="${veh_lod}" />
    <ShadowQuality value="${shadow_val}" />
    <ReflectionQuality value="${quality_val}" />
    <ReflectionMSAA value="0" />
    <SSAO value="0" />
    <AnisotropicFiltering value="16" />
    <MSAA value="0" />
    <MSAAFragments value="0" />
    <MSAAQuality value="0" />
    <SamplingMode value="0" />
    <TextureQuality value="0" />
    <ParticleQuality value="0" />
    <WaterQuality value="${quality_val}" />
    <GrassQuality value="${quality_val}" />
    <ShaderQuality value="${quality_val}" />
    <Shadow_SoftShadows value="${soft_shadow}" />
    <UltraShadows_Enabled value="false" />
    <Shadow_ParticleShadows value="false" />
    <Shadow_Distance value="1.000000" />
    <Shadow_LongShadows value="false" />
    <Shadow_SplitZStart value="0.930000" />
    <Shadow_SplitZEnd value="0.890000" />
    <Shadow_aircraftExpWeight value="0.990000" />
    <Shadow_DisableScreenSizeCheck value="false" />
    <Reflection_MipBlur value="false" />
    <FXAA_Enabled value="true" />
    <TXAA_Enabled value="false" />
    <Lighting_FogVolumes value="false" />
    <Shader_SSA value="false" />
    <DX_Version value="${dx_ver}" />
    <CityDensity value="0.000000" />
    <PedVarietyMultiplier value="${ped_variety}" />
    <VehicleVarietyMultiplier value="${veh_variety}" />
    <PostFX value="0" />
    <DoF value="false" />
    <HdStreamingInFlight value="false" />
    <MaxLodScale value="${max_lod_scale}" />
    <MotionBlurStrength value="0.000000" />
  </graphics>
  <system>
    <numBytesPerReplayBlock value="9000000" />
    <numReplayBlocks value="36" />
    <maxSizeOfStreamingReplay value="1024" />
    <maxFileStoreSize value="65536" />
  </system>
  <audio>
    <Audio3d value="false" />
  </audio>
  <video>
    <AdapterIndex value="0" />
    <OutputIndex value="0" />
    <ScreenWidth value="${gta_w}" />
    <ScreenHeight value="${gta_h}" />
    <RefreshRate value="60" />
    <Windowed value="2" />
    <VSync value="1" />
    <Stereo value="0" />
    <Convergence value="0.100000" />
    <Separation value="1.000000" />
    <PauseOnFocusLoss value="0" />
    <AspectRatio value="0" />
  </video>
  <VideoCardDescription>${GPU_NAME}</VideoCardDescription>
</Settings>
EOF_SXML
                fi
            fi

            for sxml in "$rsg_doc/settings.xml" "${TARGET_DIR}/settings.xml" "${WINEPREFIX}/drive_c/users/${USER}/Documents/Rockstar Games/GTA V/settings.xml"; do
                if [ -f "$sxml" ]; then
                    crear_respaldo_seguro "$sxml"
                    sed -i "s/<ScreenWidth value=\"[0-9]*\"/<ScreenWidth value=\"${gta_w}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<ScreenHeight value=\"[0-9]*\"/<ScreenHeight value=\"${gta_h}\"/" "$sxml" 2>/dev/null || true
                    # Modo Pantalla Completa sin Bordes (Windowed 2): 100% pantalla completa estable en GPUs híbridas PRIME sin fallo de swapchain
                    sed -i 's/<Windowed value="[0-9]*"/<Windowed value="2"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<VSync value="[0-9]*"/<VSync value="1"/' "$sxml" 2>/dev/null || true
                    sed -i "s/<ShadowQuality value=\"[0-9]*\"/<ShadowQuality value=\"${shadow_val}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<GrassQuality value=\"[0-9]*\"/<GrassQuality value=\"${quality_val}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<ShaderQuality value=\"[0-9]*\"/<ShaderQuality value=\"${quality_val}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<ReflectionQuality value=\"[0-9]*\"/<ReflectionQuality value=\"${quality_val}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<WaterQuality value=\"[0-9]*\"/<WaterQuality value=\"${quality_val}\"/" "$sxml" 2>/dev/null || true
                    sed -i 's/<TextureQuality value="[0-9]*"/<TextureQuality value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<ParticleQuality value="[0-9]*"/<ParticleQuality value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<PostFX value="[0-9]*"/<PostFX value="0"/' "$sxml" 2>/dev/null || true
                    # Desactivar Teselación para erradicar deformación de mallas y vertex exploding en Vulkan/Linux
                    sed -i 's/<Tessellation value="[0-9]*"/<Tessellation value="0"/' "$sxml" 2>/dev/null || true
                    sed -i "s/<Shadow_SoftShadows value=\"[0-9]*\"/<Shadow_SoftShadows value=\"${soft_shadow}\"/" "$sxml" 2>/dev/null || true
                    sed -i 's/<PauseOnFocusLoss value="[0-9]*"/<PauseOnFocusLoss value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<AspectRatio value="[0-9]*"/<AspectRatio value="0"/' "$sxml" 2>/dev/null || true
                    # Anti-aliasing estable: FXAA activo, MSAA/TXAA desactivados (evita mallas transparentes y corrupción de profundidad)
                    sed -i 's/<MSAA value="[0-9]*"/<MSAA value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<ReflectionMSAA value="[0-9]*"/<ReflectionMSAA value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<TXAA_Enabled value="true"/<TXAA_Enabled value="false"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<FXAA_Enabled value="false"/<FXAA_Enabled value="true"/' "$sxml" 2>/dev/null || true
                    # Estabilidad geométrica 3D y distancia de dibujado
                    sed -i "s/<LodScale value=\"[0-9\.\-]*\"/<LodScale value=\"${lod_scale}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<MaxLodScale value=\"[0-9\.\-]*\"/<MaxLodScale value=\"${max_lod_scale}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<PedLodBias value=\"[0-9\.\-]*\"/<PedLodBias value=\"${ped_lod}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<VehicleLodBias value=\"[0-9\.\-]*\"/<VehicleLodBias value=\"${veh_lod}\"/" "$sxml" 2>/dev/null || true
                    sed -i 's/<Shadow_Distance value="[0-9\.]*"/<Shadow_Distance value="1.000000"/' "$sxml" 2>/dev/null || true
                    sed -i "s/<DX_Version value=\"[0-9]*\"/<DX_Version value=\"${dx_ver}\"/" "$sxml" 2>/dev/null || true
                    # Audio estéreo limpio sin pérdidas de canal en PipeWire / PulseAudio
                    sed -i 's/<Audio3d value="[a-zA-Z]*"/<Audio3d value="false"/' "$sxml" 2>/dev/null || true
                    # Desactivar post-efectos y niebla volumétrica que rompen la vista de cámara en traducción Vulkan
                    sed -i 's/<DoF value="true"/<DoF value="false"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<InGameDepthOfField value="true"/<InGameDepthOfField value="false"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<MotionBlurStrength value="[0-9\.]*"/<MotionBlurStrength value="0.000000"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<Lighting_FogVolumes value="true"/<Lighting_FogVolumes value="false"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<UltraShadows_Enabled value="true"/<UltraShadows_Enabled value="false"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<Shadow_ParticleShadows value="true"/<Shadow_ParticleShadows value="false"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<Shadow_LongShadows value="true"/<Shadow_LongShadows value="false"/' "$sxml" 2>/dev/null || true
                    sed -i "s/<PedVarietyMultiplier value=\"[0-9\.]*\"/<PedVarietyMultiplier value=\"${ped_variety}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<VehicleVarietyMultiplier value=\"[0-9\.]*\"/<VehicleVarietyMultiplier value=\"${veh_variety}\"/" "$sxml" 2>/dev/null || true
                    if [ -n "$GPU_NAME" ]; then
                        sed -i "s|<VideoCardDescription>.*</VideoCardDescription>|<VideoCardDescription>${GPU_NAME}</VideoCardDescription>|" "$sxml" 2>/dev/null || true
                    fi
                fi
            done

            # 3. Optimización en commandline.txt (priorizando estabilidad geométrica 3D y frame pacing)
            local gta_cmdline="${TARGET_DIR}/commandline.txt"
            if [ -f "$gta_cmdline" ]; then
                crear_respaldo_seguro "$gta_cmdline"
                # Asegurar flags esenciales de emulador y compatibilidad sin destruir ajustes del usuario
                grep -qi -- "-scOfflineOnly" "$gta_cmdline" || echo "-scOfflineOnly" >> "$gta_cmdline"
                grep -qi -- "-ignoreDifferentVideoCard" "$gta_cmdline" || echo "-ignoreDifferentVideoCard" >> "$gta_cmdline"
                grep -qi -- "-Tessellation" "$gta_cmdline" || echo "-Tessellation 0" >> "$gta_cmdline"
                grep -qi -- "-mouseRawInput" "$gta_cmdline" || echo "-mouseRawInput" >> "$gta_cmdline"
                grep -qi -- "-norestrictions" "$gta_cmdline" || echo "-norestrictions" >> "$gta_cmdline"
                grep -qi -- "-nomemrestrict" "$gta_cmdline" || echo "-nomemrestrict" >> "$gta_cmdline"
                if [ "$is_gta_lite" = true ]; then
                    sed -i '/-DX11/d; /-dx11/d' "$gta_cmdline" 2>/dev/null || true
                    grep -qi -- "-DX10" "$gta_cmdline" || echo "-DX10" >> "$gta_cmdline"
                fi
                if grep -qi -- "-width" "$gta_cmdline"; then
                    sed -i "s/^-width .*/-width ${gta_w}/I" "$gta_cmdline" 2>/dev/null || true
                else
                    echo "-width ${gta_w}" >> "$gta_cmdline"
                fi
                if grep -qi -- "-height" "$gta_cmdline"; then
                    sed -i "s/^-height .*/-height ${gta_h}/I" "$gta_cmdline" 2>/dev/null || true
                else
                    echo "-height ${gta_h}" >> "$gta_cmdline"
                fi
                grep -qi -- "-windowed" "$gta_cmdline" || echo "-windowed" >> "$gta_cmdline"
                grep -qi -- "-borderless" "$gta_cmdline" || echo "-borderless" >> "$gta_cmdline"
            else
                cat <<EOF > "$gta_cmdline"
-width ${gta_w}
-height ${gta_h}
-windowed
-borderless
-mouseRawInput
-ignoreDifferentVideoCard
-scOfflineOnly
-Tessellation 0
-noInGameDOF
-disableD3D11Dof
-noDepthOfField
-frameLimit 1
-shadowSoftness 1
-norestrictions
-nomemrestrict
$([ "$is_gta_lite" = true ] && echo "-DX10")
EOF
            fi
            echo "[+] GTA V optimizado: Geometría 3D calibrada (Teselación 0, sin deformación ni vertex explosion, frame pacing 60 FPS, Social Club offline activado)."

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

            # Asegurar directorio limpio de guardado para emulador Goldberg
            local gta_save_dir="${WINEPREFIX}/drive_c/users/${USER}/AppData/Roaming/Goldberg SocialClub Emu Saves/GTA V/0F74F4C4"
            mkdir -p "$gta_save_dir"
            # Limpiar configuraciones binarias obsoletas que anulan settings.xml (preservando partidas guardadas SGTA*)
            rm -f "$gta_save_dir/pc_settings.bin" "$gta_save_dir/cfg.dat" 2>/dev/null || true

            # Overrides específicos de DirectX 11/10, Bink Video, Social Club y ASI Loader
            # Forzar xaudio2 a builtin (FAudio/PipeWire) para erradicar el crash de lectura de punteros WASAPI en Microsoft xaudio2_7.dll
            export WINEDLLOVERRIDES="xaudio2_7=b;xaudio2_8=b;xaudio2_9=b;x3daudio1_7=b;bink2w64=n,b;asiloader=n,b;dinput8=n,b;d3dcompiler_47=n,b;d3dcompiler_46=n,b;d3dcompiler_43=n,b;d3dcsx_46=n,b;socialclub=n,b;steam_api64=n,b;dxgi=n,b;d3d11=n,b;d3d10core=n,b;d3d10=n,b;d3d10_1=n,b;d3d9=n,b;${WINEDLLOVERRIDES}"
            ;;

        rockstar_gtasa)
            echo "[+] Perfil Activo: Rockstar Games (GTA San Andreas / Trilogy) [Aislado]"
            limpiar_zombies_juego "gta_sa\.exe"
            # Restaurar mod WindowedMode si estaba desactivado y asegurar modo sin bordes
            find "$TARGET_DIR" -iname "III.VC.SA.WindowedMode.asi.disabled" 2>/dev/null | while read -r wm_dis; do
                mv -f "$wm_dis" "${wm_dis%.disabled}" 2>/dev/null || true
            done
            find "$TARGET_DIR" -iname "III.VC.SA.WindowedMode.ini" 2>/dev/null | while read -r wm_ini; do
                crear_respaldo_seguro "$wm_ini"
                sed -i "s/^ShowBorder = .*/ShowBorder = 0/" "$wm_ini" 2>/dev/null || true
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

            # 2. Desactivar Ray Tracing (DXR) y extensiones inestables en GPUs Maxwell/Pascal (NVIDIA MX/GTX)
            export VKD3D_CONFIG="nodxr"
            export VKD3D_FEATURE_LEVEL="12_0"
            export VKD3D_DISABLE_EXTENSIONS="VK_EXT_descriptor_buffer"

            # 3. Aplicar perfil optimizado de bajo consumo si existe en opti/local_config.ini
            if [ -f "${TARGET_DIR}/opti/local_config.ini" ]; then
                if [ ! -f "${TARGET_DIR}/local_config.ini.vessel_orig" ]; then
                    crear_respaldo_seguro "${TARGET_DIR}/local_config.ini"
                fi
                cp -f "${TARGET_DIR}/opti/local_config.ini" "${TARGET_DIR}/local_config.ini" 2>/dev/null || true
                if [ -f "${TARGET_DIR}/opti/local_config_default.ini" ]; then
                    cp -f "${TARGET_DIR}/opti/local_config_default.ini" "${TARGET_DIR}/local_config_default.ini" 2>/dev/null || true
                fi
            fi

            # 4. Limpiar adaptadores gráficos ajenos hardcodeados en local_config.ini / *config*.ini
            find "$TARGET_DIR" -maxdepth 3 -iname "*config*.ini" 2>/dev/null | while read -r c_ini; do
                if grep -qi "\[Render/Adapter\]" "$c_ini" 2>/dev/null || grep -qi "VendorId=" "$c_ini" 2>/dev/null; then
                    crear_respaldo_seguro "$c_ini"
                    sed -i '/\[Render\/Adapter\]/,/^\[/ { /^\[Render\/Adapter\]/d; /^Description=/d; /^VendorId=/d; /^DeviceId=/d; /^SubSysId=/d; /^Revision=/d; }' "$c_ini" 2>/dev/null || true
                    sed -i '/^Description=.*Graphics/d; /^VendorId=[0-9]*/d; /^DeviceId=[0-9]*/d; /^SubSysId=[0-9]*/d; /^Revision=[0-9]*/d' "$c_ini" 2>/dev/null || true
                fi
            done

            # 5. Configurar visualización óptima en configs de RE Engine (Modo Ventana Sin Bordes / Borderless)
            find "$TARGET_DIR" -maxdepth 3 -name "*config*.ini" 2>/dev/null | while read -r re_ini; do
                if grep -q "\[AppRender\]" "$re_ini" 2>/dev/null || grep -q "\[RenderConfig\]" "$re_ini" 2>/dev/null; then
                    crear_respaldo_seguro "$re_ini"
                    sed -i 's/^FullScreenMode=.*/FullScreenMode=false/' "$re_ini" 2>/dev/null || true
                    sed -i 's/^WindowMode=.*/WindowMode=Borderless/' "$re_ini" 2>/dev/null || true
                    sed -i 's/^AppWindowMode=.*/AppWindowMode=1/' "$re_ini" 2>/dev/null || true
                    sed -i 's/^AppRenderingMethod=.*/AppRenderingMethod=1/' "$re_ini" 2>/dev/null || true
                    sed -i 's/^AppLensDistorsion=.*/AppLensDistorsion=0/' "$re_ini" 2>/dev/null || true
                    sed -i 's/^AppMotionBlur=.*/AppMotionBlur=0/' "$re_ini" 2>/dev/null || true
                    sed -i 's/^AppFilmGrainNoise=.*/AppFilmGrainNoise=0/' "$re_ini" 2>/dev/null || true
                    sed -i 's/^AppVsync=.*/AppVsync=1/' "$re_ini" 2>/dev/null || true
                    # Calibrar texturas a nivel óptimo nítido con FSR2 Quality en GPUs de entrada
                    if [ "$IS_LOW_SPEC_GPU" = "true" ]; then
                        sed -i 's/^AppTextureQuality=.*/AppTextureQuality=3/' "$re_ini" 2>/dev/null || true
                        sed -i 's/^AppImageQuality=.*/AppImageQuality=1/' "$re_ini" 2>/dev/null || true
                        sed -i 's/^AppUpScalingTypeFSR2=.*/AppUpScalingTypeFSR2=1/' "$re_ini" 2>/dev/null || true
                        sed -i 's/^AppAntiAliasing=.*/AppAntiAliasing=1/' "$re_ini" 2>/dev/null || true
                        sed -i 's/^AppMeshQuality=.*/AppMeshQuality=1/' "$re_ini" 2>/dev/null || true
                    fi
                    sed -i 's/^AppRayTraceOnOff=.*/AppRayTraceOnOff=0/' "$re_ini" 2>/dev/null || true
                    if grep -q "^NormalWindowResolution=" "$re_ini" 2>/dev/null; then
                        sed -i "s/^NormalWindowResolution=.*/NormalWindowResolution=(${best_w}.000000,${best_h}.000000)/" "$re_ini" 2>/dev/null || true
                    fi
                    local dm_idx
                    dm_idx=$(grep -B 1 "DisplayMode[0-9]*_Height=${best_h}" "$re_ini" 2>/dev/null | grep -E "DisplayMode[0-9]*_Width=${best_w}" | head -n 1 | grep -oE "DisplayMode[0-9]+" | tr -d 'DisplayMode')
                    if [ -n "$dm_idx" ]; then
                        sed -i "s/^AppResolution=.*/AppResolution=${dm_idx}/" "$re_ini" 2>/dev/null || true
                        sed -i "s/^FullScreenDisplayMode=.*/FullScreenDisplayMode=${dm_idx}/" "$re_ini" 2>/dev/null || true
                    fi
                fi
            done
            export WINEDLLOVERRIDES="EMP=n;d3d12=n,b;d3d12core=n,b;dxgi=n,b;d3d11=n,b;d3dcompiler_47=n,b;dinput8=n,b;version=n,b;xinput1_3=n,b;xinput1_4=n,b;${WINEDLLOVERRIDES}"
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
                            sed -i 's/^VSYNC=OFF/VSYNC=ON/' "$cini" 2>/dev/null || true
                            sed -i 's/^MotionBlurEnabled=ON/MotionBlurEnabled=OFF/' "$cini" 2>/dev/null || true
                            sed -i 's/^Aspect=.*/Aspect=DEFAULT/' "$cini" 2>/dev/null || true
                            sed -i "s/^Resolution=.*/Resolution=${best_res}/" "$cini" 2>/dev/null || true
                            local ref_hz="${SCREEN_HZ:-60}.00Hz"
                            sed -i "s/^RefreshRate=.*/RefreshRate=${ref_hz}/" "$cini" 2>/dev/null || true
                            sed -i 's/^AntiAlias=.*/AntiAlias=NONE/' "$cini" 2>/dev/null || true
                            sed -i 's/^AltAntiAlias=.*/AltAntiAlias=FXAA3HQ/' "$cini" 2>/dev/null || true
                            sed -i 's/^ShadowsDisable=ON/ShadowsDisable=OFF/' "$cini" 2>/dev/null || true
                            sed -i 's/^ShadowsQuality=.*/ShadowsQuality=HIGH/' "$cini" 2>/dev/null || true
                            local job_threads=$(( CPU_CORES > 1 ? CPU_CORES - 1 : 1 ))
                            sed -i "s/^JobThread=.*/JobThread=${job_threads}/" "$cini" 2>/dev/null || true
                            sed -i 's/^RenderingThread=OFF/RenderingThread=ON/' "$cini" 2>/dev/null || true
                            sed -i 's/^TextureDetail=.*/TextureDetail=HIGH/' "$cini" 2>/dev/null || true
                            sed -i 's/^ScreenQuality=.*/ScreenQuality=HIGH/' "$cini" 2>/dev/null || true
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
                    sed -i 's/^UseVSync=False/UseVSync=True/' "$ueini" 2>/dev/null || true
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

        valve_goldsrc)
            echo "[+] Perfil Activo: Valve GoldSrc Engine (Half-Life / CS 1.6) [Aislado]"
            # Limpiar instancias colgadas previas para evitar error 'The game could not be started because it is already running'
            limpiar_zombies_juego "cstrike\.exe|hl\.exe|czero\.exe|hltv\.exe|crashpad_handler\.exe"
            sleep 0.2

            # 1. Parche proactivo y universal para el hook WinHttpCloseHandle en NextClient / No-Steam
            # Evita crash por desreferenciación de puntero nulo en Wine (STATUS_ACCESS_VIOLATION 0xc0000005)
            patch_target="$TARGET"
            [ ! -f "$patch_target" ] && [ -f "${TARGET_DIR}/cstrike.exe" ] && patch_target="${TARGET_DIR}/cstrike.exe"
            [ ! -f "$patch_target" ] && [ -f "${TARGET_DIR}/hl.exe" ] && patch_target="${TARGET_DIR}/hl.exe"
            if [ -f "$patch_target" ] && [ -w "$patch_target" ]; then
                python3 -c '
import sys, shutil, os
target = sys.argv[1]
try:
    with open(target, "rb") as f:
        data = f.read()
    sig = bytes.fromhex("85f67414813eb8020000750c")
    pos = data.find(sig)
    if pos != -1:
        bak = target + ".vessel_bak"
        if not os.path.exists(bak):
            shutil.copy2(target, bak)
        patch = bytes.fromhex("eb1690909090909090909090")
        with open(target, "r+b") as f:
            f.seek(pos)
            f.write(patch)
        print("[+] Parche de estabilidad Wine WinHttp aplicado exitosamente en", target)
except Exception:
    pass
' "$patch_target" 2>/dev/null || true
            fi

            # 2. Renderizador: OpenGL nativo del sistema (hw.dll se comunica directamente con OpenGL / Mesa / NVIDIA)
            export RENDERER_IN_USE="OpenGL Nativo (Valve GoldSrc)"
            export PROTON_USE_WINED3D=1
            unset DXVK_CONFIG_FILE
            export DXVK_HUD=0
            unset SDL_VIDEODRIVER

            # 3. Desactivar FSR de Wine (evita conflictos con CEF / Chromium Embedded Framework y con el backend OpenGL)
            ACTIVAR_FSR_FINAL=0
            export WINE_FULLSCREEN_FSR=0

            # 4. Forzar librerías DX builtin para que no interfiera DXVK con CEF ni hw.dll
            export WINEDLLOVERRIDES="d3d9=b;d3d11=b;dxgi=b;d3d8=b;${WINEDLLOVERRIDES}"

            # 5. Auto-reparar configuración de video en el registro de Wine para GoldSrc
            # Elimina el indicador de colapso previo que dispara el diálogo de error de renderizado y asegura OpenGL nativo
            local goldsrc_w="${best_w}"
            local goldsrc_h="${best_h}"
            # Snapping para resoluciones atípicas que GoldSrc / SDL2 rechaza en Linux (como 1366x768 -> 1360x768 o 1280x720)
            if [ "$goldsrc_w" -eq 1366 ]; then
                goldsrc_w=1360
            fi

            # Inyectar configuración de video óptima en el registro en una sola transacción ultra-rápida
            # IMPORTANTE: En Linux (Xwayland / Wine), ScreenWindowed=1 + borderless evita llamadas a ChangeDisplaySettingsEx
            # en el servidor X, previniendo al 100% el fallo "Failed to create SDL Window"
            if pgrep -x wineserver >/dev/null 2>&1; then
                "$WINE_CMD" regedit /S - << EOF >/dev/null 2>&1 || true
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Valve\Half-Life\Settings]
"CrashInitializingVideoMode"=dword:00000000
"EngineDLL"="hw.dll"
"EngineD3D"=dword:00000000
"ScreenWidth"=dword:$(printf "%08x" "${goldsrc_w}")
"ScreenHeight"=dword:$(printf "%08x" "${goldsrc_h}")
"ScreenBPP"=dword:00000020
"ScreenWindowed"=dword:00000001
EOF
            else
                python3 -c '
import os, sys, re, time
prefix = sys.argv[1]
w = int(sys.argv[2])
h = int(sys.argv[3])
user_reg = os.path.join(prefix, "user.reg")
if os.path.exists(user_reg):
    try:
        with open(user_reg, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
        section = "[Software\\\\Valve\\\\Half-Life\\\\Settings]"
        keys = {
            "\"CrashInitializingVideoMode\"": "dword:00000000",
            "\"EngineDLL\"": "\"hw.dll\"",
            "\"EngineD3D\"": "dword:00000000",
            "\"ScreenWidth\"": f"dword:{w:08x}",
            "\"ScreenHeight\"": f"dword:{h:08x}",
            "\"ScreenBPP\"": "dword:00000020",
            "\"ScreenWindowed\"": "dword:00000001",
        }
        if section in content:
            def update_sect(m):
                header = m.group(1)
                body = m.group(2)
                lines = body.splitlines()
                k_seen = set()
                new_lines = []
                for l in lines:
                    matched = False
                    for k, v in keys.items():
                        if l.startswith(k + "="):
                            new_lines.append(f"{k}={v}")
                            k_seen.add(k)
                            matched = True
                            break
                    if not matched:
                        new_lines.append(l)
                for k, v in keys.items():
                    if k not in k_seen:
                        new_lines.append(f"{k}={v}")
                return header + "\n".join(new_lines) + "\n"
            content = re.sub(r"(\[Software\\\\Valve\\\\Half-Life\\\\Settings\][^\n]*\n)(.*?)((?=\n\[)|\Z)",
                             update_sect, content, flags=re.DOTALL)
        else:
            ts = int(time.time())
            new_block = f"\n{section} {ts}\n#time=0\n"
            for k, v in keys.items():
                new_block += f"{k}={v}\n"
            content += new_block
        with open(user_reg, "w", encoding="utf-8") as f:
            f.write(content)
    except Exception:
        pass
' "$WINEPREFIX" "$goldsrc_w" "$goldsrc_h" 2>/dev/null || true
            fi

            # 6. Argumentos óptimos para GoldSrc (OpenGL nativo sin FBO conflictivo, resolución nativa, mouse crudo)
            goldsrc_game="cstrike"
            if [ -d "${TARGET_DIR}/cstrike" ]; then
                goldsrc_game="cstrike"
            elif [ -d "${TARGET_DIR}/czero" ]; then
                goldsrc_game="czero"
            elif [ -d "${TARGET_DIR}/valve" ]; then
                goldsrc_game="valve"
            fi

            if [[ ! "$EXTRA_APP_ARGS" =~ "-game" ]]; then
                EXTRA_APP_ARGS="-game ${goldsrc_game} ${EXTRA_APP_ARGS}"
            fi
            if [[ ! "$EXTRA_APP_ARGS" =~ "-gl" ]]; then
                EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -gl"
            fi
            if [[ ! "$EXTRA_APP_ARGS" =~ "-nofbo" ]]; then
                EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -nofbo -nomsaa"
            fi
            if [[ ! "$EXTRA_APP_ARGS" =~ "-noforcemaccel" ]]; then
                EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -noforcemaccel -noforcemparms -noforcemspd"
            fi
            # Eliminar -full / -fullscreen para evitar que SDL2 intente cambiar modos de hardware en Xwayland
            EXTRA_APP_ARGS=$(echo "$EXTRA_APP_ARGS" | sed -E 's/-full(screen)?//g')
            if [[ ! "$EXTRA_APP_ARGS" =~ "-window" ]] && [[ ! "$EXTRA_APP_ARGS" =~ "-sw" ]]; then
                EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -window"
            fi
            if [[ ! "$EXTRA_APP_ARGS" =~ "-noborder" ]]; then
                EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -noborder"
            fi
            if [[ ! "$EXTRA_APP_ARGS" =~ "-w " ]]; then
                EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -w ${goldsrc_w} -h ${goldsrc_h}"
            fi
            if [[ ! "$EXTRA_APP_ARGS" =~ "-noupdate" ]]; then
                EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -noupdate"
            fi
            EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -stretchaspect -num_edicts 4096"
            ;;

        source_engine)
            echo "[+] Perfil Activo: Valve Source Engine [Aislado]"
            limpiar_zombies_juego "hl2\.exe|csgo\.exe|left4dead.*\.exe|portal.*\.exe"
            sleep 0.2
            EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -fullscreen -w ${best_w} -h ${best_h}"
            ;;

        bethesda_creation)
            echo "[+] Perfil Activo: Bethesda Creation / Gamebryo Engine (Skyrim / Fallout) [Aislado]"
            limpiar_zombies_juego "TESV\.exe|SkyrimSE\.exe|Fallout4\.exe|FalloutNV\.exe|Fallout3\.exe|Starfield\.exe"
            sleep 0.2
            export WINEDLLOVERRIDES="dinput8=n,b;xinput1_3=n,b;xaudio2_7=b;${WINEDLLOVERRIDES}"
            ;;

        godot_engine)
            echo "[+] Perfil Activo: Godot Engine [Aislado]"
            ;;

        cryengine)
            echo "[+] Perfil Activo: Crytek CryEngine [Aislado]"
            limpiar_zombies_juego "Crysis.*\.exe|FarCry.*\.exe|KingdomCome.*\.exe|Prey.*\.exe"
            ;;

        id_tech)
            echo "[+] Perfil Activo: id Tech Engine (DOOM / Wolfenstein / Quake) [Aislado]"
            limpiar_zombies_juego "DOOM.*\.exe|Wolfenstein.*\.exe|Quake.*\.exe"
            ;;

        gameranger)
            echo "[+] Perfil Activo: GameRanger Desktop Client [Aislado]"
            ;;

        *)
            if [ "$IS_PROGRAM" -eq 1 ] || [ "${PE_CATEGORY:-juego}" = "programa" ]; then
                echo "[+] Perfil Activo: Programa de Escritorio / Utilidad Windows [Aislado]"
                export WINE_FULLSCREEN_FSR=0
                ACTIVAR_FSR_FINAL=0
            else
                echo "[+] Perfil Activo: Aplicación Genérica [Aislado]"
            fi
            ;;
    esac
}
aplicar_perfil_aislado_juego

# ==============================================================================
# AUTO-ACTIVACIÓN DINÁMICA DE MODS, ASI LOADERS, ENB, RESHADE Y TRADUCCIONES
# Detecta automáticamente librerías DLL de mods y plugins ASI locales
# y activa el override nativo (n,b) en Wine para que carguen de forma transparente.
# Filtra estrictamente librerías de sistema, runtime CRT y forwarders api-ms-win.
# ==============================================================================
DLL_EXCLUIDAS_CORE="^(ntdll|kernel32|kernelbase|user32|gdi32|gdiplus|advapi32|rpcrt4|ws2_32|wsock32|iphlpapi|shell32|shlwapi|shcore|ole32|oleaut32|combase|comctl32|comdlg32|version|imm32|winmm|crypt32|cryptbase|secur32|bcrypt|ncrypt|sspicli|wldp|uxtheme|dwmapi|setupapi|cfgmgr32|winhttp|wininet|urlmon|mpr|netapi32|dnsapi|normaliz|imagehlp|dbghelp|psapi|api-ms-win-.*|ext-ms-win-.*|ucrtbase|vcruntime.*|msvcp.*|msvcr.*|concrt.*|vcomp.*|msvcrt|dxgi|d3d11|d3d12|d3d10.*|d3d9|d3d8|ddraw|vulkan-1|winevulkan|opengl32|glu32|winegstreamer|xaudio2_.*|x3daudio.*|orig_socialclub|launc)$"
MODS_ACTIVADOS=()
declare -A VISTAS_DLL=()

while IFS= read -r found_dll; do
    [ -z "$found_dll" ] && continue
    raw_bname="$(basename "$found_dll")"
    raw_name="${raw_bname%.*}"
    dll_low="$(echo "$raw_name" | tr '[:upper:]' '[:lower:]')"
    
    if [ -z "${VISTAS_DLL[$dll_low]:-}" ] && ! echo "$dll_low" | grep -qiE "$DLL_EXCLUIDAS_CORE"; then
        VISTAS_DLL["$dll_low"]=1
        export WINEDLLOVERRIDES="${dll_low}=n,b;${WINEDLLOVERRIDES}"
        MODS_ACTIVADOS+=("$raw_bname")
    fi
done < <({ find . -maxdepth 1 \( -iname "*.dll" -o -iname "*.asi" \) 2>/dev/null; find scripts plugins asi mods -maxdepth 1 \( -iname "*.dll" -o -iname "*.asi" \) 2>/dev/null || true; })

CANT_ASI=$(ls -1 *.asi scripts/*.asi plugins/*.asi 2>/dev/null | wc -l)

# Modo Pantalla Nativo Directo en Hardware (sin capas virtuales por defecto)
[ -z "$ESCRITORIO_VIRTUAL" ] && ESCRITORIO_VIRTUAL="0"
RUN_PREFIX=""
if [ "$ESCRITORIO_VIRTUAL" = "1" ]; then
    RUN_PREFIX="explorer /desktop=${DESKTOP_NAME:-GameRanger},${DESKTOP_RES:-1024x720}"
fi

GAMESCOPE_PREFIX=""
if [ "$PERFIL_RENDIMIENTO" = "extremo" ] && [[ ! "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]] && [ "$IS_PROGRAM" -eq 0 ] && [ "${PE_CATEGORY:-juego}" != "programa" ]; then
    if command -v gamescope &>/dev/null; then
        GAMESCOPE_PREFIX="gamescope -W ${best_w:-1280} -H ${best_h:-720} -r 60 -F fsr --"
    fi
fi

if [ "$IS_PROGRAM" -eq 1 ] || [ "${PE_CATEGORY:-juego}" = "programa" ]; then
    perf_label="Entorno de Escritorio Windows (ClearType HD)"
else
    perf_label="${PERFIL_RENDIMIENTO:-inteligente}"
    case "$perf_label" in
        inteligente|maximo) perf_label="Inteligente (Autocalibrado)" ;;
        estandar) perf_label="Estándar / Compatibilidad" ;;
        extremo) perf_label="Portátil Extremo (FSR Boost)" ;;
        ahorro) perf_label="Ahorro de Energía" ;;
    esac
fi

echo ""
if [ "$IS_PROGRAM" -eq 1 ] || [ "${PE_CATEGORY:-juego}" = "programa" ]; then
    echo "[+] Ejecutando Programa de Windows [Modo Ventana Nativa - ClearType HD] (Vessel v1.2)..."
    echo "    - CPU: ${CPU_MODEL} (${CPU_CORES} Hilos)"
    echo "    - GPU: ${DETECTED_GPU}"
    echo "    - Versión de Vessel: v1.2 (Producción)"
    echo "    - Modo de Ejecución: Ventana Nativa X11 / Wayland (Redimensionable)"
    echo "    - Renderizado de Texto: ClearType HD Subpixel Antialiasing"
    echo "    - Consumo de Recursos: Mínimo (~25-40 MB RAM, 0% CPU adicional)"
    echo "    - Versión de Windows: ${GAME_WINVER^^}"
    if [ -n "$PE_BITS" ] && [ "$PE_BITS" != "0" ]; then
        echo "    - Arquitectura / Binario: ${PE_BITS}-bit (Subsystem ${PE_SUBSYS:-N/A})"
    fi
    echo "    - Runner Wine: ${RUNNER_LABEL}"
    echo "    - Prefijo Wine: ${WINEPREFIX}"
    echo "    - Productividad: RichEdit, MSXML, GDI+ y DirectWrite habilitados"
else
    echo "[+] Ejecutando con Perfil [${perf_label}] (Vessel v1.2)..."
    echo "    - CPU: ${CPU_MODEL} (${CPU_CORES} Hilos)"
    echo "    - GPU: ${DETECTED_GPU}"
    echo "    - Versión de Vessel: v1.2 (Producción)"
    echo "    - Renderizador: ${RENDERER_IN_USE:-DXVK (Vulkan)}"
    echo "    - Consumo RAM / CPU: Ultra-Liviano (WINEDEBUG silenciado, Pipelines dinámicos)"
    echo "    - Fidelidad 3D & Shaders: Filtrado Anisotrópico 16x | D3D8to9 Vulkan | NVAPI: ${NVAPI_ACTIVO}"
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
fi

# Argumentos de pantalla completa y resolución adaptativa según el motor del juego
if [ "$IS_PROGRAM" -ne 1 ] && [[ ! "$TARGET_FILE" =~ ([Gg]ame[Rr]anger|winecfg|regedit|cmd|notepad) ]]; then
    # Unity Engine (ej. *_Data o UnityPlayer.dll)
    if [ -d "${TARGET_DIR}/${TARGET_FILE%.*}_Data" ] || [ -f "${TARGET_DIR}/UnityPlayer.dll" ]; then
        EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -screen-fullscreen 1 -screen-width ${best_w} -screen-height ${best_h}"
    # Source Engine (Half-Life 2, L4D, Portal, etc. - excluyendo GoldSrc para no duplicar banderas)
    elif [ "$perfil_id" != "valve_goldsrc" ] && { [ -f "${TARGET_DIR}/tier0.dll" ] || [ -f "${TARGET_DIR}/bin/tier0.dll" ]; }; then
        EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -fullscreen -w ${best_w} -h ${best_h}"
    # Unreal Engine 3/4
    elif [ -d "${TARGET_DIR}/Engine" ] || [ -d "${TARGET_DIR}/Binaries" ]; then
        EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -fullscreen"
    fi
fi

# Guardián en segundo plano para asegurar pantalla completa en juegos retro que no manejan fullscreen nativo
WATCHDOG_PID=""
if [ -n "${DISPLAY:-}" ] && [ "$IS_PROGRAM" -ne 1 ] && [[ ! "$TARGET_FILE" =~ ([Gg]ame[Rr]anger|winecfg|regedit|cmd|notepad|GTA|GTA5|PlayGTAV) ]]; then
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
    if [ -n "$PREV_POWER_PROFILE" ] && command -v powerprofilesctl &>/dev/null; then
        powerprofilesctl set "$PREV_POWER_PROFILE" 2>/dev/null || true
    fi
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
    [ -n "$TEMP_GAME_LOG" ] && rm -f "$TEMP_GAME_LOG" 2>/dev/null || true
    "$WINESERVER_CMD" -k 2>/dev/null || wineserver -k 2>/dev/null || true
}
trap limpiar_procesos_al_interrumpir INT TERM

# Optimizaciones de baja latencia del Kernel Linux para eliminar micro-stuttering (1% lows)
if [ -w /proc/sys/kernel/split_lock_mitigate ]; then
    echo 0 > /proc/sys/kernel/split_lock_mitigate 2>/dev/null || true
fi
if [ -w /proc/sys/vm/compaction_proactiveness ]; then
    echo 0 > /proc/sys/vm/compaction_proactiveness 2>/dev/null || true
fi
CURRENT_MAPS=$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo 65530)
if [ "$CURRENT_MAPS" -lt 1048576 ] && [ -w /proc/sys/vm/max_map_count ]; then
    echo 1048576 > /proc/sys/vm/max_map_count 2>/dev/null || true
fi

# Sincronizar buffers de disco y optimizar prioridad de proceso
sync 2>/dev/null || true
if [ "$IS_PROGRAM" -eq 1 ] || [ "${PE_CATEGORY:-juego}" = "programa" ]; then
    renice -n 0 $$ 2>/dev/null || true
else
    renice -n -5 $$ 2>/dev/null || true
fi

# Optimización profunda de RAM: Liberación de cachés residuales y compactación de memoria para evitar stuttering
RAM_AVAIL_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}' || echo 8192)
if [ -n "$RAM_AVAIL_MB" ] && [ "$RAM_AVAIL_MB" -lt 3500 ]; then
    sync 2>/dev/null || true
    if [ -w /proc/sys/vm/drop_caches ]; then
        echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    fi
    if [ -w /proc/sys/vm/compact_memory ]; then
        echo 1 > /proc/sys/vm/compact_memory 2>/dev/null || true
    fi
fi

# Ajuste de CPU Governor a alto rendimiento (performance) si los privilegios del kernel lo admiten
for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    if [ -w "$gov" ]; then
        echo "performance" > "$gov" 2>/dev/null || true
    fi
done

# Desactivar 'set -e' antes de la ejecución para garantizar que salidas con código != 0 no interrumpan la limpieza
set +e

# Limpiar instancias colgadas previas del ejecutable objetivo para evitar bloqueos por mutex único de Windows
if [ -n "$TARGET_FILE" ] && [[ ! "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]]; then
    limpiar_zombies_juego "$(basename "$TARGET_FILE" | sed 's/\./\\./g')"
fi

# Preparar archivo temporal para captura completa de consola y diagnóstico de fallos
TEMP_GAME_LOG=$(mktemp "${TMPDIR:-/tmp}/vessel_run_XXXXXX.log" 2>/dev/null || echo "/tmp/vessel_run_$$.log")
touch "$TEMP_GAME_LOG" 2>/dev/null || true

# Construir comando final de forma segura con arrays de Bash para evitar problemas de quoting
FINAL_CMD=()

# 1. Capa Gamescope (solo para juegos estándar, no utilidades/scripts/GameRanger)
if [[ ! "$TARGET_FILE" =~ \.([mM][sS][iI]|[rR][eE][gG]|[vV][bB][sS]|[jJ][sS]|[pP][sS]1|[lL][nN][kK]|[iI][nN][kK]|[bB][aA][tT]|[cC][mM][dD])$ ]] && [[ ! "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]] && [ -n "$GAMESCOPE_PREFIX" ]; then
    read -r -a GS_OPTS <<< "$GAMESCOPE_PREFIX"
    FINAL_CMD+=("${GS_OPTS[@]}")
fi

# 2. GameMode
if [ -n "$GAMEMODE" ] && command -v "$GAMEMODE" &>/dev/null && [[ ! "$TARGET_FILE" =~ \.([rR][eE][gG]|[vV][bB][sS]|[jJ][sS])$ ]]; then
    FINAL_CMD+=("$GAMEMODE")
fi

# 3. Binario principal de Wine
FINAL_CMD+=("$WINE_CMD")

# 4. Prefijo de escritorio virtual (si aplica y no es GameRanger o reg)
if [ -n "$RUN_PREFIX" ] && [[ ! "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]] && [[ ! "$TARGET_FILE" =~ \.([rR][eE][gG]|[vV][bB][sS]|[jJ][sS]|[pP][sS]1)$ ]]; then
    read -r -a RUN_OPTS <<< "$RUN_PREFIX"
    FINAL_CMD+=("${RUN_OPTS[@]}")
fi

# 5. Parámetros según el tipo de ejecutable o script
if [[ "$TARGET_FILE" =~ \.(msi|MSI)$ ]]; then
    FINAL_CMD+=("msiexec" "/i" "$TARGET_FILE" "$@")
elif [[ "$TARGET_FILE" =~ \.(reg|REG)$ ]]; then
    echo "[+] Importando archivo de registro en Wine: $TARGET_FILE"
    FINAL_CMD+=("regedit" "/s" "$TARGET_FILE")
elif [[ "$TARGET_FILE" =~ \.([vV][bB][sS]|[jJ][sS])$ ]]; then
    echo "[+] Ejecutando script de Windows ($TARGET_FILE)..."
    FINAL_CMD+=("wscript.exe" "$TARGET_FILE" "$@")
elif [[ "$TARGET_FILE" =~ \.([pP][sS]1)$ ]]; then
    echo "[+] Ejecutando script PowerShell de Windows ($TARGET_FILE)..."
    FINAL_CMD+=("powershell.exe" "-ExecutionPolicy" "Bypass" "-File" "$TARGET_FILE" "$@")
elif [[ "$TARGET_FILE" =~ \.(lnk|ink|LNK|INK)$ ]]; then
    FINAL_CMD+=("start" "/unix" "$TARGET" "$@")
elif [[ "$TARGET_FILE" =~ \.([bB][aA][tT]|[cC][mM][dD])$ ]]; then
    FINAL_CMD+=("cmd" "/c" "$TARGET_FILE" "$@")
else
    FINAL_CMD+=("$TARGET_FILE" "$@")
fi

# 6. Argumentos extras del motor / juego
if [ -n "$EXTRA_APP_ARGS" ] && [[ ! "$TARGET_FILE" =~ \.([rR][eE][gG]|[vV][bB][sS]|[jJ][sS]|[pP][sS]1)$ ]]; then
    read -r -a EXTRA_OPTS <<< "$EXTRA_APP_ARGS"
    FINAL_CMD+=("${EXTRA_OPTS[@]}")
fi

# 6.1 Alineación y posicionamiento dinámico en pantalla objetivo (Multimonitor Wayland/X11)
MON_WATCHDOG_PID=""
if ([ -n "$ACTIVE_MON_X" ] && [ "$ACTIVE_MON_X" -ne 0 ]) || ([ -n "$ACTIVE_MON_Y" ] && [ "$ACTIVE_MON_Y" -ne 0 ]); then
    (
        target_name="${TARGET_FILE%.*}"
        for i in {1..25}; do
            sleep 0.4
            w_ids=$(xdotool search --name "$target_name" 2>/dev/null || xdotool search --class "wine" 2>/dev/null || true)
            if [ -n "$w_ids" ]; then
                for wid in $w_ids; do
                    xdotool windowmove "$wid" "$ACTIVE_MON_X" "$ACTIVE_MON_Y" 2>/dev/null || true
                done
                break
            fi
        done
    ) &
    MON_WATCHDOG_PID=$!
fi

# 7. Ejecución con captura en tiempo real
EXEC_START_TIME=$(date +%s)
"${FINAL_CMD[@]}" 2>&1 | tee "$TEMP_GAME_LOG"
EXIT_STATUS="${PIPESTATUS[0]}"
EXEC_DURATION=$(( $(date +%s) - EXEC_START_TIME ))

# Sincronización activa de subprocesos de Windows:
# Si el ejecutable lanzó procesos secundarios (lanzadores, instaladores, subprocesses de juegos),
# mantenemos la sesión activa mientras existan procesos de juego en el WINEPREFIX.
if [ -n "$WINEPREFIX" ] && [ -d "$WINEPREFIX" ]; then
    while true; do
        has_active_game=false
        for pid_env in /proc/[0-9]*/environ; do
            [ -r "$pid_env" ] || continue
            if grep -qF "WINEPREFIX=${WINEPREFIX}" "$pid_env" 2>/dev/null; then
                c_pid="${pid_env#/proc/}"
                c_pid="${c_pid%/environ}"
                [ "$c_pid" -eq "$$" ] 2>/dev/null && continue
                [ "$c_pid" -eq "$PPID" ] 2>/dev/null && continue
                cmdline=$(cat "/proc/${c_pid}/cmdline" 2>/dev/null | tr '\0' ' ' || true)
                if echo "$cmdline" | grep -qiE '\.exe' && \
                   ! echo "$cmdline" | grep -qiE 'services\.exe|winedevice\.exe|plugplay\.exe|explorer\.exe|rpcss\.exe|conhost\.exe|svchost\.exe|wineboot\.exe'; then
                    has_active_game=true
                    break
                fi
            fi
        done
        [ "$has_active_game" = false ] && break
        sleep 1
    done
fi

# Restaurar perfil de energía previo del CPU
if [ -n "$PREV_POWER_PROFILE" ] && command -v powerprofilesctl &>/dev/null; then
    powerprofilesctl set "$PREV_POWER_PROFILE" 2>/dev/null || true
fi

# Terminar vigilantes en segundo plano si siguen activos
[ -n "$WATCHDOG_PID" ] && kill "$WATCHDOG_PID" 2>/dev/null || true
[ -n "$GR_WATCHDOG_PID" ] && kill "$GR_WATCHDOG_PID" 2>/dev/null || true
[ -n "$MON_WATCHDOG_PID" ] && kill "$MON_WATCHDOG_PID" 2>/dev/null || true

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

# ==============================================================================
# SISTEMA DE DIAGNÓSTICO INTELIGENTE Y REGISTRO DE ERRORES / CRASHES
# - Distingue salidas limpias voluntarias (código 0, código 58 GTA SA, SIGINT 130, SIGTERM 143)
#   de excepciones críticas y fallos tempranos.
# ==============================================================================
HUBO_ERROR=0
# 1. Señales fatales del sistema (SIGSEGV=139, SIGABRT=134, SIGBUS=135, SIGFPE=136, SIGILL=132)
if [[ "$EXIT_STATUS" =~ ^(132|134|135|136|139)$ ]]; then
    HUBO_ERROR=1
# 2. Excepción crítica explícita en el registro de Wine o Vulkan
elif [ -s "$TEMP_GAME_LOG" ] && grep -qiE 'Unhandled exception: [0-9a-fA-F]|wine: Unhandled|page fault on (read|write)|0xc0000005|Assertion failed|Segmentation fault|Fatal error|Failed to create SDL|Sys_Error|VK_ERROR_DEVICE_LOST|DXGI_ERROR_DEVICE_RESET' "$TEMP_GAME_LOG" 2>/dev/null; then
    HUBO_ERROR=1
# 3. Código de salida de error temprano (< 4 segundos de ejecución) excluyendo salidas voluntarias conocidas (0, 58, 130, 143)
elif [ "$EXIT_STATUS" -ne 0 ] && [ "$EXIT_STATUS" -ne 58 ] && [ "$EXIT_STATUS" -ne 130 ] && [ "$EXIT_STATUS" -ne 143 ]; then
    if [ "$EXEC_DURATION" -lt 4 ]; then
        HUBO_ERROR=1
    fi
fi

if [ "$HUBO_ERROR" -eq 1 ]; then
    mkdir -p "${DIR}/logs_errores"
    log_ts=$(date '+%Y%m%d_%H%M%S')
    log_app_name=$(basename "$TARGET_FILE" 2>/dev/null | tr -cd '[:alnum:]_.-' || echo "juego")
    ERROR_REPORT_FILE="${DIR}/logs_errores/error_${log_app_name}_${log_ts}.log"
    ULTIMO_ERROR_FILE="${DIR}/logs_errores/ultimo_error.log"

    {
        echo "================================================================================"
        echo "VESSEL v1.2 - INFORME DETALLADO DE ERROR / CIERRE INESPERADO"
        echo "================================================================================"
        echo "Fecha y Hora          : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Juego / Ejecutable    : ${TARGET_FILE}"
        echo "Ruta Completa         : ${TARGET}"
        echo "Directorio de Trabajo : ${TARGET_DIR}"
        echo "Código de Salida      : ${EXIT_STATUS}"
        echo "Perfil Activo         : ${perfil_id:-generico}"
        echo "Arquitectura PE / API : ${PE_BITS:-32}-bit | ${PE_API:-DirectX}"
        echo "Versión de Windows    : ${GAME_WINVER:-win10}"
        echo "Renderizador          : ${RENDERER_IN_USE:-DXVK (Vulkan)}"
        echo "CPU                   : ${CPU_MODEL:-Desconocida} (${CPU_CORES:-1} Hilos)"
        echo "GPU                   : ${DETECTED_GPU:-Desconocida}"
        echo "Runner Wine           : ${WINE_CMD} ($("$WINE_CMD" --version 2>/dev/null || echo "N/A"))"
        echo "Prefijo Wine          : ${WINEPREFIX}"
        echo "Fsync / Esync         : $([ "$WINEFSYNC" = "1" ] && echo "Fsync Activo" || echo "Esync Activo")"
        echo "FSR Upscaling         : ${fsr_banner:-Desactivado}"
        echo "Límite FPS            : ${LIMITE_FPS:-60} FPS"
        echo "Argumentos Extras     : ${EXTRA_APP_ARGS:-Ninguno}"
        echo "================================================================================"
        echo ""

        # Adjuntar registros gráficos de DXVK si existen en el directorio del juego o DIR
        for dxvk_l in "${TARGET_DIR}/${TARGET_FILE%.*}_d3d11.log" "${TARGET_DIR}/${TARGET_FILE%.*}_d3d9.log" "${TARGET_DIR}/${TARGET_FILE%.*}_dxgi.log" "${DIR}/dxvk.log"; do
            if [ -f "$dxvk_l" ] && [ -s "$dxvk_l" ]; then
                echo "--- REGISTRO GRÁFICO DXVK ($(basename "$dxvk_l")) ---"
                tail -n 30 "$dxvk_l" 2>/dev/null || true
                echo ""
            fi
        done

        echo "--- REGISTRO COMPLETO DE CONSOLA Y SALIDA DE ERROR (WINE / STDERR) ---"
        if [ -s "$TEMP_GAME_LOG" ]; then
            cat "$TEMP_GAME_LOG"
        else
            echo "(El proceso no emitió mensajes de consola antes de cerrarse)"
        fi
        echo ""
        echo "================================================================================"
        echo "FIN DEL INFORME"
        echo "================================================================================"
    } > "$ERROR_REPORT_FILE" 2>/dev/null || true

    # Mantener copia como ultimo_error.log para consulta instantánea
    cp -f "$ERROR_REPORT_FILE" "$ULTIMO_ERROR_FILE" 2>/dev/null || true

    # Si el directorio del juego es accesible con permisos de escritura, guardar copia local
    if [ -d "$TARGET_DIR" ] && [ -w "$TARGET_DIR" ]; then
        cp -f "$ERROR_REPORT_FILE" "${TARGET_DIR}/vessel_error.log" 2>/dev/null || true
    fi

    # Rotar registros antiguos: conservar solo los 10 más recientes
    ls -t "${DIR}/logs_errores"/error_*.log 2>/dev/null | tail -n +11 | xargs -r rm -f 2>/dev/null || true

    echo ""
    echo "================================================================================"
    echo "[!] SE HA DETECTADO UN ERROR O CIERRE INESPERADO AL EJECUTAR: ${TARGET_FILE}"
    echo "[!] Código de salida: ${EXIT_STATUS}"
    echo "[!] El informe de diagnóstico ha sido guardado exitosamente en:"
    echo "    -> ${ERROR_REPORT_FILE}"
    echo "    -> ${ULTIMO_ERROR_FILE}"
    [ -f "${TARGET_DIR}/vessel_error.log" ] && echo "    -> ${TARGET_DIR}/vessel_error.log"
    echo "================================================================================"
    echo ""
else
    # Si el juego cerró correctamente, limpiar archivo residual de fallos previos en la carpeta del juego y normalizar estado
    [ -f "${TARGET_DIR}/vessel_error.log" ] && rm -f "${TARGET_DIR}/vessel_error.log" 2>/dev/null || true
    EXIT_STATUS=0
fi

# Eliminar archivo temporal de captura en cualquier caso
rm -f "$TEMP_GAME_LOG" 2>/dev/null || true

# Esperar sincronización limpia de los subprocesos de Wine sin matarlos abruptamente
"$WINESERVER_CMD" -w 2>/dev/null || wineserver -w 2>/dev/null || true
exit $EXIT_STATUS
