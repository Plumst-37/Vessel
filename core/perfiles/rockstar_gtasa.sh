#!/usr/bin/env bash
# ==============================================================================
# VESSEL - PERFIL MODULAR: rockstar_gtasa
# ==============================================================================

echo "[+] Perfil Activo: Rockstar Games (GTA San Andreas / Trilogy) [Aislado]"
limpiar_zombies_juego "gta_sa\.exe"
# Restaurar mod WindowedMode si estaba desactivado y asegurar modo sin bordes
find "$TARGET_DIR" -iname "III.VC.SA.WindowedMode.asi.disabled" 2>/dev/null | while read -r wm_dis; do
    mv -f "$wm_dis" "${wm_dis%.disabled}" 2>/dev/null || true
done
find "$TARGET_DIR" -iname "III.VC.SA.WindowedMode.ini" 2>/dev/null | while read -r wm_ini; do
    crear_respaldo_seguro "$wm_ini"
    sed -i "s/^ShowBorder = .*/ShowBorder = 0/" "$wm_ini" 2>/dev/null || true
done
# Configurar Widescreen Fix
find "$TARGET_DIR" -maxdepth 3 -iname "*widescreen*.ini" 2>/dev/null | while read -r wf_ini; do
    crear_respaldo_seguro "$wf_ini"
    sed -i "s/^ResX = .*/ResX = ${best_w}/" "$wf_ini" 2>/dev/null || true
    sed -i "s/^ResY = .*/ResY = ${best_h}/" "$wf_ini" 2>/dev/null || true
    sed -i "s/^ForceAspectRatio = .*/ForceAspectRatio = auto/" "$wf_ini" 2>/dev/null || true
done
# Desactivar mesa_glthread para prevenir microtirones con D3D9 y ASI Loader
export mesa_glthread=false
export WINEDLLOVERRIDES="vorbisfile=n,b;vorbishooked=n,b;vorbis=n,b;ogg=n,b;bass=n,b;eax=n,b;dinput8=n,b;d3d9=n,b;dsound=n,b;libcurl=n,b;${WINEDLLOVERRIDES}"
