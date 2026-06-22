# Phase Gconsolidate-deploy — make the device persistently run a fresh CONSISTENT HEAD build (fix the stale-backup deployment regression)

## Why (the root cause of most owner-visible "defects")
Across this session the sun, rays, particles, stars, and menu were all found to be **correct on
fresh HEAD** but the owner kept seeing them broken. Root cause: `restore_knowngood_device.sh`
restores `.autoport/backups/device-knowngood-cgos-20260618`, whose CGO/DGO files are the **June-11
f1c set**. libgk-resident fixes (FFI xmm, sun/particle mips2c un-noops, cinematic) survive a
restore, but **DATA-resident fixes do NOT** — e.g. the menu widescreen-widen fix lives in
**GAME.CGO** (commit 274f79104, `*video-parms* menu-aspect-x-scale`), which the June-11 CGOs
predate. So after every phase the restore reverts the device to a stale data set → the owner sees a
bunched menu (and any other data-resident regression). The f1c-only boot constraint is **LIFTED**
([[cgo-rebuild-frame-180-crash-resolved]], Gspark), and the Gmenu phase **PROVED a fresh consistent
HEAD arm64 CGO set boots crash-free** (frame 3000, menu opened). Time to make HEAD the device's
persistent state.

## Mandate — build + deploy + verify a fresh CONSISTENT HEAD set, then make it the known-good
1. **Clean full build from HEAD** (no mixing — [[device-ground-truth-no-mixing]]): the arm64
   goalc CGO/DGO set (all 28 files: GAME/ENGINE/KERNEL.CGO + the level DGOs) AND libgk.so, a single
   consistent build. Mind the gotchas: arm64 goalc on (make-group "kernel") can overwrite the x86
   KERNEL.CGO path ([[arm64-diag-overwrites-kernel-cgo]]); regen ALL 28, not just 3
   ([[stale-asset-dgos]]). Verify the set is internally consistent (sha-logged).
2. **Deploy the full consistent set** to the device (libgk via APK + all 28 CGO/DGO into
   files/iso_data/jak1 as a consistent set).
3. **Verify it BOOTS crash-free and reaches gameplay** — long run, frame ≥ 10500, **0 sig(4/6/11)/
   Fatal**, foreground=jak1. This is the consistency proof (a bad CGO set SIGILLs at boot). If it
   does NOT boot clean, **restore the June-11 backup, do NOT update known-good, and report** — never
   leave the device bricked.
4. **Verify the data-resident fixes render** on this build, deterministically (no pixels):
   menu element X/Y spread (PART0/−220/+195 @2400x1080), sun corona size (24576), particle vproc3d
   (>0), night stars. Cite the dumps.
5. **Make it the new known-good:** copy the 28-file fresh set to a NEW dated dir
   `.autoport/backups/device-knowngood-cgos-20260622/` (sha-verify consistent), **KEEP the June-11
   dir as a fallback (do NOT delete)**, and update `restore_knowngood_device.sh`'s `SRC=` to point to
   the new dir. Now restore leaves the device on fresh HEAD.
6. Leave the device running the fresh consistent set (final state = fresh, NOT June-11). goal_src
   stays 1-to-1; x86 unchanged.

## Validator (`phase-Gconsolidate-deploy.sh`) PASS requires
1. `.autoport/reports/Gconsolidate-deploy/consolidate.txt`: full 28-file consistent HEAD arm64 set
   built + deployed; device boots → gameplay frame ≥ 10500 with **0 sig(4/6/11)/Fatal**,
   foreground=jak1; menu/sun/particles render citations. With `RESULT: DEVICE RUNS FRESH CONSISTENT
   HEAD (boots, gameplay, data-fixes render)`.
2. New backup dir `.autoport/backups/device-knowngood-cgos-20260622/` with 28 CGO/DGO (sha-verified
   consistent); the June-11 dir still present (fallback); `restore_knowngood_device.sh` SRC points to
   the new dir.
3. Fix-summary `.autoport/reports/Gconsolidate-deploy-fix-summary.md` ≥60 lines; temp instrumentation
   removed; `.autoport/gold` git-clean; goal_src 1-to-1.
4. x86 still `link finish: logo`; `deploy_verify.sh eae4df44` PASS.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY/pristine.
If the fresh set fails to boot, restore June-11 + report (never brick). NO screenshot grind.

## Max settings
`max_turns: 1600`, `max_retries: 3`.
