# 🚀 Vessel (Menu Win - Universal Edition)

> **El gestor y optimizador definitivo de juegos y aplicaciones de Windows para cualquier distribución de Linux.**  
> *Máximo rendimiento, cero consumo en segundo plano, instalación en 1 clic y compatibilidad universal.*

---

## ⚡ Instalación en 1 Solo Paso (Cualquier Linux)

Abre cualquier terminal y pega este comando:

```bash
curl -fsSL https://raw.githubusercontent.com/Plumst-37/Vessel/main/instalar.sh | bash
```

O si prefieres clonar manualmente:

```bash
git clone https://github.com/Plumst-37/Vessel.git
cd Vessel
./instalar.sh
```

El instalador:
1. Detecta automáticamente tu distribución (**Debian / Ubuntu / Linux Mint**, **Arch Linux / Manjaro**, **Fedora / RHEL** o **openSUSE**).
2. Comprueba e instala dependencias (**Wine, DXVK, GameMode, Winetricks, Zenity, librerías DNS 32-bit/64-bit**).
3. Optimiza parámetros del kernel del sistema (`vm.max_map_count`, `ip_unprivileged_port_start=0` y `ping_group_range` para multijugador y conexión total).
4. Genera una configuración `dxvk.conf` ajustada a la cantidad exacta de núcleos e hilos de tu CPU.
5. Crea el acceso directo **Menu Win (PC)** en tu **Escritorio** y en tu menú de aplicaciones listo para usar.

---

## 🌟 Características Principales

### 🚀 1. Rendimiento y Cero Sobrecarga (Zero Overhead)
- Desarrollado en **puro Bash nativo**. Consume **0% de CPU y menos de 8 MB de RAM** en reposo (a diferencia de clientes pesados como Lutris o Steam basados en Electron o Python).
- Toda la potencia de tu procesador y gráfica se dedica al 100% a tu juego.

### 🖥️ 2. Detección Inteligente de Hardware (`hardware_detect.sh`)
- **NVIDIA:** Activa automáticamente **PRIME Render Offloading** en portátiles con gráficos híbridos (Intel + NVIDIA / AMD + NVIDIA).
- **AMD Radeon:** Activa el compilador ultrarrápido **ACO** y controladores **RADV**.
- **Intel Graphics:** Optimiza la traducción a Vulkan o realiza fallback suave a **WineD3D (OpenGL)** en computadoras antiguas sin Vulkan.
- **Sincronización:** Detecta automáticamente **Fsync nativo (Futex2)** o **Esync**.

### 🎮 3. Control Gráfico en Tiempo Real y Cero Pantalla Negra / Tirones
- **Perfiles de Rendimiento:** *Máximo Rendimiento* (GameMode al 100%), *Equilibrado* y *Ahorro de Batería*.
- **Límite de FPS:** Fija topes de 30, 60, 120 FPS o Ilimitado para evitar sobrecalentamiento.
- **Buffer Anti-Tirones (Zero-Stuttering):** Cola de fotogramas sincronizada (`maxFrameLatency = 2`) y compilación asíncrona de shaders GPL que eliminan caídas de frames y micro-parones.
- **Selección Inteligente y Universal de GPU:** Soporta nativamente cualquier tarjeta gráfica (Intel HD/Iris/Arc, AMD Radeon y NVIDIA GeForce), activando PRIME offload en portátiles híbridas sin romper la aceleración de Xwayland u OpenGL.
- **Auto-Fix Capcom (`ERR09 : Unsupported function`):** Detecta y corrige automáticamente los archivos `config.ini` de juegos de Capcom MT Framework (Resident Evil 4/5/6, Revelations, Devil May Cry, etc.) configurando `FullScreen=OFF` para evitar caídas de modo exclusivo en Linux.
- **Optimizaciones para Juegos Pesados AAA:** Compilación asíncrona de shaders por hardware (`GPL` y `dxvk.enableAsync`), buffer de latencia sincronizado (`maxFrameLatency = 2`), 4GB de direccionamiento para juegos de 32 bits (`Large Address Aware`), y compatibilidad completa con DirectX 9, 10, 11 y 12 (VKD3D).
- **Soporte Retro DirectDraw y DirectPlay:** Carga automáticamente envoltorios nativos (`ddraw.dll`, `cnc-ddraw`, `d3d8to9`) eliminando pantallas negras y corrupción de texturas de 8 bits (P8) en juegos clásicos como Age of Empires II o StarCraft.
- **Decodificación de Cinemáticas y Videos:** Soporte multiarch completo para decodificadores de video (H.264, MPEG-4, WMV3, Bink, Media Foundation y DirectShow vía GStreamer 32/64 bits), solucionando el problema donde se escuchaba el audio pero la pantalla quedaba negra.
- **🖥️ Modo Escritorio Virtual Configurable:** Soluciona pantallas negras al cambiar de resolución (juegos retro a 4:3 o 800x600) y en configuraciones con múltiples monitores.
- **AMD FSR (FidelityFX Super Resolution):** Reescalado inteligente que duplica los FPS en tarjetas de gama media/baja o integradas con ajuste de nitidez.
- **HUD en Pantalla:** Contador de FPS y uso de recursos opcional.

