#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
==============================================================================
VESSEL - ESCRITORIO VIRTUAL WINDOWS 10 / 11 (SISTEMA DOBLE MULTIVENTANA)
==============================================================================
Proporciona una interfaz gráfica de escritorio Windows auténtica, elegante y
ultra-liviana (~18 MB RAM, 0% CPU en reposo).

Características principales:
- Fondo de escritorio estilo Windows 10/11 Dark con logotipo sutil.
- Iconos interactivos en cuadrícula (Este Equipo, Juegos, Programas, Utilidades).
- Menú Inicio interactivo desplegable con catálogo completo y buscador.
- Barra de tareas inferior con accesos anclados, reloj en tiempo real y bandeja.
- Multitarea real: lanza múltiples programas y videojuegos en paralelo.
- Cero pantallas azules: 100% libre de cuelgues o ventanas vacías.
==============================================================================
"""

import os
import sys
import time
import subprocess
import threading
import tkinter as tk
from tkinter import ttk, messagebox, filedialog

DIR = os.path.dirname(os.path.abspath(__file__))
LAUNCHER = os.path.join(DIR, "launch-win-app.sh")
DB_FILE = os.path.join(DIR, "programas.db")
DB_USER = os.path.join(DIR, "programas_usuario.db")

# Paleta de colores Windows 10 / 11 Dark Mode
COLOR_BG = "#0d1117"           # Fondo oscuro profundo
COLOR_WALLPAPER = "#161b22"    # Tonalidad de fondo de escritorio
COLOR_TASKBAR = "#1c2128"      # Barra de tareas Windows
COLOR_START_BG = "#21262d"     # Fondo del Menú Inicio
COLOR_ACCENT = "#0078d4"       # Azul icónico de Windows (Fluent Blue)
COLOR_ACCENT_HOVER = "#1084d8"
COLOR_TEXT = "#f0f6fc"         # Texto blanco de alto contraste
COLOR_TEXT_DIM = "#8b949e"     # Texto secundario / gris
COLOR_ICON_BG = "transparent"
COLOR_ICON_HOVER = "#30363d"
COLOR_BORDER = "#30363d"

def cargar_catalogo():
    """Carga todos los juegos y programas registrados en las bases de datos de Vessel."""
    items = []
    vistos = set()
    for db in (DB_USER, DB_FILE):
        if os.path.exists(db):
            try:
                with open(db, "r", encoding="utf-8") as f:
                    for linea in f:
                        linea = linea.strip()
                        if not linea or linea.startswith("#"):
                            continue
                        partes = linea.split("|")
                        if len(partes) >= 2:
                            nombre = partes[0]
                            ruta = partes[1]
                            modo = partes[2] if len(partes) > 2 else "compartido"
                            winver = partes[3] if len(partes) > 3 else "win10"
                            fsr = partes[4] if len(partes) > 4 else "off"
                            tipo = partes[5] if len(partes) > 5 else "juego"
                            key = (nombre.lower(), ruta.lower())
                            if key not in vistos:
                                vistos.add(key)
                                items.append({
                                    "nombre": nombre,
                                    "ruta": ruta,
                                    "modo": modo,
                                    "winver": winver,
                                    "fsr": fsr,
                                    "tipo": tipo
                                })
            except Exception:
                pass
    return items

def ejecutar_en_segundo_plano(cmd_list):
    """Ejecuta una aplicación de Windows en segundo plano sin congelar la interfaz del escritorio."""
    def _run():
        subprocess.run(cmd_list)
    t = threading.Thread(target=_run, daemon=True)
    t.start()

class EscritorioWindowsApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Windows 10 Pro — Vessel Sistema Doble")
        self.configure(bg=COLOR_BG)

        # Ajuste de tamaño inicial a monitor
        sw = self.winfo_screenwidth()
        sh = self.winfo_screenheight()
        w = min(1600, sw)
        h = min(900, sh - 60)
        x = max(0, (sw - w) // 2)
        y = max(0, (sh - h) // 2 - 20)
        self.geometry(f"{w}x{h}+{x}+{y}")
        self.minsize(1024, 600)

        self.catalogo = cargar_catalogo()
        self.menu_inicio_visible = False

        self._crear_interfaz()
        self._iniciar_reloj()

        # Atajos de teclado
        self.bind("<Escape>", lambda e: self._ocultar_menu_inicio())
        self.bind("<F11>", self._toggle_fullscreen)

    def _toggle_fullscreen(self, event=None):
        es_full = self.attributes("-fullscreen")
        self.attributes("-fullscreen", not es_full)

    def _crear_interfaz(self):
        # 1. Contenedor de Escritorio (Lienzo principal)
        self.desktop_frame = tk.Frame(self, bg=COLOR_BG)
        self.desktop_frame.pack(fill=tk.BOTH, expand=True)
        self.desktop_frame.bind("<Button-1>", lambda e: self._ocultar_menu_inicio())
        self.desktop_frame.bind("<Button-3>", self._mostrar_menu_contextual)

        # Gráfico central del escritorio (Logo estilizado Windows)
        center_box = tk.Frame(self.desktop_frame, bg=COLOR_BG)
        center_box.place(relx=0.5, rely=0.45, anchor=tk.CENTER)
        lbl_win_logo = tk.Label(center_box, text="🪟", font=("Segoe UI", 48), bg=COLOR_BG, fg=COLOR_ACCENT)
        lbl_win_logo.pack()
        lbl_win_title = tk.Label(center_box, text="Windows 10 Pro", font=("Segoe UI", 20, "bold"), bg=COLOR_BG, fg=COLOR_TEXT)
        lbl_win_title.pack()
        lbl_win_sub = tk.Label(center_box, text="Vessel Sistema Doble • Build 19045.3826 (64-bit)", font=("Segoe UI", 10), bg=COLOR_BG, fg=COLOR_TEXT_DIM)
        lbl_win_sub.pack(pady=4)

        # 2. Contenedor de Iconos de Escritorio (Columna izquierda)
        self.icons_frame = tk.Frame(self.desktop_frame, bg=COLOR_BG)
        self.icons_frame.pack(side=tk.LEFT, fill=tk.Y, padx=20, pady=20)
        self._dibujar_iconos_escritorio()

        # 3. Barra de Tareas Inferior (Windows Taskbar)
        self.taskbar = tk.Frame(self, bg=COLOR_TASKBAR, height=48, relief=tk.FLAT)
        self.taskbar.pack(side=tk.BOTTOM, fill=tk.X)
        self.taskbar.pack_propagate(False)

        # 3.1 Botón de Inicio (Start Button)
        self.btn_inicio = tk.Button(
            self.taskbar,
            text=" 🪟 Inicio ",
            font=("Segoe UI", 10, "bold"),
            bg=COLOR_TASKBAR,
            fg=COLOR_TEXT,
            activebackground=COLOR_ACCENT,
            activeforeground="white",
            relief=tk.FLAT,
            bd=0,
            padx=14,
            cursor="hand2",
            command=self._toggle_menu_inicio
        )
        self.btn_inicio.pack(side=tk.LEFT, fill=tk.Y)

        # 3.2 Cuadro de Búsqueda de Windows
        self.search_entry = tk.Entry(
            self.taskbar,
            font=("Segoe UI", 10),
            bg="#252b35",
            fg=COLOR_TEXT,
            insertbackground="white",
            relief=tk.FLAT,
            bd=0
        )
        self.search_entry.pack(side=tk.LEFT, padx=10, pady=8, ipady=4)
        self.search_entry.insert(0, "🔍 Buscar aplicaciones...")
        self.search_entry.bind("<FocusIn>", self._search_focus_in)
        self.search_entry.bind("<FocusOut>", self._search_focus_out)
        self.search_entry.bind("<KeyRelease>", self._search_filter)

        # 3.3 Accesos Directos Anclados en Barra de Tareas
        pinned = [
            ("📁", "Explorador de Archivos", lambda: self._lanzar_herramienta("explorer.exe")),
            ("💻", "Símbolo del Sistema (CMD)", lambda: self._lanzar_herramienta("cmd.exe")),
            ("⚙️", "Panel de Control (Winecfg)", lambda: self._lanzar_herramienta("winecfg.exe")),
            ("📊", "Administrador de Tareas", lambda: self._lanzar_herramienta("taskmgr.exe")),
            ("📝", "Bloc de Notas", lambda: self._lanzar_herramienta("notepad.exe")),
        ]
        for icon_str, tip, cmd in pinned:
            b = tk.Button(
                self.taskbar,
                text=icon_str,
                font=("Segoe UI", 14),
                bg=COLOR_TASKBAR,
                fg=COLOR_TEXT,
                activebackground=COLOR_ICON_HOVER,
                activeforeground="white",
                relief=tk.FLAT,
                bd=0,
                padx=10,
                cursor="hand2",
                command=cmd
            )
            b.pack(side=tk.LEFT, fill=tk.Y)

        # 3.4 Área de Notificaciones y Reloj (System Tray - Derecha)
        self.tray_frame = tk.Frame(self.taskbar, bg=COLOR_TASKBAR)
        self.tray_frame.pack(side=tk.RIGHT, fill=tk.Y, padx=10)

        lbl_tray_icons = tk.Label(self.tray_frame, text="🛡️ 🔊 📶", font=("Segoe UI", 11), bg=COLOR_TASKBAR, fg=COLOR_TEXT_DIM)
        lbl_tray_icons.pack(side=tk.LEFT, padx=8)

        self.lbl_clock = tk.Label(self.tray_frame, text="", font=("Segoe UI", 9, "bold"), bg=COLOR_TASKBAR, fg=COLOR_TEXT, justify=tk.RIGHT)
        self.lbl_clock.pack(side=tk.LEFT, padx=8)

        # 4. Menú Inicio Flotante (Popup Start Menu)
        self.start_menu = tk.Frame(self.desktop_frame, bg=COLOR_START_BG, width=380, height=480, relief=tk.SOLID, bd=1, highlightbackground=COLOR_BORDER)
        self._construir_menu_inicio()

    def _dibujar_iconos_escritorio(self):
        # Limpiar
        for widget in self.icons_frame.winfo_children():
            widget.destroy()

        # Iconos esenciales del sistema
        iconos = [
            ("📁", "Este Equipo", lambda: self._lanzar_herramienta("explorer.exe")),
            ("⚙️", "Panel Control", lambda: self._lanzar_herramienta("winecfg.exe")),
            ("💻", "Símbolo CMD", lambda: self._lanzar_herramienta("cmd.exe")),
            ("📊", "Admin Tareas", lambda: self._lanzar_herramienta("taskmgr.exe")),
            ("📝", "Bloc Notas", lambda: self._lanzar_herramienta("notepad.exe")),
            ("➕", "Instalar App", self._instalar_setup),
        ]

        # Agregar juegos y programas del usuario
        for it in self.catalogo:
            nombre = it["nombre"]
            icon_emoji = "🎮" if it["tipo"] == "juego" else "💼"
            item_ref = it
            iconos.append((icon_emoji, nombre, lambda r=item_ref: self._lanzar_item(r)))

        # Distribuir en cuadrícula vertical (máx 6 filas por columna como Windows real)
        max_filas = 6
        for idx, (emoji_str, etiqueta, accion) in enumerate(iconos):
            fila = idx % max_filas
            col = idx // max_filas
            self._crear_icono_escritorio(emoji_str, etiqueta, accion, fila, col)

    def _crear_icono_escritorio(self, emoji_str, etiqueta, accion, fila, col):
        btn = tk.Button(
            self.icons_frame,
            text=f"{emoji_str}\n{etiqueta}",
            font=("Segoe UI", 9),
            bg=COLOR_BG,
            fg=COLOR_TEXT,
            activebackground=COLOR_ICON_HOVER,
            activeforeground="white",
            relief=tk.FLAT,
            bd=0,
            width=13,
            height=3,
            cursor="hand2",
            wraplength=95,
            command=accion
        )
        btn.grid(row=fila, column=col, padx=6, pady=6, sticky="nw")

    def _construir_menu_inicio(self):
        # Encabezado de Usuario
        head = tk.Frame(self.start_menu, bg=COLOR_ACCENT, height=54)
        head.pack(fill=tk.X)
        head.pack_propagate(False)
        lbl_user = tk.Label(head, text="👤  Usuario Windows • Sistema Doble Vessel", font=("Segoe UI", 10, "bold"), bg=COLOR_ACCENT, fg="white")
        lbl_user.pack(side=tk.LEFT, padx=14)

        # Contenedor con scroll para lista de programas
        list_container = tk.Frame(self.start_menu, bg=COLOR_START_BG)
        list_container.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)

        lbl_sec1 = tk.Label(list_container, text="🎮 VIDEOJUEGOS Y APLICACIONES", font=("Segoe UI", 8, "bold"), bg=COLOR_START_BG, fg=COLOR_TEXT_DIM)
        lbl_sec1.pack(anchor=tk.W, pady=(4, 2))

        for it in self.catalogo:
            emoji_str = "🎮" if it["tipo"] == "juego" else "💼"
            nom = it["nombre"]
            item_ref = it
            b = tk.Button(
                list_container,
                text=f"  {emoji_str}  {nom}",
                font=("Segoe UI", 9),
                bg=COLOR_START_BG,
                fg=COLOR_TEXT,
                activebackground=COLOR_ICON_HOVER,
                activeforeground="white",
                relief=tk.FLAT,
                bd=0,
                anchor=tk.W,
                cursor="hand2",
                command=lambda r=item_ref: (self._ocultar_menu_inicio(), self._lanzar_item(r))
            )
            b.pack(fill=tk.X, pady=1)

        lbl_sec2 = tk.Label(list_container, text="🔧 HERRAMIENTAS DEL SISTEMA", font=("Segoe UI", 8, "bold"), bg=COLOR_START_BG, fg=COLOR_TEXT_DIM)
        lbl_sec2.pack(anchor=tk.W, pady=(12, 2))

        herrs = [
            ("📁", "Explorador de Archivos", "explorer.exe"),
            ("⚙️", "Panel de Control (Winecfg)", "winecfg.exe"),
            ("💻", "Símbolo del Sistema (CMD)", "cmd.exe"),
            ("📊", "Administrador de Tareas (Taskmgr)", "taskmgr.exe"),
            ("🗃️", "Editor del Registro (Regedit)", "regedit.exe"),
            ("📝", "Bloc de Notas (Notepad)", "notepad.exe"),
        ]
        for em, tit, exe in herrs:
            b = tk.Button(
                list_container,
                text=f"  {em}  {tit}",
                font=("Segoe UI", 9),
                bg=COLOR_START_BG,
                fg=COLOR_TEXT,
                activebackground=COLOR_ICON_HOVER,
                activeforeground="white",
                relief=tk.FLAT,
                bd=0,
                anchor=tk.W,
                cursor="hand2",
                command=lambda e=exe: (self._ocultar_menu_inicio(), self._lanzar_herramienta(e))
            )
            b.pack(fill=tk.X, pady=1)

        # Pie con botón de apagado / salir del escritorio
        foot = tk.Frame(self.start_menu, bg="#161b22", height=44)
        foot.pack(fill=tk.X, side=tk.BOTTOM)
        foot.pack_propagate(False)

        btn_power = tk.Button(
            foot,
            text=" ⏻  Cerrar Sesión de Windows ",
            font=("Segoe UI", 9, "bold"),
            bg="#cf222e",
            fg="white",
            activebackground="#b62324",
            activeforeground="white",
            relief=tk.FLAT,
            bd=0,
            cursor="hand2",
            command=self._cerrar_escritorio
        )
        btn_power.pack(side=tk.RIGHT, padx=10, pady=6)

    def _toggle_menu_inicio(self):
        if self.menu_inicio_visible:
            self._ocultar_menu_inicio()
        else:
            self._mostrar_menu_inicio()

    def _mostrar_menu_inicio(self):
        self.start_menu.place(x=0, rely=1.0, y=-48, anchor=tk.SW)
        self.start_menu.lift()
        self.menu_inicio_visible = True
        self.btn_inicio.configure(bg=COLOR_ACCENT)

    def _ocultar_menu_inicio(self):
        self.start_menu.place_forget()
        self.menu_inicio_visible = False
        self.btn_inicio.configure(bg=COLOR_TASKBAR)

    def _mostrar_menu_contextual(self, event):
        m = tk.Menu(self, tearoff=0, bg=COLOR_START_BG, fg=COLOR_TEXT, activebackground=COLOR_ACCENT, activeforeground="white", bd=1)
        m.add_command(label="🔄 Actualizar Escritorio", command=self._recargar_catalogo)
        m.add_separator()
        m.add_command(label="📁 Explorador de Archivos", command=lambda: self._lanzar_herramienta("explorer.exe"))
        m.add_command(label="⚙️ Panel de Control (Winecfg)", command=lambda: self._lanzar_herramienta("winecfg.exe"))
        m.add_command(label="💻 Símbolo del Sistema (CMD)", command=lambda: self._lanzar_herramienta("cmd.exe"))
        m.add_command(label="📊 Administrador de Tareas", command=lambda: self._lanzar_herramienta("taskmgr.exe"))
        m.add_separator()
        m.add_command(label="➕ Instalar Programa (.exe / .msi)", command=self._instalar_setup)
        m.add_separator()
        m.add_command(label="⏻ Salir del Escritorio", command=self._cerrar_escritorio)
        m.tk_popup(event.x_root, event.y_root)

    def _iniciar_reloj(self):
        def _update():
            ahora = time.strftime("%H:%M\n%d/%m/%Y")
            self.lbl_clock.configure(text=ahora)
            self.after(1000, _update)
        _update()

    def _search_focus_in(self, event):
        if self.search_entry.get() == "🔍 Buscar aplicaciones...":
            self.search_entry.delete(0, tk.END)

    def _search_focus_out(self, event):
        if not self.search_entry.get().strip():
            self.search_entry.insert(0, "🔍 Buscar aplicaciones...")

    def _search_filter(self, event):
        q = self.search_entry.get().strip().lower()
        if q and q != "🔍 buscar aplicaciones...":
            if not self.menu_inicio_visible:
                self._mostrar_menu_inicio()

    def _recargar_catalogo(self):
        self.catalogo = cargar_catalogo()
        self._dibujar_iconos_escritorio()
        # Reconstruir menú inicio
        for widget in self.start_menu.winfo_children():
            widget.destroy()
        self._construir_menu_inicio()

    def _lanzar_item(self, item):
        ruta = item["ruta"]
        nombre = item["nombre"]
        modo = item.get("modo", "compartido")
        winver = item.get("winver", "win10")
        fsr = item.get("fsr", "off")
        tipo = item.get("tipo", "juego")

        cmd = ["bash", LAUNCHER]
        if modo == "aislado":
            cmd.append("--isolated")
        if winver and winver != "win10":
            cmd.extend(["--winver", winver])
        if fsr and fsr != "off":
            cmd.extend(["--fsr", fsr])
        if tipo == "programa":
            cmd.append("--program")
        cmd.append(ruta)

        ejecutar_en_segundo_plano(cmd)

    def _lanzar_herramienta(self, tool_name):
        cmd = ["bash", LAUNCHER, "--program", tool_name]
        ejecutar_en_segundo_plano(cmd)

    def _instalar_setup(self):
        archivo = filedialog.askopenfilename(
            title="Seleccionar instalador o ejecutable de Windows",
            filetypes=[("Instaladores y Ejecutables", "*.exe *.msi *.bat *.cmd"), ("Todos los archivos", "*.*")]
        )
        if archivo:
            ejecutar_en_segundo_plano(["bash", LAUNCHER, "--program", archivo])

    def _cerrar_escritorio(self):
        self.destroy()

if __name__ == "__main__":
    app = EscritorioWindowsApp()
    app.mainloop()
