#!/bin/bash
# ==============================================================================
# Script para iniciar la compilación optimizada de Wine-TKG
# ==============================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${DIR}/wine-tkg-git/wine-tkg-git"

echo "=========================================================="
echo "   Iniciando Compilación Optimizada de Wine-TKG"
echo "=========================================================="
echo "Configuración aplicada:"
echo " - Optimización CPU: -O3 -march=native (Intel Core i5-8250U)"
echo " - Soporte Fsync / Futex2 nativo (Kernel 6.12)"
echo " - PRIME GPU Offload para GeForce MX130"
echo " - Salida de compilación: ${DIR}/wine-tkg-build"
echo "=========================================================="

cd "${BUILD_DIR}"

# Ejecutar el script no-makepkg (para Debian / distros no-Arch)
./non-makepkg-build.sh "$@"
