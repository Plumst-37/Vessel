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

MOTOR_INFERENCIA="${CORE_DIR}/motor_inferencia.py"
[ ! -f "$MOTOR_INFERENCIA" ] && MOTOR_INFERENCIA="${DIR}/motor_inferencia.py"

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
FORCE_WINED3D=0
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
        --wined3d)
            FORCE_WINED3D=1
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

# 4.0 Identificación de comandos y herramientas del sistema Windows / Wine (no auto-reparar como juegos)
IS_BUILTIN_WIN_TOOL=0
target_base_low=$(basename "$TARGET" 2>/dev/null | tr '[:upper:]' '[:lower:]')
if [[ "$target_base_low" =~ ^(explorer|winecfg|regedit|notepad|cmd|taskmgr|control|msiexec|dxdiag|winemine|winefile|wordpad|write|winver|start|progman)(\.exe)?$ ]]; then
    IS_BUILTIN_WIN_TOOL=1
    IS_PROGRAM=1
fi

# 4.0 Auto-reparación transparente de rutas inexistentes o movidas (ej. carpetas ZIP extraídas)
if [ "$IS_BUILTIN_WIN_TOOL" -eq 0 ] && [ ! -f "$TARGET" ] && [[ ! "$TARGET" =~ [Gg]ame[Rr]anger ]]; then
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
if [ "$IS_BUILTIN_WIN_TOOL" -eq 0 ] && [[ "$TARGET" != /* ]] && [ -f "${DIR}/${TARGET}" ]; then
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

# 4.0.3 Detección transparente de paquetes portables Electron (NSIS app-64.7z / app-32.7z)
# Despliega automáticamente una sola vez para eliminar 25s de descompresión repetida y fallos de ICU
if [ "$IS_BUILTIN_WIN_TOOL" -eq 0 ] && [ -f "$TARGET" ] && [[ "$(basename "$TARGET" | tr '[:upper:]' '[:lower:]')" =~ \.exe$ ]] && command -v 7z &>/dev/null; then
    if 7z l "$TARGET" '$PLUGINSDIR/app*.7z' 2>/dev/null | grep -qiE 'app-(64|32)\.7z'; then
        p_name=$(basename "$TARGET" | sed -E 's/([-_]?[0-9]+\.[0-9]+.*|[_-]setup|[_-]portable|\.exe)//gi' | tr -s ' -' '_' | sed 's/^_//;s/_$//')
        [ -z "$p_name" ] && p_name="portable_app"
        PORTABLE_DIR="${DIR}/programas_portables/${p_name}"
        if [ ! -d "$PORTABLE_DIR" ] || [ ! -f "${PORTABLE_DIR}/icudtl.dat" ]; then
            echo "[*] Desplegando paquete portable Electron para arranque nativo instantáneo..."
            mkdir -p "$PORTABLE_DIR"
            tmp_sfx_dir=$(mktemp -d "${TMPDIR:-/tmp}/vessel_sfx_XXXXXX" 2>/dev/null || echo "/tmp/vessel_sfx_$$")
            7z e -y -o"$tmp_sfx_dir" "$TARGET" '$PLUGINSDIR/app*.7z' >/dev/null 2>&1 || true
            inner_7z=$(find "$tmp_sfx_dir" -name "app*.7z" 2>/dev/null | head -n 1)
            if [ -n "$inner_7z" ] && [ -f "$inner_7z" ]; then
                7z x -y -o"$PORTABLE_DIR" "$inner_7z" >/dev/null 2>&1 || true
            fi
            rm -rf "$tmp_sfx_dir" 2>/dev/null || true
        fi
        real_electron_exe=$(find "$PORTABLE_DIR" -maxdepth 2 -iname "*.exe" ! -iname "electron.exe" 2>/dev/null | head -n 1)
        [ -z "$real_electron_exe" ] && [ -f "${PORTABLE_DIR}/electron.exe" ] && real_electron_exe="${PORTABLE_DIR}/electron.exe"
        if [ -n "$real_electron_exe" ] && [ -f "$real_electron_exe" ]; then
            echo "[+] Paquete Electron portable optimizado para arranque instantáneo: $(basename "$real_electron_exe")"
            TARGET="$real_electron_exe"
        fi

        # Si contiene un paquete web app.asar, desplegarlo para soporte nativo instantáneo si Wine del sistema carece de APIs modernas (IsWindowArranged)
        ASAR_FILE=""
        WEB_EXTRACT_DIR=""
        if [ -n "${PORTABLE_DIR:-}" ] && [ -f "${PORTABLE_DIR}/resources/app.asar" ]; then
            ASAR_FILE="${PORTABLE_DIR}/resources/app.asar"
            WEB_EXTRACT_DIR="${PORTABLE_DIR}/app_web"
        elif [ -f "$(dirname "$TARGET")/resources/app.asar" ]; then
            ASAR_FILE="$(dirname "$TARGET")/resources/app.asar"
            WEB_EXTRACT_DIR="$(dirname "$TARGET")/app_web"
        fi

        if [ -n "$ASAR_FILE" ] && [ ! -d "$WEB_EXTRACT_DIR" ]; then
            python3 -c "
import struct, json, os, sys
asar_path, out_dir = sys.argv[1], sys.argv[2]
try:
    with open(asar_path, 'rb') as f:
        f.seek(4)
        total_size, header_size, json_len = struct.unpack('<III', f.read(12))
        header = json.loads(f.read(json_len).decode('utf-8'))
        base_offset = 16 + json_len
        def extract(d, p):
            os.makedirs(p, exist_ok=True)
            for k, v in d.items():
                cur = os.path.join(p, k)
                if 'files' in v: extract(v['files'], cur)
                elif 'offset' in v:
                    f.seek(base_offset + int(v['offset']))
                    with open(cur, 'wb') as out_f: out_f.write(f.read(v['size']))
        extract(header['files'], out_dir)
except Exception: pass
" "$ASAR_FILE" "$WEB_EXTRACT_DIR" 2>/dev/null || true
        fi

        FOUND_HTML=""
        if [ -n "$WEB_EXTRACT_DIR" ] && [ -d "$WEB_EXTRACT_DIR" ]; then
            FOUND_HTML=$(find "$WEB_EXTRACT_DIR" -maxdepth 2 -iname "*.html" 2>/dev/null | head -n 1 || true)
        fi
    fi
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
                db_backend=$(echo "$matched_line" | cut -d'|' -f7 | tr -d '\r\n ')
                [ "$db_backend" = "wined3d" ] && FORCE_WINED3D=1
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
    PE_CATEGORY=""
    PE_IS_ELECTRON="0"

    if [ -f "$ANALIZADOR_PE" ] && [ -f "$TARGET" ]; then
        pe_eval=$(python3 "$ANALIZADOR_PE" --bash-full "$TARGET" 2>/dev/null || true)
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

    # Si es un programa normal de Windows y la BD tenía winxp heredado erróneamente, corregir a win10
    if [ "$IS_PROGRAM" -eq 1 ] && [ "$GAME_WINVER" = "winxp" ]; then
        GAME_WINVER="win10"
    fi

    # Inferencia heurística experta de variables de entorno (fallback si no vino integrada en --bash-full)
    if [ -z "${VESSEL_INFERRED_API:-}" ] && [ -f "$MOTOR_INFERENCIA" ] && [ -f "$TARGET" ]; then
        motor_eval=$(python3 "$MOTOR_INFERENCIA" "$TARGET" --env 2>/dev/null || true)
        if [ -n "$motor_eval" ]; then
            eval "$motor_eval" || true
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
    if [ "${IS_BUILTIN_WIN_TOOL:-0}" -eq 0 ]; then
        if [ "$PE_HAS_DX12" = "1" ] || [ -f "$(dirname "$TARGET")/d3d12.dll" ] || [ -f "$(dirname "$TARGET")/d3d12core.dll" ] || \
           find "$(dirname "$TARGET")" -maxdepth 2 -iname "d3d12*.dll" 2>/dev/null | grep -q . || \
           find "$(dirname "$TARGET")" -maxdepth 3 -iname "*re_chunk_000*.pak" 2>/dev/null | grep -q .; then
            es_dx12=true
        fi
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

        # 1. Despliegue automático desde paquete portable tar.xz (listo para jugar sin instalación ni dependencias)
        if [ -z "$FOUND_GR" ]; then
            gr_archive=""
            [ -f "${DATOS_DIR}/GameRanger.tar.xz" ] && gr_archive="${DATOS_DIR}/GameRanger.tar.xz"
            [ -z "$gr_archive" ] && [ -f "${DIR}/datos/GameRanger.tar.xz" ] && gr_archive="${DIR}/datos/GameRanger.tar.xz"
            [ -z "$gr_archive" ] && [ -f "${DIR}/GameRanger.tar.xz" ] && gr_archive="${DIR}/GameRanger.tar.xz"

            if [ -n "$gr_archive" ] && [ -s "$gr_archive" ]; then
                echo "[📦] Desplegando GameRanger Portable en el prefijo Wine..."
                mkdir -p "${WINEPREFIX}/drive_c/Program Files" "$GR_ROAMING" "$GR_PREFS"
                tar -xJf "$gr_archive" -C "${WINEPREFIX}/drive_c/Program Files/" 2>/dev/null || true
                if [ -d "${WINEPREFIX}/drive_c/Program Files/GameRanger" ]; then
                    cp -rf "${WINEPREFIX}/drive_c/Program Files/GameRanger"/* "$GR_ROAMING/" 2>/dev/null || true
                    FOUND_GR="${WINEPREFIX}/drive_c/Program Files/GameRanger/GameRanger.exe"
                fi
            fi
        fi

        # 2. Despliegue desde carpeta fuente si existe
        if [ -z "$FOUND_GR" ]; then
            for gr_cand in "${DIR}/GameRanger" "${DATOS_DIR}/GameRanger"; do
                if [ -d "$gr_cand" ] && [ -f "$gr_cand/GameRanger.exe" ]; then
                    mkdir -p "$GR_ROAMING" "$GR_PREFS" "${WINEPREFIX}/drive_c/Program Files/GameRanger"
                    cp -rf "$gr_cand"/* "$GR_ROAMING/" 2>/dev/null || true
                    cp -rf "$gr_cand"/* "${WINEPREFIX}/drive_c/Program Files/GameRanger/" 2>/dev/null || true
                    FOUND_GR="${WINEPREFIX}/drive_c/Program Files/GameRanger/GameRanger.exe"
                    break
                fi
            done
        fi

        # 3. Descarga dinámica resiliente con fallback si no existe localmente
        if [ -z "$FOUND_GR" ] && command -v curl &>/dev/null; then
            echo "[*] Obteniendo GameRanger para el entorno..."
            # Intentar primero paquete portable oficial desde el repositorio de GitHub
            curl -fsSL -k "https://raw.githubusercontent.com/Plumst-37/Vessel/main/datos/GameRanger.tar.xz" -o "${DIR}/datos/GameRanger.tar.xz" 2>/dev/null || true
            if [ -s "${DIR}/datos/GameRanger.tar.xz" ]; then
                mkdir -p "${WINEPREFIX}/drive_c/Program Files" "$GR_ROAMING" "$GR_PREFS"
                tar -xJf "${DIR}/datos/GameRanger.tar.xz" -C "${WINEPREFIX}/drive_c/Program Files/" 2>/dev/null || true
                if [ -d "${WINEPREFIX}/drive_c/Program Files/GameRanger" ]; then
                    cp -rf "${WINEPREFIX}/drive_c/Program Files/GameRanger"/* "$GR_ROAMING/" 2>/dev/null || true
                    FOUND_GR="${WINEPREFIX}/drive_c/Program Files/GameRanger/GameRanger.exe"
                fi
            fi

            # Fallback: Descargar instalador oficial de GameRanger con SSL inseguro (-k) o HTTP plano
            if [ -z "$FOUND_GR" ]; then
                curl -fsSL -k "https://www.gameranger.com/download/GameRangerSetup.exe" -o "${DIR}/GameRangerSetup.exe" 2>/dev/null || \
                curl -fsSL "http://www.gameranger.com/download/GameRangerSetup.exe" -o "${DIR}/GameRangerSetup.exe" 2>/dev/null || true
                if [ -s "${DIR}/GameRangerSetup.exe" ] && [ $(wc -c < "${DIR}/GameRangerSetup.exe") -gt 50000 ]; then
                    echo "[*] Instalando GameRanger oficial en el entorno..."
                    # Auto-inicializar prefijo si no existe antes de correr el instalador
                    if [ ! -f "${WINEPREFIX}/system.reg" ]; then
                        DISPLAY="" WINEDLLOVERRIDES="mscoree,mshtml=;winemenubuilder.exe=d;" WINEPREFIX="$WINEPREFIX" wine wineboot -u >/dev/null 2>&1 || true
                    fi
                    WINEPREFIX="${WINEPREFIX}" WINEDLLOVERRIDES="winemenubuilder.exe=d;dxgi=b;d3d11=b;d3d10core=b;d3d9=b;" wine "${DIR}/GameRangerSetup.exe" 2>/dev/null || true
                    FOUND_GR=$(find "${WINEPREFIX}/drive_c" -name "GameRanger.exe" 2>/dev/null | head -n 1)
                fi
            fi
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
        fi
    fi
fi


# 4.3 Obtener directorio y nombre base del archivo objetivo de ejecución
if [ "${IS_BUILTIN_WIN_TOOL:-0}" -eq 1 ]; then
    TARGET_DIR="${DIR}"
    TARGET_FILE="$target_base_low"
    [[ ! "$TARGET_FILE" =~ \.exe$ ]] && TARGET_FILE="${TARGET_FILE}.exe"
else
    TARGET_DIR="$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd || dirname "$TARGET")"
    TARGET_FILE="$(basename "$TARGET")"
fi

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
    if [ "${PE_HAS_DX12:-0}" = "1" ]; then
        echo -e "${YELLOW}💡 Nota: Este juego utiliza DirectX 12. Si experimentas problemas con Wine del sistema, puedes usar un runner especializado con: ${BOLD}vessel runner --kron4ek${RESET}"
    fi
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

# Si el runner activo de Wine es < 10.8 (ej. Debian Wine 10.0), Electron 38+/Chromium 140+ falla por falta de IsWindowArranged
# En ese caso, activar modo nativo de escritorio ultra-rápido si se detectó interfaz web HTML y hay navegador compatible
USE_NATIVE_WEB_APP=0
NATIVE_WEB_BROWSER=""
if [ -n "${FOUND_HTML:-}" ] && [ -f "${FOUND_HTML:-}" ]; then
    wine_ver_num=$("$WINE_CMD" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n 1 || echo "0.0")
    major_ver=$(echo "$wine_ver_num" | cut -d. -f1)
    minor_ver=$(echo "$wine_ver_num" | cut -d. -f2)
    if [ "${major_ver:-0}" -lt 10 ] || { [ "${major_ver:-0}" -eq 10 ] && [ "${minor_ver:-0}" -lt 8 ]; }; then
        for b in brave-browser google-chrome chromium chromium-browser; do
            if command -v "$b" &>/dev/null; then
                NATIVE_WEB_BROWSER="$b"
                USE_NATIVE_WEB_APP=1
                break
            fi
        done
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

# 7.0.5 Bóveda Universal de Partidas Guardadas (~/.local/share/vessel_saves)
# Garantiza que las partidas de GTA V (Goldberg SocialClub), Steam/EMPRESS/CODEX y Saved Games
# se conserven y carguen automáticamente entre actualizaciones, reinstalaciones o prefijos aislados.
if [ "${USE_NATIVE_WEB_APP:-0}" -ne 1 ] && [ "$IS_PROGRAM" -ne 1 ] && [ "${PE_CATEGORY:-juego}" != "programa" ] && [ -d "${WINEPREFIX}/drive_c/users/${USER}" ]; then
    VESSEL_SAVES_DIR="${HOME}/.local/share/vessel_saves"
    mkdir -p "$VESSEL_SAVES_DIR" 2>/dev/null || true
    SAVE_REL_PATHS=(
        "AppData/Roaming/Goldberg SocialClub Emu Saves"
        "AppData/Roaming/Goldberg SteamEmu Saves"
        "AppData/Roaming/EMPRESS"
        "AppData/Roaming/Steam"
        "AppData/Local/Rockstar Games"
        "Saved Games"
    )
    for rel_save in "${SAVE_REL_PATHS[@]}"; do
        vault_name="$(basename "$rel_save")"
        vault_path="${VESSEL_SAVES_DIR}/${vault_name}"
        prefix_save="${WINEPREFIX}/drive_c/users/${USER}/${rel_save}"
        mkdir -p "$vault_path" "$(dirname "$prefix_save")" 2>/dev/null || true

        # Importar partidas previas desde otras instalaciones de Vessel o ~/.wine sin sobreescribir archivos existentes
        for legacy_root in "${HOME}/Documentos/Juegos/Vessel/wineprefix" "${HOME}/Vessel/wineprefix" "${HOME}/.wine"; do
            legacy_save="${legacy_root}/drive_c/users/${USER}/${rel_save}"
            if [ -d "$legacy_save" ] && [ ! -L "$legacy_save" ]; then
                cp -rn "$legacy_save"/. "$vault_path"/ 2>/dev/null || true
            fi
        done

        # Vincular el directorio de partidas del prefijo activo hacia la bóveda persistente
        if [ -L "$prefix_save" ]; then
            [ "$(readlink "$prefix_save")" != "$vault_path" ] && rm -f "$prefix_save" && ln -s "$vault_path" "$prefix_save" 2>/dev/null || true
        elif [ -d "$prefix_save" ]; then
            cp -ru "$prefix_save"/. "$vault_path"/ 2>/dev/null || true
            rm -rf "$prefix_save" 2>/dev/null || true
            ln -s "$vault_path" "$prefix_save" 2>/dev/null || true
        else
            ln -s "$vault_path" "$prefix_save" 2>/dev/null || true
        fi
    done
fi

# Limpieza rápida de archivos temporales antiguos en el prefijo para evitar degradación
find "${WINEPREFIX}/drive_c/users/${USER}/AppData/Local/Temp" -mindepth 1 -mtime +1 -delete 2>/dev/null || true

# 7.1 Auto-verificación e integración modular de DXVK y VKD3D en el prefijo activo (con caché)
if [ "$RENDERER_IN_USE" != "WineD3D (OpenGL Compatibilidad)" ]; then
    if [ -d "${WINEPREFIX}/drive_c/windows/system32" ]; then
        if [ ! -f "${WINEPREFIX}/.vessel_drivers_installed" ] || [ ! -f "${WINEPREFIX}/drive_c/windows/system32/d3d11.dll" ]; then
            if [ -f "${CORE_DIR}/gestor_drivers.sh" ]; then
                bash "${CORE_DIR}/gestor_drivers.sh" instalar_todo "$WINEPREFIX" >/dev/null 2>&1 || true
                touch "${WINEPREFIX}/.vessel_drivers_installed" 2>/dev/null || true
            elif [ -d "/usr/lib/dxvk/wine64" ]; then
                for dll in d3d11 d3d10core d3d9 d3d8 dxgi; do
                    [ -f "/usr/lib/dxvk/wine64/${dll}.dll.so" ] && ln -sf "/usr/lib/dxvk/wine64/${dll}.dll.so" "${WINEPREFIX}/drive_c/windows/system32/${dll}.dll" 2>/dev/null || true
                    [ -f "/usr/lib/dxvk/wine32/${dll}.dll.so" ] && ln -sf "/usr/lib/dxvk/wine32/${dll}.dll.so" "${WINEPREFIX}/drive_c/windows/syswow64/${dll}.dll" 2>/dev/null || true
                done
                touch "${WINEPREFIX}/.vessel_drivers_installed" 2>/dev/null || true
            elif command -v dxvk-setup &>/dev/null; then
                if [ ! -L "${WINEPREFIX}/drive_c/windows/system32/d3d11.dll" ]; then
                    echo "[*] Instalando y vinculando librerías DXVK (DirectX -> Vulkan) en el prefijo..."
                    WINEPREFIX="$WINEPREFIX" dxvk-setup install -y >/dev/null 2>&1 || true
                    touch "${WINEPREFIX}/.vessel_drivers_installed" 2>/dev/null || true
                fi
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
    # Asegurar D3DCompiler_43 nativo (evita fallo E5017 de vkd3d-shader en juegos DX9/re4_tweaks)
    if [ -f "${DIR}/librerias_cache/directx9/x86/D3DCompiler_43.dll" ]; then
        d3dc_target="${WINEPREFIX}/drive_c/windows/syswow64/d3dcompiler_43.dll"
        [ ! -d "${WINEPREFIX}/drive_c/windows/syswow64" ] && d3dc_target="${WINEPREFIX}/drive_c/windows/system32/d3dcompiler_43.dll"
        if [ ! -f "$d3dc_target" ] || [ "$(stat -c%s "$d3dc_target" 2>/dev/null || echo 0)" -lt 1500000 ]; then
            cp -f "${DIR}/librerias_cache/directx9/x86/D3DCompiler_43.dll" "$d3dc_target" 2>/dev/null || true
            if [ -d "${WINEPREFIX}/drive_c/windows/syswow64" ] && [ -f "${DIR}/librerias_cache/directx9/x64/D3DCompiler_43.dll" ]; then
                cp -f "${DIR}/librerias_cache/directx9/x64/D3DCompiler_43.dll" "${WINEPREFIX}/drive_c/windows/system32/d3dcompiler_43.dll" 2>/dev/null || true
            fi
        fi
    fi
    if [ "$es_dx12" = true ] || [ "${PE_API:-}" = "dx12" ] || [ "${PE_HAS_DX12:-0}" = "1" ]; then
        if [ ! -f "${WINEPREFIX}/drive_c/windows/system32/d3d12.dll" ]; then
            echo "[*] Sincronizando traductor oficial DirectX 12 a Vulkan (VKD3D-Proton)..."
            bash "$local_gestor_lib" instalar_vkd3d "$WINEPREFIX" >/dev/null 2>&1 || true
        fi
    fi
    if [ ! -f "${WINEPREFIX}/drive_c/windows/system32/icuuc.dll" ]; then
        bash "$local_gestor_lib" instalar_icu "$WINEPREFIX" >/dev/null 2>&1 || true
    fi
    if [ -d "${DIR}/wineprefix/drive_c/windows" ] && [ "$WINEPREFIX" != "${DIR}/wineprefix" ]; then
        bash "$local_gestor_lib" propagar "$WINEPREFIX" >/dev/null 2>&1 || true
    fi
fi

# ==============================================================================
# CALIBRACIÓN UNIVERSAL DE COMPATIBILIDAD WINDOWS 10/11, DIRECT2D, DIRECT3D Y VRAM
# ==============================================================================
optimizar_entorno_windows_completo() {
    # Si ya fue calibrado en este prefijo con la versión 4 (Windows 10 22H2 Pro + 3D Fidelity), retornar inmediatamente (0.01s)
    if [ -f "${WINEPREFIX}/.vessel_win_full_v4" ]; then
        return 0
    fi

    # 1. Detección precisa de VRAM de la GPU para reporte fiel a juegos 3D y suites de diseño
    local vram_mb=""
    if command -v nvidia-smi &>/dev/null; then
        vram_mb=$(timeout 2s nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1 || true)
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

[HKEY_CURRENT_USER\Software\Wine]
"Version"="win10"

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion]
"ProductName"="Windows 10 Pro"
"CurrentBuild"="19045"
"CurrentBuildNumber"="19045"
"ReleaseId"="22H2"
"DisplayVersion"="22H2"
"BuildBranch"="vb_release"
"BuildLab"="19041.vb_release.191206-1406"
"BuildLabEx"="19041.1.amd64fre.vb_release.191206-1406"
"CurrentMajorVersionNumber"=dword:0000000a
"CurrentMinorVersionNumber"=dword:00000000
"CurrentVersion"="6.3"
"UBR"=dword:00000ef2
"EditionID"="Professional"
"InstallationType"="Client"
"CompositionVersion"="10.0.19045.3826"
"CSDVersion"=""
"PathName"="C:\\Windows"
"SystemRoot"="C:\\Windows"
"ProgramFilesDir"="C:\\Program Files"
"ProgramFilesDir (x86)"="C:\\Program Files (x86)"
"CommonFilesDir"="C:\\Program Files\\Common Files"
"CommonFilesDir (x86)"="C:\\Program Files (x86)\\Common Files"

[HKEY_LOCAL_MACHINE\Software\WOW6432Node\Microsoft\Windows NT\CurrentVersion]
"ProductName"="Windows 10 Pro"
"CurrentBuild"="19045"
"CurrentBuildNumber"="19045"
"ReleaseId"="22H2"
"DisplayVersion"="22H2"
"BuildBranch"="vb_release"
"BuildLab"="19041.vb_release.191206-1406"
"BuildLabEx"="19041.1.amd64fre.vb_release.191206-1406"
"CurrentMajorVersionNumber"=dword:0000000a
"CurrentMinorVersionNumber"=dword:00000000
"CurrentVersion"="6.3"
"UBR"=dword:00000ef2
"EditionID"="Professional"
"InstallationType"="Client"
"CompositionVersion"="10.0.19045.3826"
"CSDVersion"=""
"PathName"="C:\\Windows"
"SystemRoot"="C:\\Windows"
"ProgramFilesDir"="C:\\Program Files"
"ProgramFilesDir (x86)"="C:\\Program Files (x86)"
"CommonFilesDir"="C:\\Program Files\\Common Files"
"CommonFilesDir (x86)"="C:\\Program Files (x86)\\Common Files"

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Windows]
"CSDVersion"=dword:00000000

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\ProductOptions]
"ProductType"="WinNT"

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile]
"SystemResponsiveness"=dword:00000000
"NetworkThrottlingIndex"=dword:ffffffff
"NoLazyMode"=dword:00000001
"AlwaysOn"=dword:00000001

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games]
"Affinity"=dword:00000000
"Background Only"="False"
"Clock Rate"=dword:00002710
"GPU Priority"=dword:00000008
"Priority"=dword:00000006
"Scheduling Category"="High"
"SFIO Priority"="High"
"Latency Sensitive"="True"

[HKEY_CURRENT_USER\System\GameConfigStore]
"GameDVR_Enabled"=dword:00000000
"GameDVR_FSEBehaviorMode"=dword:00000002
"GameDVR_HonorUserFSEBehaviorMode"=dword:00000001
"GameDVR_DXGIHonorFSEWindowsCompatible"=dword:00000001
"GameDVR_EFSEFeatureFlags"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\GameDVR]
"AllowGameDVR"=dword:00000000

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management]
"LargeSystemCache"=dword:00000001
"DisablePagingExecutive"=dword:00000001

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\AudioEndpointBuilder]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Audiosrv]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\winebus]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\mountmgr]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\RpcSs]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\PlugPlay]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\CryptSvc]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\NlaSvc]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet]
"EnableActiveProbing"=dword:00000001
"ActiveWebProbeHost"="www.msftncsi.com"
"ActiveWebProbePath"="ncsi.txt"
"ActiveWebProbeContent"="Microsoft NCSI"
"ActiveDnsProbeHost"="dns.msftncsi.com"
"ActiveDnsProbeContent"="131.107.255.255"

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Tcpip]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\BFE]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Dnscache]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\EventLog]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\FontCache]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\LanmanWorkstation]
"Start"=dword:00000002

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\DirectDraw]
"EmulationOnly"=dword:00000000

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Direct3D\Drivers]
"UsePrecompiledShaders"=dword:00000001

[HKEY_CURRENT_USER\Software\Wine\Direct3D]
"VideoMemorySize"="${vram_mb}"
"StrictDrawOrdering"="disabled"
"AlwaysOffscreen"="enabled"
"OffscreenRenderingMode"="fbo"
"Multisampling"="enabled"
"CheckFloatConstants"="disabled"
"CheckDepthStencil"="disabled"
"DirectDrawRenderer"="opengl"
"ShaderBackend"="glsl"
"csmt"=dword:00000001
"MaxVersionGL"=dword:00040006

[HKEY_CURRENT_USER\Software\Wine\X11 Driver]
"UseXVidMode"="N"
"GrabPointer"="Y"
"UseTakeFocus"="N"

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
"d3d11"="native,builtin"
"dxgi"="native,builtin"
"d3d12"="native,builtin"
"d3d12core"="native,builtin"
"d3d10core"="native,builtin"
"d3d9"="native,builtin"
"d3d8"="native,builtin"
"nvapi"="native,builtin"
"nvapi64"="native,builtin"
"d3dcompiler_47"="native,builtin"
"d3dcompiler_46"="native,builtin"
"d3dcompiler_43"="native,builtin"
"d3dx11_43"="native,builtin"
"d3dx10_43"="native,builtin"
"d3dx9_43"="native,builtin"
"vcruntime140"="native,builtin"
"vcruntime140_1"="native,builtin"
"msvcp140"="native,builtin"
"msvcp140_1"="native,builtin"
"msvcp140_2"="native,builtin"
"msvcp140_codecvt_ids"="native,builtin"
"msvcp140_atomic_wait"="native,builtin"
"concrt140"="native,builtin"
"vcomp140"="native,builtin"
"ucrtbase"="native,builtin"
"xinput1_4"="native,builtin"
"xinput1_3"="native,builtin"
"xinput9_1_0"="native,builtin"
"dinput8"="native,builtin"
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
    touch "${WINEPREFIX}/.vessel_win_full_v4" 2>/dev/null || true
}


# 8. Configuración de pantalla completa universal, ratón ultra-fluido, estabilidad 3D y supresión de crash dialogs
optimizar_entorno_windows_completo
if [ ! -f "${WINEPREFIX}/.vessel_reg_v5" ]; then
    reg_base_tmp=$(mktemp "${TMPDIR:-/tmp}/vessel_base_XXXXXX.reg" 2>/dev/null || echo "/tmp/vessel_base_$$.reg")
    cat << 'EOF' > "$reg_base_tmp"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Wine\WineDbg]
"ShowCrashDialog"=dword:00000000

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\AeDebug]
"Auto"="0"

[HKEY_CURRENT_USER\Software\Wine\DirectInput]
"MouseWarpOverride"="enable"

[HKEY_CURRENT_USER\Software\Wine\X11 Driver]
"Decorated"="Y"
"Managed"="Y"

[HKEY_CURRENT_USER\Software\Wine\Direct3D]
"csmt"=dword:00000001
"StrictDrawOrdering"="disabled"
"AlwaysOffscreen"="enabled"
"CheckDepthStencil"="enabled"
EOF
    "$WINE_CMD" regedit /S "$reg_base_tmp" >/dev/null 2>&1 || true
    rm -f "$reg_base_tmp" 2>/dev/null || true
    touch "${WINEPREFIX}/.vessel_reg_v5" 2>/dev/null || true
fi

# 8.0 Gestión inteligente de ventanas y versión de Windows por aplicación en una sola operación (sin múltiples reg.exe)
if [ -n "$TARGET_FILE" ]; then
    need_app_reg=0
    if [ ! -f "${WINEPREFIX}/user.reg" ] || ! grep -Fq "[Software\\\\Wine\\\\AppDefaults\\\\${TARGET_FILE}]" "${WINEPREFIX}/user.reg" 2>/dev/null; then
        need_app_reg=1
    elif [ -n "$GAME_WINVER" ] && ! grep -A 5 -F "[Software\\\\Wine\\\\AppDefaults\\\\${TARGET_FILE}]" "${WINEPREFIX}/user.reg" 2>/dev/null | grep -Fq "\"Version\"=\"${GAME_WINVER}\""; then
        need_app_reg=1
    fi

    if [ "$need_app_reg" -eq 1 ]; then
        reg_app_tmp=$(mktemp "${TMPDIR:-/tmp}/vessel_app_XXXXXX.reg" 2>/dev/null || echo "/tmp/vessel_app_$$.reg")
        {
            echo "Windows Registry Editor Version 5.00"
            echo ""
            if [ -n "$GAME_WINVER" ]; then
                echo "[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\${TARGET_FILE}]"
                echo "\"Version\"=\"${GAME_WINVER}\""
                echo ""
            fi
            echo "[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\${TARGET_FILE}\\X11 Driver]"
            if [ "$IS_PROGRAM" -eq 1 ] || [ "${PE_CATEGORY:-juego}" = "programa" ]; then
                echo "\"Decorated\"=\"Y\""
                echo "\"Managed\"=\"Y\""
                echo "\"GrabFullscreen\"=\"N\""
                echo "\"UseTakeFocus\"=\"Y\""
            else
                echo "\"Decorated\"=\"N\""
                echo "\"GrabFullscreen\"=\"N\""
                echo "\"UseTakeFocus\"=\"N\""
            fi
        } > "$reg_app_tmp"
        "$WINE_CMD" regedit /S "$reg_app_tmp" >/dev/null 2>&1 || true
        rm -f "$reg_app_tmp" 2>/dev/null || true
    fi
fi

# 9. Configuración modular de DXVK y traducción gráfica (Solo para juegos 3D, NUNCA para programas de escritorio ni --wined3d)
if [ "${FORCE_WINED3D:-0}" -eq 1 ]; then
    export RENDERER_IN_USE="WineD3D (OpenGL Compatibilidad)"
    export PROTON_USE_WINED3D=1
    unset DXVK_CONFIG_FILE VKD3D_CONFIG_FILE DXVK_ENABLE_NVAPI DXVK_ASYNC DXVK_HUD DXVK_STATE_CACHE_PATH DXVK_GPLASYNCCACHE
elif [ "$IS_PROGRAM" -ne 1 ] && [ "${PE_CATEGORY:-juego}" != "programa" ] && [ "$RENDERER_IN_USE" != "WineD3D (OpenGL Compatibilidad)" ]; then
    CALIBRATED_DXVK_CONF="${CONFIG_DIR}/dxvk.conf"
    if [ -x "$GENERAR_DXVK" ]; then
        "$GENERAR_DXVK" 2>/dev/null || true
    elif [ -f "$GENERAR_DXVK" ]; then
        bash "$GENERAR_DXVK" 2>/dev/null || true
    fi
    if [ -f "$CALIBRATED_DXVK_CONF" ] && [ -s "$CALIBRATED_DXVK_CONF" ]; then
        export DXVK_CONFIG_FILE="$CALIBRATED_DXVK_CONF"
    elif [ -f "${DIR}/drivers/dxvk/dxvk.conf" ]; then
        export DXVK_CONFIG_FILE="${DIR}/drivers/dxvk/dxvk.conf"
    else
        export DXVK_CONFIG_FILE="$DXVK_CONF"
    fi
    if [ -f "${DIR}/drivers/vkd3d-proton/vkd3d.conf" ]; then
        export VKD3D_CONFIG_FILE="${DIR}/drivers/vkd3d-proton/vkd3d.conf"
    fi

    # Centralizar caché de estados DXVK por juego en ~/.cache/vessel/dxvk/<juego>/
    GAME_CACHE_SLUG=$(basename "${TARGET_FILE%.*}" 2>/dev/null | tr -cd '[:alnum:]_.-' | tr '[:upper:]' '[:lower:]')
    [ -z "$GAME_CACHE_SLUG" ] && GAME_CACHE_SLUG="generico"
    export DXVK_STATE_CACHE_PATH="${HOME}/.cache/vessel/dxvk/${GAME_CACHE_SLUG}"
    mkdir -p "$DXVK_STATE_CACHE_PATH" 2>/dev/null || true

    # Respaldo automático de d3d8to9 para juegos DirectX 8
    if [ "${PE_API:-}" = "d3d8" ] && [ ! -f "${WINEPREFIX}/drive_c/windows/system32/d3d8.dll" ] && [ -f "${DIR}/librerias_cache/d3d8to9/d3d8.dll" ]; then
        cp -p "${DIR}/librerias_cache/d3d8to9/d3d8.dll" "${WINEPREFIX}/drive_c/windows/system32/d3d8.dll" 2>/dev/null || true
    fi
else
    unset DXVK_CONFIG_FILE
    unset VKD3D_CONFIG_FILE
fi

# 9.1 Silenciar completamente la depuración de Wine para mínimo consumo de RAM y CPU (Ahorro: -15 MB)
if [ -z "${WINEDEBUG:-}" ]; then
    export WINEDEBUG="-all"
fi

# 9.2 Detección y activación de puente DXVK-NVAPI para GPUs NVIDIA GeForce (Solo juegos 3D)
NVAPI_ACTIVO="Inactivo"
if [ "$IS_PROGRAM" -ne 1 ] && [ "${PE_CATEGORY:-juego}" != "programa" ]; then
    if [[ "${DETECTED_GPU:-}" =~ [Nn][Vv][Ii][Dd][Ii][Aa] ]] || lspci 2>/dev/null | grep -qi "NVIDIA"; then
        export DXVK_ENABLE_NVAPI=1
        export WINEDLLOVERRIDES="nvapi,nvapi64=n,b;${WINEDLLOVERRIDES:-}"
        NVAPI_ACTIVO="Activo (GeForce Reflex & Low-Latency)"
    fi
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
else
    export WINE_FULLSCREEN_FSR=0
    unset WINE_FULLSCREEN_FSR 2>/dev/null || true
    unset WINE_FULLSCREEN_FSR_MODE 2>/dev/null || true
    unset WINE_FULLSCREEN_FSR_STRENGTH 2>/dev/null || true
fi

# 11. Uso condicional de GameMode según perfil
GAMEMODE=""
if [ "$IS_PROGRAM" -ne 1 ] && [ "$PERFIL_RENDIMIENTO" != "ahorro" ] && command -v gamemoderun &> /dev/null; then
    GAMEMODE="gamemoderun"
fi

# ==============================================================================
# MOTOR TURBO DE ACELERACIÓN DE HARDWARE Y RECURSOS EN VIVO (CPU / GPU / KERNEL)
# ==============================================================================
acelerar_hardware_sistema() {
    [ "$IS_PROGRAM" -eq 1 ] && return 0
    [ "${PE_CATEGORY:-juego}" = "programa" ] && return 0
    [ "$PERFIL_RENDIMIENTO" = "ahorro" ] && return 0

    echo "[⚡] Acelerador Turbo: Maximizando CPU, GPU, prioridad de hilos y memoria..."

    # 1. CPU Power Governor & Frecuencia Máxima (Desbloquea Turbo Boost sin caídas)
    if command -v powerprofilesctl &>/dev/null; then
        PREV_POWER_PROFILE=$(powerprofilesctl get 2>/dev/null || true)
        powerprofilesctl set performance 2>/dev/null || true
    elif command -v cpupower &>/dev/null; then
        cpupower frequency-set -g performance 2>/dev/null || true
    fi
    if [ "$(id -u)" -eq 0 ]; then
        for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            [ -w "$gov" ] && echo performance > "$gov" 2>/dev/null || true
        done
        for epp in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
            [ -w "$epp" ] && echo performance > "$epp" 2>/dev/null || true
        done
    fi

    # 2. Desbloqueo y Persistencia de Relojes de GPU (con timeout para evitar bloqueos en Wayland/Optimus)
    if [ "${HAS_NVIDIA:-false}" = true ] || lspci 2>/dev/null | grep -qi "NVIDIA" || [ -d "/proc/driver/nvidia" ]; then
        # Activar Persistence Mode (elimina la latencia de despertar del chip NVIDIA)
        timeout 2s nvidia-smi -pm 1 >/dev/null 2>&1 || true
        # Forzar estado de máximo rendimiento P0 en PowerMizer (elimina caídas de reloj)
        if command -v nvidia-settings &>/dev/null && [ -n "${DISPLAY:-}" ]; then
            timeout 2s nvidia-settings -a '[gpu:0]/GPUPowerMizerMode=1' >/dev/null 2>&1 || true
        fi
        export __GL_THREADED_OPTIMIZATIONS=1
        export __GL_YIELD="NOTHING"
    elif [ "${HAS_AMD_DEDICATED:-false}" = true ] || lspci 2>/dev/null | grep -qiE "amd|radeon"; then
        if [ "$(id -u)" -eq 0 ]; then
            for dpm in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
                [ -w "$dpm" ] && echo high > "$dpm" 2>/dev/null || true
            done
        fi
        export RADV_PERFTEST="gpl"
    elif [ "${HAS_INTEL:-false}" = true ]; then
        export ANV_ENABLE_PIPELINE_CACHE=1
    fi

    # 3. Optimización de Memoria y Kernel en Caliente (Solo si se ejecuta con permisos de root)
    if [ "$(id -u)" -eq 0 ]; then
        if [ -w /sys/kernel/mm/transparent_hugepage/enabled ]; then
            echo madvise > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
        fi
        if [ -w /proc/sys/kernel/split_lock_mitigate ]; then
            echo 0 > /proc/sys/kernel/split_lock_mitigate 2>/dev/null || true
        fi
        if [ -w /proc/sys/vm/swappiness ]; then
            echo 10 > /proc/sys/vm/swappiness 2>/dev/null || true
        fi
        if [ -w /proc/sys/vm/vfs_cache_pressure ]; then
            echo 50 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null || true
        fi
        if [ -w /proc/sys/vm/max_map_count ]; then
            echo 2147483642 > /proc/sys/vm/max_map_count 2>/dev/null || true
        fi
    fi
    export WINE_THP=1
    export MESA_SHADER_CACHE_MAX_SIZE="4096MB"

    # 4. Descriptores de Archivos y Bloqueo de Memoria en Proceso
    ulimit -n 1048576 2>/dev/null || ulimit -n 524288 2>/dev/null || true
    ulimit -l unlimited 2>/dev/null || true
}

restaurar_hardware_sistema() {
    [ "$IS_PROGRAM" -eq 1 ] && return 0
    [ "${PE_CATEGORY:-juego}" = "programa" ] && return 0

    # 1. Restaurar perfil de energía de CPU
    if [ -n "$PREV_POWER_PROFILE" ] && command -v powerprofilesctl &>/dev/null; then
        powerprofilesctl set "$PREV_POWER_PROFILE" 2>/dev/null || true
    fi

    # 2. Restaurar GPU a modo Adaptativo / Ahorro
    if [ "${HAS_NVIDIA:-false}" = true ] || lspci 2>/dev/null | grep -qi "NVIDIA" || [ -d "/proc/driver/nvidia" ]; then
        if command -v nvidia-settings &>/dev/null && [ -n "${DISPLAY:-}" ]; then
            timeout 2s nvidia-settings -a '[gpu:0]/GPUPowerMizerMode=0' >/dev/null 2>&1 || true
        fi
    elif [ "${HAS_AMD_DEDICATED:-false}" = true ] || lspci 2>/dev/null | grep -qiE "amd|radeon"; then
        for dpm in /sys/class/drm/card*/device/power_dpm_force_performance_level; do
            [ -w "$dpm" ] && echo auto > "$dpm" 2>/dev/null || true
        done
    fi
}

PREV_POWER_PROFILE=""
acelerar_hardware_sistema

# 11. Obtener directorio y nombre del archivo
if [ "${IS_BUILTIN_WIN_TOOL:-0}" -eq 1 ]; then
    TARGET_DIR="${DIR}"
    TARGET_FILE="$target_base_low"
    [[ ! "$TARGET_FILE" =~ \.exe$ ]] && TARGET_FILE="${TARGET_FILE}.exe"
else
    TARGET_DIR="$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd || dirname "$TARGET")"
    TARGET_FILE="$(basename "$TARGET")"
fi

# ==============================================================================
# OPTIMIZACIÓN UNIVERSAL DE RED Y MULTIJUGADOR PARA WINE
# - Permite a todos los programas y juegos conectarse a Internet y servidores online
# - Configura resolución DNS limpia con hostname dinámico dentro del prefijo Wine
# - Configura sondas NCSI en el registro para que Windows detecte 100% de conectividad
# ==============================================================================
optimizar_red_y_wifi() {
    [ -f "${WINEPREFIX}/.vessel_net_ok" ] && return 0
    # 1. Asegurar archivo hosts y resolución de servidores en el prefijo (dinámico por equipo)
    local etc_dir="${WINEPREFIX}/drive_c/windows/system32/drivers/etc"
    mkdir -p "$etc_dir"
    local my_host
    my_host="$(hostname 2>/dev/null || echo "localhost")"
    cat << EOF > "${etc_dir}/hosts"
127.0.0.1 localhost ${my_host}
::1 localhost ip6-localhost ip6-loopback
EOF

    # 4. Asegurar parámetros de red e Internet (NCSI / NLA / DNS) en el registro de Wine (en una sola operación)
    if [ ! -f "${WINEPREFIX}/.vessel_net_ok" ]; then
        reg_net_tmp=$(mktemp "${TMPDIR:-/tmp}/vessel_net_XXXXXX.reg" 2>/dev/null || echo "/tmp/vessel_net_$$.reg")
        cat << 'EOF' > "$reg_net_tmp"
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters]
"NameServer"="1.1.1.1,8.8.8.8"
"DhcpNameServer"="1.1.1.1,8.8.8.8"
"EnableDHCP"=dword:00000001

[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\Default]
"NameServer"="1.1.1.1,8.8.8.8"
"DhcpNameServer"="1.1.1.1,8.8.8.8"
"EnableDHCP"=dword:00000001

[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NlaSvc\Parameters\Internet]
"EnableActiveProbing"=dword:00000001
"ActiveWebProbeHost"="www.msftncsi.com"
"ActiveWebProbeContent"="Microsoft NCSI"
"ActiveDnsProbeHost"="dns.msftncsi.com"
"ActiveDnsProbeContent"="131.107.255.255"

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator]
"NoActiveProbe"=dword:00000000
"DisablePassivePolling"=dword:00000000

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings]
"GlobalUserOffline"=dword:00000000
"ProxyEnable"=dword:00000000
"CertificateRevocation"=dword:00000000
EOF
        "$WINE_CMD" regedit /S "$reg_net_tmp" >/dev/null 2>&1 || true
        rm -f "$reg_net_tmp" 2>/dev/null || true
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
export WINEDLLOVERRIDES="winemenubuilder.exe=d;dinput8=n,b;dxgi=n,b;d3d11=n,b;d3d10core=n,b;d3d9=n,b;d3d8=n,b;ddraw=n,b;d3dcompiler_43=n,b;d3dcompiler_46=n,b;d3dcompiler_47=n,b;dplayx=n,b;dpnet=n,b;dpwsockx=n,b;vorbisfile=n,b;vorbishooked=n,b;dsound=n,b;mfplat=n,b;mf=n,b;mfreadwrite=n,b;evr=n,b;quartz=b,n;devenum=b,n;qedit=b,n;wmasf=n,b;wmvcore=n,b;winegstreamer=b;xaudio2_7=b;xaudio2_8=b;xaudio2_9=b;x3daudio1_7=b;openal32=n,b;dmusic=n,b;dmsynth=n,b;dmime=n,b;dmloader=n,b;dmband=n,b;secur32=b;wininet=b;winhttp=b;ws2_32=b;iphlpapi=b;dnsapi=b;${WINEDLLOVERRIDES}"

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
        reg_gr_tmp=$(mktemp "${TMPDIR:-/tmp}/vessel_gr_XXXXXX.reg" 2>/dev/null || echo "/tmp/vessel_gr_$$.reg")
        cat << 'EOF' > "$reg_gr_tmp"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe]
