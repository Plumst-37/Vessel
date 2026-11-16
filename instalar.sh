#!/bin/bash
# ==============================================================================
# INSTALADOR UNIVERSAL EN 1-CLIC PARA CUALQUIER COMPUTADORA CON LINUX
# Compatible con: Debian, Ubuntu, Mint, Arch, Manjaro, Fedora y OpenSUSE
# ==============================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# Colores
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_CYAN="\033[1;36m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[1;31m"

# Si se ejecuta mediante pipe (curl ... | bash), clonar automáticamente el repositorio
if [ ! -f "${DIR}/menu-win.sh" ]; then
    echo -e "${C_CYAN}╔══════════════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_CYAN}║${C_RESET}             ${C_GREEN}📦  INSTALADOR REMOTO DIRECTO - VESSEL 📦${C_RESET}               ${C_CYAN}║${C_RESET}"
    echo -e "${C_CYAN}╚══════════════════════════════════════════════════════════════════════╝${C_RESET}"
    echo ""
    TARGET_DIR="$HOME/Vessel"

    if ! command -v git &>/dev/null; then
        echo -e "${C_YELLOW}Instalando 'git' necesario para descargar el proyecto...${C_RESET}"
        if command -v apt-get &>/dev/null; then sudo apt-get update && sudo apt-get install -y git;
        elif command -v pacman &>/dev/null; then sudo pacman -Sy --noconfirm git;
        elif command -v dnf &>/dev/null; then sudo dnf install -y git;
        elif command -v zypper &>/dev/null; then sudo zypper install -y git; fi
    fi

    if [ ! -d "$TARGET_DIR/.git" ]; then
        echo -e "${C_GREEN}Clonando repositorio en: ${C_BOLD}${TARGET_DIR}${C_RESET}..."
        git clone https://github.com/Plumst-37/Vessel.git "$TARGET_DIR"
    else
        echo -e "${C_GREEN}Actualizando repositorio en: ${C_BOLD}${TARGET_DIR}${C_RESET}..."
        (cd "$TARGET_DIR" && git pull || true)
    fi

    exec bash "${TARGET_DIR}/instalar.sh" "$@"
fi

clear 2>/dev/null || true
echo -e "${C_CYAN}╔══════════════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_CYAN}║${C_RESET}             ${C_GREEN}📦  INSTALADOR UNIVERSAL - PROYECTO WIN  📦${C_RESET}              ${C_CYAN}║${C_RESET}"
echo -e "${C_CYAN}║${C_RESET}       ${C_BOLD}Configuración y optimización automática para cualquier PC${C_RESET}      ${C_CYAN}║${C_RESET}"
echo -e "${C_CYAN}╚══════════════════════════════════════════════════════════════════════╝${C_RESET}"
echo ""

# 1. Detección del Gestor de Paquetes
echo -e "${C_CYAN}[1/5] Detectando distribución y comprobando dependencias...${C_RESET}"

MISSING_DEPS=false
for cmd in wine winetricks dxvk-setup gamemoderun cabextract curl 7z python3; do
    if ! command -v "$cmd" &> /dev/null; then
        MISSING_DEPS=true
        break
    fi
done

if [ "$MISSING_DEPS" = false ]; then
    echo -e "${C_GREEN}✔ Todas las dependencias principales ya están instaladas en el sistema.${C_RESET}"
