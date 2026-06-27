# Gledge-glitch — investigation log (manager notes)

## Bug (owner 2026-06-27)
At ledges/borders Jak can grab or fall off, arm64 collision-RESPONSE glitches and
"PROJECTS/launches" Jak ("ça projette"). x86 fine. Surfaced after recent collision fixes.

## Regression check — DONE, NOT a fresh regression
- All 3 recent collision fixes are baked into BOTH the supervisor anchor 8255b0120 and HEAD.
  No collide/target change on the Gledge branch since the anchor (only Gdeath-crash kmachine
  stack-overflow tolerance, unrelated).
- collide_edge_grab.cpp (ef3b4f0f9): 11 `gpr_addr==s7` #f-guard conversions — ALL genuine
  symbol `==#f` checks (JALR returns declared `symbol`). SAFE. find-edge-grabs! does NOT move
  Jak (populates *edge-grab-info*, sends event; target-edge-grab :enter ZEROES transv). Not the ejector.
- collide-puss-work m9/m10 v0 low-32 truncation (b45ec8230): methods return `symbol`
  (collide-cache-h.gc:37-38), only #f-tested in probe-using-spheres. SAFE, no pointer hazard.
- FMA -ffp-contract=off (49cc24b58): covers ALL 5 jak1 collide TUs incl collide_edge_grab.
  PROVEN deployed: deploy_verify PASS, fused=0 in all 5 collide objects in device libgk.so.
  Leaf bit-identical x86==arm64 (0/60000), FMA never flips hit/miss.
- arm64 float compare (=,!=,<,<=,>,>=) NaN-correct post-A34 (fcmp + cond codes match x86). NOT it.
- fmin_s/fmax_s DO diverge (ARM propagates NaN, x86 returns op2) BUT only use on path is
  vector-reflect-flat-above! at geometry.gc:123, reached only via DEAD `cond (#f ...)` branch
  (collide-reaction-target.gc:199). Not live.

## Launch site (confirmed by source read)
`target-collision-reaction` (goal_src/jak1/engine/target/collide-reaction-target.gc:119-237), GOALC:
- :200 / :219 `(vector-reflect-flat! arg2 vel sv-84)` — reflects velocity off surface normal sv-84.
  REQUIRES a UNIT normal (geometry.gc:56 VU0 .outer.product). Non-unit/NaN/inf sv-84 => explosion.
- :220 ground branch also `(vector+! arg2 arg2 sv-84)`.
- :211-213 EDGE case: `s3-4 = cross(poly-normal, ground-poly-normal)`, normalize, scale velocity —
  this is the wall/ground EDGE slide = exactly the owner's "border" case.
- sv-84 from sv-80 = normalize(world-sphere - best-tri intersect) at :138-139.
- integrate-and-collide! loops the step up to max-iteration-count => one bad reflection re-amplifies.
- Output velocity = arg2 = control transv. Launch metric = transv magnitude.

## No FP-control-register setup found
No MXCSR flush-to-zero / FPCR FZ setup in game/android code. Default FP env both IEEE.
FTZ/denorm divergence not ruled out but no smoking gun; needs observation.

## Method (device-safe)
collide-reaction-target.gc is ENGINE CGO — UNSAFE to rebuild for device GOAL instrumentation.
=> DEVICE instrumentation must be C++-ONLY: read *target*->control fields from libgk (no CGO rebuild).
Per-tick CTRL dump via pad_replay::dump_state, replay death-crash.inputs (recorded ON device =
faithful), find the transv explosion + anomalous normal/angle. x86 oracle via listener micro-repro
or matching control-state (full x86 replay-from-boot of a device demo desyncs on load timing).

## control-info field offsets (C++ raw = deftype-4), from all-types.gc
target->control: +108 | trans:+12 transv:+60 | local-normal:+316 surface-normal:+332
poly-normal:+348 ground-poly-normal:+364 ground-touch-point:+380 | ground-impact-vel:+412
surface-angle:+416 poly-angle:+420 touch-angle:+424 coverage:+428 | status(u64):+268 prev-status:+284

## REPRO PIVOT (2026-06-27)
- Full-demo replay (death-crash.inputs) DESYNCS from boot on BOTH x86 and device: record skips
  leading boot-neutral ticks (idle-until-first-input) so record-tick-0 = owner's first title press,
  but replay applies demo-tick-0 at the FIRST cpad read (early boot) => inputs land during boot,
  game stuck in logo-loop, no gameplay. (Harness limitation, NOT Gledge scope.) CTRL trace on both
  shows frozen title state: trans=const 0xc91b2cee/0x485955ea/0x492d7604, all else 0. Instrument works.
