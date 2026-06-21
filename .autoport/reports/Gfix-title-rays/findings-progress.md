# Gfix-title-rays — definitive findings (x86-first deterministic state dumps, NO pixels)

## 1. What the title "blue light rays" are
- skelgroup `logo-volumes` (title-obs.gc:57), drawn via the NORMAL merc path (NOT envmap).
  `global-effect = (draw-effect title)` (title-obs.gc:141) only swaps in the camera-rotated
  `title-light-group` lighting (drawable.gc:462-473), computed ONCE per intro (title-updated
  guard), with STATIC colors (time-of-day.gc:180-184).

## 2. Deterministic per-frame dumps — 3 backends (Merc2.cpp, property-armed OG_RAY_DUMP)
For `logo-volumes-english-lod0`, every frame of the draw window, original-x86 / our-x86 / device:
- RAYFADE (envmap fade rgba) = 0,0,0,0 on ALL → NOT the envmap path.
- RAYLIGHT (VuLights) = dir0=(0.612,-0.696,0) c0=(0.8,0.8,0.8) amb=(0.2,0.2,0.2) — CONSTANT, IDENTICAL.
- RAYDRAW = ab_en=1 ablend=3 (pure additive GL_ONE/GL_ONE) at_en=1 ialpha=1 tris=704 tex=40 — IDENTICAL.

## 3. The owner's premise is FALSIFIED
"Ray intensity/color animates to ~0" is FALSE: the rays render with IDENTICAL inputs on x86 and
device (pure-additive blend, constant lighting, fade=0, fixed geometry/texture). They add a
constant amount every frame for the full logo-intro spool on BOTH backends. There is NO
ray-intensity divergence to dump or fix.

## 4. The real device-specific arm64 bug found AND fixed
The spooled-title-anim frame-rate scale `f30-0` (loader.gc::ja-play-spooled-anim:683/735) is held
in a GOAL-callee-saved xmm register across the spool loop. goalc maps xmm8-15 → arm64 V24-V31
(arm64_reg5 = id&0x1f; xmm ids 16..31). The GOAL→C++ FFI trampolines (asm_funcs_arm64.s:
_arg_call_arm64/_stack_call_arm64/_mips2c_call_arm64) saved q8-q15 (V8-V15) around the C++ call —
the WRONG SIMD bank (goalc never uses V8-V15). So C++/mips2c FFI callees clobbered the GOAL
caller's xmm8-15 (V24-V31), corrupting any GOAL float held across the call. x86 is correct
(System V spills all xmm across calls), so our-x86 == original-x86.

PROVEN empirically: changing the saved bank MOVES the title spool anim fnum at f=1200:
buggy-q8-15 fnum=63.66; my-swap-bug fnum=1.63 (frozen); corrected-q24-31-no-swap fnum=61.67.
So f30-0 IS in V24-V31 and IS exposed to the FFI clobber.

FIX (asm_funcs_arm64.s, arm64-only): the 3 GOAL→C++ trampolines now save/restore q24-q31 in
matching register pairs (no swap). Stable on device (crash-free full session through the FFI
path). This fixes the documented Gcine-cut/cutscene `f30-0` "slow-mo" stomp class at its ROOT
(Gcine-cut only worked around it with a strpos cmd-af recovery).

## 5. HONEST limit — the FFI fix does NOT measurably change the title RAYS
After the fix: device ray draw window UNCHANGED (314 frames, ~6.7s), fade=0, c0=0.8, ablend=3,
village1 reveal still at the window end. The corrected anim fnum (61.67) ≈ the pre-fix value
(63.66), so the title spool's f30-0 was COINCIDENTALLY ~correct before (the clobber garbage ≈ the
true value). So the title rays' additive draw behaviour is unchanged by the fix.

By ALL measurable deterministic state — intensity, lighting, blend mode, geometry, anim rate,
draw duration, village reveal timing — the device title rays MATCH original-x86. The rays are
drawn for the TRUE spool duration (f28-0, computed fresh; unaffected by the clobber) on BOTH
backends.

## 6. Why a clean x86 "0.6s" reference could not be obtained
x86 in this headless env cannot run the title at vsync-correct 60fps pacing: vsync-ON freezes the
render (swap blocks on the occluded Wayland window → whole EE+render loop stalls pre-attract);
vsync-OFF / SDL offscreen unblocks but DECOUPLES the IOP-vblank/strpos clock from real-time (the
spool plays ~35x fast → an artificial 36-frame ray window). The blocking swap IS the 60Hz pacer,
so no driver knob gives both "advances past the freeze" AND "true 60Hz pacing" without an
attached display or a wall-clock render pacer.

## 7. Residual / recommendation
If the owner-visible "linger" persists, it is NOT in any deterministic state this methodology can
read — it can only be a GLES rendered-brightness / framebuffer-composition difference of the
additive draw (requiring pixel/oracle measurement, which this phase forbids) or the owner's eye.
The additive-merc blend (background_common.cpp SRC_0_FIX_DST → GL_ONE/GL_ONE) and the GL_RGBA8
render target are shared, non-GLES-overridden code. Recommend re-scoping any residual to a
GLES additive-brightness / framebuffer pixel-oracle investigation.