else
    if command -v apt-get &> /dev/null; then
        PKG_MGR="apt"
        INSTALL_CMD="sudo apt-get update && sudo apt-get install -y"
        PKGS="wine winetricks dxvk gamemode cabextract curl p7zip-full mesa-utils vulkan-tools zenity python3 libnss-resolve:i386 libnss-mdns:i386 gstreamer1.0-libav:i386 gstreamer1.0-plugins-ugly:i386 gstreamer1.0-plugins-bad:i386 libvkd3d1:i386 libopenexr-3-1-30:i386"
    elif command -v pacman &> /dev/null; then
        PKG_MGR="pacman"
        INSTALL_CMD="sudo pacman -Sy --noconfirm --needed"
        PKGS="wine winetricks dxvk gamemode cabextract curl p7zip mesa-utils vulkan-tools zenity python lib32-gst-plugins-ugly lib32-gst-plugins-bad lib32-gst-libav lib32-vkd3d"
    elif command -v dnf &> /dev/null; then
        PKG_MGR="dnf"
        INSTALL_CMD="sudo dnf install -y"
        PKGS="wine winetricks dxvk gamemode cabextract curl p7zip mesa-demos vulkan-tools zenity python3 gstreamer1-plugins-ugly.i686 gstreamer1-plugins-bad-free.i686 vkd3d.i686"
    elif command -v zypper &> /dev/null; then
        PKG_MGR="zypper"
        INSTALL_CMD="sudo zypper install -y"
        PKGS="wine winetricks dxvk gamemode cabextract curl p7zip mesa-utils vulkan-tools zenity python3 gstreamer-plugins-ugly-32bit gstreamer-plugins-bad-32bit"
    else
        echo -e "${C_YELLOW}Aviso: No se detectó un gestor de paquetes estándar. Asegúrate de tener Wine y DXVK instalados.${C_RESET}"
        PKG_MGR="manual"
    fi

    if [ "$PKG_MGR" != "manual" ]; then
        echo -e "      Distribución detectada con gestor: ${C_BOLD}${PKG_MGR}${C_RESET}"
        echo -e "      Instalando dependencias necesarias..."
        eval "$INSTALL_CMD $PKGS" || echo -e "${C_YELLOW}Nota: Algunos paquetes ya estaban instalados o variaron de nombre.${C_RESET}"
    fi
fi
echo -e "${C_GREEN}✔ Paquetes y dependencias del sistema listos.${C_RESET}"
echo ""

# 2. Configurar Parámetros del Kernel para Gaming y Multijugador
echo -e "${C_CYAN}[2/5] Optimizando parámetros del Kernel (memoria y multijugador)...${C_RESET}"
if [ -w /etc/sysctl.d ] || sudo -n true 2>/dev/null || [ "$EUID" -eq 0 ]; then
    sudo bash -c 'cat <<EOF > /etc/sysctl.d/99-win-gaming.conf
# Optimizaciones de memoria y red para juegos pesados y multiplayer
vm.max_map_count = 2147483642
net.ipv4.ping_group_range = 0 2147483647
net.ipv4.ip_unprivileged_port_start = 0
fs.file-max = 2097152
EOF'
    sudo /sbin/sysctl --system > /dev/null 2>&1 || true
    echo -e "${C_GREEN}✔ Parámetros del Kernel aplicados permanentemente.${C_RESET}"
else
    echo -e "${C_YELLOW}Aviso: No se pudieron escribir parámetros del kernel en /etc/sysctl.d sin permisos root (opcional).${C_RESET}"
fi
echo ""

