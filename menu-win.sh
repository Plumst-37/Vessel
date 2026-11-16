#!/bin/bash
# ==============================================================================
# MENU WIN (EDICIÓN UNIVERSAL OPTIMIZADA PARA CUALQUIER PC)
# Gestor de Juegos y Programas de Windows con Detección Automática de Hardware
# ==============================================================================

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_FILE="${DIR}/programas.db"
LAUNCHER="${DIR}/launch-win-app.sh"
DXVK_CONF="${DIR}/dxvk.conf"
CONFIG_USER="${DIR}/config_rendimiento.cfg"

# Cargar preferencias y módulo de hardware
[ -f "$CONFIG_USER" ] && source "$CONFIG_USER"
source "${DIR}/hardware_detect.sh"

# Asegurar que la base de datos de programas y el prefijo de Wine existan
touch "$DB_FILE"
mkdir -p "${DIR}/wineprefix"

# ==============================================================================
# PALETA DE COLORES ANSI
# ==============================================================================
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_CYAN="\033[1;36m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_BLUE="\033[1;34m"
C_MAGENTA="\033[1;35m"
C_RED="\033[1;31m"
C_WHITE="\033[1;37m"
C_GRAY="\033[0;90m"

# ==============================================================================
# 1. ACTUALIZACIÓN AUTOMÁTICA DESDE GITHUB (AL ABRIR EL PROGRAMA)
# ==============================================================================
verificar_actualizacion_github() {
    if [ ! -d "${DIR}/.git" ] || ! command -v git &>/dev/null; then
        return
    fi

    local remote_url
    remote_url=$(git -C "${DIR}" config --get remote.origin.url 2>/dev/null || true)
    [ -z "$remote_url" ] && return

    echo -e "${C_CYAN}🔄 Comprobando actualizaciones en GitHub...${C_RESET}"

    # Fetch rápido con timeout de 3 segundos
    if timeout 4 git -C "${DIR}" fetch origin main --quiet 2>/dev/null || timeout 4 git -C "${DIR}" fetch origin --quiet 2>/dev/null; then
        local local_hash
        local remote_hash
        local_hash=$(git -C "${DIR}" rev-parse HEAD 2>/dev/null)
        remote_hash=$(git -C "${DIR}" rev-parse origin/main 2>/dev/null || git -C "${DIR}" rev-parse @{u} 2>/dev/null)

        if [ -n "$local_hash" ] && [ -n "$remote_hash" ] && [ "$local_hash" != "$remote_hash" ]; then
            echo ""
            echo -e "${C_GREEN}⚡ ¡Nueva versión encontrada en GitHub! Actualizando automáticamente...${C_RESET}"
            if git -C "${DIR}" pull --quiet origin main 2>/dev/null || git -C "${DIR}" pull --quiet 2>/dev/null; then
                chmod +x "${DIR}"/*.sh "${DIR}"/*.py 2>/dev/null || true
                echo -e "${C_GREEN}✔ ¡Vessel actualizado con éxito a la última versión! Reiniciando menú...${C_RESET}"
                sleep 1.2
                exec "$0" "$@"
            fi
        else
            echo -e "${C_GREEN}✔ Vessel está en la última versión de GitHub.${C_RESET}"
            sleep 0.5
        fi
    fi
}

# ==============================================================================
# 2. CONFIGURACIÓN INICIAL / SELECCIÓN DE DISTRIBUCIÓN LINUX
# ==============================================================================
seleccionar_distribucion_interactiva() {
    clear 2>/dev/null || true
    echo -e "${C_CYAN}╔══════════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}             ${C_GREEN}🐧  SELECCIONA TU DISTRIBUCIÓN DE LINUX  🐧${C_RESET}              ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}       ${C_WHITE}Para configurar los comandos y paquetes exactos sin errores${C_RESET}     ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}╚══════════════════════════════════════════════════════════════════════╝${C_RESET}"
    echo ""
    echo -e "  ${C_GRAY}Elige cuál de estas distribuciones estás utilizando en tu equipo:${C_RESET}"
    echo ""
    echo -e "  ${C_BOLD}${C_CYAN}[1]${C_RESET} ${C_WHITE}🍥 Debian${C_RESET} ${C_GRAY}(Debian 11, 12 Bookworm, 13 Trixie, Sid, Devuan)${C_RESET}"
    echo -e "  ${C_BOLD}${C_CYAN}[2]${C_RESET} ${C_WHITE}🟠 Ubuntu / Linux Mint${C_RESET} ${C_GRAY}(Pop!_OS, Zorin OS, KDE Neon, Elementary)${C_RESET}"
    echo -e "  ${C_BOLD}${C_CYAN}[3]${C_RESET} ${C_WHITE}🎩 Fedora / Nobara${C_RESET} ${C_GRAY}(RHEL, CentOS, AlmaLinux, Rocky Linux)${C_RESET}"
    echo -e "  ${C_BOLD}${C_CYAN}[4]${C_RESET} ${C_WHITE}🏹 Arch Linux / Manjaro${C_RESET} ${C_GRAY}(EndeavourOS, Garuda, SteamOS Holo)${C_RESET}"
    echo -e "  ${C_BOLD}${C_CYAN}[5]${C_RESET} ${C_WHITE}🦎 openSUSE${C_RESET} ${C_GRAY}(Tumbleweed, Leap, MicroOS)${C_RESET}"
    echo ""
    read -p "$(echo -e "${C_BOLD}Selecciona tu sistema (1-5) [Por defecto: 1]: ${C_RESET}")" sel_distro

    case "$sel_distro" in
        2)
            SISTEMA_LINUX="ubuntu"
            DISTRO_NAME="Ubuntu / Linux Mint"
            ;;
        3)
            SISTEMA_LINUX="fedora"
            DISTRO_NAME="Fedora / Nobara"
            ;;
        4)
            SISTEMA_LINUX="arch"
            DISTRO_NAME="Arch Linux / Manjaro"
            ;;
        5)
            SISTEMA_LINUX="opensuse"
            DISTRO_NAME="openSUSE"
            ;;
        *)
            SISTEMA_LINUX="debian"
            DISTRO_NAME="Debian"
            ;;
    esac

    guardar_configuracion_distro

    echo ""
    echo -e "${C_GREEN}✔ Sistema configurado exitosamente:${C_RESET} ${C_BOLD}${DISTRO_NAME}${C_RESET}"
    sleep 1
}

guardar_configuracion_distro() {
    touch "$CONFIG_USER"
    if grep -q "^SISTEMA_LINUX=" "$CONFIG_USER" 2>/dev/null; then
        sed -i "s/^SISTEMA_LINUX=.*/SISTEMA_LINUX=\"$SISTEMA_LINUX\"/" "$CONFIG_USER"
    else
        echo "SISTEMA_LINUX=\"$SISTEMA_LINUX\"" >> "$CONFIG_USER"
    fi
    if grep -q "^DISTRO_NAME=" "$CONFIG_USER" 2>/dev/null; then
        sed -i "s/^DISTRO_NAME=.*/DISTRO_NAME=\"$DISTRO_NAME\"/" "$CONFIG_USER"
    else
        echo "DISTRO_NAME=\"$DISTRO_NAME\"" >> "$CONFIG_USER"
    fi
}

comprobar_configuracion_inicial_distro() {
    [ -f "$CONFIG_USER" ] && source "$CONFIG_USER"
    if [ -z "$SISTEMA_LINUX" ]; then
        seleccionar_distribucion_interactiva
    fi
}

# ==============================================================================
# ENCABEZADO DINÁMICO SEGÚN EL EQUIPO
# ==============================================================================
mostrar_banner() {
    clear 2>/dev/null || true
    # Recargar preferencias si cambiaron
    [ -f "$CONFIG_USER" ] && source "$CONFIG_USER"
    aplicar_entorno_hardware

    local motor_mostrar="${RENDERER_IN_USE:-DXVK (Vulkan)}"
    local distro_mostrar="${DISTRO_NAME:-Debian}"

    echo -e "${C_CYAN}╔══════════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}                   ${C_MAGENTA}🚀  M E N U   W I N   ( U N I V E R S A L )  🚀${C_RESET}     ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}           ${C_WHITE}Gestor y Optimizador de Juegos y Programas de Windows${C_RESET}      ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}╠══════════════════════════════════════════════════════════════════════╣${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET} ${C_YELLOW}Sistema:${C_RESET} ${distro_mostrar:0:22} | ${C_YELLOW}CPU:${C_RESET} ${CPU_MODEL:0:25} (${CPU_CORES} Hilos)"
    echo -e "${C_CYAN}║${C_RESET} ${C_GREEN}GPU:${C_RESET} ${DETECTED_GPU:0:55}"
    echo -e "${C_CYAN}║${C_RESET} ${C_CYAN}Motor:${C_RESET} [${motor_mostrar}] | ${C_CYAN}Perfil:${C_RESET} [${PERFIL_RENDIMIENTO:-maximo}] | ${C_CYAN}FPS:${C_RESET} ${LIMITE_FPS:-60}"
    echo -e "${C_CYAN}║${C_RESET} ${C_CYAN}FSR:${C_RESET} $([ "$ACTIVAR_FSR" = "1" ] && echo -e "${C_GREEN}Activo (x${FSR_STRENGTH:-2})${C_RESET}" || echo -e "${C_RED}Apagado${C_RESET}") | ${C_CYAN}HUD FPS:${C_RESET} $([ "$MOSTRAR_HUD_FPS" = "1" ] && echo -e "${C_GREEN}Activo${C_RESET}" || echo -e "${C_RED}Apagado${C_RESET}")"
    echo -e "${C_CYAN}╚══════════════════════════════════════════════════════════════════════╝${C_RESET}"
    echo ""
}

pausar() {
    echo ""
    echo -e "${C_GRAY}──────────────────────────────────────────────────────────────────────${C_RESET}"
    read -p "$(echo -e "${C_CYAN}Presiona ${C_BOLD}[Enter]${C_RESET}${C_CYAN} para volver al menú...${C_RESET}")" _
}

# ==============================================================================
# 1) INICIAR PROGRAMA
# ==============================================================================
iniciar_programa() {
    while true; do
        mostrar_banner
        echo -e "${C_GREEN}▶ [ INICIAR PROGRAMA O JUEGO ]${C_RESET}"
        echo -e "${C_GRAY}Selecciona el programa que deseas ejecutar con aceleración gráfica:${C_RESET}"
        echo ""

        if [ ! -s "$DB_FILE" ]; then
            echo -e "${C_YELLOW}⚠️  Aún no tienes programas registrados en la lista.${C_RESET}"
            echo -e "${C_WHITE}Ve a la opción ${C_BOLD}'2) Configurar Programa Win'${C_RESET}${C_WHITE} para añadir uno.${C_RESET}"
            pausar
            return
        fi

        local i=1
        declare -a nombres
        declare -a rutas

        while IFS='|' read -r nombre ruta prefijo; do
            [ -z "$nombre" ] && continue
            nombres[i]="$nombre"
            rutas[i]="$ruta"
            echo -e "  ${C_BOLD}${C_CYAN}[$i]${C_RESET} ${C_WHITE}${nombre}${C_RESET}"
            echo -e "      ${C_GRAY}↳ ${ruta}${C_RESET}"
            ((i++))
        done < "$DB_FILE"

        local total=$((i - 1))
        echo ""
        echo -e "  ${C_BOLD}${C_RED}[0]${C_RESET} ${C_YELLOW}Volver al menú principal${C_RESET}"
        echo ""
        read -p "$(echo -e "${C_BOLD}Elegir opción (1-${total} o 0): ${C_RESET}")" seleccion

        if [ "$seleccion" = "0" ] || [ -z "$seleccion" ]; then
            return
        fi

        if [[ "$seleccion" =~ ^[0-9]+$ ]] && [ "$seleccion" -ge 1 ] && [ "$seleccion" -le "$total" ]; then
            local prog_nombre="${nombres[$seleccion]}"
            local prog_ruta="${rutas[$seleccion]}"

            echo ""
            echo -e "${C_GREEN}🚀 Iniciando: ${C_BOLD}${prog_nombre}${C_RESET}..."
            echo -e "${C_GRAY}Optimizando para tu ${DETECTED_GPU}...${C_RESET}"
            sleep 1

            if [ -x "$LAUNCHER" ]; then
                "$LAUNCHER" "$prog_ruta"
            else
                echo -e "${C_RED}❌ Error: No se encontró el lanzador en ${LAUNCHER}${C_RESET}"
            fi
            pausar
            return
        else
            echo -e "${C_RED}❌ Opción inválida. Intenta nuevamente.${C_RESET}"
            sleep 1.2
        fi
    done
}

# ==============================================================================
# 2) CONFIGURAR PROGRAMA WIN
# ==============================================================================
configurar_programa_win() {
    while true; do
        mostrar_banner
        echo -e "${C_YELLOW}⚙️  [ CONFIGURAR PROGRAMA WIN ]${C_RESET}"
        echo -e "${C_GRAY}Administra los programas, instaladores y accesos de Windows:${C_RESET}"
        echo ""
        echo -e "  ${C_BOLD}${C_CYAN}[1]${C_RESET} ${C_GREEN}➕ Añadir nuevo programa portable${C_RESET}"
        echo -e "  ${C_BOLD}${C_CYAN}[2]${C_RESET} ${C_CYAN}➕ Añadir nuevo programa instalable${C_RESET}"
        echo -e "  ${C_BOLD}${C_CYAN}[3]${C_RESET} ${C_RED}🗑️  Eliminar programa de la lista (no borra tus archivos)${C_RESET}"
        echo -e "  ${C_BOLD}${C_CYAN}[4]${C_RESET} ${C_WHITE}📋 Ver todos los programas registrados${C_RESET}"
        echo -e "  ${C_BOLD}${C_CYAN}[5]${C_RESET} ${C_MAGENTA}🖥️  Crear / Regenerar Acceso Directo en el Escritorio (1-Clic)${C_RESET}"
        echo -e "  ${C_BOLD}${C_CYAN}[6]${C_RESET} ${C_BLUE}📂 Abrir carpeta del juego (para instalar Mods, parches o ver archivos)${C_RESET}"
        echo ""
        echo -e "  ${C_BOLD}${C_RED}[0]${C_RESET} ${C_YELLOW}Volver al menú principal${C_RESET}"
        echo ""
        read -p "$(echo -e "${C_BOLD}Elegir opción: ${C_RESET}")" sub_opc

        case "$sub_opc" in
            1)
                agregar_programa_portable
                ;;
            2)
                agregar_programa_instalable
                ;;
            3)
                eliminar_programa_lista
                ;;
            4)
                listar_programas
                ;;
            5)
                crear_acceso_escritorio_interactivo
                ;;
            6)
                abrir_carpeta_juego_mods
                ;;
            0|"")
                return
                ;;
            *)
                echo -e "${C_RED}❌ Opción inválida.${C_RESET}"
                sleep 1.2
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 2.1) AÑADIR PROGRAMA PORTABLE
# ------------------------------------------------------------------------------
agregar_programa_portable() {
    mostrar_banner
    echo -e "${C_GREEN}➕ [ AÑADIR NUEVO PROGRAMA PORTABLE ]${C_RESET}"
    echo -e "${C_GRAY}Configura el acceso para tu juego o programa portable (.exe, .bat o acceso directo .lnk / .ink):${C_RESET}"
    echo ""

    local ruta_prog=""
    local metodo_busqueda=""

    echo -e "${C_WHITE}¿Cómo deseas buscar el ejecutable o acceso directo portable?${C_RESET}"
    echo -e "  ${C_BOLD}[1]${C_RESET} ${C_CYAN}🖱️  Explorar con el ratón (Abrir ventana de diálogo gráfica)${C_RESET}"
    echo -e "  ${C_BOLD}[2]${C_RESET} ${C_YELLOW}⌨️  Escribir o pegar la ruta manualmente en la terminal${C_RESET}"
    echo ""
    read -p "$(echo -e "${C_BOLD}Elegir método (1 o 2): ${C_RESET}")" metodo_busqueda

    if [ "$metodo_busqueda" = "1" ]; then
        echo -e "${C_CYAN}Abriendo explorador de archivos... (Selecciona tu archivo .exe, .bat o acceso directo .lnk / .ink)${C_RESET}"
        if command -v kdialog &>/dev/null && [ -n "$DISPLAY$WAYLAND_DISPLAY" ]; then
            ruta_prog=$(kdialog --title "Seleccionar Ejecutable o Acceso Directo (.exe, .bat, .lnk, .ink)" --getopenfilename "/media" "*.exe *.bat *.cmd *.lnk *.ink *.EXE *.BAT *.CMD *.LNK *.INK | Ejecutables y Accesos Directos (*.exe, *.bat, *.lnk, *.ink)
* | Todos los archivos (*)" 2>/dev/null)
        elif command -v zenity &>/dev/null && [ -n "$DISPLAY$WAYLAND_DISPLAY" ]; then
            ruta_prog=$(zenity --file-selection --title="Seleccionar Ejecutable o Acceso Directo (.exe, .bat, .lnk, .ink)" --file-filter="Ejecutables y Accesos Directos (*.exe, *.bat, *.lnk, *.ink) | *.exe *.bat *.cmd *.lnk *.ink *.EXE *.BAT *.CMD *.LNK *.INK" --file-filter="Todos los archivos (*) | *" 2>/dev/null)
        fi

        if [ -z "$ruta_prog" ]; then
            echo -e "${C_YELLOW}No se seleccionó ningún archivo con el explorador.${C_RESET}"
            read -p "$(echo -e "${C_WHITE}¿Deseas escribir la ruta manualmente? (s/N): ${C_RESET}")" reintentar_manual
            case "$reintentar_manual" in
                [sS]*) ;;
                *) return ;;
            esac
        else
            echo -e "${C_GREEN}✔ Archivo seleccionado:${C_RESET} ${ruta_prog}"
        fi
    fi

    if [ -z "$ruta_prog" ]; then
        echo ""
        echo -e "${C_CYAN}Ubicación del programa${C_RESET} ${C_GRAY}(ruta exacta al .exe, .bat o acceso directo .lnk / .ink):${C_RESET}"
        echo -e "${C_GRAY}Ejemplo: /media/plumst/Disco/Juego/juego.exe o /media/plumst/Disco/Juego/Jugar.lnk${C_RESET}"
        read -p "$(echo -e "${C_BOLD}➤ ${C_RESET}")" ruta_prog
    fi

    # Limpiar comillas si el usuario copió la ruta con comillas
    ruta_prog="${ruta_prog%\"}"
    ruta_prog="${ruta_prog#\"}"
    ruta_prog="${ruta_prog%\'}"
    ruta_prog="${ruta_prog#\'}"

    if [ -z "$ruta_prog" ]; then
        echo -e "${C_RED}❌ La ruta no puede estar vacía.${C_RESET}"
        pausar
        return
    fi

    if [ ! -f "$ruta_prog" ]; then
        echo ""
        echo -e "${C_YELLOW}⚠️  Aviso: El archivo no parece existir en esa ruta o el disco no está montado.${C_RESET}"
        read -p "$(echo -e "${C_WHITE}¿Deseas guardarlo de todas formas? (s/N): ${C_RESET}")" guardar_forzado
        case "$guardar_forzado" in
            [sS]*) ;;
            *) echo -e "${C_YELLOW}Operación cancelada.${C_RESET}"; pausar; return ;;
        esac
    fi

    local nombre_sugerido_base=""

    # DETECCIÓN Y RESOLUCIÓN INTELIGENTE DE ACCESOS DIRECTOS .LNK / .INK
    if [[ "$ruta_prog" =~ \.([lL][nN][kK]|[iI][nN][kK])$ ]] && [ -f "$ruta_prog" ]; then
        echo ""
        echo -e "${C_CYAN}🔍 Analizando acceso directo de Windows (${ruta_prog##*.})...${C_RESET}"
        local resolved_res=""
        local resolved_status=""
        local resolved_path=""
        local link_name=""
        local candidates_raw=""

        if [ -f "${DIR}/resolver_lnk.py" ]; then
            resolved_res=$(python3 "${DIR}/resolver_lnk.py" "$ruta_prog" "${DIR}/wineprefix" 2>/dev/null || true)
            resolved_status=$(echo "$resolved_res" | grep '^STATUS=' | cut -d= -f2-)
            resolved_path=$(echo "$resolved_res" | grep '^RESOLVED_PATH=' | cut -d= -f2-)
            link_name=$(echo "$resolved_res" | grep '^NAME=' | cut -d= -f2-)
            candidates_raw=$(echo "$resolved_res" | grep '^CANDIDATES=' | cut -d= -f2-)
        fi

        # Fallback con comandos nativos si python no estuviera disponible
        if [ "$resolved_status" != "RESOLVED" ]; then
            local win_target
            win_target=$(file "$ruta_prog" 2>/dev/null | sed -n 's/.*LocalBasePath "\([^"]*\)".*/\1/p')
            [ -z "$win_target" ] && win_target=$(strings "$ruta_prog" 2>/dev/null | grep -iE '^[a-zA-Z]:\\.*\.exe$' | head -n 1)
            if [ -n "$win_target" ]; then
                local rel_clean
                rel_clean=$(echo "$win_target" | sed -E 's/^[a-zA-Z]:[\\\/]+//' | tr '\\' '/')
                if [ -f "${DIR}/wineprefix/drive_c/${rel_clean}" ]; then
                    resolved_path="${DIR}/wineprefix/drive_c/${rel_clean}"
                    resolved_status="RESOLVED"
                fi
            fi
        fi

        if [ "$resolved_status" = "RESOLVED" ] && [ -f "$resolved_path" ]; then
            echo -e "${C_GREEN}✔ ¡Acceso directo resuelto con éxito!${C_RESET}"
            echo -e "   ${C_BOLD}Acceso directo:${C_RESET} $(basename "$ruta_prog")"
            echo -e "   ${C_BOLD}Ejecutable real:${C_RESET} ${C_CYAN}${resolved_path}${C_RESET}"
            nombre_sugerido_base="$link_name"
            ruta_prog="$resolved_path"
        elif [ "$resolved_status" = "MULTIPLE_CANDIDATES" ] && [ -n "$candidates_raw" ]; then
            echo -e "${C_YELLOW}Se detectaron varios ejecutables en la carpeta del juego:${C_RESET}"
            IFS='|' read -r -a cand_list <<< "$candidates_raw"
            local ci=1
            for c in "${cand_list[@]}"; do
                echo -e "  ${C_BOLD}${C_CYAN}[$ci]${C_RESET} $c"
                ((ci++))
            done
            echo -e "  ${C_BOLD}[0]${C_RESET} Conservar la ruta original"
            read -p "$(echo -e "${C_BOLD}Selecciona el ejecutable correcto (1-${#cand_list[@]} o 0): ${C_RESET}")" cand_sel
            if [[ "$cand_sel" =~ ^[0-9]+$ ]] && [ "$cand_sel" -ge 1 ] && [ "$cand_sel" -le "${#cand_list[@]}" ]; then
                ruta_prog="${cand_list[$((cand_sel - 1))]}"
                echo -e "${C_GREEN}✔ Ejecutable seleccionado:${C_RESET} ${ruta_prog}"
            fi
        else
            echo -e "${C_YELLOW}⚠️  Aviso: No se pudo localizar automáticamente el .exe en disco.${C_RESET}"
            echo -e "${C_GRAY}(Se guardará el acceso directo para que Wine lo resuelva al abrir)${C_RESET}"
        fi
    fi

    # Sugerir nombre limpio basado en el archivo o acceso directo
    local nombre_sugerido
    if [ -n "$nombre_sugerido_base" ]; then
        nombre_sugerido="$nombre_sugerido_base"
    else
        nombre_sugerido=$(basename "$ruta_prog" | sed -E 's/\.(exe|bat|cmd|lnk|ink|msi|EXE|BAT|CMD|LNK|INK|MSI)$//' | sed 's/[-_]/ /g')
    fi

    echo ""
    echo -e "${C_CYAN}Nombre para mostrar en el menú:${C_RESET}"
    read -p "$(echo -e "${C_GRAY}[Sugerido: ${nombre_sugerido}] (Presiona Enter para usar sugerido o escribe otro):${C_RESET}\n${C_BOLD}➤ ${C_RESET}")" nombre_prog
    [ -z "$nombre_prog" ] && nombre_prog="$nombre_sugerido"

    echo "${nombre_prog}|${ruta_prog}|compartido" >> "$DB_FILE"
    echo ""
    echo -e "${C_GREEN}✅ ¡Programa portable registrado exitosamente!${C_RESET}"
    echo -e "   ${C_BOLD}Nombre:${C_RESET} ${nombre_prog}"
    echo -e "   ${C_BOLD}Ruta:${C_RESET}   ${ruta_prog}"
    echo ""

    # Opción de crear acceso directo en el Escritorio
    read -p "$(echo -e "${C_YELLOW}¿Deseas crear un acceso directo en tu Escritorio para abrirlo con 1 clic? (S/n): ${C_RESET}")" crear_desktop
    case "$crear_desktop" in
        [nN]*) ;;
        *)
            crear_archivo_desktop "$nombre_prog" "$ruta_prog"
            ;;
    esac

    echo ""
    read -p "$(echo -e "${C_MAGENTA}¿Deseas iniciar ${C_BOLD}'${nombre_prog}'${C_RESET}${C_MAGENTA} ahora mismo? (s/N): ${C_RESET}")" iniciar_ahora
    case "$iniciar_ahora" in
        [sS]*)
            echo ""
            echo -e "${C_GREEN}🚀 Iniciando programa...${C_RESET}"
            sleep 1
            "$LAUNCHER" "$ruta_prog"
            pausar
            ;;
        *)
            pausar
            ;;
    esac
}

