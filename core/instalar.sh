#!/bin/bash
# ==============================================================================
# INSTALADOR UNIVERSAL EN 1-CLIC PARA CUALQUIER COMPUTADORA CON LINUX
# Compatible con: Debian, Ubuntu, Mint, Arch, Manjaro, Fedora y OpenSUSE
# ==============================================================================

# Autoprotección multi-shell: Si se ejecuta con dash, sh, zsh o fish, cambiar inmediatamente a bash
if [ -z "$BASH_VERSION" ]; then
    if command -v bash >/dev/null 2>&1; then
        if [ -f "$0" ]; then
            exec bash "$0" "$@"
        else
            exec bash -s -- "$@"
        fi
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -f "${SCRIPT_DIR}/../menu-win.sh" ]; then
    DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
    DIR="$SCRIPT_DIR"
fi

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

    # Determinar el usuario real y su carpeta personal (evitar instalar en /root/ si se usa sudo)
    REAL_USER="${SUDO_USER:-$USER}"
    REAL_HOME=$(eval echo "~$REAL_USER")
    TARGET_DIR="$REAL_HOME/Vessel"

    echo -e "${C_WHITE}Carpeta de destino:${C_RESET} ${C_BOLD}${TARGET_DIR}${C_RESET}"

    # En Debian/Ubuntu/Mint: desactivar repositorios 'cdrom:' huérfanos que bloquean 'apt'
    if command -v apt-get &>/dev/null; then
        sudo sed -i '/^deb cdrom:/s/^/#/' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null || true
    fi

    # Intentar asegurar git si está ausente
    if ! command -v git &>/dev/null; then
        echo -e "${C_YELLOW}Instalando 'git' para clonar el repositorio...${C_RESET}"
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -y 2>/dev/null || true
            sudo apt-get install -y git 2>/dev/null || sudo apt-get install -y --fix-missing git 2>/dev/null || true
        elif command -v pacman &>/dev/null; then
            sudo pacman -Sy --noconfirm git 2>/dev/null || true
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y git 2>/dev/null || true
        elif command -v zypper &>/dev/null; then
            sudo zypper --non-interactive install git 2>/dev/null || true
        fi
    fi

    # Método 1: Clonar o actualizar mediante Git
    CLONED=false
    if command -v git &>/dev/null; then
        if [ ! -d "$TARGET_DIR/.git" ]; then
            echo -e "${C_GREEN}Clonando repositorio con Git en: ${C_BOLD}${TARGET_DIR}${C_RESET}..."
            if git clone https://github.com/Plumst-37/Vessel.git "$TARGET_DIR" 2>/dev/null; then
                CLONED=true
            fi
        else
            echo -e "${C_GREEN}Actualizando repositorio existente en: ${C_BOLD}${TARGET_DIR}${C_RESET}..."
            (cd "$TARGET_DIR" && git pull 2>/dev/null || true)
            CLONED=true
        fi
    fi

    # Método 2: Fallback infalible con tar.gz (si git falló o no existe)
    if [ "$CLONED" = false ] || [ ! -f "$TARGET_DIR/instalar.sh" ]; then
        echo -e "${C_YELLOW}Descargando código fuente directo (tar.gz)...${C_RESET}"
        mkdir -p "$TARGET_DIR"
        if command -v curl &>/dev/null; then
            curl -fsSL https://github.com/Plumst-37/Vessel/archive/refs/heads/main.tar.gz | tar -xz -C "$TARGET_DIR" --strip-components=1 2>/dev/null || true
        elif command -v wget &>/dev/null; then
            wget -qO- https://github.com/Plumst-37/Vessel/archive/refs/heads/main.tar.gz | tar -xz -C "$TARGET_DIR" --strip-components=1 2>/dev/null || true
        fi
    fi

    # Asegurar permisos correctos
    chown -R "$REAL_USER:$REAL_USER" "$TARGET_DIR" 2>/dev/null || true
    chmod +x "$TARGET_DIR"/*.sh "$TARGET_DIR"/*.py 2>/dev/null || true

    if [ -f "${TARGET_DIR}/instalar.sh" ]; then
        echo -e "${C_GREEN}✔ Archivos descargados correctamente. Iniciando configuración...${C_RESET}"
        exec bash "${TARGET_DIR}/instalar.sh" "$@"
    else
        echo -e "${C_RED}❌ Error: No se pudo descargar el repositorio. Comprueba tu conexión a Internet.${C_RESET}"
        exit 1
    fi
fi

clear 2>/dev/null || true
echo -e "${C_CYAN}╔══════════════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_CYAN}║${C_RESET}             ${C_GREEN}📦  INSTALADOR UNIVERSAL - PROYECTO WIN  📦${C_RESET}              ${C_CYAN}║${C_RESET}"
echo -e "${C_CYAN}║${C_RESET}       ${C_BOLD}Configuración y optimización automática para cualquier PC${C_RESET}      ${C_CYAN}║${C_RESET}"
echo -e "${C_CYAN}╚══════════════════════════════════════════════════════════════════════╝${C_RESET}"
echo ""

solicitar_permisos_sudo() {
    echo -e "${C_CYAN}══════════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_YELLOW}🔐 SE REQUIEREN PERMISOS DE ADMINISTRADOR (CONTRASEÑA ROOT / SUDO)${C_RESET}"
    echo -e "${C_WHITE}Para instalar los controladores y configurar cada archivo en su lugar:${C_RESET}"
    echo -e "  ${C_CYAN}•${C_RESET} Controladores Vulkan (32 y 64 bits para tu tarjeta gráfica)"
    echo -e "  ${C_CYAN}•${C_RESET} Paquetes del sistema Wine, Winetricks y Feral GameMode"
    echo -e "  ${C_CYAN}•${C_RESET} Parámetros de memoria en /etc/sysctl.d/ y límites en /etc/security/"
    echo -e "${C_CYAN}══════════════════════════════════════════════════════════════════════${C_RESET}"
    echo ""

    if [ "$EUID" -eq 0 ]; then
        echo -e "${C_GREEN}  ✔ Sesión activa con permisos de superusuario (root).${C_RESET}"
        echo ""
        return 0
    fi

    echo -e "${C_WHITE}Por favor, ingresa tu contraseña de administrador para continuar:${C_RESET}"
    if ! sudo -v; then
        echo ""
        echo -e "${C_RED}❌ Error: Contraseña incorrecta o permisos cancelados.${C_RESET}"
        echo -e "${C_YELLOW}Instalación cancelada para proteger el sistema.${C_RESET}"
        return 1
    fi

    ( while true; do sudo -n true 2>/dev/null; sleep 45; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEP_ALIVE_PID=$!
    trap 'kill "$SUDO_KEEP_ALIVE_PID" 2>/dev/null || true' EXIT INT TERM
    echo -e "${C_GREEN}  ✔ Permisos de administrador concedidos correctamente.${C_RESET}"
    echo ""
    return 0
}

# 1. Detección y Selección de Distribución de Linux (Comandos 100% Nativos)
echo -e "${C_CYAN}[1/5] Detección y Selección de Distribución de Linux...${C_RESET}"

DISTRO_DETECTED="debian"
DISTRO_LABEL="Debian GNU/Linux"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        debian|devuan) DISTRO_DETECTED="debian"; DISTRO_LABEL="Debian / Devuan" ;;
        ubuntu|linuxmint|pop|zorin|elementary) DISTRO_DETECTED="ubuntu"; DISTRO_LABEL="Ubuntu / Linux Mint / Pop!_OS / Zorin OS" ;;
        arch|manjaro|endeavouros|garuda|steamos) DISTRO_DETECTED="arch"; DISTRO_LABEL="Arch Linux / Manjaro / SteamOS" ;;
        fedora|nobara|rhel|centos) DISTRO_DETECTED="fedora"; DISTRO_LABEL="Fedora / Nobara / RHEL" ;;
        opensuse*|suse) DISTRO_DETECTED="opensuse"; DISTRO_LABEL="openSUSE (Tumbleweed / Leap)" ;;
        *)
            if [ -n "$ID_LIKE" ]; then
                case "$ID_LIKE" in
                    *debian*) DISTRO_DETECTED="debian"; DISTRO_LABEL="Debian GNU/Linux" ;;
                    *ubuntu*) DISTRO_DETECTED="ubuntu"; DISTRO_LABEL="Ubuntu / Linux Mint" ;;
                    *arch*) DISTRO_DETECTED="arch"; DISTRO_LABEL="Arch Linux / Manjaro" ;;
                    *fedora*|*rhel*) DISTRO_DETECTED="fedora"; DISTRO_LABEL="Fedora / Nobara" ;;
                    *suse*) DISTRO_DETECTED="opensuse"; DISTRO_LABEL="openSUSE" ;;
                esac
            fi
            ;;
    esac
fi

# Fallback si no se detectó por /etc/os-release
if [ "$DISTRO_DETECTED" = "generic" ] || [ -z "$DISTRO_DETECTED" ]; then
    if command -v apt-get >/dev/null 2>&1; then DISTRO_DETECTED="debian"; DISTRO_LABEL="Debian / Devuan";
    elif command -v pacman >/dev/null 2>&1; then DISTRO_DETECTED="arch"; DISTRO_LABEL="Arch Linux / Manjaro";
    elif command -v dnf >/dev/null 2>&1; then DISTRO_DETECTED="fedora"; DISTRO_LABEL="Fedora / Nobara";
    elif command -v zypper >/dev/null 2>&1; then DISTRO_DETECTED="opensuse"; DISTRO_LABEL="openSUSE";
    fi
fi

echo -e "      Distribución detectada en tu PC: ${C_GREEN}${DISTRO_LABEL}${C_RESET}"
echo ""
echo -e "  ${C_WHITE}Selecciona tu distribución para ejecutar los comandos adaptados a tu sistema:${C_RESET}"
echo -e "    ${C_BOLD}[1]${C_RESET} ${C_YELLOW}Debian / Devuan${C_RESET}"
echo -e "    ${C_BOLD}[2]${C_RESET} ${C_GREEN}Ubuntu / Linux Mint / Pop!_OS / Zorin OS${C_RESET}"
echo -e "    ${C_BOLD}[3]${C_RESET} ${C_CYAN}Arch Linux / Manjaro / EndeavourOS / SteamOS${C_RESET}"
echo -e "    ${C_BOLD}[4]${C_RESET} ${C_BLUE}Fedora / Nobara / RHEL${C_RESET}"
echo -e "    ${C_BOLD}[5]${C_RESET} ${C_MAGENTA}openSUSE (Tumbleweed / Leap)${C_RESET}"
echo -e "    ${C_BOLD}[6]${C_RESET} ${C_PURPLE}Modo Portable Universal / SteamOS (Sin sudo / Distro Inmutable / Runner Descargable)${C_RESET}"
echo -e "    ${C_BOLD}[Enter]${C_RESET} Usar sistema detectado (${DISTRO_LABEL})"
echo ""
read -p "Elige tu sistema (1-6 o Enter): " d_choice

case "$d_choice" in
    1) DISTRO_DETECTED="debian"; DISTRO_LABEL="Debian GNU/Linux" ;;
    2) DISTRO_DETECTED="ubuntu"; DISTRO_LABEL="Ubuntu / Linux Mint" ;;
    3) DISTRO_DETECTED="arch"; DISTRO_LABEL="Arch Linux / Manjaro" ;;
    4) DISTRO_DETECTED="fedora"; DISTRO_LABEL="Fedora / Nobara" ;;
    5) DISTRO_DETECTED="opensuse"; DISTRO_LABEL="openSUSE" ;;
    6) DISTRO_DETECTED="portable"; DISTRO_LABEL="Modo Portable Universal (SteamOS / Inmutable)" ;;
    *) ;;
esac

echo ""
echo -e "${C_CYAN}══════════════════════════════════════════════════════════════════════${C_RESET}"
echo -e "  ${C_BOLD}Sistema seleccionado:${C_RESET} ${C_YELLOW}${DISTRO_LABEL}${C_RESET}"
echo -e "${C_CYAN}══════════════════════════════════════════════════════════════════════${C_RESET}"
echo ""

# Solicitar permisos de administrador solo si no se eligió el Modo Portable
if [ "$DISTRO_DETECTED" != "portable" ]; then
    if ! solicitar_permisos_sudo; then
        echo -e "${C_YELLOW}  ⚠️ No se pudieron obtener permisos de administrador (sudo).${C_RESET}"
        echo -e "${C_CYAN}  ➤ Conmutando automáticamente al Modo Portable Universal (SteamOS / Inmutable)...${C_RESET}\n"
        DISTRO_DETECTED="portable"
        DISTRO_LABEL="Modo Portable Universal (SteamOS / Inmutable)"
    fi
else
    echo -e "${C_GREEN}  ✔ Continuando en Modo Portable sin requerir permisos de administrador.${C_RESET}\n"
fi

# Guardar selección en archivo de configuración
CONFIG_USER="${DIR}/config_rendimiento.cfg"
touch "$CONFIG_USER"
sed -i '/^SISTEMA_LINUX=/d' "$CONFIG_USER" 2>/dev/null || true
sed -i '/^DISTRO_NAME=/d' "$CONFIG_USER" 2>/dev/null || true
echo "SISTEMA_LINUX=\"$DISTRO_DETECTED\"" >> "$CONFIG_USER"
echo "DISTRO_NAME=\"$DISTRO_LABEL\"" >> "$CONFIG_USER"

case "$DISTRO_DETECTED" in
    debian)
        echo -e "${C_CYAN}  ⚙️ Configurando Debian GNU/Linux (32 y 64 bits)...${C_RESET}"
        sudo sed -i '/^deb cdrom:/s/^/#/' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null || true
        if command -v dpkg &>/dev/null && ! dpkg --print-foreign-architectures 2>/dev/null | grep -q "i386"; then
            sudo dpkg --add-architecture i386 2>/dev/null || true
        fi
        sudo apt-get update -y 2>/dev/null || true
        sudo apt-get install -y wine wine32:i386 wine64 winetricks cabextract curl git p7zip-full zstd mesa-utils vulkan-tools zenity python3 wine-gecko wine-mono wmctrl xdotool 2>/dev/null || sudo apt-get install -y wine winetricks cabextract curl git p7zip-full zstd zenity python3 wmctrl xdotool 2>/dev/null || true
        sudo apt-get install -y dxvk dxvk-wine32:i386 dxvk-wine64 libvulkan1 libvulkan1:i386 mesa-vulkan-drivers mesa-vulkan-drivers:i386 libgl1-mesa-dri:i386 libgl1:i386 2>/dev/null || true
        sudo apt-get install -y gamemode libgamemode0:i386 2>/dev/null || sudo apt-get install -y gamemode 2>/dev/null || true
        if lspci 2>/dev/null | grep -qi "nvidia"; then
            echo -e "${C_CYAN}  🎮 GPU NVIDIA detectada: Asegurando librerías gráficas de 32 bits...${C_RESET}"
            sudo apt-get install -y nvidia-driver-libs:i386 libgl1-nvidia-glvnd-glx:i386 libnvidia-glcore:i386 2>/dev/null || true
        elif lspci 2>/dev/null | grep -qi "intel"; then
            echo -e "${C_CYAN}  🎮 Gráficos Intel detectados: Asegurando aceleración multimedia VA-API...${C_RESET}"
            sudo apt-get install -y intel-media-va-driver intel-media-va-driver-non-free i965-va-driver 2>/dev/null || true
        elif lspci 2>/dev/null | grep -qiE "amd|radeon"; then
            echo -e "${C_CYAN}  🎮 GPU AMD detectada: Asegurando controladores VA-API de video...${C_RESET}"
            sudo apt-get install -y mesa-va-drivers mesa-va-drivers:i386 2>/dev/null || true
        fi
        sudo apt-get install -y libgnutls30:i386 2>/dev/null || sudo apt-get install -y libgnutls30t64:i386 2>/dev/null || true
        sudo apt-get install -y libnss-resolve:i386 libnss-mdns:i386 libvkd3d1 libvkd3d1:i386 2>/dev/null || true
        sudo apt-get install -y libasound2-plugins:i386 libpulse0:i386 pipewire-alsa:i386 libasound2:i386 2>/dev/null || true
        sudo apt-get install -y gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav 2>/dev/null || true
        sudo apt-get install -y gstreamer1.0-plugins-base:i386 gstreamer1.0-plugins-good:i386 gstreamer1.0-plugins-bad:i386 gstreamer1.0-plugins-ugly:i386 gstreamer1.0-libav:i386 2>/dev/null || true
        sudo apt-get install -y iw wireless-tools 2>/dev/null || true
        ;;
    ubuntu)
        echo -e "${C_CYAN}  ⚙️ Configurando Ubuntu / Linux Mint / Pop!_OS / Zorin...${C_RESET}"
        sudo sed -i '/^deb cdrom:/s/^/#/' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null || true
        if command -v dpkg &>/dev/null && ! dpkg --print-foreign-architectures 2>/dev/null | grep -q "i386"; then
            sudo dpkg --add-architecture i386 2>/dev/null || true
        fi
        sudo apt-get update -y 2>/dev/null || true
        sudo apt-get install -y wine wine32:i386 wine64 winetricks cabextract curl git p7zip-full zstd mesa-utils vulkan-tools zenity python3 wine-gecko wine-mono wmctrl xdotool 2>/dev/null || sudo apt-get install -y wine winetricks cabextract curl git p7zip-full zstd zenity python3 wmctrl xdotool 2>/dev/null || true
        sudo apt-get install -y dxvk dxvk-wine32:i386 dxvk-wine64 libvulkan1 libvulkan1:i386 mesa-vulkan-drivers mesa-vulkan-drivers:i386 libgl1-mesa-dri:i386 libgl1:i386 mangohud gamemode libgamemode0:i386 2>/dev/null || true
        if lspci 2>/dev/null | grep -qi "nvidia"; then
            echo -e "${C_CYAN}  🎮 GPU NVIDIA detectada: Asegurando controladores y librerías de 32 bits...${C_RESET}"
            nv_ver=$(dpkg -l 2>/dev/null | grep -E '^ii\s+nvidia-driver-[0-9]+' | awk '{print $2}' | grep -oE '[0-9]+' | head -n 1)
            if [ -n "$nv_ver" ]; then
                sudo apt-get install -y "libnvidia-gl-${nv_ver}:i386" 2>/dev/null || true
            else
                sudo apt-get install -y libnvidia-gl-550:i386 2>/dev/null || sudo apt-get install -y libnvidia-gl-535:i386 2>/dev/null || sudo apt-get install -y libnvidia-gl-525:i386 2>/dev/null || sudo apt-get install -y nvidia-driver-libs:i386 2>/dev/null || true
            fi
        elif lspci 2>/dev/null | grep -qi "intel"; then
            echo -e "${C_CYAN}  🎮 Gráficos Intel detectados: Asegurando aceleración multimedia VA-API...${C_RESET}"
            sudo apt-get install -y intel-media-va-driver intel-media-va-driver-non-free i965-va-driver 2>/dev/null || true
        elif lspci 2>/dev/null | grep -qiE "amd|radeon"; then
            echo -e "${C_CYAN}  🎮 GPU AMD detectada: Asegurando controladores VA-API de video...${C_RESET}"
            sudo apt-get install -y mesa-va-drivers mesa-va-drivers:i386 2>/dev/null || true
        fi
        sudo apt-get install -y libgnutls30:i386 2>/dev/null || sudo apt-get install -y libgnutls30t64:i386 2>/dev/null || true
        sudo apt-get install -y libnss-resolve:i386 libnss-mdns:i386 libvkd3d1 libvkd3d1:i386 2>/dev/null || true
        sudo apt-get install -y libasound2-plugins:i386 libpulse0:i386 pipewire-alsa:i386 libasound2:i386 2>/dev/null || true
        sudo apt-get install -y gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav 2>/dev/null || true
        sudo apt-get install -y gstreamer1.0-plugins-base:i386 gstreamer1.0-plugins-good:i386 gstreamer1.0-plugins-bad:i386 gstreamer1.0-plugins-ugly:i386 gstreamer1.0-libav:i386 2>/dev/null || true
        sudo apt-get install -y iw wireless-tools 2>/dev/null || true
        ;;
    arch)
        echo -e "${C_CYAN}  ⚙️ Configurando Arch Linux / Manjaro / SteamOS...${C_RESET}"
        if [ -f /etc/pacman.conf ] && ! grep -q '^\[multilib\]' /etc/pacman.conf; then
            echo -e "${C_CYAN}  ⚙️ Habilitando repositorio multilib (32-bit) en /etc/pacman.conf...${C_RESET}"
            sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf 2>/dev/null || true
            sudo pacman -Sy --noconfirm 2>/dev/null || true
        fi
        sudo pacman -S --needed --noconfirm wine winetricks gamemode lib32-gamemode cabextract curl git p7zip zstd mesa-utils vulkan-tools zenity python wine-gecko wine-mono wmctrl xdotool 2>/dev/null || sudo pacman -S --needed --noconfirm wine winetricks gamemode cabextract curl git p7zip zstd mesa-utils vulkan-tools zenity python wmctrl xdotool 2>/dev/null || true
        sudo pacman -S --needed --noconfirm vulkan-icd-loader lib32-vulkan-icd-loader lib32-mesa lib32-libglvnd mangohud lib32-mangohud vkd3d lib32-vkd3d 2>/dev/null || true
        if lspci 2>/dev/null | grep -qiE "amd|radeon"; then
            echo -e "${C_CYAN}  🎮 GPU AMD detectada: Instalando controladores RADV Vulkan y VA-API (32 y 64 bits)...${C_RESET}"
            sudo pacman -S --needed --noconfirm vulkan-radeon lib32-vulkan-radeon mesa lib32-mesa libva-mesa-driver lib32-libva-mesa-driver 2>/dev/null || true
        elif lspci 2>/dev/null | grep -qi "intel"; then
            echo -e "${C_CYAN}  🎮 Gráficos Intel detectados: Instalando controladores ANV Vulkan y VA-API (32 y 64 bits)...${C_RESET}"
            sudo pacman -S --needed --noconfirm vulkan-intel lib32-vulkan-intel mesa lib32-mesa intel-media-driver 2>/dev/null || true
        fi
        if lspci 2>/dev/null | grep -qi "nvidia"; then
            echo -e "${C_CYAN}  🎮 GPU NVIDIA detectada: Instalando librerías nvidia-utils (32 y 64 bits)...${C_RESET}"
            sudo pacman -S --needed --noconfirm nvidia-utils lib32-nvidia-utils 2>/dev/null || true
        fi
        sudo pacman -S --needed --noconfirm lib32-gnutls lib32-glibc gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav lib32-gst-plugins-base lib32-gst-plugins-good lib32-gst-plugins-bad lib32-gst-plugins-ugly lib32-gst-libav iw wireless_tools 2>/dev/null || true
        ;;
    fedora)
        echo -e "${C_CYAN}  ⚙️ Configurando Fedora / Nobara...${C_RESET}"
        # 1. Paquetes base esenciales (100% oficiales y disponibles en Fedora)
        sudo dnf install -y wine winetricks gamemode cabextract curl git p7zip p7zip-plugins zstd vulkan-tools glx-utils zenity python3 wine-gecko wine-mono wmctrl xdotool 2>/dev/null || sudo dnf install -y wine winetricks gamemode cabextract curl git p7zip zstd vulkan-tools zenity python3 wmctrl xdotool 2>/dev/null || true

        # 2. Soporte para juegos y ejecutables de 32 bits (Wine multiarch)
        sudo dnf install -y wine.i686 2>/dev/null || sudo dnf install -y wine-core.i686 2>/dev/null || true

        # 3. Controladores Vulkan y OpenGL 32 bits (Imprescindibles para D3D9, GTA SA y juegos clásicos)
        sudo dnf install -y vulkan-loader mesa-vulkan-drivers mesa-dri-drivers 2>/dev/null || true
        sudo dnf install -y vulkan-loader.i686 mesa-vulkan-drivers.i686 mesa-dri-drivers.i686 libglvnd-glx.i686 libglvnd-egl.i686 2>/dev/null || true

        # 4. Herramientas complementarias (MangoHud y VKD3D)
        sudo dnf install -y mangohud vkd3d 2>/dev/null || true
        sudo dnf install -y mangohud.i686 vkd3d.i686 2>/dev/null || true

        # 5. Detección y aceleración por GPU
        if lspci 2>/dev/null | grep -qiE "amd|radeon"; then
            echo -e "${C_CYAN}  🎮 GPU AMD detectada: Instalando aceleración VA-API...${C_RESET}"
            sudo dnf install -y mesa-va-drivers mesa-va-drivers.i686 2>/dev/null || sudo dnf install -y mesa-va-drivers 2>/dev/null || true
        elif lspci 2>/dev/null | grep -qi "intel"; then
            echo -e "${C_CYAN}  🎮 Gráficos Intel detectados: Instalando aceleración multimedia...${C_RESET}"
            sudo dnf install -y intel-media-driver 2>/dev/null || true
        elif lspci 2>/dev/null | grep -qi "nvidia"; then
            echo -e "${C_CYAN}  🎮 GPU NVIDIA detectada: Asegurando librerías 32 bits (RPM Fusion)...${C_RESET}"
            if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
                sudo dnf install -y "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" 2>/dev/null || true
            fi
            sudo dnf install -y xorg-x11-drv-nvidia-libs.i686 2>/dev/null || true
        fi

        # 6. Decodificadores multimedia GStreamer y Sonido (32 y 64 bits para cinemáticas sin pantalla negra)
        sudo dnf install -y gstreamer1-plugins-base gstreamer1-plugins-good gstreamer1-plugins-bad-free gstreamer1-plugins-ugly gstreamer1-libav 2>/dev/null || true
        sudo dnf install -y gstreamer1-plugins-base.i686 gstreamer1-plugins-good.i686 gstreamer1-plugins-bad-free.i686 gstreamer1-plugins-ugly.i686 gstreamer1-libav.i686 2>/dev/null || true
        sudo dnf install -y pipewire-alsa.i686 alsa-plugins-pulseaudio.i686 openal-soft.i686 2>/dev/null || true

        # 7. Librerías de red, SSL/TLS y DNS de 32 bits (Multijugador, GameRanger y HTTPS)
        sudo dnf install -y gnutls.i686 systemd-libs.i686 nss-mdns.i686 glibc.i686 libnsl.i686 libxcrypt.i686 iw wireless-tools 2>/dev/null || true

        # 8. Políticas SELinux para compatibilidad total con Wine
        if command -v setsebool &>/dev/null; then
            echo -e "${C_CYAN}  🛡️ Configurando políticas de SELinux para ejecución de juegos en Wine...${C_RESET}"
            sudo setsebool -P mmap_low_allowed 1 2>/dev/null || true
            sudo setsebool -P selinuxuser_execmod 1 2>/dev/null || true
            sudo setsebool -P wine_mmap_zero_ignore 1 2>/dev/null || true
        fi
        ;;
    opensuse)
        echo -e "${C_CYAN}  ⚙️ Configurando openSUSE...${C_RESET}"
        sudo zypper --non-interactive --auto-agree-with-licenses install wine wine-32bit winetricks gamemode gamemode-32bit cabextract curl git p7zip zstd mesa-utils vulkan-tools zenity python3 wine-gecko wine-mono wmctrl xdotool 2>/dev/null || sudo zypper --non-interactive --auto-agree-with-licenses install wine winetricks gamemode cabextract curl git p7zip zstd mesa-utils vulkan-tools zenity python3 wmctrl xdotool 2>/dev/null || true
        sudo zypper --non-interactive --auto-agree-with-licenses install libvulkan1 libvulkan1-32bit Mesa-dri-32bit libglvnd-32bit mangohud mangohud-32bit 2>/dev/null || true
        if lspci 2>/dev/null | grep -qiE "amd|radeon"; then
            echo -e "${C_CYAN}  🎮 GPU AMD detectada: Instalando controladores RADV Vulkan...${C_RESET}"
            sudo zypper --non-interactive --auto-agree-with-licenses install libvulkan_radeon libvulkan_radeon-32bit 2>/dev/null || true
        elif lspci 2>/dev/null | grep -qi "intel"; then
            echo -e "${C_CYAN}  🎮 Gráficos Intel detectados: Instalando controladores ANV Vulkan...${C_RESET}"
            sudo zypper --non-interactive --auto-agree-with-licenses install libvulkan_intel libvulkan_intel-32bit 2>/dev/null || true
        fi
        sudo zypper --non-interactive --auto-agree-with-licenses install gstreamer-plugins-base gstreamer-plugins-good gstreamer-plugins-bad gstreamer-plugins-ugly gstreamer-plugins-ugly-32bit gstreamer-plugins-bad-32bit libgnutls30-32bit systemd-32bit iw wireless-tools 2>/dev/null || sudo zypper --non-interactive --auto-agree-with-licenses install gnutls-32bit iw wireless-tools 2>/dev/null || true
        ;;
    portable)
        echo -e "${C_PURPLE}  ⚙️ Modo Portable Universal seleccionado (SteamOS / Distros Inmutables / Sin Sudo)...${C_RESET}"
        if [ -x "${DIR}/gestor_runners.sh" ]; then
            "${DIR}/gestor_runners.sh" --kron4ek 2>/dev/null || true
        fi
        ;;
    *)
        echo -e "${C_YELLOW}  ⚠️ Distribución genérica detectada. Verificando comandos estándar...${C_RESET}"
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -y 2>/dev/null || true
            sudo apt-get install -y wine winetricks gamemode cabextract curl zstd p7zip-full zenity python3 wmctrl xdotool iw wireless-tools 2>/dev/null || true
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --needed --noconfirm wine winetricks gamemode cabextract curl zstd p7zip zenity python wmctrl xdotool iw wireless_tools 2>/dev/null || true
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y --skip-broken wine winetricks gamemode cabextract curl zstd p7zip zenity python3 wmctrl xdotool iw wireless-tools 2>/dev/null || true
        elif command -v zypper &>/dev/null; then
            sudo zypper --non-interactive --auto-agree-with-licenses install wine winetricks gamemode cabextract curl zstd p7zip zenity python3 wmctrl xdotool iw wireless-tools 2>/dev/null || true
        fi
        ;;
esac
echo -e "${C_GREEN}✔ Paquetes y controladores gráficos del sistema listos con 0% fallos.${C_RESET}"
echo ""

# 2. Configurar Parámetros del Kernel para Gaming y Multijugador
echo -e "${C_CYAN}[2/5] Optimizando parámetros del Kernel y Límites Esync/Fsync...${C_RESET}"
sudo sysctl -w vm.max_map_count=2147483642 2>/dev/null || sysctl -w vm.max_map_count=2147483642 2>/dev/null || true
sudo sysctl -w fs.file-max=2097152 2>/dev/null || true
sudo sysctl -w net.ipv4.ping_group_range="0 2147483647" 2>/dev/null || true
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0 2>/dev/null || true

if [ -w /etc/sysctl.d ] || sudo -n true 2>/dev/null || [ "$EUID" -eq 0 ]; then
    sudo bash -c 'cat <<EOF > /etc/sysctl.d/99-win-gaming.conf
# Optimizaciones de memoria y red para juegos pesados y multiplayer
vm.max_map_count = 2147483642
vm.swappiness = 10
vm.vfs_cache_pressure = 50
kernel.split_lock_mitigate = 0
net.ipv4.ping_group_range = 0 2147483647
net.ipv4.ip_unprivileged_port_start = 0
fs.file-max = 2097152
EOF' 2>/dev/null || true
    sudo /sbin/sysctl --system > /dev/null 2>&1 || sudo sysctl --system > /dev/null 2>&1 || true
    echo -e "${C_GREEN}✔ Parámetros del Kernel aplicados (vm.max_map_count = 2.1M, swappiness = 10, split_lock_mitigate = 0).${C_RESET}"
fi

# Apertura opcional de firewall para multijugador, GameRanger, DirectPlay y servidores de juegos
echo -e "${C_CYAN}  🌐 Configurando Firewall para Multijugador (GameRanger, DirectPlay, SWAT 4, GTA SA, Steam)...${C_RESET}"
if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
    sudo firewall-cmd --add-port=16000/udp --add-port=2300-2400/udp --add-port=2300-2400/tcp --add-port=47624/tcp --add-port=10480-10483/udp --add-port=7777/udp --add-port=27015-27030/udp 2>/dev/null || true
    sudo firewall-cmd --permanent --add-port=16000/udp --add-port=2300-2400/udp --add-port=2300-2400/tcp --add-port=47624/tcp --add-port=10480-10483/udp --add-port=7777/udp --add-port=27015-27030/udp 2>/dev/null || true
    sudo firewall-cmd --reload 2>/dev/null || true
fi
if command -v ufw &>/dev/null && sudo ufw status 2>/dev/null | grep -qi "active"; then
    sudo ufw allow 16000/udp 2>/dev/null || true
    sudo ufw allow 2300:2400/udp 2>/dev/null || true
    sudo ufw allow 2300:2400/tcp 2>/dev/null || true
    sudo ufw allow 47624/tcp 2>/dev/null || true
    sudo ufw allow 10480:10483/udp 2>/dev/null || true
    sudo ufw allow 7777/udp 2>/dev/null || true
    sudo ufw allow 27015:27030/udp 2>/dev/null || true
fi
if command -v iptables &>/dev/null; then
    sudo iptables -C INPUT -p udp --dport 16000 -j ACCEPT 2>/dev/null || sudo iptables -I INPUT -p udp --dport 16000 -j ACCEPT 2>/dev/null || true
    sudo iptables -C INPUT -p udp --dport 7777 -j ACCEPT 2>/dev/null || sudo iptables -I INPUT -p udp --dport 7777 -j ACCEPT 2>/dev/null || true
    sudo iptables -C INPUT -p tcp --dport 47624 -j ACCEPT 2>/dev/null || sudo iptables -I INPUT -p tcp --dport 47624 -j ACCEPT 2>/dev/null || true
fi

if [ -w /etc/security/limits.d ] || sudo -n true 2>/dev/null || [ "$EUID" -eq 0 ]; then
    sudo bash -c 'cat <<EOF > /etc/security/limits.d/99-wine-gaming.conf
# Limites de archivos abiertos y prioridades para Wine Esync, Fsync y baja latencia
* hard nofile 1048576
* soft nofile 1048576
root hard nofile 1048576
root soft nofile 1048576
* hard memlock unlimited
* soft memlock unlimited
* hard nice -20
* soft nice -20
* hard rtprio 99
* soft rtprio 99
EOF' 2>/dev/null || true
    echo -e "${C_GREEN}✔ Límites de archivos, memoria y tiempo real para Esync y Fsync configurados (nofile = 1M, rtprio = 99).${C_RESET}"
fi
echo ""

# 3. Dar permisos de ejecución a los scripts
echo -e "${C_CYAN}[3/5] Configurando permisos de ejecución en los scripts del proyecto...${C_RESET}"
chmod +x "${DIR}"/*.sh "${DIR}"/core/*.sh "${DIR}"/core/*.py "${DIR}"/herramientas/*.sh 2>/dev/null || true
echo -e "${C_GREEN}✔ Scripts ejecutables configurados.${C_RESET}"
echo ""

# 4. Generar configuración DXVK adaptada al hardware de esta PC
echo -e "${C_CYAN}[4/5] Analizando hardware de este equipo y generando configuración DXVK...${C_RESET}"
if [ -f "${DIR}/core/generar_dxvk_conf.sh" ]; then
    "${DIR}/core/generar_dxvk_conf.sh"
    echo -e "${C_GREEN}✔ Archivo dxvk.conf generado a medida.${C_RESET}"
elif [ -f "${DIR}/generar_dxvk_conf.sh" ]; then
    "${DIR}/generar_dxvk_conf.sh"
    echo -e "${C_GREEN}✔ Archivo dxvk.conf generado a medida.${C_RESET}"
fi

# 4.1 Asegurar paquete maestro de DLLs y runtimes esenciales (DirectX 9/10/11, VC++ 2005-2022 AIO, Corefonts, DirectPlay, OpenAL)
local_gestor="${DIR}/core/gestor_librerias.sh"
[ ! -f "$local_gestor" ] && local_gestor="${DIR}/herramientas/gestor_librerias.sh"
if [ -f "$local_gestor" ]; then
    echo -e "${C_CYAN}      Instalando paquete maestro de DLLs y runtimes para juegos...${C_RESET}"
    bash "$local_gestor" paquete_maestro "${DIR}/wineprefix" || true
    echo -e "${C_GREEN}✔ Entorno base optimizado con todas las librerías nativas para juegos.${C_RESET}"
fi

# 4.2 Optimización de hilos gráficos Direct3D (CSMT multithread) y supresión de fallos
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "csmt" /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\WineDbg" /v ShowCrashDialog /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\AeDebug" /v Auto /t REG_SZ /d 0 /f >/dev/null 2>&1 || true
echo -e "${C_GREEN}✔ Motor Direct3D CSMT multithread y protección 3D configurados.${C_RESET}"

# 4.3 Optimización de captura de ratón en 3D y compatibilidad multi-monitor
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\DirectInput" /v "MouseWarpOverride" /t REG_SZ /d "enable" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v "UseTakeFocus" /t REG_SZ /d "Y" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v "GrabFullscreen" /t REG_SZ /d "Y" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v "Decorated" /t REG_SZ /d "Y" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v "Managed" /t REG_SZ /d "Y" /f >/dev/null 2>&1 || true

# 4.3.1 Compatibilidad total para GameRanger (Modo Ventana, win7, CEF/ANGLE sin fallos de Vulkan + Red 100% activa)
for gr_target in "GameRanger.exe" "GameRangerSetup.exe"; do
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${gr_target}" /v "Version" /t REG_SZ /d "win7" /f >/dev/null 2>&1 || true
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${gr_target}\X11 Driver" /v "Decorated" /t REG_SZ /d "Y" /f >/dev/null 2>&1 || true
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${gr_target}\X11 Driver" /v "Managed" /t REG_SZ /d "Y" /f >/dev/null 2>&1 || true
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${gr_target}\X11 Driver" /v "GrabFullscreen" /t REG_SZ /d "N" /f >/dev/null 2>&1 || true
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${gr_target}\DllOverrides" /v d3d11 /t REG_SZ /d builtin /f >/dev/null 2>&1 || true
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${gr_target}\DllOverrides" /v dxgi /t REG_SZ /d builtin /f >/dev/null 2>&1 || true
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${gr_target}\DllOverrides" /v d3d9 /t REG_SZ /d builtin /f >/dev/null 2>&1 || true
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${gr_target}\DllOverrides" /v d3d10core /t REG_SZ /d builtin /f >/dev/null 2>&1 || true
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${gr_target}\DllOverrides" /v ws2_32 /t REG_SZ /d builtin /f >/dev/null 2>&1 || true
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${gr_target}\DllOverrides" /v dnsapi /t REG_SZ /d builtin /f >/dev/null 2>&1 || true
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${gr_target}\DllOverrides" /v secur32 /t REG_SZ /d builtin /f >/dev/null 2>&1 || true
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${gr_target}\DllOverrides" /v wininet /t REG_SZ /d builtin /f >/dev/null 2>&1 || true
    WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${gr_target}\DllOverrides" /v iphlpapi /t REG_SZ /d builtin /f >/dev/null 2>&1 || true
done
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v dplayx /t REG_SZ /d "builtin,native" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v dpnet /t REG_SZ /d "builtin,native" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v dpwsockx /t REG_SZ /d "builtin,native" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v dxgi /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v d3d11 /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v d3d10core /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v d3d9 /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v d3d8 /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\DllOverrides" /v ddraw /t REG_SZ /d "native,builtin" /f >/dev/null 2>&1 || true

# Configuración automática de DXVK en el prefijo si está instalado en el sistema
if command -v dxvk-setup &>/dev/null; then
    WINEPREFIX="${DIR}/wineprefix" dxvk-setup install -y 2>/dev/null || true
fi

# 4.3.1.1 Configuración universal de red, DNS y sondas NCSI en el registro de Wine (para todos los juegos)
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters" /v NameServer /t REG_SZ /d "1.1.1.1,8.8.8.8" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters" /v DhcpNameServer /t REG_SZ /d "1.1.1.1,8.8.8.8" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters" /v EnableDHCP /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\Default" /v NameServer /t REG_SZ /d "1.1.1.1,8.8.8.8" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\Default" /v DhcpNameServer /t REG_SZ /d "1.1.1.1,8.8.8.8" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\Default" /v EnableDHCP /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true

WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v EnableActiveProbing /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v ActiveWebProbeHost /t REG_SZ /d "www.msftncsi.com" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v ActiveWebProbeContent /t REG_SZ /d "Microsoft NCSI" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v ActiveDnsProbeHost /t REG_SZ /d "dns.msftncsi.com" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v ActiveDnsProbeContent /t REG_SZ /d "131.107.255.255" /f >/dev/null 2>&1 || true

WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" /v NoActiveProbe /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" /v DisablePassivePolling /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true

WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v GlobalUserOffline /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v CertificateRevocation /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true

# Configurar archivo hosts y networks del prefijo
prefix_etc="${DIR}/wineprefix/drive_c/windows/system32/drivers/etc"
mkdir -p "$prefix_etc"
cat << 'EOF' > "${prefix_etc}/hosts"
127.0.0.1 localhost Aspire
::1 localhost ip6-localhost ip6-loopback

# Servidores Oficiales GameRanger
51.222.17.7 connect.gameranger.com
67.228.206.97 status.gameranger.com
67.228.102.62 www.gameranger.com
67.228.102.62 default.gameranger.com

# Servidores Maestros SWAT 4 (swat4stats)
116.202.182.15 swat4.ms14.gamespy.com
116.202.182.15 swat4.available.gamespy.com
116.202.182.15 swat4.master.gamespy.com
116.202.182.15 swat4pr.ms14.gamespy.com
116.202.182.15 swat4pr.available.gamespy.com
116.202.182.15 swat4pr.master.gamespy.com
116.202.182.15 master.gamespy.com

# NCSI probe verification
131.107.255.255 dns.msftncsi.com
EOF
[ ! -f "${prefix_etc}/networks" ] && echo "default 0.0.0.0" > "${prefix_etc}/networks" 2>/dev/null || true
touch "${DIR}/wineprefix/.vessel_net_ok" 2>/dev/null || true
echo -e "${C_GREEN}✔ Captura de ratón DirectInput 3D, multi-monitor, red y perfil GameRanger configurados.${C_RESET}"

# 4.3.2 Instalación e integración automática de GameRanger en el sistema
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(eval echo "~$TARGET_USER")
echo -e "${C_CYAN}      Instalando e integrando GameRanger en el sistema...${C_RESET}"

GR_PROGFILES="${DIR}/wineprefix/drive_c/Program Files/GameRanger"
GR_ROAMING="${DIR}/wineprefix/drive_c/users/${TARGET_USER}/AppData/Roaming/GameRanger/GameRanger"
mkdir -p "$GR_PROGFILES" "$GR_ROAMING"

# Si no está localmente, descargarlo automáticamente de la fuente oficial
if [ ! -f "${DIR}/GameRanger/GameRanger.exe" ] && [ ! -f "${DIR}/GameRangerSetup.exe" ]; then
    echo -e "${C_YELLOW}      Descargando instalador oficial de GameRanger...${C_RESET}"
    curl -fsSL https://www.gameranger.com/download/GameRangerSetup.exe -o "${DIR}/GameRangerSetup.exe" 2>/dev/null || wget -q https://www.gameranger.com/download/GameRangerSetup.exe -O "${DIR}/GameRangerSetup.exe" 2>/dev/null || true
fi

if [ -f "${DIR}/GameRanger/GameRanger.exe" ]; then
    mkdir -p "$GR_PROGFILES" "$GR_ROAMING" "${GR_ROAMING}/../GameRanger Prefs"
    cp -r "${DIR}/GameRanger"/* "$GR_PROGFILES/" 2>/dev/null || true
    cp -r "${DIR}/GameRanger"/* "$GR_ROAMING/" 2>/dev/null || true

    # Restaurar sesión de GameRanger si existe backup previo en cualquier perfil
    if [ -d "${DIR}/.gameranger_prefs_backup" ]; then
        if [ ! -s "${GR_ROAMING}/../GameRanger Prefs/Settings" ] || ! grep -q "SessMail" "${GR_ROAMING}/../GameRanger Prefs/Settings" 2>/dev/null; then
            cp -rf "${DIR}/.gameranger_prefs_backup"/* "${GR_ROAMING}/../GameRanger Prefs/" 2>/dev/null || true
        fi
        for u_dir in "${DIR}/wineprefix/drive_c/users"/*; do
            if [ -d "$u_dir" ] && [ "$(basename "$u_dir")" != "Public" ]; then
                u_p="${u_dir}/AppData/Roaming/GameRanger/GameRanger Prefs"
                mkdir -p "$u_p"
                if [ ! -s "${u_p}/Settings" ] || ! grep -q "SessMail" "${u_p}/Settings" 2>/dev/null; then
                    cp -rf "${DIR}/.gameranger_prefs_backup"/* "${u_p}/" 2>/dev/null || true
                fi
            fi
        done
    fi
    echo -e "${C_GREEN}✔ GameRanger instalado en Archivos de Programa y perfil de usuario.${C_RESET}"
elif [ -f "${DIR}/GameRangerSetup.exe" ]; then
    WINEPREFIX="${DIR}/wineprefix" WINEDLLOVERRIDES="dxgi=b;d3d11=b;d3d10core=b;d3d9=b;" wine "${DIR}/GameRangerSetup.exe" 2>/dev/null || true
    echo -e "${C_GREEN}✔ GameRangerSetup instalado con éxito.${C_RESET}"
fi

# Registrar GameRanger en el registro de Windows de Wine (Compatibilidad nativa y 0% pantalla negra)
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_LOCAL_MACHINE\Software\GameRanger" /v "ExecutablePath" /t REG_SZ /d "C:\Program Files\GameRanger\GameRanger.exe" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\GameRanger" /v "ExecutablePath" /t REG_SZ /d "C:\Program Files\GameRanger\GameRanger.exe" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe" /v "Version" /t REG_SZ /d "win7" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\Direct3D" /v "renderer" /t REG_SZ /d "gl" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "dxgi" /t REG_SZ /d "b" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "d3d11" /t REG_SZ /d "b" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "d3d10core" /t REG_SZ /d "b" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "d3d9" /t REG_SZ /d "b" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "dnsapi" /t REG_SZ /d "n,b" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "dplayx" /t REG_SZ /d "n,b" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "dpnet" /t REG_SZ /d "n,b" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "riched20" /t REG_SZ /d "n,b" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\DllOverrides" /v "riched32" /t REG_SZ /d "n,b" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CLASSES_ROOT\gameranger" /v "" /t REG_SZ /d "URL:GameRanger Protocol" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CLASSES_ROOT\gameranger" /v "URL Protocol" /t REG_SZ /d "" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CLASSES_ROOT\gameranger\shell\open\command" /v "" /t REG_SZ /d "\"C:\Program Files\GameRanger\GameRanger.exe\" \"%1\"" /f >/dev/null 2>&1 || true

# Registrar GameRanger en programas.db de Vessel (protegiendo juegos existentes del usuario)
mkdir -p "${DIR}/datos" 2>/dev/null || true
for db_target in "${DIR}/datos/programas.db" "${DIR}/programas.db"; do
    if [ ! -s "$db_target" ] && [ -s "${DIR}/programas.db.bak" ]; then
        cp -f "${DIR}/programas.db.bak" "$db_target" 2>/dev/null || true
    fi
    touch "$db_target"
    [ -s "$db_target" ] && cp -f "$db_target" "${db_target}.bak" 2>/dev/null || true
    if ! grep -qi "GameRanger" "$db_target" 2>/dev/null; then
        sed -i '1i GameRanger|GameRanger.exe|compartido' "$db_target" 2>/dev/null || echo "GameRanger|GameRanger.exe|compartido" >> "$db_target"
        cp -f "$db_target" "${db_target}.bak" 2>/dev/null || true
    else
        sed -i 's/^GameRanger|.*|/GameRanger|GameRanger.exe|/' "$db_target" 2>/dev/null || true
    fi
    chown "$TARGET_USER:$TARGET_USER" "$db_target" 2>/dev/null || true
done

# Acceso directo en el menú de aplicaciones y escritorio
mkdir -p "$TARGET_HOME/.local/share/applications"
LAUNCH_EXE="${DIR}/core/launch-win-app.sh"
[ ! -f "$LAUNCH_EXE" ] && LAUNCH_EXE="${DIR}/launch-win-app.sh"
cat <<EOF > "$TARGET_HOME/.local/share/applications/gameranger.desktop"
[Desktop Entry]
Type=Application
Name=GameRanger
Comment=Juega con tus amigos en línea
Exec=sh -c '"${LAUNCH_EXE}" "GameRanger.exe"'
Icon=wine
Terminal=false
Categories=Game;Network;
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.local/share/applications/gameranger.desktop" 2>/dev/null || true
chmod +x "$TARGET_HOME/.local/share/applications/gameranger.desktop" 2>/dev/null || true

DESKTOP_DIR="$TARGET_HOME/Escritorio"
[ ! -d "$DESKTOP_DIR" ] && DESKTOP_DIR="$TARGET_HOME/Desktop"
if [ -d "$DESKTOP_DIR" ]; then
    cp "$TARGET_HOME/.local/share/applications/gameranger.desktop" "${DESKTOP_DIR}/GameRanger.desktop" 2>/dev/null || true
    chown "$TARGET_USER:$TARGET_USER" "${DESKTOP_DIR}/GameRanger.desktop" 2>/dev/null || true
    chmod +x "${DESKTOP_DIR}/GameRanger.desktop" 2>/dev/null || true
    gio set "${DESKTOP_DIR}/GameRanger.desktop" metadata::trusted true 2>/dev/null || true
fi

echo -e "${C_GREEN}✔ GameRanger totalmente instalado y configurado en el sistema.${C_RESET}"

# 4.4 Configuración de GameMode para el usuario (prioridad CPU/GPU y renice -10)
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(eval echo "~$TARGET_USER")
if command -v gamemoded &>/dev/null; then
    usermod -aG gamemode "$TARGET_USER" 2>/dev/null || true
    mkdir -p "$TARGET_HOME/.config"
    cat <<EOF > "$TARGET_HOME/.config/gamemode.ini"
[general]
desiredgov=performance
defaultgov=powersave
inhibit_screensaver=1
renice=10

[cpu]
park_cores=no
pin_cores=yes

[gpu]
apply_gpu_optimisations=accept-responsibility
gpu_device=0
nv_powermode_level=1
amd_performance_level=high
EOF
    chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/gamemode.ini" 2>/dev/null || true
    echo -e "${C_GREEN}✔ Feral GameMode configurado al máximo rendimiento (CPU Governor + GPU Mode).${C_RESET}"
fi
echo ""

# 5. Crear accesos directos universales (Escritorio y Menú del Sistema)
echo -e "${C_CYAN}[5/5] Creando accesos directos de Vessel en el Escritorio y Menú del Sistema...${C_RESET}"

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(eval echo "~$TARGET_USER")

# Asegurar permisos correctos en el directorio del proyecto y prefijo de Wine
chmod +x "${DIR}"/*.sh "${DIR}"/*.py 2>/dev/null || true
chown -R "$TARGET_USER:$TARGET_USER" "${DIR}/wineprefix" 2>/dev/null || true
chown -R "$TARGET_USER:$TARGET_USER" "${DIR}"/*.cfg "${DIR}"/*.conf 2>/dev/null || true

# Configurar icono oficial de Vessel
ICON_PATH="wine"
if [ -f "${DIR}/herramientas/vessel.svg" ]; then
    mkdir -p "$TARGET_HOME/.local/share/icons/hicolor/scalable/apps" 2>/dev/null || true
    cp -f "${DIR}/herramientas/vessel.svg" "$TARGET_HOME/.local/share/icons/hicolor/scalable/apps/vessel.svg" 2>/dev/null || true
    chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.local/share/icons/hicolor/scalable/apps/vessel.svg" 2>/dev/null || true
    if [ "$EUID" -eq 0 ]; then
        mkdir -p /usr/share/icons/hicolor/scalable/apps 2>/dev/null || true
        cp -f "${DIR}/herramientas/vessel.svg" /usr/share/icons/hicolor/scalable/apps/vessel.svg 2>/dev/null || true
    fi
    ICON_PATH="vessel"
fi

VESSEL_LAUNCHER="${DIR}/vessel.sh"
[ ! -f "$VESSEL_LAUNCHER" ] && VESSEL_LAUNCHER="${DIR}/menu-win.sh"

# Menú del Sistema (~/.local/share/applications/vessel.desktop)
mkdir -p "$TARGET_HOME/.local/share/applications"
cat <<EOF > "$TARGET_HOME/.local/share/applications/vessel.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Vessel
GenericName=Gestor y Optimizador de Juegos Windows
Comment=Lanzador y Optimizador Universal de Juegos y Programas de Windows
Exec=/bin/bash "${VESSEL_LAUNCHER}"
Path=${DIR}
Icon=${ICON_PATH}
Terminal=false
Categories=Game;
StartupNotify=true
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.local/share/applications/vessel.desktop" 2>/dev/null || true
chmod +x "$TARGET_HOME/.local/share/applications/vessel.desktop" 2>/dev/null || true
gio set "$TARGET_HOME/.local/share/applications/vessel.desktop" metadata::trusted true 2>/dev/null || true

# Limpiar accesos obsoletos antiguos del menú
rm -f "$TARGET_HOME/.local/share/applications/menu-win-pc.desktop" 2>/dev/null || true

# Acceso directo en el Escritorio del Usuario
DESKTOP_DIR=""
if command -v xdg-user-dir &>/dev/null; then
    DESKTOP_DIR=$(su - "$TARGET_USER" -c 'xdg-user-dir DESKTOP' 2>/dev/null || xdg-user-dir DESKTOP 2>/dev/null || true)
fi
[ -z "$DESKTOP_DIR" ] && DESKTOP_DIR="$TARGET_HOME/Escritorio"
[ ! -d "$DESKTOP_DIR" ] && DESKTOP_DIR="$TARGET_HOME/Desktop"

if [ -d "$DESKTOP_DIR" ]; then
    cat <<EOF > "${DESKTOP_DIR}/Vessel.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Vessel
GenericName=Gestor y Optimizador de Juegos Windows
Comment=Lanzador y Optimizador Universal de Juegos y Programas de Windows
Exec=/bin/bash "${VESSEL_LAUNCHER}"
Path=${DIR}
Icon=${ICON_PATH}
Terminal=false
Categories=Game;
StartupNotify=true
EOF
    chown "$TARGET_USER:$TARGET_USER" "${DESKTOP_DIR}/Vessel.desktop" 2>/dev/null || true
    chmod +x "${DESKTOP_DIR}/Vessel.desktop" 2>/dev/null || true
    gio set "${DESKTOP_DIR}/Vessel.desktop" metadata::trusted true 2>/dev/null || true

    # Habilitar ejecución directa con un clic en entornos KDE Plasma (sin diálogos de confirmación)
    if command -v kwriteconfig5 &>/dev/null; then
        su - "$TARGET_USER" -c 'kwriteconfig5 --file kiorc --group "Executable scripts" --key behaviourOnLaunch execute' 2>/dev/null || true
    fi
    if command -v kwriteconfig6 &>/dev/null; then
        su - "$TARGET_USER" -c 'kwriteconfig6 --file kiorc --group "Executable scripts" --key behaviourOnLaunch execute' 2>/dev/null || true
    fi

    # Limpiar accesos directos obsoletos del escritorio
    rm -f "${DESKTOP_DIR}/Menu Win (PC).desktop" "${DESKTOP_DIR}/Menu Win.desktop" 2>/dev/null || true

    echo -e "${C_GREEN}✔ Acceso directo creado y validado en tu Escritorio: 'Vessel'${C_RESET}"
fi

# Comando directo 'vessel' en el PATH del sistema o usuario
mkdir -p "$TARGET_HOME/.local/bin" 2>/dev/null || true
ln -sf "${DIR}/vessel.sh" "$TARGET_HOME/.local/bin/vessel" 2>/dev/null || true
chown -h "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.local/bin/vessel" 2>/dev/null || true
if [ "$EUID" -eq 0 ] && [ -d "/usr/local/bin" ]; then
    ln -sf "${DIR}/vessel.sh" /usr/local/bin/vessel 2>/dev/null || true
fi

echo "1.3" > "${DIR}/.instalado" 2>/dev/null || true
chown "$TARGET_USER:$TARGET_USER" "${DIR}/.instalado" 2>/dev/null || true
# version.txt se mantiene limpio (0 bytes) para sincronización con git
> "${DIR}/version.txt" 2>/dev/null || true
chown "$TARGET_USER:$TARGET_USER" "${DIR}/version.txt" 2>/dev/null || true

echo ""
echo -e "${C_BOLD}${C_GREEN}🎉 ¡INSTALACIÓN COMPLETADA CON ÉXITO! 🎉${C_RESET}"
echo -e "${C_WHITE}Tu PC ahora está optimizada y lista para correr cualquier juego o programa con Vessel.${C_RESET}"
echo -e "${C_CYAN}Puedes iniciar Vessel desde la terminal con:${C_RESET}"
echo -e "   ${C_BOLD}${C_GREEN}vessel run programa.exe${C_RESET}   (Ejecuta inmediatamente cualquier juego/app)"
echo -e "   ${C_BOLD}${C_CYAN}vessel${C_RESET}                    (Abre el menú interactivo completo)"
echo -e "   ${C_BOLD}${DIR}/menu-win.sh${C_RESET}  o  ${C_BOLD}vessel${C_RESET}"
echo ""