"Version"="win7"

[HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\Direct3D]
"renderer"="gdi"
"MaxVersionGL"=dword:00000000

[HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides]
"dnsapi"=""
"iphlpapi"=""
"ws2_32"=""
"wininet"=""
"secur32"=""
"dxgi"="builtin"
"d3d11"="builtin"
"d3d9"="builtin"
"d3d10core"="builtin"
"mfc42"="native,builtin"
"mfc42u"="native,builtin"

[HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\X11 Driver]
"Decorated"="Y"
"Managed"="Y"
"GrabFullscreen"="N"
"Desktop"=-

[HKEY_CURRENT_USER\Software\Wine\DllOverrides]
"dinput8"="native,builtin"
"d3d9"="native,builtin"
"d3d8"="native,builtin"
"dxgi"="native,builtin"
"d3d11"="native,builtin"
"vorbisfile"="native,builtin"
"vorbishooked"="native,builtin"
"dsound"="native,builtin"

[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings]
"CertificateRevocation"=dword:00000000
"WarnonBadCertRecving"=dword:00000000
"SecureProtocols"=dword:00000aa0
EOF
        "$WINE_CMD" regedit /S "$reg_gr_tmp" >/dev/null 2>&1 || true
        rm -f "$reg_gr_tmp" 2>/dev/null || true
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

    # Desactivar DXVK/VKD3D/NVAPI y offload NVIDIA forzado en programas de escritorio
    # para evitar pantalla negra o cierres en apps 2D, Electron, .NET WPF, Qt e instaladores
    export RENDERER_IN_USE="GDI / WineD3D Nativo (Escritorio)"
    unset DXVK_CONFIG_FILE VKD3D_CONFIG_FILE DXVK_ENABLE_NVAPI DXVK_ASYNC DXVK_HUD DXVK_STATE_CACHE_PATH DXVK_GPLASYNCCACHE DXVK_D3D9 DXVK_D3D11 DXVK
    unset __NV_PRIME_RENDER_OFFLOAD __GLX_VENDOR_LIBRARY_NAME __VK_LAYER_NV_optimus
    export WINEDLLOVERRIDES="winemenubuilder.exe=d;dxgi=b;d3d11=b;d3d10core=b;d3d9=b;d3d8=b;ddraw=b;nvapi=d;nvapi64=d;riched20=n,b;riched32=n,b;msxml3=n,b;msxml6=n,b;gdiplus=n,b;mscoree=n,b;mshtml=n,b;secur32=b;wininet=b;winhttp=b;ws2_32=b;iphlpapi=b;dnsapi=b;"

    # Compatibilidad automática con aplicaciones Electron / Chromium en Wine
    export ELECTRON_DISABLE_SANDBOX=1
    if [ "${PE_IS_ELECTRON:-0}" = "1" ]; then
        if [[ ! " $* " =~ " --no-sandbox " ]]; then
            EXTRA_APP_ARGS="${EXTRA_APP_ARGS} --no-sandbox"
        fi
        if [[ ! " $* " =~ " --disable-gpu " ]]; then
            EXTRA_APP_ARGS="${EXTRA_APP_ARGS} --disable-gpu"
        fi
    fi

    # Aplicar ClearType HD y overrides de productividad en UNA sola operación cacheada (0.01s en arranques posteriores)
    if [ ! -f "${WINEPREFIX}/.vessel_prog_reg_v1" ]; then
        reg_prog_tmp=$(mktemp "${TMPDIR:-/tmp}/vessel_prog_XXXXXX.reg" 2>/dev/null || echo "/tmp/vessel_prog_$$.reg")
        cat << 'EOF' > "$reg_prog_tmp"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Control Panel\Desktop]
