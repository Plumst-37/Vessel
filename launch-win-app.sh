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

# Limpiar cualquier texto o pulsación residual en el búfer de entrada de la terminal
read -t 0.001 -n 10000 _discard_input 2>/dev/null || true

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DB_FILE="${DIR}/programas.db"

# 1. Cargar preferencias del usuario y detección de hardware universal
[ -f "${DIR}/config_rendimiento.cfg" ] && source "${DIR}/config_rendimiento.cfg"
source "${DIR}/hardware_detect.sh"

# 2. Aplicar optimizaciones dinámicas para el hardware real del equipo
aplicar_entorno_hardware

# 3. Procesar banderas opcionales (compatibilidad)
if [ "$1" = "--prefix" ]; then
    shift
    shift || true
fi

if [ $# -eq 0 ]; then
    echo "Uso: $0 /ruta/al/programa.exe [argumentos]"
    exit 1
fi

TARGET="$1"
shift || true

# 4. Definir la ruta del WINEPREFIX unificado
export WINEPREFIX="${DIR}/wineprefix"

# 4.0 Normalizar rutas relativas y resolución automática de GameRanger predeterminado
if [[ "$TARGET" != /* ]] && [ -f "${DIR}/${TARGET}" ]; then
    TARGET="${DIR}/${TARGET}"
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

        # Restaurar preferencias y sesión guardada del usuario si existen
        if [ ! -s "${GR_PREFS}/Settings" ] && [ -d "${DIR}/.gameranger_prefs_backup" ]; then
            mkdir -p "$GR_PREFS"
            cp -ru "${DIR}/.gameranger_prefs_backup"/* "$GR_PREFS/" 2>/dev/null || true
        fi

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

# 4.1 Resolver accesos directos de Windows (.lnk o .ink) al ejecutable real
if [[ "$TARGET" =~ \.([lL][nN][kK]|[iI][nN][kK])$ ]] && [ -f "$TARGET" ]; then
    echo "[*] Acceso directo detectado: $(basename "$TARGET"). Resolviendo ejecutable real..."
    if [ -f "${DIR}/resolver_lnk.py" ]; then
        RESOLVED_RES=$(python3 "${DIR}/resolver_lnk.py" "$TARGET" "${WINEPREFIX}" 2>/dev/null || true)
        RESOLVED_STATUS=$(echo "$RESOLVED_RES" | grep '^STATUS=' | cut -d= -f2-)
        RESOLVED_PATH=$(echo "$RESOLVED_RES" | grep '^RESOLVED_PATH=' | cut -d= -f2-)
        if [ "$RESOLVED_STATUS" = "RESOLVED" ] && [ -f "$RESOLVED_PATH" ]; then
            echo "[+] Acceso directo resuelto a: $RESOLVED_PATH"
            TARGET="$RESOLVED_PATH"
        fi
    fi
fi

# 4.2 Resolver scripts por lotes (.bat o .cmd) para omitir bucles infinitos de CPU
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

# 5. Auto-inicialización del prefijo si es nuevo
if [ ! -f "${WINEPREFIX}/system.reg" ]; then
    echo "[*] Configurando nuevo entorno de Windows unificado..."
    mkdir -p "$WINEPREFIX"
    wineboot -u
    if command -v dxvk-setup &>/dev/null && [ "$RENDERER_IN_USE" != "WineD3D (OpenGL Compatibilidad)" ]; then
        dxvk-setup install -y 2>/dev/null || true
    fi
fi

# 6. Configuración de pantalla completa universal, ratón ultra-fluido y estabilidad 3D
if [ ! -f "${WINEPREFIX}/.vessel_reg_v3" ]; then
    wine reg add "HKEY_CURRENT_USER\Software\Wine\DirectInput" /v MouseWarpOverride /t REG_SZ /d enable /f >/dev/null 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v UseTakeFocus /t REG_SZ /d N /f >/dev/null 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v GrabFullscreen /t REG_SZ /d Y /f >/dev/null 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v Decorated /t REG_SZ /d N /f >/dev/null 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\Software\Wine\X11 Driver" /v Managed /t REG_SZ /d Y /f >/dev/null 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v csmt /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v StrictDrawOrdering /t REG_SZ /d disabled /f >/dev/null 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v AlwaysOffscreen /t REG_SZ /d enabled /f >/dev/null 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v CheckDepthStencil /t REG_SZ /d enabled /f >/dev/null 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\X11 Driver" /v Decorated /t REG_SZ /d Y /f >/dev/null 2>&1 || true
    touch "${WINEPREFIX}/.vessel_reg_v3" 2>/dev/null || true
fi

# 7. Generar archivo DXVK optimizado según la CPU y límite de FPS configurado
if [ "$RENDERER_IN_USE" != "WineD3D (OpenGL Compatibilidad)" ]; then
    export DXVK_CONFIG_FILE="${DIR}/dxvk.conf"
    if [ -x "${DIR}/generar_dxvk_conf.sh" ]; then
        "${DIR}/generar_dxvk_conf.sh"
    fi
else
    unset DXVK_CONFIG_FILE
fi

# 8. Soporte para AMD FSR (FidelityFX Super Resolution - Reescalado de FPS)
if [ "$ACTIVAR_FSR" = "1" ]; then
    export WINE_FULLSCREEN_FSR=1
    export WINE_FULLSCREEN_FSR_STRENGTH="${FSR_STRENGTH:-2}"
fi

# 9. Detección del ejecutable de Wine (personalizado, Wine-TKG o del sistema)
if [ -f "${DIR}/wine-tkg-build/bin/wine" ]; then
    WINE_CMD="${DIR}/wine-tkg-build/bin/wine"
elif command -v wine &> /dev/null; then
    WINE_CMD="wine"
else
    echo "[-] Error: No se encontró ningún binario de Wine instalado en el sistema."
    echo "    Ejecuta el instalador con: ./instalar.sh"
    exit 1
fi

# 10. Uso condicional de GameMode según perfil
GAMEMODE=""
if [ "$PERFIL_RENDIMIENTO" != "ahorro" ] && command -v gamemoderun &> /dev/null; then
    GAMEMODE="gamemoderun"
fi

# 11. Obtener directorio y nombre del archivo
TARGET_DIR="$(cd "$(dirname "$TARGET")" && pwd)"
TARGET_FILE="$(basename "$TARGET")"

# ==============================================================================
# OPTIMIZACIÓN UNIVERSAL DE RED, WIFI Y MULTIJUGADOR PARA WINE
# - Permite a todos los programas y juegos conectarse a Internet y servidores online
# - Desactiva el ahorro de energía en adaptadores WiFi para evitar caídas de paquetes
# - Habilita rangos de ping ICMP y sockets no privilegiados en el Kernel
# - Configura resolución DNS y servidores maestros comunitarios en hosts
# - Configura sondas NCSI en el registro para que Windows detecte 100% de conectividad
# - Abre puertos de firewall para GameRanger (16000), DirectPlay (2300-2400, 47624) y juegos
# ==============================================================================
optimizar_red_y_wifi() {
    # 1. Privilegios de sockets y ping ICMP en el Kernel para Wine
    sysctl -w net.ipv4.ping_group_range="0 2147483647" 2>/dev/null || true
    sysctl -w net.ipv4.ip_unprivileged_port_start=0 2>/dev/null || true

    # 2. Desactivar ahorro de energía en interfaz WiFi para eliminar latencia y cortes
    local wifi_iface
    wifi_iface=$(ip link 2>/dev/null | grep -oE '\bwl[a-zA-Z0-9]+\b' | head -n 1)
    if [ -n "$wifi_iface" ]; then
        iw dev "$wifi_iface" set power_save off 2>/dev/null || true
        sudo -n iw dev "$wifi_iface" set power_save off 2>/dev/null || true
    fi

    # 3. Asegurar archivo hosts y resolución de servidores en el prefijo
    local etc_dir="${WINEPREFIX}/drive_c/windows/system32/drivers/etc"
    mkdir -p "$etc_dir"
    if [ ! -f "${etc_dir}/hosts" ] || ! grep -q "swat4stats" "${etc_dir}/hosts" 2>/dev/null; then
        cat << 'EOF' > "${etc_dir}/hosts"
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
    fi

    # 4. Asegurar parámetros de red e Internet (NCSI / NLA / DNS) en el registro de Wine
    if [ ! -f "${WINEPREFIX}/.vessel_net_ok" ]; then
        wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters" /v NameServer /t REG_SZ /d "1.1.1.1,8.8.8.8" /f >/dev/null 2>&1 || true
        wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters" /v DhcpNameServer /t REG_SZ /d "1.1.1.1,8.8.8.8" /f >/dev/null 2>&1 || true
        wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters" /v EnableDHCP /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
        wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\Default" /v NameServer /t REG_SZ /d "1.1.1.1,8.8.8.8" /f >/dev/null 2>&1 || true
        wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\Default" /v DhcpNameServer /t REG_SZ /d "1.1.1.1,8.8.8.8" /f >/dev/null 2>&1 || true
        wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\Default" /v EnableDHCP /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true

        # Sondas NCSI (Windows Network Connectivity Status Indicator) para que todos los juegos y launchers detecten conexión activa a Internet
        wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v EnableActiveProbing /t REG_DWORD /d 1 /f >/dev/null 2>&1 || true
        wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v ActiveWebProbeHost /t REG_SZ /d "www.msftncsi.com" /f >/dev/null 2>&1 || true
        wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v ActiveWebProbeContent /t REG_SZ /d "Microsoft NCSI" /f >/dev/null 2>&1 || true
        wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v ActiveDnsProbeHost /t REG_SZ /d "dns.msftncsi.com" /f >/dev/null 2>&1 || true
        wine reg add "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v ActiveDnsProbeContent /t REG_SZ /d "131.107.255.255" /f >/dev/null 2>&1 || true

        wine reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" /v NoActiveProbe /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true
        wine reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" /v DisablePassivePolling /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true

        wine reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v GlobalUserOffline /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true
        wine reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true
        wine reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v CertificateRevocation /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true

        touch "${WINEPREFIX}/.vessel_net_ok" 2>/dev/null || true
    fi

    # 5. Apertura de puertos Firewall para Multiplayer y GameRanger
    if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
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

# Overrides universales de red, sockets, SSL/TLS, DirectPlay y librerías base
export WINEDLLOVERRIDES="winemenubuilder.exe=d;dnsapi=n,b;dplayx=n,b;dpnet=n,b;dpwsockx=n,b;ws2_32=b;wininet=b;iphlpapi=b;secur32=b;winhttp=b;${WINEDLLOVERRIDES}"

# 11.1 Configuración específica para el cliente de lobby GameRanger
EXTRA_APP_ARGS=""
if [[ "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]]; then
    # GameRanger es una aplicación de escritorio/chat con interfaz Chromium CEF / ANGLE embebida.
    # Sus subventanas web no son superficies 3D exclusivas y fallan con swapchains Vulkan (VK_ERROR_OUT_OF_HOST_MEMORY).
    # Desactivamos DXVK para GameRanger y usamos WineD3D nativo, eliminando cualquier cuelgue de UI.
    export RENDERER_IN_USE="WineD3D (Lobby Compatibilidad)"
    export PROTON_USE_WINED3D=1
    export WINEDLLOVERRIDES="winemenubuilder.exe=d;dxgi=b;d3d11=b;d3d10core=b;d3d9=b;dnsapi=n,b;dplayx=n,b;dpnet=n,b;dpwsockx=n,b;riched20=n,b;riched32=n,b;ws2_32=b;wininet=b;iphlpapi=b;secur32=b;winhttp=b"
    unset DXVK_CONFIG_FILE
    unset DXVK_STATE_CACHE_PATH
    unset DXVK_ASYNC
    unset DXVK_GPLASYNCCACHE

    # Desactivar gamemode para evitar mensajes en consola (GameRanger es una app de chat 2D)
    GAMEMODE=""

    # Forzar modo Windows 7 y renderer GL en registro Wine AppDefaults para GameRanger
    wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe" /v "Version" /t REG_SZ /d "win7" /f >/dev/null 2>&1 || true
    wine reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\GameRanger.exe\Direct3D" /v "renderer" /t REG_SZ /d "gl" /f >/dev/null 2>&1 || true

    # Argumentos críticos para Chromium CEF: eliminan pantalla negra y silencian logs internos
    EXTRA_APP_ARGS="--disable-gpu --disable-gpu-compositing --in-process-gpu --no-sandbox --log-severity=disable --silent"
fi

# Moverse al directorio donde reside el juego (vital para rutas relativas y DLLs)
cd "$TARGET_DIR"

# Asegurar permisos de escritura para que los mods puedan guardar configs, logs y partidas
[ -w "$TARGET_DIR" ] || chmod -R u+w "$TARGET_DIR" 2>/dev/null || true

# ==============================================================================
# AUTO-OPTIMIZACIÓN UNIVERSAL DE PANTALLA COMPLETA, GRÁFICOS 3D Y CERO TEARING
# - Adapta automáticamente la pantalla completa nativa del monitor en cualquier PC
# - Elimina deformaciones de aspecto 3D (Aspect=DEFAULT para FOV matemático perfecto)
# - Corrige motores RE Engine (elimina renderizado entrelazado y deformaciones de lente)
# - Enforce modo pantalla completa exclusiva en Rockstar Games (Windowed=0)
# - Configura Widescreen Fix y desactiva modo ventana forzado en GTA San Andreas
# - Enforce pantalla completa en Unreal Engine (SWAT 4), Capcom MT Framework y cnc-ddraw
# ==============================================================================
auto_optimizar_juegos_3d() {
    # 1. Detectar resolución óptima del monitor principal en cualquier PC (Intel, AMD, NVIDIA)
    local best_res
    if command -v xrandr &>/dev/null; then
        best_res=$(xrandr 2>/dev/null | grep -E ' connected primary' | grep -oE '[0-9]{3,4}x[0-9]{3,4}' | head -n 1)
        [ -z "$best_res" ] && best_res=$(xrandr 2>/dev/null | grep -E '\bconnected\b' | grep -oE '[0-9]{3,4}x[0-9]{3,4}' | head -n 1)
    fi
    if [ -z "$best_res" ]; then
        best_res=$(cat /sys/class/drm/*/modes 2>/dev/null | grep -oE '^[0-9]{3,4}x[0-9]{3,4}' | head -n 1)
    fi
    [ -z "$best_res" ] && best_res="1280x720"

    local best_w best_h
    best_w=$(echo "$best_res" | cut -dx -f1)
    best_h=$(echo "$best_res" | cut -dx -f2)

    # 2. CAPCOM MT FRAMEWORK (Resident Evil 4/5/6, Revelations, DMC4, etc.)
    local capcom_dir="$HOME/Documentos/CAPCOM"
    [ ! -d "$capcom_dir" ] && capcom_dir="${WINEPREFIX}/drive_c/users/${USER}/Documents/CAPCOM"

    if [[ "$TARGET" =~ (Resident\ Evil|BH6|re6|RE6) ]] || [[ "$TARGET_DIR" =~ (Resident\ Evil|BH6|re6|RE6) ]]; then
        mkdir -p "${capcom_dir}/RESIDENT EVIL 6"
        local re6_cfg="${capcom_dir}/RESIDENT EVIL 6/config.ini"
        if [ ! -f "$re6_cfg" ]; then
            cat <<EOF > "$re6_cfg"
[GAME]
MouseBaseSpeed=1.500000
[GRAPHICS]
HDR=DEFAULT
AntiAlias=NONE
AltAntiAlias=FXAA3HQ
DeferredLightingLight=APPROXIMATE_SPECULAR
ScreenQuality=HIGH
SLI=OFF
Stereo=OFF
MotionBlurEnabled=OFF
ShadowsQuality=MEDIUM
FrameRate=VARIABLE
TextureDetail=HIGH
TextureMipLimite=0
[DISPLAY]
Resolution=${best_res}
Aspect=DEFAULT
RefreshRate=60.00Hz
FullScreen=ON
VSYNC=OFF
[SOUNDS]
SeVoiceNum=128
[CPU]
JobThread=3
RenderingThread=ON
[Window]
MainX=0
MainY=0
EOF
            echo "[+] Configuración de alta fidelidad 3D en pantalla completa generada para Resident Evil 6 (${best_res})."
        fi
    fi

    # Corregir configs existentes de Capcom MT Framework:
    local dirs_a_buscar=("$capcom_dir")
    [ -d "${TARGET_DIR}/gamedata/optimization" ] && dirs_a_buscar+=("${TARGET_DIR}/gamedata/optimization")
    [ -d "${TARGET_DIR}/optimization" ] && dirs_a_buscar+=("${TARGET_DIR}/optimization")
    [ -d "$TARGET_DIR" ] && dirs_a_buscar+=("$TARGET_DIR")

    for dir_c in "${dirs_a_buscar[@]}"; do
        if [ -d "$dir_c" ]; then
            find "$dir_c" -maxdepth 3 -name "config.ini" 2>/dev/null | while read -r cini; do
                if grep -q "\[GRAPHICS\]" "$cini" 2>/dev/null || grep -q "\[DISPLAY\]" "$cini" 2>/dev/null; then
                    sed -i 's/^FullScreen=OFF/FullScreen=ON/' "$cini" 2>/dev/null || true
                    sed -i 's/^VSYNC=ON/VSYNC=OFF/' "$cini" 2>/dev/null || true
                    sed -i 's/^MotionBlurEnabled=ON/MotionBlurEnabled=OFF/' "$cini" 2>/dev/null || true
                    # Aspect=DEFAULT asegura que el motor 3D calcule la perspectiva exacta sin achatamiento ni estiramientos
                    sed -i 's/^Aspect=.*/Aspect=DEFAULT/' "$cini" 2>/dev/null || true
                    
                    local cur_res
                    cur_res=$(grep -E '^Resolution=' "$cini" 2>/dev/null | cut -d'=' -f2 | tr -d '\r\n ')
                    if [ -z "$cur_res" ] || [ "$cur_res" = "Unknown" ] || [ "$cur_res" = "0x0" ] || ! echo "$cur_res" | grep -qE '^[0-9]+x[0-9]+$'; then
                        sed -i "s/^Resolution=.*/Resolution=${best_res}/" "$cini" 2>/dev/null || true
                    elif command -v xrandr &>/dev/null && ! xrandr 2>/dev/null | grep -q "\b${cur_res}\b"; then
                        sed -i "s/^Resolution=.*/Resolution=${best_res}/" "$cini" 2>/dev/null || true
                    fi
                    
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

    # 2.1 CAPCOM RE ENGINE (Resident Evil 4 Remake, RE2/3 Remake, RE7, RE8, DMC5)
    find "$TARGET_DIR" -maxdepth 3 -name "*config*.ini" 2>/dev/null | while read -r re_ini; do
        if grep -q "\[AppRender\]" "$re_ini" 2>/dev/null || grep -q "\[RenderConfig\]" "$re_ini" 2>/dev/null; then
            # Forzar Pantalla Completa nativa en RE Engine
            sed -i 's/^FullScreenMode=.*/FullScreenMode=true/' "$re_ini" 2>/dev/null || true
            sed -i 's/^WindowMode=.*/WindowMode=FullScreen/' "$re_ini" 2>/dev/null || true
            sed -i 's/^AppWindowMode=.*/AppWindowMode=0/' "$re_ini" 2>/dev/null || true
            # CORRECCIÓN 3D CRÍTICA: Cambiar método de renderizado entrelazado (2) a progresivo normal (1)
            # El renderizado entrelazado provoca desgarros y mallas 3D completamente dentadas/deformes
            sed -i 's/^AppRenderingMethod=.*/AppRenderingMethod=1/' "$re_ini" 2>/dev/null || true
            # Desactivar distorsión de lente óptica que deforma la perspectiva 3D
            sed -i 's/^AppLensDistorsion=.*/AppLensDistorsion=0/' "$re_ini" 2>/dev/null || true
            sed -i 's/^AppMotionBlur=.*/AppMotionBlur=0/' "$re_ini" 2>/dev/null || true
            sed -i 's/^AppFilmGrainNoise=.*/AppFilmGrainNoise=0/' "$re_ini" 2>/dev/null || true
            sed -i 's/^AppVsync=.*/AppVsync=0/' "$re_ini" 2>/dev/null || true
            # Buscar el modo de pantalla nativo correspondiente
            local dm_idx
            dm_idx=$(grep -B 1 "DisplayMode[0-9]*_Height=${best_h}" "$re_ini" 2>/dev/null | grep -E "DisplayMode[0-9]*_Width=${best_w}" | head -n 1 | grep -oE "DisplayMode[0-9]+" | tr -d 'DisplayMode')
            if [ -n "$dm_idx" ]; then
                sed -i "s/^AppResolution=.*/AppResolution=${dm_idx}/" "$re_ini" 2>/dev/null || true
                sed -i "s/^FullScreenDisplayMode=.*/FullScreenDisplayMode=${dm_idx}/" "$re_ini" 2>/dev/null || true
            else
                local max_dm
                max_dm=$(grep -oE "DisplayMode[0-9]+_Width" "$re_ini" 2>/dev/null | tr -d 'DisplayMode_Width' | sort -n | tail -n 1)
                if [ -n "$max_dm" ]; then
                    sed -i "s/^AppResolution=.*/AppResolution=${max_dm}/" "$re_ini" 2>/dev/null || true
                    sed -i "s/^FullScreenDisplayMode=.*/FullScreenDisplayMode=${max_dm}/" "$re_ini" 2>/dev/null || true
                fi
            fi
            echo "[+] RE Engine optimizado: Pantalla completa forzada, renderizado progresivo 3D y distorsión eliminada."
        fi
    done

    # 3. ROCKSTAR GAMES (GTA V, GTA IV, Max Payne 3, etc.)
    local rsg_dir="$HOME/Documentos/Rockstar Games"
    [ ! -d "$rsg_dir" ] && rsg_dir="${WINEPREFIX}/drive_c/users/${USER}/Documents/Rockstar Games"
    local rsg_dirs=("$rsg_dir")
    [ -d "$TARGET_DIR" ] && rsg_dirs+=("$TARGET_DIR")
    for r_dir in "${rsg_dirs[@]}"; do
        if [ -d "$r_dir" ]; then
            find "$r_dir" -maxdepth 3 -name "settings.xml" 2>/dev/null | while read -r sxml; do
                sed -i "s/<ScreenWidth value=\"[0-9]*\"/<ScreenWidth value=\"${best_w}\"/" "$sxml" 2>/dev/null || true
                sed -i "s/<ScreenHeight value=\"[0-9]*\"/<ScreenHeight value=\"${best_h}\"/" "$sxml" 2>/dev/null || true
                # Windowed 0 = Pantalla Completa Exclusiva Real
                sed -i 's/<Windowed value="[0-9]*"/<Windowed value="0"/' "$sxml" 2>/dev/null || true
                sed -i 's/<VSync value="[0-9]*"/<VSync value="0"/' "$sxml" 2>/dev/null || true
                sed -i 's/<PauseOnFocusLoss value="[0-9]*"/<PauseOnFocusLoss value="0"/' "$sxml" 2>/dev/null || true
                sed -i 's/<AspectRatio value="[0-9]*"/<AspectRatio value="0"/' "$sxml" 2>/dev/null || true
                sed -i 's/<AnisotropicFiltering value="[0-9]*"/<AnisotropicFiltering value="16"/' "$sxml" 2>/dev/null || true
                sed -i 's/<FXAA_Enabled value="false"/<FXAA_Enabled value="true"/' "$sxml" 2>/dev/null || true
                sed -i 's/<LodScale value="0.000000"/<LodScale value="1.000000"/' "$sxml" 2>/dev/null || true
                sed -i 's/<PedLodBias value="0.000000"/<PedLodBias value="0.200000"/' "$sxml" 2>/dev/null || true
                sed -i 's/<VehicleLodBias value="0.000000"/<VehicleLodBias value="0.200000"/' "$sxml" 2>/dev/null || true
                if [ -n "$GPU_NAME" ]; then
                    sed -i "s|<VideoCardDescription>.*</VideoCardDescription>|<VideoCardDescription>${GPU_NAME}</VideoCardDescription>|" "$sxml" 2>/dev/null || true
                fi
            done
        fi
    done

    # 3.1 OPTIMIZACIÓN ESPECÍFICA GTA V (Carga rápida sin cuelgues ni saturación de hilos)
    if [[ "$TARGET_FILE" =~ (GTA5|PlayGTAV|gta5) ]]; then
        local gta_cmdline="${TARGET_DIR}/commandline.txt"
        if [ -f "$gta_cmdline" ]; then
            sed -i 's/^-FrameQueueLimit 0/-FrameQueueLimit 1/' "$gta_cmdline" 2>/dev/null || true
            sed -i '/^-hdr/d' "$gta_cmdline" 2>/dev/null || true
            grep -q '^-StraightIntoFreemode' "$gta_cmdline" || echo "-StraightIntoFreemode" >> "$gta_cmdline"
            sed -i '/^-scOfflineOnly/d' "$gta_cmdline" 2>/dev/null || true
            grep -q '^-novsync' "$gta_cmdline" || echo "-novsync" >> "$gta_cmdline"
            grep -q '^-fullscreen' "$gta_cmdline" || echo "-fullscreen" >> "$gta_cmdline"
            grep -q '^-width' "$gta_cmdline" || echo "-width ${best_w}" >> "$gta_cmdline"
            grep -q '^-height' "$gta_cmdline" || echo "-height ${best_h}" >> "$gta_cmdline"
            grep -q '^-disablespecular' "$gta_cmdline" || echo "-disablespecular" >> "$gta_cmdline"
            echo "[+] Archivo commandline.txt de GTA V optimizado (Pantalla completa y carga inmediata)."
        fi
    fi

    # 3.2 OPTIMIZACIÓN Y PROTECCIÓN GTA SAN ANDREAS (gta_sa.exe)
    if [[ "$TARGET_FILE" =~ (gta_sa|gta-sa|gtasa) ]]; then
        # Limpiar configuración de resolución previa que crashea al cambiar de PC/monitor
        find "${WINEPREFIX}/drive_c/users" -name "gta_sa.set" -delete 2>/dev/null || true
        rm -f "$HOME/Documentos/GTA San Andreas User Files/gta_sa.set" 2>/dev/null || true
        rm -f "$HOME/Documents/GTA San Andreas User Files/gta_sa.set" 2>/dev/null || true
        # Configurar Widescreen Fix para pantalla completa y aspecto perfecto
        find "$TARGET_DIR" -iname "GTASA.WidescreenFix.ini" 2>/dev/null | while read -r wf_ini; do
            sed -i "s/^ResX = .*/ResX = ${best_w}/" "$wf_ini" 2>/dev/null || true
            sed -i "s/^ResY = .*/ResY = ${best_h}/" "$wf_ini" 2>/dev/null || true
            sed -i "s/^ForceAspectRatio = .*/ForceAspectRatio = auto/" "$wf_ini" 2>/dev/null || true
        done
        # Si existe el plugin de modo ventana con borde, desactivar borde o renombrar para pantalla completa real
        find "$TARGET_DIR" -iname "III.VC.SA.WindowedMode.ini" 2>/dev/null | while read -r wm_ini; do
            sed -i "s/^ShowBorder = .*/ShowBorder = 0/" "$wm_ini" 2>/dev/null || true
        done
        find "$TARGET_DIR" -iname "III.VC.SA.WindowedMode.asi" 2>/dev/null | while read -r wm_asi; do
            mv "$wm_asi" "${wm_asi}.disabled" 2>/dev/null || true
        done
        # Desactivar GLThread para evitar fallos de renderizado en D3D9 con mods CLEO/ModLoader
        export mesa_glthread=false
        # Asegurar overrides esenciales para ASI Loader y librerías de sonido
        export WINEDLLOVERRIDES="vorbisfile=n,b;vorbishooked=n,b;dinput8=n,b;d3d9=n,b;${WINEDLLOVERRIDES}"
        echo "[+] GTA San Andreas optimizado: Pantalla completa nativa (${best_res}) y aspecto 3D corregido."
    fi

    # 4. UNREAL ENGINE 1/2/2.5/3/4 (SWAT 4, Deus Ex, Bioshock, etc.)
    local target_system_dir="$TARGET_DIR"
    [ -d "${TARGET_DIR}/System" ] && target_system_dir="${TARGET_DIR}/System"
    [ -d "${TARGET_DIR}/Content/System" ] && target_system_dir="${TARGET_DIR}/Content/System"

    # Relación de aspecto del monitor para FOV 3D exacto (elimina deformación y estiramiento de armas y modelos)
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
        # Ajuste de FOV 3D en Unreal Engine 2/2.5 para eliminar deformación de armas y perspectiva
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

    # 5. CNC-DDRAW / DIRECTDRAW GAMES (Age of Empires II, StarCraft, Red Alert 2, etc.)
    find "$TARGET_DIR" -maxdepth 2 -iname "ddraw.ini" 2>/dev/null | while read -r ddini; do
        sed -i 's/^fullscreen=.*/fullscreen=true/' "$ddini" 2>/dev/null || true
        sed -i 's/^windowed=.*/windowed=false/' "$ddini" 2>/dev/null || true
        sed -i "s/^width=.*/width=${best_w}/" "$ddini" 2>/dev/null || true
        sed -i "s/^height=.*/height=${best_h}/" "$ddini" 2>/dev/null || true
        sed -i 's/^boxing=.*/boxing=false/' "$ddini" 2>/dev/null || true
        sed -i 's/^maintas=.*/maintas=false/' "$ddini" 2>/dev/null || true
        echo "[+] DirectDraw / cnc-ddraw configurado en pantalla completa nativa (${best_res})."
    done
}
auto_optimizar_juegos_3d

# ==============================================================================
# AUTO-ACTIVACIÓN DE MODS, ASI LOADERS, RESHADE, ENB Y TRADUCCIONES
# Detecta automáticamente librerías de mods locales y activa el override nativo (n,b)
# para que funcionen inmediatamente sin tocar winecfg
# ==============================================================================
MOD_HOOKS=("ddraw" "d3d8" "d3d9" "d3d11" "d3d12" "dxgi" "dinput8" "dinput" "dsound" "dplayx" "dpnet" "version" "winmm" "vorbisfile" "xinput1_3" "xinput1_4" "xinput9_1_0" "x3daudio1_7" "binkw32" "binkw64" "bink2w64" "dbghelp" "msimg32" "opengl32")
MODS_ACTIVADOS=()

for hook in "${MOD_HOOKS[@]}"; do
    found_hook=$(find . -maxdepth 1 -iname "${hook}.dll" 2>/dev/null | head -n 1)
    if [ -n "$found_hook" ]; then
        export WINEDLLOVERRIDES="${hook}=n,b;${WINEDLLOVERRIDES}"
        MODS_ACTIVADOS+=("$(basename "$found_hook")")
    fi
done

CANT_ASI=$(ls -1 *.asi scripts/*.asi plugins/*.asi 2>/dev/null | wc -l)

# Modo Pantalla Nativo Directo en Hardware (sin capas virtuales)
ESCRITORIO_VIRTUAL="0"
RUN_PREFIX=""

echo ""
echo "[+] Ejecutando con Perfil [${PERFIL_RENDIMIENTO:-maximo}]..."
echo "    - CPU: ${CPU_MODEL} (${CPU_CORES} Hilos)"
echo "    - GPU: ${DETECTED_GPU}"
echo "    - Renderizador: ${RENDERER_IN_USE:-DXVK (Vulkan)}"
echo "    - Fsync/Esync: $([ "$WINEFSYNC" = "1" ] && echo "Fsync Activo" || echo "Esync Activo")"
echo "    - Límite de FPS: ${LIMITE_FPS:-60} FPS"
echo "    - AMD FSR Upscaling: $([ "$ACTIVAR_FSR" = "1" ] && echo "Activado" || echo "Desactivado")"
if [[ "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]]; then
    echo "    - GameMode: Desactivado (Aplicación de Escritorio / Lobby)"
    echo "    - Modo Pantalla: Ventana de Escritorio (Lobby / Multijugador)"
    echo "    - Red / Multijugador: Puertos 16000 UDP y DirectPlay Abiertos (100% Conectado)"
else
    echo "    - GameMode: $([ -n "$GAMEMODE" ] && echo "Activo" || echo "Inactivo")"
    echo "    - Modo Pantalla: Pantalla Completa Nativa Directa (Hardware)"
    echo "    - Caché de Shaders: NVMe SSD (~/.cache/dxvk)"
fi
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

# Guardián en segundo plano para asegurar pantalla completa universal al detectar la ventana
WATCHDOG_PID=""
if [[ ! "$TARGET_FILE" =~ ([Gg]ame[Rr]anger|winecfg|regedit|cmd|notepad) ]]; then
    (
        for i in $(seq 1 30); do
            sleep 0.5
            if command -v wmctrl &>/dev/null; then
                wmctrl -l 2>/dev/null | grep -iE 'Wine|Resident|Grand Theft|GTA|SWAT|Age of Empires|BioShock|Unreal|Speed|NFS' | grep -viE 'GameRanger|Winecfg|Error|Debug' | while read -r wid rest; do
                    wmctrl -i -r "$wid" -b add,fullscreen 2>/dev/null || true
                done
            elif command -v xwininfo &>/dev/null && command -v xprop &>/dev/null; then
                xwininfo -root -tree 2>/dev/null | grep -iE '("Resident Evil|"GTA|"Grand Theft|"Swat|"PlayGTAV|"BH6|"re4|"Age of Empires|"Wine)' | grep -viE 'GameRanger|Winecfg' | grep -oE '0x[0-9a-fA-F]+' | head -n 3 | while read -r wid; do
                    xprop -id "$wid" -f _NET_WM_STATE 32a -set _NET_WM_STATE _NET_WM_STATE_FULLSCREEN 2>/dev/null || true
                done
            fi
        done
    ) &
    WATCHDOG_PID=$!
fi

# Función para limpiar procesos en caso de interrupción del usuario (Ctrl+C o terminal cerrada)
limpiar_procesos_al_interrumpir() {
    [ -n "$WATCHDOG_PID" ] && kill "$WATCHDOG_PID" 2>/dev/null || true
    if [[ "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]]; then
        GR_TARGET_USER="${SUDO_USER:-$USER}"
        GR_PREFS="${WINEPREFIX}/drive_c/users/${GR_TARGET_USER}/AppData/Roaming/GameRanger/GameRanger Prefs"
        if [ -d "$GR_PREFS" ] && [ -s "${GR_PREFS}/Settings" ]; then
            mkdir -p "${DIR}/.gameranger_prefs_backup"
            cp -ru "$GR_PREFS"/* "${DIR}/.gameranger_prefs_backup/" 2>/dev/null || true
        fi
    fi
    wineserver -k 2>/dev/null || true
}
trap limpiar_procesos_al_interrumpir INT TERM

# Sincronizar buffers de disco y optimizar prioridad de proceso
sync 2>/dev/null || true
renice -n -5 $$ 2>/dev/null || true

if [[ "$TARGET_FILE" =~ \.(msi|MSI)$ ]]; then
    $GAMEMODE "$WINE_CMD" msiexec /i "$TARGET_FILE" "$@"
elif [[ "$TARGET_FILE" =~ \.(lnk|ink|LNK|INK)$ ]]; then
    if [ -n "$RUN_PREFIX" ]; then
        $GAMEMODE "$WINE_CMD" $RUN_PREFIX start /unix "$TARGET" "$@"
    else
        $GAMEMODE "$WINE_CMD" start /unix "$TARGET" "$@"
    fi
elif [[ "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]]; then
    # GameRanger: silenciar logs ruidosos de CEF/Chromium hacia log dedicado y ejecutar fluidamente
    "$WINE_CMD" "$TARGET_FILE" "$@" $EXTRA_APP_ARGS 2>"${WINEPREFIX}/gameranger_cef.log"
else
    if [ -n "$RUN_PREFIX" ]; then
        $GAMEMODE "$WINE_CMD" $RUN_PREFIX "$TARGET_FILE" "$@" $EXTRA_APP_ARGS
    else
        $GAMEMODE "$WINE_CMD" "$TARGET_FILE" "$@" $EXTRA_APP_ARGS
    fi
fi
EXIT_STATUS=$?

# Terminar vigilante de pantalla completa si sigue activo
[ -n "$WATCHDOG_PID" ] && kill "$WATCHDOG_PID" 2>/dev/null || true

# Respaldar sesión de GameRanger para asegurar persistencia permanente
if [[ "$TARGET_FILE" =~ [Gg]ame[Rr]anger ]]; then
    GR_TARGET_USER="${SUDO_USER:-$USER}"
    GR_PREFS="${WINEPREFIX}/drive_c/users/${GR_TARGET_USER}/AppData/Roaming/GameRanger/GameRanger Prefs"
    if [ -d "$GR_PREFS" ] && [ -s "${GR_PREFS}/Settings" ]; then
        mkdir -p "${DIR}/.gameranger_prefs_backup"
        cp -ru "$GR_PREFS"/* "${DIR}/.gameranger_prefs_backup/" 2>/dev/null || true
    fi
fi

# Esperar sincronización limpia de los subprocesos de Wine sin matarlos abruptamente
wineserver -w 2>/dev/null || true
exit $EXIT_STATUS