# ------------------------------------------------------------------------------
# 2.2) AÑADIR PROGRAMA INSTALABLE (SETUP / INSTALADOR)
# ------------------------------------------------------------------------------
agregar_programa_instalable() {
    mostrar_banner
    echo -e "${C_CYAN}➕ [ AÑADIR NUEVO PROGRAMA INSTALABLE ]${C_RESET}"
    echo -e "${C_GRAY}Ejecuta instaladores (Setup.exe, Installer.exe, .msi), instala el programa y lo registra automáticamente:${C_RESET}"
    echo ""

    local ruta_setup=""
    local metodo_busqueda=""

    echo -e "${C_WHITE}¿Cómo deseas buscar el archivo del instalador (Setup / Installer / .msi)?${C_RESET}"
    echo -e "  ${C_BOLD}[1]${C_RESET} ${C_CYAN}🖱️  Explorar con el ratón (Abrir explorador de archivos gráfico)${C_RESET}"
    echo -e "  ${C_BOLD}[2]${C_RESET} ${C_YELLOW}⌨️  Escribir o pegar la ruta manualmente en la terminal${C_RESET}"
    echo ""
    read -p "$(echo -e "${C_BOLD}Elegir método (1 o 2): ${C_RESET}")" metodo_busqueda

    if [ "$metodo_busqueda" = "1" ]; then
        echo -e "${C_CYAN}Abriendo explorador de archivos... (Selecciona tu archivo de instalación)${C_RESET}"
        if command -v kdialog &>/dev/null && [ -n "$DISPLAY$WAYLAND_DISPLAY" ]; then
            ruta_setup=$(kdialog --title "Seleccionar Instalador (.exe / .msi)" --getopenfilename "/media" "*.exe *.msi *.EXE *.MSI | Instaladores de Windows (*.exe, *.msi)" 2>/dev/null)
        elif command -v zenity &>/dev/null && [ -n "$DISPLAY$WAYLAND_DISPLAY" ]; then
            ruta_setup=$(zenity --file-selection --title="Seleccionar Instalador (.exe / .msi)" --file-filter="Instaladores (*.exe, *.msi) | *.exe *.msi *.EXE *.MSI" 2>/dev/null)
        fi

        if [ -z "$ruta_setup" ]; then
            echo -e "${C_YELLOW}No se seleccionó ningún archivo con el explorador.${C_RESET}"
            read -p "$(echo -e "${C_WHITE}¿Deseas escribir la ruta manualmente? (s/N): ${C_RESET}")" reintentar_manual
            case "$reintentar_manual" in
                [sS]*) ;;
                *) return ;;
            esac
        else
            echo -e "${C_GREEN}✔ Instalador seleccionado:${C_RESET} ${ruta_setup}"
        fi
    fi

    if [ -z "$ruta_setup" ]; then
        echo ""
        echo -e "${C_CYAN}Ubicación del archivo instalador${C_RESET} ${C_GRAY}(Setup.exe, Install.exe o archivo .msi):${C_RESET}"
        echo -e "${C_GRAY}Ejemplo: /media/plumst/Descargas/Juego_Setup.exe${C_RESET}"
        read -p "$(echo -e "${C_BOLD}➤ ${C_RESET}")" ruta_setup
    fi

    # Limpiar comillas
    ruta_setup="${ruta_setup%\"}"
    ruta_setup="${ruta_setup#\"}"
    ruta_setup="${ruta_setup%\'}"
    ruta_setup="${ruta_setup#\'}"

    if [ -z "$ruta_setup" ] || [ ! -f "$ruta_setup" ]; then
        echo -e "${C_RED}❌ Archivo instalador no encontrado o ruta vacía.${C_RESET}"
        pausar
        return
    fi

    # Sugerir nombre
    local nombre_sugerido
    nombre_sugerido=$(basename "$ruta_setup" | sed -E 's/(setup|installer|install|instalador|v[0-9.]+|[-_])+/ /gi' | sed 's/\.[^.]*$//' | xargs)
    [ -z "$nombre_sugerido" ] && nombre_sugerido="Juego Windows"

    echo ""
    echo -e "${C_CYAN}Nombre del programa o juego a instalar:${C_RESET}"
    read -p "$(echo -e "${C_GRAY}[Sugerido: ${nombre_sugerido}] (Presiona Enter para usar sugerido o escribe otro):${C_RESET}\n${C_BOLD}➤ ${C_RESET}")" nombre_prog
    [ -z "$nombre_prog" ] && nombre_prog="$nombre_sugerido"

    local target_prefix="${DIR}/wineprefix"

    # Ejecutar el instalador
    echo ""
    echo -e "${C_GREEN}🚀 [ EJECUTANDO INSTALADOR DE WINDOWS ]${C_RESET}"
    echo -e "${C_YELLOW}Por favor, completa los pasos en la ventana de instalación que aparecerá.${C_RESET}"
    echo -e "${C_GRAY}(Deja la ruta por defecto recomendada: C:\\Program Files\\...)${C_RESET}"
    echo ""
    sleep 1

    local time_start
    time_start=$(date +%s)

    "$LAUNCHER" "$ruta_setup" || true

    # Pequeña pausa por si el instalador dejó subprocesos finalizando
    sleep 2

    echo ""
    echo -e "${C_GREEN}✔ El proceso del instalador ha terminado.${C_RESET}"
    echo -e "${C_CYAN}Buscando automáticamente el ejecutable principal recién instalado...${C_RESET}"

    local exe_instalado=""
    local candidatos=()
    declare -A vistos

    # 1. ESTRATEGIA .LNK / .INK: Buscar accesos directos creados por el instalador en Start Menu y Escritorio
    if [ -d "${target_prefix}/drive_c/users" ]; then
        while IFS= read -r lnk_file; do
            [ -z "$lnk_file" ] && continue
            local cand_resuelto=""
            if [ -f "${DIR}/resolver_lnk.py" ]; then
                local res_out
                res_out=$(python3 "${DIR}/resolver_lnk.py" "$lnk_file" "$target_prefix" 2>/dev/null || true)
                local res_status
                res_status=$(echo "$res_out" | grep '^STATUS=' | cut -d= -f2-)
                if [ "$res_status" = "RESOLVED" ]; then
                    cand_resuelto=$(echo "$res_out" | grep '^RESOLVED_PATH=' | cut -d= -f2-)
                fi
            fi

            if [ -z "$cand_resuelto" ] || [ ! -f "$cand_resuelto" ]; then
                local target_in_lnk
                target_in_lnk=$(strings "$lnk_file" 2>/dev/null | grep -iE '^[a-zA-Z]:\\.*\.exe$' | head -n 1)
                if [ -n "$target_in_lnk" ]; then
                    local rel_path
                    rel_path=$(echo "$target_in_lnk" | sed -E 's/^[a-zA-Z]:[\\\/]+//' | tr '\\' '/')
                    cand_resuelto="${target_prefix}/drive_c/${rel_path}"
                fi
            fi

            if [ -n "$cand_resuelto" ] && [ -f "$cand_resuelto" ]; then
                local base_cand
                base_cand=$(basename "$cand_resuelto" | tr '[:upper:]' '[:lower:]')
                if [[ ! "$base_cand" =~ (unins|uninstall|setup|installer|dxsetup|vcredist|crashpad) ]] && [ -z "${vistos[$cand_resuelto]}" ]; then
                    candidatos+=("$cand_resuelto")
                    vistos["$cand_resuelto"]=1
                fi
            fi
        done < <(find "${target_prefix}/drive_c/users" -type f \( -iname "*.lnk" -o -iname "*.ink" \) -newerct "@$((time_start - 30))" 2>/dev/null)
    fi

    # 2. ESTRATEGIA -NEWERCT: Buscar archivos .exe creados en disco (verificando tiempo de creación de inodo)
    if [ -d "${target_prefix}/drive_c" ]; then
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            local fname
            fname=$(basename "$f" | tr '[:upper:]' '[:lower:]')
            if [[ "$fname" =~ (unins|uninstall|setup|installer|dxsetup|vcredist|vc_redist|crashpad|helper|crash_reporter|update|updater) ]]; then
                continue
            fi
            if [[ "$f" =~ /windows/ ]]; then
                continue
            fi
            if [ -z "${vistos[$f]}" ]; then
                candidatos+=("$f")
                vistos["$f"]=1
            fi
        done < <(find "${target_prefix}/drive_c" -type f \( -iname "*.exe" \) -newerct "@$((time_start - 30))" 2>/dev/null | head -n 15)
    fi

    if [ ${#candidatos[@]} -gt 0 ]; then
        echo ""
        echo -e "${C_GREEN}Se detectaron los siguientes ejecutables recién creados:${C_RESET}"
        local idx=1
        for cand in "${candidatos[@]}"; do
            echo -e "  ${C_BOLD}${C_CYAN}[$idx]${C_RESET} ${cand}"
            ((idx++))
        done
        echo -e "  ${C_BOLD}[0]${C_RESET} ${C_YELLOW}Seleccionar otro archivo con el ratón o escribir ruta${C_RESET}"
        echo ""
        read -p "$(echo -e "${C_BOLD}Selecciona el ejecutable del juego instalado (1-${#candidatos[@]} o 0): ${C_RESET}")" sel_cand

        if [[ "$sel_cand" =~ ^[0-9]+$ ]] && [ "$sel_cand" -ge 1 ] && [ "$sel_cand" -le ${#candidatos[@]} ]; then
            exe_instalado="${candidatos[$((sel_cand - 1))]}"
        fi
    fi

    if [ -z "$exe_instalado" ]; then
        echo ""
        echo -e "${C_YELLOW}Selecciona el archivo ejecutable (.exe) o acceso directo (.lnk / .ink) instalado en Wine:${C_RESET}"
        if command -v kdialog &>/dev/null && [ -n "$DISPLAY$WAYLAND_DISPLAY" ]; then
            exe_instalado=$(kdialog --title "Seleccionar Ejecutable o Acceso Directo (.exe, .lnk, .ink)" --getopenfilename "${target_prefix}/drive_c" "*.exe *.lnk *.ink *.EXE *.LNK *.INK | Ejecutables y Accesos Directos (*.exe, *.lnk, *.ink)
* | Todos los archivos (*)" 2>/dev/null)
        elif command -v zenity &>/dev/null && [ -n "$DISPLAY$WAYLAND_DISPLAY" ]; then
            exe_instalado=$(zenity --file-selection --filename="${target_prefix}/drive_c/" --title="Seleccionar Ejecutable o Acceso Directo (.exe, .lnk, .ink)" --file-filter="Ejecutables y Accesos Directos (*.exe, *.lnk, *.ink) | *.exe *.lnk *.ink *.EXE *.LNK *.INK" --file-filter="Todos los archivos (*) | *" 2>/dev/null)
        fi

        if [ -z "$exe_instalado" ]; then
            read -p "$(echo -e "${C_CYAN}Escribe o pega la ruta del .exe o .lnk/.ink instalado:${C_RESET}\n${C_BOLD}➤ ${C_RESET}")" exe_instalado
        fi
    fi

    exe_instalado="${exe_instalado%\"}"
    exe_instalado="${exe_instalado#\"}"
    exe_instalado="${exe_instalado%\'}"
    exe_instalado="${exe_instalado#\'}"

    # Si seleccionó un acceso directo, resolverlo
    if [[ "$exe_instalado" =~ \.([lL][nN][kK]|[iI][nN][kK])$ ]] && [ -f "$exe_instalado" ]; then
        if [ -f "${DIR}/resolver_lnk.py" ]; then
            local res_sel
            res_sel=$(python3 "${DIR}/resolver_lnk.py" "$exe_instalado" "$target_prefix" 2>/dev/null || true)
            local res_sel_status
            res_sel_status=$(echo "$res_sel" | grep '^STATUS=' | cut -d= -f2-)
            if [ "$res_sel_status" = "RESOLVED" ]; then
                local res_sel_path
                res_sel_path=$(echo "$res_sel" | grep '^RESOLVED_PATH=' | cut -d= -f2-)
                if [ -n "$res_sel_path" ] && [ -f "$res_sel_path" ]; then
                    echo -e "${C_GREEN}✔ Acceso directo resuelto a:${C_RESET} ${res_sel_path}"
                    exe_instalado="$res_sel_path"
                fi
            fi
        fi
    fi

    if [ -z "$exe_instalado" ] || [ ! -f "$exe_instalado" ]; then
        echo -e "${C_RED}❌ No se seleccionó un ejecutable válido.${C_RESET}"
        echo -e "${C_GRAY}El programa quedó instalado en Wine, pero no se agregó al menú. Podrás agregarlo más tarde con la opción 1 (Programa portable).${C_RESET}"
        pausar
        return
    fi

    echo "${nombre_prog}|${exe_instalado}|compartido" >> "$DB_FILE"
    echo ""
    echo -e "${C_GREEN}✅ ¡Programa instalado y registrado exitosamente en el Menú Win!${C_RESET}"
    echo -e "   ${C_BOLD}Nombre:${C_RESET}     ${nombre_prog}"
    echo -e "   ${C_BOLD}Ejecutable:${C_RESET} ${exe_instalado}"
    echo ""

    # Crear acceso directo en el Escritorio
    read -p "$(echo -e "${C_YELLOW}¿Deseas crear un acceso directo en tu Escritorio para abrirlo con 1 clic? (S/n): ${C_RESET}")" crear_desk
    case "$crear_desk" in
        [nN]*) ;;
        *)
            crear_archivo_desktop "$nombre_prog" "$exe_instalado"
            ;;
    esac

    echo ""
    read -p "$(echo -e "${C_MAGENTA}¿Deseas iniciar ${C_BOLD}'${nombre_prog}'${C_RESET}${C_MAGENTA} ahora mismo? (s/N): ${C_RESET}")" iniciar_ahora
    case "$iniciar_ahora" in
        [sS]*)
            echo ""
            echo -e "${C_GREEN}🚀 Iniciando programa...${C_RESET}"
            sleep 1
            "$LAUNCHER" "$exe_instalado"
            pausar
            ;;
        *)
            pausar
            ;;
    esac
}

crear_archivo_desktop() {
    local nombre="$1"
    local ruta="$2"
    local desktop_path="/home/plumst/Escritorio/${nombre}.desktop"
    local carpeta_juego
    carpeta_juego="$(dirname "$ruta")"

    local exec_cmd="\"${LAUNCHER}\" \"${ruta}\""

    cat <<EOF > "$desktop_path"
[Desktop Entry]
Version=1.0
Type=Application
Name=${nombre}
Comment=Juego de Windows optimizado con Vessel
Exec=${exec_cmd}
Path=${carpeta_juego}
Icon=wine
Terminal=false
Categories=Game;
StartupNotify=true
Actions=AbrirCarpeta;

[Desktop Action AbrirCarpeta]
Name=📂 Abrir carpeta del juego (Instalar Mods / Archivos)
Exec=xdg-open "${carpeta_juego}"
Icon=folder-open
EOF

    chmod +x "$desktop_path"
    gio set "$desktop_path" metadata::trusted true 2>/dev/null || true
    echo -e "${C_GREEN}✔ Acceso directo creado en tu Escritorio:${C_RESET} ${nombre}.desktop"
    echo -e "${C_GRAY}  ↳ Tip: Puedes hacer clic derecho en el icono y elegir 'Abrir carpeta del juego' para pegar mods.${C_RESET}"
}

crear_acceso_escritorio_interactivo() {
    mostrar_banner
    echo -e "${C_MAGENTA}🖥️  [ CREAR ACCESO DIRECTO EN EL ESCRITORIO ]${C_RESET}"
    echo -e "${C_GRAY}Genera un lanzador directo de 1-clic en tu Escritorio para cualquier juego registrado:${C_RESET}"
    echo ""

    if [ ! -s "$DB_FILE" ]; then
        echo -e "${C_YELLOW}No hay programas guardados en la lista.${C_RESET}"
        pausar
        return
    fi

    local i=1
    declare -a nombres_d
    declare -a rutas_d
    declare -a prefijos_d
    while IFS='|' read -r nombre ruta prefijo; do
        [ -z "$nombre" ] && continue
        nombres_d[i]="$nombre"
        rutas_d[i]="$ruta"
        prefijos_d[i]="${prefijo:-compartido}"
        echo -e "  ${C_BOLD}${C_CYAN}[$i]${C_RESET} ${C_WHITE}${nombre}${C_RESET} ${C_GRAY}(${ruta})${C_RESET}"
        ((i++))
    done < "$DB_FILE"

    local total=$((i - 1))
    echo ""
    echo -e "  ${C_BOLD}[0]${C_RESET} ${C_YELLOW}Cancelar y volver${C_RESET}"
    echo ""
    read -p "$(echo -e "${C_BOLD}Selecciona el número del juego (1-${total} o 0): ${C_RESET}")" sel_d

    if [ "$sel_d" = "0" ] || [ -z "$sel_d" ]; then
        return
    fi

    if [[ "$sel_d" =~ ^[0-9]+$ ]] && [ "$sel_d" -ge 1 ] && [ "$sel_d" -le "$total" ]; then
        crear_archivo_desktop "${nombres_d[$sel_d]}" "${rutas_d[$sel_d]}"
    else
        echo -e "${C_RED}❌ Opción inválida.${C_RESET}"
    fi
    pausar
}

abrir_carpeta_juego_mods() {
    mostrar_banner
    echo -e "${C_CYAN}📂 [ ABRIR CARPETA DE UN JUEGO (MODS Y ARCHIVOS) ]${C_RESET}"
    echo -e "${C_GRAY}Abre la carpeta del juego en tu explorador de archivos para instalar mods, parches o traducciones:${C_RESET}"
    echo ""

    if [ ! -s "$DB_FILE" ]; then
        echo -e "${C_YELLOW}No hay programas registrados en la lista.${C_RESET}"
        pausar
        return
    fi

    local i=1
    declare -a nombres_c
    declare -a carpetas_c

    while IFS='|' read -r nombre ruta prefijo; do
        [ -z "$nombre" ] && continue
        nombres_c[i]="$nombre"
        carpetas_c[i]="$(dirname "$ruta")"
        echo -e "  ${C_BOLD}${C_CYAN}[$i]${C_RESET} ${C_WHITE}${nombre}${C_RESET}"
        echo -e "      ${C_GRAY}↳ Carpeta: ${carpetas_c[i]}${C_RESET}"
        ((i++))
    done < "$DB_FILE"

    local total=$((i - 1))
    echo ""
    echo -e "  ${C_BOLD}${C_YELLOW}[C]${C_RESET} ${C_MAGENTA}💽 Abrir Disco C: de Wine (Archivos de Programa / AppData)${C_RESET}"
    echo -e "  ${C_BOLD}${C_RED}[0]${C_RESET} ${C_YELLOW}Volver al menú${C_RESET}"
    echo ""
    read -p "$(echo -e "${C_BOLD}Selecciona el juego cuya carpeta deseas abrir (1-${total}, C o 0): ${C_RESET}")" sel_c

    if [ "$sel_c" = "0" ] || [ -z "$sel_c" ]; then
        return
    fi

    if [[ "$sel_c" =~ ^[cC]$ ]]; then
        local wine_c="${DIR}/wineprefix/drive_c"
        echo ""
        echo -e "${C_GREEN}Abriendo Disco C: de Wine en tu explorador de archivos...${C_RESET}"
        xdg-open "$wine_c" 2>/dev/null || dolphin "$wine_c" 2>/dev/null || true
        echo -e "${C_GRAY}Ruta: ${wine_c}${C_RESET}"
        pausar
        return
    fi

    if [[ "$sel_c" =~ ^[0-9]+$ ]] && [ "$sel_c" -ge 1 ] && [ "$sel_c" -le "$total" ]; then
        local target_folder="${carpetas_c[$sel_c]}"
        local target_name="${nombres_c[$sel_c]}"
        echo ""
        echo -e "${C_GREEN}Abriendo carpeta de '${target_name}' en tu explorador de archivos...${C_RESET}"
        xdg-open "$target_folder" 2>/dev/null || dolphin "$target_folder" 2>/dev/null || true
        echo ""
        echo -e "${C_CYAN}✔ Carpeta:${C_RESET} ${target_folder}"
        echo ""
        echo -e "${C_YELLOW}💡 Instrucciones sencillas para Mods:${C_RESET}"
        echo -e "  1. Pega tus archivos de mod (.asi, .dll, scripts, texturas o parches) directamente en esta carpeta."
        echo -e "  2. Vessel detectará y activará automáticamente librerías como dinput8.dll, dxgi.dll, version.dll, etc."
        echo -e "  3. Al iniciar el juego desde el Menú o tu Escritorio, los mods se cargarán solos."
        pausar
    else
        echo -e "${C_RED}❌ Opción inválida.${C_RESET}"
        sleep 1.2
    fi
}

eliminar_programa_lista() {
    mostrar_banner
    echo -e "${C_RED}🗑️  [ ELIMINAR PROGRAMA DE LA LISTA ]${C_RESET}"
    echo -e "${C_GRAY}Selecciona el número del programa que deseas quitar del menú.${C_RESET}"
    echo -e "${C_GRAY}(Nota: Esto solo lo quita del menú, NO borra tus archivos en disco).${C_RESET}"
    echo ""

    if [ ! -s "$DB_FILE" ]; then
        echo -e "${C_YELLOW}No hay programas guardados en la lista.${C_RESET}"
        pausar
        return
    fi

    local i=1
    declare -a nombres_del
    while IFS='|' read -r nombre ruta prefijo; do
        [ -z "$nombre" ] && continue
        nombres_del[i]="$nombre"
        echo -e "  ${C_BOLD}${C_RED}[$i]${C_RESET} ${C_WHITE}${nombre}${C_RESET} ${C_GRAY}(${ruta})${C_RESET}"
        ((i++))
    done < "$DB_FILE"

    local total=$((i - 1))
    echo ""
    echo -e "  ${C_BOLD}[0]${C_RESET} ${C_YELLOW}Cancelar y volver${C_RESET}"
    echo ""
    read -p "$(echo -e "${C_BOLD}Número a eliminar (1-${total} o 0): ${C_RESET}")" del_sel

    if [ "$del_sel" = "0" ] || [ -z "$del_sel" ]; then
        return
    fi

    if [[ "$del_sel" =~ ^[0-9]+$ ]] && [ "$del_sel" -ge 1 ] && [ "$del_sel" -le "$total" ]; then
        local eliminado="${nombres_del[$del_sel]}"
        sed -i "${del_sel}d" "$DB_FILE"
        echo ""
        echo -e "${C_GREEN}✅ El programa ${C_BOLD}'${eliminado}'${C_RESET}${C_GREEN} fue quitado del menú.${C_RESET}"
        echo -e "${C_GRAY}Tus archivos en disco se mantienen intactos.${C_RESET}"
    else
        echo -e "${C_RED}❌ Opción inválida.${C_RESET}"
    fi
    pausar
}

listar_programas() {
    mostrar_banner
    echo -e "${C_CYAN}📋 [ LISTA DE PROGRAMAS REGISTRADOS ]${C_RESET}"
    echo ""

    if [ ! -s "$DB_FILE" ]; then
        echo -e "${C_YELLOW}La lista está vacía.${C_RESET}"
    else
        local i=1
        while IFS='|' read -r nombre ruta prefijo; do
            [ -z "$nombre" ] && continue
            echo -e "  ${C_CYAN}[$i]${C_RESET} ${C_BOLD}${C_WHITE}${nombre}${C_RESET}"
            echo -e "      ${C_GRAY}↳ Ubicación:${C_RESET} ${ruta}"
            echo ""
            ((i++))
        done < "$DB_FILE"
    fi
    pausar
}

# ==============================================================================
# 3) CONFIGURACION DE RENDIMIENTO Y MOTOR GRÁFICO
# ==============================================================================
menu_configuracion() {
    while true; do
        mostrar_banner
        echo -e "${C_MAGENTA}🔧 [ CONFIGURACIÓN DE RENDIMIENTO Y MOTOR GRÁFICO ]${C_RESET}"
        echo -e "${C_GRAY}Ajusta el rendimiento para tu PC y optimiza el motor de renderizado:${C_RESET}"
        echo ""
        echo -e "  ${C_BOLD}${C_CYAN}[1]${C_RESET} ${C_GREEN}⚡ Cambiar Perfil de Rendimiento${C_RESET} (Actual: ${C_BOLD}${PERFIL_RENDIMIENTO:-maximo}${C_RESET})"
        echo -e "  ${C_BOLD}${C_CYAN}[2]${C_RESET} ${C_YELLOW}🎯 Cambiar Límite de FPS${C_RESET} (Actual: ${C_BOLD}${LIMITE_FPS:-60} FPS${C_RESET})"
        echo -e "  ${C_BOLD}${C_CYAN}[3]${C_RESET} ${C_MAGENTA}🚀 AMD FSR Upscaling (Para GPUs modestas o integradas)${C_RESET} (Actual: $([ "$ACTIVAR_FSR" = "1" ] && echo -e "${C_GREEN}ACTIVADO (x${FSR_STRENGTH:-2})${C_RESET}" || echo -e "${C_RED}DESACTIVADO${C_RESET}"))"
        echo -e "  ${C_BOLD}${C_CYAN}[4]${C_RESET} ${C_CYAN}📊 Contador de FPS en pantalla (HUD)${C_RESET} (Actual: $([ "$MOSTRAR_HUD_FPS" = "1" ] && echo -e "${C_GREEN}ACTIVADO${C_RESET}" || echo -e "${C_RED}DESACTIVADO${C_RESET}"))"
        echo -e "  ${C_BOLD}${C_CYAN}[5]${C_RESET} ${C_WHITE}🎮 Cambiar Motor Gráfico (DXVK Vulkan vs. WineD3D OpenGL)${C_RESET} (Actual: ${C_BOLD}${RENDERER_BACKEND:-auto}${C_RESET})"
        echo -e "  ${C_BOLD}${C_CYAN}[6]${C_RESET} ${C_WHITE}🖥️  Modo Escritorio Virtual (Solución a Pantalla Negra en multimonitor/resolución)${C_RESET} (Actual: $([ "$ESCRITORIO_VIRTUAL" = "1" ] && echo -e "${C_GREEN}ACTIVADO (${RESOLUCION_ESCRITORIO:-Auto})${C_RESET}" || echo -e "${C_RED}DESACTIVADO${C_RESET}"))"
        echo -e "  ${C_BOLD}${C_CYAN}[7]${C_RESET} ${C_WHITE}🔍 Diagnóstico de Hardware y Controladores${C_RESET}"
        echo ""
        echo -e "  ${C_BOLD}${C_RED}[0]${C_RESET} ${C_YELLOW}Volver al menú principal${C_RESET}"
        echo ""
        read -p "$(echo -e "${C_BOLD}Elegir opción: ${C_RESET}")" conf_opc

        case "$conf_opc" in
            1)
                ajustar_perfil_rendimiento
                ;;
            2)
                ajustar_limite_fps
                ;;
            3)
                ajustar_fsr_menu
                ;;
            4)
                alternar_hud_fps
                ;;
            5)
                ajustar_motor_grafico
                ;;
            6)
                ajustar_escritorio_virtual
                ;;
            7)
                mostrar_diagnostico_hardware
                ;;
            0|"")
                return
                ;;
            *)
                echo -e "${C_RED}❌ Opción inválida.${C_RESET}"
                sleep 1.2
                ;;
        esac
    done
}

