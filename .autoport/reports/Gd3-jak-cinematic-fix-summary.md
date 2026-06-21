# Gd3-jak-cinematic — fix summary

## Owner defect
"Jak is literally invisible in the new-game cinematic" (and "villains crash it").

## What the deterministic census actually found (premise corrected)
The audit premise was "Jak's merc bucket draws 0 tris / Jak not spawned." Deterministic,
x86-first device census **falsified that**:

- On BOTH x86 and the device, Jak's player model **eichar** IS spawned and submits merc
  geometry every cinematic frame: `common-pris-merc eichar-lod0 = 4245 tris`,
  `*target*` alive in state `target-clone-anim`. So this is NOT a spawn / scene-player /
  missing-bucket / merc-render-subset gap (consistent with Grender-audit D3: the merc
  pipeline is byte-correct on arm64).

The real, measured mechanism has **two coupled arm64-only defects**, both rooted in a
single NaN source:

1. **NaN bone matrices → Jak invisible + Adreno GLES SIG-11.**
   A degenerate root-motion align in the cinematic (1.0 / vector-length of a zero column
   in `matrix-inv-scale!`, ENGINE.CGO — see Gcine-pose) bakes a NaN into Jak's transform,
   which cascades through the whole skeleton. The C++ merc bone census showed a transient
   frame with `nan=1264 fin=0 root=(nan nan nan)` for eichar: every bone NaN that frame ->
   Jak collapses / flickers INVISIBLE. 41 ms later the Adreno GLES driver SIG-11s while
   processing Jak's merc draw (`GK-DIAG sig=11 fault=0x7efffffffc pc=0x7f02df0fc0`, crash
   handler breadcrumb `F1A-MERC-DRAW di=21/22 first_bone=64` = a GL-thread fault inside
   libGLESv2_adreno during a merc draw). The triangle-count census could not see this
   because tri counts are computed before bones — geometry is submitted, but with NaN bones.

2. **NaN `*target*` world transform → crash at the cinematic→gameplay transition.**
   The same align NaN leaves Jak's `*target*` root trsqv (`control.trans`) NaN from
   ~frame 945 (`GK-DIAG F1D target-pos ... =(nan nan nan)`). It is harmless while the
   scene-player drives Jak's on-screen pose, but when `*master-mode*` flips cinematic->play
   the gameplay/physics code reads the NaN position and the GOAL thread dies into the
   return-from-thread-dead trampoline (`sig=4 pc=0x18aee4`, frame ~10170), which blocks
   reaching gameplay. The merc blend-shape draw also intermittently re-stomps that
   trampoline band (the catalogued Gmatch/Gcine-crash3 0x18aee4 stomp), surfacing once the
   bone fix let the cinematic render past the earlier Adreno fault.

The true root (`matrix-inv-scale!` 1/0) lives in ENGINE.CGO, which cannot be rebuilt /
reseeded on this device (feedback-game-cgo-rebuild-unsafe -> SIGILL). So all fixes are
libgk-side, at the arm64 merc / kernel boundaries, mirroring the Gcine-pose precedent.

## The fix (3 parts, all libgk.so, arm64-gated / x86 no-op)

1. `game/graphics/opengl_renderer/foreground/Merc2.cpp` (`handle_pc_model`, `#ifdef __aarch64__`):
   before the bones are uploaded to the GPU, scan each used bone matrix; if any element is
   non-finite, restore that model's last fully-finite bone set (per-model cache) or identity.
   No NaN bone ever reaches the Adreno driver -> Jak renders every frame, the driver SIG-11
   cannot occur. x86 never produces NaN here, so the block is compiled out on desktop.

2. `android/gk_android_main.cpp` (`handle_rftd_code_stomp`, renamed from `handle_rftd_sigill`):
   broadened the race-free return-from-thread-dead trampoline repair-and-resume to also catch
   the **SIGSEGV** variant (not just SIGILL) when the fault pc is inside the protected band
   [0x18ae84,0x1912b4) and the band is actually stomped. Restores the canary snapshot and
   resumes; if the band is intact it returns false (a genuine fault is never masked).

3. `android/gk_android_main.cpp` (`a36_tree_scan_per_frame`, GOAL thread, always-on):
   repair Jak's NaN `*target*` root trsqv (trans/rot/scale) at the quiescent per-frame
   (sceGsSyncV) point — cache each field's last finite value and restore any that has gone
   non-finite (write-only-on-NaN, so a wrong field-offset guess can never overwrite a good
   value). Clears the NaN before the gameplay transition reads it, so the cinematic reaches
   gameplay. Logs `GD3-TARGET-TRANS-REPAIR` when it fires.

## Verification (device eae4df44, deterministic, no screenshots)
BEFORE (device-census-before3.log): Jak's bones go NaN (`nan=1264 root=(nan nan nan)`),
cinematic SIG-11s (crash_sigs=1) in Jak's merc draw; `*target*` NaN from frame 945.
AFTER  (device-census-after3.log): `crash_sigs=0`, reaches `A35-RENDER frame=18000`
(master-mode=game). Jak draws `enable=0xf visible=3593` every frame == the x86 gold
reference; `repaired_total=79` NaN-bone frames caught; `GD3-TARGET-TRANS-REPAIR x8` with
**0** residual `F1D target-pos =(nan` lines; `RFTD-STOMP-REPAIR x8` (repaired+resumed,
never fatal). x86 still boots `link finish: logo`; deploy_verify eae4df44 PASS.
Full proof: `.autoport/reports/Gd3-jak/jak-census.txt`.

## Temp dumps removed / cleanup
- REMOVED attempt-1's bulky ungated per-frame diagnostics: the `GD3-CENSUS` bucket-tris
  spew in `Merc2BucketRenderer.cpp` / `.h` (reverted to pristine) and the heavy per-frame
  `GD3JAKDRAW` bone+bbox dump.
- The remaining `GD3-MERC` line is property-armed (`debug.opengoal.gd3.census` /
  `OG_GD3_CENSUS`, OFF by default — no output in normal play); the `GD3-TARGET-TRANS-REPAIR`
  and `RFTD-STOMP-REPAIR` lines fire only when a repair actually happens (rate-limited).
  These are permanent, gated fix-observability (the Gcine-pose tripwire precedent), not
  per-frame dumps. No leftover ungated diagnostic dumps remain.
- The pristine golden `jak-original-v033` was not modified (git-clean).

## Scope / locks honored
ANDROID_SERIAL=eae4df44 only; no `goalc/emitter/IGenX86_64.*` touched; golden read-only;
fixes are libgk-side (no boot-CGO rebuild). Files changed: `game/graphics/opengl_renderer/
foreground/Merc2.cpp`, `android/gk_android_main.cpp` (+ `Merc2BucketRenderer.cpp/.h`
reverted to pristine).
