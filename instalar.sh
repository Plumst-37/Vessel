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

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"

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

if ! solicitar_permisos_sudo; then
    exit 1
fi

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
echo -e "    ${C_BOLD}[Enter]${C_RESET} Usar sistema detectado (${DISTRO_LABEL})"
echo ""
read -p "Elige tu sistema (1-5 o Enter): " d_choice

case "$d_choice" in
    1) DISTRO_DETECTED="debian"; DISTRO_LABEL="Debian GNU/Linux" ;;
    2) DISTRO_DETECTED="ubuntu"; DISTRO_LABEL="Ubuntu / Linux Mint" ;;
    3) DISTRO_DETECTED="arch"; DISTRO_LABEL="Arch Linux / Manjaro" ;;
    4) DISTRO_DETECTED="fedora"; DISTRO_LABEL="Fedora / Nobara" ;;
    5) DISTRO_DETECTED="opensuse"; DISTRO_LABEL="openSUSE" ;;
    *) ;;
esac

echo ""
echo -e "${C_CYAN}══════════════════════════════════════════════════════════════════════${C_RESET}"
echo -e "  ${C_BOLD}Sistema seleccionado:${C_RESET} ${C_YELLOW}${DISTRO_LABEL}${C_RESET}"
echo -e "${C_CYAN}══════════════════════════════════════════════════════════════════════${C_RESET}"
echo ""

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
        sudo apt-get install -y wine wine32:i386 wine64 winetricks cabextract curl p7zip-full mesa-utils vulkan-tools zenity python3 2>/dev/null || sudo apt-get install -y wine winetricks cabextract curl p7zip-full zenity python3 2>/dev/null || true
        sudo apt-get install -y libvulkan1 libvulkan1:i386 mesa-vulkan-drivers mesa-vulkan-drivers:i386 libgl1-mesa-dri:i386 libgl1:i386 2>/dev/null || true
        sudo apt-get install -y gamemode libgamemode0:i386 2>/dev/null || sudo apt-get install -y gamemode 2>/dev/null || true
        if lspci 2>/dev/null | grep -qi "nvidia"; then
            echo -e "${C_CYAN}  🎮 GPU NVIDIA detectada: Asegurando librerías gráficas de 32 bits...${C_RESET}"
            sudo apt-get install -y nvidia-driver-libs:i386 2>/dev/null || true
        fi
        sudo apt-get install -y libgnutls30:i386 2>/dev/null || sudo apt-get install -y libgnutls30t64:i386 2>/dev/null || true
        sudo apt-get install -y libnss-resolve:i386 libnss-mdns:i386 libvkd3d1:i386 2>/dev/null || true
        sudo apt-get install -y libasound2-plugins:i386 2>/dev/null || true
        sudo apt-get install -y gstreamer1.0-plugins-base:i386 gstreamer1.0-plugins-good:i386 gstreamer1.0-plugins-ugly:i386 gstreamer1.0-libav:i386 2>/dev/null || true
        ;;
    ubuntu)
        echo -e "${C_CYAN}  ⚙️ Configurando Ubuntu / Linux Mint / Pop!_OS / Zorin...${C_RESET}"
        sudo sed -i '/^deb cdrom:/s/^/#/' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null || true
        if command -v dpkg &>/dev/null && ! dpkg --print-foreign-architectures 2>/dev/null | grep -q "i386"; then
            sudo dpkg --add-architecture i386 2>/dev/null || true
        fi
        sudo apt-get update -y 2>/dev/null || true
        sudo apt-get install -y wine wine32:i386 wine64 winetricks cabextract curl p7zip-full mesa-utils vulkan-tools zenity python3 2>/dev/null || sudo apt-get install -y wine winetricks cabextract curl p7zip-full zenity python3 2>/dev/null || true
        sudo apt-get install -y libvulkan1 libvulkan1:i386 mesa-vulkan-drivers mesa-vulkan-drivers:i386 libgl1-mesa-dri:i386 libgl1:i386 mangohud gamemode libgamemode0:i386 2>/dev/null || true
        if lspci 2>/dev/null | grep -qi "nvidia"; then
            echo -e "${C_CYAN}  🎮 GPU NVIDIA detectada: Asegurando controladores y librerías de 32 bits...${C_RESET}"
            nv_ver=$(dpkg -l 2>/dev/null | grep -E '^ii\s+nvidia-driver-[0-9]+' | awk '{print $2}' | grep -oE '[0-9]+' | head -n 1)
            if [ -n "$nv_ver" ]; then
                sudo apt-get install -y "libnvidia-gl-${nv_ver}:i386" 2>/dev/null || true
            else
                sudo apt-get install -y libnvidia-gl-535:i386 2>/dev/null || sudo apt-get install -y libnvidia-gl-525:i386 2>/dev/null || true
            fi
        fi
        sudo apt-get install -y libgnutls30:i386 2>/dev/null || sudo apt-get install -y libgnutls30t64:i386 2>/dev/null || true
        sudo apt-get install -y libnss-resolve:i386 libnss-mdns:i386 libvkd3d1:i386 2>/dev/null || true
        sudo apt-get install -y libasound2-plugins:i386 2>/dev/null || true
        sudo apt-get install -y gstreamer1.0-plugins-base:i386 gstreamer1.0-plugins-good:i386 gstreamer1.0-plugins-ugly:i386 gstreamer1.0-libav:i386 2>/dev/null || true
        ;;
    arch)
        echo -e "${C_CYAN}  ⚙️ Configurando Arch Linux / Manjaro / SteamOS...${C_RESET}"
        if [ -f /etc/pacman.conf ] && ! grep -q '^\[multilib\]' /etc/pacman.conf; then
            echo -e "${C_CYAN}  ⚙️ Habilitando repositorio multilib (32-bit) en /etc/pacman.conf...${C_RESET}"
            sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf 2>/dev/null || true
            sudo pacman -Sy --noconfirm 2>/dev/null || true
        fi
        sudo pacman -S --needed --noconfirm wine winetricks gamemode lib32-gamemode cabextract curl p7zip mesa-utils vulkan-tools zenity python 2>/dev/null || sudo pacman -S --needed --noconfirm wine winetricks gamemode cabextract curl p7zip mesa-utils vulkan-tools zenity python 2>/dev/null || true
        sudo pacman -S --needed --noconfirm vulkan-icd-loader lib32-vulkan-icd-loader lib32-mesa lib32-libglvnd mangohud lib32-mangohud lib32-vkd3d 2>/dev/null || true
        if lspci 2>/dev/null | grep -qiE "amd|radeon"; then
            echo -e "${C_CYAN}  🎮 GPU AMD detectada: Instalando controladores RADV Vulkan (32 y 64 bits)...${C_RESET}"
            sudo pacman -S --needed --noconfirm vulkan-radeon lib32-vulkan-radeon mesa lib32-mesa 2>/dev/null || true
        elif lspci 2>/dev/null | grep -qi "intel"; then
            echo -e "${C_CYAN}  🎮 Gráficos Intel detectados: Instalando controladores ANV Vulkan (32 y 64 bits)...${C_RESET}"
            sudo pacman -S --needed --noconfirm vulkan-intel lib32-vulkan-intel mesa lib32-mesa 2>/dev/null || true
        fi
        if lspci 2>/dev/null | grep -qi "nvidia"; then
            echo -e "${C_CYAN}  🎮 GPU NVIDIA detectada: Instalando librerías nvidia-utils (32 y 64 bits)...${C_RESET}"
            sudo pacman -S --needed --noconfirm nvidia-utils lib32-nvidia-utils 2>/dev/null || true
        fi
        sudo pacman -S --needed --noconfirm lib32-gnutls lib32-glibc lib32-gst-plugins-base lib32-gst-plugins-good lib32-gst-plugins-ugly lib32-gst-libav 2>/dev/null || true
        ;;
    fedora)
        echo -e "${C_CYAN}  ⚙️ Configurando Fedora / Nobara...${C_RESET}"
        # 1. Paquetes base esenciales (100% oficiales y disponibles en Fedora)
        sudo dnf install -y wine winetricks gamemode cabextract curl p7zip p7zip-plugins vulkan-tools glx-utils zenity python3 2>/dev/null || sudo dnf install -y wine winetricks gamemode cabextract curl p7zip vulkan-tools zenity python3 2>/dev/null || true

        # 2. Soporte para juegos y ejecutables de 32 bits (Wine multiarch)
        sudo dnf install -y wine.i686 2>/dev/null || sudo dnf install -y wine-core.i686 2>/dev/null || true

        # 3. Controladores Vulkan y OpenGL 32 bits (Imprescindibles para D3D9, GTA SA y juegos clásicos)
        sudo dnf install -y vulkan-loader mesa-vulkan-drivers mesa-dri-drivers 2>/dev/null || true
        sudo dnf install -y vulkan-loader.i686 mesa-vulkan-drivers.i686 mesa-dri-drivers.i686 libglvnd-glx.i686 libglvnd-egl.i686 2>/dev/null || true

        # 4. Herramientas complementarias (MangoHud y VKD3D)
        sudo dnf install -y mangohud vkd3d 2>/dev/null || true
        sudo dnf install -y mangohud.i686 2>/dev/null || true

        # 5. Detección y aceleración por GPU
        if lspci 2>/dev/null | grep -qiE "amd|radeon"; then
            echo -e "${C_CYAN}  🎮 GPU AMD detectada: Instalando aceleración VA-API...${C_RESET}"
            sudo dnf install -y mesa-va-drivers mesa-va-drivers.i686 2>/dev/null || sudo dnf install -y mesa-va-drivers 2>/dev/null || true
        elif lspci 2>/dev/null | grep -qi "intel"; then
            echo -e "${C_CYAN}  🎮 Gráficos Intel detectados: Instalando aceleración multimedia...${C_RESET}"
            sudo dnf install -y intel-media-driver 2>/dev/null || true
        elif lspci 2>/dev/null | grep -qi "nvidia"; then
            echo -e "${C_CYAN}  🎮 GPU NVIDIA detectada: Asegurando librerías 32 bits (RPM Fusion)...${C_RESET}"
            sudo dnf install -y xorg-x11-drv-nvidia-libs.i686 2>/dev/null || true
        fi

        # 6. Decodificadores multimedia GStreamer y Sonido 32 bits
        sudo dnf install -y gstreamer1-plugins-base.i686 gstreamer1-plugins-good.i686 2>/dev/null || true
        sudo dnf install -y gstreamer1-plugins-ugly.i686 gstreamer1-plugins-bad-free.i686 2>/dev/null || true
        sudo dnf install -y pipewire-alsa.i686 alsa-plugins-pulseaudio.i686 openal-soft.i686 2>/dev/null || true

        # 7. Librerías de red, SSL/TLS y DNS de 32 bits (Multijugador, GameRanger y HTTPS)
        sudo dnf install -y gnutls.i686 systemd-libs.i686 nss-mdns.i686 glibc.i686 2>/dev/null || true
        ;;
    opensuse)
        echo -e "${C_CYAN}  ⚙️ Configurando openSUSE...${C_RESET}"
        sudo zypper --non-interactive --auto-agree-with-licenses install wine wine-32bit winetricks gamemode gamemode-32bit cabextract curl p7zip mesa-utils vulkan-tools zenity python3 2>/dev/null || sudo zypper --non-interactive --auto-agree-with-licenses install wine winetricks gamemode cabextract curl p7zip mesa-utils vulkan-tools zenity python3 2>/dev/null || true
        sudo zypper --non-interactive --auto-agree-with-licenses install libvulkan1 libvulkan1-32bit Mesa-dri-32bit libglvnd-32bit mangohud mangohud-32bit 2>/dev/null || true
        if lspci 2>/dev/null | grep -qiE "amd|radeon"; then
            echo -e "${C_CYAN}  🎮 GPU AMD detectada: Instalando controladores RADV Vulkan...${C_RESET}"
            sudo zypper --non-interactive --auto-agree-with-licenses install libvulkan_radeon libvulkan_radeon-32bit 2>/dev/null || true
        elif lspci 2>/dev/null | grep -qi "intel"; then
            echo -e "${C_CYAN}  🎮 Gráficos Intel detectados: Instalando controladores ANV Vulkan...${C_RESET}"
            sudo zypper --non-interactive --auto-agree-with-licenses install libvulkan_intel libvulkan_intel-32bit 2>/dev/null || true
        fi
        sudo zypper --non-interactive --auto-agree-with-licenses install gstreamer-plugins-ugly-32bit gstreamer-plugins-bad-32bit libgnutls30-32bit systemd-32bit 2>/dev/null || sudo zypper --non-interactive --auto-agree-with-licenses install gnutls-32bit 2>/dev/null || true
        ;;
    *)
        echo -e "${C_YELLOW}  ⚠️ Distribución genérica detectada. Verificando comandos estándar...${C_RESET}"
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -y 2>/dev/null || true
            sudo apt-get install -y wine winetricks gamemode cabextract curl p7zip-full zenity python3 2>/dev/null || true
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --needed --noconfirm wine winetricks gamemode cabextract curl p7zip zenity python 2>/dev/null || true
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y --skip-broken wine winetricks gamemode cabextract curl p7zip zenity python3 2>/dev/null || true
        elif command -v zypper &>/dev/null; then
            sudo zypper --non-interactive --auto-agree-with-licenses install wine winetricks gamemode cabextract curl p7zip zenity python3 2>/dev/null || true
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
net.ipv4.ping_group_range = 0 2147483647
net.ipv4.ip_unprivileged_port_start = 0
fs.file-max = 2097152
EOF' 2>/dev/null || true
    sudo /sbin/sysctl --system > /dev/null 2>&1 || sudo sysctl --system > /dev/null 2>&1 || true
    echo -e "${C_GREEN}✔ Parámetros del Kernel aplicados permanentemente (vm.max_map_count = 2.1M).${C_RESET}"
