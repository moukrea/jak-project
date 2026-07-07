# Phase Gjak1-icache-flush — port arm64 bug class #14 fix to JAK 1 (kill the ~1-in-6 boot-flake)

## Why
Gjak2-render found arm64 bug class #14 (commit a157ae909): CacheFlush after linking GOAL code was a
no-op (size=0), so the icache served stale instruction streams — intermittent, device-only, random-
object crashes. **jak1 has the SAME vestigial no-op flush at game/kernel/jak1/klink.cpp:623** and a
long-unexplained "~1-in-6 link-time boot-flake" (F1e) that matches this fingerprint exactly.

## Mandate
Port the exact jak2 fix pattern to jak1's klink: real-range CacheFlush (__builtin___clear_cache) over
the linked segments (v2/v3 as applicable) after write, before execute. arm64-only effect (x86
CacheFlush is a no-op -> x86 byte-identical). Engine goal_src untouched. Then prove the flake dies:
run N>=20 cold boot cycles on device eae4df44 (the flake was ~1-in-6, so 20 clean boots = strong
signal; report the before-rate if reproducible on HEAD^ for an A/B).

## Verify (device eae4df44)
>=20/20 cold boots reach the title/link-finish without the link-time flake; x86 boots (link finish:
logo); jak1 gameplay smoke intact (deploy_verify PASS, full consistent build).

## Report (.autoport/reports/Gjak1-icache-flush/report.txt) `RESULT: JAK1 ICACHE FLUSH <boots>/20`
## Locks: ANDROID_SERIAL=eae4df44 only; engine goal_src untouched; gold READ-ONLY.
## Max: max_turns 1200, max_retries 4. device: true, owner_verify: false.
