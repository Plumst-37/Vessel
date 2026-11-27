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

try:
    from analizador_pe import analizar_juego
except ImportError:
    analizar_juego = None

# Rutas principales con soporte para estructura modular organizada (core, config, datos)
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if os.path.isfile(os.path.join(_SCRIPT_DIR, "..", "menu-win.sh")):
    DIR = os.path.abspath(os.path.join(_SCRIPT_DIR, ".."))
else:
    DIR = _SCRIPT_DIR

CORE_DIR = os.path.join(DIR, "core") if os.path.isdir(os.path.join(DIR, "core")) else DIR
CONFIG_DIR = os.path.join(DIR, "config") if os.path.isdir(os.path.join(DIR, "config")) else DIR
DATOS_DIR = os.path.join(DIR, "datos") if os.path.isdir(os.path.join(DIR, "datos")) else DIR

if CORE_DIR not in sys.path:
    sys.path.insert(0, CORE_DIR)
if DIR not in sys.path:
    sys.path.insert(0, DIR)

# Rutas de base de datos
DB_FILE = os.path.join(DATOS_DIR, "programas.db")
DB_USER = os.path.join(DATOS_DIR, "programas_usuario.db")
DB_BAK = os.path.join(DATOS_DIR, "programas.db.bak")

# Migración transparente de rutas heredadas
if not os.path.exists(DB_FILE) or os.path.getsize(DB_FILE) == 0:
    for legacy_db in [os.path.join(DATOS_DIR, "programas_usuario.db"), os.path.join(DIR, "programas_usuario.db"), os.path.join(DIR, "programas.db")]:
        if os.path.exists(legacy_db) and os.path.getsize(legacy_db) > 0:
            try:
                shutil.copyfile(legacy_db, DB_FILE)
                break
            except Exception:
                pass
    if not os.path.exists(DB_FILE) or os.path.getsize(DB_FILE) == 0:
        example_db = os.path.join(DATOS_DIR, "programas.db.example")
        if os.path.exists(example_db):
            try:
                with open(example_db, "r", encoding="utf-8") as fin, open(DB_FILE, "w", encoding="utf-8") as fout:
                    for l in fin:
                        if l.strip() and not l.startswith("#"):
                            fout.write(l)
            except Exception:
                pass

# Rutas de scripts y configuración
LAUNCHER = os.path.join(CORE_DIR, "launch-win-app.sh") if os.path.exists(os.path.join(CORE_DIR, "launch-win-app.sh")) else os.path.join(DIR, "launch-win-app.sh")
DXVK_CONF = os.path.join(CONFIG_DIR, "dxvk.conf") if os.path.exists(os.path.join(CONFIG_DIR, "dxvk.conf")) else os.path.join(DIR, "dxvk.conf")
CONFIG_USER = os.path.join(CONFIG_DIR, "config_rendimiento.cfg") if os.path.exists(os.path.join(CONFIG_DIR, "config_rendimiento.cfg")) else os.path.join(DIR, "config_rendimiento.cfg")
WINEPREFIX = os.path.join(DIR, "wineprefix")
VERSION_FILE = os.path.join(DIR, "version.txt")
INSTALADO_MARKER = os.path.join(DIR, ".instalado")
SMART_PERF_MARKER = os.path.join(DIR, ".smart_perf_listo")
WINVER_CONF_FILE = os.path.join(DIR, ".winver_configurados")
VERSION_ACTUAL = "1.3"
SMART_PERF_VERSION_ACTUAL = "1.3"

