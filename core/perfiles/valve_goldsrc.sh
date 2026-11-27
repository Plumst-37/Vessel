#!/usr/bin/env bash
# ==============================================================================
# VESSEL - PERFIL MODULAR: valve_goldsrc
# ==============================================================================

            echo "[+] Perfil Activo: Valve GoldSrc Engine (Half-Life / CS 1.6) [Aislado]"
            # Limpiar instancias colgadas previas para evitar error 'The game could not be started because it is already running'
            limpiar_zombies_juego "cstrike\.exe|hl\.exe|czero\.exe|hltv\.exe|crashpad_handler\.exe"
            sleep 0.2

            # 1. Parche proactivo y universal para el hook WinHttpCloseHandle en NextClient / No-Steam
            # Evita crash por desreferenciación de puntero nulo en Wine (STATUS_ACCESS_VIOLATION 0xc0000005)
            patch_target="$TARGET"
            [ ! -f "$patch_target" ] && [ -f "${TARGET_DIR}/cstrike.exe" ] && patch_target="${TARGET_DIR}/cstrike.exe"
            [ ! -f "$patch_target" ] && [ -f "${TARGET_DIR}/hl.exe" ] && patch_target="${TARGET_DIR}/hl.exe"
            if [ -f "$patch_target" ] && [ -w "$patch_target" ]; then
                python3 -c '
import sys, shutil, os
target = sys.argv[1]
try:
    with open(target, "rb") as f:
        data = f.read()
    sig = bytes.fromhex("85f67414813eb8020000750c")
    pos = data.find(sig)
    if pos != -1:
        bak = target + ".vessel_bak"
        if not os.path.exists(bak):
            shutil.copy2(target, bak)
        patch = bytes.fromhex("eb1690909090909090909090")
        with open(target, "r+b") as f:
            f.seek(pos)
            f.write(patch)
        print("[+] Parche de estabilidad Wine WinHttp aplicado exitosamente en", target)
except Exception:
    pass
' "$patch_target" 2>/dev/null || true
            fi

            # 2. Renderizador: OpenGL nativo del sistema (hw.dll se comunica directamente con OpenGL / Mesa / NVIDIA)
            export RENDERER_IN_USE="OpenGL Nativo (Valve GoldSrc)"
            export PROTON_USE_WINED3D=1
            unset DXVK_CONFIG_FILE
            export DXVK_HUD=0
            unset SDL_VIDEODRIVER

            # 3. Desactivar FSR de Wine (evita conflictos con CEF / Chromium Embedded Framework y con el backend OpenGL)
            ACTIVAR_FSR_FINAL=0
            export WINE_FULLSCREEN_FSR=0

            # 4. Forzar librerías DX builtin para que no interfiera DXVK con CEF ni hw.dll
            export WINEDLLOVERRIDES="d3d9=b;d3d11=b;dxgi=b;d3d8=b;${WINEDLLOVERRIDES}"

            # 5. Auto-reparar configuración de video en el registro de Wine para GoldSrc
            # Elimina el indicador de colapso previo que dispara el diálogo de error de renderizado y asegura OpenGL nativo
            local goldsrc_w="${best_w}"
            local goldsrc_h="${best_h}"
            # Snapping para resoluciones atípicas que GoldSrc / SDL2 rechaza en Linux (como 1366x768 -> 1360x768 o 1280x720)
            if [ "$goldsrc_w" -eq 1366 ]; then
                goldsrc_w=1360
            fi

            # Inyectar configuración de video óptima en el registro en una sola transacción ultra-rápida
            # IMPORTANTE: En Linux (Xwayland / Wine), ScreenWindowed=1 + borderless evita llamadas a ChangeDisplaySettingsEx
            # en el servidor X, previniendo al 100% el fallo "Failed to create SDL Window"
            if pgrep -x wineserver >/dev/null 2>&1; then
                "$WINE_CMD" regedit /S - << EOF >/dev/null 2>&1 || true
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Valve\Half-Life\Settings]
"CrashInitializingVideoMode"=dword:00000000
"EngineDLL"="hw.dll"
"EngineD3D"=dword:00000000
"ScreenWidth"=dword:$(printf "%08x" "${goldsrc_w}")
"ScreenHeight"=dword:$(printf "%08x" "${goldsrc_h}")
"ScreenBPP"=dword:00000020
"ScreenWindowed"=dword:00000001
EOF
            else
                python3 -c '
