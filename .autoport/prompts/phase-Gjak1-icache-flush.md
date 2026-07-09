# Phase Gjak1-icache-flush — port arm64 bug class #14 fix to JAK 1 (latent correctness fix)

## OWNER CORRECTION (2026-07-09) — no boot-flake, but DO the fix
Owner (verbatim, French): "J'ai pas de boot-flake perso, quand je lance ça se lance, tu
m'invente un problème là, donc pas besoin de valider avec 20 boots consécutifs. (mais par
contre le fix est à faire quand même hein !)"
=> There is NO reproducible boot-flake. Do NOT gate on 20 consecutive boots and do NOT
frame this as fixing a flake. This is a LATENT-CORRECTNESS fix worth doing on its own merit:
the vestigial no-op icache flush is a real bug (stale instruction streams are possible even
if the owner hasn't hit them). Land the fix + prove no regression.

## Why
Gjak2-render found arm64 bug class #14 (commit a157ae909): CacheFlush after linking GOAL
code was a no-op (size=0), so the icache could serve stale instruction streams — device-only.
**jak1 has the SAME vestigial no-op flush at game/kernel/jak1/klink.cpp:623.**

## Mandate
Port the exact jak2 fix pattern to jak1's klink: real-range CacheFlush
(__builtin___clear_cache) over the linked segments (v2/v3 as applicable) after write, before
execute. arm64-only effect (x86 CacheFlush is a no-op -> x86 byte-identical). Engine
goal_src untouched.

## Verify (device eae4df44)
The fix is implemented correctly (real range, not size=0); the game boots + a short gameplay
smoke is intact (NO regression); x86 boots (link finish: logo) byte-identical on the OFF/x86
path; full consistent build; deploy_verify PASS + deploy_verify_assets PASS (arm64 CGOs).
NO 20-boot requirement.

## Report (.autoport/reports/Gjak1-icache-flush/report.txt) `RESULT: JAK1 ICACHE FLUSH <landed+no-regression>`
## Locks: ANDROID_SERIAL=eae4df44 only; engine goal_src untouched; gold READ-ONLY.
## Max: max_turns 1200, max_retries 4. device: true, owner_verify: false.
