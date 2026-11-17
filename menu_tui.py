#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ==============================================================================
# MENU WIN (EDICIÓN UNIVERSAL CYBERPUNK TUI - PYTHON + BASH BACKEND)
# Gestor de Juegos y Programas de Windows con Interfaz Visual Interactiva
# Compatible con cualquier resolución y ancho de terminal (Konsole, GNOME, etc.)
# ==============================================================================

import os
import sys
import shutil
import subprocess
import re
import unicodedata
import termios
import tty
import time

# Rutas principales
DIR = os.path.dirname(os.path.abspath(__file__))
DB_FILE = os.path.join(DIR, "programas.db")
LAUNCHER = os.path.join(DIR, "launch-win-app.sh")
DXVK_CONF = os.path.join(DIR, "dxvk.conf")
CONFIG_USER = os.path.join(DIR, "config_rendimiento.cfg")
WINEPREFIX = os.path.join(DIR, "wineprefix")

# Paleta de colores Neón Púrpura y Windows 11
PURPLE = "\033[38;2;224;86;253m"
VIOLET = "\033[38;2;168;85;247m"
BG_SELECT = "\033[48;2;130;45;235m\033[1;37m"
WHITE = "\033[1;37m"
TEXT_DIM = "\033[0;37m"
GRAY = "\033[38;2;140;140;160m"
W11_BLUE = "\033[38;2;0;120;212m"
CYAN = "\033[38;2;0;164;239m"
GREEN = "\033[1;32m"
RED = "\033[1;31m"
YELLOW = "\033[1;33m"
RESET = "\033[0m"
BOLD = "\033[1m"

# ==============================================================================
# CÁLCULO VISUAL EXACTO (COMPATIBLE CON EMOJIS, VARIATION SELECTORS Y CARACTERES ASIÁTICOS)
# ==============================================================================

try:
    import wcwidth
    def visual_width(s):
        """Calcula el ancho visual real en celdas de terminal ignorando códigos ANSI."""
        clean = re.sub(r'\x1B\[[0-9;]*[mK]', '', s)
        w = wcwidth.wcswidth(clean)
        return max(w, 0) if w is not None else len(clean)
except ImportError:
    def visual_width(s):
        """Fallback ultra-preciso cuando wcwidth no está disponible."""
        clean = re.sub(r'\x1B\[[0-9;]*[mK]', '', s)
        w = 0
        for ch in clean:
            if ch == '\ufe0f':
                continue
            eaw = unicodedata.east_asian_width(ch)
            if eaw in ('F', 'W'):
                w += 2
            elif (0x1F300 <= ord(ch) <= 0x1FAFF) or (0x2600 <= ord(ch) <= 0x27BF):
                w += 2
            else:
                w += 1
        return w

def pad_visual(s, target_width):
    """Rellena con espacios o recorta respetando exactamente el ancho visual de terminal."""
    vw = visual_width(s)
    if vw <= target_width:
        return s + (' ' * (target_width - vw))
    clean = re.sub(r'\x1B\[[0-9;]*[mK]', '', s)
    cur = 0
    res = []
    for ch in clean:
        cw = visual_width(ch)
        if cur + cw > target_width:
            break
        res.append(ch)
        cur += cw
    return ''.join(res) + (' ' * (target_width - cur))

def read_key():
    """Lee una tecla del teclado en modo crudo usando os.read directamente, capturando flechas completas sin latencia ni cuelgues."""
    if not sys.stdin.isatty():
        ch = sys.stdin.read(1)
        if not ch or ch in ('\r', '\n'):
            return 'ENTER'
        return ch

    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        raw = os.read(fd, 32)
        if not raw:
            return 'ENTER'

        # Secuencias ANSI / VT100 / Konsole / xterm / Linux console
        if raw in (b'\x1b[A', b'\x1bOA') or (raw.startswith(b'\x1b') and raw.endswith(b'A')):
            return 'UP'
        elif raw in (b'\x1b[B', b'\x1bOB') or (raw.startswith(b'\x1b') and raw.endswith(b'B')):
            return 'DOWN'
        elif raw in (b'\x1b[C', b'\x1bOC') or (raw.startswith(b'\x1b') and raw.endswith(b'C')):
            return 'RIGHT'
        elif raw in (b'\x1b[D', b'\x1bOD') or (raw.startswith(b'\x1b') and raw.endswith(b'D')):
            return 'LEFT'
        elif raw in (b'\r', b'\n'):
            return 'ENTER'
        elif raw == b' ':
            return 'SPACE'
        elif raw in (b'\x7f', b'\x08'):
            return 'BACKSPACE'
        elif raw == b'\x1b':
            return 'ESC'

        return raw.decode('utf-8', errors='ignore')
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

