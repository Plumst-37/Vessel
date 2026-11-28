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

# Auto-registro en ~/.local/bin/vessel para acceso directo permanente desde cualquier terminal
if [ ! -L "$HOME/.local/bin/vessel" ] && [ ! -f "$HOME/.local/bin/vessel" ]; then
    mkdir -p "$HOME/.local/bin" 2>/dev/null || true
    ln -sf "${DIR}/vessel.sh" "$HOME/.local/bin/vessel" 2>/dev/null || true
fi

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
    echo -e "  ${GREEN}install <setup.exe|msi>${RESET}   Instala software en modo Windows 10 limpio y lo registra"
    echo -e "  ${GREEN}doctor, check${RESET}             Diagnóstico rápido de salud del sistema, Wine, GPU y audio"
    echo -e "  ${GREEN}runner, runners${RESET}           Gestiona y descarga runners portables (Kron4ek, Wine-GE)"
    echo -e "  ${GREEN}list, ls${RESET}                  Lista los juegos y programas registrados en la biblioteca"
    echo -e "  ${GREEN}add <ruta> [nombre]${RESET}       Registra un nuevo ejecutable en la biblioteca de Vessel"
    echo -e "  ${GREEN}status, drivers${RESET}           Muestra el estado de la GPU, monitor y librerías gráficas"
    echo -e "  ${GREEN}clean-cache${RESET}               Limpia la caché centralizada de shaders DXVK/Vulkan"
    echo -e "  ${GREEN}update${RESET}                    Actualiza Vessel (GitHub) y paquetes del sistema (apt)"
    echo -e "  ${GREEN}kill, stop${RESET}                Detiene de forma limpia todos los procesos de Wine activos"
    echo -e "  ${GREEN}config${RESET}                    Abre el archivo de configuración central de drivers"
    echo -e "  ${GREEN}--version, -v${RESET}             Muestra la versión oficial de Vessel"
    echo -e "  ${GREEN}--help, -h${RESET}                Muestra este manual de ayuda\n"

    echo -e "${BOLD}OPCIONES PARA 'vessel run':${RESET}"
    echo -e "  ${YELLOW}--winver <win10|win7|winxp>${RESET}  Fuerza una versión específica de Windows"
    echo -e "  ${YELLOW}--prefix <ruta>${RESET}              Utiliza un prefijo de Wine personalizado"
    echo -e "  ${YELLOW}--isolated${RESET}                   Ejecuta en un prefijo temporal aislado (sandbox limpio)"
    echo -e "  ${YELLOW}--fsr <quality|performance>${RESET}  Activa escalado FidelityFX Super Resolution (FSR)"
    echo -e "  ${YELLOW}--wined3d${RESET}                    Usa OpenGL nativo de Wine en lugar de DXVK (Vulkan)"
    echo -e "  ${YELLOW}--program${RESET}                    Modo software/ofimática en lugar de perfil de juego"
    echo -e "  ${YELLOW}--native${RESET}                     Fuerza la ejecución como binario o script de Linux\n"

    echo -e "${BOLD}EJEMPLOS DE USO:${RESET}"
    echo -e "  $ ${CYAN}vessel run GTA5.exe${RESET}"
    echo -e "  $ ${CYAN}vessel run /media/juegos/Cyberpunk2077/Cyberpunk2077.exe -novid${RESET}"
    echo -e "  $ ${CYAN}vessel run \"GTA San Andres\"${RESET}"
    echo -e "  $ ${CYAN}vessel run 2${RESET}                     (Ejecuta el juego con ID #2 de tu lista)"
    echo -e "  $ ${CYAN}vessel install ~/Descargas/Setup.exe \"Mi Software\"${RESET}"
    echo -e "  $ ${CYAN}vessel doctor${RESET}"
    echo -e "  $ ${CYAN}vessel list${RESET}"
    echo -e "  $ ${CYAN}vessel add ~/Descargas/Programa.exe \"Mi Programa\"${RESET}"
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

    # Determinar categoría y versión de Windows con analizador_pe.py
    local cat="juego"
    local winver="win10"
    if [ -f "${CORE_DIR}/analizador_pe.py" ]; then
        local pe_eval
        pe_eval=$(python3 "${CORE_DIR}/analizador_pe.py" --bash "$abs_path" 2>/dev/null || true)
        if [ -n "$pe_eval" ]; then
            eval "$pe_eval"
            [ -n "${PE_CATEGORY:-}" ] && cat="$PE_CATEGORY"
            [ -n "${PE_WINVER:-}" ] && winver="$PE_WINVER"
        fi
    else
        local ftype
        ftype=$(file -b "$abs_path" 2>/dev/null || echo "")
        if [[ "$base_file" =~ (setup|install|installer|office|word|excel|notepad|editor|player) ]] || [ "$ftype" = "directory" ]; then
            cat="programa"
        fi
    fi

    # Verificar si ya existe en la base de datos
    mkdir -p "$(dirname "$DB_FILE")" 2>/dev/null || true
    if [ -f "$DB_FILE" ] && grep -Fq "$abs_path" "$DB_FILE"; then
        echo -e "${YELLOW}[!] El ejecutable ya está registrado en Vessel:${RESET} ${nombre}"
        return 0
    fi

    echo "${nombre}|${abs_path}|compartido|${winver}|off|${cat}" >> "$DB_FILE"
    echo -e "${GREEN}[✓] Registrado exitosamente en la biblioteca:${RESET} ${BOLD}${nombre}${RESET}"
    echo -e "  • Ubicación: ${abs_path}"
    echo -e "  • Categoría: ${cat}"
    echo -e "  💡 Inícialo cuando quieras con: ${CYAN}vessel run \"${nombre}\"${RESET} o ${CYAN}vessel run ${base_file}${RESET}\n"
}

