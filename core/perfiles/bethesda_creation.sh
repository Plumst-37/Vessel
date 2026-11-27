#!/usr/bin/env bash
# ==============================================================================
# VESSEL - PERFIL MODULAR: bethesda_creation
# ==============================================================================

echo "[+] Perfil Activo: Bethesda Creation / Gamebryo Engine (Skyrim / Fallout) [Aislado]"
limpiar_zombies_juego "TESV\.exe|SkyrimSE\.exe|Fallout4\.exe|FalloutNV\.exe|Fallout3\.exe|Starfield\.exe"
sleep 0.2
export WINEDLLOVERRIDES="dinput8=n,b;xinput1_3=n,b;xaudio2_7=b;${WINEDLLOVERRIDES}"