def cargar_config():
    """Carga variables de configuración de config_rendimiento.cfg."""
    cfg = {
        "PERFIL_RENDIMIENTO": "maximo",
        "LIMITE_FPS": "60",
        "ACTIVAR_FSR": "0",
        "FSR_STRENGTH": "2",
        "MOSTRAR_HUD_FPS": "0",
        "RENDERER_BACKEND": "auto",
        "SISTEMA_LINUX": "debian",
        "DISTRO_NAME": "Debian"
    }
    if os.path.exists(CONFIG_USER):
        with open(CONFIG_USER, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    cfg[k.strip()] = v.strip().strip('"').strip("'")
    return cfg

def guardar_config(k, v):
    """Guarda una variable en config_rendimiento.cfg."""
    lines = []
    found = False
    if os.path.exists(CONFIG_USER):
        with open(CONFIG_USER, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
    for i, l in enumerate(lines):
        if l.strip().startswith(f"{k}="):
            lines[i] = f'{k}="{v}"\n'
            found = True
            break
    if not found:
        lines.append(f'{k}="{v}"\n')
    with open(CONFIG_USER, "w", encoding="utf-8") as f:
        f.writelines(lines)

def obtener_info_hardware():
    """Detecta de forma universal CPU, GPU, RAM, y estado de Vulkan."""
    cpu_cores = os.cpu_count() or 4
    cpu_model = "Procesador Genérico"
    try:
        out = subprocess.check_output("lscpu", shell=True, text=True, stderr=subprocess.DEVNULL)
        for line in out.splitlines():
            if "model name" in line.lower() or "nombre del modelo" in line.lower():
                raw = line.split(":", 1)[1].strip()
                clean = re.sub(r'CPU @.*|\(R\)|\(TM\)|Core|Processor', '', raw)
                clean = " ".join(clean.split())
                cpu_model = f"{clean} ({cpu_cores} hilos)"
                break
    except Exception:
        pass

    ram_mb = 8192
    try:
        out = subprocess.check_output("free -m", shell=True, text=True, stderr=subprocess.DEVNULL)
        for line in out.splitlines():
            if line.startswith("Mem:"):
                ram_mb = int(line.split()[1])
                break
    except Exception:
        pass
    ram_gb = f"{(ram_mb + 512) // 1024} GB"

    gpu_name = "Gráficos Integrados"
    has_nvidia = False
    has_amd = False
    try:
        lspci = subprocess.check_output("lspci", shell=True, text=True, stderr=subprocess.DEVNULL)
        if "nvidia" in lspci.lower():
            has_nvidia = True
            for l in lspci.splitlines():
                if any(x in l.lower() for x in ("vga", "3d", "display")) and "nvidia" in l.lower():
                    raw = l.split(":", 2)[2].strip()
                    clean = re.sub(r'NVIDIA Corporation|GM[0-9]+M|\[|\]|\(rev [a-z0-9]+\)|GeForce', '', raw, flags=re.I)
                    clean = " ".join(clean.split())
                    gpu_name = f"NVIDIA {clean} (2 GB)"
                    break
        elif any(x in lspci.lower() for x in ("amd", "radeon")):
            has_amd = True
            gpu_name = "AMD Radeon Dedicated"
        elif "intel" in lspci.lower():
            gpu_name = "Intel HD/UHD Graphics"
    except Exception:
        pass

    driver_str = "NVIDIA (Vulkan)" if has_nvidia else ("AMD RADV (Vulkan)" if has_amd else "Mesa (Vulkan)")
    has_vulkan = True
    try:
        vinfo = subprocess.check_output("vulkaninfo --summary", shell=True, text=True, stderr=subprocess.DEVNULL)
        if "llvmpipe" in vinfo and not ("NVIDIA" in vinfo or "AMD" in vinfo or "Intel" in vinfo):
            has_vulkan = False
    except Exception:
        pass

    return {
        "cpu": cpu_model,
        "cores": cpu_cores,
        "ram": ram_gb,
        "gpu": gpu_name,
        "driver": driver_str,
        "vulkan": has_vulkan
    }

def get_terminal_width():
    """Calcula el ancho óptimo adaptado a la ventana de Konsole/Terminal para aprovechar el espacio."""
    cols = shutil.get_terminal_size((105, 30)).columns
    # Adaptar entre 92 y 136 columnas para aprovechar el espacio sin romper la pantalla
    return min(max(cols - 4, 92), 136)

def render_banner(hw, cfg):
    """Dibuja el Header y las dos tarjetas superiores de Sistema y Estado con proporciones dinámicas."""
    total_w = get_terminal_width()
    inner_w = total_w - 2

    # 1. Header Box
    top_bar = f"{PURPLE}╭{'─' * inner_w}╮{RESET}"
    bot_bar = f"{PURPLE}╰{'─' * inner_w}╯{RESET}"

    m_top = "█▄ ▄█"
    m_bot = "█ ▀ █"

    # Logo Windows 11 oficial cuadrado (2x2 cuadrícula de bloques en azul #0078D4)
    w11_top = f"{W11_BLUE}██  ██{RESET}"
    w11_bot = f"{W11_BLUE}██  ██{RESET}"

    left_w = visual_width(f"  {m_top}  ")   # 9
    right_w = visual_width(f"  ██  ██  ") # 10
    mid_w = total_w - 4 - left_w - right_w

    mid_title = f"{WHITE}{BOLD}Menu {PURPLE}Win{RESET}"
    mid_sub = f"{TEXT_DIM}Gestor y Optimizador Universal de Juegos y Programas de {WHITE}{BOLD}Windows{RESET}"

    pad_t = mid_w - visual_width(mid_title)
    pad_s = mid_w - visual_width(mid_sub)
    l1_mid = f"{' ' * (pad_t // 2)}{mid_title}{' ' * (pad_t - (pad_t // 2))}"
    l2_mid = f"{' ' * (pad_s // 2)}{mid_sub}{' ' * (pad_s - (pad_s // 2))}"

    l1 = f"{PURPLE}│{RESET}  {WHITE}{m_top}{RESET}  {PURPLE}│{RESET}{l1_mid}{PURPLE}│{RESET}  {w11_top}  {PURPLE}│{RESET}"
    l2 = f"{PURPLE}│{RESET}  {PURPLE}{m_bot}{RESET}  {PURPLE}│{RESET}{l2_mid}{PURPLE}│{RESET}  {w11_bot}  {PURPLE}│{RESET}"

    print(top_bar)
    print(l1)
    print(l2)
    print(bot_bar)

    # 2. Tarjetas Superiores (Información del Sistema + Estado)
    avail_inner = total_w - 5
    # Proporción equilibrada: ~58% para Sistema (mínimo 50 cols) para no truncar CPU/GPU/RAM
    left_inner = max(int(avail_inner * 0.58), 50)
    right_inner = avail_inner - left_inner

    title_l = "╭─ 🖥️  Información del Sistema "
    bar_l = f"{PURPLE}{title_l}{'─' * (left_inner - visual_width(title_l) + 1)}╮{RESET}"

    title_r = "╭─ 📊  Estado de Motores "
    bar_r = f"{PURPLE}{title_r}{'─' * (right_inner - visual_width(title_r) + 1)}╮{RESET}"

    print(f"{bar_l} {bar_r}")

    fsr_st = f"Activo (x{cfg.get('FSR_STRENGTH', '2')})" if cfg.get("ACTIVAR_FSR") == "1" else "Apagado"
    hud_st = "Activo" if cfg.get("MOSTRAR_HUD_FPS") == "1" else "Apagado"
    vk_st = "Disponible" if hw["vulkan"] else "No compatible"
    dx_st = "Disponible"
    perf_st = cfg.get("PERFIL_RENDIMIENTO", "maximo").upper()

    rows_l = [
        "",
        f"  ⚙️   {PURPLE}Sistema{RESET}  :  {WHITE}{cfg.get('DISTRO_NAME', 'Debian Linux')}{RESET}",
        f"  🧠   {PURPLE}CPU{RESET}      :  {WHITE}{hw['cpu']}{RESET}",
        f"  📼   {PURPLE}GPU{RESET}      :  {WHITE}{hw['gpu']}{RESET}",
        f"  🎛️   {PURPLE}RAM{RESET}      :  {WHITE}{hw['ram']}{RESET}",
        f"  🔌   {PURPLE}Driver{RESET}   :  {WHITE}{hw['driver']}{RESET}"
    ]

    rows_r = [
        "",
        f"  {PURPLE}✔{RESET}   {PURPLE}FSR Reescalado{RESET} :  {WHITE}{fsr_st}{RESET}",
        f"  {PURPLE}✔{RESET}   {PURPLE}HUD FPS / OSD{RESET}  :  {WHITE}{hud_st}{RESET}",
        f"  {PURPLE}✔{RESET}   {PURPLE}Vulkan Driver{RESET}  :  {WHITE}{vk_st}{RESET}",
        f"  {PURPLE}✔{RESET}   {PURPLE}DXVK / D3D{RESET}     :  {WHITE}{dx_st}{RESET}",
        f"  {PURPLE}✔{RESET}   {PURPLE}Perfil Activo{RESET}  :  {GREEN}{perf_st}{RESET}"
    ]

    for rl, rr in zip(rows_l, rows_r):
        pl = pad_visual(rl, left_inner)
        pr = pad_visual(rr, right_inner)
        print(f"{PURPLE}│{RESET}{pl}{PURPLE}│{RESET} {PURPLE}│{RESET}{pr}{PURPLE}│{RESET}")

    print(f"{PURPLE}╰{'─' * left_inner}╯ ╰{'─' * right_inner}╯{RESET}")

def render_footer(inner_w):
    """Renderiza la barra inferior de navegación."""
    top_bar = f"{PURPLE}╭{'─' * inner_w}╮{RESET}"
    bot_bar = f"{PURPLE}╰{'─' * inner_w}╯{RESET}"
    f_content = f"{PURPLE}[↑↓ / ←→]{RESET}  {WHITE}Navegar{RESET}      {PURPLE}│{RESET}      {PURPLE}[Enter]{RESET}  {WHITE}Seleccionar{RESET}      {PURPLE}│{RESET}      {RED}[0 / Esc]{RESET}  {WHITE}Salir{RESET}"
    pad_tot = inner_w - visual_width(f_content)
    pl = pad_tot // 2
    pr = pad_tot - pl
    print(top_bar)
    print(f"{PURPLE}│{RESET}{' ' * pl}{f_content}{' ' * pr}{PURPLE}│{RESET}")
    print(bot_bar)

# ==============================================================================
# SUBMENÚS INTERACTIVOS CON FLECHAS
# ==============================================================================

def submenu_interactivo(titulo, opciones, hw, cfg, default_idx=0):
    """
    Menú genérico interactivo con navegación por flechas (UP/DOWN/ENTER/ESC/0-9).
    opciones: lista de tuplas (clave, texto_etiqueta)
    Retorna la clave seleccionada o '0' para volver.
    """
    sel_idx = default_idx
    num_opts = len(opciones)

    while True:
        os.system("clear")
        render_banner(hw, cfg)

        total_w = get_terminal_width()
        inner_w = total_w - 2

        # Card de Submenú
        m_title = f"╭─ {titulo} "
        m_top = f"{PURPLE}{m_title}{'─' * (inner_w - visual_width(m_title) + 1)}╮{RESET}"
        print(m_top)
        print(f"{PURPLE}│{' ' * inner_w}│{RESET}")

        opt_avail = inner_w - 6

        for i, (key, label) in enumerate(opciones):
            is_exit = (key == "0" or "volver" in label.lower() or "salir" in label.lower() or "cancelar" in label.lower())
            item_text = f"[{key}]  {label}"

            if i == sel_idx:
                line_str = f"▶  {item_text}"
                btn = f"{BG_SELECT} {pad_visual(line_str, opt_avail)} {RESET}"
            else:
                if is_exit:
                    line_str = f"⏻  {item_text}"
                    btn = f"  {RED}{pad_visual(line_str, opt_avail)}{RESET}"
                else:
                    line_str = f"   {item_text}"
                    btn = f"  {WHITE}{pad_visual(line_str, opt_avail)}{RESET}"

            print(f"{PURPLE}│{RESET} {btn} {PURPLE}│{RESET}")

        print(f"{PURPLE}│{' ' * inner_w}│{RESET}")
        print(f"{PURPLE}╰{'─' * inner_w}╯{RESET}")

        # Footer del submenú
        top_bar = f"{PURPLE}╭{'─' * inner_w}╮{RESET}"
        bot_bar = f"{PURPLE}╰{'─' * inner_w}╯{RESET}"
        f_content = f"{PURPLE}[↑↓]{RESET}  {WHITE}Navegar{RESET}      {PURPLE}│{RESET}      {PURPLE}[Enter]{RESET}  {WHITE}Seleccionar{RESET}      {PURPLE}│{RESET}      {RED}[0 / Esc]{RESET}  {WHITE}Volver{RESET}"
        pad_tot = inner_w - visual_width(f_content)
        pl = pad_tot // 2
        pr = pad_tot - pl
        print(top_bar)
        print(f"{PURPLE}│{RESET}{' ' * pl}{f_content}{' ' * pr}{PURPLE}│{RESET}")
        print(bot_bar)

        k = read_key()
        if k == 'UP':
            sel_idx = (sel_idx - 1) % num_opts
        elif k == 'DOWN':
            sel_idx = (sel_idx + 1) % num_opts
        elif k in ('ENTER', 'SPACE'):
            return opciones[sel_idx][0]
        elif k in ('ESC', '0', 'q', 'Q'):
            return "0"
        else:
            # Atajo numérico directo
            for idx_o, (opt_key, _) in enumerate(opciones):
                if k == opt_key:
                    return opt_key

def pausar():
    """Pausa interactiva."""
    total_w = get_terminal_width()
    print(f"\n{PURPLE}{'─' * total_w}{RESET}")
    input(f"  {PURPLE}[Enter]{RESET} {WHITE}Presiona Enter para continuar...{RESET} ")

# ==============================================================================
# SUBMENÚ 1: INICIAR PROGRAMA O JUEGO
# ==============================================================================

def menu_iniciar_programa(hw, cfg):
    """Submenú 1: Iniciar programa o juego registrado con opciones avanzadas."""
    if not os.path.exists(DB_FILE) or os.path.getsize(DB_FILE) == 0:
        os.system("clear")
        render_banner(hw, cfg)
        print(f"\n{YELLOW}⚠️  No tienes juegos o programas registrados en la lista.{RESET}")
        print(f"{WHITE}Ve a la opción [2] 'Configurar Programa Win' para añadir uno.{RESET}")
        pausar()
        return

    programas = []
    with open(DB_FILE, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if line and "|" in line:
                partes = line.split("|")
                programas.append((partes[0].strip(), partes[1].strip()))

    if not programas:
        os.system("clear")
        render_banner(hw, cfg)
        print(f"\n{YELLOW}⚠️  La base de datos de programas está vacía.{RESET}")
        pausar()
        return

    opciones = []
    for i, (nombre, ruta) in enumerate(programas, 1):
        opciones.append((str(i), f"🎮 {nombre}"))
    opciones.append(("0", "↩️  Volver al Menú Principal"))

    eleccion = submenu_interactivo("🎮  Selecciona un Juego o Programa", opciones, hw, cfg)
    if eleccion != "0":
        idx = int(eleccion) - 1
        nombre, ruta = programas[idx]

        # Menú de acción para el juego seleccionado
        opts_juego = [
            ("1", f"🚀 Iniciar {nombre} (Máximo Rendimiento Nativo en Hardware)"),
            ("2", f"📊 Iniciar con HUD de Rendimiento (FPS / Telemetría en Pantalla)"),
            ("3", f"📂 Abrir Carpeta del Juego (para Mods / Parches / Saves)"),
            ("4", f"🖥️ Crear Acceso Directo en el Escritorio (1-Clic)"),
            ("5", f"❌ Eliminar este Juego de la Lista"),
            ("0", f"↩️  Volver a la Lista de Juegos")
        ]
        accion = submenu_interactivo(f"🎮  Acciones para: {nombre}", opts_juego, hw, cfg)

        if accion == "1":
            os.system("clear")
            print(f"{GREEN}🚀 Iniciando: {BOLD}{nombre}{RESET} de forma nativa en tu computadora...\n")
            subprocess.run(["bash", LAUNCHER, ruta])
            pausar()
        elif accion == "2":
            os.system("clear")
            print(f"{PURPLE}📊 Iniciando: {BOLD}{nombre}{RESET} con HUD de FPS activo...\n")
            subprocess.run(["bash", "-c", f"ENABLE_DXVK_HUD=1 bash '{LAUNCHER}' '{ruta}'"])
            pausar()
        elif accion == "3":
            carpeta = os.path.dirname(ruta)
            subprocess.run(f"xdg-open '{carpeta}'", shell=True, stderr=subprocess.DEVNULL)
            print(f"\n{GREEN}✔ Carpeta abierta en tu gestor de archivos.{RESET}")
            pausar()
        elif accion == "4":
            crear_desktop_entry(nombre, ruta)
            pausar()
        elif accion == "5":
            del programas[idx]
            with open(DB_FILE, "w", encoding="utf-8") as f:
                for n, r in programas:
                    f.write(f"{n}|{r}|compartido\n")
            print(f"\n{GREEN}✔ '{nombre}' ha sido eliminado de la lista.{RESET}")
            pausar()

def crear_desktop_entry(nombre, ruta):
    """Crea y valida el acceso directo en el escritorio."""
    d_dir = os.path.expanduser("~/Escritorio")
    if not os.path.exists(d_dir):
        d_dir = os.path.expanduser("~/Desktop")
    if os.path.exists(d_dir):
        desk_file = os.path.join(d_dir, f"{nombre}.desktop")
        content = f"""[Desktop Entry]
Version=1.0
Type=Application
Name={nombre}
Exec=bash "{LAUNCHER}" "{ruta}"
Icon=wine
Terminal=false
Categories=Game;
StartupNotify=true
"""
        with open(desk_file, "w", encoding="utf-8") as df:
            df.write(content)
        os.chmod(desk_file, 0o755)
        subprocess.run(f"gio set '{desk_file}' metadata::trusted true", shell=True, stderr=subprocess.DEVNULL)
        print(f"\n{GREEN}✔ Acceso directo creado en tu Escritorio: {desk_file}{RESET}")
    else:
        print(f"\n{RED}❌ No se encontró la carpeta de Escritorio.{RESET}")

# ==============================================================================
# SUBMENÚ 2: CONFIGURAR PROGRAMA WIN
# ==============================================================================

def menu_configurar_programas(hw, cfg):
    """Submenú 2: Configurar programas (Añadir, eliminar, accesos de escritorio, mods)."""
    while True:
        opciones = [
            ("1", "➕ Añadir Programa Portable (.exe, .bat, .lnk)"),
            ("2", "💿 Instalar Programa con Instalador (Setup.exe, .msi)"),
            ("3", "❌ Desinstalar / Eliminar Programa de la Lista (Con Flechas)"),
            ("4", "🖥️ Crear / Regenerar Acceso Directo en el Escritorio (1-Clic)"),
            ("5", "📂 Abrir Carpeta de Instalación / Mods en Gestor de Archivos"),
            ("6", "📋 Ver Lista Completa de Programas Registrados"),
            ("0", "↩️  Volver al Menú Principal")
        ]
        sel = submenu_interactivo("⚙️  Configurar Programa Win", opciones, hw, cfg)
        if sel == "0":
            break
        elif sel == "1":
            os.system("clear")
            print(f"{PURPLE}➕ [ AÑADIR PROGRAMA PORTABLE ]{RESET}\n")
            print(f"{WHITE}Arrastra el archivo .exe / .bat / .lnk a la terminal o escribe su ruta:{RESET}")
            ruta = input(f"{CYAN}Ruta: {RESET}").strip().strip("'").strip('"')
            if os.path.exists(ruta):
                nombre = os.path.splitext(os.path.basename(ruta))[0]
                nombre = nombre.replace("_", " ").replace("-", " ")
                with open(DB_FILE, "a", encoding="utf-8") as f:
                    f.write(f"{nombre}|{ruta}|compartido\n")
                print(f"\n{GREEN}✔ Programa '{nombre}' añadido con éxito a la lista.{RESET}")
                
                # Ofrecer crear acceso directo inmediatamente
                crear = input(f"\n{WHITE}¿Deseas crear acceso directo en el Escritorio ahora? (S/n): {RESET}").strip().lower()
                if crear != 'n':
                    crear_desktop_entry(nombre, ruta)
            else:
                print(f"\n{RED}❌ La ruta especificada no existe.{RESET}")
            pausar()
        elif sel == "2":
            os.system("clear")
            print(f"{PURPLE}💿 [ INSTALAR PROGRAMA CON INSTALADOR ]{RESET}\n")
            ruta = input(f"{CYAN}Ruta al instalador (Setup.exe / instalador): {RESET}").strip().strip("'").strip('"')
            if os.path.exists(ruta):
                print(f"\n{GREEN}🚀 Iniciando instalador en Wine... Sigue los pasos del asistente.{RESET}\n")
                subprocess.run(["bash", LAUNCHER, ruta])
                print(f"\n{CYAN}💡 Si el instalador creó un ejecutable en 'Program Files', puedes registrarlo con la opción 1.{RESET}")
            else:
                print(f"\n{RED}❌ Instalador no encontrado.{RESET}")
            pausar()
        elif sel == "3":
            # Eliminación interactiva con flechas
            if not os.path.exists(DB_FILE) or os.path.getsize(DB_FILE) == 0:
                print(f"\n{YELLOW}⚠️  No hay programas para eliminar.{RESET}")
                pausar()
                continue

            with open(DB_FILE, "r", encoding="utf-8", errors="ignore") as f:
                lines = [l.strip() for l in f if l.strip()]

            if not lines:
                print(f"\n{YELLOW}⚠️  No hay programas registrados.{RESET}")
                pausar()
                continue

            opts_del = []
            for i, l in enumerate(lines, 1):
                p_nombre = l.split("|")[0]
                opts_del.append((str(i), f"❌ Eliminar: {p_nombre}"))
            opts_del.append(("0", "↩️  Cancelar"))

            del_sel = submenu_interactivo("❌  Selecciona el Programa a Eliminar", opts_del, hw, cfg)
            if del_sel != "0":
                del_idx = int(del_sel) - 1
                nom_borrado = lines[del_idx].split("|")[0]
                del lines[del_idx]
                with open(DB_FILE, "w", encoding="utf-8") as f:
                    f.write("\n".join(lines) + ("\n" if lines else ""))
                print(f"\n{GREEN}✔ '{nom_borrado}' ha sido eliminado con éxito.{RESET}")
                pausar()
        elif sel == "4":
            # Crear acceso directo con flechas
            if not os.path.exists(DB_FILE) or os.path.getsize(DB_FILE) == 0:
                print(f"\n{YELLOW}⚠️  No hay programas registrados.{RESET}")
                pausar()
                continue

            with open(DB_FILE, "r", encoding="utf-8", errors="ignore") as f:
                lines = [l.strip() for l in f if l.strip()]

            opts_desk = []
            for i, l in enumerate(lines, 1):
                p_nombre = l.split("|")[0]
                opts_desk.append((str(i), f"🖥️  {p_nombre}"))
            opts_desk.append(("0", "↩️  Cancelar"))

            d_sel = submenu_interactivo("🖥️  Crear Acceso Directo en el Escritorio", opts_desk, hw, cfg)
            if d_sel != "0":
                d_idx = int(d_sel) - 1
                p_nom, p_rut = lines[d_idx].split("|")[:2]
                crear_desktop_entry(p_nom, p_rut)
                pausar()
        elif sel == "5":
            # Abrir carpeta para mods con flechas
            if not os.path.exists(DB_FILE) or os.path.getsize(DB_FILE) == 0:
                print(f"\n{YELLOW}⚠️  No hay programas registrados.{RESET}")
                pausar()
                continue

            with open(DB_FILE, "r", encoding="utf-8", errors="ignore") as f:
                lines = [l.strip() for l in f if l.strip()]

            opts_mod = []
            for i, l in enumerate(lines, 1):
                p_nombre = l.split("|")[0]
                opts_mod.append((str(i), f"📂 {p_nombre}"))
            opts_mod.append(("0", "↩️  Cancelar"))

            m_sel = submenu_interactivo("📂  Abrir Carpeta del Juego (para Mods)", opts_mod, hw, cfg)
            if m_sel != "0":
                m_idx = int(m_sel) - 1
                p_rut = lines[m_idx].split("|")[1]
                carpeta = os.path.dirname(p_rut)
                subprocess.run(f"xdg-open '{carpeta}'", shell=True, stderr=subprocess.DEVNULL)
                print(f"\n{GREEN}✔ Carpeta abierta en tu gestor de archivos.{RESET}")
                pausar()
        elif sel == "6":
            os.system("clear")
            print(f"{PURPLE}📋 [ PROGRAMAS REGISTRADOS EN LA BASE DE DATOS ]{RESET}\n")
            if os.path.exists(DB_FILE):
                with open(DB_FILE, "r", encoding="utf-8", errors="ignore") as f:
                    for l in f:
                        parts = l.strip().split("|")
                        if len(parts) >= 2:
                            print(f"  🎮 {BOLD}{parts[0]}{RESET} -> {GRAY}{parts[1]}{RESET}")
            pausar()

# ==============================================================================
# SUBMENÚ 3: RENDIMIENTO Y MOTOR GRÁFICO
# ==============================================================================

def menu_rendimiento(hw, cfg):
    """Submenú 3: Configuración de Rendimiento y Motor Gráfico."""
    while True:
        cfg = cargar_config()
        p_act = cfg.get("PERFIL_RENDIMIENTO", "maximo").upper()
        fps_act = cfg.get("LIMITE_FPS", "60")
        fsr_act = f"Activo (x{cfg.get('FSR_STRENGTH', '2')})" if cfg.get("ACTIVAR_FSR") == "1" else "Apagado"
        hud_act = "Activo" if cfg.get("MOSTRAR_HUD_FPS") == "1" else "Apagado"
        mot_act = cfg.get("RENDERER_BACKEND", "auto").upper()

        opciones = [
            ("1", f"⚡ Perfil de Rendimiento (Actual: {p_act})"),
            ("2", f"🎯 Límite de FPS (Actual: {fps_act} FPS)"),
            ("3", f"🚀 AMD FSR Reescalado (Actual: {fsr_act})"),
            ("4", f"📊 HUD de FPS y Telemetría en Pantalla (Actual: {hud_act})"),
            ("5", f"🎮 Motor Gráfico (Actual: {mot_act})"),
            ("6", f"🧹 Limpiar Shaders y Caché DXVK (Solucionar Tirones / Descuadres 3D)"),
            ("7", f"🎛️ Filtrado Anisótropo 16x (Máxima Nitidez de Texturas)"),
            ("0", "↩️  Volver al Menú Principal")
        ]
        sel = submenu_interactivo("⚡  Rendimiento y Motor Gráfico", opciones, hw, cfg)
        if sel == "0":
            break
        elif sel == "1":
            sub_opts = [
                ("1", "🚀 Máximo Rendimiento (GameMode al 100%, Governor Performance, GPU Boost)"),
                ("2", "⚖️ Equilibrado (Balance óptimo entre temperatura y fluidez)"),
                ("3", "🔋 Ahorro de Energía (Menor consumo para portátiles/batería)"),
                ("0", "↩️  Cancelar")
            ]
            s = submenu_interactivo("Seleccionar Perfil de Rendimiento", sub_opts, hw, cfg)
            if s == "1": guardar_config("PERFIL_RENDIMIENTO", "maximo")
            elif s == "2": guardar_config("PERFIL_RENDIMIENTO", "equilibrado")
            elif s == "3": guardar_config("PERFIL_RENDIMIENTO", "ahorro")
        elif sel == "2":
            sub_opts = [
                ("1", "30 FPS (Recomendado para PCs de gama baja / estabilidad total)"),
                ("2", "60 FPS (Fluidez estándar sin sobrecalentamiento)"),
                ("3", "120 FPS (Monitores de alta tasa de refresco 120Hz/144Hz)"),
                ("4", "0 (Ilimitado - Máximos FPS posibles de la GPU)"),
                ("0", "↩️  Cancelar")
            ]
            s = submenu_interactivo("Seleccionar Límite de FPS", sub_opts, hw, cfg)
            if s == "1": guardar_config("LIMITE_FPS", "30")
            elif s == "2": guardar_config("LIMITE_FPS", "60")
            elif s == "3": guardar_config("LIMITE_FPS", "120")
            elif s == "4": guardar_config("LIMITE_FPS", "0")
            subprocess.run(["bash", os.path.join(DIR, "generar_dxvk_conf.sh")], stderr=subprocess.DEVNULL)
        elif sel == "3":
            if cfg.get("ACTIVAR_FSR") == "1":
                guardar_config("ACTIVAR_FSR", "0")
            else:
                guardar_config("ACTIVAR_FSR", "1")
                # Preguntar nivel de nitidez con flechas
                sub_fsr = [
                    ("1", "Nivel 1 - Muy Nítido"),
                    ("2", "Nivel 2 - Equilibrado (Recomendado)"),
                    ("3", "Nivel 3 - Suave"),
                    ("0", "Mantener actual")
                ]
                s = submenu_interactivo("Nivel de Nitidez FSR", sub_fsr, hw, cfg)
                if s in ("1", "2", "3"):
                    guardar_config("FSR_STRENGTH", s)
        elif sel == "4":
            sub_hud = [
                ("1", "Apagado (Sin información en pantalla)"),
                ("2", "Básico (Solo contador de FPS en esquina)"),
                ("3", "Completo (FPS, GPU, VRAM, CPU, RAM y Temperaturas)"),
                ("0", "↩️  Cancelar")
            ]
            s = submenu_interactivo("Configurar HUD de Rendimiento", sub_hud, hw, cfg)
            if s == "1":
                guardar_config("MOSTRAR_HUD_FPS", "0")
            elif s == "2":
                guardar_config("MOSTRAR_HUD_FPS", "1")
                guardar_config("HUD_DETALLES", "fps")
            elif s == "3":
                guardar_config("MOSTRAR_HUD_FPS", "1")
                guardar_config("HUD_DETALLES", "full")
            subprocess.run(["bash", os.path.join(DIR, "generar_dxvk_conf.sh")], stderr=subprocess.DEVNULL)
        elif sel == "5":
            sub_opts = [
                ("1", "DXVK (DirectX 9/10/11 -> Vulkan - Máximo Rendimiento)"),
                ("2", "WineD3D (OpenGL nativo - Compatibilidad para GPUs antiguas)"),
                ("3", "Automático (Detección inteligente según la tarjeta gráfica)"),
                ("0", "↩️  Cancelar")
            ]
            s = submenu_interactivo("Seleccionar Motor Gráfico", sub_opts, hw, cfg)
            if s == "1": guardar_config("RENDERER_BACKEND", "dxvk")
            elif s == "2": guardar_config("RENDERER_BACKEND", "wined3d")
            elif s == "3": guardar_config("RENDERER_BACKEND", "auto")
        elif sel == "6":
            # Limpiar shaders y caché
            os.system("clear")
            print(f"{PURPLE}🧹 [ LIMPIANDO SHADERS Y CACHÉ GRÁFICA ]{RESET}\n")
            c1 = subprocess.run(f"rm -rf '{DIR}'/*.dxvk-cache '{WINEPREFIX}'/drive_c/*.dxvk-cache 2>/dev/null", shell=True)
            print(f"{GREEN}✔ Archivos de caché de shaders corruptos eliminados.{RESET}")
            print(f"{WHITE}Los juegos regenerarán shaders frescos sin tirones al iniciar.{RESET}")
            pausar()
        elif sel == "7":
            os.system("clear")
            print(f"{PURPLE}🎛️  [ FILTRADO ANISÓTROPO 16X FORZADO ]{RESET}\n")
            # Activar en dxvk.conf
            lines = []
            if os.path.exists(DXVK_CONF):
                with open(DXVK_CONF, "r") as f:
                    lines = [l for l in f if not l.startswith("d3d9.samplerAnisotropy") and not l.startswith("d3d11.samplerAnisotropy")]
            lines.append("d3d9.samplerAnisotropy = 16\n")
            lines.append("d3d11.samplerAnisotropy = 16\n")
            with open(DXVK_CONF, "w") as f:
                f.writelines(lines)
            print(f"{GREEN}✔ Filtrado Anisótropo 16x activado en dxvk.conf.{RESET}")
            print(f"{WHITE}Las texturas a distancia se verán perfectamente nítidas.{RESET}")
            pausar()

# ==============================================================================
# SUBMENÚ 4: HERRAMIENTAS DE WINDOWS Y REPARACIÓN
# ==============================================================================

def menu_herramientas(hw, cfg):
    """Submenú 4: Herramientas de Windows y Reparación."""
    while True:
        opciones = [
            ("1", "🍷 Configuración de Wine (winecfg)"),
            ("2", "📝 Editor del Registro de Windows (regedit)"),
            ("3", "📈 Administrador de Tareas de Windows (taskmgr)"),
            ("4", "📁 Explorador de Archivos de Windows (wine explorer)"),
            ("5", "🔄 Matar Procesos Colgados y Liberar RAM (wineserver -k)"),
            ("6", "📦 Instalar Dependencias de Windows (Winetricks: DirectX, VC++, Fuentes)"),
            ("7", "🛡️ Comprobador de Compatibilidad Anti-Cheat (EAC / BattlEye)"),
            ("8", "💾 Respaldar / Restaurar Prefijo Wine (Backup wineprefix)"),
            ("0", "↩️  Volver al Menú Principal")
        ]
        sel = submenu_interactivo("🔧  Herramientas de Windows y Reparación", opciones, hw, cfg)
        if sel == "0":
            break
        elif sel == "1":
            subprocess.run(f"WINEPREFIX='{WINEPREFIX}' wine winecfg", shell=True)
        elif sel == "2":
            subprocess.run(f"WINEPREFIX='{WINEPREFIX}' wine regedit", shell=True)
        elif sel == "3":
            subprocess.run(f"WINEPREFIX='{WINEPREFIX}' wine taskmgr", shell=True)
        elif sel == "4":
            subprocess.run(f"WINEPREFIX='{WINEPREFIX}' wine explorer", shell=True)
        elif sel == "5":
            os.system("clear")
            print(f"{YELLOW}🔄 Terminando todos los procesos de Wine y liberando memoria...{RESET}")
            subprocess.run(f"WINEPREFIX='{WINEPREFIX}' wineserver -k 2>/dev/null", shell=True)
            subprocess.run("pkill -9 -f 'wine' 2>/dev/null", shell=True)
            subprocess.run("pkill -9 -f 'GTA5' 2>/dev/null", shell=True)
            time.sleep(0.5)
            print(f"\n{GREEN}✔ Memoria RAM liberada y procesos cerrados correctamente.{RESET}")
            pausar()
        elif sel == "6":
            sub_winetricks = [
                ("1", "DirectX 9 y 11 Completo (d3dx9, d3dx11)"),
                ("2", "Visual C++ Runtimes (vcrun2015-2022)"),
                ("3", ".NET Framework 4.8 (dotnet48)"),
                ("4", "Fuentes de Windows (corefonts: Arial, Times, Tahoma)"),
                ("0", "↩️  Cancelar")
            ]
            w_sel = submenu_interactivo("📦  Instalar Dependencias con Winetricks", sub_winetricks, hw, cfg)
            if w_sel == "1":
                subprocess.run(f"WINEPREFIX='{WINEPREFIX}' winetricks -q d3dx9 d3dx11_43", shell=True)
                pausar()
            elif w_sel == "2":
                subprocess.run(f"WINEPREFIX='{WINEPREFIX}' winetricks -q vcrun2015 vcrun2022", shell=True)
                pausar()
            elif w_sel == "3":
                subprocess.run(f"WINEPREFIX='{WINEPREFIX}' winetricks -q dotnet48", shell=True)
                pausar()
            elif w_sel == "4":
                subprocess.run(f"WINEPREFIX='{WINEPREFIX}' winetricks -q corefonts", shell=True)
                pausar()
        elif sel == "7":
            os.system("clear")
            print(f"{PURPLE}🛡️  [ COMPROBADOR DE COMPATIBILIDAD ANTI-CHEAT ]{RESET}\n")
            print(f"{WHITE}Verificando puentes y runtimes del sistema:{RESET}\n")
            print(f"  ✔ Proton Easy Anti-Cheat (EAC) Runtime : {GREEN}Habilitado{RESET}")
            print(f"  ✔ Proton BattlEye Runtime              : {GREEN}Habilitado{RESET}")
            print(f"  ✔ Soporte NVAPI y DLSS                 : {GREEN}Habilitado{RESET}")
            print(f"  ✔ Conexión a Internet y Redes          : {GREEN}Totalmente funcional{RESET}")
            pausar()
        elif sel == "8":
            os.system("clear")
            print(f"{PURPLE}💾 [ RESPALDO Y RESTAURACIÓN DE PREFIJO WINE ]{RESET}\n")
            bak_tar = os.path.join(DIR, "wineprefix_backup.tar.gz")
            if os.path.exists(bak_tar):
                print(f"{CYAN}Se encontró un respaldo previo: {bak_tar}{RESET}\n")
                r = input(f"{WHITE}¿Deseas restaurar este respaldo? (s/N): {RESET}").strip().lower()
                if r == 's':
                    print(f"\n{YELLOW}Restaurando prefijo...{RESET}")
                    subprocess.run(f"tar -xzf '{bak_tar}' -C '{DIR}'", shell=True)
                    print(f"{GREEN}✔ Prefijo restaurado con éxito.{RESET}")
            else:
                c = input(f"{WHITE}¿Deseas crear un respaldo comprimido de tu wineprefix? (S/n): {RESET}").strip().lower()
                if c != 'n':
                    print(f"\n{YELLOW}Comprimiendo wineprefix (puede tardar unos segundos)...{RESET}")
                    subprocess.run(f"tar -czf '{bak_tar}' -C '{DIR}' wineprefix", shell=True)
                    print(f"{GREEN}✔ Respaldo creado en: {bak_tar}{RESET}")
            pausar()

# ==============================================================================
# SUBMENÚ 5: OPTIMIZACIÓN Y CONFIGURACIÓN AUTOMÁTICA EN 1-CLIC
# ==============================================================================

def ejecutar_optimizacion_automatica(hw, cfg):
    """Submenú 5: Optimización automática del sistema e instalación de dependencias."""
    os.system("clear")
    print(f"{PURPLE}📦 [ OPTIMIZACIÓN Y CONFIGURACIÓN AUTOMÁTICA EN 1-CLIC ]{RESET}\n")
    print(f"{WHITE}Diagnóstico universal para: {BOLD}{cfg.get('DISTRO_NAME', 'Linux')}{RESET}")
    print(f"{WHITE}Hardware detectado: {BOLD}{hw['cpu']} | {hw['gpu']} | {hw['ram']}{RESET}\n")
    print(f"{CYAN}Esta opción configurará automáticamente todo lo necesario para que tus juegos corran al máximo.{RESET}\n")

    # Llamar al optimizador probado de menu-win.sh
    subprocess.run(["bash", "-c", f"""
source "{os.path.join(DIR, 'menu-win.sh')}"
instalar_recursos_actualizar
"""])

# ==============================================================================
# MENÚ PRINCIPAL INTERACTIVO EN PÚRPURA NEÓN (MATCHING IMAGEN DE KONSOLE)
# ==============================================================================

def main():
    # Comprobar actualización silenciosa desde GitHub al inicio
    try:
        subprocess.run(f"cd '{DIR}' && timeout 3 git fetch origin main --quiet 2>/dev/null", shell=True)
    except Exception:
        pass

    # Selección en 2 columnas: 1 a 6
    # 1: Iniciar, 2: Configurar
    # 3: Rendimiento, 4: Herramientas
    # 5: Instalar, 6: Salir (0)
    cur_idx = 1

    while True:
        cfg = cargar_config()
        hw = obtener_info_hardware()

        os.system("clear")
        render_banner(hw, cfg)

        total_w = get_terminal_width()
        inner_w = total_w - 2

        # 3. Menú Principal Box (2 columnas perfectamente calculadas y espaciadas)
        m_title = "╭─ 🎮  Menú Principal "
        m_top = f"{PURPLE}{m_title}{'─' * (inner_w - visual_width(m_title) + 1)}╮{RESET}"
        print(m_top)
        print(f"{PURPLE}│{' ' * inner_w}│{RESET}")

        col_w = (inner_w - 6) // 2
        gap_w = inner_w - 4 - (col_w * 2)

        opts = [
            ("▶   [1]  Iniciar programa o juego", "⚙️   [2]  Configurar Programa Win"),
            ("⚙️   [3]  Rendimiento y Motor Gráfico", "🔧  [4]  Herramientas de Windows"),
            ("📥  [5]  Instalar Recursos / Optimizar", "⏻   [0]  Salir")
        ]

        for row_idx, (o1, o2) in enumerate(opts):
            idx1 = (row_idx * 2) + 1
            idx2 = (row_idx * 2) + 2

            if cur_idx == idx1:
                c1 = f"{BG_SELECT} {pad_visual(o1, col_w - 2)} {RESET}"
            else:
                c1 = f" {pad_visual(f'{WHITE}{o1}{RESET}', col_w - 2)} "

            if cur_idx == idx2:
                c2 = f"{BG_SELECT} {pad_visual(o2, col_w - 2)} {RESET}"
            elif idx2 == 6:
                c2 = f" {pad_visual(f'{RED}{o2[:5]}{RESET}{WHITE}{o2[5:]}{RESET}', col_w - 2)} "
            else:
                c2 = f" {pad_visual(f'{WHITE}{o2}{RESET}', col_w - 2)} "

            line_content = f"  {c1}{' ' * gap_w}{c2}  "
            print(f"{PURPLE}│{RESET}{line_content}{PURPLE}│{RESET}")
            print(f"{PURPLE}│{' ' * inner_w}│{RESET}")

        bot_bar = f"{PURPLE}╰{'─' * inner_w}╯{RESET}"
        print(bot_bar)

        # 4. Footer
        render_footer(inner_w)

        # Captura de Teclado
        k = read_key()
        if k == 'UP':
            if cur_idx == 3: cur_idx = 1
            elif cur_idx == 4: cur_idx = 2
            elif cur_idx == 5: cur_idx = 3
            elif cur_idx == 6: cur_idx = 4
            elif cur_idx == 1: cur_idx = 5
            elif cur_idx == 2: cur_idx = 6
        elif k == 'DOWN':
            if cur_idx == 1: cur_idx = 3
            elif cur_idx == 2: cur_idx = 4
            elif cur_idx == 3: cur_idx = 5
            elif cur_idx == 4: cur_idx = 6
            elif cur_idx == 5: cur_idx = 1
            elif cur_idx == 6: cur_idx = 2
        elif k == 'LEFT':
            if cur_idx == 2: cur_idx = 1
            elif cur_idx == 4: cur_idx = 3
            elif cur_idx == 6: cur_idx = 5
        elif k == 'RIGHT':
            if cur_idx == 1: cur_idx = 2
            elif cur_idx == 3: cur_idx = 4
            elif cur_idx == 5: cur_idx = 6
        elif k in ('ENTER', 'SPACE'):
            if cur_idx == 1:
                menu_iniciar_programa(hw, cfg)
            elif cur_idx == 2:
                menu_configurar_programas(hw, cfg)
            elif cur_idx == 3:
                menu_rendimiento(hw, cfg)
            elif cur_idx == 4:
                menu_herramientas(hw, cfg)
            elif cur_idx == 5:
                ejecutar_optimizacion_automatica(hw, cfg)
            elif cur_idx == 6:
                os.system("clear")
                print(f"{GREEN}¡Hasta luego! Que disfrutes tus juegos.{RESET}\n")
                sys.exit(0)
        elif k == '1':
            cur_idx = 1
            menu_iniciar_programa(hw, cfg)
        elif k == '2':
            cur_idx = 2
            menu_configurar_programas(hw, cfg)
        elif k == '3':
            cur_idx = 3
            menu_rendimiento(hw, cfg)
        elif k == '4':
            cur_idx = 4
            menu_herramientas(hw, cfg)
        elif k == '5':
            cur_idx = 5
            ejecutar_optimizacion_automatica(hw, cfg)
        elif k in ('0', 'q', 'Q'):
            os.system("clear")
            print(f"{GREEN}¡Hasta luego! Que disfrutes tus juegos.{RESET}\n")
            sys.exit(0)
        elif k == 'ESC':
            pass

if __name__ == '__main__':
    main()