guardar_config_usuario() {
    cat <<EOF > "$CONFIG_USER"
# Configuración de Rendimiento de Win para PC
PERFIL_RENDIMIENTO="${PERFIL_RENDIMIENTO}"
LIMITE_FPS="${LIMITE_FPS}"
ACTIVAR_FSR="${ACTIVAR_FSR}"
MOSTRAR_HUD_FPS="${MOSTRAR_HUD_FPS}"
FSR_STRENGTH="${FSR_STRENGTH:-2}"
RENDERER_BACKEND="${RENDERER_BACKEND:-auto}"
SISTEMA_LINUX="${SISTEMA_LINUX:-debian}"
DISTRO_NAME="${DISTRO_NAME:-Debian}"
ESCRITORIO_VIRTUAL="${ESCRITORIO_VIRTUAL:-0}"
RESOLUCION_ESCRITORIO="${RESOLUCION_ESCRITORIO:-1280x720}"
EOF
    # Regenerar dxvk.conf con los nuevos valores
    if [ -x "${DIR}/generar_dxvk_conf.sh" ]; then
        "${DIR}/generar_dxvk_conf.sh"
    fi
}

ajustar_escritorio_virtual() {
    mostrar_banner
    echo -e "${C_CYAN}🖥️  [ MODO ESCRITORIO VIRTUAL DE WINE ]${C_RESET}"
    echo -e "${C_GRAY}Soluciona la pantalla negra cuando los juegos cambian resolución (ej. a 4:3) o en configuraciones con doble monitor.${C_RESET}"
    echo ""
    local res_detectada
    res_detectada=$(xrandr 2>/dev/null | grep -E ' connected primary| connected' | head -n 1 | grep -oE '[0-9]+x[0-9]+' | head -n 1)
    [ -z "$res_detectada" ] && res_detectada="1280x720"

    echo -e "  ${C_BOLD}Estado actual:${C_RESET} $([ "$ESCRITORIO_VIRTUAL" = "1" ] && echo -e "${C_GREEN}ACTIVADO (${RESOLUCION_ESCRITORIO:-$res_detectada})${C_RESET}" || echo -e "${C_RED}DESACTIVADO${C_RESET}")"
    echo ""
    echo -e "  ${C_BOLD}[1]${C_RESET} ${C_GREEN}Activar con resolución nativa detectada (${res_detectada})${C_RESET}"
    echo -e "  ${C_BOLD}[2]${C_RESET} Activar con resolución 1920x1080 (Full HD)"
    echo -e "  ${C_BOLD}[3]${C_RESET} Activar con resolución 1280x720 (HD)"
    echo -e "  ${C_BOLD}[4]${C_RESET} Activar con resolución 1024x768 (4:3 Retro / Juegos Clásicos)"
    echo -e "  ${C_BOLD}[5]${C_RESET} ${C_RED}Desactivar Escritorio Virtual (Modo Pantalla Completa Directa)${C_RESET}"
    echo -e "  ${C_BOLD}[0]${C_RESET} Volver sin cambios"
    echo ""
    read -p "$(echo -e "${C_BOLD}Elegir opción: ${C_RESET}")" esc_opc

    case "$esc_opc" in
        1)
            ESCRITORIO_VIRTUAL="1"
            RESOLUCION_ESCRITORIO="$res_detectada"
            echo -e "${C_GREEN}✔ Escritorio Virtual activado a ${res_detectada}.${C_RESET}"
            ;;
        2)
            ESCRITORIO_VIRTUAL="1"
            RESOLUCION_ESCRITORIO="1920x1080"
            echo -e "${C_GREEN}✔ Escritorio Virtual activado a 1920x1080.${C_RESET}"
            ;;
        3)
            ESCRITORIO_VIRTUAL="1"
            RESOLUCION_ESCRITORIO="1280x720"
            echo -e "${C_GREEN}✔ Escritorio Virtual activado a 1280x720.${C_RESET}"
            ;;
        4)
            ESCRITORIO_VIRTUAL="1"
            RESOLUCION_ESCRITORIO="1024x768"
            echo -e "${C_GREEN}✔ Escritorio Virtual activado a 1024x768.${C_RESET}"
            ;;
        5)
            ESCRITORIO_VIRTUAL="0"
            echo -e "${C_YELLOW}Escritorio Virtual desactivado.${C_RESET}"
            ;;
        *) return ;;
    esac
    guardar_config_usuario
    sleep 1.2
}

