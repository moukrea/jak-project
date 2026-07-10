## WORK ECONOMY (manager/worker delegation)
You are the MANAGER (fable/opus per profile): plan, decide, VERIFY subagent claims yourself (look at
the frames!). Delegate to autoport-researcher (tfrag/level-data/texture-id scans), autoport-implementer
(edits to your exact spec), autoport-tester (builds/device runs/screencaps/screenrecords). Parallelize.

# Phase Grecharged-grass-poc — REAL 3D GRASS proof-of-concept on the TRAINING level (jak1)

## Vision ("Jak and Daxter: The Recharged Jak-pot" — owner 2026-07-07)
Put real 3D grass ON TOP of the ground wherever the ground TEXTURE is grass — a modern-visuals
"coup de jeune". PoC scoped to the TRAINING level (Geyser Rock) ONLY; if it looks good, a later
phase transposes it to every level with grass ground textures (the reference set:
recharged_assets/grass_reference/ — training uses tra-grass as the main grass ground, plus
bch-grassfringe / bch-leafyground-hang-2x1 fringes).

## Placement — driven by the GROUND TEXTURE (programmatic, no hand-authoring)
Detect, in the training level's tfrag/level data, the walkable ground surfaces whose texture is the
grass ground (tra-grass; include the leafyground/fringe surfaces if sensible). Distribute grass
instances RANDOMLY (deterministic seed, e.g. hash of position, so it's stable frame-to-frame) on
those triangles, density tunable. Respect the surface (position on the actual triangle plane).

## The 3-tier LOD look (owner spec — capture EXACTLY this)
1. **NEAR — individual 3D blades:**
   - FLAT COLOR (NO texture for now — this is the test; grass-green with per-blade TINT variation).
   - Each blade: variable SIZE, variable ORIENTATION (yaw), variable CURVATURE (bent blade, not a
     straight quad — e.g. 2-3 segment strip or curved in the vertex shader).
   - Per-blade subtle idle MOTION as if touched by a breeze (individual phase offsets — not the whole
     field moving in lockstep; shader time + per-instance random phase).
   - **Trample effect: blades FLATTEN where Jak walks** (bend away/down around Jak's position — feed
     Jak's world pos (and ideally recent path) as uniform(s); radial flatten with recovery is ideal,
     instant flatten acceptable for the PoC).
2. **MID — grass CARDS:** crossed flat quads (X-cross), same visual aspect (same greens/heights so
   the transition reads seamless), swaying VERY slightly in the wind (gentler than near-blades).
3. **FAR — nothing added:** just the original ground texture. Smooth-ish LOD transitions (distance
   bands, ideally a small fade/dither, no hard pop if feasible).
The illusion to sell: a real lawn up close, believable filler at mid range, original game far away.

## Gating + scope (Recharged architecture rule)
- Toggle in Graphics Options > "Recharged Settings" (the submenu Grecharged-hud-jak1 creates — if
  that phase hasn't run yet, create the submenu here with the same spec: before "Advanced settings"):
  row "RECHARGED GRASS" ON/OFF, persisted, **default ON** (OWNER OVERRIDE 2026-07-10: "Ça sera
  default ON l'herbe hein!" — grass ON out of the box; deliberate exception to the usual Recharged
  default-OFF rule). The toggle STILL EXISTS and **OFF must be byte-identical stock rendering** (a
  purist can turn it off and get the original). Only the DEFAULT flips to ON.
- Training level only for the PoC (hard-scope the placement to the training level's data).
- Renderer-side implementation (C++/GLES + GLSL instancing; both x86-GL and Android-GLES if
  reasonable — Android/device is the one the owner judges). Engine goal_src UNTOUCHED (all hooks in
  renderer/pc layer). Kill-switch prop. PERF: keep it playable on the Redmi (Adreno 618) — instanced
  draws, tunable density/dist-bands; report the fps cost.

## Verify (device eae4df44) — visual + honest
- Screenrecord ON-device at the training level: near blades (size/orientation/curve/tint variation
  visible), breeze idle motion visible, TRAMPLE visible when walking through grass, mid-range cards
  swaying, far = texture only. mCurrentFocus=jak1. Capture stills of each tier + a walkthrough video.
- Toggle OFF: stock render (A/B screencap identical to pre-phase build).
- fps ON vs OFF on device (report the cost; tune density to stay playable).
- x86 build still boots (link finish: logo); full CONSISTENT build; deploy_verify PASS.

## Report (`.autoport/reports/Grecharged-grass-poc/report.txt`) `RESULT: RECHARGED GRASS POC <verdict>`
placement mechanism (how grass-textured ground is detected), instance/LOD architecture, the blade
look parameters, breeze + trample implementation, fps cost, screencap/video paths, OFF==stock proof.
Honest partial OK (e.g. trample simplified) — say exactly what's in and what's deferred.

## Locks: ANDROID_SERIAL=eae4df44 only; OFF path == stock; engine goal_src untouched; .autoport/gold
READ-ONLY; full CONSISTENT builds; verify mCurrentFocus=jak1 before trusting frames.
## Max: max_turns 3000, max_retries 6. device: true, owner_verify: true.

## DEVICE HYGIENE (owner 2026-07-10, MANDATORY)
ALWAYS force-stop the game (`adb -s eae4df44 shell am force-stop org.opengoal.gk.jak1`) the
moment a device test window ends. A left-running app overheats the Redmi for hours -> can
reboot it -> PIN lockout -> pipeline stranded until the owner is physically there. Never leave
the app foregrounded after a capture/verify.
