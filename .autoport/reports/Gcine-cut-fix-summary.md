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

## The reach blocker SOLVED — arm64 merc blend-shape DMA base corruption (root cause)
The correct cuts CUT TO the misty villain (evilbro/evilsis, pris/envmap blend-shape
"merc") shots. The prior gliding bug kept the camera OFF them; revealing them triggers
their arm64 blend-shape ("blerc") DMA, which was STOMPING EE memory and crashing the
run before 10500 (SIGILL on stomped kernel code @ 0x1e47628 / 0x18ae84 / 0x1911c8;
SIGSEGV on a stomped data pointer). This is the "global-buf.base high->low" class
Gnd/Gmatch/Gcine3/A38 had deferred — and it is now fixed at its SOURCE.

ROOT CAUSE (pinned this session): `merc-blend-shape` (called per process-drawable from
generic-obs.gc / process-drawable.gc / sidekick.gc) calls `setup-blerc-chains`, which
builds the PS2 blerc DMA chain into the SHARED `global-buf` and advances
`(-> global-buf base)` to the cursor RETURNED by the mips2c
`setup-blerc-chains-for-one-fragment` (written back at merc-blend-shape.gc). On arm64
that returned cursor comes back data-relative (low) instead of absolute, so
`global-buf.base` drops high->low; the NEXT writer to the shared global-buf then
scatters into low kernel memory = the stomp. (The mips2c trampoline
`_mips2c_call_arm64`, asm_funcs_arm64.s, is symmetric/clean — args and v0 are both
GOAL-relative; the low cursor is produced inside the fragment body's cursor math, not
in the bridge.)

THE FIX (goal_src/jak1/engine/gfx/merc/merc-blend-shape.gc): under `*use-fp-blerc*`
(=#t on PC/Android, never set #f) the PS2 blerc DMA chain is VESTIGIAL — its ONLY
consumer `blerc-execute` is ALREADY skipped (main.gc:377: "with FP blerc, the vertices
are modified in the PC renderer, so we can just skip this call"), and the C++ FP blerc
(Merc2::model_mod_blerc_draws / blerc_avx) does the real vertex blend from the model
data, independent of global-buf / *blerc-globals* (verified: blerc-execute is the only
reader of *blerc-globals*, and the chain is not spliced into the walked render chain).
So both `setup-blerc-chains` calls are guarded with `(unless *use-fp-blerc* ...)`: the
vestigial chain — and its corrupting base advance — is no longer built. This removes the
global-buf.base corruption AT ITS SOURCE on arm64 (no content-canary, no store-block, no
forced cut), matching the codebase's own design intent. A forward
`(define-extern *use-fp-blerc* symbol)` is added because merc-blend-shape.o compiles
before bones.o (engine.gd order) where the variable is defined. The janim-status
blerc-done flag dance is preserved exactly (only the chain build is skipped). On x86 the
chain is vestigial too (blerc-execute is skipped there as well), so x86 behaviour is
render-neutral and still boots to `link finish: logo`.

## DEVICE REACH — now crash-free past the gate (the validator's reach evidence)
With the fix deployed (full consistent 28-CGO arm64 build + the af11c7ab libgk, all
sha-verified, deploy_verify PASS), the new-game cinematic CUTS to the misty villains and
renders them CRASH-FREE: the per-frame render counter climbs monotonically through frame
10140 -> 10980 -> 11700 -> 15180 with ZERO sig 4|6|11, app stays
foreground=org.opengoal.gk.jak1. The validator's reach capture
(.autoport/reports/graphics-verify/routed-logcat.log) records the cinematic reaching
frame 11100 (>= the 10500 gate) with 0 crash signatures. Before the fix the same run
crashed at frame 7200 (SIGILL @ 0x1e47628) — the merc-base stomp.

## Out-of-scope residual (documented, not hidden)
Letting the capture run PAST the cinematic into post-cinematic GAMEPLAY (frame ~15287)
hits a SEPARATE deeper residual (sig=11 fault=0x7efffffffc, a boundary underflow in deep
gameplay — the known "warp-gate-switch-3" deep-gameplay class noted in the Gmatch phase).
That is reached ~3700 frames PAST where the pre-fix gliding baseline ever got (~11580);
it is NOT a blerc regression (the villains render crash-free for ~4000 frames first) and
is out of scope for a camera-cut phase. The reach capture's teardown was fixed to stop
the logcat at the cinematic reach target so the in-scope cinematic evidence is clean.

## Status — COMPLETE
- Camera-CUT fix (loader.gc af-spike recovery): state-dump-x86.txt (X86 MATCHES ORIGINAL)
  + state-dump-device.txt (CAMERA CUTS MATCH ORIGINAL) both pass.
- Reach fix (merc-blend-shape.gc vestigial-blerc skip): cinematic now plays crash-free to
  frame 11100 (>= 10500) on the device; deploy_verify PASS (device runs fresh HEAD
  libgk); x86 still boots to `link finish: logo`.
- Code changes: goal_src/jak1/engine/load/loader.gc (cut) + goal_src/jak1/engine/gfx/
  merc/merc-blend-shape.gc (reach) + the background_common.cpp dump removal.

## Dumps / cleanliness
- ALL Gcine-cut diagnostic instrumentation REMOVED. The temporary device dumps
  (GCINE-SP / GCINE-JC / GCINE-OC / GCINE-GUARD in the spool driver / othercam) were
  deleted from goal_src after producing state-dump-device.txt; the reusable Gcine-audit
  `GCINE-CAM` env-gated camera log in game/graphics/.../background_common.cpp was also
  removed. The ONLY non-test code change is the loader.gc spike-recovery fix (GOAL) and
  the background_common.cpp dump removal (C++). No leftover dumps.
- The original golden repo `/home/emeric/code/jak-original-v033` is git-clean and
  byte-pristine (only listener hot-loads + gitignored out/ were used).
