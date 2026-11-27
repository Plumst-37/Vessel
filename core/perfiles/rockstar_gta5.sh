#!/usr/bin/env bash
# ==============================================================================
# VESSEL - PERFIL MODULAR: rockstar_gta5
# ==============================================================================

            echo "[+] Perfil Activo: Rockstar Games (Grand Theft Auto V) [Aislado]"
            # 1. Limpiar procesos zombies previos de GTA V de forma segura (sin matar el script)
            limpiar_zombies_juego "GTA5\.exe|PlayGTAV\.exe"
            sleep 0.2

            # Purgar caché previa de DXVK para eliminar pipelines con teselación obsoleta o buffers desalineados
            rm -f "${HOME}/.cache/dxvk/GTA5.dxvk-cache" "${HOME}/.cache/dxvk/PlayGTAV.dxvk-cache" "${TARGET_DIR}/GTA5.dxvk-cache" "${TARGET_DIR}/PlayGTAV.dxvk-cache" 2>/dev/null || true

            # Determinar resolución óptima según GPU (nativa para pantallas <= 1080p, adaptativa si supera 1080p en GPU básica)
            local gta_w="$best_w"
            local gta_h="$best_h"
            if [ "$IS_LOW_SPEC_GPU" = true ] && [ "$best_w" -gt 1920 ]; then
                gta_w="1920"
                gta_h="1080"
                echo "    - Pantalla de ultra-alta resolución detectada: Ajustando renderizado a 1080p para 60 FPS estables."
            fi

            # 2. Configuración en Rockstar Games / GTA V / settings.xml
            local rsg_doc="$HOME/Documentos/Rockstar Games/GTA V"
            [ ! -d "$rsg_doc" ] && rsg_doc="${WINEPREFIX}/drive_c/users/${USER}/Documents/Rockstar Games/GTA V"
            mkdir -p "$rsg_doc"

            # Detección inteligente de versión GTA V Lite (OptiJuegos / recursos optimizados para bajo consumo)
            local is_gta_lite=false
            if [ -f "${TARGET_DIR}/bonus/settings.xml" ] || [ -f "${TARGET_DIR}/bonus/settings_ultra.xml" ] || [ -f "${TARGET_DIR}/optiprojects.asi" ]; then
                is_gta_lite=true
                echo "    - Edición GTA V Lite detectada: Calibrando para DirectX 11, animaciones fluidas y assets ligeros."
            fi

            local dx_ver="2"
            local quality_val="1"
            local shadow_val="1"
            local soft_shadow="1"
            local lod_scale="1.000000"
            local max_lod_scale="1.000000"
            local ped_lod="0.800000"
            local veh_lod="0.800000"
            local ped_variety="0.800000"
            local veh_variety="0.800000"

            if [ "$is_gta_lite" = true ] || [ "$IS_LOW_SPEC_GPU" = true ]; then
                dx_ver="2"
                quality_val="0"
                shadow_val="0"
                soft_shadow="0"
                # Geometría 3D blindada: valores positivos para erradicar deformación de mallas y vertex explosion
                lod_scale="0.800000"
                max_lod_scale="1.000000"
                ped_lod="0.500000"
                veh_lod="0.500000"
                ped_variety="0.300000"
                veh_variety="0.300000"
            fi

            # Si no existe ningún settings.xml, generar uno inicial con geometría 3D blindada (sin vertex explosion)
            local sxml_base="$rsg_doc/settings.xml"
            if [ ! -f "$sxml_base" ] && [ ! -f "${TARGET_DIR}/settings.xml" ]; then
                if [ "$is_gta_lite" = true ] && [ -f "${TARGET_DIR}/bonus/settings.xml" ]; then
                    cp -f "${TARGET_DIR}/bonus/settings.xml" "$sxml_base" 2>/dev/null || true
                else
                    cat <<EOF_SXML > "$sxml_base"
