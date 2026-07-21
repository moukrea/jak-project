# Phase Grecharged-lightprobes — precomputed LOCAL environment probes (the "killer" ambient/IBL system)

ultrathink. Manager designs + verifies; delegate mechanical work to sub-agents. This is a BIG, multi-round
phase — write the report EARLY and fill it as you go; reserve the last third for report + device evidence.

## OWNER DIRECTIVE (2026-07-20) — READ FIRST
The current ambient (hemisphere/SH/IBL) is GLOBAL per level → interiors are wrong, no local variation. Replace
it with precomputed LOCAL environment probes baked from the STOCK game (baked light probes / irradiance
volumes + reflection probes — the AAA-standard technique). Owner calls it "un killer truc qui change la donne".

NON-NEGOTIABLE constraints (owner, verbatim intent):
- **GO ALL IN — full quality, NOT "the simplest".** "Solo, pas AAA" meant it must be **PROGRAMMATIC/automated**
  (no manual per-level work), NOT reduced scope. It's "un remake qui déchire" → build the COMPLETE system,
  done well. Ambition high; feasibility comes from automation, not from cutting corners.
- **PROVE ON VILLAGE1 FIRST** (the starting village, `village1`). Deliver the FULL system on village1. If it
  works and the owner signs off, a follow-up rolls it out to ALL other levels "d'un bloc".
- **100% PROGRAMMATIC bake** — no hand-placed probes.
- **Capture the FULL LIT environment — INCLUDE the suns** (yellow sun, green sun, sun glow "et compagnie").
  Owner (explicit, corrected): "je veux PAS les exclure les soleils, c'est justement de les exclure qui
  fausserait tout." A probe is a real HDRI of the world AS LIT — excluding the suns leaves the surrounding
  surfaces unlit → a wrong, too-dark environment, and reflections (metal/water/Precursor) would reflect a
  dead world. So the capture is the complete lit scene, suns included.
- **NOT a 1:1 reproject of the baked as the final surface colour** (that is the "redite" to avoid). The probe
  is an ENVIRONMENT INPUT (irradiance + prefiltered radiance) to the DYNAMIC runtime pipeline (reflections/IBL,
  ambient, PBR BRDF, dynamic moving shadows, per-pixel normal-mapped detail) — the value-add over flat baked
  is the dynamic relighting + reflections + material response, NOT re-displaying baked.
- **THE DESIGN CRUX = compose WITHOUT DOUBLE-COUNTING the sun.** Since the probe already contains the suns'
  contribution, the runtime must NOT naively re-add a full analytic direct-sun on top of a full-sun probe
  (energy blow-out). Design the energy-consistent composition (e.g. the probe drives reflections + the
  ambient/environment term, while the dynamic realtime layer contributes the DELTA the baked can't: moving
  shadows, dynamic actors, PBR specular highlights, per-pixel normals) — getting this right IS "faire ça bien".
