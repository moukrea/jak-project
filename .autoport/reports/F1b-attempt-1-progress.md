# Phase F1b — joint-decompress / camera-flight: honest progress report (attempt 1)

Headline: the title-camera freeze is now pinned to a hard, oracle-confirmed
divergence — the **logo-cam-logo-loop joint animation decompresses to a frozen
output on device while it flies on desktop** — and, more importantly, the
phase's *entry hypothesis* ("another arm64 emitter SIMD stand-in in the
decompressor, the bug-class #11/#12 pattern") has been **FALSIFIED by three
independent lines of evidence**. Dynamic per-joint quaternion interpolation
works on arm64 (the title's Jak/Daxter models animate with correct
4-component quaternions); the op-census of the decompressor shows correct
lowering; and F1a already proved the camera matrix math is bit-identical. The
freeze is NARROWER than feared and is NOT where attempt-1's mandate pointed.
bug class #13 is re-localized but NOT yet fixed. START / Geyser Rock / control
were NOT reached.

## 0. Validator gate status (all hard gates GREEN)
- x86 desktop smoke: `link finish: logo` PASS (/tmp/f1b-x86-smoke.log).
- qemu boot: 675 'link finish:' lines (floor 675, no regression).
- libgk.so renderer syms: DirectRenderer=62, DmaFollower/send_chain=62,
  Merc2/MercRenderer=54 (all physically present).
- Newest F1b device run (run3): max frame=8820, max tris=28547 (sustained
  60fps display loop, renderer drawing).
- Device screencaps: F1b-device-run{1,2,3}-*.png (13 brackets/run, 8-150 s).
- No forbidden edits: only probe instrumentation in joint.cpp (mips2c, NOT
  goal_src), gk_android_main.cpp, sceGraphicsInterface.cpp. IGenX86_64 /
  goal_src / infra all untouched. Anti-cheat clean.