<?xml version="1.0" encoding="UTF-8"?>
<Settings>
  <version value="27" />
  <configSource>SMC_AUTO</configSource>
  <graphics>
    <Tessellation value="0" />
    <LodScale value="${lod_scale}" />
    <PedLodBias value="${ped_lod}" />
    <VehicleLodBias value="${veh_lod}" />
    <ShadowQuality value="${shadow_val}" />
    <ReflectionQuality value="${quality_val}" />
    <ReflectionMSAA value="0" />
    <SSAO value="0" />
    <AnisotropicFiltering value="16" />
    <MSAA value="0" />
    <MSAAFragments value="0" />
    <MSAAQuality value="0" />
    <SamplingMode value="0" />
    <TextureQuality value="0" />
    <ParticleQuality value="0" />
    <WaterQuality value="${quality_val}" />
    <GrassQuality value="${quality_val}" />
    <ShaderQuality value="${quality_val}" />
    <Shadow_SoftShadows value="${soft_shadow}" />
    <UltraShadows_Enabled value="false" />
    <Shadow_ParticleShadows value="false" />
    <Shadow_Distance value="1.000000" />
    <Shadow_LongShadows value="false" />
    <Shadow_SplitZStart value="0.930000" />
    <Shadow_SplitZEnd value="0.890000" />
    <Shadow_aircraftExpWeight value="0.990000" />
    <Shadow_DisableScreenSizeCheck value="false" />
    <Reflection_MipBlur value="false" />
    <FXAA_Enabled value="true" />
    <TXAA_Enabled value="false" />
    <Lighting_FogVolumes value="false" />
    <Shader_SSA value="false" />
    <DX_Version value="${dx_ver}" />
    <CityDensity value="0.000000" />
    <PedVarietyMultiplier value="${ped_variety}" />
    <VehicleVarietyMultiplier value="${veh_variety}" />
    <PostFX value="0" />
    <DoF value="false" />
    <HdStreamingInFlight value="false" />
    <MaxLodScale value="${max_lod_scale}" />
    <MotionBlurStrength value="0.000000" />
  </graphics>
  <system>
    <numBytesPerReplayBlock value="9000000" />
    <numReplayBlocks value="36" />
    <maxSizeOfStreamingReplay value="1024" />
    <maxFileStoreSize value="65536" />
  </system>
  <audio>
    <Audio3d value="false" />
  </audio>
  <video>
    <AdapterIndex value="0" />
    <OutputIndex value="0" />
    <ScreenWidth value="${gta_w}" />
    <ScreenHeight value="${gta_h}" />
    <RefreshRate value="60" />
    <Windowed value="2" />
    <VSync value="1" />
    <Stereo value="0" />
    <Convergence value="0.100000" />
    <Separation value="1.000000" />
    <PauseOnFocusLoss value="0" />
    <AspectRatio value="0" />
  </video>
  <VideoCardDescription>${GPU_NAME}</VideoCardDescription>
