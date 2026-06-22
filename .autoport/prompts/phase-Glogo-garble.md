# Phase Glogo-garble — the logo-smash renders GARBLED — fix the GND-OOB-WRITE corrupting the logo geometry

## The defect (owner, 2026-06-22, OWNER-CONFIRMED appearance)
The Jak&Daxter logo-smash (breaking the black screen) is **GARBLED/CORRUPTED** — the logo mesh/
textures look scrambled during/after the smash. It is NOT frozen or missing (the sequence runs and
geometry renders — which is exactly why the prior `Glogo-smash` phase FALSE-GREENED on "tris render
+ state matches": tri count and state are blind to visual corruption).

## The smoking gun (already found)
`Glogo-smash` measured a **`GND-OOB-WRITE` firing ~400×** during the logo intro on the device. An
out-of-bounds write during the logo render is the almost-certain cause of the garbled mesh: it
stomps the logo's vertex/mesh/DMA buffer. This is the merc/sparticle/blend-shape arm64 stomp family
([[a38-blind-to-dma-content-canary]], [[gnd-state]], [[arm64-mips2c-fnull-guard]]).

## Methodology — characterize the OOB writer, fix at source, verify deterministically (no pixels)
1. **Characterize the `GND-OOB-WRITE`**: which function/builder writes out of bounds, the target
   address, and WHAT it corrupts (confirm it lands on the logo's vertex/mesh/DMA data, not harmless
   slack). Use the existing GND-OOB-WRITE telemetry + fp-walk/return-address chain
   ([[a34-crash-forensics-loop]]); if it's a DMA/SIMD store the mprotect tripwire is blind to, use a
   content canary ([[a38-blind-to-dma-content-canary]]).
2. **x86-first**: confirm the OOB write does NOT occur on original-x86/our-x86 (it's arm64-specific —
   e.g. an arm64 mips2c builder computing a wrong index/base, an #f-guard misfire writing past the
   buffer, or a base-pointer going data-relative). goal_src stays 1-to-1.
3. **Fix at the source** in the translation layer (`game/mips2c/**` / `game/graphics/**` /
   `android/**`): stop the out-of-bounds write so the logo geometry is intact. Prefer fixing the bad
   index/base computation; a content-canary repair is the fallback if the writer is unfixable.
4. **Verify**: `GND-OOB-WRITE` count during the logo intro goes **400 → 0** on device, AND the logo
   geometry is intact (the vertex/mesh data that was being stomped now matches the expected/clean
   values, x86-first). Owner eye is the final confirmation.

## Validator (`phase-Glogo-garble.sh`) PASS requires
1. `.autoport/reports/Glogo-garble/garble.txt`: the `GND-OOB-WRITE` writer + target + corrupted-data
   characterized; a calibrated BEFORE (device GND-OOB-WRITE ≈ 400 / logo data stomped) → AFTER
   (device GND-OOB-WRITE = 0 / logo geometry intact == x86). With `RESULT: LOGO GEOMETRY INTACT — OOB
   WRITE ELIMINATED (device)`. our-x86 == original-x86.
2. Real translation-layer code change (`game/**`/`android/**`); any `goal_src/**` edit must be a
   documented pristine revert. Fix-summary `.autoport/reports/Glogo-garble-fix-summary.md` ≥60 lines
   naming the writer + fix; temp instrumentation removed; `.autoport/gold` git-clean.
3. x86 still `link finish: logo`; device boots crash-free to title; `deploy_verify.sh eae4df44` PASS;
   if a TIT.DGO/CGO data fix is needed, the consolidated known-good backup is refreshed.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY/pristine.
After any failing device run, `bash .autoport/restore_knowngood_device.sh`. NO screenshot grind.

## Max settings
`max_turns: 1500`, `max_retries: 4`.