# 3. Dar permisos de ejecución a los scripts
echo -e "${C_CYAN}[3/5] Configurando permisos de ejecución en los scripts del proyecto...${C_RESET}"
chmod +x "${DIR}"/*.sh "${DIR}"/*.py 2>/dev/null || true
echo -e "${C_GREEN}✔ Scripts ejecutables configurados.${C_RESET}"
echo ""

# 4. Generar configuración DXVK adaptada al hardware de esta PC
echo -e "${C_CYAN}[4/5] Analizando hardware de este equipo y generando configuración DXVK...${C_RESET}"
if [ -f "${DIR}/generar_dxvk_conf.sh" ]; then
    "${DIR}/generar_dxvk_conf.sh"
    echo -e "${C_GREEN}✔ Archivo dxvk.conf generado a medida.${C_RESET}"
fi

# 4.1 Asegurar librerías esenciales para instaladores (MFC, Visual C++, Fuentes) y registro
if command -v winetricks &>/dev/null && [ ! -f "${DIR}/wineprefix/drive_c/windows/syswow64/mfc42.dll" ]; then
    echo -e "${C_CYAN}      Instalando librerías base para instaladores (MFC, VC++, Corefonts)...${C_RESET}"
    WINEPREFIX="${DIR}/wineprefix" winetricks -q corefonts vcrun2022 vcrun2010 mfc42 2>/dev/null || true
    echo -e "${C_GREEN}✔ Entorno base optimizado para cualquier instalador.${C_RESET}"
fi

# 4.2 Ajustes de Registro Direct3D y X11 (Previene pantalla negra y micro-tirones)
source "${DIR}/hardware_detect.sh" 2>/dev/null || true
local_vram="${VRAM_MB:-2048}"
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "VideoMemorySize" /t REG_SZ /d "$local_vram" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "csmt" /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "StrictDrawOrdering" /t REG_SZ /d "disabled" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "AlwaysOffscreen" /t REG_SZ /d "enabled" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "OffscreenRenderingMode" /t REG_SZ /d "fbo" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v "UseTakeFocus" /t REG_SZ /d "N" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v "GrabFullscreen" /t REG_SZ /d "Y" /f >/dev/null 2>&1 || true
echo -e "${C_GREEN}✔ Parámetros de compatibilidad gráfica Direct3D configurados.${C_RESET}"
echo ""

# 5. Crear accesos directos universales (Escritorio y Menú del Sistema)
echo -e "${C_CYAN}[5/5] Creando accesos directos en el Escritorio y Menú del Sistema...${C_RESET}"

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(eval echo "~$TARGET_USER")

LAUNCH_EXEC="sh -c 'if command -v konsole >/dev/null 2>&1; then exec konsole -e \"\$0\"; elif command -v gnome-terminal >/dev/null 2>&1; then exec gnome-terminal -- \"\$0\"; else exec x-terminal-emulator -e \"\$0\"; fi' \"${DIR}/menu-win.sh\""

mkdir -p "$TARGET_HOME/.local/share/applications"
cat <<EOF > "$TARGET_HOME/.local/share/applications/menu-win-pc.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Menu Win (PC)
Comment=Gestor y Optimizador de Juegos de Windows para PC
Exec=${LAUNCH_EXEC}
Icon=wine
Terminal=false
Categories=Game;System;
StartupNotify=true
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.local/share/applications/menu-win-pc.desktop" 2>/dev/null || true
chmod +x "$TARGET_HOME/.local/share/applications/menu-win-pc.desktop"
gio set "$TARGET_HOME/.local/share/applications/menu-win-pc.desktop" metadata::trusted true 2>/dev/null || true

DESKTOP_DIR="$TARGET_HOME/Escritorio"
[ ! -d "$DESKTOP_DIR" ] && DESKTOP_DIR="$TARGET_HOME/Desktop"

if [ -d "$DESKTOP_DIR" ]; then
    cat <<EOF > "${DESKTOP_DIR}/Menu Win (PC).desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Menu Win (PC)
Comment=Gestor y Optimizador de Juegos de Windows para PC
Exec=${LAUNCH_EXEC}
Icon=wine
Terminal=false
Categories=Game;System;
StartupNotify=true
EOF
    chown "$TARGET_USER:$TARGET_USER" "${DESKTOP_DIR}/Menu Win (PC).desktop" 2>/dev/null || true
    chmod +x "${DESKTOP_DIR}/Menu Win (PC).desktop"
    gio set "${DESKTOP_DIR}/Menu Win (PC).desktop" metadata::trusted true 2>/dev/null || true
    echo -e "${C_GREEN}✔ Acceso directo creado y validado en tu Escritorio: 'Menu Win (PC)'${C_RESET}"
fi

echo ""
echo -e "${C_BOLD}${C_GREEN}🎉 ¡INSTALACIÓN COMPLETADA CON ÉXITO! 🎉${C_RESET}"
echo -e "${C_WHITE}Tu PC ahora está optimizada y lista para correr cualquier juego o programa.${C_RESET}"
echo -e "${C_CYAN}Puedes iniciar el menú en cualquier momento ejecutando:${C_RESET}"
echo -e "   ${C_BOLD}${DIR}/menu-win.sh${C_RESET}"
echo ""
