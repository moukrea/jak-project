# Phase Grecharged-ambient-occlusion — optional screen-space AO (SSAO), gated Recharged toggle

## Owner request (2026-07-11, backlog discussion)
"Tu penses que ça serait dur d'intégrer de l'occlusion ambiante ? Ça donnerait beaucoup plus de relief
partout ! À voir si pertinent sur l'herbe, et faut faire attention aux mesh transparents qui poussent
une texture avec de l'alpha car ça pourrait donner des ombres sur des parties transparentes (le truc
auquel faire giga attention). Pareil avec un toggle dans les Recharged settings."

## Approach (screen-space AO, post-process)
Add GLES post-process AO passes (SSAO/HBAO/GTAO share the pipeline) using the EXISTING depth FBO (the renderer already renders to a depth
buffer). Reconstruct view-space position + normal from depth, compute a hemispheric occlusion factor
(kernel samples + range check), blur it (bilateral, depth-aware), and multiply it into the scene during
the final composite. HALF-RES AO buffer + blur for Adreno 618 fill-rate. Do NOT restructure the DMA->GLES
pipeline — this is an added full-screen pass.

## #1 RISK (owner-flagged, handle from the start): alpha/transparent meshes
Jak renders many "solid" things as ALPHA-CUT textures on simple meshes (foliage, fences, the recharged
grass CARDS, etc.). If these write to the AO depth, SSAO computes occlusion on the MESH silhouette, not
the visible alpha shape -> boxy shadows / halos on the transparent parts. MUST exclude alpha-blended /
alpha-tested transparent surfaces from the AO-depth (only truly OPAQUE geometry contributes to AO), or
handle alpha-tested with proper coverage. Verify explicitly on a foliage/grass-card beat: no square
shadow on transparent bits.