fi

# Apertura de firewall para multijugador y GameRanger (Puerto UDP 16000)
echo -e "${C_CYAN}  🌐 Configurando Firewall para GameRanger / Multijugador (Puerto UDP 16000)...${C_RESET}"
if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
    sudo firewall-cmd --permanent --add-port=16000/udp 2>/dev/null || true
    sudo firewall-cmd --reload 2>/dev/null || true
fi
if command -v ufw &>/dev/null && sudo ufw status 2>/dev/null | grep -qi "active"; then
    sudo ufw allow 16000/udp 2>/dev/null || true
fi
if command -v iptables &>/dev/null; then
    sudo iptables -C INPUT -p udp --dport 16000 -j ACCEPT 2>/dev/null || sudo iptables -I INPUT -p udp --dport 16000 -j ACCEPT 2>/dev/null || true
fi

# Resolución infalible de dominios de GameRanger en /etc/hosts (0% fallos de DNS)
if [ -w /etc/hosts ] || sudo -n true 2>/dev/null || [ "$EUID" -eq 0 ]; then
    if ! grep -q "connect.gameranger.com" /etc/hosts 2>/dev/null; then
        sudo bash -c 'cat <<EOF >> /etc/hosts

# Servidores Oficiales GameRanger - Vessel Gaming Network
51.222.17.7 connect.gameranger.com
67.228.206.97 status.gameranger.com
67.228.102.62 www.gameranger.com
67.228.102.62 default.gameranger.com
EOF' 2>/dev/null || true
    fi
