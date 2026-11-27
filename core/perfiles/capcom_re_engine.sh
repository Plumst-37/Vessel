#!/usr/bin/env bash
# ==============================================================================
# VESSEL - PERFIL MODULAR: capcom_re_engine
# ==============================================================================

echo "[+] Perfil Activo: Capcom RE Engine [Aislado]"
# RE Engine es un motor moderno (DirectX 12 / 64-bit), asegurar modo Windows 10 en Wine
"$WINE_CMD" reg add "HKEY_CURRENT_USER\Software\Wine\AppDefaults\\${TARGET_FILE}" /v "Version" /t REG_SZ /d "win10" /f >/dev/null 2>&1 || true
GAME_WINVER="win10"
limpiar_zombies_juego "re4\.exe|re2\.exe|re3\.exe|re7\.exe|re8\.exe|dmc5\.exe"

# 1. Auto-vincular o copiar DLLs de VKD3D-Proton (DirectX 12) a la raíz si están en subcarpetas
for sub_vkd3d in "${TARGET_DIR}/dxvk" "${TARGET_DIR}/vkd3d" "${TARGET_DIR}/_CommonRedist"; do
    if [ -d "$sub_vkd3d" ]; then
        if [ -f "${sub_vkd3d}/d3d12.dll" ]; then
            if [ ! -f "${TARGET_DIR}/d3d12.dll" ] || [ ! -s "${TARGET_DIR}/d3d12.dll" ]; then
                cp -f "${sub_vkd3d}/d3d12.dll" "${TARGET_DIR}/" 2>/dev/null || true
            fi
            if [ -f "${sub_vkd3d}/d3d12core.dll" ] && { [ ! -f "${TARGET_DIR}/d3d12core.dll" ] || [ ! -s "${TARGET_DIR}/d3d12core.dll" ]; }; then
                cp -f "${sub_vkd3d}/d3d12core.dll" "${TARGET_DIR}/" 2>/dev/null || true
            fi
            if [ -d "${TARGET_DIR}/D3D12" ] && [ -f "${sub_vkd3d}/d3d12core.dll" ]; then
                cp -f "${sub_vkd3d}/d3d12core.dll" "${TARGET_DIR}/D3D12/D3D12Core.dll" 2>/dev/null || true
            fi
        fi
    fi
done
# Reemplazar la DLL oficial de Microsoft Windows por la de Vulkan en D3D12/ si existe d3d12core.dll
if [ -d "${TARGET_DIR}/D3D12" ] && [ -f "${TARGET_DIR}/d3d12core.dll" ]; then
    cp -f "${TARGET_DIR}/d3d12core.dll" "${TARGET_DIR}/D3D12/D3D12Core.dll" 2>/dev/null || true
fi

# 2. Desactivar Ray Tracing (DXR) y extensiones inestables en GPUs Maxwell/Pascal (NVIDIA MX/GTX)
export VKD3D_CONFIG="nodxr"
export VKD3D_FEATURE_LEVEL="12_0"
export VKD3D_DISABLE_EXTENSIONS="VK_EXT_descriptor_buffer"

# 3. Aplicar perfil optimizado de bajo consumo si existe en opti/local_config.ini
if [ -f "${TARGET_DIR}/opti/local_config.ini" ]; then
    if [ ! -f "${TARGET_DIR}/local_config.ini.vessel_orig" ]; then
        crear_respaldo_seguro "${TARGET_DIR}/local_config.ini"
    fi
    cp -f "${TARGET_DIR}/opti/local_config.ini" "${TARGET_DIR}/local_config.ini" 2>/dev/null || true
    if [ -f "${TARGET_DIR}/opti/local_config_default.ini" ]; then
        cp -f "${TARGET_DIR}/opti/local_config_default.ini" "${TARGET_DIR}/local_config_default.ini" 2>/dev/null || true
    fi
fi

