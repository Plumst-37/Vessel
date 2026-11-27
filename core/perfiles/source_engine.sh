#!/usr/bin/env bash
# ==============================================================================
# VESSEL - PERFIL MODULAR: source_engine
# ==============================================================================

echo "[+] Perfil Activo: Valve Source Engine [Aislado]"
limpiar_zombies_juego "hl2\.exe|csgo\.exe|left4dead.*\.exe|portal.*\.exe"
sleep 0.2
EXTRA_APP_ARGS="${EXTRA_APP_ARGS} -fullscreen -w ${best_w} -h ${best_h}"
