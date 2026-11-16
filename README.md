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

### 🎮 3. Control Gráfico en Tiempo Real
- **Perfiles de Rendimiento:** *Máximo Rendimiento* (GameMode al 100%), *Equilibrado* y *Ahorro de Batería*.
- **Límite de FPS:** Fija topes de 30, 60, 120 FPS o Ilimitado para evitar sobrecalentamiento.
- **AMD FSR (FidelityFX Super Resolution):** Reescalado inteligente que duplica los FPS en tarjetas de gama media/baja o integradas con ajuste de nitidez.
- **HUD en Pantalla:** Contador de FPS y uso de recursos opcional.

### 📂 4. Gestión Cómoda de Juegos Portables e Instaladores
- **➕ Añadir programa portable:** Para juegos o programas ya listos en carpetas (repacks, portables, discos externos).
- **➕ Añadir programa instalable:** Ejecuta instaladores (`Setup.exe`, `Installer.exe`, `.msi`), los instala en Wine y **auto-detecta el ejecutable principal recién creado** leyendo accesos `.lnk` o inodos, registrándolo automáticamente.
- **🖱️ Selector Gráfico con Ratón:** Puedes buscar tus ejecutables navegando con carpetas y ratón (**KDialog / Zenity**) o por terminal.
- **🖥️ Accesos Directos al Escritorio (1-Clic):** Crea accesos directos validados y ejecutables en tu Escritorio para abrir cualquier juego directamente sin abrir la terminal.

### 🔒 5. Prefijos Aislados vs. Compartidos (Multi-Prefix)
- Permite elegir si un juego comparte la unidad `C:` global (para ahorrar espacio) o si tiene un **prefijo de Windows 100% aislado**, evitando conflictos de versiones de librerías o parches.

### 🛠️ 6. Centro de Herramientas de Windows
- Acceso directo con 1 clic a:
  - 🍷 **winecfg:** Configura versión de Windows (Win 7, 10, 11), DPI y escritorio virtual.
  - 📝 **regedit:** Editor del registro de Windows.
  - 📈 **taskmgr:** Administrador de tareas.
  - 📁 **wine explorer:** Explorador de archivos de Windows.
  - 🧹 **wineserver -k:** Cierra procesos congelados y libera la memoria RAM al instante.
  - 🛡️ **Comprobador de Compatibilidad Anti-Cheat:** Consulta de antemano el soporte de títulos online.

### 🌐 7. Internet, Wi-Fi y Multijugador
- Conexión de red nativa optimizada (DNS 32-bit/64-bit multiarch, soporte para puertos UDP y ICMP ping).
- Compatible con servidores comunitarios, clientes multijugador (GameRanger, FiveM, etc.) y puentes para **Easy Anti-Cheat** y **BattlEye** en Linux.

---

## 📋 Estructura del Proyecto

```text
Vessel/
├── menu-win.sh            # Panel principal interactivo con paleta ANSI
├── launch-win-app.sh      # Lanzador con GameMode, PRIME GPU y multi-prefijos
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
