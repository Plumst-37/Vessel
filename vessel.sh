#!/usr/bin/env bash
# ==============================================================================
# VESSEL - CLI Y LANZADOR UNIVERSAL DE JUEGOS Y SOFTWARE (WINDOWS & LINUX)
# Compatible con GNU GPL-3.0 - Detección Automática de APIs, DXVK y Runtimes
# Permite ejecutar: vessel run programa.exe (o vessel run app.AppImage / script.sh)
# ==============================================================================

# Resolver enlace simbólico real para garantizar la ruta base de Vessel
SOURCE="${BASH_SOURCE[0]:-$0}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="${DIR}/${SOURCE}"
done
DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

# Colores y estilo de terminal
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
RED='\033[1;31m'
BOLD='\033[1m'
RESET='\033[0m'

# Directorios y rutas clave
CORE_DIR="${DIR}/core"
[ ! -d "$CORE_DIR" ] && CORE_DIR="${DIR}"

DATOS_DIR="${DIR}/datos"
[ ! -d "$DATOS_DIR" ] && DATOS_DIR="${DIR}"

DB_FILE="${DATOS_DIR}/programas.db"
[ ! -f "$DB_FILE" ] && DB_FILE="${DIR}/programas.db"

LAUNCHER="${CORE_DIR}/launch-win-app.sh"
[ ! -f "$LAUNCHER" ] && LAUNCHER="${DIR}/launch-win-app.sh"

GESTOR_DRIVERS="${CORE_DIR}/gestor_drivers.sh"
[ ! -f "$GESTOR_DRIVERS" ] && GESTOR_DRIVERS="${DIR}/gestor_drivers.sh"

# ==============================================================================
# 1. AYUDA Y VERSIÓN
# ==============================================================================
cmd_version() {
    echo -e "${CYAN}${BOLD}Vessel v1.3${RESET} - Universal Windows & Linux Gaming Runtime"
    echo -e "Licencia GNU General Public License v3.0 (GNU GPL-3.0)"
    echo -e "Desarrollado para máxima compatibilidad y rendimiento en cualquier PC.\n"
}

cmd_help() {
    echo -e "${CYAN}${BOLD}VESSEL CLI${RESET} - Lanzador Universal de Juegos y Software (Windows & Linux)"
    echo -e "\n${BOLD}USO:${RESET}"
    echo -e "  vessel run [opciones] <programa|juego|id> [argumentos...]"
    echo -e "  vessel [comando]\n"

    echo -e "${BOLD}COMANDOS DISPONIBLES:${RESET}"
    echo -e "  ${GREEN}run <archivo|nombre|id>${RESET}   Ejecuta cualquier juego o software (DXVK/VKD3D al vuelo)"
    echo -e "  ${GREEN}list, ls${RESET}                  Lista los juegos y programas registrados en la biblioteca"
    echo -e "  ${GREEN}add <ruta> [nombre]${RESET}       Registra un nuevo ejecutable en la biblioteca de Vessel"
    echo -e "  ${GREEN}status, drivers${RESET}           Muestra el estado de la GPU, monitor y librerías gráficas"
    echo -e "  ${GREEN}kill, stop${RESET}                Detiene de forma limpia todos los procesos de Wine activos"
    echo -e "  ${GREEN}config${RESET}                    Abre el archivo de configuración central de drivers"
    echo -e "  ${GREEN}--version, -v${RESET}             Muestra la versión oficial de Vessel"
    echo -e "  ${GREEN}--help, -h${RESET}                Muestra este manual de ayuda\n"

    echo -e "${BOLD}OPCIONES PARA 'vessel run':${RESET}"
    echo -e "  ${YELLOW}--winver <win10|win7|winxp>${RESET}  Fuerza una versión específica de Windows"
    echo -e "  ${YELLOW}--prefix <ruta>${RESET}              Utiliza un prefijo de Wine personalizado"
    echo -e "  ${YELLOW}--isolated${RESET}                   Ejecuta en un prefijo temporal aislado (sandbox limpio)"
    echo -e "  ${YELLOW}--fsr <quality|performance>${RESET}  Activa escalado FidelityFX Super Resolution (FSR)"
    echo -e "  ${YELLOW}--program${RESET}                    Modo software/ofimática en lugar de perfil de juego"
    echo -e "  ${YELLOW}--native${RESET}                     Fuerza la ejecución como binario o script de Linux\n"

    echo -e "${BOLD}EJEMPLOS DE USO:${RESET}"
    echo -e "  $ ${CYAN}vessel run GTA5.exe${RESET}"
    echo -e "  $ ${CYAN}vessel run /media/juegos/Cyberpunk2077/Cyberpunk2077.exe -novid${RESET}"
    echo -e "  $ ${CYAN}vessel run \"GTA San Andres\"${RESET}"
    echo -e "  $ ${CYAN}vessel run 2${RESET}                     (Ejecuta el juego con ID #2 de tu lista)"
    echo -e "  $ ${CYAN}vessel run juego_linux.AppImage${RESET}"
    echo -e "  $ ${CYAN}vessel run script_lanzador.sh${RESET}"
    echo -e "  $ ${CYAN}vessel list${RESET}"
    echo -e "  $ ${CYAN}vessel add ~/Descargas/Setup.exe \"Mi Programa\"${RESET}"
    echo -e "  $ ${CYAN}vessel status${RESET}\n"
}