- **Effective EVERYWHERE**, with grids covering **ALL explorable HEIGHT levels** ("les bonnes infos aux bons
  endroits") — every platform/ledge/floor/roof the player can reach, plus interiors.
- Bake WITHOUT enemies/allies/player/collectibles/FX, at ALL TOD keys where the baked changes, on stock (no
  recharged mods).
- Must benefit ALL consumers, each with its own adaptation: realtime ambient, PBR, reflections on metal /
  Precursor tech / water / etc.
- **Coherent Recharged Settings menu entries** — toggle local-probe ambient, reflections on/off + quality
  tier; follow the existing selector/row conventions (greyed when parent off, clean labels), **ZERO unknown-ID
  garbage**.

## GROUNDED CODE HOOKS (verified — use these, don't reinvent)
- Sun/ambient are separable in the mood (`current-sun sun-color` / `mood-lights` distinct from ambient,
  `goal_src/jak1/engine/gfx/mood/`). NOTE (corrected): do NOT zero the sun in the capture — the owner wants
  the suns INCLUDED (full lit HDRI). This separation is instead useful at RUNTIME to compose the probe env
  with the dynamic sun WITHOUT double-counting (the design crux above).
- Interiors: levels carry `inside-box` / `inside-sphere` / `meta-inside?` volumes (`level.gc`) → auto-place a
  probe at each ROOM CENTER programmatically.
- 6-face capture: offscreen FBO infra exists (`DepthCue.cpp`, `OpenGLRenderer.cpp` glGenFramebuffers,
  `m_offscreen_mode`).
- 8 TOD keys: `time-of-day-palette` + `time-of-day-interp-colors` ("group of 8 palette fade controls",
  `goal_src/jak1/engine/gfx/mood/time-of-day-h.gc`).
- Camera teleport for the bake: `OG_LEVEL_WARP` / `debug.opengoal.level.warp` already exists.
- Baked per-vertex irradiance already in the DATA (`Tfrag3Data.h PackedTimeOfDay colors`, pre-interp, 8 TOD
  slots, tfrag/tie/shrub/HFRAG) — a cheap SEED / cross-check for the diffuse SH; the owner still wants the
  gridded spherical captures as the method, but the vertex data validates them.

## BAKE (offline tool, programmatic, on a STOCK build)
1. Stock build, recharged OFF; strip all dynamic actors (enemies/allies/player/collectibles/particles) — load
   village1 geometry + baked lighting only.
2. AUTO probe placement (village1): a 3D grid over the explorable AABB — one probe layer just above EACH
   walkable collision surface (every platform/ledge/floor/roof), PLUS volume layers for tall/open spaces, PLUS
   the center of each `inside-box`/`inside-sphere`. Collision-clip: drop probes inside solid / in the void.
3. For each probe × each of the 8 TOD keys: set the TOD and render a 6-face cubemap to an offscreen FBO of the
   FULL LIT environment — INCLUDING the suns (do NOT zero the sun light-group; the captured world must be lit).
4. Process each cubemap into: (a) L2 irradiance SH (9 coeffs × RGB) for diffuse; (b) a GGX-prefiltered
   roughness-mip cubemap for reflections, mip0 kept sharp (water/polished metal/Precursor).
5. Store a per-level probe asset (new asset type), TOD-indexed: SH grid dense, cubemaps sparse + compressed;
   shipped in the recharged asset bundle. Log the probe count + storage size.

## RUNTIME consumers (each adapted)
- **Ambient**: local probe SH (trilinear grid blend + interior-room selection) + TOD interpolation → REPLACES
  the global analytic SH with a LOCAL one (analytic SH = fallback where no probe). Fixes interiors + TOD-smooth
  by construction. The dynamic suns are added on top (probe is ambient/indirect only).
- **PBR**: diffuse = probe SH irradiance; specular = prefiltered cubemap at the material roughness (real IBL).
- **Metal / Precursor tech**: prefiltered cubemap at surface roughness.
- **Water**: mip0 sharp cubemap as the reflection source (optional SSR for dynamic actors on top).
- **Color grading**: probe average tone per location/TOD.
- **Tiers (Adreno 618)**: low = SH only (cheap, big win); mid = + low-res sparse cubemaps; high = dense grid +
  sharp cubemaps.

## GOLDEN RULE + MENU
- OFF (probes off) == the current directional-ambient behaviour; the whole feature is code-gated. rt-off +
  pbr-off + probes-off == stock byte-identical.
- Add the coherent Recharged menu entries (probe ambient on/off, reflections on/off + quality) following the
  existing menu conventions; no unknown-ID garbage.

## OBJECTIVE GATES (device eae4df44, jak1 focus, no reboot; owner_verify — owner's eye is final)
1. A village1 probe asset is built PROGRAMMATICALLY (file exists, non-trivial size, TOD-indexed) with probes
   at all explorable heights + inside-box room centers (report the counts/placement, incl. an interior probe).
2. Bake captures the FULL LIT environment INCLUDING the suns (the probe is a real HDRI — a sunlit-world
   reflection/env, not a dead dark cube). Prove the composition does NOT double-count the sun (energy-
   consistent: probe env + dynamic delta, no blow-out vs the same scene without probes).
3. Runtime ambient uses the LOCAL probe SH (shader references the probe uniform/sampler); an interior A/B shows
   the interior gets its correct LOCAL ambient (different from the global sky SH) — MEASURED, not eyeballed.
4. PBR specular IBL + at least one reflection consumer (metal/Precursor/water) sample the prefiltered cubemap
   (shows the LOCAL environment, not a flat/global cube) — MEASURED A/B.
5. Coherent Recharged menu entries present, no unknown-ID; OFF==stock byte-identical (code-gated).
6. Report `RESULT: PASS` + device mp4/png + `mCurrentFocus ... jak1`, on the DEFAULT colored render (not a
   debug viz). Verification is OBJECTIVE/numeric; the visual/aesthetic call is the owner's (push to his Honor).

---
## OWNER 2026-07-21 — HDRI CAPTURES AT FULL RESOLUTION (quality, not perf)
The bake is OFFLINE — framerate is IRRELEVANT during capture. So the 6-face cubemap HDRI captures MUST be at
FULL / NATIVE resolution: **DISABLE render scaling entirely during the bake** (no dynamic render-scale, no
resolution downscale, no "weird render scaling"). Use a high cube-face resolution (e.g. 512²+ per face, or
higher) — take as long as needed per probe; quality is the only goal. The runtime render-scale / dynamic
resolution system must NOT apply to the probe capture path. Prove in the report the capture resolution used
and that render scaling was off.

---
## OWNER 2026-07-21 — SHIP THE PROBES IN THE REPO + THE APK (no manual side-load)
Owner: "Les probes, étant faites par NOUS, doivent être INCLUSES AU REPO et EMBARQUÉES DANS L'APK !"
Right now `village1.probes` (~36 MB) is a loose file the user must copy into `.../assets/fr3/`. That is not
acceptable — our own baked data is a first-party asset. Make it ship automatically:

1. **Commit the probe asset(s) to the repo** in a tracked assets location (e.g. alongside the other bundled
   fr3/level assets the android build already packages, or a dedicated `custom_assets/`/recharged asset dir
   that is checked in). `out/jak1/fr3/village1.probes` is a build OUTPUT — put the shipping copy where the
   repo + build expect first-party assets, and commit it.
2. **Bundle it into the APK** so a plain `adb install` (no separate probes push) already has it: add the
   `.probes` to the android asset packaging / LoaderActivity extraction (the same path that ships the other
   fr3 assets to `/storage/emulated/0/OpenGOAL/jak1/assets/fr3/`), so the runtime `LightProbeGrid` finds it
   with ZERO manual placement. The `.autoport/glp_build_deploy.sh` separate-push step becomes unnecessary.
3. **Keep the bake reproducible**: the bake tool (`tools/probe_bake` + ProbeBakeCore) stays — document how to
   regenerate `<level>.probes` from the stock fr3. (Committing the baked binary is fine per the owner; the
   tool is how we rebuild/rollout. If a build-time bake is cleaner than a committed 36 MB binary, that is
   acceptable too — the hard requirement is: APK-install-only, no manual side-load, asset tracked by the repo.)

GATE (added): prove a CLEAN `adb install` of the APK (WITHOUT any separate `adb push` of `.probes`) loads the
probe grid on device — i.e. the `.probes` is bundled/extracted from the APK, and `LightProbeGrid` logs
"loaded '<...>/village1.probes'" after a fresh install with no side-load. Confirm the asset is committed
(git-tracked) and that OFF==stock is preserved.

---
## OWNER PLAYTEST #1 (2026-07-21) — QUALITY REWORK (priority over packaging)
Owner tested village1 on device. "Là où ça fonctionne, ça fonctionne bien" (the concept is validated) BUT
5 real problems — fix these FIRST (packaging = secondary):

1. **Not all interiors get their probe — most are very MUTED when you enter.** Either interior detection
   misses many village1 interiors, OR the runtime selects an EXTERIOR probe inside (the trilinear grid blend
   "reaches through walls"). FIX: (a) verify interior coverage over ALL village1 interiors (not just the hut
   that was measured), (b) select the interior probe by **containment / occlusion-aware** selection, not just
   nearest-grid trilinear that bleeds exterior light through walls. Prove on SEVERAL interiors A/B, not one.

2. **Muted details/contrast.** The colour TONE is right but the probe "mute un peu les détails/contrastes".
   The low-freq SH ambient is over-lifting the shadows / washing the albedo detail. FIX: the probe is a FILL
   that must PRESERVE the sun-driven contrast and the albedo/texture detail — rebalance (lower base weight /
   don't flatten the direct-vs-shadow separation). Measure contrast preserved vs the probe-OFF build.

3. **Probe REFLECTIONS grey everything out ("tout grisaillé", owner unsure it's useful).** The reflection
   cube is applied too broadly = a flat grey specular wash on non-reflective surfaces. FIX: reflections must
   apply ONLY to genuinely reflective materials (metal / water / Precursor, via roughness/metalness), NOT as
   an ambient grey on everything. If PBR material data isn't available on a surface, DON'T add reflection
   there. Correct-or-off — a grey wash is worse than nothing.

4. **Visible CHECKERBOARD of probes on the GROUND ("un damier de probes non maîtrisé, ça se voit au sol").**
   The probe SH is evaluated PER-VERTEX on a coarse ~4 m grid → visible probe cells / interpolation facets on
   the flat ground. FIX: make the ground ambient SEAMLESS — evaluate the probe SH **per-pixel** (sample the 3D
   SH texture in the fragment shader) instead of per-vertex, and/or a finer near-ground grid, and/or smooth
   the grid. The trilinear blend between probes must show NO grid pattern. This is the most visible defect.

5. **"Je suis pas sûr qu'on l'utilise proprement."** Review the whole runtime composition (selection,
   interpolation, energy, per-pixel vs per-vertex) against the above.

OBJECTIVE GATES (added): (1) MULTIPLE village1 interiors each get correct local (non-muted) probe light,
measured A/B; (2) contrast/detail preserved vs probe-OFF (measured, not washed); (3) reflections do NOT grey
non-reflective surfaces (measured: a non-reflective wall's luma/chroma ~unchanged with reflections ON);
(4) NO checkerboard on the ground — per-pixel SH eval, measured grid-pattern absence (e.g. FFT/gradient of a
flat-ground capture shows no ~4 m periodicity). Owner's eye on his Honor is the final gate.

---
## OWNER 2026-07-21 #2 — INDUSTRY-STANDARD & CLEAN; REFLECTIONS BELONG TO PBR + WATER, NOT THE PROBE SYSTEM
Owner: "Il faut faire ça comme dans la GAMING INDUSTRY, vraiment bien, PROPRE. Pour les reflets tu connais
pas les matériaux réfléchissants, tu devrais laisser ça aux PBR et à l'eau quand on s'en occupera."

This SUPERSEDES playtest-#1 point 3. The correct architecture:
- The light-probe system does NOT apply reflections to the world by itself. It has NO material info (it does
  not know which surfaces are reflective) → applying a reflection cube broadly is exactly the "tout grisaillé"
  grey wash. **Remove the broad probe-reflection application from the world shaders.**
- The light-probe system PRODUCES the reflection cubemaps (prefiltered mips) as a **RESOURCE** and EXPOSES
  them (per-probe / nearest anchor). The APPLICATION of reflections is a CONSUMER concern:
  - **PBR materials** (the Grecharged-pbr-realtime-fusion phase) consume the probe cubemap as IBL specular,
    weighted by the material's roughness/metalness — because PBR KNOWS which surfaces are reflective.
  - **Water** (a future water phase) consumes it as the water reflection source.
- So in THIS phase: keep baking + exposing the reflection cubemaps, but the light-probe **diffuse SH ambient
  is the only thing the probe system applies to the world**. The "Probe Reflections" toggle should either be
  removed from the light-probe menu, or made a no-op resource-enable that only matters once PBR/water consume
  it — do NOT let it grey the world. Document the hand-off contract (uniform/binding) so PBR-fusion picks it up.

Overall quality bar: **do it like the gaming industry — really well, clean.** That means: seamless per-pixel
probe interpolation (no checkerboard), proper containment-based interior selection (no wall-bleed), the probe
as a physically-plausible LOCAL irradiance fill that preserves contrast/detail — not a flat wash.

---
## OWNER PLAYTEST #1b (2026-07-21) — 3 more (likely same root causes)
1. **AO FLICKERS on camera movement (regression — did NOT before).** All AO types flicker now. LIKELY the
   SAME root as the ground checkerboard: per-VERTEX probe SH on a coarse grid → as the camera moves the
   per-vertex samples jump (spatial checkerboard = temporal flicker). The per-pixel stable SH eval fix should
   kill BOTH. FIRST determine on device: does it flicker with probes OFF too (→ a shader regression from the
   probe build, fix that) or ONLY probes ON (→ the probe interaction)? Fix so AO is temporally STABLE on
   movement, both probes on and off.
2. **Green-sun / moon CAST SHADOW becomes INVISIBLE when probes are ON.** The probe ambient FILL over-lifts
   the shadowed areas and washes out the dynamic cast shadow (same root as "mutes contrast"). FIX: the probe
   fill must PRESERVE the dynamic cast shadows of BOTH suns (yellow AND green) — the shadow must stay clearly
   visible with probes ON. Measure the green-sun shadow contrast probes-ON vs the accepted directional-ambient
   build (must not vanish).
3. **RENAME "probes" in the menu** — owner: in-game they don't capture anything, they're BAKED/precomputed, so
   "probes" is misleading. Rename the USER-FACING menu label to something clear (e.g. "BAKED AMBIENT" /
   "LOCAL AMBIENT") — reflect that it's precomputed local lighting. (Internal code name can stay.) Keep it
   coherent with the Recharged menu (no unknown-ID).

GATES (added): AO temporally stable on movement (measured: frame-to-frame AO delta on a moving capture, both
probes on/off, no flicker); green-sun cast shadow still clearly visible with probes ON (measured contrast vs
the accepted build); menu label no longer says "probe" (renamed, no unknown-ID).

---
## OWNER STANDING RULE — keep the menu-tree doc in sync
Whenever you MODIFY menu entries (here: rename "probes" -> "BAKED/LOCAL AMBIENT", and change/remove the
"Probe Reflections" toggle since reflections move to PBR/water), you MUST UPDATE `.autoport/menu-tree.md`
to match (the Recharged Settings section + the removed/renamed rows), keeping the [R]/[SUPPR] legend
accurate. The menu-tree doc must always reflect the shipped menu.

---
## OWNER 2026-07-21 #3 — UNIFY: the H/SH/IBL ambient MODELS must be FED BY THE PROBE DATA (one ambient system)
Owner: "le ambient model actuel utilise une estimation un peu nulle pour H/SH/IBL; nous on a les probes —
faudrait que ça utilise ces données probées pour H/SH/IBL, et du coup on fusionne tout ça proprement."

He is right. CURRENT (wrong): Hemisphere/SH/IBL are ANALYTIC estimations (sky/mood-derived, global) and the
probe SH is a SEPARATE parallel system. TARGET (unified, industry-standard):
1. **The probe data is THE ambient data source.** The "Ambient Model" selector becomes the EVALUATION
   FIDELITY of that same probe data:
   - Hemisphere = cheapest eval of the probe SH (DC + vertical axis only),
   - SH        = full L2 probe SH per-pixel,
   - IBL       = probe SH + the probe cubemap for the ambient env term.
2. **The analytic estimation survives ONLY as the fallback** where no probe data exists (levels not yet
   baked, out-of-grid). Automatic — not a user choice.
3. **MERGE the menu rows**: no more "Directional Ambient" vs "Baked Ambient" duplication. One coherent
   AMBIENT group: on/off, Model [Hemisphere/SH/IBL] (= fidelity of the probe-fed ambient), Strength,
   Contrast. The separate "Baked Ambient" on/off + "Baked Ambient Quality" rows fold into this (quality can
   merge into Model or stay as a probe-resolution setting — pick the cleanest, document it). Update
   `.autoport/menu-tree.md` accordingly (mark folded rows [SUPPR] with history).
GATE (added): the shader's Hemisphere/SH/IBL paths read the PROBE textures as their data (probe-fed), the
analytic path is reachable only as no-probe fallback; the menu no longer has the redundant duplicated rows.

---
## OWNER 2026-07-21 #4 — the unified ambient must WORK WITH the realtime direct lighting, never fight it
Non-negotiable layering contract (the industry-standard split):
- **AMBIENT (probe-fed, indirect)** = the base/fill layer ONLY.
- **DIRECT (realtime)** stays fully alive ON TOP: the DAY SUN with its light + cast shadows, AND the GREEN
  SUN / moon with ITS light + cast shadows — both shadowing ALL objects as designed ("comme font les jeux
  actuels"). The probe fill must NEVER wash out / cancel either sun's light or shadows (the invisible
  moon-shadow bug is exactly this violation). Energy-consistent: ambient fills where direct doesn't reach;
  direct adds on top; shadows remove ONLY the direct term.
- **REVIEW the direct-lighting implementation against INDUSTRY STANDARDS** (owner ask): verify our sun +
  green-sun direct pass (N·L, BRDF, shadow mapping quality/bias/PCF, all-objects coverage incl. actors/merc,
  energy conservation vs the ambient layer) matches how current engines do a two-directional-light + probe-GI
  setup. Fix deviations found. Document the review in the report.

FUTURE ROADMAP (owner, explicitly LATER — do NOT implement now, just keep the architecture open):
- POINT LIGHTS everywhere that cast light + shadows (fires, lanterns when lit, etc.).
- ECO collectibles (green/blue/yellow/red) integrated into the realtime lighting as tinted point lights with
  their influence radius (their light tints the mood locally).
The ambient/direct layering + light-loop design must be extensible to N point lights without a rewrite.

---
## SUPERVISOR DEVICE GUARD (2026-07-21 ~15h) — REDMI BATTERY CRITICAL
The Redmi (eae4df44) is at 3% and NOT charging (weak/dead charger, owner alerted for physical fix). A dead
battery => reboot => PIN-lock => CE-storage lockout (catastrophic, see memory). Therefore:
- **Before ANY device step**: `adb -s eae4df44 shell dumpsys battery` — if level < 30, do NOT launch the
  game, captures, installs, or any battery-draining work on the device. No exceptions.
- Do ALL CODE-side work first (per-pixel/containment/unification/probe-fed H-SH-IBL, menu merge+rename,
  APK packaging of .probes, contrast preservation, AO stability, industry-standard direct review). Desktop
  builds/compiles are fine.
- If all code work is done and the device is still <30%, write an honest RESULT: WIP report explaining the
  battery blocker and exit cleanly. Do NOT burn the battery.

---
## SUPERVISOR CORRECTION (2026-07-21 ~16h) — BATTERY GUARD LIFTED (the level reading is BOGUS)
Owner: the Redmi is plugged 24/7 in debug — its battery-LEVEL indicator is unreliable garbage ("3%" is not
real); the phone WORKS. The 2h battery pause was a supervisor mistake. Therefore:
- **IGNORE the battery level entirely.** Do NOT gate any device work on `dumpsys battery` level.
- Only remaining device-health guard: if temperature ≥ 45.0C (dumpsys battery temperature ≥ 450), pause
  device load a few minutes to cool. That's it.
- The unified build (2e901a33c) is ALREADY DEPLOYED on the device (deploy_verify PASS 12:56) — do NOT
  rebuild; go STRAIGHT to the evidence captures (`bash .autoport/glp2_battery.sh` per the round-2 state
  note) and fill the report.

---
## SUPERVISOR (2026-07-21) — EVIDENCE BUDGET CAPPED AT ~20 MIN (owner: 75 min of captures = waste)
The evidence captures exist ONLY to feed OBJECTIVE numeric measures — but the full 75-min battery is bloat.
Cap the device-evidence budget at ~20 minutes TOTAL: ONE vantage per core metric, nothing more:
1. interiors: ONE A/B pair on 2 interiors (not 4) → luma numbers;
2. ground checkerboard: ONE flat-ground still → FFT/gradient periodicity number;
3. AO flicker: ONE short moving clip (≤20 s) → frame-to-frame AO delta;
4. moon shadow: ONE night still probes-ON → shadow contrast number.
Skip every other stage (TOD sweeps, multi-vantage redundancy, orbit passes). The owner judges the rest on
his Honor in minutes — that IS the final gate. Report the 4 numbers + RESULT and stop. Do not spend tokens
narrating captures.

---
## SUPERVISOR (2026-07-21) — EVIDENCE CAPTURES WERE CONTAMINATED BY STALE TEST PBR; PURGED, RE-CAPTURE
Owner spotted busted old TEST PBR materials (PavingStones on the sage hut) in the captures. Facts:
- The PROBE BAKE is clean BY CONSTRUCTION (ProbeBakeCore reads only the stock fr3 vertex data — verified,
  zero custom_assets/PNG references). No action needed there.
- BUT the Redmi still had the OLD TEST custom_assets (village1-vis-tfrag PavingStones set) and the capture
  scripts do NOT force custom-assets/PBR OFF → the evidence captures (incl. stage A interiors at the sage
  hut) were polluted. The supervisor PURGED the stale set from the device.
RULES: (1) evidence captures for the PROBE gates must run with load-custom-assets OFF and pbr-materials OFF
(vanilla + only the feature under test) — add the props/settings to the capture scripts; (2) RE-CAPTURE every
stage that included the sage hut / stale-PBR surfaces (stage A interiors at minimum — delete their stamps so
RESUME redoes them); (3) never trust a capture made before the purge.

---
## OWNER (2026-07-21) — RENDER SCALE MUST HONOR THE USER SETTINGS (real fix, not the debug prop) + ALL captures full-res
Owner (furious, rightly): "toujours le problème de la résolution pas à 100% avec un render scale FORCÉ à
100% — tu perds en qualité de fou, tes captures sont inacceptables en l'état."
1. **FIX THE REAL BUG**: the runtime dynamic-render-scale controller IGNORES the persisted user settings
   (menu Dynamic Render Scale OFF + Render Scale 100 => the game must render at TRUE 100% native, ALWAYS,
   heavy vantage or not; Dynamic ON => respect min-render-scale floor + target fps as configured). Wire the
   controller to the pc-settings values (they persist but are ignored today). The `debug.opengoal.
   renderscale.native` FBO override was a measurement workaround — after the fix the normal settings path
   must be sufficient (keep the prop as a debug tool only).
2. **ALL evidence captures at FULL native resolution** — including the WALK/moving captures (stage E ran
   "owner-realistic" dynamic RS = degraded; NO. Full res everywhere; framerate during captures is
   irrelevant). Re-capture any degraded stage.
GATE (added): report proves (a) menu-set 100%/Dynamic-OFF yields a native-res FBO in a heavy vantage
(measured FBO size or equivalent), (b) every evidence capture ran at native res.

---
## OWNER (2026-07-21) — VANILLA BASELINES MUST BE **TRULY** VANILLA (zero recharged tweaks)
Owner: "quand tu captures du vanilla, t'as des settings qui restent actifs (AO, realtime lighting, ambient,
etc.). Les passes vanilla ne doivent avoir AUCUN de nos tweaks — mode original (comme le futur toggle global)."
1. Add a **FORCE-VANILLA mode** to the capture harness: before ANY baseline/"OFF"/stock-reference capture,
   explicitly switch OFF **every** recharged feature — custom assets, PBR materials, enhanced models,
   recharged HUD, grass (all), foliage wind, AO (mode 0), realtime lighting (sun/green-sun/shadows), ambient
   (all models), probes/baked ambient + reflections — via the existing props/settings. Not just the feature
   under test.
2. **Prove it**: log a PROP/SETTINGS CHECKLIST (dump each recharged flag state) immediately before each
   vanilla capture and include it in the report — a baseline without the logged all-off checklist is invalid.
3. A/B semantics: "feature-OFF" comparisons (probe on/off) keep the rest of the configured stack; "VANILLA
   reference" comparisons force everything off. Label each capture clearly as one or the other.
4. This prefigures the queued Grecharged-master-toggle phase (its debug.opengoal.recharged prop will replace
   the per-flag checklist later).
GATE (added): vanilla baselines carry the all-off checklist proof.

---
## OWNER VERDICT (2026-07-21 soir) — REALTIME STILL MUCH WORSE THAN BAKED. FIND THE ROOT CAUSE. (REOPENED)
Owner, after testing the full quality round: "C'est toujours BEAUCOUP plus beau et riche en relief avec le
Realtime Lighting OFF. Tous les décors ont plus de profondeur, de richesse, de volume. Les probes/ambient
n'apportent pas grand chose; ambient on/off = différence minime; c'est toujours très plat. L'AO clignote
toujours, et elle BRULE ce qu'elle ombre au lieu de l'obscurcir. FAUT QUE TU TROUVES LA RAISON pourquoi on
n'arrive pas à faire aussi bien (et donc mieux) en realtime qu'en vanilla."

This is now a ROOT-CAUSE DIAGNOSTIC phase, not another patch round. Mandatory approach:

### 1. DIAGNOSE — WHY is baked richer? (measure it, don't guess)
Strong hypothesis to CONFIRM/REFUTE first: the baked per-vertex colors carry HIGH-SPATIAL-FREQUENCY lighting
detail (crevice AO, contact shadows, local bounce, artist meso-shading at ~0.1-1m scale). The realtime path
REPLACES that with albedo x (probe-SH + sun N.L) where the probe SH (4m grid, L2) is a MASSIVE LOW-PASS
filter => all meso-scale lighting detail is destroyed => flat. Prove it quantitatively: same vantage, same
TOD, capture baked vs realtime; compare LOCAL CONTRAST / gradient-energy spectra (esp. in shadowed and
mid-lit areas). If the baked render has significantly more mid/high-frequency lighting energy, the
hypothesis is confirmed and the fix is #2. Also decompose WHERE the realtime loses it: ambient term? sun
term? missing AO-in-lighting? (Render the layers separately if needed.)

### 2. FIX DIRECTION (industry-standard: keep the baked DETAIL layer, drive the LIGHTING dynamically)
Modern remasters do NOT discard baked lighting; they split it:
  baked_detail = baked_vertex_color / lowpass(baked_vertex_color)   (the TOD-stable high-freq part:
  crevice AO, contact, meso-shading — ratio ~1.0 on flat areas, <1 in crevices)
  realtime_composite = albedo x baked_detail x (probe_ambient + sun_direct) [+ dynamic shadows]
i.e. RE-INJECT the baked high-frequency detail as a modulation layer while the probes+suns drive the
overall lighting/TOD/direction. The lowpass can be computed per-vertex at load (neighbourhood average or
the probe-SH itself sampled at the vertex = the smooth version). This preserves ALL the vanilla richness
AND adds the dynamic sun/shadows on top — realtime becomes a strict SUPERSET of baked, which is the
owner's actual acceptance bar. Design carefully (energy consistency, TOD behaviour of the detail ratio, no
double-AO with SSAO); document the exact math in the report.

### 3. AO REGRESSIONS (still broken, owner)
(a) AO STILL FLICKERS on movement — the previous "fix" did not hold on his Honor. Re-diagnose for real
(temporal instability source: depth/noise/TAA-less sampling? per-frame jitter?), fix, and prove with a
frame-to-frame AO-delta metric ON A MOVING capture that actually matches his repro.
(b) AO BURNS instead of darkening: where it should occlude, it BRIGHTENS ("elle brule ce qu'elle ombre").
Likely an inverted term or wrong blend (additive instead of multiplicative) somewhere in the AO composite
with the realtime path. Find it, fix it: AO must only DARKEN (multiply <= 1), never add light.

### 4. ACCEPTANCE (the bar that matters)
Realtime ON must be AT LEAST as rich as baked at every vantage (measured local-contrast/gradient energy
realtime >= baked on matched captures) PLUS the dynamic sun/moon shadows on top. If the measured richness
is below baked anywhere visible, it is NOT done. The owner's eye on his Honor remains the final gate.

---
## OWNER CORRECTION (2026-07-21) — AO defect restated: it looks "CRAMÉ" (burnt/ugly), NOT brightened
Owner: "non ça éclaircit pas, mais c'est comme si c'était CRAMÉ, pas juste assombri — ça fait dégueulasse
(ça l'a TOUJOURS fait)." So: NOT an inverted/additive blend; NOT a regression. The AO darkening itself is
UGLY — burnt/crushed/dirty instead of a soft occlusion shadow, and it has been like that since the AO
phase. Diagnose the QUALITY of the darkening. Usual industry culprits (check each):
1. AO applied to the FINAL colour (darkening direct sunlight too) instead of attenuating ONLY the
   ambient/indirect term → dirty burnt patches in lit areas. Industry rule: AO multiplies the ambient term
   only; direct light untouched (our probe/ambient split makes this natural now).
2. Applied in GAMMA space instead of LINEAR → darkening curves crush to burnt blacks.
3. Strength/falloff too harsh → crushed blacks, halo edges; needs a gentle curve (e.g. pow/soft-knee),
   never full black.
4. Noise/banding splotches (low sample count, no blur where needed) reading as scorch marks.
Fix = soft, physically-plausible occlusion applied to the right term in the right space. Prove with an A/B
close-up of a previously "cramé" area (owner-visible), plus the term/space audit documented.

---
## SUPERVISOR (2026-07-21 soir) — DEVICE CAPTURES ARE STRICTLY SEQUENTIAL (root cause of the wedges)
Post-mortem: the previous attempt spawned 7 capture scripts IN PARALLEL as background tasks; they fought
over the single device (each force-stops the game / sets props / waits for warp), so NONE progressed —
that was the recurring "wedged capture" the supervisor kept killing. RULE: exactly ONE device
script at a time, run SEQUENTIALLY (foreground, or strictly chained); never overlap two glp_* runs. The
existing capture stamps + battery RESUME already support sequential completion. Also: acceptance captures
r_deck_van/r_night_d1/r_int2_d1/r_deck_d0/r_deck_d1 mp4s ALREADY EXIST on disk from earlier — harvest and
measure them FIRST; only re-capture what is missing or invalid.

---
## OWNER VERDICT #3 (2026-07-21 soir) — "clairement mieux" MAIS le soleil est mort + AO invisible. REOPENED.
Owner on the detail-layer build: "C'est CLAIREMENT MIEUX, mais le soleil ne caste plus d'ombre — même pas
sûr qu'il éclaire quoi que ce soit. L'AO ne fait plus l'effet cramé mais elle est toned down, quasi pas
remarquable. Cherchez sérieusement, on y est toujours pas."

DIAGNOSIS (the structural trap you fell into): to avoid double-counting (the baked ALREADY contains the
suns), you scaled the dynamic sun delta to ~nothing (the 0.20 delta) → with the baked detail now carrying
the lighting, the analytic sun became invisible and its cast shadows (which only modulate that tiny term)
vanished. You solved double-count by KILLING the dynamic layer — the exact opposite of the layering
contract (#4: both suns fully alive with visible cast shadows on all objects).

THE CORRECT ENERGY BALANCE (industry, de-lighting-by-shadowing): don't zero the sun — SHADOW THE BAKED.
The baked pixel value = ambient_part + baked_sun_part (mixed). The dynamic cast-shadow test tells you where
the sun is NOT reaching NOW:
  lit area   : keep the full baked (detail+level) [+ a modest dynamic sun boost for direction/specular]
  shadowed   : attenuate the baked TOWARD ITS AMBIENT-ONLY estimate (the probe ambient = exactly that
               estimate!) => the moving shadow VISIBLY darkens the baked-lit surface to ambient level.
  final = albedo_detail x mix(probe_ambient_level, baked_level, sun_visibility) (+ green-sun analog)
This gives REAL, OBVIOUS moving cast shadows (10-second check) with zero double-count: the sun's energy is
already in the baked for lit areas; shadows REMOVE it where blocked. The dynamic sun boost on top stays
subtle; the SHADOWS are the visible dynamic element (+ TOD sweep via the probe/baked blend).

AO: you over-corrected burnt -> invisible. Calibrate the middle: a SOFT but CLEARLY NOTICEABLE occlusion
(crevices/contacts visibly darker at normal viewing distance), ambient-term-only, linear, gentle curve.
A/B at default strength must be obvious in a corner/crevice close-up without being dirty.

ACCEPTANCE (10-second obvious checks FIRST — feedback_acceptance_obvious_first):
1. Walk under an object at noon: a cast shadow is OBVIOUSLY there and moves with TOD. Both suns.
2. Realtime ON keeps the baked richness (owner-confirmed acquired) AND the shadows from #1.
3. AO ON vs OFF: visibly different in crevices (not burnt, not invisible).
Then the numbers. Owner's Honor = final.

---
## OWNER PROTOCOL CHANGE (2026-07-21) — THE OWNER IS THE VISUAL VERIFIER, NOT US
Owner: "les règles de sortie visuelles, j'ai pas confiance. Utilisez-MOI pour la vérif visuelle."
The "10-second obvious checks" are NOT to be self-certified by the worker (nor the supervisor). New exit
protocol for every round from now on:
1. Implement + verify MECHANICALLY only: it compiles, deploys, boots to gameplay on the device without
   crash, the feature is wired (source-level greps / logs), OFF==stock intact. NO visual self-assessment,
   no capture batteries for "visual proof", no claims like "the shadow is obviously visible".
2. Write the report with RESULT: PASS once the MECHANICAL bar is met, stating explicitly: "READY FOR OWNER
   VISUAL CHECK — <one-line summary of what changed and what to look at>". List the 2-4 things the owner
   should look at (shadows under objects, AO in crevices, richness ON vs OFF) — as PLAYTEST GUIDANCE, not
   as verified claims.
3. The supervisor pushes the build to the owner's Honor; the OWNER does the visual verification; owner-ok
   (or his defect list) decides. This replaces the previous visual acceptance gates.
Keep captures ONLY where a NUMBER is genuinely needed for a regression guard (cheap, one vantage) — never
as visual proof.
