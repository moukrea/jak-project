# Phase Grender-split — UI native + 3D scaled (renderer-side, both builds)

## Why (owner 2026-06-30)
On this engine ALL GOAL rendering (3D + sprites + HUD + menu text) goes into ONE `game_res` FBO, then
blits to the window — so RENDER SCALE % / Game Resolution soften the UI along with the 3D. The owner
wants the TRUE behavior: render the 3D scene at a chosen scale while UI/HUD/text stay NATIVE-crisp.
HARD CONSTRAINT (owner verbatim): this must be done IN THE RENDERER so it works identically on the
x86 build AND Android — NOT via an Android-native UI layer.

## Mandate (renderer + runtime; engine GOAL render logic untouched → gold oracle clean)
1. INVESTIGATE the OpenGOAL render path first (game/graphics/opengl_renderer/OpenGLRenderer.cpp
   do_pcrtc_effects / the bucket passes + android/android_opengl_renderer.cpp): identify where the 3D
   world buckets end vs where the 2D/HUD/sprite/menu buckets (progress, hud, sprite-distort) draw.
   Determine if 2D buckets can be retargeted to a native-resolution framebuffer while 3D buckets
   render to the scaled FBO, then composite (upscale 3D, draw UI native on top).
2. IMPLEMENT a render split: scaled-3D pass (the game_res*scale FBO) → upscale-blit to native → 2D/UI/
   HUD/text pass at NATIVE resolution on top. Same code on both renderers (one OpenGLRenderer family).
   This is the renderer (game/graphics + android/), NOT goal_src render logic.
3. Wire to the existing RENDER SCALE % option so lowering it softens ONLY the 3D; UI stays crisp.

## Honest scope warning
This touches the (historically locked) engine renderer. If a clean split is not achievable without
breaking PS2-resolution-dependent effects (depth, sprite placement, letterbox/lbox, pcrtc), STOP and
report exactly what blocks it + what a safe partial would be — do NOT hack a half-split that corrupts
effects. The owner play-test is the final gate.

## Verify (both builds, actual screen)
Device + x86: at RENDER SCALE 50%, the 3D is visibly softer but the HUD/menu TEXT stays crisp (vs the
current behavior where both soften). No broken effects (depth/sprites/letterbox correct), 0 flicker
(screenrecord). Full CONSISTENT build, deploy_verify PASS. Before/after screencaps at 50% showing
crisp-UI + soft-3D.

## Report (`.autoport/reports/Grender-split/report.txt`) with `RESULT: RENDER SPLIT UI-NATIVE 3D-SCALED`
the split design (where 2D vs 3D buckets diverge), screencaps proving crisp UI + scaled 3D on BOTH
builds, no-broken-effects confirmation, 0 flicker, x86 link finish: logo. If blocked, RESULT: RENDER
SPLIT BLOCKED + the exact blocker (honest).

## Locks: ANDROID_SERIAL=eae4df44; no goalc/emitter/IGenX86_64.*; engine goal_src untouched; .autoport/gold READ-ONLY.
## Max: max_turns 2000, max_retries 5. device: true, owner_verify: true.