</Settings>
EOF_SXML
                fi
            fi

            for sxml in "$rsg_doc/settings.xml" "${TARGET_DIR}/settings.xml" "${WINEPREFIX}/drive_c/users/${USER}/Documents/Rockstar Games/GTA V/settings.xml"; do
                if [ -f "$sxml" ]; then
                    crear_respaldo_seguro "$sxml"
                    sed -i "s/<ScreenWidth value=\"[0-9]*\"/<ScreenWidth value=\"${gta_w}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<ScreenHeight value=\"[0-9]*\"/<ScreenHeight value=\"${gta_h}\"/" "$sxml" 2>/dev/null || true
                    # Modo Pantalla Completa sin Bordes (Windowed 2): 100% pantalla completa estable en GPUs híbridas PRIME sin fallo de swapchain
                    sed -i 's/<Windowed value="[0-9]*"/<Windowed value="2"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<VSync value="[0-9]*"/<VSync value="1"/' "$sxml" 2>/dev/null || true
                    sed -i "s/<ShadowQuality value=\"[0-9]*\"/<ShadowQuality value=\"${shadow_val}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<GrassQuality value=\"[0-9]*\"/<GrassQuality value=\"${quality_val}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<ShaderQuality value=\"[0-9]*\"/<ShaderQuality value=\"${quality_val}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<ReflectionQuality value=\"[0-9]*\"/<ReflectionQuality value=\"${quality_val}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<WaterQuality value=\"[0-9]*\"/<WaterQuality value=\"${quality_val}\"/" "$sxml" 2>/dev/null || true
                    sed -i 's/<TextureQuality value="[0-9]*"/<TextureQuality value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<ParticleQuality value="[0-9]*"/<ParticleQuality value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<PostFX value="[0-9]*"/<PostFX value="0"/' "$sxml" 2>/dev/null || true
                    # Desactivar Teselación para erradicar deformación de mallas y vertex exploding en Vulkan/Linux
                    sed -i 's/<Tessellation value="[0-9]*"/<Tessellation value="0"/' "$sxml" 2>/dev/null || true
                    sed -i "s/<Shadow_SoftShadows value=\"[0-9]*\"/<Shadow_SoftShadows value=\"${soft_shadow}\"/" "$sxml" 2>/dev/null || true
                    sed -i 's/<PauseOnFocusLoss value="[0-9]*"/<PauseOnFocusLoss value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<AspectRatio value="[0-9]*"/<AspectRatio value="0"/' "$sxml" 2>/dev/null || true
                    # Anti-aliasing estable: FXAA activo, MSAA/TXAA desactivados (evita mallas transparentes y corrupción de profundidad)
                    sed -i 's/<MSAA value="[0-9]*"/<MSAA value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<ReflectionMSAA value="[0-9]*"/<ReflectionMSAA value="0"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<TXAA_Enabled value="true"/<TXAA_Enabled value="false"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<FXAA_Enabled value="false"/<FXAA_Enabled value="true"/' "$sxml" 2>/dev/null || true
                    # Estabilidad geométrica 3D y distancia de dibujado
                    sed -i "s/<LodScale value=\"[0-9\.\-]*\"/<LodScale value=\"${lod_scale}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<MaxLodScale value=\"[0-9\.\-]*\"/<MaxLodScale value=\"${max_lod_scale}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<PedLodBias value=\"[0-9\.\-]*\"/<PedLodBias value=\"${ped_lod}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<VehicleLodBias value=\"[0-9\.\-]*\"/<VehicleLodBias value=\"${veh_lod}\"/" "$sxml" 2>/dev/null || true
                    sed -i 's/<Shadow_Distance value="[0-9\.]*"/<Shadow_Distance value="1.000000"/' "$sxml" 2>/dev/null || true
                    sed -i "s/<DX_Version value=\"[0-9]*\"/<DX_Version value=\"${dx_ver}\"/" "$sxml" 2>/dev/null || true
                    # Audio estéreo limpio sin pérdidas de canal en PipeWire / PulseAudio
                    sed -i 's/<Audio3d value="[a-zA-Z]*"/<Audio3d value="false"/' "$sxml" 2>/dev/null || true
                    # Desactivar post-efectos y niebla volumétrica que rompen la vista de cámara en traducción Vulkan
                    sed -i 's/<DoF value="true"/<DoF value="false"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<InGameDepthOfField value="true"/<InGameDepthOfField value="false"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<MotionBlurStrength value="[0-9\.]*"/<MotionBlurStrength value="0.000000"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<Lighting_FogVolumes value="true"/<Lighting_FogVolumes value="false"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<UltraShadows_Enabled value="true"/<UltraShadows_Enabled value="false"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<Shadow_ParticleShadows value="true"/<Shadow_ParticleShadows value="false"/' "$sxml" 2>/dev/null || true
                    sed -i 's/<Shadow_LongShadows value="true"/<Shadow_LongShadows value="false"/' "$sxml" 2>/dev/null || true
                    sed -i "s/<PedVarietyMultiplier value=\"[0-9\.]*\"/<PedVarietyMultiplier value=\"${ped_variety}\"/" "$sxml" 2>/dev/null || true
                    sed -i "s/<VehicleVarietyMultiplier value=\"[0-9\.]*\"/<VehicleVarietyMultiplier value=\"${veh_variety}\"/" "$sxml" 2>/dev/null || true
                    if [ -n "$GPU_NAME" ]; then
                        sed -i "s|<VideoCardDescription>.*</VideoCardDescription>|<VideoCardDescription>${GPU_NAME}</VideoCardDescription>|" "$sxml" 2>/dev/null || true
                    fi
                fi
            done

            # 3. Optimización en commandline.txt (priorizando estabilidad geométrica 3D y frame pacing)
            local gta_cmdline="${TARGET_DIR}/commandline.txt"
            if [ -f "$gta_cmdline" ]; then
                crear_respaldo_seguro "$gta_cmdline"
                # Asegurar flags esenciales de emulador y compatibilidad sin destruir ajustes del usuario
                grep -qi -- "-scOfflineOnly" "$gta_cmdline" || echo "-scOfflineOnly" >> "$gta_cmdline"
                grep -qi -- "-ignoreDifferentVideoCard" "$gta_cmdline" || echo "-ignoreDifferentVideoCard" >> "$gta_cmdline"
                grep -qi -- "-Tessellation" "$gta_cmdline" || echo "-Tessellation 0" >> "$gta_cmdline"
                grep -qi -- "-mouseRawInput" "$gta_cmdline" || echo "-mouseRawInput" >> "$gta_cmdline"
                grep -qi -- "-norestrictions" "$gta_cmdline" || echo "-norestrictions" >> "$gta_cmdline"
                grep -qi -- "-nomemrestrict" "$gta_cmdline" || echo "-nomemrestrict" >> "$gta_cmdline"
                grep -qi -- "-nopause" "$gta_cmdline" || echo "-nopause" >> "$gta_cmdline"
                grep -qi -- "-disallowResizeWindow" "$gta_cmdline" || echo "-disallowResizeWindow" >> "$gta_cmdline"
                grep -qi -- "-percentVidMem" "$gta_cmdline" || echo "-percentVidMem 90" >> "$gta_cmdline"
                # Erradicar forzado de DirectX 10 que rompe el backend Vulkan y causa líneas de colores
                sed -i '/-DX10/Id; /-dx10/Id' "$gta_cmdline" 2>/dev/null || true
                if grep -qi -- "-width" "$gta_cmdline"; then
                    sed -i "s/^-width .*/-width ${gta_w}/I" "$gta_cmdline" 2>/dev/null || true
                else
                    echo "-width ${gta_w}" >> "$gta_cmdline"
                fi
                if grep -qi -- "-height" "$gta_cmdline"; then
                    sed -i "s/^-height .*/-height ${gta_h}/I" "$gta_cmdline" 2>/dev/null || true
                else
                    echo "-height ${gta_h}" >> "$gta_cmdline"
                fi
                grep -qi -- "-windowed" "$gta_cmdline" || echo "-windowed" >> "$gta_cmdline"
                grep -qi -- "-borderless" "$gta_cmdline" || echo "-borderless" >> "$gta_cmdline"
            else
                cat <<EOF > "$gta_cmdline"
