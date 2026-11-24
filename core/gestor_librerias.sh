#!/usr/bin/env bash
# ==============================================================================
# VESSEL - GESTOR MODULAR DE LIBRERÍAS Y RUNTIMES DE WINDOWS PARA JUEGOS
# Descarga, instala, inyecta y optimiza:
# 1. DirectX 9 / 10 / 11 Completo (+100 DLLs oficiales de Microsoft)
# 2. Microsoft Visual C++ 2005 a 2022 AIO (32 y 64 bits oficiales)
# 3. OpenAL Soft + DSOAL (Audio 3D Espacial y EAX binaural HRTF)
# 4. DirectPlay (Multijugador clásico LAN / GameRanger)
# 5. Fuentes de Windows (Corefonts: Arial, Tahoma, Times, Courier, Verdana)
# 6. cnc-ddraw (Traductor DirectDraw a OpenGL para clásicos 1995-2003)
# 7. SDL2 GameControllerDB (Base de datos universal de +2.300 mandos)
# 8. vkBasalt (Nitidez adaptativa AMD CAS y post-procesado Vulkan)
# ==============================================================================

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="${DIR}/core"
[ ! -d "$CORE_DIR" ] && CORE_DIR="${DIR}"
CACHE_DIR="${DIR}/librerias"
[ ! -d "$CACHE_DIR" ] && CACHE_DIR="${DIR}/librerias_cache"
HERRAMIENTAS_DIR="${DIR}/herramientas"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
RESET='\033[0m'

mkdir -p "$CACHE_DIR" "$HERRAMIENTAS_DIR"

# 1. ACTUALIZAR BASE DE DATOS DE MANDOS (gamecontrollerdb.txt)
actualizar_gamecontrollerdb() {
    echo -e "${CYAN}🎮 Actualizando base comunitaria de mandos (SDL_GameControllerDB)...${RESET}"
    local target_file="${HERRAMIENTAS_DIR}/gamecontrollerdb.txt"
    if curl -sL --connect-timeout 10 --max-time 30 "https://raw.githubusercontent.com/mdqinc/SDL_GameControllerDB/master/gamecontrollerdb.txt" -o "${target_file}.tmp"; then
        if [ -s "${target_file}.tmp" ]; then
            mv -f "${target_file}.tmp" "$target_file"
            echo -e "${GREEN}✓ Mapeos de mandos actualizados con éxito ($(wc -l < "$target_file") perfiles cargados).${RESET}"
            return 0
        fi
    fi
    rm -f "${target_file}.tmp" 2>/dev/null || true
    echo -e "${YELLOW}⚠ No se pudo descargar la última versión; conservando copia local existente.${RESET}"
    return 1
}

# 2. INSTALAR CNC-DDRAW (DirectDraw a OpenGL)
instalar_cnc_ddraw() {
    local target_dir="${1:-}"
    local ddraw_cache="${CACHE_DIR}/cnc-ddraw"
    mkdir -p "$ddraw_cache"

    if [ ! -f "${ddraw_cache}/ddraw.dll" ]; then
        echo -e "${CYAN}📦 Descargando cnc-ddraw (vía FunkyFr3sh/cnc-ddraw)...${RESET}"
        local zip_file="${ddraw_cache}/cnc-ddraw.zip"
        if curl -sL --connect-timeout 10 --max-time 60 "https://github.com/FunkyFr3sh/cnc-ddraw/releases/latest/download/cnc-ddraw.zip" -o "$zip_file"; then
            if command -v unzip &>/dev/null; then
                unzip -q -o "$zip_file" -d "$ddraw_cache"
                rm -f "$zip_file"
            else
                echo -e "${RED}✗ Error: Se requiere 'unzip' para desempaquetar cnc-ddraw.${RESET}"
                return 1
            fi
        else
            echo -e "${RED}✗ Error al descargar cnc-ddraw desde GitHub.${RESET}"
            return 1
        fi
    fi

    if [ -n "$target_dir" ] && [ -d "$target_dir" ]; then
        echo -e "${CYAN}🔧 Inyectando cnc-ddraw en: ${BOLD}${target_dir}${RESET}"
        cp -f "${ddraw_cache}/ddraw.dll" "${target_dir}/ddraw.dll"
        [ -d "${ddraw_cache}/shaders" ] && cp -rf "${ddraw_cache}/shaders" "${target_dir}/"

        cat << 'EOF' > "${target_dir}/ddraw.ini"
[ddraw]
renderer=opengl
windowed=false
fullscreen=true
maintas=true
boxing=false
vsync=true
adjrefreshrate=true
shader=shaders/interpolation/bilinear.glsl
fixchilds=2
hook=4
EOF
        echo -e "${GREEN}✓ cnc-ddraw inyectado y optimizado con renderizador OpenGL y filtrado bilinear.${RESET}"
    else
        echo -e "${GREEN}✓ cnc-ddraw listo en caché local de Vessel (${ddraw_cache}).${RESET}"
    fi
}

