#!/usr/bin/env python3
# ==============================================================================
# RESOLVEDOR UNIVERSAL DE ACCESOS DIRECTOS DE WINDOWS (.LNK / .INK)
# Extrae el ejecutable real (.exe/.bat/.cmd) desde archivos .lnk o .ink
# Compatible con Linux (Wine, Proton, Vessel)
# ==============================================================================

import os
import sys
import re

def resolve_lnk(lnk_path, wineprefix=None):
    if not os.path.isfile(lnk_path):
        return {"status": "NOT_FOUND", "error": f"Archivo no existe: {lnk_path}"}

    lnk_dir = os.path.dirname(os.path.abspath(lnk_path))
    lnk_base = os.path.splitext(os.path.basename(lnk_path))[0]

    # 1. Comprobar si el archivo es directamente un ejecutable PE de Windows (MZ header)
    # Puede ocurrir si un usuario renombró directamente un .exe a .ink o .lnk
    try:
        with open(lnk_path, 'rb') as f:
            magic = f.read(4)
            if magic[:2] == b'MZ':
                return {
                    "status": "RESOLVED",
                    "path": os.path.abspath(lnk_path),
                    "name": lnk_base,
                    "type": "PE_EXE",
                    "args": ""
                }
    except Exception:
        pass

    # 2. Leer contenido binario del acceso directo (.lnk / .ink)
    try:
        with open(lnk_path, 'rb') as f:
            content = f.read()
    except Exception as e:
        return {"status": "ERROR", "error": str(e)}

    # Extraer cadenas legibles ASCII y UTF-16LE
    ascii_strings = [s.decode('ascii', errors='ignore') for s in re.findall(b'[\x20-\x7e]{3,}', content)]
    utf16_strings = [s.decode('utf-16le', errors='ignore') for s in re.findall(b'(?:[\x20-\x7e]\x00){3,}', content)]
    all_strings = ascii_strings + utf16_strings

    win_paths = []
    exe_names = []

    # Buscar rutas de Windows con letra de unidad (C:\..., D:\..., Z:\...)
    for s in all_strings:
        s_clean = s.strip()
        if re.match(r'^[a-zA-Z]:[\\/]', s_clean):
            if s_clean not in win_paths:
                win_paths.append(s_clean)
        elif s_clean.lower().endswith(('.exe', '.bat', '.cmd', '.msi')):
            cleaned_name = s_clean.replace('\\\\', '/').replace('\\', '/')
            base = os.path.basename(cleaned_name)
            if base and base not in exe_names:
                exe_names.append(base)

    # 3. Comprobar prefijos de Wine (dosdevices y drive_c)
    prefixes_to_check = []
    if wineprefix and os.path.isdir(wineprefix):
        prefixes_to_check.append(wineprefix)
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    default_prefix = os.path.join(script_dir, 'wineprefix')
    if default_prefix not in prefixes_to_check and os.path.isdir(default_prefix):
        prefixes_to_check.append(default_prefix)

    for prefix in prefixes_to_check:
        dosdevices = os.path.join(prefix, 'dosdevices')
        drive_c = os.path.join(prefix, 'drive_c')

        for wp in win_paths:
            drive_match = re.match(r'^([a-zA-Z]):[\\/]+(.*)', wp)
            if not drive_match:
                continue
            drive_letter = drive_match.group(1).lower()
            rel_win = drive_match.group(2).replace('\\\\', '/').replace('\\', '/')

            # Caso 3a: Mapeo por dosdevices (ej. dosdevices/c:, dosdevices/z:)
            if os.path.isdir(dosdevices):
                dev_link = os.path.join(dosdevices, f"{drive_letter}:")
                if os.path.exists(dev_link):
                    target_dev = os.path.join(dev_link, rel_win)
                    if os.path.isfile(target_dev):
                        return {
                            "status": "RESOLVED",
                            "path": os.path.realpath(target_dev),
                            "name": lnk_base,
                            "target_win": wp,
                            "type": "DOSDEVICES_MATCH",
                            "args": ""
                        }

            # Caso 3b: Drive C
            if drive_letter == 'c' and os.path.isdir(drive_c):
                cand = os.path.join(drive_c, rel_win)
                if os.path.isfile(cand):
                    return {
                        "status": "RESOLVED",
                        "path": os.path.abspath(cand),
                        "name": lnk_base,
                        "target_win": wp,
                        "type": "PREFIX_MATCH",
                        "args": ""
                    }

                # Búsqueda case-insensitive componente por componente en drive_c
                parts = [p for p in rel_win.split('/') if p]
                curr = drive_c
                matched = True
                for part in parts:
                    if not os.path.isdir(curr):
                        matched = False
                        break
                    found_entry = None
                    try:
                        for entry in os.listdir(curr):
                            if entry.lower() == part.lower():
                                found_entry = entry
                                break
                    except Exception:
                        matched = False
                        break
                    if found_entry:
                        curr = os.path.join(curr, found_entry)
                    else:
                        matched = False
                        break

                if matched and os.path.isfile(curr):
                    return {
                        "status": "RESOLVED",
                        "path": os.path.abspath(curr),
                        "name": lnk_base,
                        "target_win": wp,
                        "type": "PREFIX_MATCH_CI",
                        "args": ""
                    }

            # Caso 3c: Drive Z (mapeado directamente a la raíz de Linux /)
            if drive_letter == 'z':
                linux_path = '/' + rel_win
                if os.path.isfile(linux_path):
                    return {
                        "status": "RESOLVED",
                        "path": os.path.abspath(linux_path),
                        "name": lnk_base,
                        "target_win": wp,
                        "type": "Z_ROOT_MATCH",
                        "args": ""
                    }

    # 4. Intentar resolver relativo a la carpeta del acceso directo (.lnk / .ink)
    # (Típico en juegos portables donde el .lnk o .ink está en la misma carpeta o subcarpeta)
    for ename in exe_names:
        # 4a. Mismo directorio
        direct = os.path.join(lnk_dir, ename)
        if os.path.isfile(direct):
            return {
                "status": "RESOLVED",
                "path": os.path.abspath(direct),
                "name": lnk_base,
                "type": "LOCAL_MATCH",
                "args": ""
            }

        # 4b. En subcarpetas de la carpeta del juego (hasta 3 niveles)
        for root, dirs, files in os.walk(lnk_dir):
            rel_depth = len(os.path.relpath(root, lnk_dir).split(os.sep))
            if rel_depth > 3:
                continue
            for f in files:
                if f.lower() == ename.lower():
                    cand_path = os.path.join(root, f)
                    return {
                        "status": "RESOLVED",
                        "path": os.path.abspath(cand_path),
                        "name": lnk_base,
                        "type": "LOCAL_SUBDIR_MATCH",
                        "args": ""
                    }

    # 4c. Sufijos de las rutas encontradas dentro de lnk_dir
    for wp in win_paths:
        parts = [p for p in wp.replace('\\\\', '/').replace('\\', '/').split('/') if p and not re.match(r'^[a-zA-Z]:', p)]
        for i in range(len(parts)):
            subpath = os.path.join(lnk_dir, *parts[i:])
            if os.path.isfile(subpath):
                return {
                    "status": "RESOLVED",
                    "path": os.path.abspath(subpath),
                    "name": lnk_base,
                    "type": "LOCAL_SUFFIX_MATCH",
                    "args": ""
                }

    # 5. Si no se encontró el ejecutable con el nombre exacto,
    # escanear ejecutables .exe presentes en la carpeta del .lnk
    local_exes = []
    try:
        for root, dirs, files in os.walk(lnk_dir):
            rel_depth = len(os.path.relpath(root, lnk_dir).split(os.sep))
            if rel_depth > 2:
                continue
            for f in files:
                if f.lower().endswith(('.exe', '.bat')):
                    fl = f.lower()
                    if not any(k in fl for k in ['unins', 'setup', 'dxsetup', 'vcredist', 'crashpad', 'helper', 'crash_reporter']):
                        local_exes.append(os.path.abspath(os.path.join(root, f)))
    except Exception:
        pass

    if len(local_exes) == 1:
        return {
            "status": "RESOLVED",
            "path": local_exes[0],
            "name": lnk_base,
            "type": "SINGLE_LOCAL_EXE",
            "args": ""
        }
    elif len(local_exes) > 1:
        return {
            "status": "MULTIPLE_CANDIDATES",
            "candidates": local_exes,
            "name": lnk_base,
            "win_paths": win_paths,
            "exe_names": exe_names
        }

    return {
        "status": "NOT_RESOLVED",
        "name": lnk_base,
        "win_paths": win_paths,
        "exe_names": exe_names
    }

def main():
    if len(sys.argv) < 2:
        print("Uso: resolver_lnk.py <archivo.lnk/.ink> [wineprefix]")
        sys.exit(1)

    lnk_file = sys.argv[1]
    wineprefix = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("WINEPREFIX")

    result = resolve_lnk(lnk_file, wineprefix)

    print(f"STATUS={result.get('status', 'UNKNOWN')}")
    if result.get("status") == "RESOLVED":
        print(f"RESOLVED_PATH={result.get('path', '')}")
        print(f"NAME={result.get('name', '')}")
        print(f"TYPE={result.get('type', '')}")
        print(f"ARGS={result.get('args', '')}")
    elif result.get("status") == "MULTIPLE_CANDIDATES":
        print(f"NAME={result.get('name', '')}")
        print(f"CANDIDATES={'|'.join(result.get('candidates', []))}")
        print(f"WIN_PATHS={'|'.join(result.get('win_paths', []))}")
    else:
        print(f"NAME={result.get('name', '')}")
        print(f"WIN_PATHS={'|'.join(result.get('win_paths', []))}")
        print(f"EXE_NAMES={'|'.join(result.get('exe_names', []))}")

if __name__ == "__main__":
    main()