# ==============================================================================
# 2. LISTAR JUEGOS Y PROGRAMAS (vessel list / vessel ls)
# ==============================================================================
cmd_list() {
    echo -e "\n${PURPLE}${BOLD}========================================================================${RESET}"
    echo -e "${CYAN}${BOLD}   VESSEL - BIBLIOTECA DE JUEGOS Y PROGRAMAS REGISTRADOS${RESET}"
    echo -e "${PURPLE}${BOLD}========================================================================${RESET}\n"

    if [ ! -f "$DB_FILE" ] || [ ! -s "$DB_FILE" ]; then
        echo -e "${YELLOW}  No hay programas o juegos registrados todavía.${RESET}"
        echo -e "  💡 Registra uno fácilmente con: ${CYAN}vessel add /ruta/al/juego.exe \"Nombre\"${RESET}\n"
        return 0
    fi

    printf "${BOLD}%-4s | %-24s | %-8s | %-7s | %s${RESET}\n" "ID" "NOMBRE" "TIPO" "WINVER" "RUTA"
    echo "-----+--------------------------+----------+---------+----------------------------------"

    local idx=1
    while IFS='|' read -r nombre ruta prefijo winver fsr cat; do
        [ -z "$nombre" ] && continue
        local tipo="Juego"
        [ "$cat" = "programa" ] && tipo="Programa"
        local display_ruta="$ruta"
        [ ${#display_ruta} -gt 45 ] && display_ruta="...${display_ruta: -42}"
        printf "%-4d | %-24s | %-8s | %-7s | %s\n" "$idx" "${nombre:0:24}" "$tipo" "${winver:-win10}" "$display_ruta"
        idx=$((idx + 1))
    done < "$DB_FILE"

    echo -e "\n${BOLD}💡 Ejecutar cualquiera de ellos:${RESET} ${CYAN}vessel run <ID>${RESET}  o  ${CYAN}vessel run \"<Nombre>\"${RESET}\n"
}

# ==============================================================================
# 3. AÑADIR PROGRAMA A LA BIBLIOTECA (vessel add)
# ==============================================================================
cmd_add() {
    local ruta="${1:-}"
    local custom_name="${2:-}"

    if [ -z "$ruta" ]; then
        echo -e "${RED}[!] Error: Especifica la ruta del archivo a registrar.${RESET}"
        echo -e "${YELLOW}Uso:${RESET} vessel add /ruta/al/ejecutable.exe [Nombre Opcional]"
        exit 1
    fi

    if [ ! -f "$ruta" ]; then
        echo -e "${RED}[!] Error: El archivo no existe: '${ruta}'${RESET}"
        exit 1
    fi

    local abs_path
    abs_path=$(realpath "$ruta" 2>/dev/null || echo "$ruta")
    local base_file
    base_file=$(basename "$abs_path")
    local nombre="${custom_name:-${base_file%.*}}"

    # Determinar categoría automáticamente
    local cat="juego"
    local ftype
    ftype=$(file -b "$abs_path" 2>/dev/null || echo "")
    if [[ "$base_file" =~ (setup|install|installer|office|word|excel|notepad|editor|player) ]] || [ "$ftype" = "directory" ]; then
        cat="programa"
    fi

    # Verificar si ya existe en la base de datos
    mkdir -p "$(dirname "$DB_FILE")" 2>/dev/null || true
    if [ -f "$DB_FILE" ] && grep -Fq "$abs_path" "$DB_FILE"; then
        echo -e "${YELLOW}[!] El ejecutable ya está registrado en Vessel:${RESET} ${nombre}"
        return 0
    fi

    echo "${nombre}|${abs_path}|compartido|win10|off|${cat}" >> "$DB_FILE"
    echo -e "${GREEN}[✓] Registrado exitosamente en la biblioteca:${RESET} ${BOLD}${nombre}${RESET}"
    echo -e "  • Ubicación: ${abs_path}"
    echo -e "  • Categoría: ${cat}"
    echo -e "  💡 Inícialo cuando quieras con: ${CYAN}vessel run \"${nombre}\"${RESET} o ${CYAN}vessel run ${base_file}${RESET}\n"
}

# ==============================================================================
# 4. DETENER PROCESOS DE WINE (vessel kill / vessel stop)
# ==============================================================================
cmd_kill() {
    echo -e "\n${YELLOW}🛑 [ VESSEL ] Deteniendo todos los procesos de Wine y juegos activos...${RESET}"
    local prefix="${DIR}/wineprefix"
    if [ -d "$prefix" ] && command -v wineserver >/dev/null 2>&1; then
        WINEPREFIX="$prefix" wineserver -k 2>/dev/null || true
    fi
    if command -v wineserver >/dev/null 2>&1; then
        wineserver -k 2>/dev/null || true
    fi
    killall -9 wine wine64 wineserver 2>/dev/null || true
    echo -e "${GREEN}✓ Todos los procesos han sido finalizados y el entorno está restaurado.${RESET}\n"
}

# ==============================================================================
# 5. ESTADO DE CONTROLADORES Y CONFIGURACIÓN (vessel status / vessel config)
# ==============================================================================
cmd_status() {
    if [ -f "$GESTOR_DRIVERS" ]; then
        bash "$GESTOR_DRIVERS" estado
    else
        echo -e "${RED}[!] Error: No se encontró el gestor de drivers en: ${GESTOR_DRIVERS}${RESET}"
        exit 1
    fi
}

cmd_config() {
    local cfg_file="${DIR}/drivers/gpu_env.conf"
    if [ ! -f "$cfg_file" ]; then
        cfg_file="${DIR}/config/config_rendimiento.cfg"
    fi

    if [ -f "$cfg_file" ]; then
        local editor="${EDITOR:-}"
        [ -z "$editor" ] && command -v nano >/dev/null 2>&1 && editor="nano"
        [ -z "$editor" ] && command -v xdg-open >/dev/null 2>&1 && editor="xdg-open"
        [ -z "$editor" ] && editor="cat"

        echo -e "${CYAN}Abriendo configuración en: ${cfg_file}...${RESET}"
        "$editor" "$cfg_file"
    else
        echo -e "${RED}[!] Archivo de configuración no encontrado.${RESET}"
    fi
}

# ==============================================================================
# 6. MOTOR DE EJECUCIÓN 'vessel run' (WINDOWS & LINUX NATIVO)
# ==============================================================================
cmd_run() {
    # Si el primer argumento es literalmente "run", descartarlo
    if [ "$1" = "run" ]; then
        shift
    fi

    if [ $# -eq 0 ]; then
        echo -e "${RED}[!] Error: No especificaste ningún programa o juego para ejecutar.${RESET}\n"
        echo -e "${BOLD}Uso:${RESET} vessel run [opciones] <programa.exe|app|id> [argumentos...]"
        echo -e "Ejemplos:"
        echo -e "  ${CYAN}vessel run GTA5.exe${RESET}"
        echo -e "  ${CYAN}vessel run /ruta/al/juego.exe${RESET}"
        echo -e "  ${CYAN}vessel run \"GTA San Andres\"${RESET}"
        echo -e "  ${CYAN}vessel run 2${RESET}"
        echo -e "  ${CYAN}vessel run script.sh${RESET}"
        echo -e "  ${CYAN}vessel run aplicacion.AppImage${RESET}\n"
        exit 1
    fi

    local pass_flags=()
    local force_native=0
    local target_raw=""

    # Procesar opciones específicas de vessel run
    while [ $# -gt 0 ]; do
        case "$1" in
            --prefix|--runner|--winver|--fsr)
                pass_flags+=("$1" "$2")
                shift 2
                ;;
            --isolated|--program)
                pass_flags+=("$1")
                shift
                ;;
            --native)
                force_native=1
                shift
                ;;
            --)
                shift
                target_raw="$1"
                shift || true
                break
                ;;
            -*)
                # Guardar banderas para pasar al ejecutable o lanzador
                pass_flags+=("$1")
                shift
                ;;
            *)
                target_raw="$1"
                shift
                break
                ;;
        esac
    done

    local app_args=("$@")

    if [ -z "$target_raw" ]; then
        echo -e "${RED}[!] No se especificó ningún archivo o programa objetivo.${RESET}"
        exit 1
    fi

    local target_resolved=""
    local db_matched_name=""

    # 1. ¿Existe el archivo directamente en la ruta proporcionada o directorio actual?
    if [ -f "$target_raw" ] || [ -d "$target_raw" ]; then
        target_resolved=$(realpath "$target_raw" 2>/dev/null || echo "$target_raw")
    fi

    # 2. Si no es una ruta directa, ¿es un número de ID de la base de datos (ej. 'vessel run 2')?
    if [ -z "$target_resolved" ] && [[ "$target_raw" =~ ^[0-9]+$ ]] && [ -f "$DB_FILE" ]; then
        local id_num="$target_raw"
        local line_match
        line_match=$(sed -n "${id_num}p" "$DB_FILE" 2>/dev/null || true)
        if [ -n "$line_match" ]; then
            db_matched_name=$(echo "$line_match" | cut -d'|' -f1)
            target_resolved=$(echo "$line_match" | cut -d'|' -f2)
            local db_winver
            db_winver=$(echo "$line_match" | cut -d'|' -f4)
            local db_fsr
            db_fsr=$(echo "$line_match" | cut -d'|' -f5)
            local db_cat
            db_cat=$(echo "$line_match" | cut -d'|' -f6)

            [ -n "$db_winver" ] && [ "$db_winver" != "default" ] && pass_flags+=("--winver" "$db_winver")
            [ -n "$db_fsr" ] && [ "$db_fsr" != "off" ] && pass_flags+=("--fsr" "$db_fsr")
            [ "$db_cat" = "programa" ] && pass_flags+=("--program")
        fi
    fi

    # 3. Si no es ID, ¿coincide con el nombre o ejecutable de algún juego en la base de datos?
    if [ -z "$target_resolved" ] && [ -f "$DB_FILE" ]; then
        while IFS='|' read -r nombre ruta prefijo winver fsr cat; do
            [ -z "$nombre" ] && continue
            local base_db
            base_db=$(basename "$ruta")
            if [ "${target_raw,,}" = "${nombre,,}" ] || [ "${target_raw,,}" = "${base_db,,}" ]; then
                db_matched_name="$nombre"
                target_resolved="$ruta"
                [ -n "$winver" ] && [ "$winver" != "default" ] && pass_flags+=("--winver" "$winver")
                [ -n "$fsr" ] && [ "$fsr" != "off" ] && pass_flags+=("--fsr" "$fsr")
                [ "$cat" = "programa" ] && pass_flags+=("--program")
                break
            fi
        done < "$DB_FILE"
    fi

    # 4. Búsqueda instantánea en los directorios de juegos ya registrados en Vessel
    if [ -z "$target_resolved" ] && [ -f "$DB_FILE" ]; then
        while IFS='|' read -r _ db_path _ _ _ _; do
            [ -z "$db_path" ] && continue
            local parent_dir
            parent_dir=$(dirname "$db_path")
            if [ -d "$parent_dir" ] && [ -f "${parent_dir}/${target_raw}" ]; then
                target_resolved="${parent_dir}/${target_raw}"
                break
            fi
            local grand_dir
            grand_dir=$(dirname "$parent_dir")
            if [ -d "$grand_dir" ] && [ -f "${grand_dir}/${target_raw}" ]; then
                target_resolved="${grand_dir}/${target_raw}"
                break
            fi
        done < "$DB_FILE"
    fi

    # 5. Tratamiento especial para GameRanger
    if [ -z "$target_resolved" ] && [[ "$target_raw" =~ [Gg]ame[Rr]anger ]]; then
        target_resolved="GameRanger.exe"
    fi

    # 6. Si aún no se encuentra y es un nombre con extensión (.exe, .sh), buscar en carpetas habituales
    if [ -z "$target_resolved" ] && [[ "$target_raw" =~ \.[a-zA-Z0-9]+$ ]]; then
        for search_dir in "$HOME/Documentos/Juegos" "$HOME/Juegos" "$HOME/Games" "/media/${USER}" "/mnt"; do
            if [ -d "$search_dir" ]; then
                local quick_found
                quick_found=$(find "$search_dir" -maxdepth 6 -iname "$target_raw" 2>/dev/null | head -n 1)
                if [ -n "$quick_found" ] && [ -f "$quick_found" ]; then
                    target_resolved="$quick_found"
                    break
                fi
            fi
        done
    fi

    # Si definitivamente no existe
    if [ -z "$target_resolved" ] || ([ ! -f "$target_resolved" ] && [ "$target_resolved" != "GameRanger.exe" ]); then
        echo -e "${RED}${BOLD}[!] Error: No se encontró el archivo o programa:${RESET} '${target_raw}'"
        echo -e "${YELLOW}\nSugerencias de resolución:${RESET}"
        echo -e "  1. Verifica que la ruta o el nombre del archivo esté bien escrito."
        echo -e "  2. Si estás en la carpeta del juego, usa: ${CYAN}vessel run ./$(basename "$target_raw")${RESET}"
        echo -e "  3. Consulta tu biblioteca de juegos registrados con: ${CYAN}vessel list${RESET}"
        echo -e "  4. Registra tu juego con: ${CYAN}vessel add /ruta/al/juego.exe \"Nombre\"${RESET}\n"
        exit 1
    fi

    # ==========================================================================
    # DETECCIÓN DE FORMATO: WINDOWS (DXVK / WINE) vs LINUX NATIVO
    # ==========================================================================
    local is_windows=0
    local is_linux=0

    case "${target_resolved,,}" in
        *.exe|*.msi|*.bat|*.cmd|*.lnk)
            is_windows=1
            ;;
        *.appimage|*.sh|*.bin|*.run|*.desktop)
            is_linux=1
            ;;
    esac

    if [ "$is_windows" -eq 0 ] && [ "$is_linux" -eq 0 ]; then
        local ftype
        ftype=$(file -b "$target_resolved" 2>/dev/null || echo "")
        if echo "$ftype" | grep -qiE "PE32|PE32\+|MS Windows|MS-DOS"; then
            is_windows=1
        elif echo "$ftype" | grep -qiE "ELF|executable|script"; then
            is_linux=1
        else
            is_windows=1
        fi
    fi

    [ "$force_native" -eq 1 ] && { is_linux=1; is_windows=0; }

    # ==========================================================================
    # CASO A: EJECUCIÓN DE APLICACIÓN O JUEGO DE WINDOWS (.exe, .bat, etc.)
    # ==========================================================================
    if [ "$is_windows" -eq 1 ]; then
        local display_title="${db_matched_name:-$(basename "$target_resolved")}"
        echo -e "${CYAN}${BOLD}⚡ [ VESSEL CLI ]${RESET} Iniciando con optimizaciones automáticas de hardware..."
        echo -e "${BLUE}  • Aplicación:${RESET} ${BOLD}${display_title}${RESET}"
        echo -e "${BLUE}  • Ubicación: ${RESET} ${target_resolved}"
        echo -e "${GREEN}  ✓ Resolviendo DXVK, VKD3D-Proton, Topología de CPU y Drivers al vuelo...${RESET}\n"

        if [ ! -f "$LAUNCHER" ]; then
            echo -e "${RED}[!] Error fatal: No se encuentra el lanzador central: ${LAUNCHER}${RESET}"
            exit 1
        fi

        exec bash "$LAUNCHER" "${pass_flags[@]}" "$target_resolved" "${app_args[@]}"
    fi

    # ==========================================================================
    # CASO B: EJECUCIÓN DE APLICACIÓN O JUEGO NATIVO DE LINUX (.AppImage, .sh, ELF)
    # ==========================================================================
    if [ "$is_linux" -eq 1 ]; then
        echo -e "${CYAN}${BOLD}⚡ [ VESSEL CLI ]${RESET} Ejecutando aplicación nativa de Linux..."
        echo -e "${BLUE}  • Aplicación:${RESET} ${BOLD}$(basename "$target_resolved")${RESET}"
        echo -e "${BLUE}  • Ubicación: ${RESET} ${target_resolved}"

        # Otorgar permisos de ejecución automáticos si faltaban
        if [ ! -x "$target_resolved" ] && [ -f "$target_resolved" ]; then
            chmod +x "$target_resolved" 2>/dev/null || true
        fi

        # Cargar entorno de GPU para aceleración dedicada en híbridas
        if [ -f "${DIR}/drivers/gpu_env.conf" ]; then
            source "${DIR}/drivers/gpu_env.conf"
            if [ "${GPU_FORCE_DEDICATED:-auto}" != "0" ]; then
                if lspci 2>/dev/null | grep -qi "nvidia" || [ -d "/proc/driver/nvidia" ]; then
                    export __NV_PRIME_RENDER_OFFLOAD=1
                    export __GLX_VENDOR_LIBRARY_NAME=nvidia
                    export __VK_LAYER_NV_optimus=NVIDIA_only
                elif lspci 2>/dev/null | grep -qiE "amd|radeon"; then
                    export DRI_PRIME=1
                fi
            fi
        fi

        # Preparar envoltorio GameMode si está disponible en el sistema
        local linux_runner=()
        if command -v gamemoderun >/dev/null 2>&1; then
            linux_runner+=("gamemoderun")
            echo -e "${GREEN}  ✓ GameMode activado (Máxima prioridad de CPU/GPU en Linux)${RESET}\n"
        else
            echo -e "${GREEN}  ✓ Entorno optimizado para Linux nativo${RESET}\n"
        fi

        local target_workdir
        target_workdir=$(dirname "$target_resolved")
        cd "$target_workdir" || true

        # Si es un archivo .desktop de Linux
        if [[ "${target_resolved,,}" == *.desktop ]]; then
            if command -v gtk-launch >/dev/null 2>&1; then
                exec gtk-launch "$(basename "$target_resolved" .desktop)"
            elif command -v dex >/dev/null 2>&1; then
                exec dex "$target_resolved"
            else
                local exec_line
                exec_line=$(grep -E "^Exec=" "$target_resolved" | head -n 1 | cut -d= -f2- | sed -E 's/%[uUfFdi]//g')
                exec bash -c "$exec_line"
            fi
        else
            exec "${linux_runner[@]}" "$target_resolved" "${app_args[@]}"
        fi
    fi
}

