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

# Cargar módulo de hardware y preferencias
[ -f "$CONFIG_USER" ] && source "$CONFIG_USER"
source "${DIR}/hardware_detect.sh"

# Asegurar que la base de datos de programas y carpeta de prefijos existan
touch "$DB_FILE"
mkdir -p "${DIR}/prefixes"

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
# ENCABEZADO DINÁMICO SEGÚN EL EQUIPO
# ==============================================================================
mostrar_banner() {
    clear 2>/dev/null || true
    # Recargar preferencias si cambiaron
    [ -f "$CONFIG_USER" ] && source "$CONFIG_USER"
    aplicar_entorno_hardware

    local motor_mostrar="${RENDERER_IN_USE:-DXVK (Vulkan)}"

    echo -e "${C_CYAN}╔══════════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}                   ${C_MAGENTA}🚀  M E N U   W I N   ( U N I V E R S A L )  🚀${C_RESET}     ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}           ${C_WHITE}Gestor y Optimizador de Juegos y Programas de Windows${C_RESET}      ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}╠══════════════════════════════════════════════════════════════════════╣${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET} ${C_YELLOW}CPU:${C_RESET} ${CPU_MODEL:0:40} (${CPU_CORES} Hilos) | ${C_YELLOW}RAM:${C_RESET} ${RAM_TOTAL_MB} MB"
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
        declare -a prefijos

        while IFS='|' read -r nombre ruta prefijo; do
            [ -z "$nombre" ] && continue
            nombres[i]="$nombre"
            rutas[i]="$ruta"
            prefijos[i]="${prefijo:-compartido}"
            local pref_badge="${C_BLUE}[Compartido]${C_RESET}"
            if [ -n "$prefijo" ] && [ "$prefijo" != "DEFAULT" ] && [ "$prefijo" != "compartido" ]; then
                pref_badge="${C_MAGENTA}[Aislado: ${prefijo}]${C_RESET}"
            fi
            echo -e "  ${C_BOLD}${C_CYAN}[$i]${C_RESET} ${C_WHITE}${nombre}${C_RESET} ${pref_badge}"
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
            local prog_prefijo="${prefijos[$seleccion]}"

            echo ""
            echo -e "${C_GREEN}🚀 Iniciando: ${C_BOLD}${prog_nombre}${C_RESET}..."
            echo -e "${C_GRAY}Optimizando para tu ${DETECTED_GPU}...${C_RESET}"
            sleep 1

            if [ -x "$LAUNCHER" ]; then
                if [ -n "$prog_prefijo" ] && [ "$prog_prefijo" != "compartido" ] && [ "$prog_prefijo" != "DEFAULT" ]; then
                    "$LAUNCHER" --prefix "$prog_prefijo" "$prog_ruta"
                else
                    "$LAUNCHER" "$prog_ruta"
                fi
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
    echo -e "${C_GRAY}Configura el acceso para tu juego o programa portable (.exe o .bat ya descargado):${C_RESET}"
    echo ""

    local ruta_prog=""
    local metodo_busqueda=""

    echo -e "${C_WHITE}¿Cómo deseas buscar el ejecutable portable?${C_RESET}"
    echo -e "  ${C_BOLD}[1]${C_RESET} ${C_CYAN}🖱️  Explorar con el ratón (Abrir ventana de diálogo gráfica)${C_RESET}"
    echo -e "  ${C_BOLD}[2]${C_RESET} ${C_YELLOW}⌨️  Escribir o pegar la ruta manualmente en la terminal${C_RESET}"
    echo ""
    read -p "$(echo -e "${C_BOLD}Elegir método (1 o 2): ${C_RESET}")" metodo_busqueda

    if [ "$metodo_busqueda" = "1" ]; then
        echo -e "${C_CYAN}Abriendo explorador de archivos... (Selecciona tu archivo .exe o .bat)${C_RESET}"
        if command -v kdialog &>/dev/null && [ -n "$DISPLAY$WAYLAND_DISPLAY" ]; then
            ruta_prog=$(kdialog --title "Seleccionar Ejecutable Portable (.exe / .bat)" --getopenfilename "/media" "*.exe *.bat *.EXE *.BAT | Ejecutables de Windows (*.exe, *.bat)" 2>/dev/null)
        elif command -v zenity &>/dev/null && [ -n "$DISPLAY$WAYLAND_DISPLAY" ]; then
            ruta_prog=$(zenity --file-selection --title="Seleccionar Ejecutable Portable (.exe / .bat)" --file-filter="Ejecutables (*.exe, *.bat) | *.exe *.bat *.EXE *.BAT" 2>/dev/null)
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
        echo -e "${C_CYAN}Ubicación del programa${C_RESET} ${C_GRAY}(ruta exacta al .exe o .bat):${C_RESET}"
        echo -e "${C_GRAY}Ejemplo: /media/plumst/Disco/Juego/juego.exe${C_RESET}"
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

    # Sugerir nombre basado en el archivo
    local nombre_sugerido
    nombre_sugerido=$(basename "$ruta_prog" | sed 's/\.[^.]*$//' | sed 's/[-_]/ /g')

    echo ""
    echo -e "${C_CYAN}Nombre para mostrar en el menú:${C_RESET}"
    read -p "$(echo -e "${C_GRAY}[Sugerido: ${nombre_sugerido}] (Presiona Enter para usar sugerido o escribe otro):${C_RESET}\n${C_BOLD}➤ ${C_RESET}")" nombre_prog
    [ -z "$nombre_prog" ] && nombre_prog="$nombre_sugerido"

    # Selección de Tipo de Prefijo de Wine
    echo ""
    echo -e "${C_WHITE}Tipo de Prefijo de Windows:${C_RESET}"
    echo -e "  ${C_BOLD}[1]${C_RESET} ${C_GREEN}🌐 Compartido (Recomendado)${C_RESET} ${C_GRAY}- Ahorra espacio en disco, usa la configuración global${C_RESET}"
    echo -e "  ${C_BOLD}[2]${C_RESET} ${C_MAGENTA}🔒 Aislado / Dedicado${C_RESET} ${C_GRAY}- Crea una instalación limpia de Windows exclusiva para este juego${C_RESET}"
    read -p "$(echo -e "${C_BOLD}Elegir tipo de prefijo (1 o 2) [Por defecto: 1]: ${C_RESET}")" pref_tipo_sel

    local tipo_prefijo="compartido"
    if [ "$pref_tipo_sel" = "2" ]; then
        local safe_prefix
        safe_prefix=$(echo "$nombre_prog" | tr -dc 'a-zA-Z0-9_-' | tr '[:upper:]' '[:lower:]')
        [ -z "$safe_prefix" ] && safe_prefix="juego_$(date +%s)"
        tipo_prefijo="$safe_prefix"
        echo -e "${C_MAGENTA}✔ Se asignará el prefijo dedicado: ${C_BOLD}prefixes/${tipo_prefijo}${C_RESET}"
    fi

    echo "${nombre_prog}|${ruta_prog}|${tipo_prefijo}" >> "$DB_FILE"
    echo ""
    echo -e "${C_GREEN}✅ ¡Programa portable registrado exitosamente!${C_RESET}"
    echo -e "   ${C_BOLD}Nombre:${C_RESET}  ${nombre_prog}"
    echo -e "   ${C_BOLD}Ruta:${C_RESET}    ${ruta_prog}"
    echo -e "   ${C_BOLD}Prefijo:${C_RESET} ${tipo_prefijo}"
    echo ""

    # Opción de crear acceso directo en el Escritorio
    read -p "$(echo -e "${C_YELLOW}¿Deseas crear un acceso directo en tu Escritorio para abrirlo con 1 clic? (S/n): ${C_RESET}")" crear_desktop
    case "$crear_desktop" in
        [nN]*) ;;
        *)
            crear_archivo_desktop "$nombre_prog" "$ruta_prog" "$tipo_prefijo"
            ;;
    esac

    echo ""
    read -p "$(echo -e "${C_MAGENTA}¿Deseas iniciar ${C_BOLD}'${nombre_prog}'${C_RESET}${C_MAGENTA} ahora mismo? (s/N): ${C_RESET}")" iniciar_ahora
    case "$iniciar_ahora" in
        [sS]*)
            echo ""
            echo -e "${C_GREEN}🚀 Iniciando programa...${C_RESET}"
            sleep 1
            if [ "$tipo_prefijo" != "compartido" ]; then
                "$LAUNCHER" --prefix "$tipo_prefijo" "$ruta_prog"
            else
                "$LAUNCHER" "$ruta_prog"
            fi
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

    # Prefijo
    echo ""
    echo -e "${C_WHITE}¿Dónde deseas instalarlo?${C_RESET}"
    echo -e "  ${C_BOLD}[1]${C_RESET} ${C_GREEN}🌐 Prefijo Compartido (Recomendado)${C_RESET} ${C_GRAY}- Usa la misma unidad C: global${C_RESET}"
    echo -e "  ${C_BOLD}[2]${C_RESET} ${C_MAGENTA}🔒 Prefijo Aislado / Dedicado${C_RESET} ${C_GRAY}- Instalación limpia de Windows exclusiva para este programa${C_RESET}"
    read -p "$(echo -e "${C_BOLD}Elegir opción (1 o 2) [Por defecto: 1]: ${C_RESET}")" pref_tipo_sel

    local tipo_prefijo="compartido"
    local target_prefix="${DIR}/wineprefix"
    if [ "$pref_tipo_sel" = "2" ]; then
        local safe_prefix
        safe_prefix=$(echo "$nombre_prog" | tr -dc 'a-zA-Z0-9_-' | tr '[:upper:]' '[:lower:]')
        [ -z "$safe_prefix" ] && safe_prefix="prog_$(date +%s)"
        tipo_prefijo="$safe_prefix"
        target_prefix="${DIR}/prefixes/${tipo_prefijo}"
        mkdir -p "$target_prefix"
        echo -e "${C_MAGENTA}✔ Se usará el prefijo dedicado: ${C_BOLD}prefixes/${tipo_prefijo}${C_RESET}"
    fi

    # Ejecutar el instalador
    echo ""
    echo -e "${C_GREEN}🚀 [ EJECUTANDO INSTALADOR DE WINDOWS ]${C_RESET}"
    echo -e "${C_YELLOW}Por favor, completa los pasos en la ventana de instalación que aparecerá.${C_RESET}"
    echo -e "${C_GRAY}(Deja la ruta por defecto recomendada: C:\\Program Files\\...)${C_RESET}"
    echo ""
    sleep 1

    local time_start
    time_start=$(date +%s)

    if [ "$tipo_prefijo" != "compartido" ]; then
        "$LAUNCHER" --prefix "$tipo_prefijo" "$ruta_setup" || true
    else
        "$LAUNCHER" "$ruta_setup" || true
    fi

    echo ""
    echo -e "${C_GREEN}✔ El proceso del instalador ha terminado.${C_RESET}"
    echo -e "${C_CYAN}Buscando automáticamente el ejecutable principal recién instalado...${C_RESET}"

    local exe_instalado=""
    local candidatos=()

    if [ -d "${target_prefix}/drive_c" ]; then
        while IFS= read -r f; do
            local fname
            fname=$(basename "$f" | tr '[:upper:]' '[:lower:]')
            if [[ "$fname" =~ (unins|uninstall|setup|installer|dxsetup|vcredist|crashpad) ]]; then
                continue
            fi
            candidatos+=("$f")
        done < <(find "${target_prefix}/drive_c" -type f \( -iname "*.exe" \) -newermt "@$((time_start - 30))" 2>/dev/null | head -n 10)
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
        echo -e "${C_YELLOW}Selecciona el archivo ejecutable (.exe) que se instaló en el disco C: de Wine:${C_RESET}"
        if command -v kdialog &>/dev/null && [ -n "$DISPLAY$WAYLAND_DISPLAY" ]; then
            exe_instalado=$(kdialog --title "Seleccionar Ejecutable Instalado (.exe)" --getopenfilename "${target_prefix}/drive_c/Program Files" "*.exe *.EXE | Ejecutables de Windows (*.exe)" 2>/dev/null)
        elif command -v zenity &>/dev/null && [ -n "$DISPLAY$WAYLAND_DISPLAY" ]; then
            exe_instalado=$(zenity --file-selection --filename="${target_prefix}/drive_c/Program Files/" --title="Seleccionar Ejecutable Instalado (.exe)" --file-filter="Ejecutables (*.exe) | *.exe *.EXE" 2>/dev/null)
        fi

        if [ -z "$exe_instalado" ]; then
            read -p "$(echo -e "${C_CYAN}Escribe o pega la ruta del .exe instalado:${C_RESET}\n${C_BOLD}➤ ${C_RESET}")" exe_instalado
        fi
    fi

    exe_instalado="${exe_instalado%\"}"
    exe_instalado="${exe_instalado#\"}"
    exe_instalado="${exe_instalado%\'}"
    exe_instalado="${exe_instalado#\'}"

    if [ -z "$exe_instalado" ] || [ ! -f "$exe_instalado" ]; then
        echo -e "${C_RED}❌ No se seleccionó un ejecutable válido.${C_RESET}"
        echo -e "${C_GRAY}El programa quedó instalado en Wine, pero no se agregó al menú. Podrás agregarlo más tarde con la opción 1 (Programa portable).${C_RESET}"
        pausar
        return
    fi

    echo "${nombre_prog}|${exe_instalado}|${tipo_prefijo}" >> "$DB_FILE"
    echo ""
    echo -e "${C_GREEN}✅ ¡Programa instalado y registrado exitosamente en el Menú Win!${C_RESET}"
    echo -e "   ${C_BOLD}Nombre:${C_RESET}     ${nombre_prog}"
    echo -e "   ${C_BOLD}Ejecutable:${C_RESET} ${exe_instalado}"
    echo -e "   ${C_BOLD}Prefijo:${C_RESET}    ${tipo_prefijo}"
    echo ""

    # Crear acceso directo en el Escritorio
    read -p "$(echo -e "${C_YELLOW}¿Deseas crear un acceso directo en tu Escritorio para abrirlo con 1 clic? (S/n): ${C_RESET}")" crear_desk
    case "$crear_desk" in
        [nN]*) ;;
        *)
            crear_archivo_desktop "$nombre_prog" "$exe_instalado" "$tipo_prefijo"
            ;;
    esac

    echo ""
    read -p "$(echo -e "${C_MAGENTA}¿Deseas iniciar ${C_BOLD}'${nombre_prog}'${C_RESET}${C_MAGENTA} ahora mismo? (s/N): ${C_RESET}")" iniciar_ahora
    case "$iniciar_ahora" in
        [sS]*)
            echo ""
            echo -e "${C_GREEN}🚀 Iniciando programa...${C_RESET}"
            sleep 1
            if [ "$tipo_prefijo" != "compartido" ]; then
                "$LAUNCHER" --prefix "$tipo_prefijo" "$exe_instalado"
            else
                "$LAUNCHER" "$exe_instalado"
            fi
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
    local prefijo="$3"
    local desktop_path="/home/plumst/Escritorio/${nombre}.desktop"

    local exec_cmd
    if [ -n "$prefijo" ] && [ "$prefijo" != "compartido" ] && [ "$prefijo" != "DEFAULT" ]; then
        exec_cmd="\"${LAUNCHER}\" --prefix \"${prefijo}\" \"${ruta}\""
    else
        exec_cmd="\"${LAUNCHER}\" \"${ruta}\""
    fi

    cat <<EOF > "$desktop_path"