"FontSmoothing"="2"
"FontSmoothingType"=dword:00000002
"FontSmoothingGamma"=dword:00000578
"FontSmoothingOrientation"=dword:00000001

[HKEY_CURRENT_USER\Software\Wine\DllOverrides]
"riched20"="native,builtin"
"riched32"="native,builtin"
"msxml3"="native,builtin"
"msxml6"="native,builtin"
"gdiplus"="native,builtin"
"mscoree"="native,builtin"
"mshtml"="native,builtin"
EOF
        "$WINE_CMD" regedit /S "$reg_prog_tmp" >/dev/null 2>&1 || true
        rm -f "$reg_prog_tmp" 2>/dev/null || true
        touch "${WINEPREFIX}/.vessel_prog_reg_v1" 2>/dev/null || true
    fi
fi

# Si se solicitó --wined3d explícitamente para un juego 3D, forzar DLLs builtin de Wine (OpenGL)
if [ "${FORCE_WINED3D:-0}" -eq 1 ] && [ "$IS_PROGRAM" -ne 1 ] && [ "${PE_CATEGORY:-juego}" != "programa" ]; then
    export RENDERER_IN_USE="WineD3D (OpenGL Compatibilidad)"
    export PROTON_USE_WINED3D=1
    unset DXVK_CONFIG_FILE VKD3D_CONFIG_FILE DXVK_ENABLE_NVAPI DXVK_ASYNC DXVK_HUD DXVK_STATE_CACHE_PATH DXVK_GPLASYNCCACHE
    export WINEDLLOVERRIDES="winemenubuilder.exe=d;dxgi=b;d3d11=b;d3d10core=b;d3d9=b;d3d8=b;ddraw=b;nvapi=d;nvapi64=d;${WINEDLLOVERRIDES}"