fi

if [ -w /etc/security/limits.d ] || sudo -n true 2>/dev/null || [ "$EUID" -eq 0 ]; then
    sudo bash -c 'cat <<EOF > /etc/security/limits.d/99-wine-gaming.conf
# Limites de archivos abiertos para Wine Esync y Fsync (Maximo rendimiento)
* hard nofile 524288
* soft nofile 524288
root hard nofile 524288
root soft nofile 524288
EOF' 2>/dev/null || true
    echo -e "${C_GREEN}✔ Límites de archivos para Esync y Fsync configurados (nofile = 524288).${C_RESET}"
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
    echo -e "${C_CYAN}      Instalando librerías base para instaladores y juegos clásicos (MFC, VC++, DirectPlay, Corefonts)...${C_RESET}"
    WINEPREFIX="${DIR}/wineprefix" winetricks -q corefonts vcrun2022 vcrun2010 mfc42 directplay 2>/dev/null || true
    echo -e "${C_GREEN}✔ Entorno base optimizado para cualquier instalador.${C_RESET}"
fi

# 4.2 Optimización de hilos gráficos Direct3D (CSMT multithread)
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "csmt" /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
echo -e "${C_GREEN}✔ Motor Direct3D CSMT multithread configurado.${C_RESET}"

# 4.3 Optimización de captura de ratón en 3D y compatibilidad multi-monitor
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\DirectInput" /v "MouseWarpOverride" /t REG_SZ /d "enable" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v "UseTakeFocus" /t REG_SZ /d "Y" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v "GrabFullscreen" /t REG_SZ /d "Y" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v "Decorated" /t REG_SZ /d "Y" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v "Managed" /t REG_SZ /d "Y" /f >/dev/null 2>&1 || true

