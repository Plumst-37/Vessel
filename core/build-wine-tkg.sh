#!/bin/bash
# ==============================================================================
# Script para iniciar la compilación optimizada de Wine-TKG
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../menu-win.sh" ]; then
    DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
    DIR="$SCRIPT_DIR"
fi
BUILD_DIR="${DIR}/wine-tkg-git/wine-tkg-git"

if [ -f "${DIR}/core/hardware_detect.sh" ]; then
    source "${DIR}/core/hardware_detect.sh" 2>/dev/null || true
else
    source "${DIR}/hardware_detect.sh" 2>/dev/null || true
fi

echo "=========================================================="
echo "   Iniciando Compilación Optimizada de Wine-TKG"
echo "=========================================================="
echo "Configuración aplicada:"
echo " - Optimización CPU: -O3 -mtune=generic (${CPU_MODEL:-CPU Genérica})"
echo " - Soporte Fsync / Futex2 nativo (Kernel $(uname -r 2>/dev/null || echo '6.x'))"
echo " - Aceleración GPU: ${DETECTED_GPU:-GPU Detectada}"
echo " - Salida de compilación: ${DIR}/wine-tkg-build"
echo "=========================================================="

if [ ! -d "${BUILD_DIR}" ]; then
    echo "[-] Error: No se encontró el árbol fuente de Wine-TKG en: ${BUILD_DIR}"
    echo "    Clona el repositorio antes de compilar:"
    echo "    git clone https://github.com/Frogging-Family/wine-tkg-git.git \"${DIR}/wine-tkg-git\""
    exit 1
fi

cd "${BUILD_DIR}"

# Ejecutar el script no-makepkg (para Debian / distros no-Arch)
./non-makepkg-build.sh "$@"
