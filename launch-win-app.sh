#!/bin/bash
# ==============================================================================
# LANZADOR UNIVERSAL OPTIMIZADO PARA APLICACIONES Y JUEGOS DE WINDOWS
# Compatible con cualquier arquitectura de PC (Intel, AMD, NVIDIA, Integradas)
# Soporta Prefijo Compartido y Prefijos Aislados por Juego
# ==============================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_FILE="${DIR}/programas.db"

# 1. Cargar preferencias del usuario y detección de hardware universal
[ -f "${DIR}/config_rendimiento.cfg" ] && source "${DIR}/config_rendimiento.cfg"
source "${DIR}/hardware_detect.sh"

# 2. Aplicar optimizaciones dinámicas para el hardware real del equipo
aplicar_entorno_hardware

# 3. Procesar banderas opcionales de prefijo
CUSTOM_PREFIX=""
if [ "$1" = "--prefix" ]; then
    shift
    CUSTOM_PREFIX="$1"
    shift
fi

if [ $# -eq 0 ]; then
    echo "Uso: $0 [--prefix nombre_o_ruta] /ruta/al/programa.exe [argumentos]"
    exit 1
fi

TARGET="$1"
shift || true

# 4. Comprobar si el programa tiene un prefijo dedicado asignado en la base de datos
if [ -z "$CUSTOM_PREFIX" ] && [ -f "$DB_FILE" ]; then
    while IFS='|' read -r db_name db_path db_prefix; do
        if [ "$db_path" = "$TARGET" ] && [ -n "$db_prefix" ] && [ "$db_prefix" != "DEFAULT" ] && [ "$db_prefix" != "compartido" ]; then
            CUSTOM_PREFIX="$db_prefix"
            break
        fi
    done < "$DB_FILE"
fi

# 5. Definir la ruta del WINEPREFIX (compartido o aislado)
if [ -n "$CUSTOM_PREFIX" ]; then
    if [[ "$CUSTOM_PREFIX" = /* ]]; then
        export WINEPREFIX="$CUSTOM_PREFIX"
    else
        export WINEPREFIX="${DIR}/prefixes/${CUSTOM_PREFIX}"
    fi
    echo "[*] Usando Prefijo Aislado: ${WINEPREFIX}"
else
    export WINEPREFIX="${DIR}/wineprefix"
fi

# 6. Auto-inicialización del prefijo si es nuevo
if [ ! -f "${WINEPREFIX}/system.reg" ]; then
    echo "[*] Configurando nuevo entorno de Windows para este juego..."
    mkdir -p "$WINEPREFIX"
    wineboot -u
    if command -v dxvk-setup &>/dev/null && [ "$RENDERER_IN_USE" != "WineD3D (OpenGL Compatibilidad)" ]; then
        dxvk-setup install -y 2>/dev/null || true
    fi
    # Clonar librerías comunes de compatibilidad desde el prefijo base si existen
    if [ -d "${DIR}/wineprefix/drive_c/windows/syswow64" ] && [ "${WINEPREFIX}" != "${DIR}/wineprefix" ]; then
        mkdir -p "${WINEPREFIX}/drive_c/windows/syswow64"
        cp -n "${DIR}/wineprefix/drive_c/windows/syswow64"/mfc42* "${WINEPREFIX}/drive_c/windows/syswow64/" 2>/dev/null || true
        cp -n "${DIR}/wineprefix/drive_c/windows/syswow64"/msvcr* "${WINEPREFIX}/drive_c/windows/syswow64/" 2>/dev/null || true
        cp -n "${DIR}/wineprefix/drive_c/windows/syswow64"/msvcp* "${WINEPREFIX}/drive_c/windows/syswow64/" 2>/dev/null || true
    fi
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

# Moverse al directorio donde reside el juego (vital para rutas relativas y DLLs)
cd "$TARGET_DIR"

# Si el juego incluye un dinput8.dll local (ASI loaders/mods), activar el override nativo
if [ -f "dinput8.dll" ]; then
    export WINEDLLOVERRIDES="dinput8=n,b;${WINEDLLOVERRIDES}"
fi

echo "[+] Ejecutando con Perfil [${PERFIL_RENDIMIENTO:-maximo}]..."
echo "    - CPU: ${CPU_MODEL} (${CPU_CORES} Hilos)"
echo "    - GPU: ${DETECTED_GPU}"
echo "    - Renderizador: ${RENDERER_IN_USE:-DXVK (Vulkan)}"
echo "    - Fsync/Esync: $([ "$WINEFSYNC" = "1" ] && echo "Fsync Activo" || echo "Esync Activo")"
echo "    - Límite de FPS: ${LIMITE_FPS:-60} FPS"
echo "    - AMD FSR Upscaling: $([ "$ACTIVAR_FSR" = "1" ] && echo "Activado" || echo "Desactivado")"
echo "    - GameMode: $([ -n "$GAMEMODE" ] && echo "Activo" || echo "Inactivo")"
echo "    - Prefijo Wine: ${WINEPREFIX}"

# Función para limpiar procesos colgados al cerrar la ventana con [X] o Ctrl+C
limpiar_procesos_al_salir() {
    wineserver -k 2>/dev/null || true
}
trap limpiar_procesos_al_salir EXIT INT TERM

if [[ "$TARGET_FILE" =~ \.(msi|MSI)$ ]]; then
    $GAMEMODE "$WINE_CMD" msiexec /i "$TARGET_FILE" "$@"
else
    $GAMEMODE "$WINE_CMD" "$TARGET_FILE" "$@"
fi
EXIT_STATUS=$?

limpiar_procesos_al_salir
exit $EXIT_STATUS