-width ${gta_w}
-height ${gta_h}
-windowed
-borderless
-mouseRawInput
-ignoreDifferentVideoCard
-scOfflineOnly
-Tessellation 0
-noInGameDOF
-disableD3D11Dof
-noDepthOfField
-frameLimit 1
-shadowSoftness 1
-norestrictions
-nomemrestrict
-nopause
-disallowResizeWindow
-percentVidMem 90
EOF
            fi
            echo "[+] GTA V optimizado: Geometría 3D calibrada (DirectX 11 nativo, Teselación 0, sin deformación ni vertex explosion, frame pacing 60 FPS, Social Club offline activado)."

            # Sincronización modular de geometría y resolución con el monitor activo
            if [ -f "${CORE_DIR}/gestor_drivers.sh" ]; then
                bash "${CORE_DIR}/gestor_drivers.sh" sincronizar "$TARGET_FILE" "$TARGET_DIR" >/dev/null 2>&1 || true
            fi

            # Garantizar steam_settings completo para emulador Goldberg (evita bloqueos de red e inicialización de perfil)
            if [ ! -d "${TARGET_DIR}/steam_settings" ]; then
                mkdir -p "${TARGET_DIR}/steam_settings"
                cat <<'EOF_DEPOTS' > "${TARGET_DIR}/steam_settings/depots.txt"
228984 	
228990 	
271591 			
271592 	
271593 			
271594 			
271595
EOF_DEPOTS
                cat <<'EOF_DLC' > "${TARGET_DIR}/steam_settings/DLC.txt"
771300 = Grand Theft Auto V - Criminal Enterprise Starter Pack
413180 = Grand Theft Auto V – Bonus $500,000
362003 = Grand Theft Auto V
362002 = Grand Theft Auto V – Bonus $1,350,000
362001 = Grand Theft Auto V – Bonus $1,500,000
362000 = Grand Theft Auto V – Bonus $1,500,000 + GTA: San Andreas 
EOF_DLC
                echo "Player" > "${TARGET_DIR}/steam_settings/force_account_name.txt"
                [ ! -f "${TARGET_DIR}/steam_appid.txt" ] && echo "271590" > "${TARGET_DIR}/steam_appid.txt"
            fi

            # Asegurar directorio limpio de guardado para emulador Goldberg
            local gta_save_dir="${WINEPREFIX}/drive_c/users/${USER}/AppData/Roaming/Goldberg SocialClub Emu Saves/GTA V/0F74F4C4"
            mkdir -p "$gta_save_dir"
            # Limpiar configuraciones binarias obsoletas que anulan settings.xml (preservando partidas guardadas SGTA*)
            rm -f "$gta_save_dir/pc_settings.bin" "$gta_save_dir/cfg.dat" 2>/dev/null || true

            # Overrides específicos de DirectX 11/10, Bink Video, Social Club y ASI Loader
            # Forzar xaudio2 a builtin (FAudio/PipeWire) para erradicar el crash de lectura de punteros WASAPI en Microsoft xaudio2_7.dll
            export WINEDLLOVERRIDES="xaudio2_7=b;xaudio2_8=b;xaudio2_9=b;x3daudio1_7=b;bink2w64=n,b;asiloader=n,b;dinput8=n,b;d3dcompiler_47=n,b;d3dcompiler_46=n,b;d3dcompiler_43=n,b;d3dcsx_46=n,b;socialclub=n,b;steam_api64=n,b;dxgi=n,b;d3d11=n,b;d3d10core=n,b;d3d10=n,b;d3d10_1=n,b;d3d9=n,b;${WINEDLLOVERRIDES}"