fi

# Moverse al directorio donde reside el juego (vital para rutas relativas y DLLs)
[ -d "$TARGET_DIR" ] && cd "$TARGET_DIR" || cd "$DIR"

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

    # Fallback Wayland nativo: kscreen-doctor (KDE Wayland) o wlr-randr (Sway / Hyprland / wlroots)
    if [ -z "$ACTIVE_MON_W" ]; then
        if command -v kscreen-doctor &>/dev/null; then
            local ks_out
            ks_out=$(kscreen-doctor -o 2>/dev/null || true)
            if [ -n "$ks_out" ]; then
                while IFS= read -r kline; do
                    if [[ "$kline" =~ Geometry:\ *([0-9]+),([0-9]+)\ +([0-9]+)x([0-9]+) ]]; then
                        ACTIVE_MON_X="${BASH_REMATCH[1]}"
                        ACTIVE_MON_Y="${BASH_REMATCH[2]}"
                        ACTIVE_MON_W="${BASH_REMATCH[3]}"
                        ACTIVE_MON_H="${BASH_REMATCH[4]}"
                        break
                    fi
                done <<< "$ks_out"
            fi
        elif command -v wlr-randr &>/dev/null; then
            local wlr_out
            wlr_out=$(wlr-randr 2>/dev/null || true)
            if [[ "$wlr_out" =~ ([0-9]+)x([0-9]+)\ px,\ [0-9.]+Hz\ \(current\)\ at\ ([0-9]+),([0-9]+) ]]; then
                ACTIVE_MON_W="${BASH_REMATCH[1]}"
                ACTIVE_MON_H="${BASH_REMATCH[2]}"
                ACTIVE_MON_X="${BASH_REMATCH[3]}"
                ACTIVE_MON_Y="${BASH_REMATCH[4]}"
            elif [[ "$wlr_out" =~ Position:\ ([0-9]+),([0-9]+).*Current\ mode:\ ([0-9]+)x([0-9]+) ]]; then
                ACTIVE_MON_X="${BASH_REMATCH[1]}"
                ACTIVE_MON_Y="${BASH_REMATCH[2]}"
                ACTIVE_MON_W="${BASH_REMATCH[3]}"
                ACTIVE_MON_H="${BASH_REMATCH[4]}"
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
    if [ -n "${FORCE_RESOLUTION:-}" ] && [ "${FORCE_RESOLUTION}" != "auto" ]; then
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

    local perfil_script="${CORE_DIR}/perfiles/${perfil_id}.sh"
    [ ! -f "$perfil_script" ] && perfil_script="${DIR}/core/perfiles/${perfil_id}.sh"

    if [ -f "$perfil_script" ]; then
        source "$perfil_script"
    else
        local perfil_gen="${CORE_DIR}/perfiles/generico.sh"
        [ ! -f "$perfil_gen" ] && perfil_gen="${DIR}/core/perfiles/generico.sh"
        if [ -f "$perfil_gen" ]; then
            source "$perfil_gen"
        else
            if [ "$IS_PROGRAM" -eq 1 ] || [ "${PE_CATEGORY:-juego}" = "programa" ]; then
                echo "[+] Perfil Activo: Programa de Escritorio / Utilidad Windows [Aislado]"
                export WINE_FULLSCREEN_FSR=0
                ACTIVAR_FSR_FINAL=0
            else
                echo "[+] Perfil Activo: Aplicación Genérica [Aislado]"
            fi
        fi
    fi
}
aplicar_perfil_aislado_juego

