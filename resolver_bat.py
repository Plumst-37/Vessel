#!/usr/bin/env python3
# ==============================================================================
# RESOLVEDOR UNIVERSAL DE SCRIPTS BATCH DE WINDOWS (.BAT / .CMD)
# Extrae el ejecutable real (.exe) para omitir bucles infinitos de CPU (tasklist, wmic)
# y ejecutar juegos directamente con el máximo rendimiento en Linux
# ==============================================================================

import os
import sys
import re

SYSTEM_EXES = {
    'cacls.exe', 'cmd.exe', 'explorer.exe', 'wmic.exe', 'powershell.exe',
    'tasklist.exe', 'taskkill.exe', 'net.exe', 'reg.exe', 'mshta.exe',
    'rundll32.exe', 'cscript.exe', 'wscript.exe', 'find.exe', 'timeout.exe',
    'where.exe', 'pause.exe', 'cls.exe', 'conhost.exe', 'attrib.exe'
}

def resolve_bat(bat_path):
    if not os.path.isfile(bat_path):
        return {"status": "NOT_FOUND", "error": f"Archivo no existe: {bat_path}"}

    bat_dir = os.path.dirname(os.path.abspath(bat_path))
    bat_base = os.path.splitext(os.path.basename(bat_path))[0]

    try:
        with open(bat_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception as e:
        return {"status": "ERROR", "error": str(e)}

    # 1. Buscar cambios de directorio comunes en scripts de juegos (ej: cd /d "%~dp0\gamedata")
    search_dirs = [bat_dir]
    for line in lines:
        line_clean = line.strip()
        cd_match = re.search(r'(?:cd\s+/d|pushd)\s+["\']?([^"\']+)["\']?', line_clean, re.IGNORECASE)
        if cd_match:
            sub = cd_match.group(1).replace('%~dp0', '').replace('%~sdp0', '').replace('\\', '/').strip('/\\')
            candidate_dir = os.path.join(bat_dir, sub)
            if os.path.isdir(candidate_dir) and candidate_dir not in search_dirs:
                search_dirs.insert(0, candidate_dir)

    # 2. Buscar ejecutables en llamadas 'start', directas o asignaciones (set EXE=...)
    candidate_exes = []
    for line in lines:
        line_clean = line.strip()
        # Ignorar comentarios :: o rem
        if line_clean.startswith('::') or line_clean.lower().startswith('rem '):
            continue

        # Casos con start
        if re.search(r'\bstart\b', line_clean, re.IGNORECASE):
            exes = re.findall(r'["\']?([a-zA-Z0-9_\-\.\\]+\.exe)["\']?', line_clean, re.IGNORECASE)
            for ex in exes:
                base = os.path.basename(ex.replace('\\', '/'))
                if base.lower() not in SYSTEM_EXES and base not in candidate_exes:
                    candidate_exes.append(base)

        # Casos con set EXE=...
        set_match = re.search(r'set\s+[a-zA-Z0-9_]*EXE[a-zA-Z0-9_]*=([^\r\n]+)', line_clean, re.IGNORECASE)
        if set_match:
            val = set_match.group(1).strip().strip('"\'')
            if not val.lower().endswith('.exe'):
                val += '.exe'
            base = os.path.basename(val.replace('\\', '/'))
            if base.lower() not in SYSTEM_EXES and base not in candidate_exes:
                candidate_exes.append(base)

    # 3. Buscar el archivo ejecutable candidato en los directorios de búsqueda
    for c_exe in candidate_exes:
        for s_dir in search_dirs:
            exact_path = os.path.join(s_dir, c_exe)
            if os.path.isfile(exact_path):
                return {
                    "status": "RESOLVED",
                    "path": os.path.abspath(exact_path),
                    "name": bat_base,
                    "target_exe": c_exe
                }

        # Búsqueda recursiva hasta 3 niveles
        for s_dir in search_dirs:
            for root, dirs, files in os.walk(s_dir):
                rel_depth = len(os.path.relpath(root, s_dir).split(os.sep))
                if rel_depth > 3:
                    continue
                for f in files:
                    if f.lower() == c_exe.lower():
                        return {
                            "status": "RESOLVED",
                            "path": os.path.abspath(os.path.join(root, f)),
                            "name": bat_base,
                            "target_exe": c_exe
                        }

    # 4. Fallback: buscar cualquier .exe de juego en el directorio o subdirectorios
    fallback_exes = []
    for s_dir in search_dirs:
        for root, dirs, files in os.walk(s_dir):
            rel_depth = len(os.path.relpath(root, s_dir).split(os.sep))
            if rel_depth > 2:
                continue
            for f in files:
                if f.lower().endswith('.exe'):
                    fl = f.lower()
                    if fl not in SYSTEM_EXES and not any(k in fl for k in ['unins', 'setup', 'dxsetup', 'vcredist', 'crashpad', 'helper', 'reporter']):
                        fallback_exes.append(os.path.abspath(os.path.join(root, f)))

    if len(fallback_exes) == 1:
        return {
            "status": "RESOLVED",
            "path": fallback_exes[0],
            "name": bat_base,
            "target_exe": os.path.basename(fallback_exes[0])
        }

    return {"status": "NOT_RESOLVED", "candidates": candidate_exes}

def main():
    if len(sys.argv) < 2:
        print("Uso: resolver_bat.py <archivo.bat/.cmd>")
        sys.exit(1)

    bat_file = sys.argv[1]
    result = resolve_bat(bat_file)

    print(f"STATUS={result.get('status', 'UNKNOWN')}")
    if result.get("status") == "RESOLVED":
        print(f"RESOLVED_PATH={result.get('path', '')}")
        print(f"NAME={result.get('name', '')}")
        print(f"TARGET_EXE={result.get('target_exe', '')}")
    else:
        print(f"ERROR={result.get('error', 'No se pudo resolver el ejecutable')}")

if __name__ == "__main__":
    main()