# ==============================================================================
# 3.1 INSTALADOR INTELIGENTE DE WINDOWS (vessel install)
# ==============================================================================
cmd_install() {
    local installer_raw="${1:-}"
    local custom_name="${2:-}"

    if [ -z "$installer_raw" ]; then
        echo -e "${RED}[!] Error: Especifica el instalador (.exe o .msi) a ejecutar.${RESET}\n"
        echo -e "${BOLD}Uso:${RESET} vessel install <setup.exe|installer.msi> [Nombre]"
        echo -e "Ejemplos:"
        echo -e "  ${CYAN}vessel install ~/Descargas/Setup.exe \"Mi Software\"${RESET}"
        echo -e "  ${CYAN}vessel install /ruta/al/instalador.msi${RESET}\n"
        exit 1
    fi

    if [ ! -f "$installer_raw" ]; then
        echo -e "${RED}[!] Error: El archivo no existe: '${installer_raw}'${RESET}"
        exit 1
    fi

    local abs_installer
    abs_installer=$(realpath "$installer_raw" 2>/dev/null || echo "$installer_raw")
    local base_installer
    base_installer=$(basename "$abs_installer")

    local default_name="${custom_name:-${base_installer%.*}}"
    if [ -z "$custom_name" ]; then
        default_name=$(echo "$default_name" | sed -E 's/([-_]?[sS]etup|[-_]?[iI]nstall(er)?|[-_]?[xX]86|[-_]?[xX]64)//g')
        [ -z "$default_name" ] && default_name="${base_installer%.*}"
    fi

    echo -e "\n${PURPLE}${BOLD}========================================================================${RESET}"
    echo -e "${CYAN}${BOLD}   VESSEL - MODO INSTALADOR INTELIGENTE DE WINDOWS${RESET}"
    echo -e "${PURPLE}${BOLD}========================================================================${RESET}\n"
    echo -e "${BLUE}  • Instalador:${RESET} ${BOLD}${base_installer}${RESET}"
    echo -e "${BLUE}  • Ubicación: ${RESET} ${abs_installer}"
    echo -e "${GREEN}  ✓ Configurando entorno limpio de Windows 10 para instaladores...${RESET}\n"

    local prefix="${DIR}/wineprefix"
    if [ ! -d "$prefix" ] && [ -d "${HOME}/Vessel/wineprefix" ]; then
        prefix="${HOME}/Vessel/wineprefix"
    fi
    local drive_c="${prefix}/drive_c"

    local marker_file="/tmp/.vessel_install_marker_$$"
    touch "$marker_file"

    if [ -f "$LAUNCHER" ]; then
        bash "$LAUNCHER" --winver win10 --program "$abs_installer"
    else
        echo -e "${RED}[!] No se encontró el lanzador central: ${LAUNCHER}${RESET}"
        rm -f "$marker_file"
        exit 1
    fi

    echo -e "\n${CYAN}⚡ [ VESSEL ] Proceso de instalación concluido. Buscando software instalado...${RESET}"

    local candidates=()
    if [ -d "$drive_c" ]; then
        while IFS= read -r found_exe; do
            [ -z "$found_exe" ] && continue
            local exe_lower
            exe_lower=$(basename "$found_exe" | tr '[:upper:]' '[:lower:]')
            if [[ "$exe_lower" =~ (unins|uninstall|update|updater|helper|crashpad|crash_reporter|vc_redist|dxsetup|setup|install) ]]; then
                continue
            fi
            candidates+=("$found_exe")
        done < <(find "$drive_c/Program Files" "$drive_c/Program Files (x86)" "$drive_c/users" -type f -name "*.exe" -newer "$marker_file" 2>/dev/null || true)
    fi

    rm -f "$marker_file"

    local num_candidates=${#candidates[@]}
    if [ "$num_candidates" -eq 0 ]; then
        echo -e "${YELLOW}[i] No se detectaron nuevos ejecutables registrados en Program Files.${RESET}"
        echo -e "    Si la aplicación es portable o se instaló en otra ruta, regístrala con:"
        echo -e "    ${CYAN}vessel add /ruta/al/ejecutable.exe \"${default_name}\"${RESET}\n"
        return 0
    fi

    echo -e "${GREEN}✓ Se detectó el software recién instalado:${RESET}"
    local chosen_exe=""
    if [ "$num_candidates" -eq 1 ]; then
        chosen_exe="${candidates[0]}"
        echo -e "  • Ejecutable principal: ${BOLD}${chosen_exe}${RESET}\n"
    else
        echo -e "  Se encontraron varios ejecutables:"
        local i=1
        for cand in "${candidates[@]}"; do
            echo -e "    [$i] $(basename "$cand") (${cand})"
            i=$((i + 1))
        done
        if [ -t 0 ]; then
            echo -ne "\n${BOLD}Selecciona el número del ejecutable principal (1-${num_candidates}) [1]: ${RESET}"
            read -r sel
            sel="${sel:-1}"
            if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "$num_candidates" ]; then
                chosen_exe="${candidates[$((sel - 1))]}"
            else
                chosen_exe="${candidates[0]}"
            fi
        else
            chosen_exe="${candidates[0]}"
        fi
    fi

    if [ -n "$chosen_exe" ]; then
        cmd_add "$chosen_exe" "$default_name"
    fi
}

