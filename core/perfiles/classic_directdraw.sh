#!/usr/bin/env bash
# ==============================================================================
# VESSEL - PERFIL MODULAR: classic_directdraw
# ==============================================================================

echo "[+] Perfil Activo: Clásico DirectDraw Universal (OpenGL / Multi-GPU) [Aislado]"
# 1. Modo Windows XP automático en Wine AppDefaults para este juego (elimina incompatibilidad de paleta en Win10)
"$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${TARGET_FILE}" /v "Version" /t REG_SZ /d "winxp" /f >/dev/null 2>&1 || true

# 2. Conmutación universal a OpenGL (compatible al 100% en Intel, AMD y NVIDIA sin fallos de paleta 8-bit)
export PROTON_USE_WINED3D=1
export RENDERER_IN_USE="OpenGL Universal (DirectDraw Clásico)"
unset DXVK_CONFIG_FILE
export DXVK_HUD=0

# 2.1 Auto-inyección de cnc-ddraw si está disponible en caché local y no en el juego
if [ ! -f "${TARGET_DIR}/ddraw.dll" ] && [ -f "${DIR}/librerias_cache/cnc-ddraw/ddraw.dll" ]; then
    echo "[+] Inyectando cnc-ddraw desde caché de Vessel para compatibilidad DirectX 1-7 perfecta..."
    cp -p "${DIR}/librerias_cache/cnc-ddraw/ddraw.dll" "${TARGET_DIR}/ddraw.dll" 2>/dev/null || true
    [ -d "${DIR}/librerias_cache/cnc-ddraw/shaders" ] && cp -rn "${DIR}/librerias_cache/cnc-ddraw/shaders" "${TARGET_DIR}/" 2>/dev/null || true
    [ -f "${DIR}/librerias_cache/cnc-ddraw/ddraw.ini" ] && cp -n "${DIR}/librerias_cache/cnc-ddraw/ddraw.ini" "${TARGET_DIR}/ddraw.ini" 2>/dev/null || true
fi

# 3. Optimización automática de cnc-ddraw en OpenGL
find "$TARGET_DIR" -maxdepth 2 -iname "ddraw.ini" 2>/dev/null | while read -r ddini; do
    crear_respaldo_seguro "$ddini"
    sed -i 's/^renderer=.*/renderer=opengl/' "$ddini" 2>/dev/null || true
    sed -i 's/^fullscreen=.*/fullscreen=true/' "$ddini" 2>/dev/null || true
    sed -i 's/^windowed=.*/windowed=false/' "$ddini" 2>/dev/null || true
    sed -i "s/^width=.*/width=${best_w}/" "$ddini" 2>/dev/null || true
    sed -i "s/^height=.*/height=${best_h}/" "$ddini" 2>/dev/null || true
    sed -i 's/^boxing=.*/boxing=false/' "$ddini" 2>/dev/null || true
    sed -i 's/^maintas=.*/maintas=false/' "$ddini" 2>/dev/null || true
    if [ -f "${TARGET_DIR}/Shaders/interpolation/catmull-rom-bilinear.glsl" ]; then
        sed -i 's|^shader=.*|shader=Shaders\\interpolation\\catmull-rom-bilinear.glsl|' "$ddini" 2>/dev/null || true
    else
        sed -i 's|^shader=.*|shader=Bilinear|' "$ddini" 2>/dev/null || true
    fi
done

# 4. Configurar DirectDraw nativo en el registro de Wine (para juegos sin cnc-ddraw)
"$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "DirectDrawRenderer" /t REG_SZ /d "opengl" /f >/dev/null 2>&1 || true
"$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\Direct3D" /v "OffscreenRenderingMode" /t REG_SZ /d "fbo" /f >/dev/null 2>&1 || true

# 5. Overrides seguros: ddraw y dsound nativos (para cnc-ddraw), y librerías 3D a builtin (WineD3D OpenGL)
export WINEDLLOVERRIDES="ddraw=n,b;dsound=n,b;d3d9=b;d3d11=b;dxgi=b;d3d8=b;${WINEDLLOVERRIDES}"
