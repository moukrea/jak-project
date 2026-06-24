# Phase Gorb-icon — the Precursor ORB icon renders as a white "egg" in the HUD + menu (texture not loading on arm64)

## The defect (owner, 2026-06-23)
The **Precursor orb** icon in the **HUD and the menu** is just a **plain white "egg"** — as if the
orb's texture/asset doesn't load, while every OTHER asset loads fine ("bizarre car c'est le seul").
So a SINGLE specific texture (the orb icon) is missing/white on Android; everything else is correct.

## Methodology — x86-first, find the one texture that's white on arm64 (deterministic, no pixels-as-gate)
1. x86-first: on desktop x86 the orb HUD/menu icon shows the real orb texture. Identify exactly which
   texture/sprite drives the orb count icon (the HUD `money`/orb counter, `hud-orb`/`fuel-cell`-style
   sprite, and the menu orb icon) and how it's loaded/bound (a normal texture, a
   `TextureAnimator`-driven/animated texture, or a special tpage). Note its tex-id / tpage / name.
2. On device: is that texture LOADED into the GL texture pool and BOUND when the orb icon draws, or
   is it missing → the shader samples a default/white texel = the white egg? Likely causes: the orb
   texture is part of a TextureAnimator/clut path not handled on arm64/GLES, a specific tpage not
   uploaded, a tex-id lookup that returns the wrong/zero handle, or a CLUT/format the GLES path
   skips. Dump the orb sprite's bound tex handle + the texture-pool entry on device vs x86.
3. Fix the root so the orb texture is loaded + bound for the HUD and menu icon. Translation layer
   (`game/graphics/**` texture path / `TextureAnimator` / `android/**`); goal_src 1-to-1; x86 unaffected.

## Validator (`phase-Gorb-icon.sh`) PASS requires
1. `.autoport/reports/Gorb-icon/orb.txt`: device dump showing the orb HUD/menu icon's bound texture is
   the REAL orb texture (correct tex-id/handle + non-default), with a calibrated BEFORE (device orb
   sprite bound to default/missing/white texture; tex-id 0/wrong) -> AFTER (bound to the orb texture ==
   x86's). With `RESULT: ORB ICON TEXTURE LOADS ON DEVICE (HUD + menu)`. Name the missing-texture cause.
2. Real code change; goal_src 1-to-1; fix-summary >=60 lines; temp instrumentation removed; golden
   pristine; x86 `link finish: logo`; `deploy_verify.sh eae4df44` PASS. Owner eye = final.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY. Keep device
awake. After any failing device run, `bash .autoport/restore_knowngood_device.sh`. NO screenshot grind.

## Max settings
`max_turns: 1400`, `max_retries: 3`.