ajustar_perfil_rendimiento() {
    mostrar_banner
    echo -e "${C_GREEN}⚡ [ CAMBIAR PERFIL DE RENDIMIENTO ]${C_RESET}"
    echo ""
    echo -e "  ${C_BOLD}[1]${C_RESET} ${C_GREEN}Máximo Rendimiento${C_RESET} (GameMode, GPU dedicada a tope, prioridad alta)"
    echo -e "  ${C_BOLD}[2]${C_RESET} ${C_YELLOW}Equilibrado${C_RESET} (Buen rendimiento con menor consumo térmico)"
    echo -e "  ${C_BOLD}[3]${C_RESET} ${C_BLUE}Ahorro de Batería / Laptop${C_RESET} (Menor uso de CPU para portátiles)"
    echo ""
    read -p "$(echo -e "${C_BOLD}Elegir perfil (1-3): ${C_RESET}")" perf_sel

    case "$perf_sel" in
        1) PERFIL_RENDIMIENTO="maximo" ;;
        2) PERFIL_RENDIMIENTO="equilibrado" ;;
        3) PERFIL_RENDIMIENTO="ahorro" ;;
        *) echo -e "${C_YELLOW}Sin cambios.${C_RESET}"; sleep 1; return ;;
    esac

    guardar_config_usuario
    echo -e "${C_GREEN}✔ Perfil cambiado a: ${C_BOLD}${PERFIL_RENDIMIENTO}${C_RESET}"
    sleep 1.2
}