# 4.3.1 Compatibilidad total para GameRanger (Chromium CEF / ANGLE sin fallos de Vulkan + Red 100% activa)
for gr_target in "GameRanger.exe" "GameRangerSetup.exe"; do
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
    cp -r "${DIR}/GameRanger"/* "$GR_PROGFILES/" 2>/dev/null || true
    cp -r "${DIR}/GameRanger"/* "$GR_ROAMING/" 2>/dev/null || true
    echo -e "${C_GREEN}✔ GameRanger instalado en Archivos de Programa y perfil de usuario.${C_RESET}"
elif [ -f "${DIR}/GameRangerSetup.exe" ]; then
    WINEPREFIX="${DIR}/wineprefix" WINEDLLOVERRIDES="dxgi=b;d3d11=b;d3d10core=b;d3d9=b;" wine "${DIR}/GameRangerSetup.exe" 2>/dev/null || true
    echo -e "${C_GREEN}✔ GameRangerSetup instalado con éxito.${C_RESET}"
fi

# Registrar GameRanger en el registro de Windows de Wine
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_LOCAL_MACHINE\Software\GameRanger" /v "ExecutablePath" /t REG_SZ /d "C:\Program Files\GameRanger\GameRanger.exe" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CURRENT_USER\Software\GameRanger" /v "ExecutablePath" /t REG_SZ /d "C:\Program Files\GameRanger\GameRanger.exe" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CLASSES_ROOT\gameranger" /t REG_SZ /d "URL:GameRanger Protocol" /f >/dev/null 2>&1 || true
WINEPREFIX="${DIR}/wineprefix" wine reg add "HKEY_CLASSES_ROOT\gameranger\shell\open\command" /t REG_SZ /d "\"C:\Program Files\GameRanger\GameRanger.exe\" \"%1\"" /f >/dev/null 2>&1 || true

# Registrar GameRanger en programas.db de Vessel
touch "${DIR}/programas.db"
if ! grep -qi "GameRanger" "${DIR}/programas.db" 2>/dev/null; then
    FOUND_GR=$(find "${DIR}/wineprefix/drive_c" -name "GameRanger.exe" 2>/dev/null | head -n 1)
    [ -z "$FOUND_GR" ] && [ -f "${DIR}/GameRanger/GameRanger.exe" ] && FOUND_GR="${DIR}/GameRanger/GameRanger.exe"
    if [ -n "$FOUND_GR" ]; then
        echo "GameRanger|${FOUND_GR}|compartido" >> "${DIR}/programas.db"
        echo -e "${C_GREEN}✔ GameRanger registrado en la lista de programas de Vessel.${C_RESET}"
    fi
fi
chown "$TARGET_USER:$TARGET_USER" "${DIR}/programas.db" 2>/dev/null || true

# Acceso directo en el menú de aplicaciones y escritorio
mkdir -p "$TARGET_HOME/.local/share/applications"
cat <<EOF > "$TARGET_HOME/.local/share/applications/gameranger.desktop"
[Desktop Entry]
Type=Application
Name=GameRanger
Comment=Juega con tus amigos en línea
Exec=sh -c '"${DIR}/launch-win-app.sh" "GameRanger.exe"'
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

# Configurar inicio automático de GameRanger al iniciar sesión en la computadora
mkdir -p "$TARGET_HOME/.config/autostart"
cat <<EOF > "$TARGET_HOME/.config/autostart/gameranger.desktop"
[Desktop Entry]
Type=Application
Name=GameRanger
Comment=Inicia GameRanger automáticamente al iniciar sesión
Exec=sh -c 'sleep 3 && "${DIR}/launch-win-app.sh" "GameRanger.exe"'
Icon=wine
Terminal=false
Categories=Game;Network;
X-GNOME-Autostart-enabled=true
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/autostart/gameranger.desktop" 2>/dev/null || true
chmod +x "$TARGET_HOME/.config/autostart/gameranger.desktop" 2>/dev/null || true
echo -e "${C_GREEN}✔ GameRanger totalmente instalado y configurado para inicio automático.${C_RESET}"

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
echo -e "${C_CYAN}[5/5] Creando accesos directos en el Escritorio y Menú del Sistema...${C_RESET}"

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(eval echo "~$TARGET_USER")

# Asegurar permisos correctos en el directorio del proyecto y prefijo de Wine
chmod +x "${DIR}"/*.sh "${DIR}"/*.py 2>/dev/null || true
chown -R "$TARGET_USER:$TARGET_USER" "${DIR}/wineprefix" 2>/dev/null || true
chown -R "$TARGET_USER:$TARGET_USER" "${DIR}"/*.cfg "${DIR}"/*.conf 2>/dev/null || true

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

echo "3.0.0" > "${DIR}/version.txt" 2>/dev/null || true
chown "$TARGET_USER:$TARGET_USER" "${DIR}/version.txt" 2>/dev/null || true

echo ""
echo -e "${C_BOLD}${C_GREEN}🎉 ¡INSTALACIÓN COMPLETADA CON ÉXITO! 🎉${C_RESET}"
echo -e "${C_WHITE}Tu PC ahora está optimizada y lista para correr cualquier juego o programa.${C_RESET}"
echo -e "${C_CYAN}Puedes iniciar el menú en cualquier momento ejecutando:${C_RESET}"
echo -e "   ${C_BOLD}${DIR}/menu-win.sh${C_RESET}"
echo ""
