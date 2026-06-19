# Phase Ghalo — kill the spurious halo/glow on the Naughty Dog logo (and title) screens

## The defect (supervisor confirmed by direct device-vs-v0.3.3 comparison, 2026-06-19)
On the device, the **Naughty Dog logo** beat shows a spurious **bright yellow/white GLOW (halo) on the RIGHT side, containing Jak+Daxter character art + a red seal** — i.e. **village1 geometry + a sun-particle glow are leaking/rendering onto the ND-logo screen**. The original (v0.3.3) ND-logo beat is the ND logo on a CLEAN BLACK background, nothing else. The owner sees this every boot and has flagged it repeatedly. The title screen shows the same halo class (sun/bloom glow it shouldn't have).

This is almost certainly a **REGRESSION of the prior Gndlogo fix on the current consistent current-source build** (the device now runs a full current-source build after Gspark-enterstate lifted the f1c-only constraint, so a fix that lived only on the old f1c set may not be present/effective now). The Gndlogo fix was: **done?-gated village display + sun-fade suppression**, landed in TIT.DGO. See memory [[project-gndlogo-state]], [[project-gsce-state]], [[project-gtitle-pixelmatch-state]].

## Mandate
1. **Reproduce + localize objectively.** Confirm via the trustworthy detector that intro-logo `halo_excess_frac` is high (it reads ~0.276 now; clean target <0.01) and the title halo is present. Find WHERE the village1 geometry + sun-particle glow get drawn during the `ndi`/ND-logo intro on the current build — is the prior done?-gated-village / sun-fade-suppression logic missing, bypassed, or built differently in the current-source TIT.DGO? Diff against what Gndlogo did.
2. **Fix the real leak.** Suppress the village/sun render during the ND-logo (and title) beats so they match the original (clean black behind the ND logo; no spurious bloom on the title). The fix is likely GOAL in TIT.DGO (done?-gated village display + sun-fade) — now shippable as a FULL consistent rebuild (Gspark lifted the CGO constraint; do NOT push a standalone CGO — [[feedback-game-cgo-rebuild-unsafe]]).
3. **X86-first:** if our x86 build ALSO shows the leak vs the original, fix it on the host first (free, no device). If only the device shows it, it's arm64/Adreno.

## Objective gate (the trustworthy detector — NOT the owner's eye)
The hardened `verify_device_graphics.sh` reports per-beat `halo_excess_frac` vs the v0.3.3 original. PASS requires the device, after your fix:
- **intro-logo `halo_excess_frac` < 0.01** (was ~0.276) — the ND-logo beat is clean black, no village/sun leak.
- **title-pressstart `halo_excess_frac` < 0.02** — no spurious title bloom.
- No regression: still boots + reaches in-game, 0 sig 11/6/4, frame ≥ 10500, foreground=org.opengoal.gk.jak1.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. Oracle repo + `.autoport/gold/` read-only. FULL consistent rebuild + `deploy_verify.sh eae4df44` PASS (device provably runs fresh HEAD). After any failing run, `bash .autoport/restore_knowngood_device.sh`. Don't regress the menu/cutscene/gameplay.

## Validator (`phase-Ghalo.sh`) PASS requires
1. Run the detector; `report.json` shows intro-logo `halo_excess_frac` < 0.01 AND title-pressstart < 0.02 vs the v0.3.3 oracle.
2. `Ghalo-fix-summary.md` (≥60 lines): where the village1/sun glow leaks onto the ND-logo/title beats on the current build, why the prior Gndlogo gating is missing/ineffective now, and the fix.
3. A real code change under `goal_src/**` or `game/**`.
4. `deploy_verify.sh eae4df44` PASS; crash-free long run (frame ≥ 10500, foreground=jak1, 0 sig 11/6/4); x86 still `link finish: logo`.

## Max settings
`max_turns: 1200`, `max_retries: 3`.