# 4. Limpiar adaptadores gráficos ajenos hardcodeados en local_config.ini / *config*.ini
find "$TARGET_DIR" -maxdepth 3 -iname "*config*.ini" 2>/dev/null | while read -r c_ini; do
    if grep -qi "\[Render/Adapter\]" "$c_ini" 2>/dev/null || grep -qi "VendorId=" "$c_ini" 2>/dev/null; then
        crear_respaldo_seguro "$c_ini"
        sed -i '/\[Render\/Adapter\]/,/^\[/ { /^\[Render\/Adapter\]/d; /^Description=/d; /^VendorId=/d; /^DeviceId=/d; /^SubSysId=/d; /^Revision=/d; }' "$c_ini" 2>/dev/null || true
        sed -i '/^Description=.*Graphics/d; /^VendorId=[0-9]*/d; /^DeviceId=[0-9]*/d; /^SubSysId=[0-9]*/d; /^Revision=[0-9]*/d' "$c_ini" 2>/dev/null || true
    fi
done

# 5. Configurar visualización óptima en configs de RE Engine (Modo Ventana Sin Bordes / Borderless)
find "$TARGET_DIR" -maxdepth 3 -name "*config*.ini" 2>/dev/null | while read -r re_ini; do
    if grep -q "\[AppRender\]" "$re_ini" 2>/dev/null || grep -q "\[RenderConfig\]" "$re_ini" 2>/dev/null; then
        crear_respaldo_seguro "$re_ini"
        sed -i 's/^FullScreenMode=.*/FullScreenMode=false/' "$re_ini" 2>/dev/null || true
        sed -i 's/^WindowMode=.*/WindowMode=Borderless/' "$re_ini" 2>/dev/null || true
        sed -i 's/^AppWindowMode=.*/AppWindowMode=1/' "$re_ini" 2>/dev/null || true
        sed -i 's/^AppRenderingMethod=.*/AppRenderingMethod=1/' "$re_ini" 2>/dev/null || true
        sed -i 's/^AppLensDistorsion=.*/AppLensDistorsion=0/' "$re_ini" 2>/dev/null || true
        sed -i 's/^AppMotionBlur=.*/AppMotionBlur=0/' "$re_ini" 2>/dev/null || true
        sed -i 's/^AppFilmGrainNoise=.*/AppFilmGrainNoise=0/' "$re_ini" 2>/dev/null || true
        sed -i 's/^AppVsync=.*/AppVsync=1/' "$re_ini" 2>/dev/null || true
        # Calibrar texturas a nivel óptimo nítido con FSR2 Quality en GPUs de entrada
        if [ "$IS_LOW_SPEC_GPU" = "true" ]; then
            sed -i 's/^AppTextureQuality=.*/AppTextureQuality=3/' "$re_ini" 2>/dev/null || true
            sed -i 's/^AppImageQuality=.*/AppImageQuality=1/' "$re_ini" 2>/dev/null || true
            sed -i 's/^AppUpScalingTypeFSR2=.*/AppUpScalingTypeFSR2=1/' "$re_ini" 2>/dev/null || true
            sed -i 's/^AppAntiAliasing=.*/AppAntiAliasing=1/' "$re_ini" 2>/dev/null || true
            sed -i 's/^AppMeshQuality=.*/AppMeshQuality=1/' "$re_ini" 2>/dev/null || true
        fi
        sed -i 's/^AppRayTraceOnOff=.*/AppRayTraceOnOff=0/' "$re_ini" 2>/dev/null || true
        if grep -q "^NormalWindowResolution=" "$re_ini" 2>/dev/null; then
            sed -i "s/^NormalWindowResolution=.*/NormalWindowResolution=(${best_w}.000000,${best_h}.000000)/" "$re_ini" 2>/dev/null || true
        fi
        local dm_idx
        dm_idx=$(grep -B 1 "DisplayMode[0-9]*_Height=${best_h}" "$re_ini" 2>/dev/null | grep -E "DisplayMode[0-9]*_Width=${best_w}" | head -n 1 | grep -oE "DisplayMode[0-9]+" | tr -d 'DisplayMode')
        if [ -n "$dm_idx" ]; then
            sed -i "s/^AppResolution=.*/AppResolution=${dm_idx}/" "$re_ini" 2>/dev/null || true
            sed -i "s/^FullScreenDisplayMode=.*/FullScreenDisplayMode=${dm_idx}/" "$re_ini" 2>/dev/null || true
        fi
    fi
done
export WINEDLLOVERRIDES="EMP=n;d3d12=n,b;d3d12core=n,b;dxgi=n,b;d3d11=n,b;d3dcompiler_47=n,b;dinput8=n,b;version=n,b;xinput1_3=n,b;xinput1_4=n,b;${WINEDLLOVERRIDES}"
