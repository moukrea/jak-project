# Gmenu-placement — fix summary

## The owner-reported defect
On the main menu (the `progress` menu opened on `(progress-screen title)` after the
title flythrough), the UI texture/sprite ASSETS beneath the menu text appeared
**bunched toward the screen CENTRE** instead of spread to their proper positions,
on the 2400x1080 (~20:9 ultrawide) device. A prior phase (`Gmenu-ui-placement`)
fixed only the tint-backdrop x-SCALE and was a scale-proxy that did not match what
the owner still saw; this re-do measures per-element X/Y POSITION, x86-first, with
deterministic STATE dumps and **never pixels** (the menu is a transparent overlay
over a moving island, so a background pixel diff is invalid).

## Methodology (owner-mandated: deterministic state, x86-first, no pixels)
- Built a per-element position dumper over the goalc listener
  (`.autoport/gmenu_pos_x86_dump.sh`): boot gk to the title attract, `(lt)` +
  `(build-game)`, force the 20:9 float aspect with `(set-aspect! *pc-settings* 20 9)`,
  open the menu with a REAL START press (xfocus_tap 28), and read each
  `adjust-sprites` runtime field per frame (particle `pos.x/pos.y/init-pos.x`,
  icon `icon-x/scale-x`, plus the camera/aspect factors arscale, relative-x-scale,
  x-pix, x-ratio, perspective.x, hvdf-off.x). `pos.x` is the GS offset from
  screen-centre; the sprite3_3d.vert shader maps it to `NDC.x = pos.x / 256.0`
  (a FIXED /256, no framebuffer/aspect term), so `pos.x` directly determines
  on-screen placement and "bunched toward centre" can only mean `pos.x -> 0`.
- The PRISTINE original v0.3.3 (`/home/emeric/code/jak-original-v033`, c4bc4d3ff)
  was read the SAME way and was NEVER instrumented — `.autoport/gold` stays clean.
- Device: a TEMPORARY `GMENU-DUMP` block in `progress.gc::adjust-sprites` (plain
  GOAL `(format 0 ...)` -> GK_STDOUT logcat; gated to once per 30 frames; a pure
  read-only no-op) emitted the same fields. A consistent HEAD arm64 CGO/DGO set
  was built + deployed, the menu was opened via `cpad_inject "start"`, and the
  values were harvested from logcat. Device eae4df44, native panel 2400x1080.

## Measurements @ 2400x1080 (20:9) — the decisive data
    element            our-x86(HEAD)   original-x86    device(arm64 HEAD)
    PART0 (centre) x=      0.0             0.0             0.0
    PART1 (L panel) x=  -220.0          -220.0          -220.0
    PART2 (R panel) x=  +195.0          +195.0          +195.0
    arscale            1.6666          1.6666          1.6666
- **our-x86 == original-x86**: the active-element X/Y positions are BIT-IDENTICAL
  (0.0 / -220.0 / +195.0; y +16.0). The only raw delta is ICON scale.x (0.0129 vs
  0.0170), which is purely the widescreen-toggle symbol (our run aspect4x3 vs
  original aspect16x9) feeding `adjust-ratios` — a saved-settings difference, not
  code. PART positions are symbol-independent. So the placement source is 1-to-1
  with the original; there is NO source hack.
- **device == our-x86 == original-x86**: the device reproduces those exact
  positions on fresh HEAD, with arscale 1.6666 (correct 20:9), crash-free
  (reached render frame 3000, crash_sigs=0, foreground on org.opengoal.gk.jak1).
- **Aspect behaviour**: as the aspect widens 4:3 -> 20:9 the panels move OUTWARD
  (|pos.x| grows 197->220 and 153->195) — they SPREAD toward the edges, they do
  NOT collapse toward centre. Present on x86, the original, AND the device.

## The decisive x86-at-2400x1080 question, answered
original-x86 at 2400x1080 places the elements SPREAD (-220/+195), i.e. it DOES
support the ultrawide menu layout; and the device on fresh HEAD reproduces that
exactly. Therefore this is **NEITHER an arm64 codegen regression NOR an
ultrawide-support gap** — on fresh HEAD the menu is placed correctly on the device.

## Root cause of what the owner saw: a DEPLOYMENT regression (Ghalo-class)
The element POSITIONS were always correct (device == original). The visible
"bunched toward centre" came from the device running, and `restore_knowngood`
repeatedly reverting it to, the STALE known-good backup
`.autoport/backups/device-knowngood-cgos-20260618` (June-11 CGOs). Its
GAME/ENGINE/KERNEL.CGO DIFFER from fresh HEAD: they predate both the arm64 menu
widescreen-widen fix (commit 274f79104, the `*video-parms* menu-aspect-x-scale`
precompute) and the arm64 FFI xmm float-preservation fix. On that stale build the
orange tint BACKDROP was compressed to ~0.6x (prior phase MEASURED 61440 vs the
correct 102400), so the UI box covered only the centre with the world bleeding
through the L/R edges = the reported clustering/bands. After every failing device
run the orchestrator's `restore_knowngood` put the stale build back, so the owner
kept seeing the pre-fix menu even though the fix was committed on HEAD.

## The fix (translation/deployment layer; NO goal_src change)
The placement source is already correct and 1-to-1 with the original, so no
goal_src edit is warranted (any such edit would have to be a documented pristine
revert; none is needed). The fix is purely deployment:
1. Build the CONSISTENT HEAD arm64 CGO/DGO set (which carries the already-committed
   menu widescreen-widen fix + the FFI fix) and deploy it to the device, replacing
   the stale CGOs.
2. UPDATE the device known-good backup to this HEAD set so `restore_knowngood` (run
   after every failing device run, and by the validator itself) stops reverting the
   menu to the bunched pre-fix build. This is the identical deployment-regression
   class that was fixed for the ND-logo in the Ghalo phase ("known-good backup now
   = the fixed set").

## Files
- NO goal_src changes (verified: `git diff <supervisor-anchor> HEAD -- goal_src/**`
  and `git status -- goal_src/**` are both empty).
- New tooling (translation/harness layer, not game source):
  `.autoport/gmenu_pos_x86_dump.sh`, `.autoport/gmenu_pos_device_dump.sh`.
- Device known-good backup refreshed to the HEAD consistent set; `restore_knowngood`
  repointed accordingly.
- Reports: `.autoport/reports/Gmenu-placement/menu.txt` (+ device-gmenu dumps).

## Temporary instrumentation: REMOVED
The `GMENU-DUMP` block temporarily added to `progress.gc::adjust-sprites` has been
**removed**; `git diff HEAD -- goal_src/jak1/engine/ui/progress/progress.gc` is
empty, and the whole `goal_src/**` tree is pristine (no leftover dump code). The
listener dumps read runtime fields only and added NO source to the original; the
device dump block was a pure read-only no-op and is deleted. `.autoport/gold` is
byte-pristine (`git status --porcelain .autoport/gold` is empty). The final
committed/deployed device build is the CLEAN consistent set (no instrumentation);
because the dump was a behaviourless read-only print, the clean build's placement
is identical to the measured values above.

## Verification
- our-x86 == original-x86 (bit-identical PART positions) — 1-to-1 confirmed.
- device == our-x86 == original-x86 @ 2400x1080 (spread, not bunched) — measured.
- x86 still reaches `link finish: logo`; device boots crash-free to the menu;
  `deploy_verify.sh eae4df44` PASS (device provably runs fresh HEAD libgk).
- Validator: `bash .autoport/validators/phase-Gmenu-placement.sh`.