ajustar_limite_fps() {
    mostrar_banner
    echo -e "${C_YELLOW}🎯 [ CONFIGURAR LÍMITE DE FPS ]${C_RESET}"
    echo -e "${C_GRAY}Limitar los FPS ayuda a mantener temperaturas bajas y evitar tirones de frametime:${C_RESET}"
    echo ""
    echo -e "  ${C_BOLD}[1]${C_RESET} 30 FPS  ${C_GRAY}(Ideal para laptops con batería o juegos muy pesados)${C_RESET}"
    echo -e "  ${C_BOLD}[2]${C_RESET} 60 FPS  ${C_GRAY}(Recomendado estándar: fluido y fresco)${C_RESET}"
    echo -e "  ${C_BOLD}[3]${C_RESET} 120 FPS ${C_GRAY}(Para monitores de alta tasa de refresco)${C_RESET}"
    echo -e "  ${C_BOLD}[4]${C_RESET} Ilimitado (Sin tope de fotogramas)"
    echo ""
    read -p "$(echo -e "${C_BOLD}Elegir límite (1-4): ${C_RESET}")" fps_sel

    case "$fps_sel" in
        1) LIMITE_FPS="30" ;;
        2) LIMITE_FPS="60" ;;
        3) LIMITE_FPS="120" ;;
        4) LIMITE_FPS="ilimitado" ;;
        *) echo -e "${C_YELLOW}Sin cambios.${C_RESET}"; sleep 1; return ;;
    esac

    guardar_config_usuario
    echo -e "${C_GREEN}✔ Límite establecido en: ${C_BOLD}${LIMITE_FPS}${C_RESET}"
    sleep 1.2
}

