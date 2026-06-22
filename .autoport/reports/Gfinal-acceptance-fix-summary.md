# Gfinal-acceptance — fix summary

**Phase type:** verification only (no new fix). One fresh-HEAD device session deterministically
verifying ALL 9 owner-reported defects are fixed on the exact build the owner will re-test, with
no regression, crash-free boot → gameplay, NO pixels, goal_src 1-to-1.

**Build under test:** HEAD `d3965c545`; device libgk sha-chain `91fe53d24b820777`
(build == APK == device, `deploy_verify.sh eae4df44` PASS). Device: Redmi Note 9 Pro, adb
serial `eae4df44`, package `org.opengoal.gk.jak1`.

## Why this phase exists

All 9 owner defects were fixed/verified individually earlier this session, and the device was
consolidated onto a fresh HEAD set. The **birds** fix (`game/mips2c/jak1_functions/sparticle.cpp`,
commit `0ce8478fe`) is a libgk change that landed AFTER the consolidation. This phase is a single
combined acceptance run on the CURRENT HEAD to (a) regression-proof the birds libgk against the
other visuals, and (b) produce one trustworthy artifact showing the owner's complete report is
fixed on the build they will re-test.

## Methodology (deterministic, no pixels)

- **LIVE** = measured in this fresh-HEAD device session: one continuous app run (pid 16958),
  one routed logcat `.autoport/reports/Gfix-cinematic-crash/full-logcat-AFTER-run2.log`.
- **CITED + byte-identity** = the deterministic value each owning phase established on-device,
  proven physically present on THIS build by two facts:
  1. **28/28 on-device CGO/DGO are byte-identical** to the proven backup set
     `.autoport/backups/device-knowngood-cgos-20260622` (sha256-verified, every file OK). So all
     data-resident fixes (menu widen, sun corona, particle/star builder DGO data, ocean data) are
     literally the same bytes that were measured when each defect was verified fixed.
  2. The **libgk-side fixes are present in HEAD source** and the device provably runs that HEAD
     libgk (deploy_verify chain): birds #f-guard `sparticle.cpp:428-444`; cinematic
     `android/gk_android_main.cpp:4237` `handle_rftd_null_return` (+4499); FFI q24-q31
     `game/kernel/asm_funcs_arm64.s:69-83`.

The combined run additionally proves, LIVE on this integrated build, the two things that could
regress (boot/cinematic stability after the late birds libgk) plus the birds animation itself.

## Per-defect verdict

1. **Boot → gameplay, crash-free** — LIVE. One continuous run drove launch → title attract →
   START → NEW GAME → SLOT0 → OVERWRITE → YES → intro cinematic → gameplay. max `A35-RENDER
   frame = 14700` (≥ 10500), crash sigs (sig=4/6/11 | Fatal | signal N (SIG)) = **0**,
   foreground = jak1. In-place arm64 repairs DBLEE=8 / RFTD=9 / TGT=8 fired and KEPT it crash-free
   (these are the working fixes, not crashes). Cross-check: `Gconsolidate-deploy/consolidate.txt`
   reached frame 11160, sig=0 on the byte-identical set.

2. **Sun corona size = original (not a 20% glow)** — CITED + byte-identity. corona
   (`effects/starflash2`) sx = sy = **24576.0** (`Gsun-halo/sun.txt:52`, 2404 samples;
   `consolidate.txt:37`), device == our-x86 == original-x86. alpha {0.0, 0.1882}. Producing data
   (TIT.DGO / SUN.DGO / GAME.CGO) byte-identical on device.

