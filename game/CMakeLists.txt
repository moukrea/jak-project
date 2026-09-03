# Set a more convenient ARM flag
if(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64")
    set(ARM64_ARCH TRUE)
    message(STATUS "ARM64 architecture detected")
else()
    set(ARM64_ARCH FALSE)
    message(STATUS "Non-ARM64 architecture detected")
endif()

if(ARM64_ARCH)
    # Add your ARM64-specific configuration or build options here
    set(OG_ASM_FUNCS_FILE kernel/asm_funcs_arm64.s)
    enable_language(ASM)
    set(CMAKE_ASM_SOURCE_FILE_EXTENSIONS ${CMAKE_ASM_SOURCE_FILE_EXTENSIONS} s)
    set_source_files_properties(${OG_ASM_FUNCS_FILE} PROPERTIES COMPILE_FLAGS "-arch arm64 -g")
else()
    set(OG_ASM_FUNCS_FILE kernel/asm_funcs_x86_64.asm)
    enable_language(ASM_NASM)
    set(CMAKE_ASM_NASM_SOURCE_FILE_EXTENSIONS ${CMAKE_ASM_NASM_SOURCE_FILE_EXTENSIONS} asm)
    set(CMAKE_ASM_NASM_COMPILE_OBJECT "<CMAKE_ASM_NASM_COMPILER> <INCLUDES> -f ${CMAKE_ASM_NASM_OBJECT_FORMAT} -o <OBJECT> <SOURCE>")
    set_source_files_properties(${OG_ASM_FUNCS_FILE} PROPERTIES COMPILE_FLAGS "-g")
endif()

set(RUNTIME_SOURCE
        external/discord_jak1.cpp
        external/discord_jak2.cpp
        external/discord_jak3.cpp
        external/discord_jakx.cpp
        external/discord.cpp
        graphics/display.cpp
        # Gfixed-tick-interpolation : horloge a pas fixe + alpha d'interpolation de rendu.
        graphics/fixed_tick.cpp
        graphics/gfx_test.cpp
        graphics/gfx.cpp
        graphics/jak2_texture_remap.cpp
        graphics/jak3_texture_remap.cpp
        graphics/jakx_texture_remap.cpp
        graphics/screenshot.cpp
        graphics/opengl_renderer/background/background_common.cpp
        graphics/opengl_renderer/background/Hfrag.cpp
        graphics/opengl_renderer/background/MeshBrowserGizmos.cpp
        graphics/opengl_renderer/background/Shrub.cpp
        graphics/opengl_renderer/background/TFragment.cpp
        graphics/opengl_renderer/background/Tie3.cpp
        graphics/opengl_renderer/BlitDisplays.cpp
        graphics/opengl_renderer/BucketRenderer.cpp
        graphics/opengl_renderer/CollideMeshRenderer.cpp
        graphics/opengl_renderer/FollowProbe.cpp
        graphics/opengl_renderer/debug_gui.cpp
        graphics/opengl_renderer/DepthCue.cpp
        graphics/opengl_renderer/DirectRenderer.cpp
        graphics/opengl_renderer/DirectRenderer2.cpp
        graphics/opengl_renderer/dma_helpers.cpp
        graphics/opengl_renderer/EyeRenderer.cpp
        graphics/opengl_renderer/foreground/Generic2_Build.cpp
        graphics/opengl_renderer/foreground/Generic2_DMA.cpp
        graphics/opengl_renderer/foreground/Generic2_OpenGL.cpp
        graphics/opengl_renderer/foreground/Generic2.cpp
        graphics/opengl_renderer/foreground/Generic2BucketRenderer.cpp
        graphics/opengl_renderer/foreground/Merc2.cpp
        graphics/opengl_renderer/foreground/Merc2BucketRenderer.cpp
        graphics/opengl_renderer/foreground/Shadow2.cpp
        graphics/opengl_renderer/loader/CustomTextureReplacements.cpp
        graphics/opengl_renderer/loader/Loader.cpp
        graphics/opengl_renderer/loader/LoaderStages.cpp
        graphics/opengl_renderer/loader/ManagedAssets.cpp
        graphics/opengl_renderer/GpuCaps.cpp
        assets/AssetCli.cpp
        assets/CurlTransport.cpp
        graphics/opengl_renderer/loader/PbrTestPattern.cpp
        graphics/opengl_renderer/ocean/CommonOceanRenderer.cpp
        graphics/opengl_renderer/ocean/OceanMid_PS2.cpp
        graphics/opengl_renderer/ocean/OceanMid.cpp
        graphics/opengl_renderer/ocean/OceanMidAndFar.cpp
        graphics/opengl_renderer/ocean/OceanNear_PS2.cpp
        graphics/opengl_renderer/ocean/OceanNear.cpp
        graphics/opengl_renderer/ocean/OceanTexture_PC.cpp
        graphics/opengl_renderer/ocean/OceanTexture.cpp
        graphics/opengl_renderer/GrassRenderer.cpp
        graphics/opengl_renderer/GrassBakeCore.cpp
        graphics/opengl_renderer/AmbientOcclusion.cpp
        graphics/opengl_renderer/opengl_utils.cpp
        graphics/opengl_renderer/OpenGLRenderer.cpp
        graphics/opengl_renderer/Profiler.cpp
        graphics/opengl_renderer/ProgressRenderer.cpp
        graphics/opengl_renderer/Shader.cpp
        graphics/opengl_renderer/Shadow_PS2.cpp
        graphics/opengl_renderer/ShadowRenderer.cpp
        graphics/opengl_renderer/SkyBlendCPU.cpp
        graphics/opengl_renderer/SkyBlendGPU.cpp
        graphics/opengl_renderer/SkyRenderer.cpp
        graphics/opengl_renderer/SlowTimeEffect.cpp
        graphics/opengl_renderer/sprite/GlowRenderer.cpp
        graphics/opengl_renderer/sprite/Sprite3_Distort.cpp
        graphics/opengl_renderer/sprite/Sprite3_Glow.cpp
        graphics/opengl_renderer/sprite/Sprite3.cpp
        graphics/opengl_renderer/TextureAnimator.cpp
        graphics/opengl_renderer/TextureAnimatorDefs.cpp
        graphics/opengl_renderer/TextureUploadHandler.cpp
        graphics/opengl_renderer/VisDataHandler.cpp
        graphics/opengl_renderer/Warp.cpp
        graphics/pipelines/opengl.cpp
        graphics/sceGraphicsInterface.cpp
        graphics/texture/jak1_tpage_dir.cpp
        graphics/texture/jak2_tpage_dir.cpp
        graphics/texture/jak3_tpage_dir.cpp
        graphics/texture/TextureConverter.cpp
        graphics/texture/TexturePool.cpp
        ${OG_ASM_FUNCS_FILE}
        kernel/common/fileio.cpp
        kernel/common/kboot.cpp
        kernel/common/kdgo.cpp
        kernel/common/kdsnetm.cpp
        kernel/common/klink.cpp
        kernel/common/klisten.cpp
        kernel/common/kmachine.cpp
        kernel/common/kmalloc.cpp
        kernel/common/kmemcard.cpp
        kernel/common/kprint.cpp
        kernel/common/kscheme.cpp
        kernel/common/ksocket.cpp
        kernel/common/ksound.cpp
        kernel/common/runtime_trace.cpp
        kernel/jak1/fileio.cpp
        kernel/jak1/kboot.cpp
        kernel/jak1/kdgo.cpp
        kernel/jak1/klink.cpp
        kernel/jak1/klisten.cpp
        kernel/jak1/kmachine.cpp
        kernel/jak1/kprint.cpp
        kernel/jak1/kscheme.cpp
        kernel/jak1/ksound.cpp
        kernel/jak2/fileio.cpp
        kernel/jak2/kboot.cpp
        kernel/jak2/kdgo.cpp
        kernel/jak2/klink.cpp
        kernel/jak2/klisten.cpp
        kernel/jak2/kmachine.cpp
        kernel/jak2/kmachine_extras.cpp
        kernel/jak2/kmalloc.cpp
        kernel/jak2/kprint.cpp
        kernel/jak2/kscheme.cpp
        kernel/jak2/ksound.cpp
        kernel/jak3/fileio.cpp
        kernel/jak3/kboot.cpp
        kernel/jak3/kdgo.cpp
        kernel/jak3/kdsnetm.cpp
        kernel/jak3/klink.cpp
        kernel/jak3/klisten.cpp
        kernel/jak3/kmachine.cpp
        kernel/jak3/kmachine_extras.cpp
        kernel/jak3/kmalloc.cpp
        kernel/jak3/kmemcard.cpp
        kernel/jak3/kprint.cpp
        kernel/jak3/kscheme.cpp
        kernel/jak3/ksocket.cpp
        kernel/jak3/ksound.cpp
        kernel/jakx/fileio.cpp
        kernel/jakx/kboot.cpp
        kernel/jakx/kdgo.cpp
        kernel/jakx/kdsnetm.cpp
        kernel/jakx/klink.cpp
        kernel/jakx/klisten.cpp
        kernel/jakx/kmachine.cpp
        kernel/jakx/kmachine_extras.cpp
        kernel/jakx/kmalloc.cpp
        kernel/jakx/kmemcard.cpp
        kernel/jakx/kprint.cpp
        kernel/jakx/kscheme.cpp
        kernel/jakx/ksocket.cpp
        kernel/jakx/ksound.cpp
        mips2c/jak1_functions/bones.cpp
        mips2c/jak1_functions/collide_cache.cpp
        mips2c/jak1_functions/collide_edge_grab.cpp
        mips2c/jak1_functions/collide_func.cpp
        mips2c/jak1_functions/collide_mesh.cpp
        mips2c/jak1_functions/collide_probe.cpp
        mips2c/jak1_functions/draw_string.cpp
        mips2c/jak1_functions/generic_effect.cpp
        mips2c/jak1_functions/generic_effect2.cpp
        mips2c/jak1_functions/generic_merc.cpp
        mips2c/jak1_functions/generic_tie.cpp
        mips2c/jak1_functions/joint.cpp
        mips2c/jak1_functions/merc_blend_shape.cpp
        mips2c/jak1_functions/ocean_vu0.cpp
        mips2c/jak1_functions/ocean.cpp
        mips2c/jak1_functions/ripple.cpp
        mips2c/jak1_functions/shadow.cpp
        mips2c/jak1_functions/sky_tng.cpp
        mips2c/jak1_functions/sparticle_launcher.cpp
        mips2c/jak1_functions/sparticle.cpp
        mips2c/jak1_functions/test_func.cpp
        mips2c/jak1_functions/texture.cpp
        mips2c/jak1_functions/tfrag.cpp
        mips2c/jak1_functions/tie_methods.cpp
        mips2c/jak1_functions/time_of_day.cpp
        mips2c/jak2_functions/bones.cpp
        mips2c/jak2_functions/collide_cache.cpp
        mips2c/jak2_functions/collide_edge_grab.cpp
        mips2c/jak2_functions/collide_func.cpp
        mips2c/jak2_functions/collide_hash.cpp
        mips2c/jak2_functions/collide_mesh.cpp
        mips2c/jak2_functions/debug.cpp
        mips2c/jak2_functions/font.cpp
        mips2c/jak2_functions/foreground.cpp
        mips2c/jak2_functions/generic_effect.cpp
        mips2c/jak2_functions/generic_merc.cpp
        mips2c/jak2_functions/joint.cpp
        mips2c/jak2_functions/lights.cpp
        mips2c/jak2_functions/merc_blend_shape.cpp
        mips2c/jak2_functions/nav_control.cpp
        mips2c/jak2_functions/nav_mesh.cpp
        mips2c/jak2_functions/ocean_vu0.cpp
        mips2c/jak2_functions/ocean.cpp
        mips2c/jak2_functions/ripple.cpp
        mips2c/jak2_functions/shadow.cpp
        mips2c/jak2_functions/sky.cpp
        mips2c/jak2_functions/sparticle_launcher.cpp
        mips2c/jak2_functions/sparticle.cpp
        mips2c/jak2_functions/spatial_hash.cpp
        mips2c/jak2_functions/squid.cpp
        mips2c/jak2_functions/texture.cpp
        mips2c/jak2_functions/vortex.cpp
        mips2c/jak3_functions/collide_func.cpp
        mips2c/jak3_functions/debug.cpp
        mips2c/jak3_functions/font.cpp
        mips2c/jak3_functions/foreground.cpp
        mips2c/jak3_functions/generic_effect.cpp
        mips2c/jak3_functions/joint.cpp
        mips2c/jak3_functions/lights.cpp
        mips2c/jak3_functions/sky.cpp
        mips2c/jak3_functions/texture.cpp
        mips2c/jak3_functions/particle_curves.cpp
        mips2c/jak3_functions/cloth.cpp
        mips2c/jak3_functions/collide_cache.cpp
        mips2c/jak3_functions/collide_hash.cpp
        mips2c/jak3_functions/collide_edge_grab.cpp
        mips2c/jak3_functions/collide_mesh.cpp
        mips2c/jak3_functions/spatial_hash.cpp
        mips2c/jak3_functions/sparticle.cpp
        mips2c/jak3_functions/sparticle_launcher.cpp
        mips2c/jak3_functions/nav_control.cpp
        mips2c/jak3_functions/nav_engine.cpp
        mips2c/jak3_functions/merc_blend_shape.cpp
        mips2c/jak3_functions/wvehicle_part.cpp
        mips2c/jak3_functions/ripple.cpp
        mips2c/jak3_functions/shadow.cpp
        mips2c/jak3_functions/ocean.cpp
        mips2c/jak3_functions/ocean_vu0.cpp
        mips2c/jak3_functions/generic_merc.cpp
        mips2c/mips2c_table.cpp
        overlord/common/dma.cpp
        overlord/common/fake_iso.cpp
        overlord/common/iso_api.cpp
        overlord/common/iso.cpp
        overlord/common/isocommon.cpp
        overlord/common/overlord.cpp
        overlord/common/sbank.cpp
        overlord/common/soundcommon.cpp
        overlord/common/srpc.cpp
        overlord/common/ssound.cpp
        overlord/jak1/dma.cpp
        overlord/jak1/fake_iso.cpp
        overlord/jak1/iso_api.cpp
        overlord/jak1/iso_queue.cpp
        overlord/jak1/iso.cpp
        overlord/jak1/isocommon.cpp
        overlord/jak1/overlord.cpp
        overlord/jak1/ramdisk.cpp
        overlord/jak1/srpc.cpp
        overlord/jak1/ssound.cpp
        overlord/jak1/stream.cpp
        overlord/jak2/dma.cpp
        overlord/jak2/iso_api.cpp
        overlord/jak2/iso_cd.cpp
        overlord/jak2/iso_queue.cpp
        overlord/jak2/iso.cpp
        overlord/jak2/list.cpp
        overlord/jak2/overlord.cpp
        overlord/jak2/pages.cpp
        overlord/jak2/spustreams.cpp
        overlord/jak2/srpc.cpp
        overlord/jak2/ssound.cpp
        overlord/jak2/stream.cpp
        overlord/jak2/streamlfo.cpp
        overlord/jak2/streamlist.cpp
        overlord/jak2/vag.cpp
        overlord/jak3/overlord.cpp
        overlord/jak3/pagemanager.cpp
        overlord/jak3/iso_cd.cpp
        overlord/jak3/dma.cpp
        overlord/jak3/iso.cpp
        overlord/jak3/iso_queue.cpp
        overlord/jak3/srpc.cpp
        overlord/jak3/vag.cpp
        overlord/jak3/ssound.cpp
        overlord/jak3/iso_api.cpp
        overlord/jak3/spustreams.cpp
        overlord/jak3/list.cpp
        overlord/jak3/vblank_handler.cpp
        overlord/jak3/dvd_driver.cpp
        overlord/jak3/basefile.cpp
        overlord/jak3/basefilesystem.cpp
        overlord/jak3/ramdisk.cpp
        overlord/jak3/isocommon.cpp
        overlord/jak3/init.cpp
        overlord/jak3/stream.cpp
        overlord/jak3/sbank.cpp
        overlord/jak3/soundcommon.cpp
        overlord/jak3/streamlist.cpp
        overlord/jakx/overlord.cpp
        overlord/jakx/pagemanager.cpp
        overlord/jakx/iso_cd.cpp
        overlord/jakx/dma.cpp
        overlord/jakx/iso.cpp
        overlord/jakx/iso_queue.cpp
        overlord/jakx/srpc.cpp
        overlord/jakx/vag.cpp
        overlord/jakx/ssound.cpp
        overlord/jakx/iso_api.cpp
        overlord/jakx/spustreams.cpp
        overlord/jakx/list.cpp
        overlord/jakx/vblank_handler.cpp
        overlord/jakx/dvd_driver.cpp
        overlord/jakx/basefile.cpp
        overlord/jakx/basefilesystem.cpp
        overlord/jakx/ramdisk.cpp
        overlord/jakx/isocommon.cpp
        overlord/jakx/init.cpp
        overlord/jakx/stream.cpp
        overlord/jakx/sbank.cpp
        overlord/jakx/soundcommon.cpp
        overlord/jakx/streamlist.cpp
        runtime.cpp
        sce/deci2.cpp
        sce/iop.cpp
        sce/libcdvd_ee.cpp
        sce/libdma.cpp
        sce/libgraph.cpp
        sce/libpad.cpp
        sce/libscf.cpp
        sce/sif_ee_memcard.cpp
        sce/sif_ee.cpp
        sce/stubs.cpp
        settings/settings.cpp
        system/background_worker.cpp
        system/Deci2Server.cpp
        system/pad_replay.cpp
        system/hid/devices/dualsense_effects.cpp
        system/hid/devices/game_controller.cpp
        system/hid/devices/keyboard.cpp
        system/hid/devices/mouse.cpp
        system/hid/display_manager.cpp
        system/hid/input_bindings.cpp
        system/hid/input_manager.cpp
        system/hid/sdl_util.cpp
        system/IOP_Kernel.cpp
        system/iop_thread.cpp
        system/load_gate.cpp
        system/autoport_proof.cpp
        system/npc_flicker.cpp
        system/SystemThread.cpp
        tools/filter_menu/filter_menu.cpp
        tools/subtitle_editor/subtitle_editor_db.cpp
        tools/subtitle_editor/subtitle_editor_repl_client.cpp
        tools/subtitle_editor/subtitle_editor.cpp
        )

add_subdirectory(sound)

# Gcollision-arm (1-to-1 ARM==x86 collision): force IEEE-strict, non-contracted FP
# for the mips2c VU0 collision translation units. The Android NDK clang build
# defaults to -ffp-contract=on (AArch64 has fmadd), so single-statement multiply-
# add/subtract in the VU0 emulation (vmadd/vmsub and the vopmsub cross product that
# computes the wall NORMAL — collide_func.cpp / mips2c_private.h) FUSE to fmadd:
# ONE rounding instead of the PS2/x86 TWO roundings. The x86 oracle (GCC -mavx, no
# -mfma) cannot emit FMA, so it stays non-contracted. That asymmetry makes arm64
# collision math diverge bit-for-bit from x86 (push-out distance / normal), the
# owner-reported "floats/decimals mishandled in the ARM translation". Disabling
# contraction here makes the arm64 collision pipeline BIT-IDENTICAL to x86 (proven:
# .autoport/reports/Gcollision-arm/). No-op on the x86 build (GCC has no FMA to
# disable). See .autoport/reports/Gcollision-arm-fix-summary.md.
# Real MSVC `cl` rejects `-ffp-contract=off` (clang-cl accepts it, hence the
# compiler-id guard); on MSVC the equivalent no-FMA-fusion mode is /fp:precise.
if(NOT (MSVC AND CMAKE_CXX_COMPILER_ID STREQUAL "MSVC"))
        set_source_files_properties(
                mips2c/jak1_functions/collide_cache.cpp
                mips2c/jak1_functions/collide_edge_grab.cpp
                mips2c/jak1_functions/collide_func.cpp
                mips2c/jak1_functions/collide_mesh.cpp
                mips2c/jak1_functions/collide_probe.cpp
                # Gperf-particles2: the 2d-NEON sparticle fast-path (sparticle.cpp) replaces the
                # scalar VU0 aging loop with inlined float math that MUST stay two-rounding
                # (multiply-then-add, no FMA) to be bit-identical to the PS2/x86 scalar path.
                # Its in-file comment asserted "-ffp-contract=off" but the file was NOT on this
                # list (it only passed by luck: the current NDK emitted no fmadd). Add it so the
                # bit-exactness is guaranteed across compiler/NDK changes — same rationale as the
                # collide TUs above. No-op on today's build (already non-contracted).
                mips2c/jak1_functions/sparticle.cpp
                # Gjak2-polish 2026-08-31: les memes TU pour jak2 — la liste Gcollision-arm
                # n'avait jamais ete etendue au second jeu (501 FMA fusionnees mesurees dans
                # les objets arm64 livres, contre 0 chez les jumelles jak1 ; detail et mise en
                # garde sur la mesure dans android/CMakeLists.txt). Ici c'est surtout une
                # garantie : le desktop compile sans -mfma, donc l'oracle x86 ne contractait
                # deja pas — on le verrouille au lieu de dependre de la chance, exactement
                # comme le commentaire sparticle ci-dessus le fait pour jak1.
                mips2c/jak2_functions/collide_cache.cpp
                mips2c/jak2_functions/collide_edge_grab.cpp
                mips2c/jak2_functions/collide_func.cpp
                mips2c/jak2_functions/collide_hash.cpp
                mips2c/jak2_functions/collide_mesh.cpp
                PROPERTIES COMPILE_OPTIONS "-ffp-contract=off")

        # Grecharged-grass-precompute-mode: keep the x86 bake tool and the arm64 runtime float-identical —
        # no FMA contraction divergence between the machine that writes <level>.grassbake and the one that
        # reads/expands it (bit-identical placement across x86 desktop and arm64 device).
        set_source_files_properties(graphics/opengl_renderer/GrassBakeCore.cpp
                PROPERTIES COMPILE_OPTIONS "-ffp-contract=off")
else()
        set_source_files_properties(
                mips2c/jak1_functions/collide_cache.cpp
                mips2c/jak1_functions/collide_edge_grab.cpp
                mips2c/jak1_functions/collide_func.cpp
                mips2c/jak1_functions/collide_mesh.cpp
                mips2c/jak1_functions/collide_probe.cpp
                mips2c/jak1_functions/sparticle.cpp
                PROPERTIES COMPILE_OPTIONS "/fp:precise")
        set_source_files_properties(graphics/opengl_renderer/GrassBakeCore.cpp
                PROPERTIES COMPILE_OPTIONS "/fp:precise")
endif()

# Gloading-screen: the loading-screen textures are NOT feature-gated. They used to
# ride inside RechargedHudTextures.cpp, which only joins the build under
# OG_FEAT_RECHARGED_HUD -- and the SHIPPED android build is hud=0, so slots
# 8311/8312 were never filled and DirectRenderer bound the grey checkerboard
# placeholder in place of the silhouette. The loading screen is not the HUD.
list(APPEND RUNTIME_SOURCE graphics/opengl_renderer/LoadingScreenTextures.cpp)

# Grecharged-buildsys-flags: feature-gated TUs are appended to RUNTIME_SOURCE
# only when their flag is ON (default OFF => symbol absent from gk). The
# runtime code that calls into them is #ifdef'd on the same OG_FEAT_* macro.
if(OG_FEAT_RECHARGED_HUD)
        list(APPEND RUNTIME_SOURCE graphics/opengl_renderer/RechargedHudTextures.cpp)
endif()
if(OG_FEAT_VULKAN_SUPPORT)
        list(APPEND RUNTIME_SOURCE graphics/pipelines/vulkan.cpp)
endif()

# Grecharged-buildsys-flags: stamp the flag-set id onto the marker TU only
# (kboot.cpp is shared with the android_kernel build). Source-file properties
# are directory-scoped under cmake 3.10, hence set here in the game/ scope.
set_source_files_properties(kernel/common/kboot.cpp
        PROPERTIES COMPILE_DEFINITIONS "OG_FLAG_SET_ID=\"${OG_FLAG_SET_ID}\"")

# we build the runtime as a static library.
add_library(runtime STATIC ${RUNTIME_SOURCE} "../third-party/glad/src/glad.c")

target_link_libraries(runtime common fmt SDL3::SDL3 imgui discord-rpc sound stb_image libco libcurl)
if(WIN32)
    target_link_libraries(runtime mman)
else()
    target_link_libraries(runtime pthread dl)
endif()

if(NOT OG_ARM64_BOOT_STUB)
    add_executable(gk main.cpp)
    target_link_libraries(gk runtime)
    if(WIN32)
        set_target_properties(gk PROPERTIES VS_DPI_AWARE "PerMonitor")
        # first-boot native folder picker (IFileOpenDialog) in main.cpp
        target_link_libraries(gk ole32 uuid)
    endif()
endif()

set(NPCF_GUARD_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/..")
if(NOT OG_ARM64_BOOT_STUB)

# ------------------------------------------------------------------------------------------------
# Gcutscene-npc-flicker (owner 2026-08-31) — LA GARDE TOURNE AU POINT DE PRODUCTION.
#
# Le defaut des PNJ qui clignotent en cinematique a deja ete corrige (Grecharged-hd-models3/4/5)
# et il est revenu. La garde laissee par ces phases-la etait `[hd-flicker] blackouts=0`, dont le
# compteur n'a plus AUCUN site d'ecriture depuis 45b7140ca7 : une clause qu'aucun chemin de code
# ne pouvait violer. Et aucun de ses trois scripts de preuve n'est appele par un validateur, un
# hook ou l'orchestrateur — ils ont tourne une fois, dans leur propre phase, jamais depuis.
#
# On ne peut donc plus construire le moteur sans que la garde passe. C'est la regle des DIRECTIVES
# du 2026-08-11 : quand une perte se repete, on la rend impossible AU POINT DE PRODUCTION, pas
# detectable au point de controle.
#
# SORTIE DE SECOURS ASSUMEE : OG_SKIP_NPCF_GUARD=1. Une garde qui peut bloquer definitivement la
# chaine de livraison serait pire que le defaut qu'elle surveille (meme raisonnement que le
# fail-open de game/system/load_gate.h). Par defaut elle est appliquee.
# ------------------------------------------------------------------------------------------------
if(UNIX AND NOT ANDROID_SKIP_NPCF_GUARD)
    add_custom_command(TARGET gk POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E env
                bash ${NPCF_GUARD_ROOT}/.autoport/lib/npcf_guard_hook.sh
        WORKING_DIRECTORY ${NPCF_GUARD_ROOT}
        COMMENT "npc-flicker: garde de non-regression (instrument + valeurs publiees)")
endif()
endif()

# When OG_ARM64_BOOT_STUB is on, the `gk` target is defined at the root scope
# (see root CMakeLists.txt) so its phony ninja path is `gk`, not `game/gk` —
# which avoids colliding with the CUSTOM_COMMAND output path build-arm64/game/gk.