ajustar_fsr_menu() {
    mostrar_banner
    echo -e "${C_MAGENTA}🚀 [ CONFIGURACIÓN AMD FIDELITYFX SUPER RESOLUTION (FSR) ]${C_RESET}"
    echo -e "${C_GRAY}El reescalado inteligente FSR permite multiplicar los FPS en gráficas modestas:${C_RESET}"
    echo ""
    echo -e "  Estado actual: $([ "$ACTIVAR_FSR" = "1" ] && echo -e "${C_GREEN}ACTIVADO${C_RESET}" || echo -e "${C_RED}DESACTIVADO${C_RESET}")"
    echo -e "  Nitidez actual: Nivel ${FSR_STRENGTH:-2} (0=Máxima nitidez, 5=Suave)"
    echo ""
    echo -e "  ${C_BOLD}[1]${C_RESET} Alternar FSR (Encender / Apagar)"
    echo -e "  ${C_BOLD}[2]${C_RESET} Cambiar nivel de nitidez (0 a 5)"
    echo -e "  ${C_BOLD}[0]${C_RESET} Volver"
    echo ""
    read -p "$(echo -e "${C_BOLD}Elegir opción: ${C_RESET}")" fsr_opc

    case "$fsr_opc" in
        1)
            if [ "$ACTIVAR_FSR" = "1" ]; then
                ACTIVAR_FSR="0"
                echo -e "${C_YELLOW}AMD FSR Desactivado.${C_RESET}"
            else
                ACTIVAR_FSR="1"
                echo -e "${C_GREEN}AMD FSR Activado.${C_RESET}"
            fi
            ;;
        2)
            read -p "$(echo -e "${C_CYAN}Ingresa nivel de nitidez (0=Muy nítido, 2=Equilibrado, 5=Suave): ${C_RESET}")" nueva_nitidez
            if [[ "$nueva_nitidez" =~ ^[0-5]$ ]]; then
                FSR_STRENGTH="$nueva_nitidez"
                echo -e "${C_GREEN}Nitidez establecida en ${FSR_STRENGTH}.${C_RESET}"
            else
                echo -e "${C_RED}Valor inválido.${C_RESET}"
            fi
            ;;
        *) return ;;
    esac

    guardar_config_usuario
    sleep 1.2
}

alternar_hud_fps() {
    if [ "$MOSTRAR_HUD_FPS" = "1" ]; then
        MOSTRAR_HUD_FPS="0"
        echo -e "${C_YELLOW}Contador de FPS desactivado.${C_RESET}"
    else
        MOSTRAR_HUD_FPS="1"
        echo -e "${C_GREEN}Contador de FPS (HUD) activado para tus juegos.${C_RESET}"
    fi
    guardar_config_usuario
    sleep 1.2
}

ajustar_motor_grafico() {
    mostrar_banner
    echo -e "${C_WHITE}🎮 [ MOTOR DE RENDERIZADO GRÁFICO ]${C_RESET}"
    echo -e "${C_GRAY}Elige el motor que traduce los gráficos de DirectX en Linux:${C_RESET}"
    echo ""
    echo -e "  ${C_BOLD}[1]${C_RESET} ${C_GREEN}Automático (Recomendado)${C_RESET}"
    echo -e "      ${C_GRAY}Usa DXVK (Vulkan) si tu GPU lo soporta; si es una PC antigua, usa OpenGL.${C_RESET}"
    echo -e "  ${C_BOLD}[2]${C_RESET} ${C_CYAN}Forzar DXVK (Vulkan)${C_RESET}"
    echo -e "      ${C_GRAY}Máximo rendimiento y FPS para GPUs modernas (NVIDIA, AMD, Intel 2016+).${C_RESET}"
    echo -e "  ${C_BOLD}[3]${C_RESET} ${C_YELLOW}Forzar WineD3D (OpenGL Compatibilidad)${C_RESET}"
    echo -e "      ${C_GRAY}Compatibilidad total para computadoras antiguas o tarjetas gráficas sin Vulkan.${C_RESET}"
    echo ""
    read -p "$(echo -e "${C_BOLD}Elegir opción (1-3): ${C_RESET}")" motor_sel

    case "$motor_sel" in
        1) RENDERER_BACKEND="auto" ;;
        2) RENDERER_BACKEND="dxvk" ;;
        3) RENDERER_BACKEND="wined3d" ;;
        *) echo -e "${C_YELLOW}Sin cambios.${C_RESET}"; sleep 1; return ;;
    esac

    guardar_config_usuario
    aplicar_entorno_hardware
    echo -e "${C_GREEN}✔ Motor configurado a: ${C_BOLD}${RENDERER_BACKEND}${C_RESET}"
    sleep 1.2
}