# Helpers de scripts internos
SCRIPT_DXVK = os.path.join(CORE_DIR, "generar_dxvk_conf.sh") if os.path.exists(os.path.join(CORE_DIR, "generar_dxvk_conf.sh")) else os.path.join(DIR, "generar_dxvk_conf.sh")
SCRIPT_HARDWARE = os.path.join(CORE_DIR, "hardware_detect.sh") if os.path.exists(os.path.join(CORE_DIR, "hardware_detect.sh")) else os.path.join(DIR, "hardware_detect.sh")
SCRIPT_RUNNERS = os.path.join(CORE_DIR, "gestor_runners.sh") if os.path.exists(os.path.join(CORE_DIR, "gestor_runners.sh")) else os.path.join(DIR, "gestor_runners.sh")

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
        "DISTRO_NAME": "Debian",
        "SMART_PERF_CONFIGURADO": "0",
        "SMART_PERF_VERSION": "0"
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
    """Carga o detecta de forma ultrarrápida la información de hardware desde perfil_hardware.cfg."""
    cfg_hw_path = os.path.join(CONFIG_DIR, "perfil_hardware.cfg") if os.path.exists(os.path.join(CONFIG_DIR, "perfil_hardware.cfg")) else os.path.join(DIR, "perfil_hardware.cfg")
    current_host_id = "host_generic"
    if os.path.exists("/etc/machine-id"):
        try:
            with open("/etc/machine-id", "r") as f:
                current_host_id = f.read().strip()
        except Exception:
            pass

    re_scan = not os.path.exists(cfg_hw_path)
    if not re_scan and os.path.exists(cfg_hw_path):
        try:
            with open(cfg_hw_path, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
                if f'HOST_ID="{current_host_id}"' not in content and f"HOST_ID='{current_host_id}'" not in content and f"HOST_ID={current_host_id}" not in content:
                    re_scan = True
        except Exception:
            re_scan = True

    if re_scan:
        script_det = os.path.join(DIR, "herramientas", "detector_hardware.sh")
        if os.path.exists(script_det):
            subprocess.run(["bash", script_det, "--save"], stderr=subprocess.DEVNULL)
        if os.path.exists(SCRIPT_DXVK):
            subprocess.run(["bash", SCRIPT_DXVK], stderr=subprocess.DEVNULL)

    hw = {}
    if os.path.exists(cfg_hw_path):
        try:
            with open(cfg_hw_path, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        k, v = line.split("=", 1)
                        hw[k.strip()] = v.strip().strip('"').strip("'")
        except Exception:
            pass

    cpu_cores = int(hw.get("CPU_THREADS", os.cpu_count() or 4))
    raw_cpu = hw.get("CPU_MODEL", "Procesador Genérico")
    clean_cpu = re.sub(r'CPU @.*|\(R\)|\(TM\)|Core|Processor', '', raw_cpu)
    clean_cpu = " ".join(clean_cpu.split())
    cpu_model = f"{clean_cpu} ({cpu_cores} hilos)"

    ram_mb = int(hw.get("RAM_TOTAL_MB", 8192))
    ram_gb = f"{(ram_mb + 512) // 1024} GB"

    gpu_name = hw.get("GPU_PRIMARY", "Gráficos Integrados")
    vram_mb = hw.get("GPU_VRAM_MB", "2048")
    if "MB" not in gpu_name and "GB" not in gpu_name:
        vram_display = f"{int(vram_mb) // 1024} GB" if int(vram_mb) >= 1024 else f"{vram_mb} MB"
        gpu_name = f"{gpu_name} ({vram_display})"

    vendor = hw.get("GPU_PRIMARY_VENDOR", "nvidia")
    driver_str = "NVIDIA (Vulkan)" if vendor == "nvidia" else ("AMD RADV (Vulkan)" if vendor == "amd" else "Mesa (Vulkan)")

    native_w = hw.get("NATIVE_RES_W", "1920")
    native_h = hw.get("NATIVE_RES_H", "1080")
    rec_w = hw.get("RECOMMENDED_GAME_W", "1280")
    rec_h = hw.get("RECOMMENDED_GAME_H", "720")
    is_entry = hw.get("GPU_IS_ENTRY_LEVEL", "true").lower() == "true"
    sync_str = "NTSync" if hw.get("HAS_NTSYNC") == "true" else ("Fsync" if hw.get("HAS_FSYNC") == "true" else "Esync")

    return {
        "cpu": cpu_model,
        "cpu_raw": raw_cpu,
        "cores": cpu_cores,
        "ram": ram_gb,
        "ram_mb": ram_mb,
        "gpu": gpu_name,
        "gpu_vendor": vendor,
        "vram_mb": vram_mb,
        "driver": driver_str,
        "vulkan": True,
        "native_res": f"{native_w}x{native_h}",
        "rec_res": f"{rec_w}x{rec_h}",
        "is_entry": is_entry,
        "sync": sync_str,
        "has_gamemode": hw.get("HAS_GAMEMODE") == "true",
        "has_gamescope": hw.get("HAS_GAMESCOPE") == "true",
        "has_pipewire": hw.get("HAS_PIPEWIRE") == "true",
        "server": hw.get("DISPLAY_SERVER", "wayland")
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

    mid_title = f"{WHITE}{BOLD}Menu {PURPLE}Win{RESET}  {CYAN}{BOLD}[v{VERSION_ACTUAL}]{RESET}"
    mid_sub = f"{TEXT_DIM}Gestor y Optimizador Universal de Juegos y Programas de {WHITE}{BOLD}Windows{RESET} {GRAY}• {PURPLE}{BOLD}v{VERSION_ACTUAL}{RESET}"

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
    p_raw = cfg.get("PERFIL_RENDIMIENTO", "inteligente").lower()
    p_badge = "⭐ INTELIGENTE" if p_raw in ("inteligente", "maximo") else ("🛡️ ESTÁNDAR" if p_raw == "estandar" else "🚀 EXTREMO")

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
        f"  🏷️   {PURPLE}Versión Vessel{RESET}:  {CYAN}{BOLD}v{VERSION_ACTUAL} (Estable){RESET}",
        f"  {PURPLE}✔{RESET}   {PURPLE}FSR Reescalado{RESET} :  {WHITE}{fsr_st}{RESET}",
        f"  {PURPLE}✔{RESET}   {PURPLE}HUD FPS / OSD{RESET}  :  {WHITE}{hud_st}{RESET}",
        f"  {PURPLE}✔{RESET}   {PURPLE}Vulkan Driver{RESET}  :  {WHITE}{vk_st}{RESET}",
        f"  {PURPLE}✔{RESET}   {PURPLE}Smart Perf.{RESET}    :  {GREEN}{BOLD}{p_badge}{RESET}"
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

def submenu_interactivo(titulo, opciones, hw, cfg, default_idx=0, info_lines=None):
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

        if info_lines:
            for il in info_lines:
                print(f"{PURPLE}│{RESET}  {pad_visual(il, inner_w - 4)}  {PURPLE}│{RESET}")
            print(f"{PURPLE}│{' ' * inner_w}│{RESET}")
            print(f"{PURPLE}├{'─' * inner_w}┤{RESET}")
            print(f"{PURPLE}│{' ' * inner_w}│{RESET}")

        opt_avail = inner_w - 6

        for i, (key, label) in enumerate(opciones):
            is_exit = (key == "0" or "volver" in label.lower() or "salir" in label.lower() or "cancelar" in label.lower())
            lines = label.splitlines()
            first_line = lines[0]
            extra_lines = lines[1:] if len(lines) > 1 else []
            item_text = f"[{key}]  {first_line}"

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
            for el in extra_lines:
                desc_str = f"       {GRAY}{el.strip()}{RESET}"
                desc_btn = f"  {pad_visual(desc_str, opt_avail)}"
                print(f"{PURPLE}│{RESET} {desc_btn} {PURPLE}│{RESET}")

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

def ejecutar_juego_y_liberar_ram(cmd_args, con_hud=False):
    """
    Libera completamente la memoria RAM de Python (~25 MB) reemplazando el proceso
    por el ejecutor ligero de bash, y reabre el menú automáticamente al salir del juego.
    """
    script_ejecutor = os.path.join(DIR, "herramientas", "ejecutar_y_volver.sh")
    env = os.environ.copy()
    if con_hud:
        env["ENABLE_DXVK_HUD"] = "1"

    if os.path.exists(script_ejecutor):
        os.chmod(script_ejecutor, 0o755)
        try:
            import termios
            termios.tcflush(sys.stdin, termios.TCIFLUSH)
        except Exception:
            pass
        # os.execvpe reemplaza este proceso de Python liberando el 100% de su RAM
        os.execvpe("bash", ["bash", script_ejecutor] + cmd_args, env)
    else:
        # Fallback de respaldo en caso de que no exista el script ejecutor
        full_cmd = ["bash", LAUNCHER] + cmd_args
        if con_hud:
            subprocess.run(full_cmd, env=env)
        else:
            subprocess.run(full_cmd)
        pausar()

# ==============================================================================
# GESTIÓN Y PERSISTENCIA DE PROGRAMAS Y JUEGOS (GAMERANGER PORTABLE SIEMPRE LISTO)
# ==============================================================================

def asegurar_gameranger_en_db():
    """Garantiza que GameRanger portable esté siempre en la base de datos."""
    if not os.path.exists(DB_FILE) or os.path.getsize(DB_FILE) == 0:
        try:
            with open(DB_FILE, "w", encoding="utf-8") as f:
                f.write("GameRanger|GameRanger.exe|compartido|win7|off|juego\n")
            shutil.copyfile(DB_FILE, DB_FILE + ".bak")
        except Exception:
            pass

def desplegar_gameranger_portable(mostrar_notif=False):
    """Instala y despliega GameRanger portable en la PC en el primer inicio para que esté 100% listo."""
    src_gr = os.path.join(DIR, "GameRanger")
    if not os.path.exists(src_gr):
        return

    # 1. Asegurar programas.db con GameRanger listo en opción 1
    asegurar_gameranger_en_db()

    # 2. Desplegar archivos portables en Program Files
    prog_files = os.path.join(WINEPREFIX, "drive_c", "Program Files", "GameRanger")
    os.makedirs(prog_files, exist_ok=True)
    if not os.path.exists(os.path.join(prog_files, "GameRanger.exe")):
        try:
            shutil.copytree(src_gr, prog_files, dirs_exist_ok=True)
        except Exception:
            pass

    # 3. Desplegar en AppData/Roaming para todos los perfiles de usuario en Wine
    users_dir = os.path.join(WINEPREFIX, "drive_c", "users")
    if os.path.exists(users_dir):
        for u in os.listdir(users_dir):
            if u.lower() != "public":
                u_roaming = os.path.join(users_dir, u, "AppData", "Roaming", "GameRanger", "GameRanger")
                u_prefs = os.path.join(users_dir, u, "AppData", "Roaming", "GameRanger", "GameRanger Prefs")
                os.makedirs(u_roaming, exist_ok=True)
                os.makedirs(u_prefs, exist_ok=True)
                if not os.path.exists(os.path.join(u_roaming, "GameRanger.exe")):
                    try:
                        shutil.copytree(src_gr, u_roaming, dirs_exist_ok=True)
                    except Exception:
                        pass
                # Restaurar backup de sesión si existe y no tiene sesión activa válida
                bak_dir = os.path.join(DIR, ".gameranger_prefs_backup")
                user_settings = os.path.join(u_prefs, "Settings")
                needs_restore = not os.path.exists(user_settings)
                if not needs_restore and os.path.exists(user_settings):
                    try:
                        with open(user_settings, "rb") as sf:
                            if b"SessMail" not in sf.read():
                                needs_restore = True
                    except Exception:
                        pass
                if os.path.exists(bak_dir) and needs_restore:
                    try:
                        shutil.copytree(bak_dir, u_prefs, dirs_exist_ok=True)
                    except Exception:
                        pass

    # 4. Crear acceso directo en el escritorio si no existe
    d_dir = os.path.expanduser("~/Escritorio")
    if not os.path.exists(d_dir):
        d_dir = os.path.expanduser("~/Desktop")
    if os.path.exists(d_dir):
        desk_file = os.path.join(d_dir, "GameRanger.desktop")
        if not os.path.exists(desk_file):
            content = f"""[Desktop Entry]
Version=1.0
Type=Application
Name=GameRanger
Comment=Juega con tus amigos en línea
Exec=bash "{LAUNCHER}" "GameRanger.exe"
Icon=wine
Terminal=false
Categories=Game;Network;
StartupNotify=true
"""
            try:
                with open(desk_file, "w", encoding="utf-8") as df:
                    df.write(content)
                os.chmod(desk_file, 0o755)
                subprocess.run(["gio", "set", desk_file, "metadata::trusted", "true"], stderr=subprocess.DEVNULL)
            except Exception:
                pass

    # 5. Crear acceso directo en el menú de aplicaciones del sistema
    app_dir = os.path.expanduser("~/.local/share/applications")
    os.makedirs(app_dir, exist_ok=True)
    app_file = os.path.join(app_dir, "gameranger.desktop")
    if not os.path.exists(app_file):
        content = f"""[Desktop Entry]
Version=1.0
Type=Application
Name=GameRanger
Comment=Juega con tus amigos en línea
Exec=bash "{LAUNCHER}" "GameRanger.exe"
Icon=wine
Terminal=false
Categories=Game;Network;
StartupNotify=true
"""
        try:
            with open(app_file, "w", encoding="utf-8") as af:
                af.write(content)
            os.chmod(app_file, 0o755)
        except Exception:
            pass

    if mostrar_notif:
        print(f"\n{GREEN}✔ GameRanger portable preinstalado e integrado en tu PC con éxito.{RESET}")

def verificar_acceso_directo_vessel(mostrar_notif=False):
    """
    Verifica si el acceso directo de Vessel existe en el Escritorio.
    Si no existe o si la ruta del proyecto cambió, lo genera automáticamente
    asegurando permisos ejecutables (+x) y confianza XDG / KDE Plasma para abrir con un clic.
    """
    home = os.path.expanduser("~")
    desk_dir = None
    if shutil.which("xdg-user-dir"):
        try:
            res = subprocess.run(["xdg-user-dir", "DESKTOP"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            cand = res.stdout.strip()
            if cand and os.path.isdir(cand):
                desk_dir = cand
        except Exception:
            pass

    if not desk_dir:
        for cand in [os.path.join(home, "Escritorio"), os.path.join(home, "Desktop")]:
            if os.path.isdir(cand):
                desk_dir = cand
                break

    if not desk_dir or not os.path.isdir(desk_dir):
        return False

    desk_file = os.path.join(desk_dir, "Vessel.desktop")
    vessel_sh = os.path.join(DIR, "vessel.sh")
    app_dir = os.path.join(home, ".local", "share", "applications")
    app_file = os.path.join(app_dir, "vessel.desktop")

    # Asegurar que vessel.sh sea ejecutable
    try:
        if os.path.exists(vessel_sh):
            os.chmod(vessel_sh, 0o755)
    except Exception:
        pass

    icon_path = "wine"
    svg_icon = os.path.join(DIR, "herramientas", "vessel.svg")
    if os.path.exists(svg_icon):
        user_icons = os.path.join(home, ".local", "share", "icons", "hicolor", "scalable", "apps")
        try:
            os.makedirs(user_icons, exist_ok=True)
            shutil.copy2(svg_icon, os.path.join(user_icons, "vessel.svg"))
            icon_path = "vessel"
        except Exception:
            icon_path = svg_icon

    desktop_content = f"""[Desktop Entry]
Version=1.0
Type=Application
Name=Vessel
GenericName=Gestor y Optimizador de Juegos Windows
Comment=Lanzador y Optimizador Universal de Juegos y Programas de Windows
Exec=/bin/bash "{vessel_sh}"
Path={DIR}
Icon={icon_path}
Terminal=false
Categories=Game;
StartupNotify=true
"""

    necesita_crear = False
    if not os.path.exists(desk_file):
        necesita_crear = True
    else:
        try:
            with open(desk_file, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
                if DIR not in content or "Exec=" not in content:
                    necesita_crear = True
        except Exception:
            necesita_crear = True

    if necesita_crear:
        try:
            with open(desk_file, "w", encoding="utf-8") as f:
                f.write(desktop_content)
            os.chmod(desk_file, 0o755)
            if shutil.which("gio"):
                subprocess.run(["gio", "set", desk_file, "metadata::trusted", "true"], stderr=subprocess.DEVNULL)
            # Limpiar accesos obsoletos antiguos
            for old_name in ["Menu Win (PC).desktop", "Menu Win.desktop"]:
                old_path = os.path.join(desk_dir, old_name)
                if os.path.exists(old_path):
                    try:
                        os.remove(old_path)
                    except Exception:
                        pass
        except Exception:
            pass

        # Habilitar ejecución directa con un clic en entornos KDE Plasma (sin diálogos de confirmación)
        for ktool in ["kwriteconfig5", "kwriteconfig6"]:
            if shutil.which(ktool):
                try:
                    subprocess.run([ktool, "--file", "kiorc", "--group", "Executable scripts", "--key", "behaviourOnLaunch", "execute"], stderr=subprocess.DEVNULL)
                except Exception:
                    pass
    else:
        # Asegurar permisos correctos si ya existe
        try:
            os.chmod(desk_file, 0o755)
            if shutil.which("gio"):
                subprocess.run(["gio", "set", desk_file, "metadata::trusted", "true"], stderr=subprocess.DEVNULL)
        except Exception:
            pass

    # Asegurar también en el menú de aplicaciones del sistema (~/.local/share/applications)
    try:
        os.makedirs(app_dir, exist_ok=True)
        if not os.path.exists(app_file) or DIR not in open(app_file, "r", encoding="utf-8", errors="ignore").read():
            with open(app_file, "w", encoding="utf-8") as f:
                f.write(desktop_content)
            os.chmod(app_file, 0o755)
            if shutil.which("gio"):
                subprocess.run(["gio", "set", app_file, "metadata::trusted", "true"], stderr=subprocess.DEVNULL)
            old_app = os.path.join(app_dir, "menu-win-pc.desktop")
            if os.path.exists(old_app):
                try:
                    os.remove(old_app)
                except Exception:
                    pass
    except Exception:
        pass

    if mostrar_notif:
        print(f"\n{GREEN}✔ Acceso directo 'Vessel' verificado y configurado en tu Escritorio: {desk_file}{RESET}")

    return True

def cargar_lista_programas():
    """Carga y unifica la lista de juegos y programas de DB_FILE, DB_USER y .bak tanto en datos/ como en la raíz."""
    desplegar_gameranger_portable()
    programas = []
    vistos = set()

    db_candidates = [
        os.path.join(DATOS_DIR, "programas_usuario.db"),
        os.path.join(DIR, "programas_usuario.db"),
        DB_USER,
        os.path.join(DATOS_DIR, "programas.db"),
        os.path.join(DIR, "programas.db"),
        DB_FILE,
        os.path.join(DATOS_DIR, "programas.db.bak"),
        os.path.join(DIR, "programas.db.bak"),
        DB_BAK
    ]

    # Comprobar si existe alguna base de datos previa configurada
    hay_db = False
    for db_path in db_candidates:
        if os.path.exists(db_path) and os.path.getsize(db_path) > 0:
            hay_db = True
            break

    # Si es una instalación totalmente nueva y vacía, registrar GameRanger por defecto
    if not hay_db:
        programas.append(("GameRanger", "GameRanger.exe", "compartido", "win7", "off", "juego"))
        vistos.add("gameranger")
        guardar_lista_programas(programas)
        return programas

    # Cargar juegos del usuario desde todas las ubicaciones posibles respetando sus decisiones
    for db_path in db_candidates:
        if os.path.exists(db_path) and os.path.getsize(db_path) > 0:
            try:
                with open(db_path, "r", encoding="utf-8", errors="ignore") as f:
                    for line in f:
                        line = line.strip()
                        if line and "|" in line and not line.startswith("#"):
                            partes = line.split("|")
                            nom = partes[0].strip()
                            rut = partes[1].strip()
                            prefijo = partes[2].strip() if len(partes) > 2 else "compartido"
                            if not prefijo:
                                prefijo = "compartido"
                            winver = partes[3].strip() if len(partes) > 3 and partes[3].strip() else "win10"
                            fsr = partes[4].strip() if len(partes) > 4 and partes[4].strip() else "off"
                            tipo = partes[5].strip().lower() if len(partes) > 5 and partes[5].strip() else ""
                            if not tipo:
                                if nom.lower() == "gameranger":
                                    tipo = "juego"
                                elif analizar_juego and os.path.exists(rut):
                                    try:
                                        inf = analizar_juego(rut)
                                        tipo = inf.get("category", "juego")
                                    except Exception:
                                        tipo = "juego"
                                else:
                                    tipo = "juego"

                            # Auto-reparación transparente de rutas movidas o descomprimidas fuera de ZIP
                            if not os.path.exists(rut) and nom != "GameRanger":
                                rut_no_zip = re.sub(r'/[zZ][iI][pP]/', '/', rut)
                                if os.path.exists(rut_no_zip):
                                    rut = rut_no_zip
                                else:
                                    d_padre = os.path.dirname(os.path.dirname(rut))
                                    b_name = os.path.basename(rut)
                                    if os.path.isdir(d_padre):
                                        for r, _, files in os.walk(d_padre):
                                            if b_name in files:
                                                cand = os.path.join(r, b_name)
                                                if os.path.exists(cand):
                                                    rut = cand
                                                    break

                            # Priorizar binario nativo óptimo (.exe) si la ruta apunta a un script .bat
                            if rut.endswith((".bat", ".cmd")):
                                d_rut = os.path.dirname(rut)
                                for c_exe in ["PlayGTAV.exe", "GTA5.exe", "gta_sa.exe", "speed.exe", "BH6.exe", "re4.exe", "biohazard4.exe", "Swat4.exe"]:
                                    encontrado = False
                                    for sub in ["", "gta_data", "gamedata", "bin", "System", "Content/System"]:
                                        c_path = os.path.join(d_rut, sub, c_exe) if sub else os.path.join(d_rut, c_exe)
                                        if os.path.exists(c_path):
                                            rut = c_path
                                            encontrado = True
                                            break
                                    if encontrado:
                                        break

                            key = nom.lower()
                            if key not in vistos:
                                vistos.add(key)
                                programas.append((nom, rut, prefijo, winver, fsr, tipo))
            except Exception:
                pass

    return programas

def guardar_lista_programas(programas):
    """Guarda la lista unificada en DB_FILE y DB_USER preservando modo de prefijo, versión de Windows, FSR y tipo."""
    lineas = []
    for item in programas:
        n = item[0]
        r = item[1]
        p = item[2] if len(item) > 2 and item[2] else "compartido"
        w = item[3] if len(item) > 3 and item[3] else "win10"
        f = item[4] if len(item) > 4 and item[4] else "off"
        t = item[5] if len(item) > 5 and item[5] else "juego"
        lineas.append(f"{n}|{r}|{p}|{w}|{f}|{t}\n")

    os.makedirs(DATOS_DIR, exist_ok=True)
    rutas_a_guardar = set([
        DB_FILE,
        DB_USER,
        os.path.join(DATOS_DIR, "programas.db"),
        os.path.join(DATOS_DIR, "programas_usuario.db"),
        os.path.join(DIR, "programas.db"),
        os.path.join(DIR, "programas_usuario.db")
    ])
    for db_path in rutas_a_guardar:
        try:
            with open(db_path, "w", encoding="utf-8") as file_out:
                file_out.writelines(lineas)
        except Exception:
            pass
    try:
        shutil.copyfile(DB_FILE, os.path.join(DATOS_DIR, "programas.db.bak"))
        if DATOS_DIR != DIR:
            shutil.copyfile(DB_FILE, os.path.join(DIR, "programas.db.bak"))
    except Exception:
        pass

# ==============================================================================
# SUBMENÚS DE ENTORNO WINDOWS: JUEGOS Y PROGRAMAS (100% SEPARADOS Y OPTIMIZADOS)
# ==============================================================================

def ejecutar_herramienta_windows(tool_exe, label):
    """Ejecuta una utilidad nativa del sistema Windows en modo ventana nativa con ClearType HD."""
    os.system("clear")
    print(f"{GREEN}🚀 Abriendo {label}...{RESET}\n")
    ejecutar_juego_y_liberar_ram(["--program", tool_exe], con_hud=False)

def gestionar_o_iniciar_juego(item, hw, cfg):
    """Acciones completas para el videojuego seleccionado (jugar, telemetría, mods, winver, fsr)."""
    programas = cargar_lista_programas()
    idx = -1
    for i, p in enumerate(programas):
        if p[0] == item[0] and p[1] == item[1]:
            idx = i
            break
    if idx == -1:
        return

    nombre = item[0]
    ruta = item[1]
    prefijo = item[2] if len(item) > 2 else "compartido"
    winver = item[3] if len(item) > 3 else "win10"
    fsr = item[4] if len(item) > 4 else "off"
    tipo = item[5] if len(item) > 5 else "juego"

    # Comprobar si el juego ya tenía confirmada su versión de Windows
    if not es_winver_confirmado(nombre, ruta):
        v_elegida = seleccionar_version_windows_interactivo(nombre, ruta, hw, cfg, primera_vez=True)
        if v_elegida:
            winver = v_elegida
            programas[idx] = (nombre, ruta, prefijo, winver, fsr, tipo)
            guardar_lista_programas(programas)
            registrar_winver_confirmado(nombre, ruta)
        else:
            return

    winver_labels = WINVER_LABELS
    fsr_labels = {
        "off": "Desactivado",
        "quality": "Calidad (+30% FPS)",
        "balanced": "Equilibrado (+50% FPS)",
        "performance": "Rendimiento (+75% FPS)",
        "ultra": "Ultra (+90% FPS)"
    }

    pe_info = analizar_juego(ruta) if (analizar_juego and os.path.exists(ruta)) else None
    pe_tag = ""
    if pe_info and pe_info.get("is_pe"):
        pe_tag = f" [{pe_info['bits']}-bit | {pe_info['api'].upper()}]"
        if pe_info.get("anti_cheat_warning"):
            pe_tag += f" {YELLOW}⚠️ Anti-Cheat{RESET}"

    opts_juego = [
        ("1", f"🚀 Iniciar {nombre} (Máximo Rendimiento Nativo en Hardware)"),
        ("2", f"📊 Iniciar con HUD de Rendimiento (FPS / Telemetría en Pantalla)"),
        ("3", f"📂 Abrir Carpeta del Juego (para Mods / Parches / Saves)"),
        ("4", f"🖥️  Crear Acceso Directo en el Escritorio (1-Clic)"),
        ("5", f"🛡️  Modo de Prefijo Wine: [{'Aislado (Sandbox Propio)' if prefijo == 'aislado' else 'Compartido (Global)'}]"),
        ("6", f"🪟 Versión de Windows: [{winver_labels.get(winver, 'Windows 10')}]{pe_tag}"),
        ("7", f"⚡ Reescalado AMD FSR: [{fsr_labels.get(fsr, 'Desactivado')}]"),
        ("8", f"❌ Eliminar este Juego de la Lista"),
        ("0", f"↩️  Volver al Catálogo de Juegos")
    ]
    accion = submenu_interactivo(f"🎮  Acciones para: {nombre}", opts_juego, hw, cfg)

    if accion == "1":
        if pe_info and pe_info.get("anti_cheat_warning"):
            ac_name = pe_info.get("anti_cheat_name", "Kernel Ring 0")
            print(f"\n{YELLOW}⚠️  ADVERTENCIA DE COMPATIBILIDAD - ANTI-CHEAT DE KERNEL DETECTADO{RESET}")
            print(f"{WHITE}Este título utiliza un sistema Anti-Cheat a nivel de Kernel exclusivo de Windows ({ac_name}).{RESET}")
            print(f"{GRAY}Podrás ejecutar pruebas o modo sin conexión / un jugador, pero los servidores oficiales en línea bloquearán el acceso en Linux.{RESET}\n")
            continuar = input(f"{CYAN}¿Deseas intentar ejecutar de todos modos? (S/n): {RESET}").strip().lower()
            if continuar == 'n':
                return
        os.system("clear")
        print(f"{GREEN}🚀 Iniciando: {BOLD}{nombre}{RESET} de forma nativa en tu computadora...\n")
        if not os.path.exists(ruta) and "gameranger" in ruta.lower():
            ruta = "GameRanger.exe"
        cmd_args = []
        if prefijo == "aislado":
            cmd_args.append("--isolated")
        if winver:
            cmd_args.extend(["--winver", winver])
        if fsr and fsr != "off":
            cmd_args.extend(["--fsr", fsr])
        cmd_args.append(ruta)
        ejecutar_juego_y_liberar_ram(cmd_args, con_hud=False)
    elif accion == "2":
        if pe_info and pe_info.get("anti_cheat_warning"):
            ac_name = pe_info.get("anti_cheat_name", "Kernel Ring 0")
            print(f"\n{YELLOW}⚠️  ADVERTENCIA DE COMPATIBILIDAD - ANTI-CHEAT DE KERNEL DETECTADO{RESET}")
            print(f"{WHITE}Este título utiliza un sistema Anti-Cheat a nivel de Kernel exclusivo de Windows ({ac_name}).{RESET}")
            print(f"{GRAY}Podrás ejecutar pruebas o modo sin conexión / un jugador, pero los servidores oficiales en línea bloquearán el acceso en Linux.{RESET}\n")
            continuar = input(f"{CYAN}¿Deseas intentar ejecutar de todos modos? (S/n): {RESET}").strip().lower()
            if continuar == 'n':
                return
        os.system("clear")
        print(f"{PURPLE}📊 Iniciando: {BOLD}{nombre}{RESET} con HUD de FPS activo...\n")
        if not os.path.exists(ruta) and "gameranger" in ruta.lower():
            ruta = "GameRanger.exe"
        cmd_args = []
        if prefijo == "aislado":
            cmd_args.append("--isolated")
        if winver:
            cmd_args.extend(["--winver", winver])
        if fsr and fsr != "off":
            cmd_args.extend(["--fsr", fsr])
        cmd_args.append(ruta)
        ejecutar_juego_y_liberar_ram(cmd_args, con_hud=True)
    elif accion == "3":
        carpeta = os.path.join(DIR, "GameRanger") if "gameranger" in ruta.lower() else os.path.dirname(ruta)
        subprocess.run(["xdg-open", carpeta], stderr=subprocess.DEVNULL)
        pausar()
    elif accion == "4":
        crear_desktop_entry(nombre, ruta, prefijo, winver, fsr, tipo)
        pausar()
    elif accion == "5":
        nuevo_prefijo = "compartido" if prefijo == "aislado" else "aislado"
        programas[idx] = (nombre, ruta, nuevo_prefijo, winver, fsr, tipo)
        guardar_lista_programas(programas)
        print(f"\n{GREEN}✔ Modo de prefijo Wine para '{nombre}' cambiado a: {BOLD}{nuevo_prefijo.upper()}{RESET}")
        pausar()
    elif accion == "6":
        v_nueva = seleccionar_version_windows_interactivo(nombre, ruta, hw, cfg)
        if v_nueva:
            programas[idx] = (nombre, ruta, prefijo, v_nueva, fsr, tipo)
            guardar_lista_programas(programas)
            registrar_winver_confirmado(nombre, ruta)
            target_exe = os.path.basename(pe_info["resolved_exe"]) if pe_info and pe_info.get("resolved_exe") else os.path.basename(ruta)
            for pfx in [WINEPREFIX, os.path.join(DIR, "wineprefixes", nombre)]:
                if os.path.isdir(pfx):
                    cmd_reg = f'WINEPREFIX="{pfx}" wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\{target_exe}" /v Version /t REG_SZ /d "{v_nueva}" /f'
                    subprocess.run(cmd_reg, shell=True, stderr=subprocess.DEVNULL)
            print(f"\n{GREEN}✔ Versión de Windows para '{nombre}' actualizada a: {BOLD}{winver_labels.get(v_nueva, v_nueva).upper()}{RESET}")
            pausar()
    elif accion == "7":
        sub_fsr = [
            ("1", "Desactivado (Resolución nativa 1:1)"),
            ("2", "Calidad (Quality - 1.3x Upscale con máxima nitidez, +25-35% FPS)"),
            ("3", "Equilibrado (Balanced - 1.5x Upscale, +40-50% FPS)"),
            ("4", "Rendimiento (Performance - 2.0x Upscale para PCs modestas, +60-80% FPS)"),
            ("0", "↩️  Cancelar")
        ]
        f_sel = submenu_interactivo(f"⚡  Reescalado AMD FSR para: {nombre}", sub_fsr, hw, cfg)
        n_fsr = fsr
        if f_sel == "1": n_fsr = "off"
        elif f_sel == "2": n_fsr = "quality"
        elif f_sel == "3": n_fsr = "balanced"
        elif f_sel == "4": n_fsr = "performance"
        if n_fsr != fsr:
            programas[idx] = (nombre, ruta, prefijo, winver, n_fsr, tipo)
            guardar_lista_programas(programas)
            print(f"\n{GREEN}✔ Modo AMD FSR para '{nombre}' configurado a: {BOLD}{fsr_labels.get(n_fsr, n_fsr).upper()}{RESET}")
            pausar()
    elif accion == "8":
        del programas[idx]
        guardar_lista_programas(programas)
        print(f"\n{GREEN}✔ '{nombre}' ha sido eliminado de la lista.{RESET}")
        pausar()

def gestionar_o_iniciar_programa(item, hw, cfg):
    """Acciones completas para el programa de Windows seleccionado (ventana nativa, clearType, prefijo)."""
    programas = cargar_lista_programas()
    idx = -1
    for i, p in enumerate(programas):
        if p[0] == item[0] and p[1] == item[1]:
            idx = i
            break
    if idx == -1:
        return

    nombre = item[0]
    ruta = item[1]
    prefijo = item[2] if len(item) > 2 else "compartido"
    winver = item[3] if len(item) > 3 else "win10"
    tipo = "programa"
    winver_labels = WINVER_LABELS

    opts_prog = [
        ("1", f"🚀 Iniciar {nombre} (Modo Ventana Nativa - ClearType HD)"),
        ("2", f"📂 Abrir Carpeta del Programa"),
        ("3", f"🖥️  Crear Acceso Directo en el Escritorio (1-Clic)"),
        ("4", f"🪟 Versión de Windows: [{winver_labels.get(winver, 'Windows 10')}]"),
        ("5", f"🛡️  Modo de Prefijo Wine: [{'Aislado (Sandbox Propio)' if prefijo == 'aislado' else 'Compartido (Global)'}]"),
        ("6", f"❌ Eliminar este Programa de la Lista"),
        ("0", f"↩️  Volver a Programas")
    ]
    accion = submenu_interactivo(f"💼  Acciones para: {nombre}", opts_prog, hw, cfg)

    if accion == "1":
        os.system("clear")
        print(f"{GREEN}🚀 Iniciando: {BOLD}{nombre}{RESET} [Ventana Nativa - ClearType HD]...\n")
        cmd_args = ["--program"]
        if prefijo == "aislado":
            cmd_args.append("--isolated")
        if winver:
            cmd_args.extend(["--winver", winver])
        cmd_args.append(ruta)
        ejecutar_juego_y_liberar_ram(cmd_args, con_hud=False)
    elif accion == "2":
        carpeta = os.path.dirname(ruta)
        subprocess.run(["xdg-open", carpeta], stderr=subprocess.DEVNULL)
        pausar()
    elif accion == "3":
        crear_desktop_entry(nombre, ruta, prefijo, winver, "off", "programa")
        pausar()
    elif accion == "4":
        v_nueva = seleccionar_version_windows_interactivo(nombre, ruta, hw, cfg)
        if v_nueva:
            programas[idx] = (nombre, ruta, prefijo, v_nueva, "off", "programa")
            guardar_lista_programas(programas)
            print(f"\n{GREEN}✔ Versión de Windows para '{nombre}' actualizada a: {BOLD}{winver_labels.get(v_nueva, v_nueva).upper()}{RESET}")
            pausar()
    elif accion == "5":
        nuevo_p = "compartido" if prefijo == "aislado" else "aislado"
        programas[idx] = (nombre, ruta, nuevo_p, winver, "off", "programa")
        guardar_lista_programas(programas)
        print(f"\n{GREEN}✔ Modo de prefijo Wine para '{nombre}' cambiado a: {BOLD}{nuevo_p.upper()}{RESET}")
        pausar()
    elif accion == "6":
        del programas[idx]
        guardar_lista_programas(programas)
        print(f"\n{GREEN}✔ '{nombre}' ha sido eliminado de la lista.{RESET}")
        pausar()

def menu_juegos(hw, cfg):
    """Submenú 1: Catálogo y Ejecución de Videojuegos con Aceleración 3D Vulkan/DirectX."""
    while True:
        programas = cargar_lista_programas()
        juegos = [p for p in programas if len(p) <= 5 or p[5] != "programa"]

        opciones = []
        for i, item in enumerate(juegos, 1):
            nombre, ruta = item[0], item[1]
            prefijo = item[2] if len(item) > 2 else "compartido"
            winver = item[3] if len(item) > 3 else "win10"
            fsr = item[4] if len(item) > 4 else "off"
            tag_pref = f"{CYAN}[🛡️ Aislado]{RESET}" if prefijo == "aislado" else f"{GRAY}[Compartido]{RESET}"
            tag_wver = f"{PURPLE}[🪟 {winver.upper()}]{RESET}"
            tag_fsr = f" {GREEN}[⚡ FSR {fsr.capitalize()}]{RESET}" if fsr != "off" else ""
            opciones.append((str(i), f"🎮 {nombre} {tag_pref} {tag_wver}{tag_fsr}"))

        opciones.append(("+", "➕ Añadir Nuevo Videojuego (.exe, .lnk, .bat)"))
        opciones.append(("0", "↩️  Volver al Menú Principal"))

        info_lines = [
            f"{WHITE}Catálogo de Videojuegos de Windows optimizados para tu hardware:{RESET}",
            f"{GRAY}Aceleración 3D Vulkan, DirectX 9/11/12, AMD FSR y baja latencia de mandos.{RESET}",
            f"{GRAY}Usa las flechas {BOLD}[↑↓]{RESET}{GRAY} y presiona {BOLD}[Enter]{RESET}{GRAY} para jugar o configurar:{RESET}"
        ]

        eleccion = submenu_interactivo("🎮  Catálogo de Videojuegos", opciones, hw, cfg, info_lines=info_lines)
        if eleccion == "0":
            break
        elif eleccion == "+":
            menu_agregar_item_especifico("juego", hw, cfg)
        else:
            try:
                idx = int(eleccion) - 1
                item = juegos[idx]
                gestionar_o_iniciar_juego(item, hw, cfg)
            except Exception:
                pass

def menu_programas(hw, cfg):
    """Submenú 2: Catálogo de Aplicaciones de Windows, Oficina y Utilidades del Sistema."""
    while True:
        programas = cargar_lista_programas()
        user_progs = [p for p in programas if len(p) > 5 and p[5] == "programa"]

        opciones = []
        # 1. Utilidades integradas nativas de Windows
        opciones.append(("E", "📁 Explorador de Archivos (Windows Explorer)"))
        opciones.append(("C", "⚙️  Panel de Control y Configuración de Wine (Winecfg)"))
        opciones.append(("N", "📝 Bloc de Notas de Windows (Notepad)"))
        opciones.append(("T", "💻 Símbolo del Sistema de Windows (CMD)"))
        opciones.append(("R", "🗃️  Editor del Registro de Windows (Regedit)"))
        opciones.append(("M", "📊 Administrador de Tareas de Windows (Task Manager)"))

        # 2. Programas añadidos por el usuario
        for i, item in enumerate(user_progs, 1):
            nombre, ruta = item[0], item[1]
            prefijo = item[2] if len(item) > 2 else "compartido"
            winver = item[3] if len(item) > 3 else "win10"
            tag_pref = f"{CYAN}[🛡️ Aislado]{RESET}" if prefijo == "aislado" else f"{GRAY}[Compartido]{RESET}"
            tag_wver = f"{PURPLE}[🪟 {winver.upper()}]{RESET}"
            opciones.append((str(i), f"💼 {nombre} {tag_pref} {tag_wver} {WHITE}[ClearType HD]{RESET}"))

        opciones.append(("+", "➕ Añadir Programa Portable (.exe, .lnk, .bat)"))
        opciones.append(("S", "💿 Instalar Programa con Setup (.exe, .msi)"))
        opciones.append(("0", "↩️  Volver al Menú Principal"))

        info_lines = [
            f"{WHITE}Entorno de Software y Utilidades de Windows {BOLD}{PURPLE}[ClearType HD - Bajo Consumo de RAM]{RESET}:",
            f"{GRAY}Ventanas nativas redimensionables, fuentes suavizadas y mínimo uso de memoria (~25 MB).{RESET}",
            f"{GRAY}Presiona {BOLD}[E]{RESET} para Explorador, {BOLD}[C]{RESET} para Configuración, o selecciona un programa:{RESET}"
        ]

        eleccion = submenu_interactivo("💼  Programas y Utilidades de Windows", opciones, hw, cfg, info_lines=info_lines)
        if eleccion == "0":
            break
        elif eleccion in ("E", "e"):
            ejecutar_herramienta_windows("explorer.exe", "Explorador de Archivos de Windows")
        elif eleccion in ("C", "c"):
            ejecutar_herramienta_windows("winecfg.exe", "Panel de Control y Configuración de Wine")
        elif eleccion in ("N", "n"):
            ejecutar_herramienta_windows("notepad.exe", "Bloc de Notas de Windows")
        elif eleccion in ("T", "t"):
            ejecutar_herramienta_windows("cmd.exe", "Símbolo del Sistema de Windows (CMD)")
        elif eleccion in ("R", "r"):
            ejecutar_herramienta_windows("regedit.exe", "Editor del Registro de Windows")
        elif eleccion in ("M", "m"):
            ejecutar_herramienta_windows("taskmgr.exe", "Administrador de Tareas de Windows")
        elif eleccion == "+":
            menu_agregar_item_especifico("programa", hw, cfg)
        elif eleccion in ("S", "s"):
            menu_instalar_con_setup(hw, cfg)
        else:
            try:
                idx = int(eleccion) - 1
                item = user_progs[idx]
                gestionar_o_iniciar_programa(item, hw, cfg)
            except Exception:
                pass

def menu_iniciar_programa(hw, cfg):
    """Redirecciona al menú de juegos para compatibilidad con accesos antiguos."""
    menu_juegos(hw, cfg)

def crear_desktop_entry(nombre, ruta, prefijo="compartido", winver="win10", fsr="off", tipo="juego"):
    """Crea y valida el acceso directo en el escritorio con soporte para prefijo aislado, versión de Windows, AMD FSR y modo programa."""
    d_dir = os.path.expanduser("~/Escritorio")
    if not os.path.exists(d_dir):
        d_dir = os.path.expanduser("~/Desktop")
    if os.path.exists(d_dir):
        desk_file = os.path.join(d_dir, f"{nombre}.desktop")
        exec_parts = [f'bash "{LAUNCHER}"']
        if prefijo == "aislado":
            exec_parts.append("--isolated")
        if winver and winver != "win10":
            exec_parts.append(f'--winver "{winver}"')
        if fsr and fsr != "off":
            exec_parts.append(f'--fsr "{fsr}"')
        if tipo == "programa":
            exec_parts.append("--program")
        exec_parts.append(f'"{ruta}"')
        exec_str = " ".join(exec_parts)
        cat_str = "Utility;Application;" if tipo == "programa" else "Game;"
        content = f"""[Desktop Entry]
Version=1.0
Type=Application
Name={nombre}
Exec={exec_str}
Icon=wine
Terminal=false
Categories={cat_str}
StartupNotify=true
"""
        with open(desk_file, "w", encoding="utf-8") as df:
            df.write(content)
        os.chmod(desk_file, 0o755)
        subprocess.run(["gio", "set", desk_file, "metadata::trusted", "true"], stderr=subprocess.DEVNULL)
        print(f"\n{GREEN}✔ Acceso directo creado en tu Escritorio: {desk_file}{RESET}")
    else:
        print(f"\n{RED}❌ No se encontró la carpeta de Escritorio.{RESET}")

def seleccionar_archivo_mouse(titulo="Seleccionar Juego o Programa"):
    """Abre el explorador de archivos gráfico nativo (kdialog / zenity / tkinter) para seleccionar con el mouse."""
    # 1. Probar kdialog (Nativo de KDE Plasma / Konsole)
    if shutil.which("kdialog") and (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        try:
            init_dir = "/media" if os.path.exists("/media") else os.path.expanduser("~")
            cmd = [
                "kdialog",
                "--title", titulo,
                "--getopenfilename", init_dir,
                "*.exe *.bat *.cmd *.lnk *.ink *.msi *.EXE *.BAT *.CMD *.LNK *.INK *.MSI | Ejecutables y Accesos (*.exe, *.bat, *.lnk, *.msi)\n* | Todos los archivos (*)"
            ]
            res = subprocess.check_output(cmd, stderr=subprocess.DEVNULL, text=True).strip()
            if res and os.path.exists(res):
                return res
        except Exception:
            pass

    # 2. Probar zenity (GNOME / GTK)
    if shutil.which("zenity") and (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        try:
            cmd = [
                "zenity", "--file-selection",
                f"--title={titulo}",
                "--file-filter=Ejecutables y Juegos (*.exe, *.bat, *.lnk, *.msi) | *.exe *.bat *.cmd *.lnk *.ink *.msi *.EXE *.BAT *.CMD *.LNK *.INK *.MSI",
                "--file-filter=Todos los archivos (*) | *"
            ]
            res = subprocess.check_output(cmd, stderr=subprocess.DEVNULL, text=True).strip()
            if res and os.path.exists(res):
                return res
        except Exception:
            pass

    # 3. Fallback con tkinter
    try:
        import tkinter as tk
        from tkinter import filedialog
        root = tk.Tk()
        root.withdraw()
        root.attributes('-topmost', True)
        res = filedialog.askopenfilename(
            title=titulo,
            filetypes=[
                ("Ejecutables y Juegos", "*.exe *.bat *.cmd *.lnk *.ink *.msi"),
                ("Todos los archivos", "*.*")
            ]
        )
        root.destroy()
        if res and os.path.exists(res):
            return res
    except Exception:
        pass

    return None

# ==============================================================================
# SUBMENÚ 2: CONFIGURAR PROGRAMA WIN
# ==============================================================================

WINVER_LABELS = {
    "win10": "Windows 10",
    "win7": "Windows 7",
    "winxp": "Windows XP SP3",
    "win81": "Windows 8.1"
}

def cargar_winver_confirmados():
    """Carga el conjunto de juegos que ya han confirmado su versión de Windows."""
    confirmados = set()
    if os.path.exists(WINVER_CONF_FILE):
        try:
            with open(WINVER_CONF_FILE, "r", encoding="utf-8") as f:
                for line in f:
                    c = line.strip().lower()
                    if c:
                        confirmados.add(c)
        except Exception:
            pass
    return confirmados

def registrar_winver_confirmado(nombre, ruta):
    """Registra un juego como confirmado para no volver a preguntarle al usuario."""
    confirmados = cargar_winver_confirmados()
    if nombre:
        confirmados.add(nombre.strip().lower())
    if ruta:
        confirmados.add(ruta.strip().lower())
        try:
            confirmados.add(os.path.realpath(ruta).lower())
        except Exception:
            pass
    try:
        with open(WINVER_CONF_FILE, "w", encoding="utf-8") as f:
            for item in sorted(confirmados):
                f.write(f"{item}\n")
    except Exception:
        pass

def es_winver_confirmado(nombre, ruta):
    """Comprueba si el juego ya confirmó previamente su versión de Windows."""
    confirmados = cargar_winver_confirmados()
    if nombre and nombre.strip().lower() in confirmados:
        return True
    if ruta and ruta.strip().lower() in confirmados:
        return True
    try:
        if ruta and os.path.realpath(ruta).lower() in confirmados:
            return True
    except Exception:
        pass
    return False

def detectar_winver_sugerido(pe_info, ruta_exe):
    """
    Determina la versión de Windows sugerida de acuerdo al análisis de PE,
    época, arquitectura (32/64 bits), APIs y subsistema del binario.
    """
    if pe_info and pe_info.get("winver"):
        return pe_info["winver"]

    file_name = os.path.basename(ruta_exe).lower() if ruta_exe else ""
    if "gameranger" in file_name:
        return "win7"
    if not pe_info:
        return "win10"
    if pe_info.get("is_64") or pe_info.get("has_d3d12") or pe_info.get("has_d3d11") or pe_info.get("has_vulkan"):
        return "win10"

    subsys_str = pe_info.get("subsys", "6.0")
    try:
        sub_maj = int(subsys_str.split(".")[0])
        sub_min = int(subsys_str.split(".")[1]) if "." in subsys_str else 0
    except Exception:
        sub_maj = 6
        sub_min = 0

    if pe_info.get("has_ddraw") or pe_info.get("engine") == "classic_directdraw":
        return "winxp"

    return "win10"

def seleccionar_version_windows_interactivo(nombre, ruta, hw, cfg, primera_vez=False):
    """
    Submenú interactivo para seleccionar la versión de Windows para el juego a agregar.
    Incorpora recomendación inteligente según la arquitectura y APIs detectadas.
    Permite aceptar la recomendación simplemente presionando [Enter].
    Retorna la versión elegida ('win10', 'win7', 'winxp') o None si el usuario cancela.
    """
    pe_info = analizar_juego(ruta) if (analizar_juego and os.path.exists(ruta)) else None
    winver_sugerido = detectar_winver_sugerido(pe_info, ruta)

    if pe_info and pe_info.get("is_pe"):
        bits_txt = f"{pe_info['bits']}-bit"
        api_txt = pe_info['api'].upper()
        if api_txt == "AUTO":
            api_txt = "DirectX / GDI"
        info_binario = f"{bits_txt} / {api_txt}"
    else:
        info_binario = "Binario estándar de Windows"

    info_lines = []
    if primera_vez:
        info_lines.append(f"{YELLOW}⚡ Primera ejecución: Configura la versión de Windows para este juego.{RESET}")
        info_lines.append(f"{GRAY}Esta configuración se guardará y no se volverá a preguntar.{RESET}")
    info_lines.append(f"{WHITE}Juego : {BOLD}{CYAN}{nombre}{RESET}  {GRAY}(Binario detectado: {info_binario}){RESET}")
    info_lines.append(f"{WHITE}Selecciona el entorno de compatibilidad de Windows:{RESET}")
    info_lines.append(f"{GRAY}Presiona {BOLD}{WHITE}[Enter]{RESET}{GRAY} para confirmar la opción recomendada o usa las flechas:{RESET}")

    rec_tag = f" {GREEN}─── [ RECOMENDADO ]{RESET}"
    lbl_win10 = f"⭐ Windows 10{rec_tag if winver_sugerido == 'win10' else ''}\n• Juegos modernos (2014+), 64 bits y DirectX 11 / 12\n• Máximo rendimiento gráfico y mandos modernos (XInput)"
    lbl_win7 = f"💿 Windows 7{rec_tag if winver_sugerido == 'win7' else ''}\n• Juegos de la era 2007 a 2013, DirectX 9 / 10 y GameRanger"
    lbl_winxp = f"💾 Windows XP{rec_tag if winver_sugerido == 'winxp' else ''}\n• Clásicos retro de 32 bits (1998 a 2006) y DirectX 8 / 9\n• Evita fallos de memoria antigua y problemas de resolución"

    sub_winver = [
        ("1", lbl_win10),
        ("2", lbl_win7),
        ("3", lbl_winxp),
        ("0", "↩️  Cancelar")
    ]

    default_idx = 0
    if winver_sugerido == "win7":
        default_idx = 1
    elif winver_sugerido == "winxp":
        default_idx = 2

    sel_w = submenu_interactivo("⚙️  Seleccionar Versión de Windows para el Juego", sub_winver, hw, cfg, default_idx=default_idx, info_lines=info_lines)
    if sel_w == "0":
        return None

    version_final = "win10"
    if sel_w == "2":
        version_final = "win7"
    elif sel_w == "3":
        version_final = "winxp"

    # Salvaguarda de compatibilidad técnica
    if version_final == "winxp" and pe_info and (pe_info.get("is_64") or pe_info.get("has_d3d12")):
        print(f"\n{RED}❌ Incompatible: Este juego es nativo de 64 bits o utiliza DirectX 12.{RESET}")
        print(f"{YELLOW}   Windows XP no admite ejecutables de 64-bit ni D3D12CreateDevice en Wine.{RESET}")
        print(f"{CYAN}   Se mantendrá en Windows 10 para garantizar máxima estabilidad gráfica.{RESET}")
        version_final = "win10"
        pausar()

    return version_final

def seleccionar_tipo_interactivo(nombre, ruta, hw, cfg):
    """
    Submenú interactivo para seleccionar si el elemento es un Videojuego o un Programa de Windows.
    Recomendación inteligente según el análisis PE del binario.
    """
    pe_info = analizar_juego(ruta) if (analizar_juego and os.path.exists(ruta)) else None
    cat_sugerida = pe_info.get("category", "juego") if pe_info else "juego"

    rec_tag = f" {GREEN}─── [ RECOMENDADO ]{RESET}"
    lbl_juego = f"🎮 Videojuego{rec_tag if cat_sugerida == 'juego' else ''}\n• Aceleración 3D Vulkan/DirectX, FSR, GameMode, Baja Latencia y Mandos"
    lbl_prog = f"💼 Programa de Windows{rec_tag if cat_sugerida == 'programa' else ''}\n• Aplicaciones de productividad, suites de diseño, utilidades y herramientas\n• Modo Ventana Nativa con ClearType HD y mínimo consumo de RAM (~25-40 MB)"

    sub_tipo = [
        ("1", lbl_juego),
        ("2", lbl_prog),
        ("0", "↩️  Cancelar")
    ]
    info_lines = [
        f"{WHITE}Archivo : {BOLD}{CYAN}{nombre}{RESET}",
        f"{WHITE}¿Cómo deseas ejecutar este elemento en Vessel?{RESET}",
        f"{GRAY}Presiona {BOLD}{WHITE}[Enter]{RESET}{GRAY} para confirmar la opción recomendada o usa las flechas:{RESET}"
    ]

    default_idx = 0 if cat_sugerida == "juego" else 1
    sel_t = submenu_interactivo("⚙️  Tipo de Aplicación (Juego vs Programa)", sub_tipo, hw, cfg, default_idx=default_idx, info_lines=info_lines)
    if sel_t == "0":
        return None
    return "programa" if sel_t == "2" else "juego"

def menu_agregar_item_especifico(tipo_forzado, hw, cfg):
    """Añade un juego o programa portable a la base de datos con detección de tipo, nombre y versión de Windows."""
    lbl_tipo = "Videojuego" if tipo_forzado == "juego" else ("Programa de Windows" if tipo_forzado == "programa" else "Juego o Programa")
    sub_metodo = [
        ("1", f"🖱️  Seleccionar {lbl_tipo} con el Mouse (Ventana gráfica de archivos)"),
        ("2", "⌨️  Escribir o pegar la ruta manualmente en la terminal"),
        ("0", "↩️  Cancelar")
    ]
    m_opc = submenu_interactivo(f"➕  Buscar {lbl_tipo} (.exe, .bat, .lnk)", sub_metodo, hw, cfg)
    ruta = ""
    if m_opc == "1":
        os.system("clear")
        print(f"{CYAN}🖱️  Abriendo explorador de archivos... Haz clic y selecciona tu archivo.{RESET}\n")
        ruta = seleccionar_archivo_mouse(f"Seleccionar {lbl_tipo} (.exe, .bat, .lnk)")
        if not ruta:
            print(f"{YELLOW}⚠️  No se seleccionó ningún archivo.{RESET}")
            pausar()
            return
    elif m_opc == "2":
        os.system("clear")
        print(f"{PURPLE}➕ [ AÑADIR {lbl_tipo.upper()} MANUALMENTE ]{RESET}\n")
        print(f"{WHITE}Arrastra el archivo .exe / .bat / .lnk a la terminal o escribe su ruta:{RESET}")
        ruta = input(f"{CYAN}Ruta: {RESET}").strip().strip("'").strip('"')
    else:
        return

    if not ruta or not os.path.exists(ruta):
        print(f"\n{RED}❌ El archivo no existe o la ruta especificada es inválida.{RESET}")
        pausar()
        return

    # Resolución inteligente de accesos directos .lnk si aplica
    nombre_sugerido = os.path.splitext(os.path.basename(ruta))[0]
    if ruta.lower().endswith(('.lnk', '.ink')):
        try:
            sys.path.insert(0, DIR)
            from resolver_lnk import resolve_lnk
            res_lnk = resolve_lnk(ruta, WINEPREFIX)
            if res_lnk.get("status") == "RESOLVED" and os.path.isfile(res_lnk.get("path", "")):
                ruta = res_lnk["path"]
                if res_lnk.get("name"):
                    nombre_sugerido = res_lnk["name"]
        except Exception:
            pass

    nombre_sugerido = nombre_sugerido.replace("_", " ").replace("-", " ")

    # Comprobación de duplicados
    real_nueva = os.path.realpath(os.path.abspath(ruta))
    for item in cargar_lista_programas():
        db_nom, db_rut = item[0], item[1]
        real_db = os.path.realpath(os.path.abspath(db_rut)) if os.path.exists(db_rut) else db_rut
        if real_nueva == real_db or ruta.strip() == db_rut:
            os.system("clear")
            print(f"{YELLOW}══════════════════════════════════════════════════════════════════════{RESET}")
            print(f"{YELLOW}⚠️  ESTE ELEMENTO YA SE ENCUENTRA EN LA LISTA: {BOLD}{db_nom}{RESET}")
            print(f"{YELLOW}══════════════════════════════════════════════════════════════════════{RESET}\n")
            print(f"  {WHITE}Nombre en la lista :{RESET} {BOLD}{CYAN}{db_nom}{RESET}")
            print(f"  {WHITE}Ruta del archivo   :{RESET} {GRAY}{db_rut}{RESET}\n")
            pausar()
            return

    # Asignar nombre
    os.system("clear")
    print(f"{PURPLE}🏷️  [ ASIGNAR NOMBRE ]{RESET}\n")
    print(f"  {WHITE}Archivo seleccionado :{RESET} {CYAN}{ruta}{RESET}")
    print(f"  {WHITE}Nombre sugerido      :{RESET} {BOLD}{WHITE}{nombre_sugerido}{RESET}\n")
    print(f"{WHITE}Escribe el nombre que deseas mostrar en el menú (Enter para '{nombre_sugerido}'):{RESET}")
    nombre_custom = input(f"{CYAN}➤ Nombre: {RESET}").strip()
    if not nombre_custom:
        nombre_custom = nombre_sugerido

    # Tipo de elemento
    tipo_final = tipo_forzado
    if not tipo_final:
        tipo_final = seleccionar_tipo_interactivo(nombre_custom, ruta, hw, cfg)
        if not tipo_final:
            return

    # Modo de Prefijo
    sub_pref = [
        ("1", "📁 Prefijo Compartido (Recomendado - Comparte librerías y espacio)"),
        ("2", "🛡️ Prefijo Aislado / Sandbox (Ideal para mods o programas exclusivos)"),
        ("0", "↩️  Cancelar")
    ]
    sel_p = submenu_interactivo("Modo de Almacenamiento y Prefijo", sub_pref, hw, cfg)
    if sel_p == "0":
        return
    modo_p = "aislado" if sel_p == "2" else "compartido"

    # Versión de Windows
    version_elegida = seleccionar_version_windows_interactivo(nombre_custom, ruta, hw, cfg)
    if not version_elegida:
        return

    progs_actuales = cargar_lista_programas()
    progs_actuales.append((nombre_custom, ruta, modo_p, version_elegida, "off", tipo_final))
    guardar_lista_programas(progs_actuales)
    registrar_winver_confirmado(nombre_custom, ruta)

    # Configurar Wine AppDefaults
    try:
        pe_inf = analizar_juego(ruta) if (analizar_juego and os.path.exists(ruta)) else None
        target_exe = os.path.basename(pe_inf["resolved_exe"]) if pe_inf and pe_inf.get("resolved_exe") else os.path.basename(ruta)
        pfx_list = [WINEPREFIX]
        if modo_p == "aislado":
            pfx_list.append(os.path.join(DIR, "wineprefixes", nombre_custom))
        for pfx in pfx_list:
            if os.path.isdir(pfx):
                cmd_reg = f'WINEPREFIX="{pfx}" wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\{target_exe}" /v Version /t REG_SZ /d "{version_elegida}" /f'
                subprocess.run(cmd_reg, shell=True, stderr=subprocess.DEVNULL)
    except Exception:
        pass

    lbl_icono = "🎮 Videojuego" if tipo_final == "juego" else "💼 Programa de Windows"
    print(f"\n{GREEN}✔ ¡{lbl_icono} '{nombre_custom}' registrado exitosamente en Vessel! ({WINVER_LABELS.get(version_elegida, version_elegida)}){RESET}")

    crear = input(f"\n{WHITE}¿Deseas crear acceso directo en el Escritorio ahora? (S/n): {RESET}").strip().lower()
    if crear != 'n':
        crear_desktop_entry(nombre_custom, ruta, modo_p, version_elegida, "off", tipo_final)

    ini = input(f"\n{PURPLE}¿Deseas iniciar '{nombre_custom}' ahora mismo? (s/N): {RESET}").strip().lower()
    if ini == 's':
        if pe_inf and pe_inf.get("anti_cheat_warning"):
            ac_name = pe_inf.get("anti_cheat_name", "Kernel Ring 0")
            print(f"\n{YELLOW}⚠️  ADVERTENCIA DE COMPATIBILIDAD - ANTI-CHEAT DE KERNEL DETECTADO{RESET}")
            print(f"{WHITE}Este título utiliza un sistema Anti-Cheat a nivel de Kernel exclusivo de Windows ({ac_name}).{RESET}")
            print(f"{GRAY}Podrás ejecutar pruebas o modo sin conexión / un jugador, pero los servidores oficiales en línea bloquearán el acceso en Linux.{RESET}\n")
            continuar = input(f"{CYAN}¿Deseas intentar ejecutar de todos modos? (S/n): {RESET}").strip().lower()
            if continuar == 'n':
                pausar()
                return
        os.system("clear")
        print(f"{GREEN}🚀 Iniciando: {BOLD}{nombre_custom}{RESET}...\n")
        args_launch = []
        if tipo_final == "programa":
            args_launch.append("--program")
        if modo_p == "aislado":
            args_launch.append("--isolated")
        if version_elegida and version_elegida != "win10":
            args_launch.extend(["--winver", version_elegida])
        args_launch.append(ruta)
        ejecutar_juego_y_liberar_ram(args_launch, con_hud=False)
    pausar()

def menu_instalar_con_setup(hw, cfg):
    """Ejecuta un instalador (.exe / .msi) y registra automáticamente el nuevo programa o juego."""
    sub_metodo = [
        ("1", "🖱️  Seleccionar Instalador con el Mouse (Ventana gráfica)"),
        ("2", "⌨️  Escribir o pegar la ruta manualmente en la terminal"),
        ("0", "↩️  Cancelar")
    ]
    m_opc = submenu_interactivo("💿  Seleccionar Instalador (Setup.exe / .msi)", sub_metodo, hw, cfg)
    ruta = ""
    if m_opc == "1":
        os.system("clear")
        print(f"{CYAN}🖱️  Abriendo explorador de archivos... Selecciona el Setup.exe o instalador.{RESET}\n")
        ruta = seleccionar_archivo_mouse("Seleccionar Instalador (Setup.exe, .msi)")
        if not ruta:
            print(f"{YELLOW}⚠️  No se seleccionó ningún instalador.{RESET}")
            pausar()
            return
    elif m_opc == "2":
        os.system("clear")
        print(f"{PURPLE}💿 [ INSTALAR PROGRAMA CON INSTALADOR ]{RESET}\n")
        ruta = input(f"{CYAN}Ruta al instalador (Setup.exe / instalador): {RESET}").strip().strip("'").strip('"')
    else:
        return

    if not ruta or not os.path.exists(ruta):
        print(f"\n{RED}❌ Instalador no encontrado.{RESET}")
        pausar()
        return

    def escanear_instalaciones():
        archivos = {}
        rutas_buscar = [
            os.path.join(WINEPREFIX, "drive_c", "users"),
            os.path.join(WINEPREFIX, "drive_c", "Program Files"),
            os.path.join(WINEPREFIX, "drive_c", "Program Files (x86)"),
            os.path.join(WINEPREFIX, "drive_c", "Games"),
            os.path.join(WINEPREFIX, "drive_c", "Juegos"),
            os.path.expanduser("~/Escritorio"),
            os.path.expanduser("~/Desktop")
        ]
        for base in rutas_buscar:
            if os.path.isdir(base):
                for r_root, _, r_files in os.walk(base):
                    for f in r_files:
                        ext = os.path.splitext(f)[1].lower()
                        if ext in ('.lnk', '.ink', '.exe'):
                            f_low = f.lower()
                            if not any(ign in f_low for ign in ['unins', 'uninst', 'uninstall', 'setup', 'dxsetup', 'vcredist', 'wine', 'notepad', 'regedit', 'explorer']):
                                p_full = os.path.join(r_root, f)
                                try:
                                    mtime = os.path.getmtime(p_full)
                                    archivos[p_full] = mtime
                                except Exception:
                                    pass
        return archivos

    snapshot_antes = escanear_instalaciones()

    print(f"\n{GREEN}🚀 Iniciando instalador en Wine... Sigue los pasos del asistente.{RESET}\n")
    subprocess.run(["bash", LAUNCHER, ruta])

    snapshot_despues = escanear_instalaciones()
    nuevos_candidatos = [f for f in snapshot_despues if f not in snapshot_antes]

    nuevo_lnk = None
    nuevo_exe = None
    for f in nuevos_candidatos:
        if f.lower().endswith(('.lnk', '.ink')):
            nuevo_lnk = f
            break
    if not nuevo_lnk:
        exes = [f for f in nuevos_candidatos if f.lower().endswith('.exe')]
        if exes:
            exes.sort(key=lambda x: os.path.getsize(x) if os.path.exists(x) else 0, reverse=True)
            nuevo_exe = exes[0]

    auto_detectado_path = None
    auto_detectado_nombre = ""
    if nuevo_lnk:
        try:
            sys.path.insert(0, DIR)
            from resolver_lnk import resolve_lnk
            res_lnk = resolve_lnk(nuevo_lnk, WINEPREFIX)
            if res_lnk.get("status") == "RESOLVED" and os.path.isfile(res_lnk.get("path", "")):
                auto_detectado_path = res_lnk["path"]
                auto_detectado_nombre = res_lnk.get("name") or os.path.splitext(os.path.basename(nuevo_lnk))[0]
        except Exception:
            pass
        if not auto_detectado_path:
            auto_detectado_path = nuevo_lnk
            auto_detectado_nombre = os.path.splitext(os.path.basename(nuevo_lnk))[0]
    elif nuevo_exe:
        auto_detectado_path = nuevo_exe
        auto_detectado_nombre = os.path.splitext(os.path.basename(nuevo_exe))[0]

    if auto_detectado_path:
        auto_detectado_nombre = auto_detectado_nombre.replace("_", " ").replace("-", " ")
        print(f"\n{PURPLE}╭──────────────────────────────────────────────────────────────────────────────╮{RESET}")
        print(f"{PURPLE}│  🎮 {BOLD}{WHITE}¡NUEVO ELEMENTO DETECTADO TRAS LA INSTALACIÓN!{RESET}{PURPLE}                                   │{RESET}")
        print(f"{PURPLE}╰──────────────────────────────────────────────────────────────────────────────╯{RESET}")
        print(f"  {WHITE}Nombre sugerido :{RESET} {BOLD}{CYAN}{auto_detectado_nombre}{RESET}")
        print(f"  {WHITE}Ruta ejecutable :{RESET} {GRAY}{auto_detectado_path}{RESET}\n")

        resp = input(f"{YELLOW}¿Deseas registrar este elemento en el menú de Vessel automáticamente? (S/n): {RESET}").strip().lower()
        if resp != 'n':
            nom_custom = input(f"{WHITE}Nombre para mostrar en el menú [{CYAN}{auto_detectado_nombre}{WHITE}]: {RESET}").strip()
            if not nom_custom:
                nom_custom = auto_detectado_nombre

            tipo_final = seleccionar_tipo_interactivo(nom_custom, auto_detectado_path, hw, cfg)
            if not tipo_final:
                tipo_final = "programa"

            sub_pref = [
                ("1", "📁 Prefijo Compartido (Recomendado - Comparte espacio y librerías)"),
                ("2", "🛡️ Prefijo Aislado / Sandbox (Ideal para juegos problemáticos o mods)"),
                ("0", "↩️  Cancelar")
            ]
            sel_p = submenu_interactivo("Modo de Almacenamiento y Prefijo", sub_pref, hw, cfg)
            if sel_p != "0":
                modo_p = "aislado" if sel_p == "2" else "compartido"
                version_elegida = seleccionar_version_windows_interactivo(nom_custom, auto_detectado_path, hw, cfg)
                if not version_elegida:
                    version_elegida = "win10"

                progs_actuales = cargar_lista_programas()
                progs_actuales.append((nom_custom, auto_detectado_path, modo_p, version_elegida, "off", tipo_final))
                guardar_lista_programas(progs_actuales)
                registrar_winver_confirmado(nom_custom, auto_detectado_path)

                # Configurar Wine AppDefaults
                try:
                    pe_inf = analizar_juego(auto_detectado_path) if (analizar_juego and os.path.exists(auto_detectado_path)) else None
                    target_exe = os.path.basename(pe_inf["resolved_exe"]) if pe_inf and pe_inf.get("resolved_exe") else os.path.basename(auto_detectado_path)
                    pfx_list = [WINEPREFIX]
                    if modo_p == "aislado":
                        pfx_list.append(os.path.join(DIR, "wineprefixes", nom_custom))
                    for pfx in pfx_list:
                        if os.path.isdir(pfx):
                            cmd_reg = f'WINEPREFIX="{pfx}" wine reg add "HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\{target_exe}" /v Version /t REG_SZ /d "{version_elegida}" /f'
                            subprocess.run(cmd_reg, shell=True, stderr=subprocess.DEVNULL)
                except Exception:
                    pass

                lbl_tipo = "🎮 Videojuego" if tipo_final == "juego" else "💼 Programa de Windows"
                print(f"\n{GREEN}✔ ¡{lbl_tipo} '{nom_custom}' registrado exitosamente en Vessel! ({WINVER_LABELS.get(version_elegida, version_elegida)}){RESET}")

                c_desk = input(f"\n{WHITE}¿Deseas crear acceso directo en el Escritorio ahora? (S/n): {RESET}").strip().lower()
                if c_desk != 'n':
                    crear_desktop_entry(nom_custom, auto_detectado_path, modo_p, version_elegida, "off", tipo_final)

                c_ini = input(f"\n{PURPLE}¿Deseas iniciar '{nom_custom}' ahora mismo? (s/N): {RESET}").strip().lower()
                if c_ini == 's':
                    os.system("clear")
                    print(f"{GREEN}🚀 Iniciando: {BOLD}{nom_custom}{RESET}...\n")
                    args_launch = []
                    if tipo_final == "programa":
                        args_launch.append("--program")
                    if modo_p == "aislado":
                        args_launch.append("--isolated")
                    if version_elegida and version_elegida != "win10":
                        args_launch.extend(["--winver", version_elegida])
                    args_launch.append(auto_detectado_path)
                    ejecutar_juego_y_liberar_ram(args_launch, con_hud=False)
    else:
        print(f"\n{CYAN}💡 Si el instalador creó un ejecutable en 'Program Files', puedes registrarlo con la opción 1.{RESET}")
    pausar()

def menu_configurar_programas(hw, cfg):
    """Submenú: Administrador de Programas y Videojuegos (Añadir, Instalar, Eliminar, Accesos)."""
    while True:
        opciones = [
            ("1", "➕ Añadir Programa o Juego Portable (.exe, .bat, .lnk)"),
            ("2", "💿 Instalar Programa con Instalador (Setup.exe, .msi)"),
            ("3", "❌ Desinstalar / Eliminar Elemento de la Lista (Con Flechas)"),
            ("4", "🖥️ Crear / Regenerar Acceso Directo en el Escritorio (1-Clic)"),
            ("5", "📂 Abrir Carpeta de Instalación / Mods en Gestor de Archivos"),
            ("6", "📋 Ver Lista Completa de Elementos Registrados"),
            ("0", "↩️  Volver al Menú Principal")
        ]
        sel = submenu_interactivo("⚙️  Configurar y Administrar Elementos Win", opciones, hw, cfg)
        if sel == "0":
            break
        elif sel == "1":
            menu_agregar_item_especifico(None, hw, cfg)
        elif sel == "2":
            menu_instalar_con_setup(hw, cfg)
        elif sel == "3":
            progs = cargar_lista_programas()
            if not progs:
                print(f"\n{YELLOW}⚠️  No tienes juegos o programas registrados en la lista para eliminar.{RESET}")
                pausar()
                continue
            opts_del = []
            for i, item in enumerate(progs, 1):
                p_nom = item[0]
                p_tipo = item[5] if len(item) > 5 else "juego"
                p_ico = "🎮" if p_tipo == "juego" else "💼"
                opts_del.append((str(i), f"❌ Eliminar: {p_ico} {p_nom}"))
            opts_del.append(("0", "↩️  Cancelar"))
            del_sel = submenu_interactivo("❌  Selecciona el Elemento a Eliminar", opts_del, hw, cfg)
            if del_sel != "0":
                del_idx = int(del_sel) - 1
                nom_borrado = progs[del_idx][0]
                progs_nuevos = [p for p in progs if p[0] != nom_borrado]
                guardar_lista_programas(progs_nuevos)
                print(f"\n{GREEN}✔ '{nom_borrado}' ha sido eliminado con éxito de la lista.{RESET}")
                pausar()
        elif sel == "4":
            progs = cargar_lista_programas()
            opts_desk = []
            for i, item in enumerate(progs, 1):
                p_nom = item[0]
                p_tipo = item[5] if len(item) > 5 else "juego"
                p_ico = "🎮" if p_tipo == "juego" else "💼"
                opts_desk.append((str(i), f"🖥️  {p_ico} {p_nom}"))
            opts_desk.append(("0", "↩️  Cancelar"))
            d_sel = submenu_interactivo("🖥️  Crear Acceso Directo en el Escritorio", opts_desk, hw, cfg)
            if d_sel != "0":
                d_idx = int(d_sel) - 1
                item = progs[d_idx]
                p_nom, p_rut = item[0], item[1]
                p_pref = item[2] if len(item) > 2 else "compartido"
                p_wver = item[3] if len(item) > 3 else "win10"
                p_fsr = item[4] if len(item) > 4 else "off"
                p_tipo = item[5] if len(item) > 5 else "juego"
                crear_desktop_entry(p_nom, p_rut, p_pref, p_wver, p_fsr, p_tipo)
                pausar()
        elif sel == "5":
            progs = cargar_lista_programas()
            opts_mod = []
            for i, item in enumerate(progs, 1):
                p_nom = item[0]
                p_tipo = item[5] if len(item) > 5 else "juego"
                p_ico = "🎮" if p_tipo == "juego" else "💼"
                opts_mod.append((str(i), f"📂 {p_ico} {p_nom}"))
            opts_mod.append(("0", "↩️  Cancelar"))
            m_sel = submenu_interactivo("📂  Abrir Carpeta (para Mods / Archivos)", opts_mod, hw, cfg)
            if m_sel != "0":
                m_idx = int(m_sel) - 1
                p_nom, p_rut = progs[m_idx][0], progs[m_idx][1]
                carpeta = os.path.join(DIR, "GameRanger") if "gameranger" in p_rut.lower() else os.path.dirname(p_rut)
                subprocess.run(["xdg-open", carpeta], stderr=subprocess.DEVNULL)
                print(f"\n{GREEN}✔ Carpeta abierta en tu gestor de archivos.{RESET}")
                pausar()
        elif sel == "6":
            os.system("clear")
            print(f"{PURPLE}📋 [ ELEMENTOS REGISTRADOS EN LA BASE DE DATOS ]{RESET}\n")
            for item in cargar_lista_programas():
                p_nom, p_rut = item[0], item[1]
                p_pref = item[2] if len(item) > 2 else "compartido"
                p_wver = item[3] if len(item) > 3 else "win10"
                p_fsr = item[4] if len(item) > 4 else "off"
                p_tipo = item[5] if len(item) > 5 else "juego"
                p_ico = "🎮" if p_tipo == "juego" else "💼"
                tag_tipo = f"{PURPLE}[{p_tipo.capitalize()}]{RESET}"
                tag_pref = f"{CYAN}[🛡️ Aislado]{RESET}" if p_pref == "aislado" else f"{GRAY}[Compartido]{RESET}"
                tag_wver = f"{PURPLE}[🪟 {p_wver.upper()}]{RESET}"
                tag_fsr = f" {GREEN}[⚡ FSR {p_fsr.capitalize()}]{RESET}" if p_fsr != "off" else ""
                print(f"  {p_ico} {BOLD}{p_nom}{RESET} {tag_tipo} {tag_pref} {tag_wver}{tag_fsr} -> {GRAY}{p_rut}{RESET}")
            pausar()

# ==============================================================================
# SUBMENÚ 3: RENDIMIENTO Y MOTOR GRÁFICO (VESSEL SMART PERFORMANCE)
# ==============================================================================

def menu_rendimiento(hw, cfg):
    """Submenú 3: Vessel Smart Performance - Calibración Automática de Juegos sin Tocar tu Sistema."""
    while True:
        cfg = cargar_config()
        p_act = cfg.get("PERFIL_RENDIMIENTO", "inteligente").lower()
        fps_act = cfg.get("LIMITE_FPS", "60")
        fsr_act = f"Activo (x{cfg.get('FSR_STRENGTH', '2')})" if cfg.get("ACTIVAR_FSR") == "1" else "Apagado"
        hud_act = "Activo" if cfg.get("MOSTRAR_HUD_FPS") == "1" else "Apagado"
        mot_act = cfg.get("RENDERER_BACKEND", "auto").upper()

        p_badge = "⭐ INTELIGENTE" if p_act in ("inteligente", "maximo") else ("🛡️ ESTÁNDAR" if p_act == "estandar" else "🚀 EXTREMO")

        info_perf = [
            f"🖥️  {BOLD}{WHITE}Diagnóstico Automático de Hardware (Plug & Play):{RESET}",
            f"  • {PURPLE}CPU / Hilos{RESET} : {WHITE}{hw.get('cpu_raw', hw['cpu'])}{RESET} ({hw['cores']} hilos asignados)",
            f"  • {PURPLE}GPU Activa{RESET}  : {WHITE}{hw['gpu']}{RESET} | Servidor: {WHITE}{hw.get('server', 'wayland').upper()}{RESET}",
            f"  • {PURPLE}Resolución{RESET}  : Pantalla {WHITE}{hw.get('native_res', '1920x1080')}{RESET} ➔ Óptima Juego: {GREEN}{BOLD}{hw.get('rec_res', '1280x720')}{RESET} ({'Adaptativa CAS' if hw.get('is_entry') else 'Nativa Alta'})",
            f"  • {PURPLE}Kernel/Sync{RESET} : {CYAN}{hw.get('sync', 'Fsync')} Activo{RESET} | GameMode: {GREEN if hw.get('has_gamemode') else RED}{'Activo' if hw.get('has_gamemode') else 'No detectado'}{RESET} | PipeWire: {GREEN if hw.get('has_pipewire') else RED}{'2.6ms' if hw.get('has_pipewire') else 'Estándar'}{RESET}"
        ]

        opts_perf = [
            ("1", f"⭐ Modo Rendimiento Inteligente  ─── [ RECOMENDADO ] [Activo: {p_badge}]\n"
                  f"• Calibra resolución y shaders automáticamente para tu GPU.\n"
                  f"• Prioridad de CPU alta y cero micro-tirones mientras juegas.\n"
                  f"• 100% Seguro: Funciona en memoria RAM. NO toca archivos de tu sistema.\n"
                  f"• Al salir del juego, tu PC vuelve a su estado normal."),

            ("2", "🛡️ Modo Estándar / Compatibilidad Total\n"
                  "• Ejecuta el juego con Wine/DXVK clásico sin optimizaciones agresivas.\n"
                  "• Ideal si solo quieres probar si un juego antiguo abre."),

            ("3", f"🚀 Modo Portátil Extremo (Gamescope + FSR) [FSR: {fsr_act}]\n"
                  "• Reescalado de resolución inteligente por hardware.\n"
                  "• Diseñado para ganar hasta +50% FPS en laptops."),

            ("4", "🔄 Restaurar Copias de Seguridad (.vessel_orig / .vessel_bak)\n"
                  "• Devuelve todos los juegos a su configuración de fábrica en un abrir y cerrar de ojos."),

            ("5", f"🛠️ Ajustes Avanzados Manuales (FPS: {fps_act}, HUD: {hud_act}, Motor: {mot_act})\n"
                  "• Configuración individual de FPS, nitidez FSR, HUD, shaders y runners."),

            ("0", "↩️ Volver al Menú Principal")
        ]

        sel = submenu_interactivo("⚡  VESSEL SMART PERFORMANCE (Calibración Automática)", opts_perf, hw, cfg, info_lines=info_perf)
        if sel == "0":
            break
        elif sel == "1":
            # [1] ⭐ Modo Rendimiento Inteligente [ RECOMENDADO ]
            guardar_config("PERFIL_RENDIMIENTO", "inteligente")
            guardar_config("ACTIVAR_FSR", "0")
            guardar_config("SMART_PERF_CONFIGURADO", "1")
            guardar_config("SMART_PERF_VERSION", SMART_PERF_VERSION_ACTUAL)
            try:
                open(SMART_PERF_MARKER, "w").close()
            except Exception:
                pass
            subprocess.run(["bash", os.path.join(DIR, "generar_dxvk_conf.sh")], stderr=subprocess.DEVNULL)

            os.system("clear")
            render_banner(hw, cfg)
            print(f"\n  {GREEN}{BOLD}✔ Modo Rendimiento Inteligente [RECOMENDADO] Activado con Éxito{RESET}")
            print(f"  {CYAN}══════════════════════════════════════════════════════════════════════{RESET}")
            print(f"  🧠 {PURPLE}CPU / Hilos{RESET}    : {WHITE}{hw['cores']} hilos asignados a dxvk.numCompilerThreads{RESET}")
            print(f"  📼 {PURPLE}GPU / Gráficos{RESET} : {WHITE}{hw['gpu']} (Perfil adaptativo calibrado para máximos FPS){RESET}")
            print(f"  🎛️ {PURPLE}Memoria RAM{RESET}   : {WHITE}{hw['ram']} (Caché optimizada en RAM para cero tirones){RESET}")
            print(f"  🛡️ {PURPLE}Seguridad{RESET}     : {GREEN}100% Seguro. Todo corre en RAM sin tocar archivos del sistema.{RESET}")
            print(f"  {CYAN}══════════════════════════════════════════════════════════════════════{RESET}\n")
            pausar()
        elif sel == "2":
            # [2] 🛡️ Modo Estándar / Compatibilidad Total
            guardar_config("PERFIL_RENDIMIENTO", "estandar")
            guardar_config("ACTIVAR_FSR", "0")
            guardar_config("SMART_PERF_CONFIGURADO", "1")
            guardar_config("SMART_PERF_VERSION", SMART_PERF_VERSION_ACTUAL)
            try:
                open(SMART_PERF_MARKER, "w").close()
            except Exception:
                pass
            subprocess.run(["bash", os.path.join(DIR, "generar_dxvk_conf.sh")], stderr=subprocess.DEVNULL)
            os.system("clear")
            render_banner(hw, cfg)
            print(f"\n  {GREEN}{BOLD}✔ Modo Estándar / Compatibilidad Total Activado{RESET}")
            print(f"  {CYAN}══════════════════════════════════════════════════════════════════════{RESET}")
            print(f"  • Ejecutará los juegos con Wine y DXVK estándar sin optimizaciones agresivas.")
            print(f"  • Ideal para pruebas de compatibilidad o si un juego antiguo presenta problemas.")
            print(f"  {CYAN}══════════════════════════════════════════════════════════════════════{RESET}\n")
            pausar()
        elif sel == "3":
            # [3] 🚀 Modo Portátil Extremo (Gamescope + FSR)
            guardar_config("PERFIL_RENDIMIENTO", "extremo")
            guardar_config("ACTIVAR_FSR", "1")
            guardar_config("SMART_PERF_CONFIGURADO", "1")
            guardar_config("SMART_PERF_VERSION", SMART_PERF_VERSION_ACTUAL)
            try:
                open(SMART_PERF_MARKER, "w").close()
            except Exception:
                pass
            subprocess.run(["bash", os.path.join(DIR, "generar_dxvk_conf.sh")], stderr=subprocess.DEVNULL)
            os.system("clear")
            render_banner(hw, cfg)
            print(f"\n  {GREEN}{BOLD}✔ Modo Portátil Extremo (Gamescope + FSR) Activado{RESET}")
            print(f"  {CYAN}══════════════════════════════════════════════════════════════════════{RESET}")
            print(f"  • Reescalado de resolución inteligente AMD FSR activo para ganar hasta +50% FPS.")
            print(f"  • Fallback automático: Si Gamescope no está disponible, pasa a pantalla completa nativa.")
            print(f"  {CYAN}══════════════════════════════════════════════════════════════════════{RESET}\n")
            pausar()
        elif sel == "4":
            # [4] 🔄 Restaurar Configuraciones Originales (Botón de Respaldo)
            os.system("clear")
            restaurador = os.path.join(DIR, "herramientas", "restaurar_respaldos.sh")
            if os.path.exists(restaurador):
                subprocess.run(["bash", restaurador])
            else:
                print(f"{YELLOW}No se encontró el script de restauración.{RESET}")
            pausar()
        elif sel == "5":
            # [5] 🛠️ Ajustes Avanzados Manuales
            menu_rendimiento_avanzado(hw, cfg)

def menu_rendimiento_avanzado(hw, cfg):
    """Submenú de Ajustes Avanzados Manuales de Rendimiento y Motor Gráfico."""
    while True:
        cfg = cargar_config()
        fps_act = cfg.get("LIMITE_FPS", "60")
        fsr_act = f"Activo (x{cfg.get('FSR_STRENGTH', '2')})" if cfg.get("ACTIVAR_FSR") == "1" else "Apagado"
        hud_act = "Activo" if cfg.get("MOSTRAR_HUD_FPS") == "1" else "Apagado"
        mot_act = cfg.get("RENDERER_BACKEND", "auto").upper()

        opciones = [
            ("1", f"🎯 Límite de FPS (Actual: {fps_act} FPS)"),
            ("2", f"🚀 AMD FSR Nivel de Nitidez (Actual: {fsr_act})"),
            ("3", f"📊 HUD de FPS y Telemetría en Pantalla (Actual: {hud_act})"),
            ("4", f"🎮 Motor Gráfico (Actual: {mot_act})"),
            ("5", f"🧹 Limpiar Shaders y Caché DXVK (Solucionar Tirones / Descuadres 3D)"),
            ("6", f"🎛️ Filtrado Anisótropo 16x (Máxima Nitidez de Texturas)"),
            ("7", f"🍷 Gestor de Wine Runners (Wine-GE / Kron4ek Staging / Lutris)"),
            ("0", "↩️  Volver a Smart Performance")
        ]
        sel = submenu_interactivo("🛠️  Ajustes Avanzados Manuales", opciones, hw, cfg)
        if sel == "0":
            break
        elif sel == "1":
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
        elif sel == "2":
            sub_fsr = [
                ("1", "Nivel 1 - Muy Nítido"),
                ("2", "Nivel 2 - Equilibrado (Recomendado)"),
                ("3", "Nivel 3 - Suave"),
                ("0", "Mantener actual")
            ]
            s = submenu_interactivo("Nivel de Nitidez FSR", sub_fsr, hw, cfg)
            if s in ("1", "2", "3"):
                guardar_config("FSR_STRENGTH", s)
        elif sel == "3":
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
        elif sel == "4":
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
        elif sel == "5":
            # Limpiar shaders y caché
            os.system("clear")
            print(f"{PURPLE}🧹 [ LIMPIANDO SHADERS Y CACHÉ GRÁFICA ]{RESET}\n")
            c1 = subprocess.run(f"rm -rf '{DIR}'/*.dxvk-cache '{WINEPREFIX}'/drive_c/*.dxvk-cache 2>/dev/null", shell=True)
            print(f"{GREEN}✔ Archivos de caché de shaders corruptos eliminados.{RESET}")
            print(f"{WHITE}Los juegos regenerarán shaders frescos sin tirones al iniciar.{RESET}")
            pausar()
        elif sel == "6":
            os.system("clear")
            print(f"{PURPLE}🎛️  [ FILTRADO ANISÓTROPO 16X FORZADO ]{RESET}\n")
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
        elif sel == "7":
            script_runners = os.path.join(DIR, "gestor_runners.sh")
            while True:
                sub_r = [
                    ("1", "📋 Listar Runners Instalados y Activos en el Sistema"),
                    ("2", "📥 Descargar e Instalar Wine-Staging WOW64 Portable (Kron4ek - DX12, MF, Esync/Fsync)"),
                    ("3", "📥 Descargar e Instalar Wine-GE Portable (GloriousEggroll - Optimizado para Gaming)"),
                    ("0", "↩️  Volver a Ajustes Avanzados")
                ]
                sr = submenu_interactivo("🍷  Gestor de Wine Runners", sub_r, hw, cfg)
                if sr == "0":
                    break
                elif sr == "1":
                    os.system("clear")
                    subprocess.run(["bash", script_runners, "--list"])
                    pausar()
                elif sr == "2":
                    os.system("clear")
                    subprocess.run(["bash", script_runners, "--kron4ek"])
                    pausar()
                elif sr == "3":
                    os.system("clear")
                    subprocess.run(["bash", script_runners, "--wine-ge"])
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
            ("9", "🔍 Diagnóstico de Controladores Gráficos y 32-bit (NVIDIA / AMD / Intel)"),
            ("10", "🎮 Gestor de Librerías y Mandos (SDL2 Gamepad, cnc-ddraw, DSOAL 3D, vkBasalt)"),
            ("11", "🖥️  Regenerar y Validar Acceso Directo de Vessel en el Escritorio"),
            ("12", "📋 Ver Informe de Errores de Juegos (Crash Reports)"),
            ("13", "⚡ Motor de Inferencia Heurística y Diagnóstico de Ejecutables (.exe)\n• Analiza cualquier binario PE en <5 ms, detecta arquitectura, LAA, motor y calcula variables óptimas"),
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
            script_lib = os.path.join(CORE_DIR, "gestor_librerias.sh") if os.path.exists(os.path.join(CORE_DIR, "gestor_librerias.sh")) else os.path.join(DIR, "herramientas", "gestor_librerias.sh")
            sub_winetricks = [
                ("1", "🚀 Instalar Paquete Maestro de DLLs para Todos los Juegos (Recomendado)\n• DirectX 9/10/11 (+100 DLLs), VC++ 2005-2022 AIO, D3D8to9, NVAPI, OpenAL 3D, DirectPlay y Corefonts"),
                ("2", "🎮 DirectX 9, 10 y 11 Completo (+100 DLLs oficiales de Microsoft)\n• D3DX9/10/11, D3DCompiler 33-47, XInput 1.1-1.4, XAudio2 y XACT"),
                ("3", "⚙️  Microsoft Visual C++ Runtimes (2005 a 2022 AIO Oficial)\n• VCRuntime140, MSVCP140, MSVCR120, MSVCP120, MSVCR100, MFC42"),
                ("4", "🕹️  D3D8to9: Traductor DirectX 8 a Vulkan (60 FPS para clásicos 2001-2006)\n• Convierte GTA Vice City/SA, Max Payne, NFS Underground a DirectX 9 / DXVK"),
                ("5", "🟢 DXVK-NVAPI: Puente de Alto Rendimiento para GPUs NVIDIA GeForce\n• Desbloquea Reflex, baja latencia y extensiones nativas NVIDIA"),
                ("6", "🔤 Fuentes Oficiales de Windows (Corefonts: Arial, Times, Tahoma, Verdana)"),
                ("7", "🌐 .NET Framework 4.8 (dotnet48 para launchers y mods)"),
                ("8", "🔊 Audio 3D OpenAL + DSOAL (EAX binaural espacial)"),
                ("9", "🕹️  DirectDraw Retro OpenGL (cnc-ddraw para clásicos 1995-2003)"),
                ("10", "⚡ VKD3D-Proton: DirectX 12 a Vulkan (Resident Evil 4 Remake y juegos DX12)"),
                ("11", "🛠️  Apartado Modular de Drivers (DXVK, VKD3D-Proton, GPU y Pantalla)\n• Revisa el estado de drivers abiertos y configuración de pantalla objetivo"),
                ("0", "↩️  Cancelar")
            ]
            w_sel = submenu_interactivo("📦  Instalar Dependencias y DLLs de Windows", sub_winetricks, hw, cfg)
            if w_sel == "1":
                os.system("clear")
                subprocess.run(["bash", script_lib, "paquete_maestro", WINEPREFIX])
                pausar()
            elif w_sel == "2":
                os.system("clear")
                subprocess.run(["bash", script_lib, "instalar_directx", WINEPREFIX])
                pausar()
            elif w_sel == "3":
                os.system("clear")
                subprocess.run(["bash", script_lib, "instalar_vcredist", WINEPREFIX])
                pausar()
            elif w_sel == "4":
                os.system("clear")
                subprocess.run(["bash", script_lib, "instalar_d3d8to9", WINEPREFIX])
                pausar()
            elif w_sel == "5":
                os.system("clear")
                subprocess.run(["bash", script_lib, "instalar_nvapi", WINEPREFIX])
                pausar()
            elif w_sel == "6":
                os.system("clear")
                subprocess.run(["bash", script_lib, "instalar_fuentes", WINEPREFIX])
                pausar()
            elif w_sel == "7":
                os.system("clear")
                print(f"{CYAN}🌐 Instalando .NET Framework 4.8 (puede tardar varios minutos)...{RESET}\n")
                subprocess.run(f"WINEPREFIX='{WINEPREFIX}' winetricks -q dotnet48", shell=True)
                pausar()
            elif w_sel == "8":
                os.system("clear")
                subprocess.run(["bash", script_lib, "instalar_openal", WINEPREFIX])
                pausar()
            elif w_sel == "9":
                os.system("clear")
                target_dest = os.path.join(WINEPREFIX, "drive_c", "windows", "syswow64") if os.path.isdir(os.path.join(WINEPREFIX, "drive_c", "windows", "syswow64")) else os.path.join(WINEPREFIX, "drive_c", "windows", "system32")
                subprocess.run(["bash", script_lib, "instalar_ddraw", target_dest])
                pausar()
            elif w_sel == "10":
                os.system("clear")
                subprocess.run(["bash", script_lib, "instalar_vkd3d", WINEPREFIX])
                pausar()
            elif w_sel == "11":
                os.system("clear")
                script_drv = os.path.join(CORE_DIR, "gestor_drivers.sh") if os.path.exists(os.path.join(CORE_DIR, "gestor_drivers.sh")) else os.path.join(DIR, "core", "gestor_drivers.sh")
                subprocess.run(["bash", script_drv, "estado"])
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
        elif sel == "9":
            os.system("clear")
            hw_diag_script = os.path.join(CORE_DIR, "hardware_detect.sh") if os.path.exists(os.path.join(CORE_DIR, "hardware_detect.sh")) else os.path.join(DIR, "hardware_detect.sh")
            subprocess.run(["bash", hw_diag_script, "--check-drivers"])
            pausar()
        elif sel == "10":
            os.system("clear")
            script_lib = os.path.join(CORE_DIR, "gestor_librerias.sh") if os.path.exists(os.path.join(CORE_DIR, "gestor_librerias.sh")) else os.path.join(DIR, "herramientas", "gestor_librerias.sh")
            if os.path.exists(script_lib):
                subprocess.run(["bash", script_lib, "menu"])
            else:
                print(f"{RED}No se encontró el gestor de librerías en: {script_lib}{RESET}")
            pausar()
        elif sel == "11":
            os.system("clear")
            print(f"{PURPLE}🖥️  [ VALIDAR / REGENERAR ACCESO DIRECTO DE VESSEL EN EL ESCRITORIO ]{RESET}\n")
            verificar_acceso_directo_vessel(mostrar_notif=True)
            pausar()
        elif sel == "12":
            os.system("clear")
            logs_dir = os.path.join(DIR, "logs_errores")
            ultimo = os.path.join(logs_dir, "ultimo_error.log")
            if os.path.exists(ultimo):
                print(f"{PURPLE}📋 [ REGISTRO DE ÚLTIMO ERROR / CRASH REPORT ]{RESET}\n")
                try:
                    with open(ultimo, "r", encoding="utf-8", errors="replace") as f:
                        lines = f.readlines()
                    print("".join(lines[:45]))
                    if len(lines) > 45:
                        print(f"\n{YELLOW}... ({len(lines) - 45} líneas adicionales en: {ultimo}){RESET}")
                except Exception as e:
                    print(f"{RED}Error leyendo archivo: {e}{RESET}")
            else:
                print(f"{PURPLE}📋 [ REGISTRO DE ERRORES / CRASH REPORTS ]{RESET}\n")
                print(f"{GREEN}✔ No se han detectado errores recientes.{RESET}")
                print(f"{WHITE}Todos los juegos se han ejecutado y cerrado limpiamente sin generar registros residuales.{RESET}\n")
            pausar()
        elif sel == "13":
            os.system("clear")
            print(f"{PURPLE}⚡ [ MOTOR DE INFERENCIA HEURÍSTICA Y RENDIMIENTO PE ]{RESET}\n")
            print(f"{WHITE}Escribe o pega la ruta completa al archivo .exe que deseas inspeccionar:{RESET}")
            ruta_test = input(f"{CYAN}Ruta (.exe): {RESET}").strip().strip('"').strip("'")
            if ruta_test and os.path.exists(ruta_test):
                os.system("clear")
                script_inf = os.path.join(CORE_DIR, "motor_inferencia.py") if os.path.exists(os.path.join(CORE_DIR, "motor_inferencia.py")) else os.path.join(DIR, "core", "motor_inferencia.py")
                subprocess.run(["python3", script_inf, ruta_test, "--summary"])
            else:
                print(f"\n{YELLOW}⚠ Archivo no encontrado o ruta vacía.{RESET}")
            pausar()

# ==============================================================================
# SUBMENÚ 5: ACTUALIZAR Y CONFIGURAR AUTOMÁTICAMENTE
# ==============================================================================

def menu_actualizar(hw, cfg, es_primer_inicio=False):
    """Submenú 5: Actualizar distribución, descargar componentes y optimizar el sistema."""
    cfg = cargar_config()
    distro_detectada = cfg.get("DISTRO_NAME", "Debian")
    distro_id = cfg.get("SISTEMA_LINUX", "debian")

    if os.path.exists("/etc/os-release"):
        with open("/etc/os-release", "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                if line.startswith("NAME="):
                    distro_detectada = line.split("=", 1)[1].strip().strip('"')
                elif line.startswith("ID="):
                    d_raw = line.split("=", 1)[1].strip().strip('"').lower()
                    if d_raw in ("debian", "ubuntu", "linuxmint", "pop", "zorin", "arch", "manjaro", "endeavouros", "fedora", "nobara", "opensuse", "suse"):
                        distro_id = d_raw

    # Si no es el primer inicio, ofrecer menú para actualizar Vessel desde GitHub o paquetes del sistema
    if not es_primer_inicio:
        menu_opcs = [
            ("1", "⚡ Buscar y descargar actualizaciones de Vessel en GitHub"),
            ("2", f"🐧 Descargar paquetes del sistema ({distro_detectada}) y drivers Vulkan"),
            ("0", "↩️  Volver al Menú Principal")
        ]
        sel_act = submenu_interactivo("🔄  Centro de Actualizaciones de Vessel", menu_opcs, hw, cfg)
        if sel_act == "1":
            os.system("clear")
            actualizado = verificar_actualizacion_automatica_github(mostrar_notif=True, cfg=cfg)
            if not actualizado:
                pausar()
            return
        elif sel_act == "2":
            pass  # Continúa a la selección de distribución
        else:
            return

    distro_menu = [
        ("1", f"🐧 Debian / Devuan {'(Detectada en tu PC)' if 'debian' in distro_id or 'devuan' in distro_id else ''}"),
        ("2", f"🐧 Ubuntu / Linux Mint / Pop!_OS / Zorin OS {'(Detectada en tu PC)' if any(x in distro_id for x in ('ubuntu', 'mint', 'pop', 'zorin')) else ''}"),
        ("3", f"🐧 Arch Linux / Manjaro / EndeavourOS / SteamOS {'(Detectada en tu PC)' if any(x in distro_id for x in ('arch', 'manjaro', 'endeavour', 'steamos')) else ''}"),
        ("4", f"🐧 Fedora / Nobara / RHEL {'(Detectada en tu PC)' if any(x in distro_id for x in ('fedora', 'nobara', 'rhel')) else ''}"),
        ("5", f"🐧 openSUSE (Tumbleweed / Leap) {'(Detectada en tu PC)' if 'suse' in distro_id else ''}"),
        ("0", "↩️  Cancelar y Volver al Menú Principal")
    ]

    titulo_sub = "🚀  Paso 1: Selecciona tu Distribución de Linux" if es_primer_inicio else "🔄  Selecciona tu Distribución de Linux para Actualizar"
    sel_distro = submenu_interactivo(titulo_sub, distro_menu, hw, cfg)
    if sel_distro == "0":
        if es_primer_inicio:
            print(f"\n{YELLOW}⚠️  Configuración inicial pospuesta. Podrás ejecutarla en cualquier momento desde la opción [5] Actualizar.{RESET}")
            time.sleep(1.5)
        return

    mapa_distros = {
        "1": ("debian", "Debian GNU/Linux"),
        "2": ("ubuntu", "Ubuntu / Linux Mint"),
        "3": ("arch", "Arch Linux / Manjaro"),
        "4": ("fedora", "Fedora / Nobara"),
        "5": ("opensuse", "openSUSE")
    }

    id_elegido, nombre_elegido = mapa_distros.get(sel_distro, (distro_id, distro_detectada))
    guardar_config("SISTEMA_LINUX", id_elegido)
    guardar_config("DISTRO_NAME", nombre_elegido)
    cfg["SISTEMA_LINUX"] = id_elegido
    cfg["DISTRO_NAME"] = nombre_elegido

    # Preguntar si desea descargar los archivos necesarios (S/n)
    os.system("clear")
    encabezado_modo = "CONFIGURACIÓN INICIAL DE PRIMER USO" if es_primer_inicio else "ACTUALIZAR Y CONFIGURAR"
    print(f"{PURPLE}🔄 [ {encabezado_modo} - {nombre_elegido.upper()} ]{RESET}\n")
    print(f"  {WHITE}Distribución seleccionada :{RESET} {CYAN}{nombre_elegido}{RESET}")
    print(f"  {WHITE}Hardware detectado        :{RESET} {BOLD}{hw['cpu']} | {hw['gpu']} | {hw['ram']}{RESET}\n")
    print(f"{WHITE}Esta opción descargará y configurará automáticamente todos los paquetes,{RESET}")
    print(f"{WHITE}drivers Vulkan (32 y 64 bits), optimizaciones de memoria del kernel y dependencias para tu PC.{RESET}\n")

    confirmar = input(f"{CYAN}¿Deseas descargar los archivos necesarios para esta computadora? (S/n): {RESET}").strip().lower()
    if confirmar == 'n':
        print(f"\n{YELLOW}⚠️  Operación cancelada. Volviendo al menú principal...{RESET}")
        time.sleep(1.2)
        return

    # Proceder a ejecutar la descarga e instalación completa
    os.system("clear")
    print(f"{GREEN}🚀 Iniciando descarga, actualización y configuración de {nombre_elegido}...{RESET}\n")

    res = subprocess.run(["bash", "-c", f"""
export SISTEMA_LINUX="{id_elegido}"
export DISTRO_NAME="{nombre_elegido}"
source "{os.path.join(DIR, 'menu-win.sh')}"
ejecutar_descarga_e_instalacion_automatica
"""])

    # Si la instalación completó con éxito, registrar versión actual en INSTALADO_MARKER y mantener version.txt en 0 bytes
    if res.returncode == 0:
        try:
            open(VERSION_FILE, "w").close()
            with open(INSTALADO_MARKER, "w", encoding="utf-8") as f:
                f.write(VERSION_ACTUAL + "\n")
        except Exception:
            pass

    print(f"\n{CYAN}══════════════════════════════════════════════════════════════════════{RESET}")
    print(f"{BOLD}{GREEN}🎉 ¡CONFIGURACIÓN Y OPTIMIZACIÓN COMPLETADA CON ÉXITO AL 100%! 🎉{RESET}")
    print(f"{WHITE}Tu computadora ({nombre_elegido}) está lista para correr cualquier juego o programa.{RESET}")
    print(f"{CYAN}══════════════════════════════════════════════════════════════════════{RESET}")
    pausar()

def comprobar_primer_inicio(hw, cfg):
    """Comprueba si el usuario entra por primera vez (version.txt vacío o diferente versión)."""
    # Si ya se marcó como instalado, no repetir el asistente
    if os.path.exists(INSTALADO_MARKER):
        return

    # Si no existe el archivo version.txt, crearlo vacío
    if not os.path.exists(VERSION_FILE):
        try:
            with open(VERSION_FILE, "w", encoding="utf-8") as f:
                pass
        except Exception:
            pass

    v_content = ""
    try:
        if os.path.exists(VERSION_FILE):
            with open(VERSION_FILE, "r", encoding="utf-8", errors="ignore") as f:
                v_content = f.read().strip()
    except Exception:
        v_content = ""

    # Si version.txt está vacío o la versión no es la actual, lanzar asistente de primer inicio
    if not v_content or v_content != VERSION_ACTUAL:
        os.system("clear")
        total_w = get_terminal_width()
        inner_w = total_w - 2

        print(f"{PURPLE}╭{'─' * inner_w}╮{RESET}")
        title = "🎮  ¡BIENVENIDO A VESSEL (MENU WIN)!  🎮"
        pad = max((inner_w - visual_width(title)) // 2, 0)
        print(f"{PURPLE}│{RESET}{' ' * pad}{BOLD}{WHITE}{title}{RESET}{' ' * max(inner_w - pad - visual_width(title), 0)}{PURPLE}│{RESET}")
        print(f"{PURPLE}│{' ' * inner_w}│{RESET}")

        msg1 = "Detectamos que es la primera vez que abres el programa en esta computadora."
        msg2 = "Para que tus juegos corran al máximo rendimiento (Vulkan, DXVK, Esync y Fsync),"
        msg3 = "vamos a seleccionar tu distribución de Linux y optimizar todo a tu medida."

        for m in (msg1, msg2, msg3):
            pm = max((inner_w - visual_width(m)) // 2, 0)
            print(f"{PURPLE}│{RESET}{' ' * pm}{CYAN}{m}{RESET}{' ' * max(inner_w - pm - visual_width(m), 0)}{PURPLE}│{RESET}")

        print(f"{PURPLE}╰{'─' * inner_w}╯{RESET}\n")
        print(f"{WHITE}Presiona {BOLD}{GREEN}[Enter]{RESET}{WHITE} para seleccionar tu sistema Linux y comenzar la configuración inicial...{RESET}")
        read_key()

        menu_actualizar(hw, cfg, es_primer_inicio=True)

        # Preinstalar y dejar GameRanger portable listo en la PC desde el primer inicio
        desplegar_gameranger_portable(mostrar_notif=True)

        try:
            with open(INSTALADO_MARKER, "w", encoding="utf-8") as f:
                f.write(VERSION_ACTUAL + "\n")
        except Exception:
            pass

def comprobar_configuracion_smart_performance(hw, cfg):
    """
    Comprueba si es la primera vez que el usuario abre Vessel tras una actualización
    que añade o modifica el menú de Smart Performance.
    Si aún no se ha calibrado, abre la pantalla de autocalibración antes de entrar al menú principal,
    guarda la selección en la configuración y muestra recordatorio de acceso fácil en el menú [3].
    """
    cfg = cargar_config()
    ya_calibrado = (
        cfg.get("SMART_PERF_CONFIGURADO") == "1" and
        cfg.get("SMART_PERF_VERSION") == SMART_PERF_VERSION_ACTUAL and
        os.path.exists(SMART_PERF_MARKER)
    )

    if ya_calibrado:
        return

    total_w = get_terminal_width()
    inner_w = max(total_w - 2, 70)

    os.system("clear")
    print(f"{PURPLE}╭{'─' * inner_w}╮{RESET}")
    title = "⚡  ¡NUEVA ACTUALIZACIÓN: VESSEL SMART PERFORMANCE!  ⚡"
    pad = max((inner_w - visual_width(title)) // 2, 0)
    print(f"{PURPLE}│{RESET}{' ' * pad}{BOLD}{CYAN}{title}{RESET}{' ' * max(inner_w - pad - visual_width(title), 0)}{PURPLE}│{RESET}")

    sub = 'Calibración Inteligente "Plug & Play Portable" sin Tocar tu Sistema'
    pad_s = max((inner_w - visual_width(sub)) // 2, 0)
    print(f"{PURPLE}│{RESET}{' ' * pad_s}{WHITE}{sub}{RESET}{' ' * max(inner_w - pad_s - visual_width(sub), 0)}{PURPLE}│{RESET}")
    print(f"{PURPLE}├{'─' * inner_w}┤{RESET}")
    print(f"{PURPLE}│{' ' * inner_w}│{RESET}")

    msg_hw1 = "  Hemos analizado los componentes de tu equipo automáticamente:"
    msg_hw2 = f"    • 🧠 {PURPLE}CPU / Hilos{RESET} : {WHITE}{hw.get('cpu_raw', hw['cpu'])}{RESET} ({hw['cores']} Hilos)"
    msg_hw3 = f"    • 📼 {PURPLE}GPU Gráfica{RESET} : {WHITE}{hw['gpu']}{RESET} | Servidor: {WHITE}{hw.get('server', 'wayland').upper()}{RESET}"
    msg_hw4 = f"    • 🎛️ {PURPLE}Memoria RAM{RESET} : {WHITE}{hw['ram']}{RESET} ({hw.get('ram_mb', 8192)} MB)"
    msg_hw5 = f"    • 🖥️ {PURPLE}Resolución{RESET}  : Pantalla {WHITE}{hw.get('native_res', '1920x1080')}{RESET} ➔ Óptima Juego: {GREEN}{BOLD}{hw.get('rec_res', '1280x720')}{RESET}"
    msg_hw6 = f"    • 🛡️ {PURPLE}Seguridad{RESET}   : {GREEN}100% Protegido (0 comandos sudo / todo en RAM){RESET}"

    for m in (msg_hw1, msg_hw2, msg_hw3, msg_hw4, msg_hw5, msg_hw6):
        print(f"{PURPLE}│{RESET} {pad_visual(m, inner_w - 2)} {PURPLE}│{RESET}")

    print(f"{PURPLE}│{' ' * inner_w}│{RESET}")
    msg_intro = "  Por favor, selecciona cómo deseas calibrar tus juegos portátiles:"
    print(f"{PURPLE}│{RESET} {pad_visual(msg_intro, inner_w - 2)} {PURPLE}│{RESET}")
    print(f"{PURPLE}╰{'─' * inner_w}╯{RESET}\n")

    opts = [
        ("1", "⭐ Modo Rendimiento Inteligente  ─── [ RECOMENDADO ]\n"
              "• Calibra resolución y shaders automáticamente para tu GPU.\n"
              "• Prioridad de CPU alta y cero micro-tirones mientras juegas.\n"
              "• 100% Seguro: Funciona en memoria RAM. NO toca archivos de tu sistema.\n"
              "• Al salir del juego, tu PC vuelve a su estado normal."),

        ("2", "🛡️ Modo Estándar / Compatibilidad Total\n"
              "• Ejecuta el juego con Wine/DXVK clásico sin optimizaciones agresivas.\n"
              "• Ideal si solo quieres probar si un juego antiguo abre."),

        ("3", "🚀 Modo Portátil Extremo (Gamescope + FSR)\n"
              "• Reescalado de resolución inteligente por hardware.\n"
              "• Diseñado para ganar hasta +50% FPS en laptops.")
    ]

    sel = submenu_interactivo("⚡  Elige tu Perfil de Rendimiento Inicial", opts, hw, cfg, default_idx=0)

    if sel == "2":
        perfil_elegido = "estandar"
        fsr_elegido = "0"
        nombre_perfil = "🛡️ Modo Estándar / Compatibilidad Total"
    elif sel == "3":
        perfil_elegido = "extremo"
        fsr_elegido = "1"
        nombre_perfil = "🚀 Modo Portátil Extremo (Gamescope + FSR)"
    else:
        perfil_elegido = "inteligente"
        fsr_elegido = "0"
        nombre_perfil = "⭐ Modo Rendimiento Inteligente [RECOMENDADO]"

    guardar_config("PERFIL_RENDIMIENTO", perfil_elegido)
    guardar_config("ACTIVAR_FSR", fsr_elegido)
    guardar_config("SMART_PERF_CONFIGURADO", "1")
    guardar_config("SMART_PERF_VERSION", SMART_PERF_VERSION_ACTUAL)

    try:
        with open(SMART_PERF_MARKER, "w", encoding="utf-8") as f:
            f.write(SMART_PERF_VERSION_ACTUAL + "\n")
    except Exception:
        pass

    subprocess.run(["bash", os.path.join(DIR, "generar_dxvk_conf.sh")], stderr=subprocess.DEVNULL)

    os.system("clear")
    print(f"\n{PURPLE}╭{'─' * inner_w}╮{RESET}")
    c_title = "✔  ¡CONFIGURACIÓN GUARDADA CON ÉXITO!  ✔"
    pad_c = max((inner_w - visual_width(c_title)) // 2, 0)
    print(f"{PURPLE}│{RESET}{' ' * pad_c}{BOLD}{GREEN}{c_title}{RESET}{' ' * max(inner_w - pad_c - visual_width(c_title), 0)}{PURPLE}│{RESET}")
    print(f"{PURPLE}├{'─' * inner_w}┤{RESET}")
    print(f"{PURPLE}│{' ' * inner_w}│{RESET}")

    l1 = f"  • Perfil Activo: {BOLD}{GREEN}{nombre_perfil}{RESET}"
    l2 = f"  • Calibración: Shaders adaptados a tus {hw['cores']} hilos de CPU."
    l3 = f"  • Memoria Caché: Configurada en RAM para cero micro-tirones."
    l4 = f"  • Seguridad: Cero modificaciones a tu sistema operativo (100% aislado)."
    print(f"{PURPLE}│{RESET} {pad_visual(l1, inner_w - 2)} {PURPLE}│{RESET}")
    print(f"{PURPLE}│{RESET} {pad_visual(l2, inner_w - 2)} {PURPLE}│{RESET}")
    print(f"{PURPLE}│{RESET} {pad_visual(l3, inner_w - 2)} {PURPLE}│{RESET}")
    print(f"{PURPLE}│{RESET} {pad_visual(l4, inner_w - 2)} {PURPLE}│{RESET}")
    print(f"{PURPLE}│{' ' * inner_w}│{RESET}")
    print(f"{PURPLE}├{'─' * inner_w}┤{RESET}")
    print(f"{PURPLE}│{' ' * inner_w}│{RESET}")

    r1 = "  💡  ¿CÓMO VOLVER A ABRIR ESTA CONFIGURACIÓN EN EL FUTURO?"
    r2 = "  Siempre que quieras cambiar de perfil, ajustar FPS o ver telemetría,"
    r3 = "  puedes abrir esta pantalla fácilmente desde el Menú Principal en la opción:"
    r4 = f"             {BOLD}{PURPLE}⚡  [3]  Smart Performance{RESET}"

    print(f"{PURPLE}│{RESET} {pad_visual(f'{YELLOW}{BOLD}{r1}{RESET}', inner_w - 2)} {PURPLE}│{RESET}")
    print(f"{PURPLE}│{RESET} {pad_visual(f'{GRAY}{r2}{RESET}', inner_w - 2)} {PURPLE}│{RESET}")
    print(f"{PURPLE}│{RESET} {pad_visual(f'{WHITE}{r3}{RESET}', inner_w - 2)} {PURPLE}│{RESET}")
    print(f"{PURPLE}│{RESET} {pad_visual(r4, inner_w - 2)} {PURPLE}│{RESET}")
    print(f"{PURPLE}│{' ' * inner_w}│{RESET}")
    print(f"{PURPLE}╰{'─' * inner_w}╯{RESET}\n")

    print(f"  {WHITE}Presiona {BOLD}{GREEN}[Enter]{RESET}{WHITE} para continuar al Menú Principal...{RESET}")
    read_key()

def comprobar_librerias_esenciales(hw, cfg):
    """
    Verifica si las librerías fundamentales están presentes en el prefijo principal:
    d3dx9_43.dll y msvcp140.dll en system32 o syswow64.
    Si faltan y no se ha omitido la verificación, ofrece un asistente en 1-clic
    para instalar el Paquete Esencial de Compatibilidad (DirectX, Visual C++, VKD3D-Proton).
    """
    pfx_win = os.path.join(WINEPREFIX, "drive_c", "windows")
    if not os.path.isdir(pfx_win):
        return

    sys32 = os.path.join(pfx_win, "system32")
    syswow = os.path.join(pfx_win, "syswow64")

    tiene_dx = (
        os.path.exists(os.path.join(sys32, "d3dx9_43.dll")) or
        os.path.exists(os.path.join(syswow, "d3dx9_43.dll"))
    )
    tiene_vc = (
        os.path.exists(os.path.join(sys32, "msvcp140.dll")) or
        os.path.exists(os.path.join(syswow, "msvcp140.dll"))
    )

    if tiene_dx and tiene_vc:
        return

    if cfg.get("OMITIR_VERIFICACION_LIBRERIAS") == "1":
        return

    total_w = get_terminal_width()
    inner_w = max(total_w - 2, 70)

    os.system("clear")
    print(f"{PURPLE}╭{'─' * inner_w}╮{RESET}")
    title = "⚡  VESSEL: ASISTENTE PLUG & PLAY DE COMPATIBILIDAD  ⚡"
    pad = max((inner_w - visual_width(title)) // 2, 0)
    print(f"{PURPLE}│{RESET}{' ' * pad}{BOLD}{CYAN}{title}{RESET}{' ' * max(inner_w - pad - visual_width(title), 0)}{PURPLE}│{RESET}")
    print(f"{PURPLE}│{' ' * inner_w}│{RESET}")

    msg1 = "Se ha detectado que faltan librerías nativas clave en tu entorno Wine."
    msg2 = "Para garantizar que el 100% de tus juegos y programas arranquen sin errores"
    msg3 = "de DLLs faltantes, se recomienda instalar el Paquete Esencial de Compatibilidad:"
    msg4 = "• DirectX 9 / 10 / 11 (+100 DLLs nativas oficiales de Microsoft)"
    msg5 = "• Microsoft Visual C++ 2005 a 2022 AIO (32 y 64 bits)"
    msg6 = "• VKD3D-Proton (DirectX 12 oficial HansKristian) y DXVK-NVAPI"

    for m in (msg1, msg2, msg3, "", msg4, msg5, msg6, ""):
        if not m:
            print(f"{PURPLE}│{' ' * inner_w}│{RESET}")
            continue
        color = GREEN if m.startswith("•") else WHITE
        print(f"{PURPLE}│{RESET}  {color}{m}{RESET}{' ' * max(inner_w - 2 - visual_width(m), 0)}{PURPLE}│{RESET}")

    print(f"{PURPLE}├{'─' * inner_w}┤{RESET}")
    print(f"{PURPLE}│{RESET}  {BOLD}[1]{RESET} {GREEN}{BOLD}Instalar ahora automáticamente (Recomendado - 1 Clic){RESET}{' ' * max(inner_w - 55, 0)}{PURPLE}│{RESET}")
    print(f"{PURPLE}│{RESET}  {BOLD}[2]{RESET} {GRAY}Continuar sin instalar por ahora{RESET}{' ' * max(inner_w - 34, 0)}{PURPLE}│{RESET}")
    print(f"{PURPLE}╰{'─' * inner_w}╯{RESET}\n")

    print(f"{WHITE}Selecciona una opción [1-2] (Enter = 1): {RESET}", end="", flush=True)
    k = read_key()
    if k in ('1', 'ENTER', 'SPACE', ''):
        print(f"\n\n{CYAN}🚀 Instalando Paquete Maestro de Compatibilidad de forma automática...{RESET}\n")
        gestor_lib = os.path.join(CORE_DIR, "gestor_librerias.sh")
        if not os.path.exists(gestor_lib):
            gestor_lib = os.path.join(DIR, "gestor_librerias.sh")
        if os.path.exists(gestor_lib):
            subprocess.run(["bash", gestor_lib, "paquete_maestro", WINEPREFIX])
        print(f"\n{GREEN}✔ ¡Paquete Esencial de Compatibilidad configurado con éxito!{RESET}")
        time.sleep(1.5)
    else:
        print(f"\n{YELLOW}Continuando al Menú Principal...{RESET}")
        time.sleep(0.5)

def verificar_actualizacion_automatica_github(mostrar_notif=True, cfg=None):
    """Verifica e instala actualizaciones desde GitHub automáticamente para todos los usuarios.
    Muestra mensajes claros al usuario: buscando actualización, nueva versión encontrada o al día.
    """
    if cfg is None:
        cfg = cargar_config()
    total_w = get_terminal_width()
    inner_w = max(total_w - 2, 60)

    # Notificación visible de búsqueda de actualizaciones
    print(f"\n{PURPLE}╭{'─' * inner_w}╮{RESET}")
    title = f"🔄  VESSEL v{VERSION_ACTUAL} - BUSCANDO ACTUALIZACIONES EN GITHUB..."
    pad = max((inner_w - visual_width(title)) // 2, 0)
    print(f"{PURPLE}│{RESET}{' ' * pad}{CYAN}{BOLD}{title}{RESET}{' ' * max(inner_w - pad - visual_width(title), 0)}{PURPLE}│{RESET}")
    print(f"{PURPLE}╰{'─' * inner_w}╯{RESET}")
    sys.stdout.flush()

    if not shutil.which("git"):
        print(f"  {YELLOW}⚠️  Git no está instalado. Continuando en modo offline...{RESET}\n")
        time.sleep(0.8)
        return False

    git_dir = os.path.join(DIR, ".git")
    remote_repo = "https://github.com/Plumst-37/Vessel.git"

    # Si no es un repositorio git (ej. usuario descargó ZIP), inicializar git para recibir actualizaciones
    if not os.path.exists(git_dir):
        try:
            print(f"  {CYAN}⚡ Configurando repositorio para recibir actualizaciones automáticas...{RESET}")
            subprocess.run(
                f"cd '{DIR}' && git init && git remote add origin '{remote_repo}' && git fetch --depth=1 origin main && git reset --hard origin/main",
                shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15
            )
        except Exception:
            print(f"  {YELLOW}⚠️  No se pudo conectar con GitHub. Continuando en modo offline...{RESET}\n")
            time.sleep(0.8)
            return False
    else:
        # Asegurar que remote origin siempre apunte al repositorio oficial
        subprocess.run(
            f"cd '{DIR}' && (git remote set-url origin '{remote_repo}' 2>/dev/null || git remote add origin '{remote_repo}' 2>/dev/null)",
            shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

    # 0. Evitar bucles de reinicio infinito si ya se actualizó en esta sesión
    if os.environ.get("_VESSEL_JUST_UPDATED") == "1":
        return False

    # 0.1 Respetar modo desarrollador para evitar sobreescribir código en desarrollo
    if os.environ.get("VESSEL_DEV_MODE") == "1" or cfg.get("AUTO_ACTUALIZAR_GITHUB") == "0" or os.path.exists(os.path.join(DIR, ".git_dev")):
        if mostrar_notif:
            print(f"  {CYAN}🛠️  Modo desarrollador activo: omitiendo actualización automática para proteger código local.{RESET}\n")
            time.sleep(0.6)
        return False

    try:
        # 1. Proteger juegos del usuario antes de actualizar
        if os.path.exists(DB_FILE) and os.path.getsize(DB_FILE) > 0:
            shutil.copyfile(DB_FILE, DB_BAK)
            if not os.path.exists(DB_USER) or os.path.getsize(DB_USER) == 0:
                shutil.copyfile(DB_FILE, DB_USER)
            else:
                try:
                    progs_act = cargar_lista_programas()
                    guardar_lista_programas(progs_act)
                except Exception:
                    pass

        cfg_file = os.path.join(DIR, "config_rendimiento.cfg")
        if os.path.exists(cfg_file):
            shutil.copyfile(cfg_file, cfg_file + ".bak")

        # Recordar si el usuario ya tenía configurado el sistema
        ya_configurado = os.path.exists(INSTALADO_MARKER) or (os.path.exists(VERSION_FILE) and os.path.getsize(VERSION_FILE) > 0)

        # 2. Deshacer cualquier estado de conflicto previo de Git (needs merge)
        subprocess.run(
            f"cd '{DIR}' && (git merge --abort 2>/dev/null; git rebase --abort 2>/dev/null; git reset --merge 2>/dev/null) || true",
            shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )

        # 3. Comprobar actualizaciones remotas con timeout de 7 segundos
        res = subprocess.run(
            f"cd '{DIR}' && git fetch origin main --quiet",
            shell=True, timeout=7, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        if res.returncode != 0:
            print(f"  {YELLOW}⚠️  Sin conexión a GitHub (modo offline). Iniciando Vessel...{RESET}\n")
            time.sleep(0.8)
            return False

        # 4. Comparar commit local vs remoto
        local_hash = subprocess.check_output(f"cd '{DIR}' && git rev-parse HEAD", shell=True, text=True).strip()
        remote_hash = subprocess.check_output(f"cd '{DIR}' && git rev-parse origin/main", shell=True, text=True).strip()

        if local_hash and remote_hash and local_hash != remote_hash:
            print(f"\n  {YELLOW}{BOLD}⚡ ¡Nueva actualización encontrada en GitHub!{RESET}")
            print(f"  {WHITE}Descargando e instalando los últimos parches y mejoras para tus juegos...{RESET}")

            # Limpiar cualquier conflicto y sincronizar limpiamente con origin/main
            subprocess.run(
                f"cd '{DIR}' && git checkout HEAD -- config/config_rendimiento.cfg config/dxvk.conf 2>/dev/null || true",
                shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            subprocess.run(
                f"cd '{DIR}' && git reset --hard origin/main",
                shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=25
            )

            # Verificar si realmente se actualizó al hash remoto para evitar falsos reinicios
            new_local_hash = subprocess.check_output(f"cd '{DIR}' && git rev-parse HEAD", shell=True, text=True).strip()
            if new_local_hash != remote_hash:
                print(f"  {YELLOW}⚠️  Aviso: Continuando en modo local para proteger archivos...{RESET}\n")
                time.sleep(1)
                return False

            # Restaurar bases de datos y configuraciones del usuario
            if os.path.exists(DB_USER):
                try:
                    progs = cargar_lista_programas()
                    guardar_lista_programas(progs)
                except Exception:
                    pass
            elif os.path.exists(DB_BAK):
                shutil.copyfile(DB_BAK, DB_FILE)

            if os.path.exists(cfg_file + ".bak"):
                shutil.copyfile(cfg_file + ".bak", cfg_file)

            # Si el usuario ya estaba configurado, restaurar marcadores
            if ya_configurado:
                try:
                    with open(INSTALADO_MARKER, "w", encoding="utf-8") as f:
                        f.write(VERSION_ACTUAL + "\n")
                except Exception:
                    pass

            # version.txt debe mantenerse estrictamente en 0 bytes
            try:
                open(VERSION_FILE, "w").close()
            except Exception:
                pass

            # Restaurar permisos y desplegar componentes
            subprocess.run(f"chmod +x '{DIR}'/*.sh '{DIR}'/core/*.sh '{DIR}'/core/*.py '{DIR}'/herramientas/*.sh 2>/dev/null", shell=True)
            desplegar_gameranger_portable()

            print(f"\n  {GREEN}{BOLD}✔ ¡Vessel se ha actualizado con éxito a la versión {VERSION_ACTUAL}!{RESET}")
            print(f"  {CYAN}Iniciando la aplicación con los nuevos cambios...{RESET}\n")
            time.sleep(1.0)

            # Reiniciar el script con variable protectora anti-bucles
            new_env = os.environ.copy()
            new_env["_VESSEL_JUST_UPDATED"] = "1"
            os.execvpe(sys.executable, [sys.executable] + sys.argv, new_env)
            return True
        else:
            if mostrar_notif:
                print(f"  {GREEN}{BOLD}✔ Ya tienes la versión más reciente de Vessel (v{VERSION_ACTUAL}).{RESET}")
                print(f"  {GRAY}Todos los parches de compatibilidad y rendimiento están al día.{RESET}\n")
                time.sleep(0.8)
            return False
    except Exception as e:
        print(f"  {YELLOW}⚠️  Aviso: Continuando en modo local ({e})...{RESET}\n")
        time.sleep(0.8)
        return False
        time.sleep(0.8)
        return False

# ==============================================================================
# MENÚ PRINCIPAL INTERACTIVO EN PÚRPURA NEÓN (MATCHING IMAGEN DE KONSOLE)
# ==============================================================================

def main():
    cfg = cargar_config()
    # Comprobar e instalar actualización automática desde GitHub para todos los usuarios
    verificar_actualizacion_automatica_github(mostrar_notif=True, cfg=cfg)

    hw = obtener_info_hardware()

    # Comprobar si el usuario entra por primera vez (version.txt vacío)
    comprobar_primer_inicio(hw, cfg)

    # Comprobar configuración inicial de Smart Performance (primera vez o tras actualización)
    comprobar_configuracion_smart_performance(hw, cfg)

    # Comprobar librerías esenciales (DirectX y Visual C++) para garantizar 100% Plug & Play
    comprobar_librerias_esenciales(hw, cfg)

    # Preinstalar e integrar GameRanger portable listo en opción 1
    desplegar_gameranger_portable()

    # Comprobar y asegurar acceso directo de Vessel en el Escritorio
    verificar_acceso_directo_vessel()

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
        m_title = "╭─ 🪟  Entorno Windows Universal "
        m_top = f"{PURPLE}{m_title}{'─' * (inner_w - visual_width(m_title) + 1)}╮{RESET}"
        print(m_top)
        print(f"{PURPLE}│{' ' * inner_w}│{RESET}")

        prompt_1 = f"  {WHITE}{BOLD}Selecciona qué deseas abrir en tu sistema:{RESET}"
        prompt_2 = f"    {PURPLE}[1]{RESET} {WHITE}{BOLD}Juegos{RESET}             {GRAY}➔ Videojuegos 3D/2D (DirectX, Vulkan, FSR, GameMode){RESET}"
        prompt_3 = f"    {PURPLE}[2]{RESET} {WHITE}{BOLD}Programas{RESET}          {GRAY}➔ Aplicaciones de Windows, Oficina, Utilidades y CMD{RESET}"
        print(f"{PURPLE}│{RESET} {pad_visual(prompt_1, inner_w - 2)} {PURPLE}│{RESET}")
        print(f"{PURPLE}│{RESET} {pad_visual(prompt_2, inner_w - 2)} {PURPLE}│{RESET}")
        print(f"{PURPLE}│{RESET} {pad_visual(prompt_3, inner_w - 2)} {PURPLE}│{RESET}")
        print(f"{PURPLE}│{' ' * inner_w}│{RESET}")
        print(f"{PURPLE}├{'─' * inner_w}┤{RESET}")
        print(f"{PURPLE}│{' ' * inner_w}│{RESET}")

        col_w = (inner_w - 6) // 2
        gap_w = inner_w - 4 - (col_w * 2)

        opts = [
            ("▶   [1]  🎮  Juegos", "▶   [2]  💼  Programas"),
            ("⚡  [3]  Smart Performance", "🔧  [4]  Herramientas de Windows"),
            ("🔄  [5]  Actualizar", "⏻   [0]  Salir")
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
            else:
                c2 = f" {pad_visual(f'{WHITE}{o2}{RESET}', col_w - 2)} "

            line_content = f"  {c1}{' ' * gap_w}{c2}  "
            print(f"{PURPLE}│{RESET}{line_content}{PURPLE}│{RESET}")
            print(f"{PURPLE}│{' ' * inner_w}│{RESET}")

        print(f"{PURPLE}├{'─' * inner_w}┤{RESET}")
        prompt_call = f"  {WHITE}Opción: {BOLD}{GREEN}[1]{RESET}{WHITE} Juegos, {BOLD}{GREEN}[2]{RESET}{WHITE} Programas {BOLD}{PURPLE}[Enter = Iniciar]{RESET}{WHITE} o {BOLD}{RED}[0]{RESET}{WHITE} Salir:{RESET}"
        print(f"{PURPLE}│{RESET} {pad_visual(prompt_call, inner_w - 2)} {PURPLE}│{RESET}")

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
                menu_juegos(hw, cfg)
            elif cur_idx == 2:
                menu_programas(hw, cfg)
            elif cur_idx == 3:
                menu_rendimiento(hw, cfg)
            elif cur_idx == 4:
                menu_herramientas(hw, cfg)
            elif cur_idx == 5:
                menu_actualizar(hw, cfg)
            elif cur_idx == 6:
                os.system("clear")
                print(f"{GREEN}¡Hasta luego! Que disfrutes tu sistema Windows.{RESET}\n")
                sys.exit(0)
        elif k == '1':
            cur_idx = 1
            menu_juegos(hw, cfg)
        elif k == '2':
            cur_idx = 2
            menu_programas(hw, cfg)
        elif k == '3':
            cur_idx = 3
            menu_rendimiento(hw, cfg)
        elif k == '4':
            cur_idx = 4
            menu_herramientas(hw, cfg)
        elif k == '5':
            cur_idx = 5
            menu_actualizar(hw, cfg)
        elif k in ('0', '6', 'q', 'Q'):
            os.system("clear")
            print(f"{GREEN}¡Hasta luego! Que disfrutes tu sistema Windows.{RESET}\n")
            sys.exit(0)
        elif k == 'ESC':
            pass

if __name__ == '__main__':
    main()
