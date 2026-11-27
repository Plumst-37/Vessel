#!/usr/bin/env bash
# ==============================================================================
# VESSEL - PERFIL MODULAR: unreal_engine
# ==============================================================================

echo "[+] Perfil Activo: Unreal Engine (SWAT 4 / Clásicos 3D) [Aislado]"
limpiar_zombies_juego "Swat4\.exe|Swat4X\.exe|Bioshock\.exe"
local target_system_dir="$TARGET_DIR"
[ -d "${TARGET_DIR}/System" ] && target_system_dir="${TARGET_DIR}/System"
[ -d "${TARGET_DIR}/Content/System" ] && target_system_dir="${TARGET_DIR}/Content/System"

local target_fov="100.000000"
if [ "$best_h" -gt 0 ]; then
    local aspect_ratio_int=$(( (best_w * 100) / best_h ))
    if [ "$aspect_ratio_int" -ge 170 ]; then
        target_fov="100.000000"
    elif [ "$aspect_ratio_int" -ge 150 ]; then
        target_fov="95.000000"
    else
        target_fov="85.000000"
    fi
fi

find "$target_system_dir" -maxdepth 2 -name "*.ini" 2>/dev/null | while read -r ueini; do
    if grep -q "\[WinDrv.WindowsClient\]\|\[D3DDrv.D3DRenderDevice\]\|\[/Script/Engine.GameUserSettings\]" "$ueini" 2>/dev/null; then
        crear_respaldo_seguro "$ueini"
    fi
    if grep -q "\[WinDrv.WindowsClient\]" "$ueini" 2>/dev/null; then
        sed -i 's/^StartupFullscreen=False/StartupFullscreen=True/' "$ueini" 2>/dev/null || true
        sed -i "s/^FullscreenViewportX=[0-9]*/FullscreenViewportX=${best_w}/" "$ueini" 2>/dev/null || true
        sed -i "s/^FullscreenViewportY=[0-9]*/FullscreenViewportY=${best_h}/" "$ueini" 2>/dev/null || true
        sed -i "s/^WindowedViewportX=[0-9]*/WindowedViewportX=${best_w}/" "$ueini" 2>/dev/null || true
        sed -i "s/^WindowedViewportY=[0-9]*/WindowedViewportY=${best_h}/" "$ueini" 2>/dev/null || true
    fi
    if grep -q "\[D3DDrv.D3DRenderDevice\]" "$ueini" 2>/dev/null; then
        sed -i 's/^UseVSync=False/UseVSync=True/' "$ueini" 2>/dev/null || true
        sed -i 's/^LevelOfAnisotropy=[0-9]*/LevelOfAnisotropy=16/' "$ueini" 2>/dev/null || true
        sed -i 's/^Use16bit=True/Use16bit=False/' "$ueini" 2>/dev/null || true
        sed -i 's/^Use16bitTextures=True/Use16bitTextures=False/' "$ueini" 2>/dev/null || true
        sed -i 's/^ReduceMouseLag=False/ReduceMouseLag=True/' "$ueini" 2>/dev/null || true
    fi
    if grep -q "\[/Script/Engine.GameUserSettings\]" "$ueini" 2>/dev/null; then
        sed -i 's/^FullscreenMode=[0-9]*/FullscreenMode=0/' "$ueini" 2>/dev/null || true
        sed -i 's/^PreferredFullscreenMode=[0-9]*/PreferredFullscreenMode=0/' "$ueini" 2>/dev/null || true
        sed -i 's/^LastConfirmedFullscreenMode=[0-9]*/LastConfirmedFullscreenMode=0/' "$ueini" 2>/dev/null || true
        sed -i "s/^ResolutionSizeX=[0-9]*/ResolutionSizeX=${best_w}/" "$ueini" 2>/dev/null || true
        sed -i "s/^ResolutionSizeY=[0-9]*/ResolutionSizeY=${best_h}/" "$ueini" 2>/dev/null || true
    fi
    if grep -q "DesiredFOV=" "$ueini" 2>/dev/null || grep -q "DefaultFOV=" "$ueini" 2>/dev/null; then
        sed -i "s/^DesiredFOV=.*/DesiredFOV=${target_fov}/" "$ueini" 2>/dev/null || true
        sed -i "s/^DefaultFOV=.*/DefaultFOV=${target_fov}/" "$ueini" 2>/dev/null || true
    fi
    if grep -q "FirstPersonFOV=" "$ueini" 2>/dev/null; then
        sed -i "s/^FirstPersonFOV=.*/FirstPersonFOV=${target_fov}/" "$ueini" 2>/dev/null || true
    fi
    if grep -q "FovAngleDegrees=" "$ueini" 2>/dev/null; then
        sed -i "s/^FovAngleDegrees=.*/FovAngleDegrees=${target_fov}/" "$ueini" 2>/dev/null || true
    fi
done
[ -d "${TARGET_DIR}/Engine" ] || [ -d "${TARGET_DIR}/Binaries" ] && EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -fullscreen"