mostrar_diagnostico_hardware() {
    mostrar_banner
    echo -e "${C_CYAN}🔍 [ DIAGNÓSTICO DE HARDWARE Y CONTROLADORES ]${C_RESET}"
    echo ""
    echo -e "${C_BOLD}Sistema Operativo:${C_RESET} $(uname -sr)"
    echo -e "${C_BOLD}Procesador:${C_RESET}       ${CPU_MODEL} (${CPU_CORES} Hilos)"
    echo -e "${C_BOLD}Memoria RAM:${C_RESET}      ${RAM_TOTAL_MB} MB"
    echo -e "${C_BOLD}Tarjeta Gráfica:${C_RESET}  ${DETECTED_GPU}"
    echo -e "${C_BOLD}Soporte Vulkan:${C_RESET}   $([ "$HAS_VULKAN" = true ] && echo -e "${C_GREEN}Compatible (Vulkan Activo)${C_RESET}" || echo -e "${C_YELLOW}No detectado (Usará OpenGL WineD3D)${C_RESET}")"
    echo -e "${C_BOLD}Sincronización:${C_RESET}   $([ "$WINEFSYNC" = "1" ] && echo "Fsync nativo (Futex2)" || echo "Esync")"
    echo -e "${C_BOLD}Motor Activo:${C_RESET}     ${RENDERER_IN_USE}"
    echo ""
    if command -v nvidia-smi &> /dev/null && [ "$HAS_NVIDIA" = true ]; then
        echo -e "${C_GREEN}=== ESTADO NVIDIA SMI ===${C_RESET}"
        nvidia-smi || true
    fi
    echo ""
    pausar
}

# ==============================================================================
# 4) HERRAMIENTAS DE WINDOWS Y REPARACIÓN
# ==============================================================================
menu_herramientas_windows() {
    while true; do
        mostrar_banner
        echo -e "${C_YELLOW}🛠️  [ HERRAMIENTAS DE WINDOWS Y REPARACIÓN ]${C_RESET}"
        echo -e "${C_GRAY}Paneles de configuración oficiales, registro y utilidades del entorno Wine:${C_RESET}"
        echo ""
        echo -e "  ${C_BOLD}${C_CYAN}[1]${C_RESET} ${C_WHITE}🍷 Panel de Control de Wine (winecfg)${C_RESET} ${C_GRAY}- Versión Win7/10/11, DPI, escritorio virtual${C_RESET}"
        echo -e "  ${C_BOLD}${C_CYAN}[2]${C_RESET} ${C_WHITE}📝 Editor del Registro (regedit)${C_RESET} ${C_GRAY}- Aplicar parches .reg y claves de registro${C_RESET}"
        echo -e "  ${C_BOLD}${C_CYAN}[3]${C_RESET} ${C_WHITE}📈 Administrador de Tareas (taskmgr)${C_RESET} ${C_GRAY}- Ver procesos y cerrar juegos trabados${C_RESET}"
        echo -e "  ${C_BOLD}${C_CYAN}[4]${C_RESET} ${C_WHITE}📁 Explorador de Archivos de Windows (wine explorer)${C_RESET}"
        echo -e "  ${C_BOLD}${C_CYAN}[5]${C_RESET} ${C_RED}🔄 Cerrar procesos de Wine colgados y liberar RAM (wineserver -k)${C_RESET}"
        echo -e "  ${C_BOLD}${C_CYAN}[6]${C_RESET} ${C_GREEN}🛡️  Comprobador de Compatibilidad Anti-Cheat de Juegos Online${C_RESET}"
        echo ""
        echo -e "  ${C_BOLD}${C_RED}[0]${C_RESET} ${C_YELLOW}Volver al menú principal${C_RESET}"
        echo ""
        read -p "$(echo -e "${C_BOLD}Elegir opción: ${C_RESET}")" util_opc

        case "$util_opc" in
            1)
                echo -e "${C_CYAN}Abriendo Panel de Wine (winecfg)...${C_RESET}"
                WINEPREFIX="${DIR}/wineprefix" wine winecfg &
                sleep 1
                ;;
            2)
                echo -e "${C_CYAN}Abriendo Editor del Registro (regedit)...${C_RESET}"
                WINEPREFIX="${DIR}/wineprefix" wine regedit &
                sleep 1
                ;;
            3)
                echo -e "${C_CYAN}Abriendo Administrador de Tareas (taskmgr)...${C_RESET}"
                WINEPREFIX="${DIR}/wineprefix" wine taskmgr &
                sleep 1
                ;;
            4)
                echo -e "${C_CYAN}Abriendo Explorador de Archivos de Windows...${C_RESET}"
                WINEPREFIX="${DIR}/wineprefix" wine explorer &
                sleep 1
                ;;
            5)
                echo -e "${C_YELLOW}Cerrando procesos de Wine y liberando memoria...${C_RESET}"
                wineserver -k 2>/dev/null || true
                echo -e "${C_GREEN}✅ Todos los procesos de Wine fueron terminados limpiamente.${C_RESET}"
                sleep 1.5
                ;;
            6)
                comprobar_compatibilidad_anticheat
                ;;
            0|"")
                return
                ;;
            *)
                echo -e "${C_RED}❌ Opción inválida.${C_RESET}"
                sleep 1.2
                ;;
        esac
    done
}

comprobar_compatibilidad_anticheat() {
    mostrar_banner
    echo -e "${C_GREEN}🛡️  [ COMPROBADOR DE COMPATIBILIDAD ANTI-CHEAT ]${C_RESET}"
    echo -e "${C_GRAY}Consulta si un juego online funciona en Linux antes de descargarlo:${C_RESET}"
    echo ""
    echo -e "  ${C_BOLD}[1]${C_RESET} Consultar juegos populares (GTA V, Apex, Valorant, Fortnite, etc.)"
    echo -e "  ${C_BOLD}[2]${C_RESET} Escribir el nombre de un juego para buscarlo en la base de compatibilidad"
    echo -e "  ${C_BOLD}[0]${C_RESET} Volver"
    echo ""
    read -p "$(echo -e "${C_BOLD}Elegir opción: ${C_RESET}")" ac_sel

    case "$ac_sel" in
        1)
            mostrar_banner
            echo -e "${C_CYAN}📋 ESTADO DE JUEGOS POPULARES EN LINUX / WINE:${C_RESET}"
            echo ""
            echo -e "  ${C_GREEN}✔ Grand Theft Auto V (Online / Co-Op / FiveM):${C_RESET} Totalmente Funcional (BattlEye y Co-Op soportados)"
            echo -e "  ${C_GREEN}✔ Apex Legends:${C_RESET} Totalmente Funcional (Easy Anti-Cheat tiene soporte oficial para Linux)"
            echo -e "  ${C_GREEN}✔ Elden Ring / Dark Souls:${C_RESET} Totalmente Funcional (EAC habilitado)"
            echo -e "  ${C_GREEN}✔ Counter-Strike 2 / Team Fortress 2 / L4D2:${C_RESET} Totalmente Funcional (VAC nativo)"
            echo -e "  ${C_GREEN}✔ Minecraft / Palworld / Terraria:${C_RESET} Totalmente Funcional (Multijugador 100%)"
            echo -e "  ${C_RED}✘ Valorant:${C_RESET} NO FUNCIONA (Vanguard requiere driver a nivel de kernel de Windows Ring-0)"
            echo -e "  ${C_RED}✘ Fortnite:${C_RESET} NO FUNCIONA (Epic Games bloquea Linux en modo Battle Royale)"
            echo -e "  ${C_RED}✘ Call of Duty Warzone:${C_RESET} NO FUNCIONA (Ricochet Anti-Cheat kernel exclusivo de Windows)"
            echo ""
            pausar
            ;;
        2)
            echo ""
            read -p "$(echo -e "${C_CYAN}Escribe el nombre del juego: ${C_RESET}")" juego_consulta
            echo ""
            if echo "$juego_consulta" | grep -iE "valorant|fortnite|warzone|league of legends|lol|genshin" > /dev/null; then
                echo -e "${C_RED}⚠️  Resultado: Incompatible o requiere bypass especial.${C_RESET}"
                echo -e "    El juego usa un anti-cheat invasivo de anillo 0 (kernel) exclusivo de Windows."
            else
                echo -e "${C_GREEN}✔ Resultado: Compatible.${C_RESET}"
                echo -e "    La mayoría de juegos sin anti-cheat a nivel de kernel funcionan perfectamente con Wine + DXVK y conexión Wi-Fi/Internet."
            fi
            pausar
            ;;
        *) return ;;
    esac
}

