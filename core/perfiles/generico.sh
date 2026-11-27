#!/usr/bin/env bash
# ==============================================================================
# VESSEL - PERFIL MODULAR: generico
# ==============================================================================

if [ "$IS_PROGRAM" -eq 1 ] || [ "${PE_CATEGORY:-juego}" = "programa" ]; then
    echo "[+] Perfil Activo: Programa de Escritorio / Utilidad Windows [Aislado]"
    export WINE_FULLSCREEN_FSR=0
    ACTIVAR_FSR_FINAL=0
else
    echo "[+] Perfil Activo: Aplicación Genérica [Aislado]"
fi
