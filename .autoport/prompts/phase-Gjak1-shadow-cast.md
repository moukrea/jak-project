# Phase Gjak1-shadow-cast — Jak casts NO shadow on Android (PORT-parity bug, longstanding)

## Owner report (2026-07-12, verbatim)
"Jak est censé cast une ombre (du moins il en cast une sur le build PC original), sur Android il ne
cast aucune ombre ! C'est assez important... c'est dommage de se passer de ça !"
=> PARITY bug, NOT a Recharged feature: the original PC build draws Jak's shadow; Android must too.
No toggle — this is stock behavior to restore. Applies to all shadow-casting actors, not just Jak.

## Engine facts (verified)
jak1 has a real shadow system: engine/gfx/shadow/shadow-cpu.gc + shadow-vu1.gc (+ shadow.gc /
shadow-*-h.gc) — a CPU-computed volume/projected shadow drawn via its own renderer/bucket, set up from
bones.gc ("Main draw function for all bone-related renderers. Will set up merc, generic and shadow").

## Diagnosis leads (project history — check in this order)
1. **Android curated renderer subset**: the Android build compiles/registers only a SUBSET of desktop
   renderers (Gwater lesson: ocean was missing; fixes need the 3-part pattern — mips2c kSet allowlist
   entry + CMakeLists TU inclusion + renderer/bucket registration w/ GLES gates). Check whether the
   Shadow/shadow-vu1 renderer TU + bucket registration exist in the Android build at all.
2. **arm64 mips2c noop**: jak2's shadow-cpu mips2c was a noop that zeroed the frame DMA cursor
   (Gjak2-visuals root cause). Check jak1's arm64 mips2c allowlist for shadow-cpu/shadow-vu1 entries —
   if kSet-noop'd, the shadow DMA chain is never built.
3. **x86-first oracle**: confirm our-x86 Linux build casts the shadow (expected yes) — then the delta is
   pure translation-layer (codegen/mips2c/renderer subset), never goal_src.

## Mandate
Fix in the TRANSLATION LAYER ONLY (arm64 codegen / mips2c allowlist / Android renderer subset / GLES) —
engine goal_src untouched, our-x86 == original-x86. Full consistent build; regen+sync CGO/DGOs if any
mips2c/codegen change (stale-asset rule).

## Verify (device eae4df44) — supervisor eyeballs
Screencap Jak standing in open ground with his blob/projected shadow VISIBLE beneath him (close-up),
+ one while jumping (shadow stays on ground under him); mCurrentFocus=jak1 on every frame; A/B vs an x86
oracle shot of the same beat; no new crashes (short soak), frame pacing unaffected (fps before/after);
deploy_verify + deploy_verify_assets PASS.

## Report (.autoport/reports/Gjak1-shadow-cast/report.txt) RESULT: JAK SHADOW <verdict>
which mechanism was missing (subset TU / bucket / mips2c noop / codegen), the fix (files), device frames
(standing + jumping) + x86 oracle A/B, fps before/after.
## Locks: ANDROID_SERIAL=eae4df44 only; engine goal_src untouched; gold READ-ONLY; force-stop after tests.
## Max: max_turns 2400, max_retries 5. device: true, owner_verify: true.
