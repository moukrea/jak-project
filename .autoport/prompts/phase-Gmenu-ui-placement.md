# Phase Gmenu-ui-placement — fix the garbled menu, verified by DETERMINISTIC STATE DUMPS, x86-FIRST. No screenshot pixel-diffs.

## Methodology (owner directive 2026-06-19 — this is NOT optional; see memory state-dumps-x86-first-not-screenshots)
Do NOT verify this with screenshot pixel-diffs — frames aren't at the same instant, the numbers are noise, and they false-green. Verify with DETERMINISTIC STATE DUMPS compared NUMERICALLY, and compare our-x86 vs the unaltered original-x86 FIRST.

1. **Dump the menu UI state, don't eyeball it.** Instrument the menu render to dump (to stdout/log, behind an env flag): the on-screen position + scale/matrix of each menu element — the text list items, the **ornamental ring sprite** (its matrix/scale), the **eco-orb**, and the **menu 3D-background camera projection** (the same projection-row dump style as the Gcine-audit camera tooling). These numbers are the ground truth, not pixels.
2. **x86-FIRST. Run BOTH and diff the dumps numerically:**
   - OUR x86: `build-x86/game/gk` (current source) → reach the menu → capture the state dump.
   - ORIGINAL x86: `/home/emeric/code/jak-original-v033` (c4bc4d3ff, READ-ONLY golden) → reach the menu → capture the same dump. (You may add the SAME dump instrumentation to a TEMPORARY copy of the original to capture it, but you MUST remove it / never commit it — the golden reference stays pristine.)
   - **Diff the two dumps.** If our-x86 already diverges from the original (ring scale wrong, element positions wrong, background projection wrong) → it's an OUR-CODE bug, fix it ON x86 and re-diff until our-x86 == original-x86. (Your earlier device probe found `ratio ≈ -1.9996` = a 2× scale on the ring; check whether that 2× is already present on our-x86 vs the original.) An ARM-compat change must NEVER alter x86 — if it did, that's the bug.
3. **Only then the device.** Once our-x86 state == original-x86 state, dump the same state on the **device** (arm64) and diff vs the original. The residual is the genuine arm64 delta — fix that.
4. **Remove ALL dump instrumentation when done** (from our build AND any temp original copy). Dumps are temporary.

## The defect (for orientation — but TRUST THE DUMPS, not this)
On the device the menu shows: the ornamental ring sprite ~2× oversized and shoved to center (original: a thin ring on the right edge), and the 3D background mis-projected into vertical bands (ocean left / village center / village+Lurker right) instead of the framed village. The text items are roughly placed. So suspect the 2D-HUD/sprite SCALE + the menu background-camera projection (the arm64 HUD/camera-projection class, cf. Gcine-camfov's 5/3 aspect bug) — NOT 2D-text-list layout or the aspect enum. But confirm with the dumps.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. Original repo + `.autoport/gold/` READ-ONLY and must stay pristine (remove any temp dump you add). Engine/boot-CGO change → FULL consistent rebuild + `deploy_verify.sh eae4df44` PASS. After any failing run, `bash .autoport/restore_knowngood_device.sh`. Don't regress the halo (Ghalo) / cutscene / gameplay.

## Validator (`phase-Gmenu-ui-placement.sh`) PASS requires
1. `.autoport/reports/Gmenu-ui/state-dump-x86.txt`: the our-x86 vs original-x86 menu STATE diff (ring scale, element positions, background projection rows), showing our-x86 == original-x86 within tolerance (scale ratios ≈ 1.0), with a `RESULT: X86 MATCHES ORIGINAL` line. (If the bug was x86-level, this proves you fixed it on the host.)
2. `.autoport/reports/Gmenu-ui/state-dump-device.txt`: the device-vs-original menu STATE diff, showing the device ring scale ≈ 1.0 and background projection rows matching the original within ~5%, with `RESULT: MENU STATE MATCHES ORIGINAL`.
3. `Gmenu-ui-placement-fix-summary.md` (≥60 lines): the dumped numbers (before/after, x86 + device), where the divergence was (x86-level vs arm64), and the fix.
4. A real code change under `goal_src/**` or `game/**`; NO leftover dump instrumentation committed (the fix-summary must state dumps were removed); x86 still `link finish: logo`; `deploy_verify.sh eae4df44` PASS; no crash (sig 4|6|11), reaches gameplay.

## Max settings
`max_turns: 1500`, `max_retries: 3`.
