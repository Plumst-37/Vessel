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
HAS_INTEL=false

if lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -i 'intel' > /dev/null; then
    HAS_INTEL=true
fi

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
    DETECTED_GPU="Intel: ${GPU_NAME:-Gráficos Integrados}"
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

    # 7. Caché de shaders universal y optimización de hilos OpenGL/Mesa
    export STAGING_SHARED_MEMORY=1
    export DXVK_ASYNC=1
    export __GL_SHADER_DISK_CACHE=1
    export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
    export __GL_SHADER_DISK_CACHE_SIZE=10737418240
    export MESA_DISK_CACHE_SINGLE_FILE=1
    export mesa_glthread=true

    # 8. Renderizado según la GPU detectada (Garantiza usar la GPU dedicada en laptops híbridas)
    # Detección dinámica y universal de GPU dedicada (NVIDIA GeForce o AMD Radeon)
    local discrete_info
    discrete_info=$(MESA_VK_DEVICE_SELECT=list vulkaninfo 2>&1 | grep -i 'discrete GPU' | head -n 1 || true)
    if [ -n "$discrete_info" ]; then
        local discrete_pci_id
        discrete_pci_id=$(echo "$discrete_info" | awk '{print $3}')
        local discrete_name
        discrete_name=$(echo "$discrete_info" | grep -oE '"[^"]+"' | tr -d '"')

        if [ -n "$discrete_pci_id" ]; then
            export MESA_VK_DEVICE_SELECT="${discrete_pci_id}!"
            export MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE=1
        fi
        if [ -n "$discrete_name" ]; then
            export DXVK_FILTER_DEVICE_NAME="${discrete_name}"
        fi
    fi

    if [ "$HAS_NVIDIA" = true ]; then
        # Activar capas y optimizaciones NVIDIA (PRIME offload, hilos OpenGL y sincronización limpia)
        export __NV_PRIME_RENDER_OFFLOAD=1
        export __GLX_VENDOR_LIBRARY_NAME=nvidia
        export __VK_LAYER_NV_optimus=NVIDIA_only
        export VKD3D_CONFIG="dxr11,dxr"
        export __GL_THREADED_OPTIMIZATIONS=1
        export __GL_SYNC_TO_VBLANK=0
    elif [ "$HAS_AMD_DEDICATED" = true ]; then
        # Activar optimizaciones AMD Radeon (PRIME, compilador ACO y SAM)
        export DRI_PRIME=1
        export RADV_PERFTEST=aco,sam,dcc
        export vblank_mode=0
    fi

    # 9. Puentes y compatibilidad para Anti-Cheat (EAC / BattlEye en juegos con soporte Linux)
    export PROTON_ENABLE_NVAPI=1
    export PROTON_BATTLEYE_ASYNC=1
    export PROTON_EAC_ASYNC=1
    export WINE_DISABLE_FAST_SYNC=0

    # 10. Prevención universal de pantalla negra y stutter de movimiento en Wayland/X11
    export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0
    export WINE_FULLSCREEN_INTEGER_SCALING=0
    export GST_PLUGIN_FEATURE_RANK="libav:MAX,ugly:MAX,bad:MAX"
    export KWIN_DRM_NO_DIRECT_SCANOUT=1
}
