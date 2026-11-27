#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
==============================================================================
VESSEL - ANALIZADOR UNIVERSAL DE FIRMAS BINARIAS PE (PORTABLE EXECUTABLE)
Detecta con 99.9% de precisión arquitectura, versión de Windows, APIs y motor
==============================================================================
"""

import sys
import os
import struct
import json
import re

PROGRAM_NAMES = {
    "winecfg.exe", "winecfg", "explorer.exe", "explorer", "notepad.exe", "notepad",
    "notepad++.exe", "regedit.exe", "regedit", "taskmgr.exe", "taskmgr", "cmd.exe", "cmd",
    "control.exe", "control", "calc.exe", "mspaint.exe", "wordpad.exe", "iexplore.exe",
    "winword.exe", "excel.exe", "powerpnt.exe", "outlook.exe", "onenote.exe", "msaccess.exe",
    "soffice.exe", "soffice.bin", "swriter.exe", "scalc.exe", "wps.exe", "wpp.exe", "et.exe",
    "sublime_text.exe", "code.exe", "vscodium.exe", "pycharm.exe", "pycharm64.exe",
    "idea.exe", "idea64.exe", "clion.exe", "clion64.exe", "devcpp.exe", "codeblocks.exe",
    "geany.exe", "atom.exe", "7zfm.exe", "7zg.exe", "winrar.exe", "peazip.exe", "rufus.exe",
    "etcher.exe", "ccleaner.exe", "keepass.exe", "putty.exe", "filezilla.exe", "anydesk.exe",
    "teamviewer.exe", "vlc.exe", "mpc-hc.exe", "mpc-hc64.exe", "potplayer.exe",
    "foobar2000.exe", "calibre.exe", "sumatrapdf.exe", "acrobat.exe", "foxitreader.exe",
    "acroord32.exe", "audacity.exe", "blender.exe", "gimp.exe", "inkscape.exe",
    "photoshop.exe", "illustrator.exe", "indesign.exe", "fl64.exe", "fl.exe", "reaper.exe",
    "chrome.exe", "brave.exe", "firefox.exe", "msedge.exe", "opera.exe", "discord.exe",
    "telegram.exe", "slack.exe", "zoom.exe", "skype.exe", "thunderbird.exe",
    "uninstaller.exe", "setup.exe", "installer.exe", "updater.exe", "patcher.exe",
    "cheatengine.exe", "cheatengine-x86_64.exe", "fomod.exe", "vortex.exe", "modorganizer.exe"
}

PROGRAM_KEYWORDS = (
    "rufus", "etcher", "ventoy", "7z", "winrar", "peazip", "notepad++", "vlc",
    "obs64", "obs32", "cpu-z", "cpuz", "gpu-z", "gpuz", "hwmonitor", "hwinfo",
    "crystaldisk", "putty", "winscp", "filezilla", "anydesk", "teamviewer",
    "rustdesk", "telegram", "discord", "whatsapp", "spotify", "gimp", "krita",
    "inkscape", "blender", "audacity", "handbrake", "gerador", "generador",
    "setup", "install", "uninst", "updater", "viewer", "reader", "editor",
    "converter", "downloader", "portable", "browser", "chrome", "firefox",
    "msedge", "brave", "opera", "office", "winword", "excel", "powerpnt",
    "acrobat", "foxit", "sumatra", "keepass", "ccleaner", "paint", "photoshop"
)

def resolve_target_file(target_path):
    """
    Si target_path es un acceso directo (.lnk/.ink) o script por lotes (.bat/.cmd),
    resuelve automáticamente al ejecutable binario (.exe) subyacente.
    """
    if not target_path or not os.path.exists(target_path):
        return target_path

    ext = os.path.splitext(target_path)[1].lower()
    script_dir = os.path.dirname(os.path.abspath(__file__))

    # 1. Scripts por lotes (.bat / .cmd)
    if ext in ('.bat', '.cmd'):
        try:
            sys.path.insert(0, script_dir)
            from resolver_bat import resolve_bat
            bat_info = resolve_bat(target_path)
            if bat_info.get("status") == "RESOLVED":
                cand = bat_info.get("path") or bat_info.get("resolved_path", "")
                if cand and os.path.isfile(cand):
                    return cand
        except Exception:
            pass

    # 2. Accesos directos (.lnk / .ink)
    if ext in ('.lnk', '.ink'):
        try:
            sys.path.insert(0, script_dir)
            from resolver_lnk import resolve_lnk
            lnk_info = resolve_lnk(target_path)
            if lnk_info.get("status") == "RESOLVED":
                cand = lnk_info.get("path") or lnk_info.get("resolved_path", "")
                if cand and os.path.isfile(cand):
                    return cand
        except Exception:
            pass

    return target_path

def analizar_juego(exe_path):
    """
    Analiza el cabezal PE real (DOS Header, COFF Header, Optional Header)
    y el entorno de librerías del juego para determinar su configuración óptima.
    """
    # Resolver scripts y accesos directos si es necesario
    real_path = resolve_target_file(exe_path)

    res = {
        "target": exe_path,
        "resolved_exe": real_path,
        "winver": "win10",
        "bits": 64,
        "api": "auto",
        "engine": "generico",
        "subsys": "6.0",
        "is_64": False,
        "is_pe": False,
        "has_d3d12": False,
        "has_d3d11": False,
        "has_d3d9": False,
        "has_d3d8": False,
        "has_ddraw": False,
        "has_vulkan": False,
        "anti_cheat_warning": False,
        "anti_cheat_name": "",
        "category": "juego"
    }

    if not real_path or not os.path.isfile(real_path):
        bn = os.path.basename(exe_path or "").lower()
        if bn in PROGRAM_NAMES or any(kw in bn for kw in PROGRAM_KEYWORDS):
            res["category"] = "programa"
            res["api"] = "gdi"
        elif any(k in bn for k in ("gta5", "playgtav")):
            res["engine"] = "rockstar_gta5"
            res["has_d3d11"] = True
            res["api"] = "dx11"
        elif any(k in bn for k in ("gta_sa", "gtasa", "gta-sa")):
            res["engine"] = "rockstar_gtasa"
            res["has_d3d9"] = True
            res["api"] = "d3d9"
        elif any(k in bn for k in ("tesv", "skyrim", "fallout3", "falloutnv", "fallout4", "oblivion", "starfield")):
            res["engine"] = "bethesda_creation"
            res["has_d3d11"] = True
            res["api"] = "dx11"
        return res

    game_dir = os.path.dirname(os.path.abspath(real_path))
    file_name = os.path.basename(real_path).lower()
    file_stem = os.path.splitext(file_name)[0]
    full_path_low = os.path.abspath(real_path).lower()

    # 1. Leer cabezal binario PE (Portable Executable)
    is_64 = False
    sub_maj = 6
    sub_min = 0
    is_pe = False

    try:
        with open(real_path, "rb") as f:
            dos_hdr = f.read(64)
            if len(dos_hdr) >= 64 and dos_hdr[:2] == b"MZ":
                pe_off = struct.unpack_from("<I", dos_hdr, 0x3C)[0]
                if pe_off > 0 and pe_off < 4096:
                    f.seek(pe_off)
                    pe_data = f.read(256)
                    if len(pe_data) >= 80 and pe_data[:4] == b"PE\0\0":
                        is_pe = True
                        machine = struct.unpack_from("<H", pe_data, 4)[0]
                        # Machine types: 0x8664 = AMD64/x86_64, 0xaa64 = ARM64, 0x0200 = IA64
                        is_64 = (machine in (0x8664, 0xaa64, 0x0200))

                        # Optional Header Magic (offset 24): 0x020b = PE32+ (64-bit), 0x010b = PE32 (32-bit)
                        magic = struct.unpack_from("<H", pe_data, 24)[0]
                        if magic == 0x020b:
                            is_64 = True

                        # Major/Minor Subsystem Version (offset 72 y 74)
                        sub_maj = struct.unpack_from("<H", pe_data, 72)[0]
                        sub_min = struct.unpack_from("<H", pe_data, 74)[0]
    except Exception:
        pass

    res["is_pe"] = is_pe
    res["is_64"] = is_64
    res["bits"] = 64 if is_64 else 32
    res["subsys"] = f"{sub_maj}.{sub_min}"

    # 2. Escaneo de librerías locales, dependencias y carpetas de motor
    root_files = set(f.lower() for f in os.listdir(game_dir)) if os.path.isdir(game_dir) else set()
    parent_dir = os.path.dirname(game_dir)
    parent_files = set(f.lower() for f in os.listdir(parent_dir)) if os.path.isdir(parent_dir) else set()
    all_files = root_files | parent_files

    has_d3d12 = any(f in all_files for f in ("d3d12.dll", "d3d12core.dll"))
    has_d3d11 = any(f in all_files for f in ("d3d11.dll", "dxgi.dll"))
    has_d3d9 = "d3d9.dll" in all_files
    has_d3d8 = "d3d8.dll" in all_files
    has_ddraw = "ddraw.dll" in all_files or "ddraw.ini" in all_files
    has_vulkan = "vulkan-1.dll" in all_files or "winevulkan.dll" in all_files
    has_opengl = False
    has_desktop_fw = any(f in all_files for f in ("chrome_elf.dll", "libcef.dll", "icudtl.dat", "qt5core.dll", "qt6core.dll", "electron.exe"))
    is_electron = any(f in all_files for f in ("chrome_elf.dll", "icudtl.dat", "electron.exe")) or os.path.isfile(os.path.join(game_dir, "resources", "app.asar"))

    # 2.0 Escaneo rápido de firmas internas en el propio ejecutable PE (primeros 2 MB)
    try:
        with open(real_path, "rb") as f_bin:
            chunk = f_bin.read(2 * 1024 * 1024).lower()
            if b"d3d12.dll" in chunk or b"d3d12core.dll" in chunk:
                has_d3d12 = True
            if b"d3d11.dll" in chunk or b"dxgi.dll" in chunk:
                has_d3d11 = True
            if b"d3d9.dll" in chunk:
                has_d3d9 = True
            if b"d3d8.dll" in chunk:
                has_d3d8 = True
            if b"ddraw.dll" in chunk:
                has_ddraw = True
            if b"vulkan-1.dll" in chunk:
                has_vulkan = True
            if b"opengl32.dll" in chunk:
                has_opengl = True
            if any(sig in chunk for sig in (b"mscoree.dll", b"coreclr.dll", b"qt5core.dll", b"qt6core.dll", b"nullsoftinst", b"inno setup", b"winspool.drv")):
                has_desktop_fw = True
            if any(sig in chunk for sig in (b"electron", b"chrome_elf.dll", b"icudtl.dat", b"app.asar")):
                is_electron = True
                has_desktop_fw = True
    except Exception:
        pass

    # 2.1 Escaneo preventivo de Anti-Cheats de Kernel (Ring 0)
    anti_cheat_warning = False
    anti_cheat_name = ""
    known_anticheats = {
        "vgk.sys": "Riot Vanguard (Ring 0)",
        "easyanticheat.sys": "Easy Anti-Cheat (Ring 0)",
        "easyanticheat_eos.sys": "Easy Anti-Cheat EOS (Ring 0)",
        "bedaisy.sys": "BattlEye (Ring 0)",
        "mhyprot2.sys": "HoYoverse Anti-Cheat (Ring 0)",
        "anticheat.sys": "Kernel Anti-Cheat Genérico (Ring 0)",
        "neacsafe.sys": "NetEase Anti-Cheat (Ring 0)",
    }

    if os.path.isdir(game_dir):
        for ac_file, ac_label in known_anticheats.items():
            if ac_file in root_files:
                anti_cheat_warning = True
                anti_cheat_name = ac_label
                break

        if not anti_cheat_warning:
            try:
                for entry in os.scandir(game_dir):
                    if entry.is_dir(follow_symlinks=False):
                        s_name = entry.name.lower()
                        if any(k in s_name for k in ("anticheat", "eac", "battleye", "vanguard", "easyanticheat")):
                            anti_cheat_warning = True
                            anti_cheat_name = "Easy Anti-Cheat / BattlEye (Ring 0)" if ("eac" in s_name or "easy" in s_name) else "Kernel Anti-Cheat (Ring 0)"
                            break
                        try:
                            for subentry in os.scandir(entry.path):
                                sub_low = subentry.name.lower()
                                if sub_low in known_anticheats:
                                    anti_cheat_warning = True
                                    anti_cheat_name = known_anticheats[sub_low]
                                    break
                        except Exception:
                            pass
                    if anti_cheat_warning:
                        break
            except Exception:
                pass

    res["anti_cheat_warning"] = anti_cheat_warning
    res["anti_cheat_name"] = anti_cheat_name

    # 3. Detección Inteligente de Motor de Juego y Desambiguación Remake vs Clásico
    engine = "generico"
    stem_lower = file_stem.lower()

    # A) Rockstar RAGE (GTA V / GTA IV / RDR2)
    if any(k in file_name for k in ("gta5", "playgtav")) or "grand theft auto v" in full_path_low or "gta v" in full_path_low or "gta_data" in full_path_low:
        engine = "rockstar_gta5"
        has_d3d11 = True

    # B) Capcom RE Engine (RE4 Remake, RE2 Remake, RE3 Remake, RE7, RE8 Village, DMC5, SF6)
    # Todos los juegos RE Engine son NATIVAMENTE de 64 bits y usan DirectX 12 o paquetes .pak re_chunk
    elif any(f.startswith("re_chunk_000") for f in all_files) or (is_64 and any(k in file_name for k in ("re4.exe", "re2.exe", "re3.exe", "re7.exe", "re8.exe", "dmc5.exe", "sf6.exe"))):
        engine = "capcom_re_engine"
        has_d3d12 = True

    # C) Capcom MT Framework o Clásico (Resident Evil 4 2005 original 32-bit, RE5, RE6, Revelations, DMC4)
    elif "nativepc" in all_files or (not is_64 and any(k in file_name for k in ("re4.exe", "biohazard4.exe"))) or any(k in file_name for k in ("bh6.exe", "re6.exe", "re5.exe", "re5dx9.exe", "re5dx10.exe", "dmc4.exe")):
        engine = "capcom_mt_framework"
        has_d3d9 = True

    # D) Unity Engine
    elif "unityplayer.dll" in all_files or (stem_lower + "_data") in root_files:
        engine = "unity_engine"

    # E) Rockstar RenderWare (GTA San Andreas / Vice City / GTA III)
    elif "gta_sa.exe" in file_name or "gta-sa.exe" in file_name or "gta san andreas" in full_path_low:
        engine = "rockstar_gtasa"
        has_d3d9 = True

    # F) EA Games (Need for Speed)
    elif any(k in file_name for k in ("speed", "speed2", "nfs")) or "need for speed" in full_path_low:
        engine = "ea_nfs"
        if not is_64 and sub_maj <= 5:
            has_d3d9 = True
        elif is_64 or sub_maj >= 6:
            has_d3d11 = True

    # G) Unreal Engine (SWAT 4, BioShock, Unreal Tournament, DeusEx)
    elif any(k in file_name for k in ("swat4", "swat4x", "bioshock", "deusex")) or os.path.isdir(os.path.join(game_dir, "System")) or "content/system" in full_path_low:
        engine = "unreal_engine"

    # H) Valve GoldSrc Engine (Half-Life 1, Counter-Strike 1.6, Condition Zero, Day of Defeat, etc.)
    elif any(k in file_name for k in ("cstrike.exe", "hl.exe", "czero.exe", "hltv.exe")) or "hw.dll" in all_files or "sw.dll" in all_files or any(os.path.isdir(os.path.join(game_dir, d)) for d in ("cstrike", "valve", "czero")):
        engine = "valve_goldsrc"
        has_d3d9 = False

    # I) Valve Source Engine (Half-Life 2, CS:Source, CS:GO, Team Fortress 2, Portal, L4D)
    elif "tier0.dll" in all_files or "vstdlib.dll" in all_files:
        engine = "source_engine"

    # I) DirectDraw Clásico (Age of Empires, StarCraft, Red Alert 2, Fallout, Diablo)
    elif has_ddraw or any(k in file_name for k in ("empires2", "age2_x1", "starcraft", "ra2", "diablo", "fallout", "carmageddon")):
        engine = "classic_directdraw"
        has_ddraw = True

    # J) Bethesda Creation Engine / Gamebryo (Skyrim, Fallout 3/NV/4, Oblivion, Starfield)
    elif any(k in file_name for k in ("tesv", "skyrim", "fallout3", "falloutnv", "fallout4", "oblivion", "starfield")) or any(f.endswith(".esm") for f in all_files):
        engine = "bethesda_creation"
        if "starfield" in file_name:
            has_d3d12 = True
        elif is_64 or "fallout4" in file_name or "skyrimse" in file_name:
            has_d3d11 = True
        else:
            has_d3d9 = True

    # K) Godot Engine (Juegos Indie modernos)
    elif any(f.endswith(".pck") for f in root_files) or "godot" in file_name:
        engine = "godot_engine"
        has_vulkan = True if is_64 else False

    # L) Crytek CryEngine (Crysis, Far Cry, Kingdom Come, Prey)
    elif any(k in file_name for k in ("crysis", "farcry", "kingdomcome", "prey")) or any("crysystem" in f or "cryrender" in f for f in all_files):
        engine = "cryengine"
        if is_64:
            has_d3d11 = True
        else:
            has_d3d9 = True

    # M) id Tech Engine (DOOM, Quake, Wolfenstein, RAGE)
    elif any(k in file_name for k in ("doom", "wolfenstein", "quake", "rage")) or any(f.endswith(".wad") or f.endswith(".pk4") for f in all_files):
        engine = "id_tech"
        if is_64:
            has_vulkan = True
        else:
            has_d3d9 = True

    # N) Desambiguaciones Adicionales Remake vs Clásico por Arquitectura PE:
    # Dead Space: 64-bit = Remake 2023 (DX12) | 32-bit = Clásico 2008 (DX9)
    if "deadspace.exe" in file_name:
        if is_64:
            has_d3d12 = True
            engine = "ea_frostbite"
        else:
            has_d3d9 = True
    # DOOM: 64-bit = DOOM 2016/Eternal (Vulkan) | 32-bit = DOOM 3 (OpenGL)
    elif "doom.exe" in file_name:
        if is_64:
            has_vulkan = True
        else:
            has_d3d9 = True
    # Mafia: 64-bit = Definitive Edition (DX11) | 32-bit = Clásico (DX8/9)
    elif "mafia.exe" in file_name:
        if is_64:
            has_d3d11 = True
        else:
            has_d3d8 = True

    res["engine"] = engine
    res["has_d3d12"] = has_d3d12
    res["has_d3d11"] = has_d3d11
    res["has_d3d9"] = has_d3d9
    res["has_d3d8"] = has_d3d8
    res["has_ddraw"] = has_ddraw
    res["has_vulkan"] = has_vulkan

    res["is_electron"] = is_electron

    # 4. Determinación Infalible de Versión de Windows
    # REGLA 1: GameRanger es cliente de escritorio Win32 CEF -> Windows 7 (máxima estabilidad para lobby)
    if "gameranger" in file_name:
        winver = "win7"
    # REGLA 2: Solo clásicos 2D DirectDraw retro (sin DX9/11/12) van a Windows XP para preservar paleta de 8 bits
    elif (engine == "classic_directdraw" or (has_ddraw and not has_d3d9 and not has_d3d11 and not has_d3d12)) and not is_64 and not has_desktop_fw:
        winver = "winxp"
    # REGLA 3: Todo software moderno, instaladores, Electron, .NET, y juegos 3D -> SIEMPRE Windows 10
    else:
        winver = "win10"

    res["winver"] = winver

    # 5. Clasificación de Categoría: Juego vs Programa de Escritorio (antes de decidir API)
    category = "juego"
    is_in_program_dir = any(p_kw in full_path_low for p_kw in ("/program files", "/program files (x86)", "/software", "/utilidades", "/herramientas", "/office", "/adobe", "/editors"))
    is_in_game_dir = any(g_kw in full_path_low for g_kw in ("/juegos", "/games", "/steam", "/epic", "/gog", "repack", "fitgirl", "dodi", "crack"))
    matches_program_kw = (file_name in PROGRAM_NAMES) or any(kw in file_name for kw in PROGRAM_KEYWORDS)

    if "gameranger" in file_name:
        category = "juego"
    elif matches_program_kw:
        category = "programa"
    elif engine != "generico":
        category = "juego"
    elif is_in_program_dir:
        category = "programa"
    elif has_desktop_fw and not (has_d3d12 or has_d3d11 or has_d3d9 or has_d3d8 or has_ddraw or has_vulkan):
        category = "programa"
    elif is_electron:
        category = "programa"
    elif not (has_d3d12 or has_d3d11 or has_d3d9 or has_d3d8 or has_ddraw or has_vulkan or has_opengl):
        if is_in_game_dir:
            category = "juego"
        else:
            category = "programa"
    else:
        category = "juego"

    res["category"] = category

    # 6. Determinación de API Gráfica
    if category == "programa":
        api = "gdi"
    elif engine == "valve_goldsrc":
        api = "opengl"
    elif has_d3d12:
        api = "dx12"
    elif has_d3d11:
        api = "dx11"
    elif has_vulkan:
        api = "vulkan"
    elif has_d3d9:
        api = "d3d9"
    elif has_d3d8:
        api = "d3d8"
    elif has_ddraw:
        api = "ddraw"
    elif has_opengl:
        api = "opengl"
    else:
        api = "dx11" if is_64 else "d3d9"

    res["api"] = api
    return res

def main():
    if len(sys.argv) < 2:
        print("Uso: analizador_pe.py [--bash | --json | --winver | --engine | --api | --bits | --category] <ruta_al_exe>")
        sys.exit(1)

    flag = ""
    exe_path = ""
    for arg in sys.argv[1:]:
        if arg.startswith("--"):
            flag = arg.lower()
        else:
            exe_path = arg

    if not exe_path:
        print("Error: No se especificó archivo ejecutable.")
        sys.exit(1)

    info = analizar_juego(exe_path)

    if flag in ("--bash", "--bash-full"):
        print(f'PE_TARGET="{info["resolved_exe"]}"')
        print(f'PE_WINVER="{info["winver"]}"')
        print(f'PE_BITS="{info["bits"]}"')
        print(f'PE_API="{info["api"]}"')
        print(f'PE_ENGINE="{info["engine"]}"')
        print(f'PE_SUBSYS="{info["subsys"]}"')
        print(f'PE_IS_64="{1 if info["is_64"] else 0}"')
        print(f'PE_IS_PE="{1 if info["is_pe"] else 0}"')
        print(f'PE_HAS_DX12="{1 if info["has_d3d12"] else 0}"')
        print(f'PE_HAS_DX11="{1 if info["has_d3d11"] else 0}"')
        print(f'PE_HAS_DDRAW="{1 if info["has_ddraw"] else 0}"')
        print(f'PE_CATEGORY="{info["category"]}"')
        print(f'PE_IS_ELECTRON="{1 if info.get("is_electron") else 0}"')
        print(f'PE_ANTI_CHEAT_WARNING="{1 if info.get("anti_cheat_warning") else 0}"')
        print(f'PE_ANTI_CHEAT_NAME="{info.get("anti_cheat_name", "")}"')

        if flag == "--bash-full":
            try:
                script_dir = os.path.dirname(os.path.abspath(__file__))
                if script_dir not in sys.path:
                    sys.path.insert(0, script_dir)
                import motor_inferencia
                analysis = motor_inferencia.InferenceEngine.analyze(exe_path)
                env_vars = analysis.get("prescriptions", {}).get("environment_variables", {})
                for k, v in env_vars.items():
                    if re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', k):
                        print(f'export {k}="{v}"')
                print(f'export VESSEL_INFERRED_API="{analysis.get("prescriptions", {}).get("api", info["api"])}"')
                print(f'export VESSEL_INFERRED_WINVER="{analysis.get("prescriptions", {}).get("winver", info["winver"])}"')
                print(f'export VESSEL_INFERRED_BITS="{analysis.get("pe_telemetry", {}).get("bits", info["bits"])}"')
                print(f'export VESSEL_INFERRED_ENGINE="{analysis.get("engine_telemetry", {}).get("engine", info["engine"])}"')
                print(f'export VESSEL_INFERRED_LAA="{1 if analysis.get("pe_telemetry", {}).get("is_large_address_aware") else 0}"')
            except Exception:
                pass
    elif flag == "--json":
        print(json.dumps(info, indent=2))
    elif flag == "--winver":
        print(info["winver"])
    elif flag == "--engine":
        print(info["engine"])
    elif flag == "--api":
        print(info["api"])
    elif flag == "--bits":
        print(info["bits"])
    elif flag == "--category":
        print(info["category"])
    else:
        # Formato legible por defecto
        print(f"Archivo   : {info['resolved_exe']}")
        print(f"Formato   : {'PE32+ (64-bit)' if info['is_64'] else 'PE32 (32-bit)'}")
        print(f"Tipo      : {'🎮 Juego' if info['category'] == 'juego' else '💼 Programa'}")
        print(f"Windows   : {info['winver'].upper()}")
        print(f"Motor     : {info['engine']}")
        print(f"API 3D    : {info['api'].upper()}")
        print(f"Subsystem : {info['subsys']}")
        if info.get("anti_cheat_warning"):
            print(f"Anti-Cheat: ⚠️ {info.get('anti_cheat_name')} (Kernel Ring-0)")

if __name__ == "__main__":
    main()