# ==============================================================================
# AUTO-ACTIVACIÓN DINÁMICA DE MODS, ASI LOADERS, ENB, RESHADE Y TRADUCCIONES
# Detecta automáticamente librerías DLL de mods y plugins ASI locales
# y activa el override nativo (n,b) en Wine para que carguen de forma transparente.
# Filtra estrictamente librerías de sistema, runtime CRT y forwarders api-ms-win.
# ==============================================================================
DLL_EXCLUIDAS_CORE="^(ntdll|kernel32|kernelbase|user32|gdi32|gdiplus|advapi32|rpcrt4|ws2_32|wsock32|iphlpapi|shell32|shlwapi|shcore|ole32|oleaut32|combase|comctl32|comdlg32|imm32|crypt32|cryptbase|secur32|bcrypt|ncrypt|sspicli|wldp|uxtheme|dwmapi|setupapi|cfgmgr32|winhttp|wininet|urlmon|mpr|netapi32|dnsapi|normaliz|imagehlp|dbghelp|psapi|api-ms-win-.*|ext-ms-win-.*|ucrtbase|vcruntime.*|msvcp.*|msvcr.*|concrt.*|vcomp.*|msvcrt|dxgi|d3d11|d3d12|d3d10.*|d3d9|d3d8|ddraw|vulkan-1|winevulkan|opengl32|glu32|winegstreamer|xaudio2_.*|x3daudio.*|orig_socialclub|launc)$"
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
    echo "[+] Ejecutando Programa de Windows [Modo Ventana Nativa - ClearType HD] (Vessel v1.3)..."
    echo "    - CPU: ${CPU_MODEL} (${CPU_CORES} Hilos)"
    echo "    - GPU: ${DETECTED_GPU}"
    echo "    - Versión de Vessel: v1.3 (Producción)"
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
    echo "[+] Ejecutando con Perfil [${perf_label}] (Vessel v1.3)..."
    echo "    - CPU: ${CPU_MODEL} (${CPU_CORES} Hilos)"
    echo "    - GPU: ${DETECTED_GPU}"
    echo "    - Versión de Vessel: v1.3 (Producción)"
    echo "    - Renderizador: ${RENDERER_IN_USE:-DXVK (Vulkan)}"
    echo "    - Consumo RAM / CPU: Ultra-Liviano (WINEDEBUG silenciado, Pipelines dinámicos)"
    echo "    - Fidelidad 3D & Shaders: Filtrado Anisotrópico 16x | D3D8to9 Vulkan | NVAPI: ${NVAPI_ACTIVO}"
    echo "    - Fsync/Esync: $([ "$WINEFSYNC" = "1" ] && echo "Fsync Activo" || echo "Esync Activo")"
    echo "    - Límite de FPS: ${LIMITE_FPS:-Ilimitado (Máximo FPS)}"
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

