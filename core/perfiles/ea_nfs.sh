#!/usr/bin/env bash
# ==============================================================================
# VESSEL - PERFIL MODULAR: ea_nfs
# ==============================================================================

echo "[+] Perfil Activo: EA Games (Need For Speed) [Aislado]"
find "$TARGET_DIR" -maxdepth 3 -iname "*widescreen*.ini" 2>/dev/null | while read -r wf_ini; do
    crear_respaldo_seguro "$wf_ini"
    sed -i "s/^ResX = .*/ResX = ${best_w}/" "$wf_ini" 2>/dev/null || true
    sed -i "s/^ResY = .*/ResY = ${best_h}/" "$wf_ini" 2>/dev/null || true
    sed -i "s/^ForceAspectRatio = .*/ForceAspectRatio = auto/" "$wf_ini" 2>/dev/null || true
done
export WINEDLLOVERRIDES="dinput8=n,b;d3d9=n,b;scripts=n,b;${WINEDLLOVERRIDES}"