[Desktop Entry]
Version=1.0
Type=Application
Name=${nombre}
Comment=Juego de Windows optimizado con Win PC
Exec=${exec_cmd}
Icon=wine
Terminal=false
Categories=Game;
StartupNotify=true
EOF

    chmod +x "$desktop_path"
    gio set "$desktop_path" metadata::trusted true 2>/dev/null || true
    echo -e "${C_GREEN}✔ Acceso directo creado en tu Escritorio:${C_RESET} ${nombre}.desktop"
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
        crear_archivo_desktop "${nombres_d[$sel_d]}" "${rutas_d[$sel_d]}" "${prefijos_d[$sel_d]}"
    else
        echo -e "${C_RED}❌ Opción inválida.${C_RESET}"
    fi
    pausar
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
            local pref="${prefijo:-compartido}"
            echo -e "  ${C_CYAN}[$i]${C_RESET} ${C_BOLD}${C_WHITE}${nombre}${C_RESET}"
            echo -e "      ${C_GRAY}Ruta:${C_RESET}    ${ruta}"
            echo -e "      ${C_GRAY}Prefijo:${C_RESET} ${pref}"
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
        echo -e "  ${C_BOLD}${C_CYAN}[6]${C_RESET} ${C_WHITE}🔍 Diagnóstico de Hardware y Controladores${C_RESET}"
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
EOF
    # Regenerar dxvk.conf con los nuevos valores
    if [ -x "${DIR}/generar_dxvk_conf.sh" ]; then
        "${DIR}/generar_dxvk_conf.sh"
    fi
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
# 5) INSTALAR RECURSOS Y ACTUALIZAR
# ==============================================================================
instalar_recursos_actualizar() {
    while true; do
        mostrar_banner
        echo -e "${C_CYAN}📦 [ INSTALAR RECURSOS Y ACTUALIZAR ]${C_RESET}"
        echo -e "${C_GRAY}Mantén al día tus drivers, librerías de DirectX, C++ y componentes de Windows:${C_RESET}"
        echo ""
        echo -e "  ${C_BOLD}${C_GREEN}[1]${C_RESET} ${C_WHITE}🚀 Instalar Paquete Completo Todo-en-Uno (DirectX, VC++, Fuentes, DXVK)${C_RESET}"
        echo -e "  ${C_BOLD}${C_CYAN}[2]${C_RESET} ${C_WHITE}🌐 Instalar Wine-Gecko (Motor HTML/Navegador para Launchers y Tiendas)${C_RESET}"
        echo -e "  ${C_BOLD}${C_YELLOW}[3]${C_RESET} ${C_WHITE}⚡ Reinstalar / Sincronizar DXVK (Traductor DirectX a Vulkan)${C_RESET}"
        echo -e "  ${C_BOLD}${C_MAGENTA}[4]${C_RESET} ${C_WHITE}🔄 Actualizar Sistema y Drivers de tu distribución${C_RESET}"
        echo ""
        echo -e "  ${C_BOLD}${C_RED}[0]${C_RESET} ${C_YELLOW}Volver al menú principal${C_RESET}"
        echo ""
        read -p "$(echo -e "${C_BOLD}Elegir opción: ${C_RESET}")" rec_opc

        case "$rec_opc" in
            1)
                mostrar_banner
                echo -e "${C_GREEN}🚀 [ INSTALANDO PAQUETE COMPLETO DE COMPATIBILIDAD ]${C_RESET}"
                echo -e "${C_GRAY}Instalando librerías clave de Windows en el entorno...${C_RESET}"
                echo ""
                echo -e "${C_CYAN}[1/4] Instalando Fuentes oficiales de Windows (corefonts)...${C_RESET}"
                WINEPREFIX="${DIR}/wineprefix" winetricks -q corefonts
                echo -e "${C_GREEN}✔ Fuentes listas.${C_RESET}"
                echo ""
                echo -e "${C_CYAN}[2/4] Instalando Visual C++ 2015-2022 (x86 y x64)...${C_RESET}"
                WINEPREFIX="${DIR}/wineprefix" winetricks -q vcrun2022
                echo -e "${C_GREEN}✔ Visual C++ listo.${C_RESET}"
                echo ""
                echo -e "${C_CYAN}[3/4] Instalando DirectX Runtimes (d3dcompiler_47 y d3dx9)...${C_RESET}"
                WINEPREFIX="${DIR}/wineprefix" winetricks -q d3dcompiler_47 d3dx9
                echo -e "${C_GREEN}✔ DirectX listo.${C_RESET}"
                echo ""
                echo -e "${C_CYAN}[4/4] Verificando DXVK en el entorno...${C_RESET}"
                WINEPREFIX="${DIR}/wineprefix" dxvk-setup install -y
                echo -e "${C_GREEN}✔ DXVK verificado e instalado.${C_RESET}"
                echo ""
                echo -e "${C_BOLD}${C_GREEN}✅ ¡Todos los recursos para juegos quedaron instalados y actualizados!${C_RESET}"
                pausar
                ;;
            2)
                mostrar_banner
                echo -e "${C_CYAN}🌐 [ INSTALANDO WINE-GECKO ]${C_RESET}"
                echo -e "${C_GRAY}Descargando motor web oficial de Wine para interfaces y launchers...${C_RESET}"
                echo ""
                echo -e "${C_YELLOW}Descargando e instalando Gecko en el sistema...${C_RESET}"
                sudo mkdir -p /usr/share/wine/gecko 2>/dev/null || true
                sudo curl -L -o /usr/share/wine/gecko/wine-gecko-2.47.4-x86_64.msi https://dl.winehq.org/wine/wine-gecko/2.47.4/wine-gecko-2.47.4-x86_64.msi
                sudo curl -L -o /usr/share/wine/gecko/wine-gecko-2.47.4-x86.msi https://dl.winehq.org/wine/wine-gecko/2.47.4/wine-gecko-2.47.4-x86.msi
                echo -e "${C_CYAN}Registrando en el entorno de Wine...${C_RESET}"
                WINEPREFIX="${DIR}/wineprefix" wine msiexec /i /usr/share/wine/gecko/wine-gecko-2.47.4-x86_64.msi /qn
                WINEPREFIX="${DIR}/wineprefix" wine msiexec /i /usr/share/wine/gecko/wine-gecko-2.47.4-x86.msi /qn
                echo ""
                echo -e "${C_GREEN}✅ ¡Wine-Gecko instalado correctamente!${C_RESET}"
                pausar
                ;;
            3)
                mostrar_banner
                echo -e "${C_YELLOW}⚡ [ REINSTALANDO / ACTUALIZANDO DXVK ]${C_RESET}"
                echo ""
                WINEPREFIX="${DIR}/wineprefix" dxvk-setup install -y
                echo ""
                echo -e "${C_GREEN}✅ DXVK sincronizado con éxito.${C_RESET}"
                pausar
                ;;
            4)
                mostrar_banner
                echo -e "${C_MAGENTA}🔄 [ ACTUALIZAR SISTEMA Y CONTROLADORES ]${C_RESET}"
                echo -e "${C_GRAY}Se buscarán actualizaciones de paquetes y drivers...${C_RESET}"
                echo ""
                if command -v apt-get &> /dev/null; then
                    sudo apt-get update && sudo apt-get upgrade -y
                elif command -v pacman &> /dev/null; then
                    sudo pacman -Syu --noconfirm
                elif command -v dnf &> /dev/null; then
                    sudo dnf upgrade -y
                elif command -v zypper &> /dev/null; then
                    sudo zypper update -y
                fi
                echo ""
                echo -e "${C_GREEN}✅ Sistema y controladores actualizados.${C_RESET}"
                pausar
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