## 1. Instrumentation built this phase (twin probes, both backends)
- **F1B-TRS** (joint.cpp `cspace_parented_transformq_joint::execute`, the
  mips2c bone builder, identical C++ on both backends): windowed dump of the
  per-joint INPUT transformq (the GOAL decompressor's output: t / q / s) and
  OUTPUT bone row3. Because this function is the same C++ on x86 and arm64,
  any divergence in the dumped transformq is purely upstream in the
  GOAL-compiled decompressor. Gated by OG_F1B_TRS (desktop env) / `f1b_trs`
  marker file (device run-as). 48-call window every 8192 calls.
- **F1B-JB / F1B-FG** (gk_android_main.cpp + desktop twin in
  sceGraphicsInterface.cpp `f1b_jb_probe_desktop`, OG_F1B_JB): per-tick dump
  of the title logo master + camera-slave joint-chain OUTPUT (nodes 3..5 bone
  row3/row0) and channel-0 frame-group identity (art name string, num-frames,
  control-bits, num-joints).
- 3×150 s device runs (run1/2/3) + 3 desktop oracle rounds
  (/tmp/f1b-x86-round{1,2,3}.log, OG_F1B_JB). Op-census disasm of joint.o
  (x86+arm64, 77 functions each) at /tmp/f1b-disasm/{x86,arm64}/fn*.txt.

## 2. The oracle diff — the camera freeze, exactly
- **DESKTOP** camera-slave loop (proc 0x1deff4, node 4 = the camera look
  joint) FLIES: f=2100 r3=(-746726,224324,677988) → f=3000
  r3=(-617383,117825,245174) → f=5700 r3=(-851379,273627,862655) → … every
  300-frame sample distinct; r0 (rotation) changes every sample.
- **DEVICE** camera-slave loop (proc 0x1e64c4, node 4, bone 0x1e6a90) is
  FROZEN: f=3000 / f=6000 / f=9000 all byte-identical at
  r3=(-543372.9,189225.1,874363.8), r0=(-0.1280,0.9808,-0.1472).
- The frozen joint's decompressed quaternion (F1B-TRS, bone 0x1e6a90):
  **q=(0.3924, 0.5310, 0.5310, 0.5310)** — CONSTANT across the entire run,
  every one of its 55 sampled calls. Its sibling fixed joint (node 3, bone
  0x1e6a30) is correctly identity q=(0,0,0,1), t=(0,-409600,0).
- Control is HEALTHY while the output is frozen (F1B-FG + F1A-CAMJOINT on
  proc 0x1e64c4): the frame-group respools intro → intro-2 → loop
  (logo-cam-logo-intro → -intro-2 → -loop), frame-num advances and cycles
  (17.55 → 40.63 → 46.79 …), the `fixed`/`frames` pointers refresh per spool
  part, skel is valid, draw-status=0x3010080 (has-joint-channels), and
  `othercam` (the watcher) is alive. Time advances; the decompressed pose
  does not. This is the precise F1a "freeze at the logo-loop respawn",
  now reduced to a single animation and a single frozen quaternion.

## 3. The entry hypothesis ("decompressor SIMD stand-in") is FALSIFIED
Three independent disproofs:

1. **Characters animate correctly on device.** A global quaternion survey of
   run3 F1B-TRS: of 474 distinct joints, **140 have time-varying 4-component
   quaternions** with all lanes distinct — e.g. the title-intro `sidekick`
   (Daxter, bone 0x1eb290: 9 distinct quats like (0.0073,0.9935,-0.1090,
   0.0305), (0.1002,0.9892,-0.0780,-0.0730)) and `eichar` (Jak) joints. The
   dynamic per-joint quaternion-interpolation path (decomp-frame +
   finalize-frame!'s quaternion-normalize!) therefore WORKS on arm64. A
   global decompressor/SIMD stand-in would freeze these too — it does not.

2. **The "master logo moves" signal that motivated the decompressor theory
   was a misread.** The master logo letters carry **identity** local
   quaternions q=(0,0,0,1) (rigid letters); their visible flight comes
   entirely from the parent/root transform, so they NEVER exercise the
   dynamic per-joint quaternion path. F1a saw parent-driven rigid motion and
   inferred "the decompressor works for the master, so the bug is a narrower
   stand-in"; in fact the master never tested the path at all.

3. **Op-census of the decompressor shows correct arm64 lowering.**
   - `eval-blend-tree!` `.mul.x.vf` (broadcast-lane-X multiply) lowers on
     arm64 to `dup vN.4s, vM.s[0]` + `fmul vK.4s, vK.4s, vN.4s` — exactly the
     semantics of x86's `vshufps $0x0,%xmm,%xmm,%xmm` + `vmulps` (broadcast
     lane 0, then full 4-lane multiply). Verified instruction-for-instruction
     in /tmp/f1b-disasm.
   - decomp-fixed (fn7), decomp-frame (fn8), eval-blend-tree! (fn1) are all
     ~1.39× their x86 byte size — normal AArch64 fixed-width expansion, **no
     stand-in bloat** (a stand-in emits extra fix-up instructions and stands
     out; A34/A42's did).
   - quaternion-normalize! (quaternion.gc) is ratio-preserving, and F1a's
     A36-TFRAG-CAM proved the camera matrix is bit-identical at a matched
     moment ⇒ normalize + matrix-from-quaternion already work on arm64.

4. **Not the A37 anti-stomp guard either.** joint.cpp's `suspicious` bone-skip
   (`if (suspicious) return 0;`) fired **0 times** in run3, and the camera
   bone 0x1e6a90 is in-range (not flagged). The bone store happens; the value
   written is frozen.

## 4. Re-localization — what the bug actually is
The freeze is SPECIFIC to the `logo-cam-logo-loop` (and -intro-2) camera
animation's decompression. Its control bits are cb=0x000000b8, nj=2: joint 0
ctrl=0x8 (no dynamic components), joint 1 ctrl=0xb (dynamic big-trans + dynamic
quat). Joint 1 is the frozen camera-look joint. The output equals a single
constant pose = consistent with **only the FIXED contribution surviving and
the DYNAMIC (keyframe-interpolated) contribution being dropped for this
animation on device** — i.e. the per-channel blend weight or the keyframe
index/interp for this specific animation collapses, not the decompressor math.
Corroborating: the title-INTRO camera slaves DID move on device (e.g. f=600
r0=(-0.1145,-0.0299,1.3950)); only the loop animation sticks.

Net correction to the mandate: because Jak/Daxter already animate on device,
the premise "Jak cannot walk without this fix" is too strong — the dynamic
skeleton path is alive. The camera-loop freeze is a narrower defect in the
blend/keyframe selection for this animation (or in the look-through/clone
plumbing feeding the title course), not the whole decompressor.

## 5. Why I stopped here instead of shipping a fix
- The decompressor internals (decomp-frame, eval-blend-tree!, build-requests!)
  live in **goal_src/jak1/engine/anim/joint.gc — a hard lock for this phase**.
  I cannot add interior probes to it, and the four C++-observable hypotheses
  (wrong blend weight / wrong frame index / data-pointer desync for cb=0xb8 /
  clone-copy plumbing) are indistinguishable from the input/output taps alone.
- A speculative IGenARM64 change is unjustified and dangerous: the op-census
  shows the candidate ops are already correct, characters animate, and the
  village flythrough renders — a blind emitter edit would risk regressing
  proven-good paths for an unproven theory. The phase forbids weakening any
  prior fix, and the project rule is honest failures over false greens.

## 6. Exact next probe (scripted for the next attempt)
1. From the C++ side (gk_android_main, where the joint-control object is
   reachable by address), dump for the loop camera channel on BOTH backends:
   joint-control `active-channels`; per-channel `command` / `frame-num` /
   `frame-interp` / `inspector-amount` (eval-blend-tree! INPUTS + OUTPUT
   weights); and, after a tick, the produced per-request `frame` /
   `frame-interp` / `amount`. The first field that differs device-vs-desktop
   names the stage: weight≈0 ⇒ eval-blend-tree!; wrong frame index ⇒
   build-requests!; both right but pose frozen ⇒ data-pointer walk inside
   decomp-frame for cb=0xb8.
2. Test the clone/look-through path: confirm whether the loop camera-slave is
   self-animated (it appears to be: valid skel, has-joint-channels) vs fed by
   flatten-joint-control-to-spr / clone-anim — if a copy, the freeze is in the
   spr-flatten/clone SIMD copy, not decomp.
3. Only after the stage is named: if it lands in an emitter op, fix
   IGenARM64.cpp with NDK-verified semantics, regen all 28 DGOs (x86 CGOs must
   stay byte-identical; qemu ≥ 675), reinstall, re-run, and verify the loop
   camera FLIES (proc-0x1e64c4 node-4 r3 changes across late ticks) before
   touching START.

## 7. Honest residuals / not done
- bug class #13 NOT fixed; the camera still freezes at the logo loop.
- START not pressed; Geyser Rock (training) not loaded; Jak control not
  exercised — all gated behind the title course holding (this fix).
- F1a blocker A (village merc draw → Adreno fault) untouched; Geyser Rock has
  its own level data, so this may not block it, but it is unverified.
- Interlopers (xiaoji ×2, sshxmobile, ghplus) disabled per device run by the
  run script's trap and re-enabled on exit; no new device run was started in
  this analysis pass.

## 8. Evidence inventory
- Device: F1b-routed-logcat-run{1,2,3}.log, F1b-device-run{1,2,3}-*.png (39
  frames), F1b-focus-run{1,2,3}.txt.
- Desktop oracle: /tmp/f1b-x86-round{1,2,3}.log (OG_F1B_JB), /tmp/f1b-x86-
  smoke.log, /tmp/f1b-qemu.log (675).
- Op-census: /tmp/f1b-joint-{x86,arm64}.o, /tmp/f1b-disasm/{x86,arm64}/fn*.txt
  (fn1=eval-blend-tree!, fn7=decomp-fixed, fn8=decomp-frame, fn10=finalize-
  frame!), /tmp/f1b-disasm-run.log.
- Probes: joint.cpp (F1B-TRS), android/gk_android_main.cpp (F1B-JB/F1B-FG),
  game/graphics/sceGraphicsInterface.cpp (f1b_jb_probe_desktop twin).
