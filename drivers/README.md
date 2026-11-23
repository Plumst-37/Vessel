# Apartado Modular de Controladores y Traducción Gráfica en Vessel

Bienvenido al subsistema modular de controladores, optimizaciones de hardware y capas de traducción gráfica de **Vessel**.

Este directorio (`drivers/`) permite inspeccionar, modificar y personalizar en caliente el comportamiento gráfico de cualquier juego o aplicación de Windows en GNU/Linux, garantizando compatibilidad plug & play y máximo rendimiento en cualquier procesador (Intel Core, AMD Ryzen, Celeron, Athlon, Xeon) y cualquier tarjeta gráfica (NVIDIA GeForce, AMD Radeon, Intel Arc/Iris/UHD).

---

## 📂 Estructura Modular del Directorio

```text
drivers/
├── README.md                      # Esta guía técnica de uso y personalización
├── gpu_env.conf                   # Configuración central universal (Monitor, GPU, CPU, Zink)
├── dxvk/
│   ├── dxvk.conf                  # Configuración editable de DXVK (D3D8/9/10/11 -> Vulkan)
│   ├── x64/                       # Librerías DLL de 64 bits (d3d11.dll, dxgi.dll, d3d9.dll, etc.)
│   └── x32/                       # Librerías DLL de 32 bits
├── vkd3d-proton/
│   ├── vkd3d.conf                 # Configuración editable de VKD3D-Proton (D3D12 -> Vulkan)
│   ├── x64/                       # Librerías DLL de 64 bits (d3d12.dll, d3d12core.dll)
│   └── x32/                       # Librerías DLL de 32 bits
└── dxvk-nvapi/
    ├── dxvk-nvapi.conf            # Configuración de extensiones NVIDIA Reflex y DLSS Bridge
    ├── x64/                       # nvapi64.dll
    └── x32/                       # nvapi.dll
```

---

## ⚙️ Parámetros Principales de `drivers/gpu_env.conf`

El archivo `gpu_env.conf` viene configurado de fábrica con valores adaptativos (`"auto"`) para que Vessel se ajuste automáticamente a cualquier máquina:

### 1. Detección Dinámica de Pantalla y Geometría
- `TARGET_MONITOR="auto"`:
  * Si está en `"auto"`, interroga en tiempo real a `xrandr` (X11) o gestores de Wayland para ubicar la pantalla activa/primaria donde se sitúa el usuario.
  * Soporta salidas de laptop (`eDP-1`) y monitores externos de escritorio (`HDMI-1`, `HDMI-A-1`, `DP-1`, `DP-2`).
- `FORCE_RESOLUTION="auto"`:
  * Si está en `"auto"`, adopta la resolución nativa del monitor detectado (Full HD 1080p, 2K 1440p, 4K, 720p).
  * Puedes fijar una resolución forzada personalizada si lo deseas (ejemplo: `"1280x720"` o `"1920x1080"`).

### 2. Aceleración Gráfica y Sistemas Híbridos (GPU Offload)
- `GPU_FORCE_DEDICATED="auto"`:
  * Detecta si tu equipo cuenta con gráficos dedicados e inyecta dinámicamente las variables de rendimiento según el fabricante:
    * **NVIDIA GeForce:** Activa PRIME Offload (`__NV_PRIME_RENDER_OFFLOAD=1`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `__VK_LAYER_NV_optimus=NVIDIA_only`).
    * **AMD Radeon:** Activa renderizado dedicado (`DRI_PRIME=1`), controlador Vulkan RADV (`AMD_VULKAN_ICD=RADV`) y Smart Access Memory (`RADV_PERFTEST=gpl,sam`).
    * **Intel Arc / Iris Xe:** Activa offload dedicado (`DRI_PRIME=1`) y optimizaciones de pipeline ANV.
  * Valor `"1"`: Forzar GPU dedicada siempre.
  * Valor `"0"`: Desactivar offload (utilizar GPU integrada para ahorro de batería).
- `ENABLE_VULKAN_GPL=1`:
  * Activa Vulkan Graphics Pipeline Library (GPL) para precachear shaders y eliminar tirones (*stuttering*) en drivers NVIDIA 525+ y Mesa 23+.

### 3. Aprovechamiento del 100% de la CPU
- `CPU_COMPILER_THREADS="auto"`:
  * Al estar en `"auto"`, calcula en caliente `$(nproc)` para asignar el 100% de los núcleos físicos e hilos lógicos de tu procesador a la compilación en segundo plano de shaders, eliminando caídas bruscas de FPS.

### 4. Traducción Oficial OpenGL -> Vulkan (Mesa Zink)
- `OPENGL_TRANSLATION="auto"`:
  * `"auto"`: Utiliza aceleración OpenGL estándar con fallbacks resilientes.
  * `"zink"`: Fuerza la traducción de OpenGL sobre Vulkan mediante Mesa Zink (`MESA_LOADER_DRIVER_OVERRIDE=zink`, `GALLIUM_DRIVER=zink`). Ideal para resolver cuelgues o bajo rendimiento en juegos OpenGL clásicos corriendo sobre GPUs modernas o controladores propietarios problemáticos.
  * `"native"`: Utiliza exclusivamente el controlador nativo de OpenGL del sistema host.

---

## 🛠️ Comprobación del Estado de los Controladores

Puedes consultar en cualquier momento el estado de la configuración activa y las librerías instaladas ejecutando:

```bash
bash core/gestor_drivers.sh estado
```

O desde el menú principal de Vessel (`menu-win.sh` ➔ Opción de Drivers y Runtimes).

---

## ⚖️ Filosofía Open-Source y Licencia GNU GPL-3.0

1. **Descarga Limpia y Legal:** Vessel no distribuye binarios propietarios protegidos por derechos de autor dentro de su repositorio Git. Todas las librerías (`DXVK`, `VKD3D-Proton`, `DXVK-NVAPI`) se descargan o enlazan dinámicamente desde sus repositorios oficiales de código abierto bajo demanda.
2. **Resiliencia:** Si faltan utilidades como `zstd`, Vessel alerta limpiamente al usuario indicando el comando exacto para su distribución (`apt`, `pacman`, `dnf`) sin dañar ni corromper el prefijo de Wine.