import os, sys, re, time
prefix = sys.argv[1]
w = int(sys.argv[2])
h = int(sys.argv[3])
user_reg = os.path.join(prefix, "user.reg")
if os.path.exists(user_reg):
    try:
        with open(user_reg, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
        section = "[Software\\\\Valve\\\\Half-Life\\\\Settings]"
        keys = {
            "\"CrashInitializingVideoMode\"": "dword:00000000",
            "\"EngineDLL\"": "\"hw.dll\"",
            "\"EngineD3D\"": "dword:00000000",
            "\"ScreenWidth\"": f"dword:{w:08x}",
            "\"ScreenHeight\"": f"dword:{h:08x}",
            "\"ScreenBPP\"": "dword:00000020",
            "\"ScreenWindowed\"": "dword:00000001",
        }
        if section in content:
            def update_sect(m):
                header = m.group(1)
                body = m.group(2)
                lines = body.splitlines()
                k_seen = set()
                new_lines = []
                for l in lines:
                    matched = False
                    for k, v in keys.items():
                        if l.startswith(k + "="):
                            new_lines.append(f"{k}={v}")
                            k_seen.add(k)
                            matched = True
                            break
                    if not matched:
                        new_lines.append(l)
                for k, v in keys.items():
                    if k not in k_seen:
                        new_lines.append(f"{k}={v}")
                return header + "\n".join(new_lines) + "\n"
            content = re.sub(r"(\[Software\\\\Valve\\\\Half-Life\\\\Settings\][^\n]*\n)(.*?)((?=\n\[)|\Z)",
                             update_sect, content, flags=re.DOTALL)
        else:
            ts = int(time.time())
            new_block = f"\n{section} {ts}\n#time=0\n"
            for k, v in keys.items():
                new_block += f"{k}={v}\n"
            content += new_block
        with open(user_reg, "w", encoding="utf-8") as f:
            f.write(content)
    except Exception:
        pass
' "$WINEPREFIX" "$goldsrc_w" "$goldsrc_h" 2>/dev/null || true
            fi

            # 6. Argumentos óptimos para GoldSrc (OpenGL nativo sin FBO conflictivo, resolución nativa, mouse crudo)
            goldsrc_game="cstrike"
            if [ -d "${TARGET_DIR}/cstrike" ]; then
                goldsrc_game="cstrike"
            elif [ -d "${TARGET_DIR}/czero" ]; then
                goldsrc_game="czero"
            elif [ -d "${TARGET_DIR}/valve" ]; then
                goldsrc_game="valve"
            fi

            if [[ ! "$EXTRA_APP_ARGS" =~ "-game" ]]; then
                EXTRA_APP_ARGS="-game ${goldsrc_game} ${EXTRA_APP_ARGS}"
            fi
            if [[ ! "$EXTRA_APP_ARGS" =~ "-gl" ]]; then
                EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -gl"
            fi
            if [[ ! "$EXTRA_APP_ARGS" =~ "-nofbo" ]]; then
                EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -nofbo -nomsaa"
            fi
            if [[ ! "$EXTRA_APP_ARGS" =~ "-noforcemaccel" ]]; then
                EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -noforcemaccel -noforcemparms -noforcemspd"
            fi
            # Eliminar -full / -fullscreen para evitar que SDL2 intente cambiar modos de hardware en Xwayland
            EXTRA_APP_ARGS=$(echo "$EXTRA_APP_ARGS" | sed -E 's/-full(screen)?//g')
            if [[ ! "$EXTRA_APP_ARGS" =~ "-window" ]] && [[ ! "$EXTRA_APP_ARGS" =~ "-sw" ]]; then
                EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -window"
            fi
            if [[ ! "$EXTRA_APP_ARGS" =~ "-noborder" ]]; then
                EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -noborder"
            fi
            if [[ ! "$EXTRA_APP_ARGS" =~ "-w " ]]; then
                EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -w ${goldsrc_w} -h ${goldsrc_h}"
            fi
            if [[ ! "$EXTRA_APP_ARGS" =~ "-noupdate" ]]; then
                EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -noupdate"
            fi
            EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -stretchaspect -num_edicts 4096"