# ==============================================================================
# 3.2 DIAGNÓSTICO RÁPIDO DEL SISTEMA (vessel doctor)
# ==============================================================================
cmd_doctor() {
    echo -e "\n${PURPLE}${BOLD}========================================================================${RESET}"
    echo -e "${CYAN}${BOLD}   VESSEL DOCTOR - DIAGNÓSTICO RÁPIDO DEL SISTEMA${RESET}"
    echo -e "${PURPLE}${BOLD}========================================================================${RESET}\n"

    local total_errors=0
    local total_warns=0

    # 1. Verificación de Wine
    echo -e "${BOLD}[1/5] Entorno de Compatibilidad Wine / WoW64:${RESET}"
    local wine_bin
    wine_bin=$(command -v wine 2>/dev/null || true)
    if [ -n "$wine_bin" ]; then
        local wine_ver
        wine_ver=$(wine --version 2>/dev/null || echo "Desconocida")
        echo -e "  ${GREEN}[✓]${RESET} Binario Wine encontrado: ${CYAN}${wine_bin}${RESET}"
        echo -e "  ${GREEN}[✓]${RESET} Versión de Wine: ${BOLD}${wine_ver}${RESET}"

        if [ -f "/usr/lib/i386-linux-gnu/wine/wine" ] || [ -f "/usr/lib32/wine/wine" ] || dpkg --print-foreign-architectures 2>/dev/null | grep -q "i386"; then
            echo -e "  ${GREEN}[✓]${RESET} Arquitectura 32-bit (WoW64): Disponible (Juegos de 32 y 64 bits soportados)"
        elif echo "$wine_ver" | grep -qE "wine-([9|10])"; then
            echo -e "  ${GREEN}[✓]${RESET} Arquitectura WoW64 moderna (Wine 9/10 integrada activa)"
        else
            echo -e "  ${YELLOW}[!]${RESET} Soporte de 32-bit: Podría requerir 'sudo dpkg --add-architecture i386'"
            total_warns=$((total_warns + 1))
        fi
        if command -v wineserver &>/dev/null; then
            if pgrep -x wineserver >/dev/null 2>&1; then
                echo -e "  ${GREEN}[✓]${RESET} Demonio wineserver: Disponible y activo"
            else
                echo -e "  ${GREEN}[✓]${RESET} Demonio wineserver: Disponible (en reposo)"
            fi
        else
            echo -e "  ${YELLOW}[!]${RESET} wineserver no encontrado en PATH"
            total_warns=$((total_warns + 1))
        fi
    else
        echo -e "  ${RED}[✗]${RESET} Wine no está instalado o no se encuentra en el PATH."
        total_errors=$((total_errors + 1))
    fi

    # 2. Controladores Gráficos y Vulkan
    echo -e "\n${BOLD}[2/5] Gráficos y Capas Vulkan:${RESET}"
    local gpus
    gpus=$(lspci 2>/dev/null | grep -E "VGA compatible controller|3D controller" | cut -d: -f3- | sed "s/^[ \t]*//" || true)
    if [ -n "$gpus" ]; then
        while IFS= read -r gpu_line; do
            echo -e "  ${GREEN}[✓]${RESET} GPU Detectada: ${BOLD}${gpu_line}${RESET}"
        done <<< "$gpus"
    else
        echo -e "  ${YELLOW}[!]${RESET} No se pudieron enumerar adaptadores gráficos mediante lspci."
    fi

    local icd_dir="/usr/share/vulkan/icd.d"
    local icd_files
    icd_files=$(ls "$icd_dir" 2>/dev/null | grep "\.json$" | tr '\n' ' ' || true)
    if [ -n "$icd_files" ]; then
        echo -e "  ${GREEN}[✓]${RESET} Manifiestos Vulkan ICD activos: ${CYAN}${icd_files}${RESET}"
    else
        echo -e "  ${YELLOW}[!]${RESET} No se encontraron archivos ICD en ${icd_dir} (Instala 'libvulkan1' y drivers)"
        total_warns=$((total_warns + 1))
    fi

    # 3. Librerías de Traducción Vessel (DXVK / VKD3D / NVAPI / ICU)
    echo -e "\n${BOLD}[3/5] Librerías de Traducción y Runtime de Vessel:${RESET}"
    local drivers_dir="${DIR}/drivers"
    if [ ! -d "$drivers_dir" ] && [ -d "${HOME}/Vessel/drivers" ]; then
        drivers_dir="${HOME}/Vessel/drivers"
    fi

    local dxvk_ok=0
    local vkd3d_ok=0
    local nvapi_ok=0
    [ -f "${drivers_dir}/x64/d3d11.dll" ] || [ -f "${drivers_dir}/dxvk/x64/d3d11.dll" ] && dxvk_ok=1
    [ -f "${drivers_dir}/x64/d3d12.dll" ] || [ -f "${drivers_dir}/vkd3d/x64/d3d12.dll" ] || [ -f "${drivers_dir}/vkd3d-proton/x64/d3d12.dll" ] && vkd3d_ok=1
    [ -f "${drivers_dir}/x64/nvapi64.dll" ] || [ -f "${drivers_dir}/nvapi/x64/nvapi64.dll" ] || [ -f "${drivers_dir}/dxvk-nvapi/x64/nvapi64.dll" ] && nvapi_ok=1

    if [ "$dxvk_ok" -eq 1 ]; then
        echo -e "  ${GREEN}[✓]${RESET} DXVK (DirectX 9/10/11 -> Vulkan): Listo"
    else
        echo -e "  ${YELLOW}[!]${RESET} DXVK no encontrado en drivers/ (Se instalará automáticamente al primer run)"
    fi

    if [ "$vkd3d_ok" -eq 1 ]; then
        echo -e "  ${GREEN}[✓]${RESET} VKD3D-Proton (DirectX 12 -> Vulkan): Listo"
    else
        echo -e "  ${YELLOW}[!]${RESET} VKD3D-Proton no encontrado en drivers/ (Se instalará automáticamente al primer run)"
    fi

    if [ "$nvapi_ok" -eq 1 ]; then
        echo -e "  ${GREEN}[✓]${RESET} DXVK-NVAPI (NVIDIA Reflex / DLSS Bridge): Listo"
    else
        echo -e "  ${YELLOW}[!]${RESET} DXVK-NVAPI no encontrado en drivers/ (Opcional)"
    fi

    local icu_dll="${DIR}/wineprefix/drive_c/windows/system32/icuuc.dll"
    if [ ! -f "$icu_dll" ] && [ -d "${HOME}/Vessel/wineprefix/drive_c/windows/system32" ]; then
        icu_dll="${HOME}/Vessel/wineprefix/drive_c/windows/system32/icuuc.dll"
    fi
    if [ -f "$icu_dll" ]; then
        echo -e "  ${GREEN}[✓]${RESET} Runtime Windows 10 ICU (Qt6/Electron/PySide6): Instalado y Listo"
    else
        echo -e "  ${YELLOW}[!]${RESET} Runtime Windows 10 ICU: No detectado en el prefijo principal"
    fi

    # 4. Servidor de Audio
    echo -e "\n${BOLD}[4/5] Servidor de Audio:${RESET}"
    if pgrep -x pipewire >/dev/null 2>&1; then
        echo -e "  ${GREEN}[✓]${RESET} Servidor de Sonido: PipeWire activo (Baja latencia profesional)"
    elif pgrep -x pulseaudio >/dev/null 2>&1; then
        echo -e "  ${GREEN}[✓]${RESET} Servidor de Sonido: PulseAudio activo"
    elif [ -d "/proc/asound" ]; then
        echo -e "  ${GREEN}[✓]${RESET} Servidor de Sonido: ALSA directo"
    else
        echo -e "  ${YELLOW}[!]${RESET} No se detectó un servidor de audio activo."
        total_warns=$((total_warns + 1))
    fi

    # 5. Caché Centralizada y Espacio en Disco
    echo -e "\n${BOLD}[5/5] Caché y Almacenamiento:${RESET}"
    local shader_cache="$HOME/.cache/vessel/shaders"
    if mkdir -p "$shader_cache" 2>/dev/null && [ -w "$shader_cache" ]; then
        echo -e "  ${GREEN}[✓]${RESET} Caché Centralizada de Shaders: ${CYAN}${shader_cache}${RESET} (Operativa)"
    else
        echo -e "  ${RED}[✗]${RESET} No se puede escribir en: ${shader_cache}"
        total_errors=$((total_errors + 1))
    fi

    local free_space
    free_space=$(df -h "$HOME" 2>/dev/null | awk 'NR==2 {print $4}' || echo "N/A")
    if [ -w "$HOME" ]; then
        echo -e "  ${GREEN}[✓]${RESET} Permisos en \$HOME y Espacio Libre: ${BOLD}${free_space}${RESET} (Lectura/Escritura OK)"
    else
        echo -e "  ${RED}[✗]${RESET} Sin permisos de escritura en \$HOME (${HOME})"
        total_errors=$((total_errors + 1))
    fi

    # Resumen Final
    echo -e "\n${PURPLE}------------------------------------------------------------------------${RESET}"
    if [ "$total_errors" -eq 0 ] && [ "$total_warns" -eq 0 ]; then
        echo -e "${GREEN}${BOLD}✓ DIAGNÓSTICO EXITOSO: Tu sistema está al 100% calibrado para Vessel.${RESET}"
    elif [ "$total_errors" -eq 0 ]; then
        echo -e "${GREEN}${BOLD}✓ DIAGNÓSTICO COMPLETADO: Tu sistema es compatible con Vessel.${RESET} (${YELLOW}${total_warns} advertencias leves${RESET})"
    else
        echo -e "${RED}${BOLD}[!] DIAGNÓSTICO: Se detectaron ${total_errors} inconvenientes críticos.${RESET}"
    fi
    echo -e "${PURPLE}------------------------------------------------------------------------${RESET}\n"
}

