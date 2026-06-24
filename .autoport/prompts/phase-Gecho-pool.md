# Phase Gecho-pool — the black dark-eco pool isn't rendered in the intro cinematic (Daxter's animal form shows through)

## The defect (owner, 2026-06-23)
In the NEW-GAME intro cinematic, the **black dark-eco pool** that Daxter falls into (in human form)
is **not rendered** — so we **see his animal form (ottsel) waiting inside** for its sequence, when the
black eco should be HIDING it. "the sole issue of the cinematic." Cinematic otherwise flawless.

## Methodology — x86-first, find the unrendered black-eco-pool effect (deterministic, no pixels-as-gate)
1. x86-first: on desktop x86 the dark-eco pool renders (black liquid/surface) and occludes Daxter's
   ottsel. Identify the GOAL element + renderer that draws it — the dark-eco pool surface (a
   `darkeco`/`dark-eco`/`eco-pool`/`liquid` part-tracker, a `shrubbery`/`tfrag`/special-surface draw,
   or a sprite/particle/`generic` effect specific to the geyser/training intro). Note its draw
   bucket / renderer / texture.
2. On device: is that draw SUBMITTED and rendered, or skipped/noop'd/transparent on arm64/GLES?
   Likely the same renderer-family pattern as ocean/sun/orb (a mips2c builder noop'd in the arm64
   allowlist, a renderer TU not compiled into the Android subset, or a GLES blend/primitive gate).
   Dump the pool draw's presence (tris/verts submitted, bucket active) on device vs x86.
3. Fix the root so the black-eco pool renders on device and occludes the ottsel. Translation layer
   (`game/graphics/**` renderer + `game/mips2c/**` builder + CMakeLists TU + bucket/GLES gate, per the
   renderer-family 3-part pattern); goal_src 1-to-1; x86 unaffected.

## Validator (`phase-Gecho-pool.sh`) PASS requires
1. `.autoport/reports/Gecho-pool/pool.txt`: device dump showing the dark-eco-pool draw now renders
   (bucket active, tris/verts > 0) where it was absent/0 BEFORE, x86-first (device == x86's pool draw).
   With `RESULT: DARK-ECO POOL RENDERS IN CINEMATIC (device occludes the ottsel)`. Name the cause.
2. Real code change; goal_src 1-to-1; fix-summary >=60 lines; temp instrumentation removed; golden
   pristine; x86 `link finish: logo`; device boots + cinematic plays crash-free; `deploy_verify.sh
   eae4df44` PASS. Owner eye = final.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY. Keep device
awake. After any failing device run, `bash .autoport/restore_knowngood_device.sh`. NO screenshot grind.

## Max settings
`max_turns: 1500`, `max_retries: 3`.