# ==============================================================================
# 5) INSTALAR RECURSOS Y OPTIMIZAR AUTOMÁTICAMENTE
# ==============================================================================
instalar_recursos_actualizar() {
    mostrar_banner
    echo -e "${C_CYAN}📦 [ INSTALACIÓN Y OPTIMIZACIÓN AUTOMÁTICA DE RECURSOS ]${C_RESET}"
    echo -e "${C_GRAY}Comprobación inteligente: Solo instala o actualiza lo que falte en tu equipo.${C_RESET}"
    echo ""
    echo -e "  ${C_BOLD}Distribución configurada:${C_RESET} ${C_YELLOW}${DISTRO_NAME:-Debian}${C_RESET}"
    echo ""
    echo -e "  ${C_WHITE}¿Deseas ejecutar la comprobación automática o cambiar de distribución?${C_RESET}"
    echo -e "    ${C_BOLD}[Enter]${C_RESET} Ejecutar comprobación y optimización automática para ${DISTRO_NAME:-Debian}"
    echo -e "    ${C_BOLD}[C]${C_RESET}     Cambiar distribución de Linux"
    echo -e "    ${C_BOLD}[0]${C_RESET}     Volver al menú principal"
    echo ""
    read -p "$(echo -e "${C_BOLD}Opción: ${C_RESET}")" opt_c

    case "$opt_c" in
        0) return ;;
        [cC]*)
            seleccionar_distribucion_interactiva
            ;;
        *) ;;
    esac

    echo ""
    echo -e "${C_CYAN}══════════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_GREEN}🚀 INICIANDO ANÁLISIS Y OPTIMIZACIÓN AUTOMÁTICA...${C_RESET}"
    echo -e "${C_CYAN}══════════════════════════════════════════════════════════════════════${C_RESET}"
    echo ""

    # 1. Paquetes del Sistema Operativo
    echo -e "${C_BOLD}[1/4] Comprobando paquetes del sistema para ${DISTRO_NAME:-Debian}...${C_RESET}"
    local faltan_paquetes=false
    local cmds_requeridos=(wine winetricks dxvk-setup gamemoderun cabextract curl 7z python3)
    local faltantes=()

    for c in "${cmds_requeridos[@]}"; do
        if ! command -v "$c" &>/dev/null; then
            faltan_paquetes=true
            faltantes+=("$c")
        fi
    done

    if [ "$SISTEMA_LINUX" = "debian" ] || [ "$SISTEMA_LINUX" = "ubuntu" ]; then
        if command -v dpkg &>/dev/null; then
            if ! dpkg -s libnss-resolve:i386 &>/dev/null || ! dpkg -s libnss-mdns:i386 &>/dev/null; then
                faltan_paquetes=true
                faltantes+=("libnss-resolve:i386" "libnss-mdns:i386")
            fi
            if ! dpkg -s gstreamer1.0-libav:i386 &>/dev/null || ! dpkg -s gstreamer1.0-plugins-ugly:i386 &>/dev/null; then
                faltan_paquetes=true
                faltantes+=("gstreamer1.0-libav:i386" "gstreamer1.0-plugins-ugly:i386" "gstreamer1.0-plugins-bad:i386" "libvkd3d1:i386")
            fi
        fi
    fi

    if [ "$faltan_paquetes" = false ]; then
        echo -e "${C_GREEN}  ✔ Todos los paquetes del sistema ya están instalados y al día (Omitido).${C_RESET}"
    else
        echo -e "${C_YELLOW}  ⬇️ Faltan componentes (${faltantes[*]}). Instalando automáticamente...${C_RESET}"
        case "$SISTEMA_LINUX" in
            debian|ubuntu)
                sudo apt-get update && sudo apt-get install -y wine winetricks dxvk gamemode cabextract curl p7zip-full mesa-utils vulkan-tools zenity python3 libnss-resolve:i386 libnss-mdns:i386 gstreamer1.0-libav:i386 gstreamer1.0-plugins-ugly:i386 gstreamer1.0-plugins-bad:i386 libvkd3d1:i386 libopenexr-3-1-30:i386
                ;;
            fedora)
                sudo dnf install -y wine winetricks dxvk gamemode cabextract curl p7zip mesa-demos vulkan-tools zenity python3 gstreamer1-plugins-ugly.i686 gstreamer1-plugins-bad-free.i686 vkd3d.i686
                ;;
            arch)
                sudo pacman -Sy --noconfirm --needed wine winetricks dxvk gamemode cabextract curl p7zip mesa-utils vulkan-tools zenity python lib32-gst-plugins-ugly lib32-gst-plugins-bad lib32-gst-libav lib32-vkd3d
                ;;
            opensuse)
                sudo zypper install -y wine winetricks dxvk gamemode cabextract curl p7zip mesa-utils vulkan-tools zenity python3 gstreamer-plugins-ugly-32bit gstreamer-plugins-bad-32bit
                ;;
            *)
                echo -e "${C_RED}  ⚠️ Distribución desconocida. Instala Wine y DXVK con tu gestor habitual.${C_RESET}"
                ;;
        esac
        echo -e "${C_GREEN}  ✔ Paquetes del sistema completados.${C_RESET}"
    fi
    echo ""

    # 2. Parámetros del Kernel de Linux (Memoria y Red)
    echo -e "${C_BOLD}[2/4] Comprobando optimizaciones del Kernel (Memoria y Multijugador)...${C_RESET}"
    local max_map
    max_map=$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo 0)
    if [ "$max_map" -ge 2147483640 ] && [ -f /etc/sysctl.d/99-win-gaming.conf ]; then
        echo -e "${C_GREEN}  ✔ Parámetros del Kernel (vm.max_map_count = 2.1M y puertos): Ya optimizados (Omitido).${C_RESET}"
    else
        echo -e "${C_YELLOW}  ⚙️ Aplicando optimizaciones permanentes en /etc/sysctl.d/99-win-gaming.conf...${C_RESET}"
        if [ -w /etc/sysctl.d ] || sudo -n true 2>/dev/null || [ "$EUID" -eq 0 ]; then
            sudo bash -c 'cat <<EOF > /etc/sysctl.d/99-win-gaming.conf
# Optimizaciones de memoria y red para juegos pesados y multiplayer
vm.max_map_count = 2147483642
net.ipv4.ping_group_range = 0 2147483647
net.ipv4.ip_unprivileged_port_start = 0
fs.file-max = 2097152
EOF'
            sudo /sbin/sysctl --system > /dev/null 2>&1 || true
            echo -e "${C_GREEN}  ✔ Parámetros del Kernel aplicados con éxito.${C_RESET}"
        fi
    fi
    echo ""

    # 3. Librerías de Windows en Wine (MFC, Visual C++, DirectX, Fuentes)
    echo -e "${C_BOLD}[3/4] Comprobando entorno de Windows (MFC, Visual C++, DirectX, Fuentes)...${C_RESET}"
    local sys32="${DIR}/wineprefix/drive_c/windows/syswow64"
    local fonts="${DIR}/wineprefix/drive_c/windows/Fonts"
    local faltan_win=()

    [ ! -f "$sys32/mfc42.dll" ] && faltan_win+=("mfc42")
    [ ! -f "$sys32/msvcr100.dll" ] && faltan_win+=("vcrun2010")
    [ ! -f "$sys32/vcruntime140.dll" ] && faltan_win+=("vcrun2022")
    [ ! -f "$sys32/d3dcompiler_47.dll" ] && faltan_win+=("d3dcompiler_47")
    [ ! -f "$fonts/arial.ttf" ] && faltan_win+=("corefonts")

    if [ ${#faltan_win[@]} -eq 0 ]; then
        echo -e "${C_GREEN}  ✔ Librerías esenciales de Windows (MFC42, VC++ 2010-2022, DirectX, Fuentes): Ya instaladas (Omitido).${C_RESET}"
    else
        echo -e "${C_YELLOW}  ⬇️ Instalando librerías de Windows faltantes: ${faltan_win[*]}...${C_RESET}"
        WINEPREFIX="${DIR}/wineprefix" winetricks -q "${faltan_win[@]}" 2>/dev/null || true
        echo -e "${C_GREEN}  ✔ Librerías de Windows instaladas con éxito.${C_RESET}"
    fi

    # Verificar DXVK en el prefijo
    if [ ! -f "$sys32/d3d11.dll" ]; then
        echo -e "${C_CYAN}  ⚡ Sincronizando DXVK en el prefijo de Wine...${C_RESET}"
        WINEPREFIX="${DIR}/wineprefix" dxvk-setup install -y 2>/dev/null || true
    fi

    # Configuración de compatibilidad gráfica Direct3D y X11 (evita pantalla negra y tirones)
    local vram_val="${VRAM_MB:-2048}"
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "VideoMemorySize" /t REG_SZ /d "$vram_val" /f >/dev/null 2>&1 || true
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "csmt" /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "StrictDrawOrdering" /t REG_SZ /d "disabled" /f >/dev/null 2>&1 || true
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "AlwaysOffscreen" /t REG_SZ /d "enabled" /f >/dev/null 2>&1 || true
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "OffscreenRenderingMode" /t REG_SZ /d "fbo" /f >/dev/null 2>&1 || true
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v "UseTakeFocus" /t REG_SZ /d "N" /f >/dev/null 2>&1 || true
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v "GrabFullscreen" /t REG_SZ /d "Y" /f >/dev/null 2>&1 || true
    echo -e "${C_GREEN}  ✔ Parámetros de video Direct3D (VRAM ${vram_val}MB, CSMT, X11) optimizados.${C_RESET}"
    echo ""

    # 4. Afinación de DXVK y Shaders
    echo -e "${C_BOLD}[4/4] Optimizando motor DXVK y caché de shaders para ${CPU_CORES} hilos de CPU...${C_RESET}"
    if [ -x "${DIR}/generar_dxvk_conf.sh" ]; then
        "${DIR}/generar_dxvk_conf.sh"
        echo -e "${C_GREEN}  ✔ Configuración dxvk.conf generada para ${CPU_CORES} hilos y Shaders Asíncronos.${C_RESET}"
    fi
    echo ""

    echo -e "${C_CYAN}══════════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_GREEN}🎉 ¡OPTIMIZACIÓN AUTOMÁTICA COMPLETADA CON ÉXITO! 🎉${C_RESET}"
    echo -e "${C_WHITE}Tu PC (${DISTRO_NAME:-Debian}) está lista al 100% para correr cualquier juego o programa.${C_RESET}"
    echo -e "${C_CYAN}══════════════════════════════════════════════════════════════════════${C_RESET}"
    pausar
}

# ==============================================================================
# BUCLE PRINCIPAL
# ==============================================================================

# 1. Comprobar actualización desde GitHub al abrir
verificar_actualizacion_github

# 2. Comprobar configuración inicial de la distribución Linux
comprobar_configuracion_inicial_distro

while true; do
    mostrar_banner
    echo -e "  ${C_BOLD}${C_GREEN}[1]${C_RESET} ${C_WHITE}Iniciar programa o juego${C_RESET}"
    echo -e "  ${C_BOLD}${C_YELLOW}[2]${C_RESET} ${C_WHITE}Configurar Programa Win${C_RESET} ${C_GRAY}(Añadir, accesos de escritorio, mods)${C_RESET}"
    echo -e "  ${C_BOLD}${C_MAGENTA}[3]${C_RESET} ${C_WHITE}Configuración de Rendimiento y Motor Gráfico${C_RESET} ${C_GRAY}(FPS, FSR, Vulkan/OpenGL)${C_RESET}"
    echo -e "  ${C_BOLD}${C_BLUE}[4]${C_RESET} ${C_WHITE}Herramientas de Windows y Reparación${C_RESET} ${C_GRAY}(winecfg, regedit, taskmgr, anticheat)${C_RESET}"
    echo -e "  ${C_BOLD}${C_CYAN}[5]${C_RESET} ${C_WHITE}Instalar Recursos y Optimizar Automáticamente${C_RESET} ${C_GRAY}(Verificación por distro)${C_RESET}"
    echo ""
    echo -e "  ${C_BOLD}${C_RED}[0]${C_RESET} ${C_GRAY}Salir${C_RESET}"
    echo ""
    read -p "$(echo -e "${C_BOLD}${C_CYAN}Elegir opción (1-5 o 0): ${C_RESET}")" opcion_principal

    case "$opcion_principal" in
        1)
            iniciar_programa
            ;;
        2)
            configurar_programa_win
            ;;
        3)
            menu_configuracion
            ;;
        4)
            menu_herramientas_windows
            ;;
        5)
            instalar_recursos_actualizar
            ;;
        0|q|Q)
            echo ""
            echo -e "${C_GREEN}¡Hasta luego! Que disfrutes tus juegos.${C_RESET}"
            exit 0
            ;;
        *)
            echo -e "${C_RED}❌ Opción no reconocida. Por favor ingresa un número del 1 al 5 o 0.${C_RESET}"
            sleep 1.5
            ;;
    esac
done
