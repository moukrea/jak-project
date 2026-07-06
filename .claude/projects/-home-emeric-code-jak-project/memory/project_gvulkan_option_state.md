---
name: project_gvulkan_option_state
description: Gvulkan-option outcome — no upstream Vulkan renderer exists; delivered selection plumbing + menu + a real x86 SDL_gpu Vulkan present; full renderer port + Android runtime deferred.
metadata:
  type: project
---

Gvulkan-option (2026-07-06, idx 183) — PASS as an HONEST PARTIAL. Owner play-test pending (no Android
device was connected during the headless run).

**Corrected false premise:** the phase assumed upstream OpenGOAL has a Vulkan renderer to wire up. It
does NOT in this checkout — no `game/graphics/vulkan_renderer/`, nothing in `git log --all`, never
existed. The game renders through **47,315 lines of raw OpenGL** (101 files) + dozens of GLSL shaders.
Porting that to Vulkan (both builds, oracle-matched) is a multi-person, multi-month effort — infeasible
in one phase. So a "Vulkan option" here = selection infrastructure + menu + a real minimal Vulkan
present, with the actual game-geometry renderer DEFERRED.

**What shipped (commits 7d50c5fb8, 01c01f532, 2a7e7c8c1 on autoport/android-port):**
- Backend selection: `GfxPipeline::Vulkan`; `DisplaySettings::renderer` int in display-settings.json
  (C++-readable), read by `Gfx::Init` BEFORE the GOAL kernel loads (the crux — pc-settings.gc is read
  too late/wrong-format for C++). Default 0 = OpenGL/GLES → GL/GLES stays default, unchanged.
- Menu: "VULKAN RENDERER" on-off toggle appended before Back in both `*graphic-options-pc*` /
  `*-android*` arrays (progress-pc.gc), on-change → gfx-renderer + `pc-set-gfx-renderer!` + commit.
  ALL menu edits in `goal_src/jak1/pc/` (engine goal_src untouched, lock-compliant — reused the existing
  `pc-gfx-renderer` enum + `gfx-renderer` field, un-commented its serializer).
- x86 Vulkan RUNTIME (real, verified): `game/graphics/pipelines/vulkan.cpp` — a minimal SDL3 **SDL_gpu**
  module (`gRendererVulkan`) that creates a Vulkan device+swapchain and clears+presents. renderer=1 →
  `[Vulkan] SDL_gpu device up (driver: vulkan)` → boots to `link finish: logo` at ~60fps, 0 swapchain
  errors. HONEST LIMIT: presents a CLEARED surface, not the scene (send_chain is a no-op; buckets not
  ported). gfx.cpp + vulkan.cpp are DESKTOP-ONLY (game/CMakeLists.txt; Android uses android/CMakeLists.txt).
- Android: menu option appears (shared GOAL) + persists; Vulkan RUNTIME DEFERRED (keeps GLES, protects
  the working build). Native libgk rebuild verified clean (no regression).

**Deferred:** the Vulkan game renderer (47k-line bucket + SPIR-V port); Android Vulkan surface/runtime;
on-device verification (owner play-test). See [[feedback_android_pc_port_binding_location]] for the
Android crash-safety gotcha this phase hit. Related: [[project_gwater_state]] (renderer-family 3-part
pattern), [[feedback_1to1_fix_in_translation_layers]].