# ==============================================================================
# GESTIÓN DE RUNNERS DE WINE (vessel runner / vessel runners)
# ==============================================================================
cmd_runner() {
    local runners_script="${CORE_DIR}/gestor_runners.sh"
    [ ! -f "$runners_script" ] && runners_script="${DIR}/core/gestor_runners.sh"
    bash "$runners_script" "$@"
}

cmd_clean_cache() {
    local dxvk_cache="$HOME/.cache/vessel/dxvk"
    local shader_cache="$HOME/.cache/vessel/shaders"
    echo -e "\n${CYAN}${BOLD}Limpiando caché centralizada de shaders DXVK/Vulkan...${RESET}"
    rm -rf "$dxvk_cache"/* "$shader_cache"/* 2>/dev/null || true
    mkdir -p "$dxvk_cache" "$shader_cache" 2>/dev/null || true
    echo -e "${GREEN}[✓] Caché de shaders limpiada correctamente (${dxvk_cache}).${RESET}\n"
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
            --isolated|--program|--wined3d)
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
            local db_backend
            db_backend=$(echo "$line_match" | cut -d'|' -f7)

            [ -n "$db_winver" ] && [ "$db_winver" != "default" ] && pass_flags+=("--winver" "$db_winver")
            [ -n "$db_fsr" ] && [ "$db_fsr" != "off" ] && pass_flags+=("--fsr" "$db_fsr")
            [ "$db_cat" = "programa" ] && pass_flags+=("--program")
            [ "$db_backend" = "wined3d" ] && pass_flags+=("--wined3d")
        fi
    fi

    # 3. Si no es ID, ¿coincide con el nombre o ejecutable de algún juego en la base de datos?
    if [ -z "$target_resolved" ] && [ -f "$DB_FILE" ]; then
        while IFS='|' read -r nombre ruta prefijo winver fsr cat backend; do
            [ -z "$nombre" ] && continue
            local base_db
            base_db=$(basename "$ruta")
            if [ "${target_raw,,}" = "${nombre,,}" ] || [ "${target_raw,,}" = "${base_db,,}" ]; then
                db_matched_name="$nombre"
                target_resolved="$ruta"
                [ -n "$winver" ] && [ "$winver" != "default" ] && pass_flags+=("--winver" "$winver")
                [ -n "$fsr" ] && [ "$fsr" != "off" ] && pass_flags+=("--fsr" "$fsr")
                [ "$cat" = "programa" ] && pass_flags+=("--program")
                [ "$backend" = "wined3d" ] && pass_flags+=("--wined3d")
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
    install)
        shift
        cmd_install "$@"
        ;;
    doctor|check|salud)
        cmd_doctor
        ;;
    runner|runners)
        shift
        cmd_runner "$@"
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
    clean-cache)
        cmd_clean_cache
        ;;
    update|upgrade)
        echo -e "\n${CYAN}${BOLD}Actualizando Vessel y paquetes del sistema...${RESET}"
        if [ -d "${DIR}/.git" ]; then
            git -C "$DIR" pull origin main || true
            : > "${DIR}/version.txt" 2>/dev/null || true
        fi
        if command -v apt &>/dev/null; then
            sudo apt update && sudo apt upgrade -y
        fi
        echo -e "${GREEN}[✓] Actualización completada.${RESET}\n"
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