# ==============================================================================
# 7. DISPATCHER PRINCIPAL DE COMANDOS
# ==============================================================================

# Si se ejecutó 'vessel' sin ningún argumento:
if [ $# -eq 0 ]; then
    # Terminal interactiva TTY: Abrir menú TUI de Vessel
    if [ -t 0 ] && [ -t 1 ]; then
        exec bash "${DIR}/menu-win.sh" "$@"
    fi

    # Entorno gráfico sin TTY (doble clic en escritorio o menú del sistema):
    for term in konsole gnome-terminal ptyxis xfce4-terminal mate-terminal tilix alacritty kitty foot qterminal terminator x-terminal-emulator xterm; do
        if command -v "$term" &>/dev/null; then
            case "$term" in
                konsole)
                    exec konsole --workdir "$DIR" -e bash "${DIR}/menu-win.sh" "$@"
                    ;;
                gnome-terminal|tilix|ptyxis)
                    exec "$term" --working-directory="$DIR" -- bash "${DIR}/menu-win.sh" "$@"
                    ;;
                xfce4-terminal|mate-terminal)
                    exec "$term" --working-directory="$DIR" -e "bash \"${DIR}/menu-win.sh\" $*"
                    ;;
                alacritty)
                    exec alacritty --working-directory "$DIR" -e bash "${DIR}/menu-win.sh" "$@"
                    ;;
                kitty)
                    exec kitty --directory "$DIR" bash "${DIR}/menu-win.sh" "$@"
                    ;;
                foot)
                    exec foot -D "$DIR" bash "${DIR}/menu-win.sh" "$@"
                    ;;
                qterminal)
                    exec qterminal -d "$DIR" -e bash "${DIR}/menu-win.sh" "$@"
                    ;;
                terminator)
                    exec terminator --working-directory="$DIR" -e "bash \"${DIR}/menu-win.sh\" $*"
                    ;;
                *)
                    exec "$term" -e bash "${DIR}/menu-win.sh" "$@"
                    ;;
            esac
        fi
    done

    # Fallback si no hay terminal gráfica instalada
    msg="Vessel requiere una ventana de terminal para mostrar su menú interactivo.\nPuedes abrir tu terminal habitual y escribir:\n  vessel run juego.exe  o  vessel"
    if command -v zenity &>/dev/null; then
        zenity --warning --title="Vessel" --text="$msg" --width=450 2>/dev/null || true
        exit 1
    elif command -v notify-send &>/dev/null; then
        notify-send -u critical "Vessel" "Abre una terminal y ejecuta: vessel" 2>/dev/null || true
        exit 1
    fi

    exec bash "${DIR}/menu-win.sh" "$@"
fi

# Subcomandos específicos
case "$1" in
    run)
        cmd_run "$@"
        ;;
    list|ls)
        cmd_list
        ;;
    add)
        shift
        cmd_add "$@"
        ;;
    status|drivers|info)
        cmd_status
        ;;
    kill|stop)
        cmd_kill
        ;;
    config)
        cmd_config
        ;;
    version|--version|-v)
        cmd_version
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        # Si el argumento parece un archivo o ejecutable existente, o termina con extensión ejecutable,
        # o coincide con un elemento en la base de datos de juegos, ejecutarlo directamente con 'run'
        if [ -f "$1" ] || [[ "$1" =~ \.(exe|msi|bat|cmd|lnk|appimage|sh|bin|run|desktop)$ ]] || grep -qiE "^[^|]*$1[^|]*\|" "$DB_FILE" 2>/dev/null; then
            cmd_run "$@"
        else
            echo -e "${RED}${BOLD}[!] Comando o archivo no reconocido:${RESET} '${1}'\n"
            cmd_help
            exit 1
        fi
        ;;
esac
