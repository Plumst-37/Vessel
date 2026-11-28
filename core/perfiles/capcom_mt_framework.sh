#!/usr/bin/env bash
# ==============================================================================
# VESSEL - PERFIL MODULAR: capcom_mt_framework
# ==============================================================================

echo "[+] Perfil Activo: Capcom MT Framework (Resident Evil Series) [Aislado]"
limpiar_zombies_juego "BH6\.exe|biohazard4\.exe|re6\.exe|re5dx9\.exe|re5dx10\.exe"
local capcom_dir="$HOME/Documentos/CAPCOM"
[ ! -d "$capcom_dir" ] && capcom_dir="${WINEPREFIX}/drive_c/users/${USER}/Documents/CAPCOM"
local dirs_a_buscar=("$capcom_dir" "$TARGET_DIR")
[ -d "${TARGET_DIR}/gamedata/optimization" ] && dirs_a_buscar+=("${TARGET_DIR}/gamedata/optimization")
[ -d "${TARGET_DIR}/optimization" ] && dirs_a_buscar+=("${TARGET_DIR}/optimization")

for dir_c in "${dirs_a_buscar[@]}"; do
    if [ -d "$dir_c" ]; then
        find "$dir_c" -maxdepth 3 -name "config.ini" 2>/dev/null | while read -r cini; do
            if grep -q "\[GRAPHICS\]" "$cini" 2>/dev/null || grep -q "\[DISPLAY\]" "$cini" 2>/dev/null; then
                crear_respaldo_seguro "$cini"
                sed -i 's/^FullScreen=OFF/FullScreen=ON/' "$cini" 2>/dev/null || true
                sed -i 's/^VSYNC=ON/VSYNC=OFF/' "$cini" 2>/dev/null || true
                sed -i 's/^MotionBlurEnabled=ON/MotionBlurEnabled=OFF/' "$cini" 2>/dev/null || true
                sed -i 's/^Aspect=.*/Aspect=DEFAULT/' "$cini" 2>/dev/null || true
                sed -i "s/^Resolution=.*/Resolution=${best_res}/" "$cini" 2>/dev/null || true
                local ref_hz="${SCREEN_HZ:-60}.00Hz"
                sed -i "s/^RefreshRate=.*/RefreshRate=${ref_hz}/" "$cini" 2>/dev/null || true
                sed -i 's/^AntiAlias=.*/AntiAlias=NONE/' "$cini" 2>/dev/null || true
                sed -i 's/^AltAntiAlias=.*/AltAntiAlias=NONE/' "$cini" 2>/dev/null || true
                if [ "${VESSEL_HARDWARE_TIER:-baja}" = "baja" ] || [ "${GPU_VRAM_MB:-0}" -le 2048 ]; then
                    sed -i 's/^ShadowsQuality=.*/ShadowsQuality=LOW/' "$cini" 2>/dev/null || true
                    sed -i 's/^TextureDetail=.*/TextureDetail=MEDIUM/' "$cini" 2>/dev/null || true
                    sed -i 's/^ScreenQuality=.*/ScreenQuality=MEDIUM/' "$cini" 2>/dev/null || true
                else
                    sed -i 's/^ShadowsDisable=ON/ShadowsDisable=OFF/' "$cini" 2>/dev/null || true
                    sed -i 's/^ShadowsQuality=.*/ShadowsQuality=HIGH/' "$cini" 2>/dev/null || true
                    sed -i 's/^TextureDetail=.*/TextureDetail=HIGH/' "$cini" 2>/dev/null || true
                    sed -i 's/^ScreenQuality=.*/ScreenQuality=HIGH/' "$cini" 2>/dev/null || true
                fi
                sed -i 's/^TextureMipLimite=.*/TextureMipLimite=0/' "$cini" 2>/dev/null || true
                sed -i 's/^MouseBaseSpeed=.*/MouseBaseSpeed=1.500000/' "$cini" 2>/dev/null || true
                sed -i 's/^MainX=.*/MainX=0/' "$cini" 2>/dev/null || true
                sed -i 's/^MainY=.*/MainY=0/' "$cini" 2>/dev/null || true
            fi
        done
    fi
done
