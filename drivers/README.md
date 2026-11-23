# Apartado Modular de Drivers Gráficos y Capas de Traducción en Vessel

Bienvenido al directorio de control y personalización de controladores y capas de traducción de Vessel.

Este directorio está diseñado para que cualquier usuario pueda inspeccionar, modificar y optimizar el comportamiento gráfico de sus juegos en GNU/Linux.

---

## Estructura del Directorio

```text
drivers/
├── README.md                      # Esta guía de uso y documentación técnica
├── gpu_env.conf                   # Configuración global de hardware, monitor objetivo y GPU dedicada
├── dxvk/
│   ├── dxvk.conf                  # Configuración editable de DXVK (D3D8/9/10/11 -> Vulkan)
│   ├── x64/                       # Librerías DLL de 64 bits (d3d11.dll, dxgi.dll, etc.)
│   └── x32/                       # Librerías DLL de 32 bits
├── vkd3d-proton/
│   ├── vkd3d.conf                 # Configuración editable de VKD3D-Proton (D3D12 -> Vulkan)
│   ├── x64/                       # Librerías DLL de 64 bits (d3d12.dll, d3d12core.dll)
│   └── x32/                       # Librerías DLL de 32 bits
└── dxvk-nvapi/
    ├── dxvk-nvapi.conf            # Configuración de extensiones NVIDIA Reflex y DLSS
    ├── x64/                       # nvapi64.dll
    └── x32/                       # nvapi.dll
```

---

## ¿Cómo modificar la configuración?

### 1. Cambiar la Pantalla de Salida de Video (`gpu_env.conf`)
Si juegas en laptop con monitor secundario, puedes elegir en qué pantalla se abrirán los juegos:
- `TARGET_MONITOR="eDP-1"`: Abre los juegos en la pantalla integrada de la laptop (1280x720).
- `TARGET_MONITOR="HDMI-A-1"`: Abre los juegos en tu monitor externo HDMI (1920x1080).
- `TARGET_MONITOR="auto"`: Detecta automáticamente dónde está tu cursor.

### 2. Ajustar Límites de FPS, VSync y Shaders (`dxvk/dxvk.conf`)
- `dxgi.maxFrameRate = 60`: Ajusta los fotogramas por segundo deseados (0 para sin límite).
- `dxvk.numCompilerThreads = 8`: Cambia el número de hilos de CPU asignados a compilar gráficos en segundo plano.
- `dxvk.gpl = True`: Mantiene activado Vulkan Graphics Pipeline Library para erradicar el stuttering.

---

## Gestión Limpia y Cumplimiento de Código Abierto (GPLv3)
- Todas las librerías binarias (`.dll`) se descargan u obtienen dinámicamente desde fuentes oficiales de código abierto mediante el script `core/gestor_drivers.sh` o los paquetes de tu distribución.
- Ningún binario con derechos propietarios se almacena estáticamente en el repositorio de Git, garantizando 100% de cumplimiento legal.