- DECISION: use a deterministic GOALC-function differential (trampoline) — call the collision vector
  primitives + dump FP control register on both backends with FIXED inputs. No gameplay/replay/drive.
- Suspected ops (VU0/SIMD, un-audited for collision/denormal/grazing inputs): vector-reflect-flat!
  (geometry.gc:56, the launch op, needs UNIT normal), vector-cross! (edge tangent), vector-length/
  vector-normalize!, vector-flatten!, vector-dot. Plus surface-angle (collide-shape-moving-angle-set!)
  feeding the wall/ground sv-160 decision (edges sit near the wall-angle threshold => flip-prone).
- Existing deterministic infra found: OG_F1_WARP=1 (x86) / debug.opengoal.f1.warp=1 (device) warp to
  Geyser; drive hook kmachine.cpp:931 (Gcrash-mouche3); cpad_inject file (gk_android_main.cpp:6227).
  Fallback for gameplay dump if primitives are clean.

## ROOT-CAUSE LEAD (device-proven): vftoi0 float->int divergence
mips2c_private.h:1455 `vftoi0` = bare `(s32)float`. On x86 = `cvttss2si` (overflow/NaN/+Inf -> 0x80000000).
On arm64 = `FCVTZS` (saturates: +overflow/+Inf -> 0x7fffffff, NaN -> 0). Independently device-verified:
  +ovf/+Inf/>=2^31: x86=80000000 arm64=7fffffff ; NaN: x86=80000000 arm64=00000000 ; in-range + -ovf/-Inf: identical.
Used in the COLLISION path: collide_edge_grab.cpp:72,74 (triangle bbox min/max -> int for the pcgtw AABB
rejection test, DEST::xyzw incl .w), AND collide_cache/mesh/probe.cpp. NOT in the proven-identical leaf
(collide_func.cpp has no vftoi). Latent until the ef3b4f0f9 #f-guard fix ENABLED the edge-grab path.
Mechanism: a NaN/overflow bbox lane -> opposite-signed int -> triangle accepted on one backend, rejected on
the other -> different grabbable triangle -> wrong center-hold/world-vertex -> wrong snap + wrong
edge-grab-off launch (unknown-vector101 * -40960) = "ça projette".
FIX (1-to-1, arm64==x86 oracle): on arm64, vftoi0 emulates cvttss2si: `!(f>=-2^31 && f<2^31) -> 0x80000000`.
Must CONFIRM it fires live in collision (counter) before claiming it's THE projection; else it's a real-but-
latent fix + owner eye is final. NOTE: PS2 VU ftoi actually saturates like ARM, but 1-to-1 binds to x86 oracle.

## ROOT CAUSE CONFIRMED (device-measured per-lane)
vftoi0 divergence fires 74948x during a Geyser collision drive; per-lane lane=[x=15886, y=20977,
z=36493, w=1592] => 97.9% on the MEANINGFUL x/y/z geometry lanes (NOT the benign .w). Every captured
diverging input is NaN (exp=0xFF). So NaN collision coords reach vftoi0 in the spatial-hash/bbox
quantization; x86 cvttss2si(NaN)=0x80000000, arm64 FCVTZS(NaN)=0 -> different grid cell/AABB int ->
arm64 picks different collision triangles than the x86 oracle -> wrong push-out = projection.
Collision math is otherwise bit-identical (FMA off + proven primitives), so the NaN is the same on
both (or cascades only through vftoi0) => fixing vftoi0 to emulate cvttss2si makes arm64 collision == x86.
Method-16 edge-grab bbox itself showed lane=[0,0,0,0] (its inputs in-range) — the fix's collision
impact is via the collide_cache spatial-hash vftoi0, which feeds the broad-phase the edge/border
response uses. Honest caveat: direct in-game projection (edge-grab-off/-jump) NOT reached via blind
drive; owner demo replay desyncs from boot. Validated at the divergence level (vftoi0 arm64==x86,
device before/after). Owner visual = final gate (per phase).

## Hook wiring
*target* read pattern = jak1/kmachine.cpp:726-737 (intern_from_c("*target*")->value, g_ee_main_mem+off, #f-guard s7.offset).
Per-frame jak1 hook = kboot.cpp:170 (calls f1_maybe_warp_to_geyser each frame, both backends).
pad_replay tick tap = common/kmachine.cpp:272 on_cpad_read; trace via open_state_trace.
x86 arm: pad_replay::init_from_env (main.cpp:115). Android arm: gk_android_main.cpp:6244-6254 prop.