# Optimización profunda de RAM y kernel (solo con privilegios de root para no retrasar lanzamientos normales)
if [ "$(id -u)" -eq 0 ]; then
    RAM_AVAIL_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}' || echo 8192)
    if [ -n "$RAM_AVAIL_MB" ] && [ "$RAM_AVAIL_MB" -lt 3500 ]; then
        sync 2>/dev/null || true
        [ -w /proc/sys/vm/drop_caches ] && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
        [ -w /proc/sys/vm/compact_memory ] && echo 1 > /proc/sys/vm/compact_memory 2>/dev/null || true
    fi
fi

# Desactivar 'set -e' antes de la ejecución para garantizar que salidas con código != 0 no interrumpan la limpieza
set +e

# Limpiar instancias colgadas previas del ejecutable objetivo para evitar bloqueos por mutex único de Windows
if [ -n "$TARGET_FILE" ] && [[ ! "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]] && [ "${IS_BUILTIN_WIN_TOOL:-0}" -eq 0 ]; then
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

# 2. GameMode o Elevación Nativa de Prioridad en Tiempo Real (nice / ionice)
if [ -n "$GAMEMODE" ] && command -v "$GAMEMODE" &>/dev/null && [[ ! "$TARGET_FILE" =~ \.([rR][eE][gG]|[vV][bB][sS]|[jJ][sS])$ ]]; then
    FINAL_CMD+=("$GAMEMODE")
elif [ "$IS_PROGRAM" -ne 1 ] && [[ ! "$TARGET_FILE" =~ \.([rR][eE][gG]|[vV][bB][sS]|[jJ][sS])$ ]]; then
    # Solo agregar 'nice' si el usuario actual tiene permisos efectivos para bajar el valor nice (sin arrojar "Permiso denegado")
    if command -v nice &>/dev/null; then
        nice_test=$(nice -n -10 true 2>&1 || true)
        if [ -z "$nice_test" ]; then
            FINAL_CMD=("nice" "-n" "-10" "${FINAL_CMD[@]}")
        else
            nice_test=$(nice -n -5 true 2>&1 || true)
            if [ -z "$nice_test" ]; then
                FINAL_CMD=("nice" "-n" "-5" "${FINAL_CMD[@]}")
            fi
        fi
    fi
    if command -v ionice &>/dev/null; then
        ionice_test=$(ionice -c 2 -n 0 true 2>&1 || true)
        if [ -z "$ionice_test" ]; then
            FINAL_CMD=("ionice" "-c" "2" "-n" "0" "${FINAL_CMD[@]}")
        fi
    fi
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
elif [[ "$TARGET_FILE" =~ ^[Ee][Xx][Pp][Ll][Oo][Rr][Ee][Rr](\.[Ee][Xx][Ee])?$ ]]; then
    if [ $# -eq 0 ]; then
        FINAL_CMD+=("explorer.exe" "/e,c:\\")
    else
        FINAL_CMD+=("explorer.exe" "$@")
    fi
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

# 7. Ejecución con captura en tiempo real (aislada de procesos daemon de Wine para evitar bloqueos)
export VESSEL_SESSION_ID="vessel_$$_$(date +%s)"
EXEC_START_TIME=$(date +%s)
if [ "${USE_NATIVE_WEB_APP:-0}" -eq 1 ] && [ -n "$FOUND_HTML" ] && [ -f "$FOUND_HTML" ] && [ -n "$NATIVE_WEB_BROWSER" ]; then
    echo -e "\n[+] Interfaz Web Detectada: Ejecutando en Modo Aplicación de Escritorio Nativa..."
    echo "    - Archivo UI: $(basename "$FOUND_HTML")"
    echo "    - Motor Gráfico: $NATIVE_WEB_BROWSER (Hardware Acceleration)"
    echo "    - Consumo de Recursos: Mínimo (~25 MB RAM, 0% CPU en reposo)"
    echo "    - Rendimiento: 60 FPS Nativo (Sin sobrecarga de Wine)"
    echo ""
    BEFORE_WIDS=""
    if command -v wmctrl &>/dev/null; then
        BEFORE_WIDS=$(wmctrl -l 2>/dev/null | awk '{print $1}')
    fi
    "$NATIVE_WEB_BROWSER" "--app=file://${FOUND_HTML}" "$@" >/dev/null 2>&1 &
    APP_PID=$!
    if command -v wmctrl &>/dev/null; then
        TARGET_WID=""
        for _ in {1..25}; do
            sleep 0.2
            TARGET_WID=$(wmctrl -l 2>/dev/null | awk '{print $1}' | grep -vFf <(echo "$BEFORE_WIDS") | tail -n 1 || true)
            [ -n "$TARGET_WID" ] && break
        done
        if [ -z "$TARGET_WID" ]; then
            app_base_name=$(basename "$TARGET_FILE" .exe)
            html_title=$(grep -ioP '(?<=<title>)(.*?)(?=</title>)' "$FOUND_HTML" 2>/dev/null | head -n 1 || true)
            search_regex="${app_base_name//_/ }"
            [ -n "$html_title" ] && search_regex="${search_regex}|${html_title}"
            TARGET_WID=$(wmctrl -l 2>/dev/null | grep -iE "$search_regex" | awk '{print $1}' | tail -n 1 || true)
        fi
        if [ -n "$TARGET_WID" ]; then
            while wmctrl -l 2>/dev/null | grep -qE "^${TARGET_WID}\b"; do
                sleep 0.5
            done
        else
            wait "$APP_PID" 2>/dev/null || true
        fi
    else
        wait "$APP_PID" 2>/dev/null || true
    fi
    EXIT_STATUS=0
    EXEC_DURATION=$(( $(date +%s) - EXEC_START_TIME ))
else
    "${FINAL_CMD[@]}" > "$TEMP_GAME_LOG" 2>&1 &
    APP_PID=$!
    TAIL_PID=""
    if [ -t 1 ]; then
        tail -f --pid="$APP_PID" -n +1 "$TEMP_GAME_LOG" 2>/dev/null &
        TAIL_PID=$!
    fi
    wait "$APP_PID" 2>/dev/null || true
    EXIT_STATUS=$?
    [ -n "$TAIL_PID" ] && kill "$TAIL_PID" 2>/dev/null || true
    EXEC_DURATION=$(( $(date +%s) - EXEC_START_TIME ))
fi

# Sincronización activa de subprocesos de Windows:
# Si un juego o instalador/portable lanzó procesos secundarios (ej. PlayGTAV, DriverBoosterPortable),
# mantenemos la sesión activa mientras existan subprocesos de ESTA sesión (VESSEL_SESSION_ID).
if [ "${USE_NATIVE_WEB_APP:-0}" -ne 1 ] && [ -n "$WINEPREFIX" ] && [ -d "$WINEPREFIX" ]; then
    is_prog_mode=0
    if [ "$IS_PROGRAM" -eq 1 ] || [ "${PE_CATEGORY:-juego}" = "programa" ]; then
        is_prog_mode=1
    fi
    target_base=$(basename "$TARGET_FILE" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    target_dir_base=$(basename "$TARGET_DIR" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    while true; do
        has_active_game=false
        for pid_env in /proc/[0-9]*/environ; do
            [ -r "$pid_env" ] || continue
            c_pid="${pid_env#/proc/}"
            c_pid="${c_pid%/environ}"
            [ "$c_pid" -eq "$$" ] 2>/dev/null && continue
            [ "$c_pid" -eq "$PPID" ] 2>/dev/null && continue

            matched_session=0
            if grep -qF "VESSEL_SESSION_ID=${VESSEL_SESSION_ID}" "$pid_env" 2>/dev/null; then
                matched_session=1
            elif [ "$is_prog_mode" -eq 0 ] && grep -qF "WINEPREFIX=${WINEPREFIX}" "$pid_env" 2>/dev/null; then
                matched_session=2
            fi
            [ "$matched_session" -eq 0 ] && continue

            cmdline=$(cat "/proc/${c_pid}/cmdline" 2>/dev/null | tr '\0' ' ' || true)
            cmdline_lower=$(echo "$cmdline" | tr '[:upper:]' '[:lower:]')

            if echo "$cmdline_lower" | grep -qiE '\.exe' && \
               ! echo "$cmdline_lower" | grep -qiE 'services\.exe|winedevice\.exe|plugplay\.exe|explorer\.exe|rpcss\.exe|conhost\.exe|svchost\.exe|wineboot\.exe'; then
                if [ "$matched_session" -eq 1 ] || [ -z "$target_base" ] || echo "$cmdline_lower" | grep -qF "$target_base" || echo "$cmdline_lower" | grep -qF "$target_dir_base"; then
                    has_active_game=true
                    if [ "$is_prog_mode" -eq 0 ]; then
                        renice -n -10 -p "$c_pid" >/dev/null 2>&1 || renice -n -5 -p "$c_pid" >/dev/null 2>&1 || true
                        ionice -c 2 -n 0 -p "$c_pid" >/dev/null 2>&1 || true
                    fi
                    break
                fi
            fi
        done
        [ "$has_active_game" = false ] && break
        sleep 1
    done
fi

# Restaurar estado del hardware y perfiles de energía al finalizar el juego
restaurar_hardware_sistema

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
    # Si se detectó un fallo gráfico Vulkan/DXGI, purgar caché de shaders del juego para el próximo arranque
    if [ -n "${DXVK_STATE_CACHE_PATH:-}" ] && [ -d "${DXVK_STATE_CACHE_PATH}" ] && [ -s "$TEMP_GAME_LOG" ] && \
       grep -qiE 'VK_ERROR_DEVICE_LOST|DXGI_ERROR_DEVICE_RESET|vkCreateGraphicsPipelines|vkCreateDevice|VK_ERROR_' "$TEMP_GAME_LOG" 2>/dev/null; then
        echo -e "${YELLOW}[!] Fallo gráfico Vulkan/DXGI detectado: purgando caché de shaders en ${DXVK_STATE_CACHE_PATH}...${RESET}"
        rm -rf "${DXVK_STATE_CACHE_PATH:?}"/* 2>/dev/null || true
    fi
    mkdir -p "${DIR}/logs_errores"
    log_ts=$(date '+%Y%m%d_%H%M%S')
    log_app_name=$(basename "$TARGET_FILE" 2>/dev/null | tr -cd '[:alnum:]_.-' || echo "juego")
    ERROR_REPORT_FILE="${DIR}/logs_errores/error_${log_app_name}_${log_ts}.log"
    ULTIMO_ERROR_FILE="${DIR}/logs_errores/ultimo_error.log"

    {
        echo "================================================================================"
        echo "VESSEL v1.3 - INFORME DETALLADO DE ERROR / CIERRE INESPERADO"
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

# Esperar sincronización limpia de los subprocesos de Wine sin matarlos abruptamente (solo en juegos y con timeout)
if [ "$IS_PROGRAM" -ne 1 ] && [ "${PE_CATEGORY:-juego}" != "programa" ]; then
# Si no queda ningún otro .exe de usuario activo en este WINEPREFIX, apagar wineserver y servicios residuales para liberar RAM/CPU
if [ "${USE_NATIVE_WEB_APP:-0}" -ne 1 ] && [ -n "${WINEPREFIX:-}" ] && [ -d "${WINEPREFIX:-}" ]; then
    other_app_running=0
    for pid_env in /proc/[0-9]*/environ; do
        [ -r "$pid_env" ] || continue
        if grep -qF "WINEPREFIX=${WINEPREFIX}" "$pid_env" 2>/dev/null; then
            c_pid="${pid_env#/proc/}"
            c_pid="${c_pid%/environ}"
            [ "$c_pid" -eq "$$" ] 2>/dev/null && continue
            cmdline_low=$(tr '\0' ' ' < "/proc/${c_pid}/cmdline" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
            if echo "$cmdline_low" | grep -qiE '\.exe' && ! echo "$cmdline_low" | grep -qiE 'services\.exe|winedevice\.exe|plugplay\.exe|explorer\.exe|rpcss\.exe|conhost\.exe|svchost\.exe|wineboot\.exe'; then
                other_app_running=1
                break
            fi
        fi
    done
    if [ "$other_app_running" -eq 0 ]; then
        WINEPREFIX="$WINEPREFIX" "$WINESERVER_CMD" -k >/dev/null 2>&1 || WINEPREFIX="$WINEPREFIX" wineserver -k >/dev/null 2>&1 || true
    fi
fi
fi
exit $EXIT_STATUS