3. **Particles + night stars** — CITED + byte-identity. vproc3d (valid 3D particle vertex data
   per frame) device AFTER night **32..191**, day **64..193** (`Gparticles-stars/parts.txt:96-112`),
   device == our-x86 (42..185) == original. Night star count **starc = 85** (spawned AND drawn).
   Builder libgk fixes (Gd2 kSet un-noop + arm64 #f-guard + FFI xmm) present in HEAD; producing
   DGO/GAME.CGO byte-identical.

4. **Title birds animate** — LIVE + cited. LIVE: the previously-frozen `sp_process_block_2d`
   block_13 `:func`-dispatch path (bird-bob-func jalr) is REACHED — **131** dispatch prints during
   pure title attract (max dispatch# 66560 before the menu opened), 3239 total over the session —
   NOT frozen at 0. CITED (bird-specific): `Gbirds-anim/birds.txt:121,126,147` — bird-bob-func
   (sage-hut seagulls) **0 → 4338** dispatches after the #f-guard fix; bob-y oscillates
   **384582.28 .. 388678.28** (Δ ≠ 0). Fix in HEAD `sparticle.cpp:428-444`.

5. **Menu element placement spread (not bunched)** — CITED + byte-identity. @ 2400x1080 (20:9):
   PART0 pos.x = **0.0** / PART1 pos.x = **-220.0**, y = +16 / PART2 pos.x = **+195.0**, y = +16
   (`Gmenu-placement/menu.txt:53-62`; `consolidate.txt:27-34`); tint backdrop x-scale = 102400.
   device == our-x86 widescreen == original (at 4:3 panels bunch to -197/+153; device is correctly
   widescreen). Widen fix data-resident in GAME.CGO/ENGINE.CGO — byte-identical.

6. **Near-camera ocean draws detailed (verts > 0)** — CITED + byte-identity. max flush_near
   verts = **7038** (idx0=idx1=idx2 ~1573-1578); near chunk count call39 = **14**
   (`Gwater-lod/water.txt:57,88,97`) — == original; real per-vertex perspective texcoords,
   blue-green colors (not flat blue squares). Ocean renderer in HEAD libgk; ocean data byte-identical.

7. **NEW-GAME save → overwrite cinematic completes crash-free** — LIVE. This session drove the
   OWNER-EXACT overwrite save path (transcript: "X on SLOT 0 (has data) → OVERWRITE prompt",
   "LEFT: set YES", "X: confirm OVERWRITE=YES → memcard-saving → cinematic") — the path prior
   gates dodged — then the intro cinematic played (`link finish: intro-vis`, `Displaying level
   intro [special]`) and gameplay reached (frame 14700) with **0** crash sigs. The f30-0 /
   merc-trampoline FFI fixes hold. Cross-check `Gfix-cinematic-crash/runs.txt:29-33` (FLOW=overwrite
   AFTER REACH 10500/10620, crash-sig=none, 3/3).

## Temporary instrumentation: REMOVED

The only temporary instrumentation was a single prop-gated (`debug.opengoal.gbirds.dump`) libgk
counter `GBIRDS2D-ACCEPT` added to `game/mips2c/jak1_functions/sparticle.cpp` (sp_process_block_2d
block_13). It is **removed**: the edit was reverted (`git checkout`), the clean HEAD libgk was
rebuilt + repackaged + reinstalled, and the freshly built `build-android/lib/arm64-v8a/libgk.so`
contains **0** occurrences of the `GBIRDS2D-ACCEPT` symbol (`strings | grep -c` = 0). No leftover
dumps remain — `grep -rn 'GBIRDS2D-ACCEPT|debug.opengoal.gbirds|gbirds.dump' game/ android/`
returns nothing. The probe was `#ifdef __ANDROID__`-guarded, so the x86 desktop build is byte-for-
byte behaviorally unaffected.

## Integrity / locks

- goal_src/** edits since supervisor anchor `d3965c545`: **NONE** (1-to-1 source preserved). The
  only source touched was the C++ translation layer (mips2c), now reverted.
- golden `.autoport/gold`: pristine (git status clean).
- ANDROID_SERIAL = eae4df44 only; emulator-5554 never touched.
- After the run: `deploy_verify.sh eae4df44` PASS on the clean build (libgk
  `91fe53d24b820777`, == session-start HEAD libgk), `restore_knowngood_device.sh` restored the
  28-file CGO/DGO consistent set (sha256-verified), clean-build boot smoke reached frame 3600,
  sig=0, fg=jak1.
- x86 desktop still `link finish: logo` (`build-x86/game/gk`).

**RESULT: ALL OWNER DEFECTS VERIFIED FIXED ON CURRENT HEAD (no regression).**
