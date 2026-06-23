# Phase Gcrash-mouche — collecting a scout fly ("mouche"/buzzer) INSTANT-crashes — reproduce it for real, then fix

## The defect (owner, 2026-06-23) — UNRESOLVED (Gcrash-geyser fixed only the steps blue-lock)
Collecting a scout fly (the Precursor **`buzzer`** freed from a crate) crashes the game **instantly,
every time** — DETERMINISTIC. Gcrash-geyser fixed the steps edge-grab blue-lock but **could NOT
reproduce the buzzer collect** (the flies need platforming cpad_inject can't do; the buzzer census
stayed 0; the listener-trigger attempts didn't fire a real collect). Its static-trace suspect:
**`buzzer` pickup → `manipy` (the "fly-to-HUD" effect) → merc draw** — the merc/DMA blend-shape/envmap
stomp class ([[a38-blind-to-dma-content-canary]], [[cross-thread-stomp-repair-resume]],
[[gd3-jak-cinematic-state]]). NOTE: collecting ORBS does NOT crash (a different/`manipy` path), so the
crash is buzzer-pickup-FX-specific.

## The hard part: you MUST actually exercise the buzzer pickup FX (don't false-green on orb-collect)
The prior phase passed a too-loose gate by collecting orbs, NOT a buzzer. You must trigger the real
**buzzer pickup → manipy fly-to-HUD merc** path. Try, in order, until one reproduces the crash:
1. **Spawn a `buzzer` already in/near the pickup state** at Jak's position via the GOAL listener (find
   the buzzer's spawn/`init`/`pickup`/`touch` event handler in the decomp; `(process-spawn buzzer ...)`
   then fire its collect/`'touch`/`'pickup` event), so the manipy fly-to-HUD FX runs.
2. **Directly invoke the `manipy` fly-to-HUD spawn** (the collectible→HUD animation) for a buzzer-type
   pickup — that is the suspected crashing draw.
3. **Teleport Jak onto a live buzzer** (after breaking its crate) so proximity-collect fires; if the
   crate-break doesn't spawn the buzzer on arm64, that itself is the bug — investigate the
   crate→buzzer spawn.
4. cpad_inject navigation as a last resort.
Capture the crash deterministically: `GK-DIAG sig=(4|6|11)` / `Fatal signal`, fp-walk + 24-word LR
windows, and a **content-canary** if it's a DMA/SIMD merc stomp (mprotect is blind to it). Name the
writer + victim. x86-first: confirm it does NOT crash on x86 (so it's an arm64/GLES translation defect).

## Fix + verify
Fix the root (the buzzer-pickup `manipy` merc/DMA stomp — extend the repair-and-resume content canary,
or the Merc2 bone/base-pointer repair, to that draw). libgk/translation layer; goal_src 1-to-1; x86
unaffected. Then prove collecting a buzzer is crash-free repeatably (≥5×).

### If — after EXHAUSTIVE attempts (≥6 distinct trigger methods) — a real buzzer collect genuinely
cannot be exercised programmatically: do NOT fake it. Instead (a) fix the static-trace-named
manipy/HUD-merc path using the known merc/DMA stomp-class pattern, (b) write an explicit
**OWNER-VERIFICATION request** to `.autoport/reports/Gcrash-mouche/owner-verify.md` (the deployed
build sha + "collect a scout fly in Geyser Rock and confirm no crash"), and (c) state honestly in the
report that programmatic verification was impossible and owner-eye is required. The supervisor will
coordinate the owner test.

## Validator (`phase-Gcrash-mouche.sh`) PASS requires ONE of:
- **Verified path:** `.autoport/reports/Gcrash-mouche/runs.txt` shows a real BUZZER pickup-FX
  reproduced the crash BEFORE (sig + writer/victim, manipy/merc named) and is crash-free AFTER ≥5×,
  with `RESULT: BUZZER COLLECT CRASH-FREE (verified)`. OR
- **Owner-verify path:** `runs.txt` documents ≥6 distinct failed programmatic trigger attempts, a real
  fix to the named manipy/HUD-merc path, `owner-verify.md` present, with
  `RESULT: BUZZER FIX APPLIED — OWNER VERIFICATION REQUIRED`.
Plus: real `game/**`/`android/**` change; goal_src 1-to-1; fix-summary ≥60 lines; temp instrumentation
removed; `.autoport/gold` git-clean; x86 `link finish: logo`; `deploy_verify.sh eae4df44` PASS.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY. Keep device
awake. After any failing device run, `bash .autoport/restore_knowngood_device.sh`. NO screenshot grind.

## Max settings
`max_turns: 1600`, `max_retries: 4`.