### 📂 4. Gestión Cómoda de Juegos Portables e Instaladores
- **➕ Añadir programa portable:** Para juegos o programas ya listos en carpetas (repacks, portables, discos externos). Admite ejecutables directos (`.exe`, `.bat`, `.cmd`) y **accesos directos de Windows (`.lnk` y `.ink`)**, resolviendo automáticamente el ejecutable real dentro de la carpeta o prefijo.
- **➕ Añadir programa instalable:** Ejecuta instaladores (`Setup.exe`, `Installer.exe`, `.msi`), los instala en Wine y **auto-detecta el ejecutable principal recién creado** leyendo accesos `.lnk` o inodos, registrándolo automáticamente.
- **📂 Acceso Directo a Archivos del Juego:** Opción dedicada en el menú para abrir en 1 clic la carpeta de cualquier juego en tu gestor de archivos (Dolphin / Nautilus).
- **🖱️ Selector Gráfico con Ratón:** Puedes buscar tus ejecutables navegando con carpetas y ratón (**KDialog / Zenity**) o por terminal.
- **🖥️ Accesos Directos al Escritorio (1-Clic):** Crea accesos directos validados en tu Escritorio con acción de clic derecho integrada: **"📂 Abrir carpeta del juego (Instalar Mods / Archivos)"**.

### 🧩 5. Soporte Total para Mods, Shaders y Parches (Zero-Config)
- **Auto-Detección de Hooks y DLLs:** Detecta automáticamente cualquier librería de mod pegada en la carpeta del juego (`dinput8.dll`, `dxgi.dll`, `version.dll`, `dsound.dll`, `winmm.dll`, `xinput*.dll`, `bink*.dll`, `dbghelp.dll`, etc.) y aplica los overrides nativos de Wine al instante.
- **Soporte ASI Loader, ReShade y ENB:** Pega tus scripts (`.asi`, carpetas `scripts/`, `CLEO`, ScriptHook, Cyber Engine Tweaks) directamente desde el gestor de archivos de Linux y se cargarán solos al iniciar el juego.
- **Permisos de Escritura Automáticos:** Asegura que mods y parches puedan escribir logs, configuraciones `.ini` y partidas guardadas sin problemas de permisos.

### 🔄 6. Auto-Actualización desde GitHub en Tiempo Real
- Cada vez que abres el menú, Vessel consulta silenciosamente el repositorio oficial en GitHub (`Plumst-37/Vessel`).
- Si hay nuevas mejoras, parches de compatibilidad o correcciones, **se actualiza e instala automáticamente sin intervención**.

### 📦 7. Optimización Inteligente y Automática de Recursos (Opción 5)
- **Configuración Inicial por Distribución:** Detecta y te permite seleccionar si usas **Debian**, **Ubuntu/Mint**, **Fedora**, **Arch Linux** u **openSUSE** para ejecutar los comandos exactos de tu sistema.
- **Comprobación Inteligente:** Comprueba herramientas de sistema, parámetros del kernel y librerías de Windows (MFC42, VC++, DirectX, fuentes). **Si ya están instaladas, las omite; si falta algo, lo instala automáticamente.**

### 🛠️ 8. Centro de Herramientas de Windows
- Acceso directo con 1 clic a:
  - 🍷 **winecfg:** Configura versión de Windows (Win 7, 10, 11), DPI y escritorio virtual.
  - 📝 **regedit:** Editor del registro de Windows.
  - 📈 **taskmgr:** Administrador de tareas.
  - 📁 **wine explorer:** Explorador de archivos de Windows.
  - 🧹 **wineserver -k:** Cierra procesos congelados y libera la memoria RAM al instante.
  - 🛡️ **Comprobador de Compatibilidad Anti-Cheat:** Consulta de antemano el soporte de títulos online.

### 🌐 9. Internet, Wi-Fi y Multijugador
- Conexión de red nativa optimizada (DNS 32-bit/64-bit multiarch, soporte para puertos UDP y ICMP ping).
- Compatible con servidores comunitarios, clientes multijugador (GameRanger, FiveM, etc.) y puentes para **Easy Anti-Cheat** y **BattlEye** en Linux.
- Conexión de red nativa optimizada (DNS 32-bit/64-bit multiarch, soporte para puertos UDP y ICMP ping).
- Compatible con servidores comunitarios, clientes multijugador (GameRanger, FiveM, etc.) y puentes para **Easy Anti-Cheat** y **BattlEye** en Linux.

---

## 📋 Estructura del Proyecto

```text
Vessel/
├── menu-win.sh            # Panel principal interactivo con paleta ANSI
├── launch-win-app.sh      # Lanzador con GameMode, PRIME GPU y multi-prefijos
├── resolver_lnk.py        # Resolvedor universal de accesos directos (.lnk / .ink)
├── hardware_detect.sh     # Detector universal de CPU, GPU, Vulkan y Fsync
├── generar_dxvk_conf.sh   # Generador dinámico de dxvk.conf según hilos de CPU
├── config_rendimiento.cfg # Archivo de preferencias persistente
├── instalar.sh            # Instalador universal de 1 solo clic
└── dxvk.conf              # Configuración de DXVK optimizada
```

---

## 🤝 Créditos y Licencia

Creado para la comunidad de gaming en Linux. Código abierto bajo la licencia MIT.
¡Disfruta de tus juegos favoritos de Windows en Linux con el máximo rendimiento posible!