## Two settings (owner 2026-07-11) — TYPE selector + separate QUALITY, implement ALL variants except baked
The Adreno 618 is only the WEAK test target for perf work — the shipping game also runs on powerful
devices (owner's Snapdragon 8 Elite Gen 5) and PCs. So AO is NOT gated by the Redmi; users scale it in
settings. Two Recharged Settings rows:
  1. "Ambient Occlusion: Off / SSAO / HBAO / GTAO"  (the ALGORITHM; Off == byte-identical stock)
  2. "AO Quality: Low / Medium / High"             (shown only when AO != Off; scales resolution +
     sample count: Low=quarter-res/few samples, Medium=half-res, High=full-res/full samples)
Implement ALL THREE algorithms (SSAO, HBAO, GTAO). Do NOT implement baked AO (owner: "sauf baked").
- SSAO  — classic screen-space hemisphere-kernel AO from the depth buffer. The cheapest/baseline.
- HBAO  — horizon-based: march rays in screen-space along depth to find the horizon angle. Higher
          quality, heavier than SSAO.
- GTAO  — ground-truth AO: physically-based horizon integral (cosine-weighted visibility). Highest
          quality, heaviest — meant for strong devices/PC; may be unplayable at High on the Redmi,
          that is EXPECTED and fine (the setting exists so the user picks what their device handles).
All three share the same depth-FBO source, the same alpha-exclusion handling, the same blur+composite;
they differ only in the occlusion-estimation shader. Engine goal_src untouched (renderer/pc layer only).
Report device fps for EACH algorithm at EACH quality (SSAO/HBAO/GTAO x Low/Med/High) on the Redmi so the
owner sees the cost curve; note which combos are Redmi-playable vs strong-device-only.

## PERF PHILOSOPHY (owner 2026-07-11) — Redmi max-settings fps is NOT a gate
Report the per-combo fps as an INFORMATIONAL cost curve only. Low Redmi fps at High/GTAO is EXPECTED
and is NOT a failure — the game ships to strong devices (Snapdragon 8 Elite / PC). The only perf
requirement: a fluid experience is reachable at a LOW setting (Off/SSAO-Low). Do NOT gate on, or spend
effort optimizing, Redmi max-settings fps. Gate on VISUAL QUALITY + Off==stock + no alpha artifacts.

## Verify (device eae4df44)
AO ON shows real contact/crease darkening (screencaps: a corner/contact vs OFF); NO boxy shadows on
alpha-cut foliage/grass cards (the risk beat); OFF == stock; fps ON/OFF reported; deploy_verify +
deploy_verify_assets PASS; force-stop after tests.

## Report (.autoport/reports/Grecharged-ambient-occlusion/report.txt) RESULT: AMBIENT OCCLUSION <verdict>
the SSAO pass (depth source, half-res, blur, composite), the alpha-exclusion handling + proof, the
toggle, fps ON/OFF, device captures ON vs OFF incl. the alpha-foliage risk beat.
## Locks: ANDROID_SERIAL=eae4df44 only; engine goal_src untouched; gold READ-ONLY; force-stop after tests.
## Max: max_turns 3500, max_retries 6. device: true, owner_verify: true.

## OWNER DEVICE TEST — THREE DEFECTS (2026-07-15 11:45, verbatim, Redmi training level)
"Déjà le build sur Redmi, à Sandover rend toujours quasiment tout sans texture (tout est violet)...
j'ai été sur le niveau d'entraînement et j'ai testé tous les modes d'occlusion ambiante... ça dit
unknown ID <number> pour quasiment toutes les entrées et en plus... il n'y a aucune différence quand
c'est on ou off"
1. PURPLE at Sandover: root cause was the RECALLED round-2 enhanced overlay being re-pushed by asset
   syncs (it still lived in out/jak1/fr3/enhanced). SUPERVISOR FIXED: overlay moved out of out/jak1
   (archived .autoport/recalled/), deleted on-device, setting #f. NO worker may reintroduce enhanced/
   fr3s (feature recalled until hd-models3).
2. "unknown ID <number>" on almost every AO menu row: the new menu strings are MISSING from the text
   banks deployed on the device. Ship the TEXT entries with the build: regenerate the text banks (TXT
   in the iso set) as part of the full consistent build and deploy them (deploy_verify_assets covers
   iso files). A menu with unknown IDs is an automatic gate FAIL.
3. AO ON vs OFF: NO VISIBLE DIFFERENCE on device (owner cycled all modes at training). Required proof:
   (a) AOPERF line showing mode CHANGES when the menu row changes (the earlier log only ever showed
   mode=0 — verify the menu->settings->renderer push end-to-end on DEVICE, same class as past toggle
   bugs); (b) same-beat A/B captures where SSAO/HBAO/GTAO each produce a VISIBLE darkening difference
   vs OFF (corner/contact shadows) measurable by pixel-diff in the occluded regions AND visible to a
   human; (c) mode differences also visible between variants at High quality.
The owner tested mid-phase: after fixes, redo the full device proof and leave the device in a clean
bootable state (no mixed deploys).

## DEFECT #4 — THE AO PASS BREAKS LEVEL TEXTURING (2026-07-15 12:40, supervisor-proven)
The owner's "tout violet à Sandover" was NOT data: with the AO-WIP libgk, the title flythrough renders
the world purple (missing textures); after restoring the published (pre-AO) libgk on the SAME
stock-verified fr3 set, textures are back. The AO pass leaks GL state (texture unit binding / FBO /
sampler state) into subsequent level draws. MANDATORY:
- Fix the state leak (save/restore all GL state the AO pass touches; rebind after the pass).
- PROOF before ANY device redeploy: boot to the title flythrough and verify the world is TEXTURED with
  AO compiled in (all modes, including OFF). A purple/magenta world = automatic FAIL, do not proceed.
- The device currently runs the published clean build + stock-verified fr3 set; leave it that way
  unless your build passes the textured-title check.

## OWNER DATAPOINT on defect #4 (2026-07-15 12:50, verbatim): "C'est pas violet sur le build x86, le
problème n'est visible que sur le Redmi, je pense que c'est un problème d'assets ou un truc du style"
=> Asset FILES are excluded by the supervisor A/B (same stock-verified fr3 set on device; swapping ONLY
libgk toggles the purple). Combined with the owner's x86-clean datapoint: the breakage is GLES/ANDROID-
SPECIFIC in the AO pass — desktop GL tolerates what Adreno GLES does not. Prime suspects (known classes
here): FBO attachment formats/completeness on GLES, texture-unit/sampler state not restored after the AO
pass, glActiveTexture leakage, depth-texture sampling setup, mediump. Debug ON DEVICE (the x86 render
proves nothing for this bug); the textured-title gate runs ON DEVICE before any redeploy.

## OWNER CAPTURE PROTOCOL (2026-07-15 13:50, verbatim — applies to EVERY device capture in this phase)
"Le rendu sur le Redmi est en ultra basse résolution... va sur un niveau genre le niveau d'entraînement,
bloque en pleine résolution et désactive l'herbe pour gagner un peu de perf, ça t'évitera de faire des
screens sur de la résolution pourrie !"
=> For ALL AO evidence captures on the Redmi:
1. LOCK FULL render resolution: disable dynamic render scale / force scale 1.0 in pc-settings (the PC
   options system rows exist — find the keys, set them for the run; restore after).
2. DISABLE recharged-grass? (#f) during AO capture runs to reclaim the perf headroom that keeps the
   resolution up (restore #t after the phase's final state).
3. Capture at the TRAINING level (owner's judging level), camera near geometry with corners/crevices
   (hut, rocks, terraces) where AO reads.
Low-res captures are NOT acceptance evidence — retake them.

## DEFECT #5 — GLOBAL DARKENING (owner 2026-07-15 14:20, verbatim + supervisor capture OWNER-VIEW-GLOBAL-DARK.png)
"Pourquoi tout est si foncé ??? On dirait que le jeu entier est occludé une fois l'occlusion ambiante
activée ! Tout est extrêmement sombre..."
Supervisor confirmed on his live view: the WHOLE scene is crushed dark (rocks near-black), not
crease-localized. The AO term saturates everywhere — classic causes: wrong depth reconstruction on GLES
(non-linearized depth -> everything "occluded"), AO multiplied over the full framebuffer including lit/
sky areas, strength/radius mistuned, or double application.
MANDATORY acceptance for the fix:
1. Ship an AO-DEBUG view (prop: render the raw AO buffer) — verify the term is ~WHITE (1.0) on open flat
   ground and sky, dark ONLY in creases/corners/contact areas. Include a debug capture in the report.
2. Quantified gate: at the training vantage, mean luminance delta ON-vs-OFF over OPEN areas <= ~5%;
   the darkening must be LOCALIZED (crease crops show it; open-field crops don't).
3. AO must modulate the AMBIENT contribution, not multiply the final lit color wholesale (no darkening
   of sky/emissive/fullbright).
Judge at full resolution per the capture protocol. The owner's screenshot is the counter-example: that
look = automatic FAIL.

## SUPERVISOR CATCH (2026-07-15 16:20): menu-proof2/* = the MIUI LAUNCHER, not the game
Your entire menu-proof2 capture series (00-title..04-recharged-row) shows the MIUI home screen — the
game was NOT foregrounded (crashed or never started) and no focus check was performed. HARD RULE
(long-standing, violated here): EVERY capture must be focus-bracketed — `dumpsys window | grep
mCurrentFocus` must show org.opengoal.gk.jak1 IMMEDIATELY BEFORE AND AFTER each screenshot, and the
values must be saved next to the frame. A capture without its focus bracket is garbage; a launcher
frame in a proof set = automatic FAIL. Also DIAGNOSE why the game wasn't up (crash during menu nav?
check the logcat for the session) before re-capturing.

## DEFECT #6 — TITLE CRASH WITH PERSISTED AO MODE (owner report + supervisor repro, 2026-07-15 16:45)
With the AO-WIP build and the owner's persisted (ambient-occlusion 3)+(ao-quality 2), boot reaches the
title flythrough, AOPERF flips to mode=3 ~7s in, fps sag 39->29, and the process DIES natively ~15-25s
later (no Java FATAL; ActivityManager "has died") — the renderscale-resize window. Your glFinish+skip-
one-frame mitigation is INCOMPLETE for GTAO. Requirements:
1. The on-device TITLE GATE now runs with EACH persisted mode (off/ssao/hbao/gtao × low/med/high seeded
   in pc-settings before boot): 2+ minutes alive at title for every combo, textured world, focus checks.
2. Use the A34 crash-forensics loop on the tombstone to NAME the faulting site (fp-walk + lr windows).
3. RESILIENCE (required): a crash must never brick boot — implement a safe-boot fallback (e.g. if the
   previous session died within N seconds of AO enable, boot with AO forced off once and log it).
4. Supervisor restored the device (published clean APK + ambient-occlusion 0). Do NOT redeploy until
   the full mode-matrix title gate passes locally on your build.

## OWNER TUNING FEEDBACK (2026-07-15 17:05, verbatim — per-mode strength calibration)
"SSAO est quasiment impossible à voir une différence avec l'AO off complet, HBAO on voit un poil plus
mais vraiment bof (du coup aucune valeur ajoutée quasiment) et GTAO on voit la diff pour de vrai"
=> Calibrate so EVERY tier earns its place, without violating defect #5 (open-area delta <= ~5%):
- SSAO must be CLEARLY visible vs OFF (raise strength/radius/sample contribution until the crease
  darkening at the training vantage is unmistakable — target a measured crease-region delta in the same
  order as GTAO's current one, softer falloff acceptable).
- HBAO must sit visibly BETWEEN SSAO and GTAO (quality and/or intensity distinguishable from both).
- GTAO = the current look is the reference ("on voit la diff pour de vrai") — don't regress it.
- Report per-mode measured crease-delta + open-delta numbers side by side, plus same-vantage crops
  OFF/SSAO/HBAO/GTAO so the progression is obvious to a human.

## OWNER TUNING #2 (2026-07-15 17:15, verbatim): "la qualité faible fait un rendu pixelisé alors qu'on
est à pleine résolution, faut flouter ! sinon c'est affreux"
=> The low-quality AO (computed at reduced internal resolution) composites UNFILTERED — blocky/pixelated
term over a full-res frame. REQUIRED (and it was in the owner's ORIGINAL spec: "demi-résolution + blur"):
a depth-aware (bilateral) blur pass on the AO term before compositing, at EVERY quality that computes
below full res (low certainly, medium if applicable). No visible pixelation/stair-stepping in the AO at
any quality — close-up crop proof per quality tier (low/med/high at the same vantage). The blur must not
bleed across depth edges (bilateral weights), or it will halo.
(Owner precision 17:18: the pixelation was observed on GTAO at low quality specifically — GTAO-low is
the reference case to fix and prove first; apply the same blur discipline to all modes' sub-full-res
qualities.)

## OWNER TUNING #3 (2026-07-15 17:25, verbatim — reinforces #1, raises the bar)
"En vrai SSAO et HBAO sont tous les deux à peine remarquables, dans la plupart des cas on a quasiment
aucune différence avec l'AO OFF complètement."
=> BOTH SSAO and HBAO are near-invisible in normal play, not just at one vantage. The calibration target
is not a marginal measured delta — it is: A PLAYER TOGGLING THE MODE MID-GAME MUST SEE THE CHANGE
IMMEDIATELY, for EVERY mode. Concretely: boost SSAO and HBAO strength/radius aggressively (their
character may differ — SSAO soft/broad, HBAO sharper — but both must be unmistakable vs OFF in a normal
gameplay view, not only in crease close-ups). Keep the defect-#5 open-area cap. Prove with mid-gameplay
same-vantage A/B for each mode (not just the training crease corner), judged at a glance.

## OWNER CORRECTION (2026-07-15 17:30, verbatim): "GTAO n'est pas la référence intouchable, il y a
peut-être des soucis avec, c'est des retours rapides que je te fais !"
=> Retract the "GTAO = untouched reference" framing. GTAO is merely the most VISIBLE so far — it already
has known issues (title crash defect #6, low-quality pixelation tuning #2) and may have more (over-
darkening, artifacts, cost). ALL modes stay open to fixes and tuning; the owner's remarks are quick
impressions, not sign-offs. Nothing in this phase is validated until his final play-test.

## DEFECT #7 — GLOBAL FLOOR + WATER DARKENING ON DEVICE (owner 2026-07-16 00:15, verbatim)
"SSAO n'est pas vraiment visible, et GTAO a tendance à assombrir les sols et l'eau au global (p'têtre
les autres aussi), ce qui est bizarre, me semblait que l'AO c'était surtout du détail, pas du shading
global"
The owner is CORRECT: AO = local crease/contact darkening; open floors ~untouched, water untouched.
1. WATER must be EXCLUDED from AO compositing entirely (it renders in the transparency path — AO must
   apply to the OPAQUE resolve only; if the composite happens after water/transparents, that is a
   bucket-ordering bug to fix, not tune).
2. GTAO grazing-angle floors STILL darken globally ON DEVICE — the x86 whiteness proof (open 68%) did
   NOT transfer. Verify the AO-term whiteness ON DEVICE (debug view capture on the Redmi at a beach/
   water vantage): open floor and sky ~white, water untouched, creases dark. Device numbers, not x86.
3. SSAO still not really visible in his quick test — tuning #3 bar stands (mid-game toggle immediately
   visible); re-verify ON DEVICE after the floor fix (a correct floor term may change perceived
   strength).
Acceptance adds a WATER vantage (Sentinel Beach shoreline) to the proof set: OFF/each-mode A/B where the
water pixels are byte-similar to OFF (delta ~0) and the floor delta stays within the open-area cap.
