# Gorb-icon fix summary

## Owner defect (2026-06-23)
The Precursor ORB icon in the in-game HUD and the in-game progress menu renders as
a plain white "egg" on Android/arm64 — "as if the texture doesn't load, while every
OTHER asset loads fine (c'est le seul)". A single specific icon is white; everything
else is correct.

## x86-first diagnosis (deterministic state-dumps, not pixel-grind)
1. The HUD orb icon (hud-money, hud-classes.gc:448,597) and the menu orb icon
   (progress.gc:261-262) are NOT 2D sprites — both are the 3D merc model `money`
   (skelgroup *money-sg*, collectables.gc:646), base texture `egg-ndimadman`
   (common tpage, combo 30343212, 128x64) + a pal-environment-front envmap.
2. The TextureAnimator/anim-slot hypothesis was FALSIFIED: jak1 animates zero
   textures, m_anim_slot_array is nullptr for jak1, and the extractor never emits a
   negative draw.texture for jak1. The orb takes the normal positive-index path.
3. egg-ndimadman uploads to GL on device BYTE-IDENTICALLY to x86 (w=128 h=64 rw=128
   rh=64 glerr=0x0 avg=149,50,35,47) and is even merc-bound (handle 217) — so the
   bug is NOT the texture upload/load.
4. The decisive find: both the HUD and the menu spawn the orb with
   dma-add-func=dma-add-process-drawable-hud, so draw-bones-hud (bones.gc:1408)
   forces use-mercneric=1 and calls draw-bones-generic-merc (bones.gc:1494) -> the
   C++ Generic2 renderer (do_hud_draws). That path looks the texture up by tbp, not
   by merc handle. The world orb (Merc2) and the title options-menu orb (Merc2,
   pixel-verified == gold) render fine because they do NOT use generic-merc.
5. The entire generic-merc / generic-effect mips2c family (11 functions) was NO-OP'd
   on arm64 — absent from the kSet allowlist in
   game/mips2c/mips2c_table_jak1_arm64.cpp. The shared no-op returns 0; the orb's
   generic DMA bucket never builds; the orb HUD/menu draw never reaches Generic2.
   Device BEFORE (orb-HUD FX armed): GORB HUD count = 0 -> the orb icon's bound
   texture is MISSING = the white egg. (The kmachine.cpp:805 comment already named
   this path; the recent Gcrash-mouche fix suppressed its crash but never un-noop'd
   generic-merc.)

## The fix (translation layer; goal_src 1-to-1 preserved)
### Primary — enable generic-merc on arm64
Added the 11 generic-merc/generic-effect function names to the kSet allowlist in
game/mips2c/mips2c_table_jak1_arm64.cpp (the same un-noop pattern as Gsprite/Gwater/
Gd2/F1-collision). The C++ bodies already exist (generic_merc.cpp / generic_effect.cpp
/ generic_effect2.cpp, all in CMakeLists) — they were merely gated off. Pre-audited
hazard-free: none of the 11 use integer idiv/mod (no X8/R8 hazard); all s7 compares in
execute-asm are the self-relative #t/boolean idiom (cannot exhibit the upper-32
#f-guard misfire); the family is self-contained (only external callees are 3 plain
GOAL defuns reached via the proven _call_goal8_asm_arm64 FFI trampoline).
Device AFTER: all 11 bind to REAL arm64 trampolines (zero A37-MIPS2C-FALLBACK); the
orb HUD draw reaches Generic2 and binds the REAL egg-ndimadman (tbp=0x2412, GL
handle 109, placeholder=0) == x86. The white egg is gone.

### Secondary — arm64 bone-ref stomp guard (Sprite3)
Enabling generic-merc exposed a second, pre-existing arm64 bug. bones.gc:1124-1128
packs a pointer into a 128-bit DMA-tag via `(shl (the-as int s2-0) 32)` — the source
literally warns "does this work correctly for the upper 64 bits??". On x86 a GOAL ptr
is a clean 32-bit offset; on arm64 it carries dirty upper-32 bits, so the store writes
low-heap bone-ref pointer-pairs (high32 == heap pointer 0x17fd64) past the bone region
into the adjacent *sprite-array-2d* heap object, stomping one 2D sprite's adgif block.
The Sprite3 GS decoders then abort (clamp:0x17fd640017fd24 -> SIGABRT at frame 670).
bones.gc is goal_src (1-to-1 LOCKED), so the fix is the established translation-layer
content guard: game/graphics/opengl_renderer/sprite/Sprite3.cpp do_block_common skips
any 2D sprite whose clamp register high-32 is a heap pointer (>= HEAP_START 0x13fd20).
A valid CLAMP/ZBUF register high-32 is <= ~0xfff, so there are NO false-positives. The
orb is a 3D merc draw (not a 2D sprite), so it is unaffected; only the single stomped
sprite is dropped. Device: crash=no, ran to frame 4320 (was SIGABRT at 670), clean
Geyser scene, orb binds the real texture.

## Files changed (game/ + goalc-table only; NO goal_src; NO IGenX86_64)
- game/mips2c/mips2c_table_jak1_arm64.cpp — +11 generic-merc names in kSet (+comment).
- game/graphics/opengl_renderer/sprite/Sprite3.cpp — arm64 bone-ref stomp skip guard
  in do_block_common.

## Verification (device eae4df44, x86-first)
- egg-ndimadman device upload == x86 oracle (w/h/rw/rh/glerr/avg identical).
- BEFORE: GORB HUD = 0 (orb HUD bound texture missing/white).
- AFTER : GORB HUD egg-ndimadman hit=1 placeholder=0 GL handle 109 (== x86), for both
  the HUD (hud-money) and the menu (progress) generic-merc path.
- Stability: no crash, frame 4320 (was 670), clean scene.
- deploy_verify proves the device runs the fresh HEAD libgk with both fixes.
- x86 desktop smoke still reaches `link finish: logo` (the kSet change is arm64-only;
  it cannot affect the x86 build, which uses no allowlist).

## Temporary instrumentation — REMOVED (no leftover)
All diagnostic scaffolding added during the investigation has been deleted from the
final build; only the two real fixes above remain:
- REMOVED the GORB LOAD / GORB MODEL scan + gorb_relevant() helper from
  game/graphics/opengl_renderer/loader/LoaderStages.cpp.
- REMOVED the GORB MERC per-draw dump (and the temporary `#include <set>`) from
  game/graphics/opengl_renderer/foreground/Merc2.cpp.
- REMOVED the GORB HUD do_hud_draws dump (and the temporary `#include <cstdio>` /
  `<set>`) from game/graphics/opengl_renderer/foreground/Generic2_OpenGL.cpp.
- REMOVED the GMDMA-PTRPAIR scan (3 sites) from
  game/mips2c/jak1_functions/generic_merc.cpp.
- REMOVED the temporary `gorb.fx` repro hook (s_gorb_fx + the OG_GORB_FX /
  debug.opengoal.gorb.fx reads + the skelgroup selection) from
  game/kernel/jak1/kmachine.cpp.
The Sprite3 skip guard is NOT instrumentation — it is the permanent translation-layer
fix for the arm64 bone-ref stomp and is retained.

## Owner eye = final
The white-egg defect's bound-texture root (generic-merc no-op'd on arm64) is fixed and
the orb binds its real egg-ndimadman texture on device == x86, with the game stable.
Owner visual confirmation of the green orb in the HUD/menu is the final gate.
