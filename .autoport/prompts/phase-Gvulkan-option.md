# Phase Gvulkan-option — add a Vulkan renderer backend as a selectable option (both x86 + Android)

## Why (owner 2026-07-04, backlog)
Today x86 renders via OpenGL and Android via OpenGL ES. The owner wants **Vulkan** available as a
CHOICE in BOTH builds, exposed via a dedicated entry in the in-game Graphics Options. This is a LARGE
effort and a BACKLOG item (do it after the swamp crash + perf glitch are resolved) — scope carefully.

## Scope / investigation FIRST (do not blind-implement)
1. Upstream OpenGOAL already has a Vulkan renderer tree — check `game/graphics/vulkan_renderer/` (or
   similar) and how the desktop selects a backend (a setting / `--vulkan` flag / `gfx_renderer`
   config). Map what EXISTS vs what's missing. The realistic path is to WIRE UP + fix the existing
   Vulkan backend, not write one from scratch. If the Android GLES port never included the Vulkan
   TUs (the Android renderer is a curated subset — see the Gwater 3-part renderer-family pattern),
   most of this phase is: compile the Vulkan backend into the Android build, provide an
   arm64/Android-compatible Vulkan surface (SDL3 Vulkan or a native VkSurface via the Android
   window), and gate it behind the option.
2. Decide honestly whether full Android Vulkan is feasible in one phase. If not, deliver
   INCREMENTALLY and honestly: e.g. (a) desktop x86 Vulkan selectable first (likely mostly there),
   (b) Android Vulkan as a follow-up, OR ship the menu option + backend selection plumbing with
   Vulkan working on whichever build is achievable and the other clearly marked "not yet".

## Mandate
1. RENDERER BACKEND SELECTION: a persisted setting (pc-settings) choosing GL/GLES vs Vulkan, read at
   startup to pick the backend. Applies to both builds where Vulkan is available.
2. GRAPHICS OPTIONS ENTRY: add a dedicated "Renderer" (or "Graphics API") option to the in-game
   Graphics Options menu (respect the established menu ordering / persistence / touch+pad from the
   Goptions-reorder + Gtouch-fix work). Changing it persists; note if a restart is required to
   switch backend (likely — surface recreation).
3. Vulkan renders the game CORRECTLY on the build(s) delivered (title + a gameplay scene match the
   GL/GLES output — oracle-diff vs the GL path, not a blank/garbage frame). Note the fps delta.
4. No regression to the existing GL/GLES path when the option is left on GL/GLES (the DEFAULT stays
   GL/GLES so nothing changes for users who don't opt in).

## Verify
Menu shows the Renderer option (screencaps), switching to Vulkan renders the game correctly on the
delivered build(s) (side-by-side vs GL/GLES), setting persists, GL/GLES default unchanged, fps noted.
x86 link finish: logo (if x86 Vulkan delivered, it also boots under Vulkan). Full CONSISTENT build,
deploy_verify PASS (Android). Honest partial delivery is acceptable and must be labeled.

## Report (`.autoport/reports/Gvulkan-option/report.txt`) with `RESULT: VULKAN RENDERER OPTION`
what existed upstream vs what you wired, which build(s) got working Vulkan (+ what's deferred), the
menu option + persistence, correctness oracle-diff vs GL/GLES, fps delta, GL/GLES default unchanged.
If blocked: honest RESULT: VULKAN RENDERER OPTION BLOCKED + the exact blocker.

## Locks: ANDROID_SERIAL=<current owner device>; no goalc/emitter/IGenX86_64.*; engine goal_src untouched (pc/ ok); .autoport/gold READ-ONLY.
## Max: max_turns 3000, max_retries 6. device: true, owner_verify: true.
