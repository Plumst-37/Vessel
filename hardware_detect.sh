#!/bin/bash
# ==============================================================================
# MÓDULO DE DETECCIÓN Y OPTIMIZACIÓN UNIVERSAL DE HARDWARE PARA LINUX
# Compatible con cualquier PC (Intel, AMD, NVIDIA, laptops híbridas y sobremesa)
# ==============================================================================

# Detección de CPU
CPU_CORES=$(nproc 2>/dev/null || echo 4)
CPU_MODEL=$(lscpu 2>/dev/null | grep -iE 'model name|nombre del modelo' | cut -d: -f2 | xargs | head -n 1)
[ -z "$CPU_MODEL" ] && CPU_MODEL="Procesador Genérico (${CPU_CORES} hilos)"

# Detección de Memoria RAM
RAM_TOTAL_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
[ -z "$RAM_TOTAL_MB" ] && RAM_TOTAL_MB=8192

# Detección de GPU
DETECTED_GPU="Desconocida"
HAS_NVIDIA=false
HAS_AMD_DEDICATED=false

if lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -i 'nvidia' > /dev/null; then
    HAS_NVIDIA=true
    GPU_NAME=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -i 'nvidia' | cut -d: -f3 | xargs | head -n 1)
    DETECTED_GPU="NVIDIA: ${GPU_NAME}"
elif lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -i 'amd|radeon' > /dev/null; then
    HAS_AMD_DEDICATED=true
    GPU_NAME=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -i 'amd|radeon' | cut -d: -f3 | xargs | head -n 1)
    DETECTED_GPU="AMD Radeon: ${GPU_NAME}"
else
    GPU_NAME=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -i 'intel' | cut -d: -f3 | xargs | head -n 1)
    DETECTED_GPU="Intel Integrada: ${GPU_NAME:-Gráficos Integrados}"
fi

# Detección de compatibilidad con Vulkan (para GPUs modernas vs. antiguas)
HAS_VULKAN=false
if command -v vulkaninfo &>/dev/null; then
    if vulkaninfo --summary 2>/dev/null | grep -iE "GPU[0-9]|deviceName" | grep -iv "llvmpipe" > /dev/null; then
        HAS_VULKAN=true
    fi
fi

# Función para exportar las variables de entorno óptimas según el hardware
aplicar_entorno_hardware() {
    # 1. Hilos de compilación para DXVK basados en la CPU real
    export DXVK_NUM_COMPILER_THREADS="$CPU_CORES"

    # 2. Configuración de sincronización del Kernel (Fsync / Esync)
    KERNEL_MAJOR=$(uname -r | cut -d. -f1)
    KERNEL_MINOR=$(uname -r | cut -d. -f2)

    if [ "$KERNEL_MAJOR" -gt 5 ] || { [ "$KERNEL_MAJOR" -eq 5 ] && [ "$KERNEL_MINOR" -ge 16 ]; }; then
        # Kernel moderno (Linux 5.16+ o 6.x) soporta futex_waitv (Fsync nativo)
        export WINEFSYNC=1
        export WINEESYNC=1
    else
        # Fallback a Esync si los límites de archivos lo permiten
        export WINEFSYNC=0
        export WINEESYNC=1
    fi

    # 3. Direccionamiento de memoria ampliado para juegos de 32 bits (permite 4GB en vez de 2GB)
    export WINE_LARGE_ADDRESS_AWARE=1

    # 4. Latencia de audio ultra-baja para evitar cortes y retrasos (PipeWire / PulseAudio)
    export PULSE_LATENCY_MSEC=50

    # 5. Desactivar logs innecesarios de Wine para máximo rendimiento de CPU
    export WINEDEBUG=-all

    # 6. Selección de Renderizador: DXVK (Vulkan) o Fallback WineD3D (OpenGL para PCs antiguas)
    local backend="${RENDERER_BACKEND:-auto}"
    if [ "$backend" = "wined3d" ] || { [ "$backend" = "auto" ] && [ "$HAS_VULKAN" = false ]; }; then
        # Modo Compatibilidad OpenGL (para tarjetas sin Vulkan o PCs antiguas)
        export PROTON_USE_WINED3D=1
        export RENDERER_IN_USE="WineD3D (OpenGL Compatibilidad)"
        export WINEDLLOVERRIDES="winemenubuilder.exe=d;dxgi=b;d3d11=b;d3d10core=b;d3d9=b;${WINEDLLOVERRIDES}"
    else
        # Modo Máximo Rendimiento Vulkan con DXVK
        export RENDERER_IN_USE="DXVK (Vulkan)"
        export WINEDLLOVERRIDES="winemenubuilder.exe=d;dxgi=n;d3d11=n;d3d10core=n;d3d9=n;${WINEDLLOVERRIDES}"
    fi

    # 7. Reducir latencia de memoria compartida en Wine Staging
    export STAGING_SHARED_MEMORY=1

    # 8. Renderizado según la GPU detectada
    if [ "$HAS_NVIDIA" = true ]; then
        export __NV_PRIME_RENDER_OFFLOAD=1
        export __GLX_VENDOR_LIBRARY_NAME=nvidia
        export __VK_LAYER_NV_optimus=NVIDIA_only
        export DRI_PRIME=1
    elif [ "$HAS_AMD_DEDICATED" = true ]; then
        export DRI_PRIME=1
        export RADV_PERFTEST=aco
    fi

    # 9. Puentes y compatibilidad para Anti-Cheat (EAC / BattlEye en juegos con soporte Linux)
    export PROTON_ENABLE_NVAPI=1
    export PROTON_BATTLEYE_ASYNC=1
    export PROTON_EAC_ASYNC=1
    export WINE_DISABLE_FAST_SYNC=0

    # 10. Bypass de compositor de escritorio en pantalla completa
    export WINE_FULLSCREEN_INTEGER_SCALING=0
}
