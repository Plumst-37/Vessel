#!/bin/bash
# ==============================================================================
# VESSEL - RESTAURADOR DE RESPALDOS ORIGINALES (BOTÓN DE PÁNICO)
# Restaura cualquier archivo modificado por Vessel a su estado original de fábrica
# Soporta copias atómicas .vessel_orig y .vessel_bak
# ==============================================================================

# Autoprotección multi-shell
if [ -z "$BASH_VERSION" ]; then
    command -v bash >/dev/null 2>&1 && exec bash "$0" "$@"
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

# Colores de salida
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
WHITE="\033[1;37m"
BOLD="\033[1m"
RESET="\033[0m"

echo -e "${CYAN}══════════════════════════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}🔄 VESSEL - RESTAURADOR DE CONFIGURACIONES ORIGINALES${RESET}"
echo -e "  Restaura archivos modificados (.vessel_orig / .vessel_bak) a estado de fábrica"
echo -e "${CYAN}══════════════════════════════════════════════════════════════════════${RESET}\n"

RUTAS_A_BUSCAR=()

# 1. Si se pasó una ruta específica como argumento
if [ -n "$1" ] && [ -d "$1" ]; then
    RUTAS_A_BUSCAR+=("$1")
fi

# 2. Rutas estándar de Vessel y juegos registrados
RUTAS_A_BUSCAR+=("${DIR}/wineprefixes")
RUTAS_A_BUSCAR+=("${DIR}/wineprefix")
[ -d "$HOME/Documentos/Rockstar Games" ] && RUTAS_A_BUSCAR+=("$HOME/Documentos/Rockstar Games")
[ -d "$HOME/Documentos/CAPCOM" ] && RUTAS_A_BUSCAR+=("$HOME/Documentos/CAPCOM")

# 3. Añadir rutas de juegos de la base de datos
for db in "${DIR}/datos/programas_usuario.db" "${DIR}/programas_usuario.db" "${DIR}/datos/programas.db" "${DIR}/programas.db"; do
    if [ -f "$db" ]; then
        while IFS='|' read -r _nom ruta _pref _win _fsr; do
            [ -z "$ruta" ] && continue
            juego_dir="$(dirname "$ruta" 2>/dev/null || true)"
            if [ -d "$juego_dir" ]; then
                RUTAS_A_BUSCAR+=("$juego_dir")
                parent_dir="$(dirname "$juego_dir" 2>/dev/null || true)"
                [ -d "$parent_dir" ] && RUTAS_A_BUSCAR+=("$parent_dir")
            fi
        done < "$db"
    fi
done

TOTAL_RESTAURADOS=0

for search_dir in "${RUTAS_A_BUSCAR[@]}"; do
    [ ! -d "$search_dir" ] && continue
    while IFS= read -r bak_file; do
        [ -z "$bak_file" ] && continue
        if [[ "$bak_file" == *.vessel_orig ]]; then
            orig_file="${bak_file%.vessel_orig}"
        else
            orig_file="${bak_file%.vessel_bak}"
        fi
        if [ -f "$bak_file" ]; then
            cp -f "$bak_file" "$orig_file" 2>/dev/null || true
            echo -e "  ${GREEN}✔ Restaurado:${RESET} $(basename "$orig_file") en ${CYAN}$(dirname "$orig_file")${RESET}"
            TOTAL_RESTAURADOS=$((TOTAL_RESTAURADOS + 1))
        fi
    done < <(find "$search_dir" -maxdepth 5 -type f \( -name "*.vessel_orig" -o -name "*.vessel_bak" \) 2>/dev/null || true)
done

echo ""
if [ "$TOTAL_RESTAURADOS" -gt 0 ]; then
    echo -e "${GREEN}✔ Se restauraron ${TOTAL_RESTAURADOS} archivo(s) a su configuración original de fábrica.${RESET}"
else
    echo -e "${YELLOW}ℹ No se encontraron respaldos pendientes (.vessel_orig / .vessel_bak). Tus juegos ya están en estado limpio.${RESET}"
fi
echo -e "${CYAN}══════════════════════════════════════════════════════════════════════${RESET}"