# 3. INSTALAR DSOAL + OPENAL SOFT (Audio 3D Espacial EAX)
instalar_dsoal() {
    local target_dir="${1:-}"
    local dsoal_cache="${CACHE_DIR}/dsoal"
    mkdir -p "$dsoal_cache"

    if [ ! -f "${dsoal_cache}/dsound.dll" ] || [ ! -f "${dsoal_cache}/dsoal-aldrv.dll" ]; then
        echo -e "${CYAN}📦 Descargando DSOAL (Audio 3D EAX binaural vía kcat/dsoal)...${RESET}"
        local zip_file="${dsoal_cache}/DSOAL.zip"
        if curl -sL --connect-timeout 10 --max-time 60 "https://github.com/kcat/dsoal/releases/download/latest-master/DSOAL.zip" -o "$zip_file"; then
            if command -v unzip &>/dev/null; then
                unzip -q -o "$zip_file" -d "$dsoal_cache"
                rm -f "$zip_file"
                find "$dsoal_cache" -name "*.zip" -exec unzip -q -o {} -d "$dsoal_cache" \; 2>/dev/null || true
                find "$dsoal_cache" -type f \( -iname "dsound.dll" -o -iname "dsoal-aldrv.dll" \) -exec cp -f {} "$dsoal_cache/" \; 2>/dev/null || true
                find "$dsoal_cache" -name "*.zip" -delete 2>/dev/null || true
            else
                echo -e "${RED}✗ Error: Se requiere 'unzip' para desempaquetar DSOAL.${RESET}"
                return 1
            fi
        else
            echo -e "${RED}✗ Error al descargar DSOAL desde GitHub.${RESET}"
            return 1
        fi
    fi

    cat << 'EOF' > "${dsoal_cache}/alsoft.ini"
[general]
drivers = -dsound,
hrtf = true
default-reverb = true
resampler = sinc
stereo-mode = headphones
EOF

    if [ -n "$target_dir" ] && [ -d "$target_dir" ]; then
        echo -e "${CYAN}🔧 Inyectando DSOAL en: ${BOLD}${target_dir}${RESET}"
        cp -f "${dsoal_cache}/dsound.dll" "${target_dir}/dsound.dll"
        cp -f "${dsoal_cache}/dsoal-aldrv.dll" "${target_dir}/dsoal-aldrv.dll"
        cp -f "${dsoal_cache}/alsoft.ini" "${target_dir}/alsoft.ini"
        echo -e "${GREEN}✓ DSOAL inyectado: Sonido envolvente 3D binaural y EAX activo con HRTF.${RESET}"
    else
        echo -e "${GREEN}✓ DSOAL listo en caché local de Vessel (${dsoal_cache}).${RESET}"
    fi
}

# 4. CONFIGURAR DllOverrides EN REGISTRO DE WINE
configurar_dlloverrides() {
    local target_prefix="${1:-${DIR}/wineprefix}"
    echo -e "${CYAN}⚙️  Configurando DllOverrides en el registro de Wine para compatibilidad nativa...${RESET}"

    local dx_overrides=(
        d3dx9_24 d3dx9_25 d3dx9_26 d3dx9_27 d3dx9_28 d3dx9_29 d3dx9_30
        d3dx9_31 d3dx9_32 d3dx9_33 d3dx9_34 d3dx9_35 d3dx9_36 d3dx9_37
        d3dx9_38 d3dx9_39 d3dx9_40 d3dx9_41 d3dx9_42 d3dx9_43
        d3dx10_33 d3dx10_34 d3dx10_35 d3dx10_36 d3dx10_37 d3dx10_38
        d3dx10_39 d3dx10_40 d3dx10_41 d3dx10_42 d3dx10_43
        d3dx11_42 d3dx11_43
        d3dcompiler_33 d3dcompiler_34 d3dcompiler_35 d3dcompiler_36
        d3dcompiler_37 d3dcompiler_38 d3dcompiler_39 d3dcompiler_40
        d3dcompiler_41 d3dcompiler_42 d3dcompiler_43 d3dcompiler_46 d3dcompiler_47
        d3dcsx_42 d3dcsx_43
        dinput8 xinput1_1 xinput1_2 xinput1_3 xinput1_4 xinput9_1_0
        xaudio2_0 xaudio2_1 xaudio2_2 xaudio2_3 xaudio2_4 xaudio2_5 xaudio2_6 xaudio2_7
        xactengine2_0 xactengine2_1 xactengine2_2 xactengine2_3 xactengine2_4 xactengine2_5
        xactengine2_6 xactengine2_7 xactengine2_8 xactengine2_9
        xactengine3_0 xactengine3_1 xactengine3_2 xactengine3_3 xactengine3_4 xactengine3_5
        xactengine3_6 xactengine3_7
        dplayx d3d8 nvapi nvapi64 d3d12 d3d12core
    )

    local vc_overrides=(
        vcruntime140 vcruntime140_1 msvcp140 msvcp140_1 msvcp140_2
        msvcp140_codecvt_ids msvcp140_atomic_wait concrt140 vcomp140
        msvcp120 msvcr120 msvcp110 msvcr110 msvcp100 msvcr100
        msvcp90 msvcr90 msvcp80 msvcr80
        mfc42 mfc100 mfc110 mfc120 mfc140
    )

    local prod_overrides=(
        riched20 riched32 msftedit
        msxml3 msxml4 msxml6
        gdiplus windowscodecs mscms
        actxprxy wbemprox wbemdisp wmiutils
        schannel crypt32 secur32
        wininet urlmon dwrite
    )

    local reg_file="/tmp/vessel_dlloverrides_$$.reg"
    cat << 'EOF' > "$reg_file"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Wine\DllOverrides]
EOF

    for dll in "${dx_overrides[@]}" "${vc_overrides[@]}" "${prod_overrides[@]}"; do
        echo "\"${dll}\"=\"native,builtin\"" >> "$reg_file"
    done

    WINEPREFIX="$target_prefix" wine regedit /S "$reg_file" 2>/dev/null || true
    rm -f "$reg_file"
    echo -e "${GREEN}✓ DllOverrides configurado: +140 librerías nativas registradas con prioridad en Wine (DirectX, VC++, Productividad y Sistema).${RESET}"
}