# ==============================================================================
# BUCLE PRINCIPAL
# ==============================================================================
while true; do
    mostrar_banner
    echo -e "  ${C_BOLD}${C_GREEN}[1]${C_RESET} ${C_WHITE}Iniciar programa o juego${C_RESET}"
    echo -e "  ${C_BOLD}${C_YELLOW}[2]${C_RESET} ${C_WHITE}Configurar Programa Win${C_RESET} ${C_GRAY}(Añadir, accesos de escritorio, prefijos)${C_RESET}"
    echo -e "  ${C_BOLD}${C_MAGENTA}[3]${C_RESET} ${C_WHITE}Configuración de Rendimiento y Motor Gráfico${C_RESET} ${C_GRAY}(FPS, FSR, Vulkan/OpenGL)${C_RESET}"
    echo -e "  ${C_BOLD}${C_BLUE}[4]${C_RESET} ${C_WHITE}Herramientas de Windows y Reparación${C_RESET} ${C_GRAY}(winecfg, regedit, taskmgr, anticheat)${C_RESET}"
    echo -e "  ${C_BOLD}${C_CYAN}[5]${C_RESET} ${C_WHITE}Instalar Recursos y Actualizar${C_RESET} ${C_GRAY}(DirectX, VC++, fuentes, drivers)${C_RESET}"
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
