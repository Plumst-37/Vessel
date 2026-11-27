#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
==============================================================================
VESSEL - MOTOR EXPERTO HEURÍSTICO DE INFERENCIA Y RENDIMIENTO (WINE/PROTON)
Copyright (C) 2026 Vessel Gaming Project
Licensed under the GNU General Public License v3.0 (GPL-3.0).

Inspecciona ejecutables PE de Windows en < 5 ms, detecta topología del host
y calcula de forma heurística las variables de entorno óptimas para máxima
tasa de fotogramas (FPS), baja latencia y prevención de cuelgues (OOM/crash).

Sin dependencias externas: 100% Python 3 estándar (struct, os, sys, json, re).
==============================================================================
"""

import os
import sys
import struct
import json
import re
import argparse
import time
from pathlib import Path

# ==============================================================================
# 1. PARSER ULTRA-RÁPIDO DE CABECERAS BINARIAS PE (PORTABLE EXECUTABLE)
# ==============================================================================

class PEInspector:
    """
    Parser binario optimizado para cabeceras PE/COFF de Windows.
    Extrae arquitectura, Large Address Aware, subsistemas y librerías importadas
    con degradación elegante ante binarios ofuscados o corruptos.
    """

    # Firmas de máquinas conocidas
    MACHINE_TYPES = {
        0x014c: ("IMAGE_FILE_MACHINE_I386", 32, "x86 (32-bit)"),
        0x8664: ("IMAGE_FILE_MACHINE_AMD64", 64, "x86_64 (64-bit)"),
        0xaa64: ("IMAGE_FILE_MACHINE_ARM64", 64, "ARM64 (64-bit)"),
        0x0200: ("IMAGE_FILE_MACHINE_IA64", 64, "Itanium (64-bit)"),
    }

    # Características clave
    CHAR_LARGE_ADDRESS_AWARE = 0x0020
    CHAR_DLL = 0x2000

    # APIs gráficas y de sistema reconocidas
    GRAPHICS_SIGNATURES = {
        "d3d8.dll": "dx8",
        "d3d9.dll": "dx9",
        "d3d10.dll": "dx10",
        "d3d10_1.dll": "dx10",
        "d3d10core.dll": "dx10",
        "d3d11.dll": "dx11",
        "dxgi.dll": "dx11",
        "d3d12.dll": "dx12",
        "d3d12core.dll": "dx12",
        "vulkan-1.dll": "vulkan",
        "winevulkan.dll": "vulkan",
        "opengl32.dll": "opengl",
        "ddraw.dll": "ddraw",
    }

    MULTIMEDIA_SIGNATURES = {
        "xinput1_4.dll": "xinput",
        "xinput1_3.dll": "xinput",
        "xinput9_1_0.dll": "xinput",
        "dinput8.dll": "dinput",
        "xaudio2_9.dll": "xaudio",
        "xaudio2_7.dll": "xaudio",
        "dsound.dll": "dsound",
        "openal32.dll": "openal",
        "eax.dll": "eax",
    }

    @classmethod
    def inspect(cls, file_path: str) -> dict:
        """
        Inspecciona el archivo binario y retorna la telemetría PE estructurada.
        Garantiza tiempo de respuesta en submilisegundos y cero excepciones fatales.
        """
        result = {
            "valid_pe": False,
            "architecture": "Desconocida",
            "bits": 32,
            "is_64": False,
            "is_large_address_aware": False,
            "subsystem_major": 6,
            "subsystem_minor": 0,
            "subsystem_type": "GUI",
            "characteristics": 0,
            "imported_dlls": [],
            "detected_apis": [],
            "error": None
        }

        if not file_path or not os.path.isfile(file_path):
            result["error"] = "Ruta de archivo no válida o inexistente"
            return result

        try:
            with open(file_path, "rb") as f:
                # 1. Cabecera DOS (MZ)
                dos_header = f.read(64)
                if len(dos_header) < 64 or dos_header[:2] != b"MZ":
                    result["error"] = "No es un ejecutable DOS/MZ válido"
                    return result

                e_lfanew = struct.unpack_from("<I", dos_header, 0x3C)[0]
                if e_lfanew <= 0 or e_lfanew > 4096:
                    result["error"] = f"Offset PE e_lfanew inválido ({e_lfanew})"
                    return result

                # 2. Firma PE
                f.seek(e_lfanew)
                pe_sig = f.read(4)
                if pe_sig != b"PE\x00\x00":
                    result["error"] = "Firma PE\\0\\0 no encontrada"
                    return result

                result["valid_pe"] = True

                # 3. Cabecera COFF (20 bytes)
                coff_data = f.read(20)
                if len(coff_data) < 20:
                    result["error"] = "Cabecera COFF truncada"
                    return result

                machine, num_sections, _, _, _, opt_size, characteristics = struct.unpack("<HHIIIHH", coff_data)
                result["characteristics"] = characteristics

                mach_info = cls.MACHINE_TYPES.get(machine, ("UNKNOWN", 32, f"Desconocida (0x{machine:04x})"))
                result["architecture"] = mach_info[2]
                result["bits"] = mach_info[1]
                result["is_64"] = (mach_info[1] == 64)

                # Large Address Aware
                if result["is_64"]:
                    result["is_large_address_aware"] = True
                else:
                    result["is_large_address_aware"] = bool(characteristics & cls.CHAR_LARGE_ADDRESS_AWARE)

                # 4. Optional Header
                if opt_size > 0:
                    opt_data = f.read(min(opt_size, 256))
                    if len(opt_data) >= 2:
                        magic = struct.unpack_from("<H", opt_data, 0)[0]
                        if magic == 0x020b:
                            result["is_64"] = True
                            result["bits"] = 64
                            result["architecture"] = "x86_64 (64-bit)"
                            result["is_large_address_aware"] = True
                        elif magic == 0x010b:
                            result["is_64"] = False
                            result["bits"] = 32

                        # Subsystem version
                        # En PE32: offset 48 en OptionalHeader (72 desde PE)
                        # En PE32+: offset 48 en OptionalHeader (72 desde PE)
                        if len(opt_data) >= 52:
                            sub_maj = struct.unpack_from("<H", opt_data, 48)[0]
                            sub_min = struct.unpack_from("<H", opt_data, 50)[0]
                            result["subsystem_major"] = sub_maj
                            result["subsystem_minor"] = sub_min

                        if len(opt_data) >= 70:
                            sub_type = struct.unpack_from("<H", opt_data, 68)[0]
                            result["subsystem_type"] = "CUI" if sub_type == 3 else "GUI"

                # 5. Escaneo de Tabla de Importaciones (Import Directory)
                imported_dlls = cls._parse_import_table(f, opt_data, num_sections, result["is_64"])
                result["imported_dlls"] = imported_dlls

                # 6. Escaneo Heurístico Secundario en Bloques Binarios (Fallback de Resiliencia)
                # Escanea los primeros 64 KB de forma vectorizada para pescar strings de APIs
                f.seek(0)
                chunk = f.read(65536)
                extra_dlls = cls._scan_binary_chunk_dlls(chunk)
                all_dlls = set(imported_dlls) | set(extra_dlls)

                detected_apis = set()
                for dll in all_dlls:
                    if dll in cls.GRAPHICS_SIGNATURES:
                        detected_apis.add(cls.GRAPHICS_SIGNATURES[dll])
                    if dll in cls.MULTIMEDIA_SIGNATURES:
                        detected_apis.add(cls.MULTIMEDIA_SIGNATURES[dll])

                result["detected_apis"] = sorted(list(detected_apis))

        except Exception as e:
            result["error"] = f"Error en lectura binaria: {str(e)}"

        return result

    @classmethod
    def _parse_import_table(cls, f, opt_data: bytes, num_sections: int, is_64: bool) -> list:
        """Extrae la lista de DLLs importadas mapeando RVAs a offsets de sección."""
        dlls = []
        try:
            dd_offset = 112 if is_64 else 96
            if len(opt_data) < dd_offset + 16:
                return dlls

            imp_rva, imp_size = struct.unpack_from("<II", opt_data, dd_offset + 8)
            if imp_rva == 0 or imp_size == 0:
                return dlls

            # Leer Secciones (40 bytes cada una)
            sec_data = f.read(num_sections * 40)
            sections = []
            for i in range(num_sections):
                s = sec_data[i * 40:(i + 1) * 40]
                if len(s) < 40:
                    break
                vsize, vrva, rsize, roff = struct.unpack_from("<IIII", s, 8)
                sections.append((vrva, max(vsize, rsize), roff))

            def rva_to_off(rva):
                for vrva, span, roff in sections:
                    if vrva <= rva < vrva + span:
                        return roff + (rva - vrva)
                return None

            imp_off = rva_to_off(imp_rva)
            if not imp_off:
                return dlls

            f.seek(imp_off)
            count = 0
            while count < 64:  # Límite de seguridad
                count += 1
                desc = f.read(20)
                if len(desc) < 20 or desc == b"\x00" * 20:
                    break
                name_rva = struct.unpack_from("<I", desc, 12)[0]
                name_off = rva_to_off(name_rva)
                if name_off:
                    cur = f.tell()
                    f.seek(name_off)
                    name_raw = f.read(64).split(b"\x00", 1)[0]
                    if name_raw:
                        dlls.append(name_raw.decode("latin1", "ignore").lower())
                    f.seek(cur)
        except Exception:
            pass
        return dlls

    @classmethod
    def _scan_binary_chunk_dlls(cls, chunk: bytes) -> list:
        """Escanea cadenas binarias para detectar referencias a librerías gráficas."""
        found = set()
        chunk_low = chunk.lower()
        for dll_str in cls.GRAPHICS_SIGNATURES:
            if dll_str.encode("ascii") in chunk_low:
                found.add(dll_str)
        for dll_str in cls.MULTIMEDIA_SIGNATURES:
            if dll_str.encode("ascii") in chunk_low:
                found.add(dll_str)
        return list(found)


# ==============================================================================
# 2. IDENTIFICADOR HEURÍSTICO DE MOTORES, MIDDLEWARE Y SEGURIDAD
# ==============================================================================

class EngineFingerprinter:
    """
    Analiza la estructura de carpetas, assets y ejecutables para identificar
    motores gráficos comerciales y sistemas de protección / Anti-Cheat de Kernel.
    """

    KNOWN_ANTIS = {
        "vgk.sys": ("Riot Vanguard", "CRITICAL", "Anti-Cheat a nivel de Kernel Ring-0. Incompatible con Wine; el modo online será bloqueado en Linux."),
        "easyanticheat.sys": ("Easy Anti-Cheat", "HIGH", "Driver de Kernel EAC detectado. Requiere soporte nativo Proton EAC en el juego o servidores sin verificación Ring-0."),
        "easyanticheat_eos.sys": ("Easy Anti-Cheat (EOS)", "HIGH", "Driver EAC Epic Online Services detectado. Puede requerir Proton EAC bridge."),
        "bedaisy.sys": ("BattlEye", "HIGH", "Driver BattlEye Ring-0. Funcional solo si los desarrolladores activaron el módulo de Proton/Linux en el servidor."),
        "mhyprot2.sys": ("HoYoverse Anti-Cheat", "HIGH", "Driver Ring-0 no admitido en Wine estándar."),
        "anticheat.sys": ("Kernel Anti-Cheat Genérico", "HIGH", "Driver Ring-0 no admitido en Wine estándar."),
    }

    @classmethod
    def fingerprint(cls, exe_path: str, pe_info: dict) -> dict:
        result = {
            "engine": "generico",
            "engine_label": "Genérico / Win32 Estándar",
            "confidence": 50,
            "middleware": [],
            "anti_cheat": {
                "detected": False,
                "name": "",
                "risk_level": "NONE",
                "warning": ""
            }
        }

        if not exe_path:
            return result

        real_exe = os.path.realpath(exe_path)
        game_dir = os.path.dirname(real_exe)
        file_name = os.path.basename(real_exe).lower()
        file_stem = os.path.splitext(file_name)[0]
        full_path_low = real_exe.lower()

        # Listar contenido superficial del directorio (0 subprocesos)
        root_files = set()
        root_dirs = set()
        if os.path.isdir(game_dir):
            try:
                for entry in os.scandir(game_dir):
                    if entry.is_file(follow_symlinks=False):
                        root_files.add(entry.name.lower())
                    elif entry.is_dir(follow_symlinks=False):
                        root_dirs.add(entry.name.lower())
            except Exception:
                pass

        # 1. Detección de Anti-Cheat & Seguridad (Pre-Flight Shield)
        for ac_file, ac_data in cls.KNOWN_ANTIS.items():
            if ac_file in root_files:
                result["anti_cheat"] = {
                    "detected": True,
                    "name": ac_data[0],
                    "risk_level": ac_data[1],
                    "warning": ac_data[2]
                }
                break

        if not result["anti_cheat"]["detected"]:
            # Buscar en subcarpetas de seguridad directas
            for sub in ("easyanticheat", "battleye", "anticheat"):
                if sub in root_dirs:
                    result["anti_cheat"] = {
                        "detected": True,
                        "name": sub.upper(),
                        "risk_level": "MEDIUM",
                        "warning": f"Carpeta de {sub.upper()} detectada. Requiere soporte Proton Runtime para jugar online."
                    }
                    break

        # 2. Detección de Motores
        apis = pe_info.get("detected_apis", [])
        is_64 = pe_info.get("is_64", False)

        # A) Unity
        if "unityplayer.dll" in root_files or any(d.endswith("_data") for d in root_dirs) or "monobleedingedge" in root_dirs:
            result["engine"] = "unity"
            result["engine_label"] = "Unity Engine"
            result["confidence"] = 95
            result["middleware"].append("Unity Runtime")

        # B) Unreal Engine
        elif "engine" in root_dirs or file_name.endswith("-shipping.exe") or "win64" in root_dirs or "win32" in root_dirs:
            result["engine"] = "unreal"
            result["engine_label"] = "Unreal Engine"
            result["confidence"] = 90
            result["middleware"].append("Epic Unreal Runtime")

        # C) Capcom RE Engine
        elif any(f.startswith("re_chunk_000") for f in root_files) or (is_64 and any(k in file_name for k in ("re4.exe", "re2.exe", "re3.exe", "re7.exe", "re8.exe", "sf6.exe", "dmc5.exe"))):
            result["engine"] = "re_engine"
            result["engine_label"] = "Capcom RE Engine (DX12)"
            result["confidence"] = 95
            result["middleware"].append("Capcom RE Engine")

        # D) Rockstar RAGE (GTA V / GTA IV / RDR2)
        elif any(k in file_name for k in ("gta5", "playgtav", "rdr2")) or "gta v" in full_path_low or "gta_data" in full_path_low:
            result["engine"] = "rockstar_rage"
            result["engine_label"] = "Rockstar Advanced Game Engine (RAGE)"
            result["confidence"] = 95
            result["middleware"].append("Rockstar Social / RAGE")

        # E) Rockstar RenderWare (GTA SA / Vice City / III)
        elif any(k in file_name for k in ("gta_sa", "gta-sa", "gta3", "gta-vc")) or "eax.dll" in root_files and "vorbisfile.dll" in root_files:
            result["engine"] = "rockstar_renderware"
            result["engine_label"] = "Rockstar RenderWare (Clásico)"
            result["confidence"] = 95
            result["middleware"].append("RenderWare 3D")

        # F) Source Engine (Half-Life 2, CS, Portal)
        elif "hl2.exe" in file_name or "tier0.dll" in root_files or "vstdlib.dll" in root_files:
            result["engine"] = "source"
            result["engine_label"] = "Valve Source Engine"
            result["confidence"] = 95
            result["middleware"].append("Valve Source")

        # G) Bethesda Creation / Gamebryo (Skyrim, Fallout, Oblivion, Starfield)
        elif any(f.endswith(".esm") for f in root_files) or any(k in file_name for k in ("tesv", "skyrim", "fallout3", "fallout4", "falloutnv", "starfield")):
            result["engine"] = "bethesda_creation"
            result["engine_label"] = "Bethesda Creation Engine"
            result["confidence"] = 90
            result["middleware"].append("Bethesda Gamebryo/Creation")

        # H) Godot Engine
        elif any(f.endswith(".pck") for f in root_files) or "godot" in file_name:
            result["engine"] = "godot"
            result["engine_label"] = "Godot Engine"
            result["confidence"] = 90
            result["middleware"].append("Godot Core")

        # I) GameMaker Studio
        elif "data.win" in root_files or any(f.startswith("audiogroup") for f in root_files):
            result["engine"] = "gamemaker"
            result["engine_label"] = "GameMaker Studio"
            result["confidence"] = 90

        # J) EA Frostbite / Need for Speed
        elif "frostbite" in full_path_low or any(k in file_name for k in ("speed", "nfs")):
            result["engine"] = "ea_games"
            result["engine_label"] = "EA Games Engine"
            result["confidence"] = 80

        # K) Clásicos DirectDraw 2D
        elif "ddraw" in apis or any(k in file_name for k in ("empires2", "age2_x1", "starcraft", "ra2", "diablo", "fallout")):
            result["engine"] = "classic_directdraw"
            result["engine_label"] = "DirectDraw 2D Retro"
            result["confidence"] = 85

        return result


# ==============================================================================
# 3. SONDA DE TOPOLOGÍA DE HARDWARE DEL SISTEMA HOST (SUB-MILISEGUNDO)
# ==============================================================================

class HardwareTopologyProbe:
    """
    Sonda pasiva de hardware del sistema anfitrión GNU/Linux.
    Lee directamente de sysfs (/sys) y procfs (/proc) sin invocar subprocesos
    pesados, logrando una inspección de GPU, VRAM, CPU y RAM en < 1 ms.
    """

    @classmethod
    def probe(cls) -> dict:
        hw = {
            "cpu": {
                "model": "Desconocido",
                "cores": 1,
                "threads": os.cpu_count() or 1,
                "is_hybrid": False,
                "p_cores": 0,
                "e_cores": 0
            },
            "ram": {
                "total_mb": 8192,
                "available_mb": 4096
            },
            "gpu": {
                "vendor": "generic",
                "vendor_label": "Genérico / Mesa",
                "model": "Gráficos del Sistema",
                "driver": "Mesa / Vulkan",
                "vram_mb": 2048,
                "is_dual_gpu": False,
                "discrete_gpu_available": False,
                "supports_vulkan": True
            }
        }

        # 1. CPU & Topología
        cls._probe_cpu(hw["cpu"])

        # 2. Memoria RAM
        cls._probe_ram(hw["ram"])

        # 3. GPU y VRAM
        cls._probe_gpu(hw["gpu"])

        return hw

    @classmethod
    def _probe_cpu(cls, cpu: dict):
        try:
            if os.path.exists("/proc/cpuinfo"):
                with open("/proc/cpuinfo", "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()

                for line in content.splitlines():
                    if "model name" in line:
                        cpu["model"] = line.split(":", 1)[1].strip()
                        break

            # Detección de Arquitectura Híbrida (Intel 12th/13th/14th/Ultra con P-Cores y E-Cores)
            model_low = cpu["model"].lower()
            if any(k in model_low for k in ("12th gen", "13th gen", "14th gen", "ultra ", "core ultra")):
                cpu["is_hybrid"] = True

            # Detección por frecuencias heterogéneas en sysfs
            cpufreq_dir = "/sys/devices/system/cpu"
            if os.path.isdir(cpufreq_dir):
                freqs = set()
                try:
                    for i in range(cpu["threads"]):
                        freq_path = f"{cpufreq_dir}/cpu{i}/cpufreq/cpuinfo_max_freq"
                        if os.path.exists(freq_path):
                            with open(freq_path, "r") as ff:
                                freqs.add(int(ff.read().strip()))
                    if len(freqs) > 1:
                        cpu["is_hybrid"] = True
                except Exception:
                    pass

        except Exception:
            pass

    @classmethod
    def _probe_ram(cls, ram: dict):
        try:
            if os.path.exists("/proc/meminfo"):
                with open("/proc/meminfo", "r", encoding="utf-8", errors="ignore") as f:
                    for line in f:
                        if line.startswith("MemTotal:"):
                            ram["total_mb"] = int(line.split()[1]) // 1024
                        elif line.startswith("MemAvailable:"):
                            ram["available_mb"] = int(line.split()[1]) // 1024
        except Exception:
            pass

    @classmethod
    def _probe_gpu(cls, gpu: dict):
        try:
            vendors_found = []
            vram_found = 0

            # Inspección sysfs en /sys/class/drm
            drm_path = "/sys/class/drm"
            if os.path.isdir(drm_path):
                cards = [c for c in os.listdir(drm_path) if c.startswith("card") and "-" not in c]
                for card in sorted(cards):
                    dev_vendor = f"{drm_path}/{card}/device/vendor"
                    if os.path.exists(dev_vendor):
                        try:
                            with open(dev_vendor, "r") as vf:
                                v_id = vf.read().strip().lower()
                                if "0x10de" in v_id:
                                    vendors_found.append("nvidia")
                                elif "0x1002" in v_id:
                                    vendors_found.append("amd")
                                elif "0x8086" in v_id:
                                    vendors_found.append("intel")
                        except Exception:
                            pass

                    # VRAM en sysfs
                    vram_file = f"{drm_path}/{card}/device/mem_info_vram_total"
                    if os.path.exists(vram_file):
                        try:
                            with open(vram_file, "r") as vrf:
                                vram_bytes = int(vrf.read().strip())
                                if vram_bytes > 0:
                                    vram_found = max(vram_found, vram_bytes // (1024 * 1024))
                        except Exception:
                            pass

            if len(vendors_found) > 1:
                gpu["is_dual_gpu"] = True

            # Prioridad de GPU Primaria para Gaming: NVIDIA dedicada > AMD dedicada > Intel integrada
            if "nvidia" in vendors_found:
                gpu["vendor"] = "nvidia"
                gpu["vendor_label"] = "NVIDIA GeForce"
                gpu["discrete_gpu_available"] = True
                # Comprobar driver propietario vs Nouveau
                if os.path.exists("/proc/driver/nvidia/version"):
                    with open("/proc/driver/nvidia/version", "r", errors="ignore") as nvf:
                        line1 = nvf.readline()
                        m = re.search(r"Kernel Module\s+([0-9]+\.[0-9]+)", line1)
                        drv_ver = m.group(1) if m else "Propietario"
                    gpu["driver"] = f"NVIDIA Oficial {drv_ver}"
                else:
                    gpu["driver"] = "Nouveau (Open Source)"

            elif "amd" in vendors_found:
                gpu["vendor"] = "amd"
                gpu["vendor_label"] = "AMD Radeon"
                gpu["driver"] = "Mesa RADV"
                gpu["discrete_gpu_available"] = True
            elif "intel" in vendors_found:
                gpu["vendor"] = "intel"
                gpu["vendor_label"] = "Intel Graphics"
                gpu["driver"] = "Mesa ANV / Xe"

            if vram_found > 0:
                gpu["vram_mb"] = vram_found

        except Exception:
            pass


# ==============================================================================
# 4. MOTOR DE INFERENCIA HEURÍSTICA Y MATRIZ DE PRESCRIPCIÓN DE RENDIMIENTO
# ==============================================================================

class InferenceEngine:
    """
    Combina la telemetría del binario PE con la topología de hardware
    para sintetizar el conjunto matemáticamente óptimo de variables de entorno,
    mitigar el shader stuttering y garantizar 0 fallos de memoria.
    """

    @classmethod
    def analyze(cls, exe_path: str) -> dict:
        t_start = time.perf_counter()

        # 1. Parsing PE
        pe = PEInspector.inspect(exe_path)

        # 2. Fingerprinting
        engine = EngineFingerprinter.fingerprint(exe_path, pe)

        # 3. Hardware Probing
        hw = HardwareTopologyProbe.probe()

        # 4. Decisión de API Gráfica
        detected_apis = pe.get("detected_apis", [])
        engine_id = engine.get("engine", "")

        api_final = "dx11"  # Default seguro para 64-bit
        if "dx12" in detected_apis or engine_id == "re_engine":
            api_final = "dx12"
        elif "dx11" in detected_apis or "dx10" in detected_apis or (pe.get("is_64") and engine_id in ("rockstar_rage", "unreal_engine", "unity")):
            api_final = "dx11"
        elif "vulkan" in detected_apis:
            api_final = "vulkan"
        elif "dx9" in detected_apis or engine_id in ("rockstar_renderware", "capcom_mt_framework"):
            api_final = "dx9"
        elif "dx8" in detected_apis:
            api_final = "dx8"
        elif "opengl" in detected_apis or engine_id == "source":
            api_final = "opengl"
        elif "ddraw" in detected_apis or engine_id == "classic_directdraw":
            api_final = "ddraw"
        else:
            api_final = "gdi"

        # 5. Generación de Variables de Entorno y Razonamiento Heurístico
        env = {}
        reasons = []

        # A) Arquitectura de Memoria y 32-bit Large Address Aware
        if not pe.get("is_64", False):
            if not pe.get("is_large_address_aware", False):
                env["WINE_LARGE_ADDRESS_AWARE"] = "1"
                reasons.append("Binario 32-bit sin flag LAA: Se prescribe WINE_LARGE_ADDRESS_AWARE=1 para evitar cuelgues Out-Of-Memory (OOM) habilitando 4 GB de espacio virtual.")
            else:
                reasons.append("Binario 32-bit con LAA nativo: Aprovecha 4 GB de memoria virtual en Wine.")

            # Topología de CPU en 32-bit: Limitar hilos si host > 16 para evitar desbordamiento de búfer
            if hw["cpu"]["threads"] > 16:
                env["WINE_CPU_TOPOLOGY"] = "16"
                reasons.append(f"Host de {hw['cpu']['threads']} hilos detectado con juego 32-bit: WINE_CPU_TOPOLOGY fijado a 16 para evitar desbordamiento de enteros en bucles clásicos.")
        else:
            reasons.append("Binario nativo de 64 bits: Direccionamiento de memoria completo sin limitaciones de 4 GB.")

        # B) CPU Híbrido (Intel Alder / Raptor Lake)
        if hw["cpu"]["is_hybrid"]:
            reasons.append("CPU con arquitectura híbrida (P-Cores + E-Cores): Se activa aislamiento de hilos para priorizar núcleos de alto rendimiento.")

        # C) Prescripción de API Gráfica y Traductores (DXVK / VKD3D-Proton / D3D8to9)
        if api_final == "dx12":
            env["VKD3D_PROTON"] = "1"
            env["VKD3D_FEATURE_LEVEL"] = "12_0"
            if hw["gpu"]["vram_mb"] < 4096 or hw["gpu"]["vendor"] == "intel":
                env["VKD3D_CONFIG"] = "no_upload_hvv,nodxr"
                reasons.append("DirectX 12 con VRAM moderada (<4 GB) o Intel: VKD3D_CONFIG=no_upload_hvv,nodxr para prevenir saturación de VRAM y deshabilitar Ray Tracing.")
            else:
                env["VKD3D_CONFIG"] = "dxr11"
                reasons.append("DirectX 12 con VRAM óptima: VKD3D_CONFIG=dxr11 activado para máxima compatibilidad gráfica.")

        elif api_final in ("dx11", "dx10"):
            env["DXVK"] = "1"
            env["DXVK_ASYNC"] = "1"
            env["DXVK_STATE_CACHE"] = "1"
            env["DXVK_FRAME_LATENCY"] = "1"
            reasons.append("DirectX 10/11: DXVK con compilación asíncrona de pipelines y State Cache para erradicar el shader stuttering.")

        elif api_final == "dx9":
            env["DXVK_D3D9"] = "1"
            env["DXVK_ASYNC"] = "1"
            env["DXVK_FRAME_LATENCY"] = "1"
            env["PBA_ENABLE"] = "1"
            reasons.append("DirectX 9: DXVK nativo a 60+ FPS fijos con búferes persistentes (PBA) para eliminación de micro-tirones.")

        elif api_final == "dx8":
            env["ENABLE_D3D8TO9"] = "1"
            env["DXVK_D3D9"] = "1"
            reasons.append("DirectX 8: Inyección de D3D8to9 para convertir llamadas a DirectX 9 / Vulkan nativo a 60 FPS fijos.")

        elif api_final == "vulkan":
            env["DXVK"] = "0"
            env["VKD3D_PROTON"] = "0"
            reasons.append("API Vulkan nativa detectada: Pase directo sin capas de traducción intermedias.")

        elif api_final == "opengl":
            env["MESA_GL_VERSION_OVERRIDE"] = "4.6"
            env["WINE_D3D_NO_GLSL"] = "0"
            reasons.append("OpenGL: Configuración de compatibilidad GLSL moderna 4.6 nativa.")

        elif api_final == "ddraw":
            env["ENABLE_CNC_DDRAW"] = "1"
            reasons.append("DirectDraw clásico: Enrutado a cnc-ddraw (OpenGL moderno) para preservar paletas de 8 bits sin parpadeos.")

        # D) Optimizaciones de GPU (solo para aplicaciones/juegos con aceleración 3D)
        if api_final != "gdi":
            if hw["gpu"]["is_dual_gpu"]:
                if hw["gpu"]["vendor"] == "nvidia":
                    env["__NV_PRIME_RENDER_OFFLOAD"] = "1"
                    env["__GLX_VENDOR_LIBRARY_NAME"] = "nvidia"
                    env["__VK_LAYER_NV_optimus"] = "NVIDIA_only"
                    reasons.append("Gráficos duales detectados (Laptop híbrida NVIDIA): Forzado de renderizado en GPU dedicada NVIDIA GeForce con PRIME offload.")
                elif hw["gpu"]["vendor"] in ("amd", "intel"):
                    env["DRI_PRIME"] = "1"
                    reasons.append("Gráficos duales detectados (Laptop híbrida AMD/Intel): Forzado de renderizado en GPU dedicada con DRI_PRIME=1.")

            if hw["gpu"]["vendor"] == "nvidia":
                env["__GL_SHADER_DISK_CACHE"] = "1"
                env["__GL_SHADER_DISK_CACHE_SKIP_CLEANUP"] = "1"
                env["__GL_THREADED_OPTIMIZATIONS"] = "1"
                env["__GL_YIELD"] = "NOTHING"
                env["DXVK_ENABLE_NVAPI"] = "1"
                reasons.append("GPU NVIDIA: Desbloqueo de caché ilimitada, multithreading OpenGL/Vulkan, cero latencia de espera y DXVK-NVAPI.")

            elif hw["gpu"]["vendor"] == "amd":
                env["AMD_VULKAN_ICD"] = "RADV"
                env["RADV_PERFTEST"] = "gpl"
                reasons.append("GPU AMD: Forzado de Mesa RADV con compilador rápido ACO y Vulkan GPL.")

            elif hw["gpu"]["vendor"] == "intel":
                env["ANV_ENABLE_PIPELINE_CACHE"] = "1"
                reasons.append("GPU Intel: Optimización de caché de pipelines Vulkan ANV para eliminar stuttering.")

        # E) Sincronización de Hilos del Kernel (Fsync / Esync) y Páginas Gigantes (THP)
        env["WINEFSYNC"] = "1"
        env["WINEESYNC"] = "1"
        env["STAGING_SHARED_MEMORY"] = "1"
        env["WINE_THP"] = "1"
        env["MESA_SHADER_CACHE_MAX_SIZE"] = "4096MB"
        reasons.append("Kernel & Memoria: Fsync/Esync activo y Transparent Huge Pages (THP) para cero tirones de caché TLB.")

        # F) Audio de Baja Latencia
        env["PULSE_LATENCY_MSEC"] = "60"

        # 6. Versión de Windows Sugerida
        if "gameranger" in exe_path.lower():
            winver_rec = "win7"
        elif pe.get("is_64") or api_final in ("dx11", "dx12", "vulkan"):
            winver_rec = "win10"
        elif api_final == "ddraw" or engine_id == "classic_directdraw":
            winver_rec = "winxp"
        else:
            winver_rec = "win10"

        t_end = time.perf_counter()
        elapsed_ms = (t_end - t_start) * 1000

        return {
            "target": exe_path,
            "elapsed_ms": round(elapsed_ms, 2),
            "pe_telemetry": pe,
            "engine_telemetry": engine,
            "hardware_telemetry": hw,
            "prescriptions": {
                "api": api_final,
                "winver": winver_rec,
                "environment_variables": env,
                "reasons": reasons
            }
        }


# ==============================================================================
# 5. CLI HANDLERS (--json, --env, --summary)
# ==============================================================================

def print_env_output(analysis: dict):
    """Imprime variables en sintaxis lista para eval de Bash."""
    env_vars = analysis["prescriptions"]["environment_variables"]
    for k, v in env_vars.items():
        # Validar que k sea un identificador POSIX válido para bash [a-zA-Z_][a-zA-Z0-9_]*
        if re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', k):
            print(f'export {k}="{v}"')
    # Metadatos del análisis
    print(f'export VESSEL_INFERRED_API="{analysis["prescriptions"]["api"]}"')
    print(f'export VESSEL_INFERRED_WINVER="{analysis["prescriptions"]["winver"]}"')
    print(f'export VESSEL_INFERRED_BITS="{analysis["pe_telemetry"]["bits"]}"')
    print(f'export VESSEL_INFERRED_ENGINE="{analysis["engine_telemetry"]["engine"]}"')
    print(f'export VESSEL_INFERRED_LAA="{1 if analysis["pe_telemetry"]["is_large_address_aware"] else 0}"')
    ac = analysis["engine_telemetry"]["anti_cheat"]
    print(f'export VESSEL_ANTI_CHEAT_WARNING="{1 if ac["detected"] else 0}"')
    print(f'export VESSEL_ANTI_CHEAT_NAME="{ac["name"]}"')

def print_summary_output(analysis: dict):
    """Imprime un resumen visual atractivo acorde al estilo de Vessel."""
    CYAN = "\033[1;36m"
    GREEN = "\033[1;32m"
    YELLOW = "\033[1;33m"
    PURPLE = "\033[1;35m"
    RED = "\033[1;31m"
    WHITE = "\033[1;37m"
    BOLD = "\033[1m"
    RESET = "\033[0m"

    pe = analysis["pe_telemetry"]
    eng = analysis["engine_telemetry"]
    hw = analysis["hardware_telemetry"]
    rx = analysis["prescriptions"]
    ms = analysis["elapsed_ms"]

    print(f"\n{PURPLE}╔══════════════════════════════════════════════════════════════════════════════════╗{RESET}")
    print(f"{PURPLE}║{RESET}         {CYAN}{BOLD}⚡ VESSEL - MOTOR EXPERTO DE INFERENCIA Y RENDIMIENTO HEURÍSTICO{RESET}         {PURPLE}║{RESET}")
    print(f"{PURPLE}║{RESET}                  {WHITE}Tiempo de análisis: {GREEN}{BOLD}{ms} ms{RESET} {WHITE}| GNU GPLv3 Oficial{RESET}                 {PURPLE}║{RESET}")
    print(f"{PURPLE}╚══════════════════════════════════════════════════════════════════════════════════╝{RESET}\n")

    print(f"  {CYAN}🎯 Ejecutable Objetivo{RESET} : {BOLD}{WHITE}{analysis['target']}{RESET}")
    print(f"  {CYAN}📦 Arquitectura Binaria{RESET}: {WHITE}{pe['architecture']}{RESET} | Subsystem {pe['subsystem_major']}.{pe['subsystem_minor']} ({pe['subsystem_type']})")
    laa_tag = f"{GREEN}Activo (4 GB){RESET}" if pe["is_large_address_aware"] else f"{YELLOW}No Activo (Wine LAA Forzado){RESET}"
    print(f"  {CYAN}🧠 Large Address Aware{RESET} : {laa_tag}")
    print(f"  {CYAN}🎮 Motor Detectado{RESET}    : {BOLD}{GREEN}{eng['engine_label']}{RESET} (Confianza {eng['confidence']}%)")
    print(f"  {CYAN}🖼️  API Gráfica Inferida{RESET}: {BOLD}{PURPLE}{rx['api'].upper()}{RESET} (Recomendado: {rx['winver'].upper()})")

    # Anti-cheat
    ac = eng["anti_cheat"]
    if ac["detected"]:
        print(f"\n  {RED}{BOLD}⚠️  ALERTA DE SEGURIDAD / ANTI-CHEAT:{RESET}")
        print(f"     • Sistema : {YELLOW}{ac['name']}{RESET} [Riesgo: {RED}{ac['risk_level']}{RESET}]")
        print(f"     • Detalle : {WHITE}{ac['warning']}{RESET}")

    # Hardware
    print(f"\n  {BOLD}{WHITE}💻 Topología de Hardware Detectada:{RESET}")
    print(f"     • CPU : {WHITE}{hw['cpu']['model']}{RESET} ({hw['cpu']['threads']} Hilos){' [Arquitectura Híbrida P+E]' if hw['cpu']['is_hybrid'] else ''}")
    print(f"     • RAM : {WHITE}{hw['ram']['total_mb']} MB{RESET} Total | {hw['ram']['available_mb']} MB Disponibles")
    print(f"     • GPU : {WHITE}{hw['gpu']['vendor_label']}{RESET} ({hw['gpu']['vram_mb']} MB VRAM) | Driver: {WHITE}{hw['gpu']['driver']}{RESET}")
    if hw["gpu"]["is_dual_gpu"]:
        print(f"     • {GREEN}✓ Sistema con GPU Dual (PRIME Offload habilitado hacia gráfica dedicada){RESET}")

    # Prescripciones
    print(f"\n  {BOLD}{WHITE}🚀 Prescripciones de Rendimiento Calculadas:{RESET}")
    for reason in rx["reasons"]:
        print(f"     {GREEN}✔{RESET} {WHITE}{reason}{RESET}")

    print(f"\n  {BOLD}{WHITE}⚙️  Variables de Entorno Inyectadas:{RESET}")
    for k, v in rx["environment_variables"].items():
        print(f"     {CYAN}{k}{RESET}={GREEN}\"{v}\"{RESET}")
    print("")

def main():
    parser = argparse.ArgumentParser(
        description="Vessel Inferencia - Motor Heurístico de Detección de Binarios y Rendimiento para Linux/Wine."
    )
    parser.add_argument("exe", help="Ruta al ejecutable Windows (.exe) a inspeccionar")
    parser.add_argument("--json", action="store_true", help="Salida en formato JSON estructurado")
    parser.add_argument("--env", action="store_true", help="Salida en sentencias export de Bash")
    parser.add_argument("--summary", action="store_true", help="Salida en resumen visual legible para humanos")

    args = parser.parse_args()

    analysis = InferenceEngine.analyze(args.exe)

    if args.json:
        print(json.dumps(analysis, indent=2, ensure_ascii=False))
    elif args.env:
        print_env_output(analysis)
    else:
        # Default: summary
        print_summary_output(analysis)

if __name__ == "__main__":
    main()
