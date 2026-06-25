# Phase Gcrash-mouche3 — the REAL in-level scout-fly collect still crashes (Gcrash-mouche2 6/6 was a false green)

## The defect (owner verification, 2026-06-24)
On the LATEST device build (which DOES contain Gcrash-mouche2's libgk fix), collecting a scout fly
the REAL way **still crashes**. So Gcrash-mouche2's "6/6 crash-free" was a **FALSE GREEN**: its
PROGRAMMATIC trigger (listener spawn / direct pickup) exercised a DIFFERENT code path than the owner's
real in-level collect — **break the fly-CRATE → the buzzer flies out → Jak collects it** (crash is on
the COLLECT, owner-confirmed). The earlier phases could not reproduce the real path because reaching/
collecting needs platforming cpad_inject can't reliably do.

## Mandate — exercise the REAL path, or capture the OWNER's real crash (owner-in-the-loop)
Do NOT declare a fix on a programmatic shortcut again. Two acceptable routes:

### Route A — drive the REAL crate→fly→collect on-device
Break the ACTUAL Geyser-Rock fly-crate (the `crate`/`money`-crate that contains a `buzzer`) so the
buzzer spawns the same way as in real play, then have Jak collect THAT buzzer (cpad_inject navigation
+ a debug teleport ONLY to position Jak, not to bypass the pickup). Reproduce the crash on the real
path, capture it (sig + fp-walk + content canary on the manipy/pickup), name writer+victim, fix the
root, and show the REAL crate→fly→collect is crash-free + render-advancing ≥5×.

### Route B — owner-in-the-loop forensics (if Route A can't faithfully reproduce)
Build + deploy a build with **comprehensive crash forensics ARMED on the buzzer-collect path** (signal
handler dumping sig/pc/lr/fp-walk; a content canary over the manipy/render-DMA victim; the stomp
logger), write `.autoport/reports/Gcrash-mouche3/owner-capture.md` instructing the owner to **collect a
scout fly in Geyser Rock** so the crash is logged, and STOP for the supervisor to coordinate the owner
test + pull the logcat. Then analyze the REAL captured crash and fix it. The diagnosis must come from
the OWNER's real crash, not a synthetic one.

### Route C — PREFERRED: Ginput-replay demo (owner records once → infinite deterministic replay)
Use the `Ginput-replay` harness. Supervisor boots the device build with recording armed; the OWNER
plays from idle and does the REAL crate-break→buzzer→collect ONCE; the demo
`.autoport/demos/mouche-crash.inputs` is pulled from the device. Then replay it **deterministically on
arm64** (reproduces the collect-crash every time, no owner) and on **x86** (no crash); diff the
per-frame **state trace x86 vs arm64** → the first divergent frame names the bug; fix it in the
translation layer; **replay-verify** the real demo ≥5× crash-free + render-advancing with x86==arm64
trace. This is the faithful real-path repro the earlier programmatic shortcut lacked.

## Validator (`phase-Gcrash-mouche3.sh`) PASS requires ONE of:
- **Route A:** `.autoport/reports/Gcrash-mouche3/runs.txt`: the REAL crate→fly→collect reproduced the
  crash BEFORE (sig/writer/victim, on the real path — documented as the real crate-break+pickup, not a
  spawn shortcut) and is crash-free + render-advancing AFTER ≥5×. `RESULT: REAL SCOUT-FLY COLLECT CRASH-FREE (5/5)`.
- **Route B:** `owner-capture.md` present with the armed-forensics build + collect instructions, the
  real crash later captured + named, the fix applied, with `RESULT: REAL CRASH CAPTURED + FIXED — OWNER RE-VERIFY`.
Plus: real `game/**`/`android/**` change; goal_src 1-to-1; fix-summary ≥60 lines; temp instrumentation
removed; golden pristine; x86 `link finish: logo`; `deploy_verify.sh eae4df44` PASS.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. `.autoport/gold` READ-ONLY. Keep device awake. NO screenshot grind.

## Max settings
`max_turns: 1600`, `max_retries: 4`.