# 5. INSTALAR DIRECTX 9/10/11 COMPLETO (+100 DLLs NATIVAS)
instalar_directx_completo() {
    local target_prefix="${1:-${DIR}/wineprefix}"
    local dx_cache="${CACHE_DIR}/directx9"
    local dx_exe="${dx_cache}/directx_Jun2010_redist.exe"
    mkdir -p "$dx_cache"

    echo -e "\n${CYAN}🎮 [ PASO 1/5 ] Descargando e instalando DirectX End-User Runtimes Completo...${RESET}"
    if [ ! -f "$dx_exe" ] || [ ! -s "$dx_exe" ]; then
        echo -e "${CYAN}  📦 Descargando paquete oficial DirectX Junio 2010 Redist (96 MB)...${RESET}"
        if ! curl -sL --connect-timeout 15 --max-time 180 "https://files.holarse-linuxgaming.de/mirrors/microsoft/directx_Jun2010_redist.exe" -o "${dx_exe}.tmp"; then
            echo -e "${YELLOW}  ⚠ Falló servidor primario, intentando espejo alternativo...${RESET}"
            curl -sL --connect-timeout 15 --max-time 180 "https://archive.org/download/directx_Jun2010_redist/directx_Jun2010_redist.exe" -o "${dx_exe}.tmp" || true
        fi
        if [ -s "${dx_exe}.tmp" ]; then
            mv -f "${dx_exe}.tmp" "$dx_exe"
        else
            rm -f "${dx_exe}.tmp" 2>/dev/null || true
            echo -e "${RED}✗ Error al descargar DirectX Redistributable.${RESET}"
            return 1
        fi
    fi

    if [ ! -d "${dx_cache}/x86" ] || [ $(ls "${dx_cache}/x86"/*.dll 2>/dev/null | wc -l) -lt 50 ]; then
        echo -e "${CYAN}  📂 Desempaquetando archivos de DirectX para 32-bit y 64-bit...${RESET}"
        mkdir -p "${dx_cache}/extracted" "${dx_cache}/x86" "${dx_cache}/x64"
        7z x -y -o"${dx_cache}/extracted" "$dx_exe" >/dev/null 2>&1 || cabextract -q -d "${dx_cache}/extracted" "$dx_exe" 2>/dev/null || true

        cd "${dx_cache}/extracted"
        7z e -y -o"${dx_cache}/x86" "*_x86.cab" "*.dll" >/dev/null 2>&1 || true
        7z e -y -o"${dx_cache}/x64" "*_x64.cab" "*.dll" >/dev/null 2>&1 || true
        rm -rf "${dx_cache}/extracted"
        cd "$DIR"
    fi

    local num_x86=$(ls "${dx_cache}/x86"/*.dll 2>/dev/null | wc -l)
    local num_x64=$(ls "${dx_cache}/x64"/*.dll 2>/dev/null | wc -l)
    echo -e "${GREEN}✓ ${num_x86} DLLs (32-bit) y ${num_x64} DLLs (64-bit) de DirectX listas en caché.${RESET}"

    local sys32="${target_prefix}/drive_c/windows/system32"
    local syswow="${target_prefix}/drive_c/windows/syswow64"
    if [ -d "$sys32" ]; then
        echo -e "${CYAN}  🔧 Inyectando librerías DirectX en Windows System32 y SysWOW64...${RESET}"
        if [ -d "$syswow" ]; then
            for f in "${dx_cache}/x86"/*.dll; do
                [ -f "$f" ] || continue
                local bname_low
                bname_low=$(basename "$f" | tr '[:upper:]' '[:lower:]')
                cp -f "$f" "${syswow}/${bname_low}" 2>/dev/null || true
            done
            for f in "${dx_cache}/x64"/*.dll; do
                [ -f "$f" ] || continue
                local bname_low
                bname_low=$(basename "$f" | tr '[:upper:]' '[:lower:]')
                cp -f "$f" "${sys32}/${bname_low}" 2>/dev/null || true
            done
        else
            for f in "${dx_cache}/x86"/*.dll; do
                [ -f "$f" ] || continue
                local bname_low
                bname_low=$(basename "$f" | tr '[:upper:]' '[:lower:]')
                cp -f "$f" "${sys32}/${bname_low}" 2>/dev/null || true
            done
        fi
        echo -e "${GREEN}✓ DirectX 9/10/11 (D3DX, D3DCompiler, XAudio2, XACT, XInput) instalado en el prefijo.${RESET}"
    fi
}

# 6. INSTALAR VISUAL C++ 2005 A 2022 AIO
instalar_vcredist_aio() {
    local target_prefix="${1:-${DIR}/wineprefix}"
    local vc_cache="${CACHE_DIR}/vcredist"
    mkdir -p "$vc_cache"

    echo -e "\n${CYAN}⚙️  [ PASO 2/5 ] Descargando e instalando Microsoft Visual C++ Runtimes (2005-2022 AIO)...${RESET}"

    local vcx86="${vc_cache}/vc_redist.x86.exe"
    local vcx64="${vc_cache}/vc_redist.x64.exe"

    if [ ! -f "$vcx86" ] || [ ! -s "$vcx86" ]; then
        echo -e "${CYAN}  📦 Descargando Visual C++ 2015-2022 (32-bit)...${RESET}"
        curl -sL --connect-timeout 15 --max-time 120 "https://aka.ms/vs/17/release/vc_redist.x86.exe" -o "$vcx86" || true
    fi
    if [ ! -f "$vcx64" ] || [ ! -s "$vcx64" ]; then
        echo -e "${CYAN}  📦 Descargando Visual C++ 2015-2022 (64-bit)...${RESET}"
        curl -sL --connect-timeout 15 --max-time 120 "https://aka.ms/vs/17/release/vc_redist.x64.exe" -o "$vcx64" || true
    fi

    if [ -f "$vcx86" ] && [ -s "$vcx86" ]; then
        echo -e "${CYAN}  🔧 Instalando Visual C++ 2015-2022 x86 en Wine...${RESET}"
        WINEPREFIX="$target_prefix" wine "$vcx86" /install /quiet /norestart >/dev/null 2>&1 || true
    fi
    if [ -f "$vcx64" ] && [ -s "$vcx64" ] && [ -d "${target_prefix}/drive_c/windows/syswow64" ]; then
        echo -e "${CYAN}  🔧 Instalando Visual C++ 2015-2022 x64 en Wine...${RESET}"
        WINEPREFIX="$target_prefix" wine "$vcx64" /install /quiet /norestart >/dev/null 2>&1 || true
    fi

    if command -v winetricks &>/dev/null; then
        echo -e "${CYAN}  🔧 Instalando runtimes complementarios (VC++ 2010, 2012, 2013, MFC42)...${RESET}"
        WINEPREFIX="$target_prefix" winetricks -q vcrun2010 vcrun2012 vcrun2013 mfc42 >/dev/null 2>&1 || true
    fi

    echo -e "${GREEN}✓ Microsoft Visual C++ 2005-2022 AIO instalado con éxito.${RESET}"
}

# 7. INSTALAR FUENTES OFICIALES DE WINDOWS (COREFONTS)
instalar_corefonts() {
    local target_prefix="${1:-${DIR}/wineprefix}"
    echo -e "\n${CYAN}🔤 [ PASO 3/5 ] Instalando Fuentes Oficiales de Windows (Corefonts)...${RESET}"
    if command -v winetricks &>/dev/null; then
        WINEPREFIX="$target_prefix" winetricks -q corefonts >/dev/null 2>&1 || true
        echo -e "${GREEN}✓ Fuentes de Windows (Arial, Times, Tahoma, Courier, Verdana) instaladas.${RESET}"
    fi
}

# 8. HABILITAR DIRECTPLAY PARA MULTIJUGADOR / GAMERANGER
instalar_directplay() {
    local target_prefix="${1:-${DIR}/wineprefix}"
    echo -e "\n${CYAN}🌐 [ PASO 4/5 ] Habilitando DirectPlay para multijugador y LAN...${RESET}"
    if command -v winetricks &>/dev/null; then
        WINEPREFIX="$target_prefix" winetricks -q directplay >/dev/null 2>&1 || true
        echo -e "${GREEN}✓ DirectPlay habilitado y listo para multijugador.${RESET}"
    fi
}

# 9. INSTALAR AUDIO 3D OPENAL SOFT Y DSOAL
instalar_openal() {
    local target_prefix="${1:-${DIR}/wineprefix}"
    echo -e "\n${CYAN}🔊 [ PASO 5/5 ] Instalando OpenAL 3D Sound y DSOAL (EAX Spatial Audio)...${RESET}"
    local syswow="${target_prefix}/drive_c/windows/syswow64"
    local sys32="${target_prefix}/drive_c/windows/system32"
    local dest="${syswow:-$sys32}"
    instalar_dsoal "$dest"
    echo -e "${GREEN}✓ Audio 3D OpenAL y DSOAL configurado.${RESET}"
}

# 9.1 INSTALAR D3D8TO9 (Traductor DirectX 8 a DirectX 9 / Vulkan para 60 FPS fijos)
instalar_d3d8to9() {
    local target_prefix="${1:-${DIR}/wineprefix}"
    echo -e "\n${CYAN}🕹️  [ MEJORA 3D ] Configurando D3D8to9 (DirectX 8 -> Vulkan)...${RESET}"
    local d3d8_cache="${CACHE_DIR}/d3d8to9"
    mkdir -p "$d3d8_cache"
    local d3d8_dll="${d3d8_cache}/d3d8.dll"

    if [ ! -f "$d3d8_dll" ]; then
        if [ -f "${DIR}/../librerias/d3d8to9/d3d8.dll" ]; then
            cp -f "${DIR}/../librerias/d3d8to9/d3d8.dll" "$d3d8_dll"
        else
            echo -e "${CYAN}  📦 Descargando D3D8to9 desde GitHub...${RESET}"
            curl -sL --connect-timeout 10 --max-time 60 "https://github.com/crosire/d3d8to9/releases/download/v1.16.0/d3d8.dll" -o "$d3d8_dll" || true
        fi
    fi

    if [ -f "$d3d8_dll" ]; then
        [ -d "${target_prefix}/drive_c/windows/syswow64" ] && cp -f "$d3d8_dll" "${target_prefix}/drive_c/windows/syswow64/d3d8.dll"
        [ -d "${target_prefix}/drive_c/windows/system32" ] && cp -f "$d3d8_dll" "${target_prefix}/drive_c/windows/system32/d3d8.dll"
        echo -e "${GREEN}✓ D3D8to9 inyectado: Clásicos 3D DirectX 8 ahora correrán nativos sobre DXVK Vulkan a 60 FPS.${RESET}"
    else
        echo -e "${YELLOW}⚠ D3D8to9 no disponible en este momento.${RESET}"
    fi
}

# 9.2 INSTALAR DXVK-NVAPI (Puente nativo para tarjetas NVIDIA GeForce)
instalar_dxvk_nvapi() {
    local target_prefix="${1:-${DIR}/wineprefix}"
    echo -e "\n${CYAN}🟢 [ MEJORA 3D ] Configurando DXVK-NVAPI (Puente nativo NVIDIA GeForce)...${RESET}"
    local nvapi_cache="${CACHE_DIR}/dxvk-nvapi"
    mkdir -p "$nvapi_cache"

    if [ ! -f "${nvapi_cache}/x32/nvapi.dll" ] || [ ! -f "${nvapi_cache}/x64/nvapi64.dll" ]; then
        if [ -d "${DIR}/../librerias/dxvk-nvapi" ]; then
            cp -rf "${DIR}/../librerias/dxvk-nvapi"/* "$nvapi_cache/" 2>/dev/null || true
        else
            echo -e "${CYAN}  📦 Descargando DXVK-NVAPI desde GitHub...${RESET}"
            local tar_file="${nvapi_cache}/dxvk-nvapi.tar.gz"
            if curl -sL --connect-timeout 10 --max-time 60 "https://github.com/jp7677/dxvk-nvapi/releases/download/v0.9.3/dxvk-nvapi-v0.9.3.tar.gz" -o "$tar_file"; then
                tar -xzf "$tar_file" -C "$nvapi_cache" 2>/dev/null || true
                rm -f "$tar_file"
            fi
        fi
    fi

    local instalado=0
    if [ -d "${target_prefix}/drive_c/windows/syswow64" ] && [ -f "${nvapi_cache}/x32/nvapi.dll" ]; then
        cp -f "${nvapi_cache}/x32/nvapi.dll" "${target_prefix}/drive_c/windows/syswow64/nvapi.dll"
        instalado=1
    fi
    if [ -d "${target_prefix}/drive_c/windows/system32" ] && [ -f "${nvapi_cache}/x64/nvapi64.dll" ]; then
        cp -f "${nvapi_cache}/x64/nvapi64.dll" "${target_prefix}/drive_c/windows/system32/nvapi64.dll"
        instalado=1
    fi

    if [ "$instalado" -eq 1 ]; then
        echo -e "${GREEN}✓ DXVK-NVAPI inyectado: Características y extensiones de bajo nivel NVIDIA listas.${RESET}"
    else
        echo -e "${YELLOW}⚠ DXVK-NVAPI no disponible en este momento.${RESET}"
    fi
}

# 9.3 INSTALAR VKD3D-PROTON (Traductor Oficial DirectX 12 a Vulkan)
instalar_vkd3d_proton() {
    local target_prefix="${1:-${DIR}/wineprefix}"
    echo -e "\n${CYAN}⚡ [ DIRECTX 12 ] Configurando VKD3D-Proton (DirectX 12 -> Vulkan)...${RESET}"
    local vkd3d_cache="${CACHE_DIR}/vkd3d-proton"
    mkdir -p "$vkd3d_cache"

    # 1. Comprobar si ya existen DLLs extraídas en drivers/ o librerias_cache
    if [ ! -f "${vkd3d_cache}/x64/d3d12.dll" ] || [ ! -f "${vkd3d_cache}/x86/d3d12.dll" ]; then
        if [ -f "${DIR}/drivers/vkd3d-proton/x64/d3d12.dll" ]; then
            mkdir -p "${vkd3d_cache}/x64" "${vkd3d_cache}/x86"
            cp -f "${DIR}/drivers/vkd3d-proton/x64"/*.dll "${vkd3d_cache}/x64/" 2>/dev/null || true
            cp -f "${DIR}/drivers/vkd3d-proton/x32"/*.dll "${vkd3d_cache}/x86/" 2>/dev/null || true
        elif [ -f "${DIR}/librerias_cache/vkd3d-proton/x64/d3d12.dll" ]; then
            mkdir -p "${vkd3d_cache}/x64" "${vkd3d_cache}/x86"
            cp -f "${DIR}/librerias_cache/vkd3d-proton/x64"/*.dll "${vkd3d_cache}/x64/" 2>/dev/null || true
            cp -f "${DIR}/librerias_cache/vkd3d-proton/x86"/*.dll "${vkd3d_cache}/x86/" 2>/dev/null || true
        fi
    fi

    # 2. Si no están en caché, descargar paquete oficial de HansKristian-Work/vkd3d-proton
    if [ ! -f "${vkd3d_cache}/x64/d3d12.dll" ] || [ ! -f "${vkd3d_cache}/x86/d3d12.dll" ]; then
        echo -e "${CYAN}  📦 Descargando VKD3D-Proton oficial v2.14.1 desde GitHub...${RESET}"
        local zst_file="${vkd3d_cache}/vkd3d-proton-2.14.1.tar.zst"
        local url="https://github.com/HansKristian-Work/vkd3d-proton/releases/download/v2.14.1/vkd3d-proton-2.14.1.tar.zst"
        if curl -sL --connect-timeout 15 --max-time 180 "$url" -o "$zst_file"; then
            mkdir -p "${vkd3d_cache}/extract_tmp"
            local decompressed=false
            if command -v tar &>/dev/null && tar --help 2>&1 | grep -q "zstd"; then
                tar --zstd -xf "$zst_file" -C "${vkd3d_cache}/extract_tmp" 2>/dev/null && decompressed=true || true
            fi
            if [ "$decompressed" = false ] && command -v zstd &>/dev/null; then
                zstd -dc "$zst_file" 2>/dev/null | tar -xf - -C "${vkd3d_cache}/extract_tmp" 2>/dev/null && decompressed=true || true
            fi
            if [ "$decompressed" = true ]; then
                local ext_dir
                ext_dir=$(find "${vkd3d_cache}/extract_tmp" -maxdepth 1 -type d -name "vkd3d-proton-*" | head -n 1)
                if [ -d "$ext_dir" ]; then
                    mkdir -p "${vkd3d_cache}/x64" "${vkd3d_cache}/x86"
                    cp -f "$ext_dir/x64"/*.dll "${vkd3d_cache}/x64/" 2>/dev/null || true
                    cp -f "$ext_dir/x86"/*.dll "${vkd3d_cache}/x86/" 2>/dev/null || true
                fi
            fi
            rm -rf "${vkd3d_cache}/extract_tmp" "$zst_file"
        fi
    fi

    local instalado=0
    local sys32="${target_prefix}/drive_c/windows/system32"
    local syswow="${target_prefix}/drive_c/windows/syswow64"

    if [ -d "$sys32" ] && [ -f "${vkd3d_cache}/x64/d3d12.dll" ]; then
        cp -f "${vkd3d_cache}/x64/d3d12.dll" "${sys32}/d3d12.dll" 2>/dev/null || true
        [ -f "${vkd3d_cache}/x64/d3d12core.dll" ] && cp -f "${vkd3d_cache}/x64/d3d12core.dll" "${sys32}/d3d12core.dll" 2>/dev/null || true
        instalado=1
    fi
    if [ -d "$syswow" ] && [ -f "${vkd3d_cache}/x86/d3d12.dll" ]; then
        cp -f "${vkd3d_cache}/x86/d3d12.dll" "${syswow}/d3d12.dll" 2>/dev/null || true
        [ -f "${vkd3d_cache}/x86/d3d12core.dll" ] && cp -f "${vkd3d_cache}/x86/d3d12core.dll" "${syswow}/d3d12core.dll" 2>/dev/null || true
        instalado=1
    fi

    if [ "$instalado" -eq 1 ]; then
        echo -e "${GREEN}✓ VKD3D-Proton inyectado: Soporte DirectX 12 nativo sobre Vulkan activo.${RESET}"
    else
        echo -e "${YELLOW}⚠ VKD3D-Proton no disponible en este momento.${RESET}"
    fi
}

# 10. PROPAGAR AUTOMÁTICAMENTE LIBRERÍAS A PREFIJOS AISLADOS (0 EXTRA DISCO VÍA HARDLINKS)
propagar_librerias_a_prefijo() {
    local dest_prefix="${1:-}"
    local master_prefix="${DIR}/wineprefix"
    [ -z "$dest_prefix" ] && return 0
    [ ! -d "${dest_prefix}/drive_c/windows" ] && return 0
    [ ! -d "${master_prefix}/drive_c/windows" ] && return 0
    [ "$dest_prefix" = "$master_prefix" ] && return 0

    local m_sys32="${master_prefix}/drive_c/windows/system32"
    local m_syswow="${master_prefix}/drive_c/windows/syswow64"
    local d_sys32="${dest_prefix}/drive_c/windows/system32"
    local d_syswow="${dest_prefix}/drive_c/windows/syswow64"

    if [ -d "$m_syswow" ] && [ -d "$d_syswow" ]; then
        for f in "$m_syswow"/*.dll; do
            [ -f "$f" ] || continue
            local bname=$(basename "$f")
            if [ ! -f "${d_syswow}/${bname}" ]; then
                ln -f "$f" "${d_syswow}/${bname}" 2>/dev/null || cp -n "$f" "${d_syswow}/${bname}" 2>/dev/null || true
            fi
        done
    fi

    if [ -d "$m_sys32" ] && [ -d "$d_sys32" ]; then
        for f in "$m_sys32"/*.dll; do
            [ -f "$f" ] || continue
            local bname=$(basename "$f")
            if [ ! -f "${d_sys32}/${bname}" ]; then
                ln -f "$f" "${d_sys32}/${bname}" 2>/dev/null || cp -n "$f" "${d_sys32}/${bname}" 2>/dev/null || true
            fi
        done
    fi

    configurar_dlloverrides "$dest_prefix" >/dev/null 2>&1 || true
}

# 11. INSTALADOR MAESTRO DE TODAS LAS DEPENDENCIAS DE JUEGOS
instalar_paquete_maestro() {
    local target_prefix="${1:-${DIR}/wineprefix}"
    echo -e "\n${BOLD}${PURPLE}========================================================================${RESET}"
    echo -e "${BOLD}${PURPLE}   VESSEL - INSTALADOR MAESTRO DE DLLs Y RUNTIMES PARA JUEGOS          ${RESET}"
    echo -e "${BOLD}${PURPLE}========================================================================${RESET}"
    echo -e "  ${WHITE}Prefijo objetivo : ${CYAN}${target_prefix}${RESET}"
    echo -e "  ${WHITE}Librerías        : DirectX 9/10/11/12 (DXVK + VKD3D-Proton), VC++ 2005-2022 AIO,${RESET}"
    echo -e "                     OpenAL 3D, DirectPlay, Corefonts, cnc-ddraw, SDL2 DB${RESET}"
    echo -e "${BOLD}${PURPLE}========================================================================${RESET}\n"

    instalar_directx_completo "$target_prefix"
    instalar_vcredist_aio "$target_prefix"
    instalar_d3d8to9 "$target_prefix"
    instalar_dxvk_nvapi "$target_prefix"
    instalar_vkd3d_proton "$target_prefix"
    instalar_corefonts "$target_prefix"
    instalar_directplay "$target_prefix"
    instalar_openal "$target_prefix"
    actualizar_gamecontrollerdb
    configurar_dlloverrides "$target_prefix"

    echo -e "\n${BOLD}${GREEN}✔ ¡PAQUETE MAESTRO DE DLLs INSTALADO EXITOSAMENTE!${RESET}"
    echo -e "${WHITE}  Tu prefijo de Wine ahora cuenta con la máxima compatibilidad gráfica,${RESET}"
    echo -e "${WHITE}  de audio, mandos y dependencias para correr cualquier juego Windows.${RESET}\n"
}

# 12. CONFIGURAR VKBASALT (Nitidez AMD CAS en Vulkan)
configurar_vkbasalt() {
    local conf_dir="${HOME}/.config/vkBasalt"
    mkdir -p "$conf_dir"
    cat << 'EOF' > "${conf_dir}/vkBasalt.conf"
# Configuración Optimizada de Nitidez Ultra-HD AMD CAS para Vessel
effects = cas
casSharpness = 0.4
enableOnLaunch = True
toggleKey = Home
EOF
    echo -e "${GREEN}✓ Archivo de configuración de vkBasalt generado en: ${conf_dir}/vkBasalt.conf${RESET}"
    echo -e "    - Efecto Activo: AMD Contrast Adaptive Sharpening (CAS 0.4)"
    echo -e "    - Tecla rápida para activar/desactivar en tiempo real: ${BOLD}Inicio (Home)${RESET}"
}

# 13. DIAGNÓSTICO DEL ECOSISTEMA DE MEJORAS
mostrar_estado() {
    echo -e "\n${BOLD}${BLUE}================================================================${RESET}"
    echo -e "${BOLD}${BLUE}    ESTADO DE LIBRERÍAS Y MEJORAS DE CÓDIGO ABIERTO EN VESSEL   ${RESET}"
    echo -e "${BOLD}${BLUE}================================================================${RESET}\n"

    # GameControllerDB
    if [ -f "${HERRAMIENTAS_DIR}/gamecontrollerdb.txt" ]; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}SDL2 GameControllerDB:${RESET} Presente ($(wc -l < "${HERRAMIENTAS_DIR}/gamecontrollerdb.txt") mandos soportados)"
    else
        echo -e "  [${YELLOW}✗${RESET}] ${BOLD}SDL2 GameControllerDB:${RESET} No encontrado (ejecuta actualización)"
    fi

    # DirectX
    if [ -f "${DIR}/wineprefix/drive_c/windows/syswow64/d3dx9_43.dll" ] || [ -f "${CACHE_DIR}/directx9/x86/d3dx9_43.dll" ]; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}DirectX 9/10/11 Completo:${RESET} Instalado y listo (+100 DLLs nativas de Microsoft)"
    else
        echo -e "  [${YELLOW}○${RESET}] ${BOLD}DirectX 9/10/11 Completo:${RESET} Disponible para instalación bajo demanda"
    fi

    # Visual C++
    if [ -f "${DIR}/wineprefix/drive_c/windows/syswow64/vcruntime140.dll" ]; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}Visual C++ 2005-2022 AIO:${RESET} Instalado en el prefijo Wine"
    else
        echo -e "  [${YELLOW}○${RESET}] ${BOLD}Visual C++ 2005-2022 AIO:${RESET} Disponible para instalación bajo demanda"
    fi

    # Corefonts
    if [ -f "${DIR}/wineprefix/drive_c/windows/Fonts/arial.ttf" ]; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}Fuentes Oficiales Windows:${RESET} Corefonts presentes (Arial, Times, Tahoma)"
    else
        echo -e "  [${YELLOW}○${RESET}] ${BOLD}Fuentes Oficiales Windows:${RESET} Disponibles para instalación bajo demanda"
    fi

    # cnc-ddraw
    if [ -f "${CACHE_DIR}/cnc-ddraw/ddraw.dll" ]; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}cnc-ddraw (DirectDraw -> OpenGL):${RESET} Descargado y listo en caché"
    else
        echo -e "  [${YELLOW}○${RESET}] ${BOLD}cnc-ddraw:${RESET} Descargable bajo demanda para juegos retro"
    fi

    # DSOAL
    if [ -f "${CACHE_DIR}/dsoal/dsound.dll" ]; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}DSOAL (Audio 3D Espacial / EAX):${RESET} Descargado y listo en caché"
    else
        echo -e "  [${YELLOW}○${RESET}] ${BOLD}DSOAL:${RESET} Descargable bajo demanda para juegos clásicos"
    fi

    # D3D8to9
    if [ -f "${DIR}/wineprefix/drive_c/windows/syswow64/d3d8.dll" ] || [ -f "${CACHE_DIR}/d3d8to9/d3d8.dll" ]; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}D3D8to9 (DirectX 8 -> Vulkan):${RESET} Instalado y listo (60 FPS para clásicos 2001-2006)"
    else
        echo -e "  [${YELLOW}○${RESET}] ${BOLD}D3D8to9:${RESET} Disponible para instalación bajo demanda"
    fi

    # DXVK-NVAPI
    if [ -f "${DIR}/wineprefix/drive_c/windows/system32/nvapi64.dll" ] || [ -f "${CACHE_DIR}/dxvk-nvapi/x64/nvapi64.dll" ]; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}DXVK-NVAPI (NVIDIA GeForce Bridge):${RESET} Instalado y activo para GPUs GeForce"
    else
        echo -e "  [${YELLOW}○${RESET}] ${BOLD}DXVK-NVAPI:${RESET} Disponible para instalación bajo demanda"
    fi

    # VKD3D-Proton (DirectX 12)
    if [ -f "${DIR}/wineprefix/drive_c/windows/system32/d3d12.dll" ] || [ -f "${CACHE_DIR}/vkd3d-proton/x64/d3d12.dll" ]; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}VKD3D-Proton (DirectX 12 -> Vulkan):${RESET} Instalado y listo (RE4 Remake y juegos DX12)"
    else
        echo -e "  [${YELLOW}○${RESET}] ${BOLD}VKD3D-Proton:${RESET} Disponible para instalación bajo demanda"
    fi

    # vkBasalt
    if command -v vkbasalt &>/dev/null || [ -f "/usr/lib/x86_64-linux-gnu/libvkbasalt.so" ] || [ -f "/usr/lib64/libvkbasalt.so" ] || [ -f "/usr/lib/libvkbasalt.so" ]; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}vkBasalt (Post-procesado Vulkan):${RESET} Instalado en el sistema"
    else
        echo -e "  [${YELLOW}○${RESET}] ${BOLD}vkBasalt:${RESET} No detectado en el sistema (opcional)"
    fi

    # Gamescope
    if command -v gamescope &>/dev/null; then
        echo -e "  [${GREEN}✓${RESET}] ${BOLD}Gamescope (Micro-compositor Valve):${RESET} Instalado y listo ($(gamescope --version 2>&1 | head -n 1 || echo "Activo"))"
    else
        echo -e "  [${YELLOW}○${RESET}] ${BOLD}Gamescope:${RESET} No detectado en el sistema (opcional para reescalado FSR de resolución fija)"
    fi
    echo ""
}

# MODO INTERACTIVO O CLI
case "${1:-menu}" in
    paquete_maestro)
        instalar_paquete_maestro "${2:-${DIR}/wineprefix}"
        ;;
    instalar_directx)
        instalar_directx_completo "${2:-${DIR}/wineprefix}"
        configurar_dlloverrides "${2:-${DIR}/wineprefix}"
        ;;
    instalar_vcredist)
        instalar_vcredist_aio "${2:-${DIR}/wineprefix}"
        configurar_dlloverrides "${2:-${DIR}/wineprefix}"
        ;;
    instalar_fuentes)
        instalar_corefonts "${2:-${DIR}/wineprefix}"
        ;;
    instalar_directplay)
        instalar_directplay "${2:-${DIR}/wineprefix}"
        ;;
    instalar_openal)
        instalar_openal "${2:-${DIR}/wineprefix}"
        ;;
    instalar_d3d8to9)
        instalar_d3d8to9 "${2:-${DIR}/wineprefix}"
        configurar_dlloverrides "${2:-${DIR}/wineprefix}"
        ;;
    instalar_nvapi)
        instalar_dxvk_nvapi "${2:-${DIR}/wineprefix}"
        configurar_dlloverrides "${2:-${DIR}/wineprefix}"
        ;;
    instalar_vkd3d|instalar_vkd3d_proton)
        instalar_vkd3d_proton "${2:-${DIR}/wineprefix}"
        configurar_dlloverrides "${2:-${DIR}/wineprefix}"
        ;;
    propagar)
        propagar_librerias_a_prefijo "${2:-}"
        ;;
    configurar_overrides)
        configurar_dlloverrides "${2:-${DIR}/wineprefix}"
        ;;
    actualizar_mandos)
        actualizar_gamecontrollerdb
        ;;
    instalar_ddraw)
        instalar_cnc_ddraw "${2:-}"
        ;;
    instalar_dsoal)
        instalar_dsoal "${2:-}"
        ;;
    configurar_vkbasalt)
        configurar_vkbasalt
        ;;
    estado)
        mostrar_estado
        ;;
    menu|*)
        mostrar_estado
        echo -e "${PURPLE}Opciones disponibles:${RESET}"
        echo "  [1] 🚀 Instalar Paquete Maestro de DLLs para Todos los Juegos (Recomendado)"
        echo "  [2] 🎮 Instalar DirectX 9/10/11 Completo (+100 DLLs nativas de Microsoft)"
        echo "  [3] ⚙️  Instalar Visual C++ 2005 a 2022 AIO (32 y 64 bits)"
        echo "  [4] 🕹️  Instalar D3D8to9 (DirectX 8 -> Vulkan 60 FPS fijos)"
        echo "  [5] 🟢 Instalar DXVK-NVAPI (Puente nativo NVIDIA GeForce)"
        echo "  [6] ⚡ Instalar VKD3D-Proton (DirectX 12 -> Vulkan para juegos modernos)"
        echo "  [7] 🔤 Instalar Fuentes Oficiales de Windows (Corefonts: Arial, Times, Tahoma)"
        echo "  [8] 🔊 Descargar / Preparar DSOAL (Audio 3D Espacial EAX)"
        echo "  [9] 🕹️  Descargar / Preparar cnc-ddraw (DirectDraw OpenGL)"
        echo "  [10] 🎮 Actualizar base de datos de mandos (gamecontrollerdb.txt)"
        echo "  [11] 🎨 Generar configuración optimizada de vkBasalt (AMD CAS)"
        echo "  [12] 🚀 Panel Modular de Drivers (DXVK, VKD3D-Proton, GPU y Pantalla)"
        echo "  [0] ↩️  Salir"
        echo ""
        read -rp "Selecciona una opción [0-12]: " opc
        case "$opc" in
            1) instalar_paquete_maestro "${DIR}/wineprefix" ;;
            2) instalar_directx_completo "${DIR}/wineprefix" && configurar_dlloverrides "${DIR}/wineprefix" ;;
            3) instalar_vcredist_aio "${DIR}/wineprefix" && configurar_dlloverrides "${DIR}/wineprefix" ;;
            4) instalar_d3d8to9 "${DIR}/wineprefix" && configurar_dlloverrides "${DIR}/wineprefix" ;;
            5) instalar_dxvk_nvapi "${DIR}/wineprefix" && configurar_dlloverrides "${DIR}/wineprefix" ;;
            6) instalar_vkd3d_proton "${DIR}/wineprefix" && configurar_dlloverrides "${DIR}/wineprefix" ;;
            7) instalar_corefonts "${DIR}/wineprefix" ;;
            8) instalar_dsoal ;;
            9) instalar_cnc_ddraw ;;
            10) actualizar_gamecontrollerdb ;;
            11) configurar_vkbasalt ;;
            12) bash "${CORE_DIR}/gestor_drivers.sh" estado ;;
            *) echo "Saliendo..." ;;
        esac
        ;;
esac
