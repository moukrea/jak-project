# Phase Gsun-halo — title sun is a ~20% glow instead of a small disc — find the SIZE divergence (x86-first, no pixels)

## The defect (owner, 2026-06-21)
On the title screen the sun is a **massive ~20%-of-screen light glow/halo** that fades when the
sun goes down. The owner: "it's expected to be super small and **see the SUN**, the real SUN."
So there should be a small sun DISC; instead the additive CORONA/glow dominates. Prior phases
(Ghalo, Ghalo-sun) claimed PASS but the defect persists on the owner's device — a false green.

## Re-baseline FIRST (the FFI fix may have changed this)
The just-shipped arm64 FFI xmm8-15 fix ([[arm64-ffi-xmm8-15-trampoline]]) corrected a broad GOAL-
float-across-FFI corruption. A sun size/fade float that crosses a GOAL→C++ FFI call could have
been affected. So **re-measure on current HEAD** before concluding anything.

## Methodology — DETERMINISTIC SIZE DUMPS, x86-FIRST, NEVER pixels ([[porting-1to1-fix-in-translation-layers]], [[state-dumps-x86-first-not-screenshots]])
Unlike the title rays (which were deterministically correct), the sun glow has a concrete,
dumpable metric: the **drawn size/scale of the sun disc AND the corona/glow**. Dump the
defect-relevant DATA, no pixels (owner: "you suck at visual comparison"; the title flyover is a
moving camera so pixels are invalid anyway).

1. Find the sun draw: the sun disc + the additive **corona** (`group-sun`, weather-part.gc ~:482),
   the sun-sprite scale, and the `sun-fade`/`current-interp` that gates it (title-obs ndi/sun path).
2. Dump per-frame, across a title beat with the sun up: **sun disc scale/size, corona sprite
   size/scale (and count), sun-fade / current-interp value** — on **original-x86 (.autoport/gold)**,
   **our-x86 (HEAD)**, **device**.
3. **our-x86 vs original-x86 FIRST:**
   - if our-x86 corona size DIVERGES from original-x86 → a SOURCE hack diverged our build (e.g.
     Ghalo sun-fade in title-obs.gc); the 1-to-1 fix is to **revert that hack to pristine** so
     our-x86 == original-x86. (Restoring the original is the goal — that is NOT a forbidden hack.)
   - if our-x86 == original-x86 but DEVICE corona is ~20% (bigger) → an arm64/GLES translation
     defect (a size float computed wrong on arm64, or a GLES additive-glow/point-sprite size/
     bloom difference). Fix in the translation layer (`goalc/**`, `game/graphics/**`, `android/**`).
4. The end state: **device corona size == original-x86 corona size** (small disc + small corona),
   and **our-x86 == original-x86** (1-to-1 preserved).

## Validator (`phase-Gsun-halo.sh`) PASS requires
1. `.autoport/reports/Gsun-halo/sun.txt`: per-frame sun disc + corona size/scale dumps for
   original-x86, our-x86, device — with our-x86 == original-x86 (1-to-1), a calibrated BEFORE
   where device's corona is oversized, and an AFTER where device corona size matches original.
   With `RESULT: SUN CORONA SIZE MATCHES ORIGINAL (device, 1-to-1 source)`.
2. our-x86 sun metrics == original-x86 (explicitly shown). If the fix touched `goal_src/**`, it
   must be a REVERT toward the pristine upstream (our-x86 ends == original-x86); any change that
   makes our-x86 DIVERGE from original-x86 FAILS.
3. Fix-summary `.autoport/reports/Gsun-halo-fix-summary.md` ≥60 lines (the metric, the layer, the
   fix/revert); temp instrumentation removed; `.autoport/gold` git-clean.
4. x86 still `link finish: logo`; device boots crash-free to title; `deploy_verify.sh eae4df44` PASS.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY/pristine.
After any failing device run, `bash .autoport/restore_knowngood_device.sh`. NO screenshot grind.

## Max settings
`max_turns: 1400`, `max_retries: 3`.
