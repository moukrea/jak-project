---
name: project-gorb-icon-state
description: Gorb-icon PASS — orb white-egg = generic-merc no-op'd on arm64; un-noop'd + bone-ref stomp guard
metadata:
  type: project
---

Gorb-icon PASS 2026-06-24 (commit 40184a01c). Owner: the Precursor ORB icon in
the in-game HUD + progress menu was a plain white "egg" (the ONLY asset that
failed).

ROOT: the orb is the 3D merc model `money` (*money-sg*, base tex `egg-ndimadman`
common 128x64 + pal-environment-front envmap). The HUD/menu spawn it with
dma-add-process-drawable-hud, so draw-bones-hud (bones.gc:1408) forces
use-mercneric=1 -> draw-bones-generic-merc -> the C++ **Generic2** renderer (NOT
Merc2). The whole **generic-merc/generic-effect mips2c family (11 fns)** was
NO-OP'd on arm64 (absent from kSet in mips2c_table_jak1_arm64.cpp) -> the orb's
generic DMA bucket never built -> orb HUD draw never reached Generic2 -> white.
Texture/upload were always fine (red herring). World orb + title-options-menu orb
use Merc2 -> always rendered. Falsified en route: TextureAnimator/anim-slot (jak1
animates nothing), texture-upload, envmap-texture (shared w/ fine fuel-cell).

FIX 1: added the 11 generic-merc fns to kSet (un-noop, same as Gsprite/Gwater/Gd2
/F1-collision; bodies pre-existed). **generic-merc is now LIVE on arm64** — HUD
merc icons (money/forced-mercneric) render. Orb binds real egg-ndimadman
(tbp 0x2412, handle 109, placeholder=0) == x86.

NEW arm64 bug class (FIX 2, the reason generic-merc was left off): bones.gc:
1124-1128 packs a ptr into a 128-bit DMA-tag via `(shl (the-as int ptr) 32)` —
the source itself warns "does this work correctly for the upper 64 bits??". On
arm64 GOAL pointers carry DIRTY UPPER-32 (see [[feedback_arm64_x86_model_reg_ids]]
"GOAL ptr = low32(host addr)"), so the shift writes bone-ref pointer-pairs (high
0x17fd64) past the bone region into the adjacent *sprite-array-2d* heap object,
stomping one 2D-sprite adgif -> Sprite3 SIGABRT (clamp:0x17fd640017fd24). bones.gc
is goal_src (locked); the ROOT (goalc arm64 ptr-shift codegen) is UNFIXED —
similar `shl ptr 32` stomps may surface elsewhere. Translation-layer guard:
Sprite3::do_block_common skips any 2D sprite whose CLAMP high-32 is a heap ptr
(>= HEAP_START 0x13fd20; valid CLAMP/ZBUF high-32 <= ~0xfff -> no false-positive).

Diagnosis method (owner-aligned, [[feedback_state_dumps_x86_first_not_screenshots]]):
deterministic GORB-* state dumps (GORB HUD = Generic2 tbp->tex bind; GORB LOAD =
upload avg vs x86) + a temporary gorb.fx repro hook (mouche-style: spawn *money-sg*
as HUD object). 3 screenrecord attempts all missed the one-shot FX (fires during
ND-logo load, off-screen) — owner state-dumps were the real proof. Device:
crash-free to frame 4680 (was SIGABRT@670), orb binds real tex == x86. Owner
visual confirm of the green orb = final gate. See [[feedback_arm64_mips2c_fnull_guard]],
[[feedback_cross_thread_stomp_repair_resume]], [[project_gmenu_textures_state]].
