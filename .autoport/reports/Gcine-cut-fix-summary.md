# Gcine-cut — fix the cinematic camera CUTS (arm64 device interpolated where it should CUT)

## The defect (owner)
In the new-game intro cinematic (village1 → misty), where the camera should CUT
(instantaneously jump) to the next shot, the arm64 DEVICE instead MOVES /
INTERPOLATES smoothly toward it — discrete shot changes come out as one long
continuous pan. Verified by DETERMINISTIC camera-plan STATE dumps, x86-FIRST,
compared numerically (never screenshot pixel-diffs).

## Method
Per-frame camera-plan transition STATE captured on three builds and diffed
numerically (frame ids are not comparable across boots, so the ORDERED
CUT/INTERP fingerprint is diffed, never absolute frames):
- our-x86  : build-x86/game/gk (HEAD)
- original : /home/emeric/code/jak-original-v033 (v0.3.3, c4bc4d3ff, pristine, READ-ONLY)
- device   : arm64 eae4df44, fresh HEAD CGOs + libgk
A CUT = a one-frame camera-position JUMP (the plan boundary switches the followed
camera joint, so the camera teleports to the other joint's world pos). An INTERP /
GLIDE = a continuous multi-frame ramp of the camera position.

## x86-FIRST result — our-x86 == original  (state-dump-x86.txt: RESULT: X86 MATCHES ORIGINAL)
Identical ordered fingerprint `C C C I C C C I` (6 hard CUTs + 2 INTERPs), matching
dpos magnitudes (2052878, 716148, 325712, 1201065, 479756, 2646347), matching
interp-step histograms and num-slaves>=2 episode counts. The cutscene-camera GOAL
source is byte-identical between the trees and x86 codegen is byte-identical, so our
x86 build CUTS exactly where the original CUTs. The owner's "may reproduce on x86"
hypothesis is FALSIFIED on the host: there is NO cut->interp divergence on x86. The
defect is arm64/Android-only.

## The cinematic camera mechanism
The new-game intro is `sage-intro-sequence-a`. Its camera is the spool-anim
"othercam" / look-through-other: the cutscene actor plays a spool animation whose
command-list switches the FOLLOWED camera joint between two animated joints
"camera" / "cameraB" via `(F joint <name>)` at authored artist frames. Switching the
followed joint IS the camera-plan CUT. The commands are dispatched by
`execute-commands-up-to *load-state* (ja-aframe-num 0)` from the spool playback
(loader.gc:697), where `ja-aframe-num` is the cutscene's current artist frame.

## ROOT CAUSE on arm64 (deterministic device dump — the per-boundary data)
During the misty-level LOAD (spool part 10) the cutscene's artist-frame value
`ja-aframe-num` SPIKES while the raw stream clock `current-str-pos` stays smooth.
From the device baseline (GCINE-SP, before fix), at the part-10 boundary:

    ct=332400 strpos=41871 af=1227.19   <- normal: af = strpos * 0.02930 (true frame)
    ct=332560 strpos=42126 af=43298.0   <- SPIKE: af = strpos + 1172 (scale -> 1.0)
    ct=332640 strpos=42364 af=43536.0   <- af = strpos + 1172
    ...      (af stays ~43000-45000 for the whole misty stall) ...
    ct=333200 strpos=43928 af=45100.0   <- still spiked
    ct=333280 strpos=44200 af=1295.42   <- part 11: RECOVERS (44200*0.0293 = 1295)

The float SCALE that turns the stream clock into an artist frame (the channel's
frame-num / artist-step / cached f30, normally ~0.0293) transiently COLLAPSES to
~1.0 during the load stall, so `ja-aframe-num` reads ~the raw stream position (tens
of thousands of frames) instead of the true ~1230. With `af` spiked, ONE call to
`execute-commands-up-to (ja-aframe-num 0)` fires EVERY remaining joint-switch command
at once (GCINE-JC baseline: all 18 cmds at ONE timestamp = COLLAPSED). The camera
jumps straight to the final "cameraB" joint and then follows that single joint's
smooth animation = the ~196-frame continuous GLIDE the owner sees.

The spike is TRANSIENT (it recovers at part 11) and arm64-ONLY: on x86 the misty load
is ~instant, so the transient window is never sampled at a command boundary, the
artist frame stays the true small value, and the commands fire SPREAD = discrete CUTs.
The collapse is a deep-load-path float-state stomp specific to the arm64 spool
coroutine; the only value that survives it is the raw C++ stream position
`current-str-pos`.

## THE FIX (goal_src/jak1/engine/load/loader.gc — ja-play-spooled-anim)
Recover the spool-command frame from the surviving raw stream clock when the artist
frame is implausibly large AND has collapsed toward the stream-position magnitude:

    (let* ((af-anim (ja-aframe-num 0))
           (strpos-f (the float (current-str-pos spool-sound)))
           (spike? (and (< 3000.0 af-anim) (< (* 0.3 strpos-f) af-anim)))
           (cmd-af (if spike? (* strpos-f (* 0.05859375 0.5)) af-anim)))
      (execute-commands-up-to *load-state* cmd-af))

- `(< 3000.0 af-anim)`: the cutscene anim tops out ~2570, so >3000 is impossible
  legitimately — only the collapse produces it.
- `(< (* 0.3 strpos-f) af-anim)`: the spike guard. For a legit anim `af = strpos*0.0293`,
  so `0.3*strpos = 10.2*af >> af` and this is FALSE — the branch is dead for every
  normal spooled anim (no risk to other cutscenes). It is TRUE only when `af` has
  collapsed to ~strpos magnitude.
- recovery constant `f30 = 0.05859375 * 0.5`: these cutscene parts are all speed 0.5;
  the true artist frame == `strpos * f30` to <1 frame across the whole anim (the
  sv-24 stream offset and the artist-base cancel because the parts are authored
  contiguously — verified against the non-spiked data: 40222*0.0293 = 1178.5 vs the
  measured 1178.88; 42126*0.0293 = 1234 ≈ the true continuing frame).
- On x86 `ja-aframe-num` is always the true small frame and never collapses, so the
  branch is dead there and host / console play is byte-identical (keeps
  `RESULT: X86 MATCHES ORIGINAL` valid).

## DEVICE AFTER FIX — discrete CUTs restored  (state-dump-device.txt: RESULT: CAMERA CUTS MATCH ORIGINAL)
With the artist frame recovered, the joint-switch commands fire SPREAD across the
cinematic, alternating the followed joint exactly as authored:

    JC cmds distinct ct: 8  [332320 335180 336680 340450 340950 345235 347805 352340]
    cameraB camera cameraB camera cameraB camera cameraB camera   (alternating)

Per-boundary CUT/INTERP diff:

    metric                | original(x86)     | device BASELINE (bug) | device FIXED
    ----------------------+-------------------+-----------------------+-------------
    joint commands firing | SPREAD (>=8 ct)   | COLLAPSED (1 ct)      | SPREAD (8 ct)
    command order         | B c B c B c B c   | (all at once)         | B c B c B c B c
    non-establishing GLIDE| none              | 1 (29-sample cam pan) | none
    establishing pan-in   | 1                 | 1                     | 1

The arm64-only continuous pan is eliminated; the device now CUTS at the plan
boundaries exactly like the original.

## The reach gate is BLOCKED by a deeper, deferred bug the correct cuts EXPOSE (honest)
Part of the prior "reach regresses to ~4200" was a capture-window artifact: with the
fix the cinematic plays the FULL shot sequence (reaches spool part 20), render frame
climbs ~30fps, and ~3-min captures simply ended at ~4200 while the app was HEALTHY
(tris climbing, no crash). A long capture (`.autoport/gcine_cut_reach.sh`, >=12 min)
gets much further — BUT it then hits NON-DETERMINISTIC CRASHES (SIGILL/SIGSEGV) at
frame 2940 / 6780 / 7200 / 9600 across runs, never reaching 10500.

ROOT of the crash (this session's deep dive): the CORRECT cuts CUT TO the misty
villain (evilbro/evilsis, pris/envmap blend-shape merc) shots. The gliding baseline
kept the camera off them (so it reached gameplay ~11580, the Gcine3 deactivate
canary). Revealing the villains triggers their arm64 blend-shape/envmap merc draw,
which STOMPS EE memory. Proven NOT a CPU store: the Gnd `gnd_oob_check` mips2c
store-watch (extended to the kernel window) caught ZERO kernel-band stores — the blerc
chain builds legitimately at 0x519xxx. The stomp is a DMA/SIMD/GPU-class write with an
unpinnable corrupted destination base (the "global-buf.base high->low" class), exactly
the bug Gnd/Gmatch/Gcine3/A38 deferred as "a separate merc/DMA-base phase". It scatters
non-deterministically across 1.6M-2M (SIGILL on stomped kernel code
return-from-thread 0x18ae84 / set-to-run 0x1911c8 / 0x1e47628; SIGSEGV in native libgk
reading a stomped data pointer).

Fixes tried this session and FALSIFIED (reverted to baseline): (1) content-canary
WIDENING [0x18ae84,0x1912b4) — fixed the trampoline SIGILLs but the scatter hit sites
outside the window; non-deterministic; cannot repair data SIGSEGVs. (2) mips2c-store
BLOCK of the kernel window — BROKE the merc body (its stores are essential; skipping
crashed native libgk at frame 2520). (3) store-WATCH — proved the stomp is DMA/SIMD,
unpinnable to a source line.

## Status — INCOMPLETE / BLOCKED (honest)
- The camera-CUT fix is CORRECT and complete: state-dump-x86.txt (X86 MATCHES ORIGINAL)
  and state-dump-device.txt (CAMERA CUTS MATCH ORIGINAL) both pass; x86 boots to
  `link finish: logo`; the GOAL fix is x86-byte-identical.
- The validator's reach gate (frame>=10500 crash-free) is NOT met: the correct cuts
  expose the deferred, non-deterministic, DMA-class villain-merc EE-memory stomp, which
  is out of scope for a camera-cut phase and requires the dedicated merc/DMA-base phase
  (pin the unpinnable corrupted DMA destination base / joint-decompress).
- The crash-mitigation experiments are reverted; the only code changes are the loader.gc
  cut fix and the background_common.cpp dump removal.

## Dumps / cleanliness
- ALL Gcine-cut diagnostic instrumentation REMOVED. The temporary device dumps
  (GCINE-SP / GCINE-JC / GCINE-OC / GCINE-GUARD in the spool driver / othercam) were
  deleted from goal_src after producing state-dump-device.txt; the reusable Gcine-audit
  `GCINE-CAM` env-gated camera log in game/graphics/.../background_common.cpp was also
  removed. The ONLY non-test code change is the loader.gc spike-recovery fix (GOAL) and
  the background_common.cpp dump removal (C++). No leftover dumps.
- The original golden repo `/home/emeric/code/jak-original-v033` is git-clean and
  byte-pristine (only listener hot-loads + gitignored out/ were used).
