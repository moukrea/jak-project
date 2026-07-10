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

## SUPERVISOR FACT-CHECK (2026-07-10) — the report's "working on device" is a FALSE GREEN
Owner tested on the Redmi with the toggle ON and saw NOTHING beyond the stock grass texture +
stock shrubs. Supervisor verified the FACTS:
- The device libgk.so has **ZERO** grass-renderer strings (grep recharged-grass/grass-blade/
  g_grass = 0). The grass renderer is C++ in libgk; it was built LOCALLY (9 strings) but the
  device was never reinstalled with it. Only the GOAL toggle flag reached the device -> the menu
  shows "RECHARGED GRASS: OUI" but there is NO renderer to act on it. Nothing renders.
- The report's "deploy_verify + deploy_verify_assets PASS / working on device" is FALSE — the
  frames labelled device (mv_*, OFF_geyser) are either x86 or menus or the STOCK texture; do NOT
  trust green ground as proof (Geyser Rock ground is ALREADY green stock).
- The report says "Default is OFF" — WRONG, owner override is DEFAULT ON.
MANDATORY to close this phase now (validator enforces all of these):
1. DEFAULT ON (pc-settings init), toggle still present, OFF still byte-identical stock.
2. Reinstall the APK carrying the grass libgk on the device so `deploy_verify.sh eae4df44 jak1`
   PASSES and the device libgk actually contains the grass strings (validator checks both).
3. Prove grass ON the DEVICE with an OBJECTIVE OFF-vs-ON comparison: SAME in-game viewpoint
   (NOT a menu, NOT x86), grass toggle OFF vs ON, the difference must be OBVIOUS (real 3D blades
   over the ground, not the stock texture). If it does NOT visibly differ on device, the grass
   does not work — say so honestly, do not claim it does.
4. Force-stop the app when the device test ends (device-hygiene rule).

## OWNER POLISH ROUND (2026-07-10) — "impressionnant" but iterate (keep the good parts)
Owner quote (verbatim, French):
"Alors impressionnant ! Par contre j'ai l'impression que l'herbe full 3D est rendu plus près
de la caméra (c'est attendu) mais pas suffisamment loin pour que Jak soit dedans, Jak est dans
les Grass Cards qui d'ailleurs ont pas l'air (même en illusion) de faire des brins mais plutôt
des rectangles flous, qui n'ont pas l'air de varier au grès du vent (simulé comme la vraie herbe
3D) la vraie herbe 3D n'a pas assez de variation de teinte, taille et surtout n'est pas assez
dense ! Mais c'est déjà pas mal du tout. Aussi les grass cards... Ça fait des carrés chelou sans
rien au milieu des fois, et ça se corrige pas en allant venant (sorte de pop-in non maîtrisé)."

Breakdown (do NOT reinterpret) — the PoC is GOOD; polish these:
1. NEAR-BLADE LOD BAND TOO SHORT: the full 3D blades render close to camera but NOT far enough —
   JAK IS NOT STANDING IN THE 3D GRASS, he's already in the CARDS band. Push the near-blade→card
   transition distance OUT so Jak (and the ground right around him) is in real 3D blades.
2. 3D BLADES need MORE: (a) more TINT variation, (b) more SIZE variation, (c) MUCH MORE DENSITY
   (owner: "surtout pas assez dense"). Density is the #1 ask.
3. GRASS CARDS look WRONG: they read as "blurry rectangles", not grass tufts — even the illusion
   fails. Make the card texture/shape read as grass blades/tufts (alpha-cut tuft, not a flat
   rectangle), matching the near-blades' greens/height so the transition is seamless.
4. CARDS don't sway in the WIND: the near 3D grass is wind-simulated but the cards are static —
   give the cards the same (gentler) wind sway.
5. CARD POP-IN BUG: cards sometimes render as "weird empty squares with nothing in the middle",
   and it does NOT resolve by moving around = uncontrolled pop-in / broken card instancing or a
   missing-texture/alpha issue. Fix the pop-in so cards are always populated + stable.
Owner is REMOTE — when this iteration is verified (objective A/B on Redmi + I confirm), PUSH a
fresh jak1 build to moukrea/jak-builds (update the jak1-grass-poc release) for his HONOR playtest.
Keep default ON. Objective A/B still required; do NOT self-certify the look.

## OWNER CORRECTION to the pop-in item (2026-07-10)
Owner quote (verbatim, French):
"Correction sur les carrés vides, ça concerne aussi l'herbe en vraie 3D, comme si des chunks
entiers se desinstanciais en dépit du fait qu'on soit a proximité... Toujours même idée, une
sorte de culling/pop-in/lod system non maîtrisé"
=> The empty-square / de-instancing bug is SYSTEMIC, affecting BOTH the near 3D BLADES and the
cards: whole CHUNKS drop out even when we are close to them. Root-cause the culling / LOD /
chunk-instancing system (frustum or distance culling too aggressive? per-chunk instance budget
overflow/eviction? a chunk visibility/bucket bug?). The fix must keep ALL nearby grass chunks
(blades AND cards) populated + stable — no chunk disappearing while in range, no state that only
"fixes" by moving. This is the #1 correctness bug of the polish round.

## OWNER POLISH FEEDBACK #2 (2026-07-10, on the interim build) — CULLING STILL BROKEN
Owner quote (verbatim, French):
"Alors l'herbe mériterai d'être un peu plus longue. D'entrée c'est pas mal mais en bougeant on
a des zones entières qui disparaissent, sinon des zones qui chargent pas, sinon ça fait du
pop-in en bougeant... Et on a pas les grass cards à distance il semblerait"

Breakdown (do NOT reinterpret):
1. LENGTH: grass should be a bit LONGER / taller (bump blade + card height).
2. CULLING / POP-IN STILL BROKEN (this is the #1 blocker, the previous fix DID NOT resolve it):
   while MOVING, "entire zones DISAPPEAR", other "zones DON'T LOAD", and there's "pop-in when
   moving". Re-root-cause from scratch — the prior fix was wrong. Suspects: chunk visibility keyed
   to a stale camera/eye position; per-chunk instance buffers rebuilt only on a trigger that
   misses while moving; frustum/distance cull using the wrong transform; a fixed chunk pool that
   evicts in-view chunks; async chunk build that never completes for some chunks. INSTRUMENT it:
   log per-frame how many chunks are in-range vs actually drawn vs culled, while walking, and find
   why in-range chunks are not drawn. Do NOT claim fixed until a MOVING device capture shows zero
   disappearing/unloaded zones.
3. GRASS CARDS AT DISTANCE MISSING: the owner does not see the mid-range grass cards at distance
   at all — the card LOD tier isn't rendering (wrong distance band? culled by the same bug? cards
   never instanced?). Make the cards actually appear in their distance band.
Owner is REMOTE + reviewing via jak-builds pushes — keep pushing interim builds when there is a
visible change, but the CULLING must be genuinely fixed (moving capture proof) before calling it good.

## OWNER POLISH ROUND #3 (2026-07-10) — culling FIXED (owner: "beaucoup beaucoup mieux, impressionnant"), finitions
Owner quote (verbatim, French):
"Ça marche beaucoup, beaucoup mieux ! Impressionnant ! Cependant je trouve que la vraie herbe
3D n'est pas assez dense et les grass cards au loin ont une teinte différente, du coup c'est
comme si l'herbe changeait de couleur quand on avance. Aussi le swing des grass cards est
beaucoup plus visible que sur l'herbe en premier plan (en gros ça bouge beaucoup plus a fond
que devant). Et bizarrement certaines plateformes ne reçoivent pas d'herbe, j'ai l'impression
que ces les plateformes dont le relief est le moins plat, bien qu'elles aient la même texture
au sol, on dirait qu'elles sont ignorés, ou leur point de référence est plat sur le point le
plus bas, les rendant invisible (sous le sol)... Aussi, quand on est en l'air (en train de
sauter), l'herbe en dessous se plie comme si on marchait dessus. En tout cas c'est vraiment
pas mal !"

Breakdown (do NOT reinterpret) — the CULLING IS FIXED, keep it; polish these 5:
1. DENSITY: the near 3D grass is STILL not dense enough — increase density again.
2. CARD TINT MISMATCH: the distant grass CARDS have a DIFFERENT TINT than the near 3D grass, so
   "the grass changes color as you advance". Match the cards' colour/greens to the near blades so
   near→far is a seamless single colour.
3. CARD SWAY TOO STRONG: the card sway is MUCH more visible than the foreground grass — cards move
   way too much vs the near blades. Reduce card sway amplitude to be equal-or-gentler than the
   near blades (owner: "ça bouge beaucoup plus à fond que devant").
4. SLOPED PLATFORMS GET NO GRASS: platforms with the LEAST-FLAT relief (bumpy/sloped) — SAME ground
   texture — are skipped, OR their grass reference height is FLAT at the LOWEST point so the blades
   render UNDER the ground (invisible below the surface). Fix placement to follow the ACTUAL
   per-triangle surface height (sample the real ground Y at each instance), not a flat/min-Y
   reference, so sloped grass-textured surfaces get correctly-placed visible grass.
5. AIRBORNE TRAMPLE: when Jak is in the AIR (jumping), the grass below bends as if walked on. The
   trample must be gated by Jak's ALTITUDE — only trample when Jak is on/near the ground surface,
   not when airborne above it (check Jak's Y vs the grass ground Y, skip trample when he's above).
Owner is REMOTE — when verified (objective where possible + moving capture), re-push jak1-grass-poc.
Keep default ON. The systemic culling fix (DROPPED=0) must NOT regress.

## OWNER POLISH ROUND #4 (2026-07-10) — "impressionnant, gros coup de jeune, très très bien bravo"
Owner quote (verbatim, French):
"Alors c'est beaucoup mieux ! Il reste des plateformes avec des textures d'herbe qui n'ont pas
d'herbe par contre, et a niveau de la couleur, tu t'es assuré que ça prenait des couleurs qui
correspondait à la texture ? Histoire que la texture au travers fasse pas tâche (ou l'inverse),
idem pour les grass cards a loin, qui mériteraient d'ailleurs d'être plus loin (et ptêtre que ça
devrait être ajustable, la distance des vrais brins, la distance des grass cards... Distance
étant l'endroit le plus loin jusqu'où on le voit). Aussi quand un modèle 3D est sur (overlap) un
sol où il y a de l'herbe... L'herbe passe au travers ça fait tâche, tu devrais cacher l'herbe aux
endroits où il y a un overlap avec un truc qui n'est pas de l'herbe ! Mais c'est impressionnant,
ça donne un gros coup de jeune au jeu ! Aussi, quand on s'accroche à un rebord avec les mains de
Jak, l'herbe de se rebord devrait aussi s'écarter comme on fait au sol quand il marche ! C'est
vraiment très très bien bravo"

Breakdown (do NOT reinterpret) — keep everything that works; add these 5:
1. STILL-MISSING PLATFORMS: some platforms WITH grass textures STILL have NO grass. The sloped-height
   fix helped but did not cover all grass-textured surfaces — find why the remaining grass-textured
   platforms are skipped (different tpage/texture-id variant? surface flagged non-walkable? a
   different mesh/renderer bucket?) and place grass on them too.
2. COLOUR MATCHES THE GROUND TEXTURE: make the grass blade/card colour SAMPLE / match the underlying
   ground texture at each location, so the texture showing through does NOT clash with the blades
   (and vice-versa). Per-location tint from the ground texture (not one global green). Same for the
   distant CARDS — their colour must match the local ground too.
3. CARD DISTANCE FURTHER + ADJUSTABLE DISTANCES: push the grass cards' render distance FURTHER out.
   AND make the distances ADJUSTABLE (owner wants sliders/settings): "distance des vrais brins" and
   "distance des grass cards" — distance = the farthest point up to which each tier is visible. Add
   two Recharged Settings for near-blade view-distance and card view-distance.
4. HIDE GRASS UNDER OVERLAPPING NON-GRASS OBJECTS: when a 3D model/object sits ON (overlaps) a
   grass-textured ground, the grass currently pokes THROUGH it. Cull/hide grass instances where a
   non-grass object overlaps the ground (so grass doesn't clip through crates/models/props).
5. LEDGE-GRAB TRAMPLE: when Jak hangs on a ledge with his hands, the grass on that ledge should
   part/spread like the walk-trample does on the ground (feed Jak's hand/ledge-grab position to the
   trample, gate on the ledge-hang state).
Keep: culling DROPPED=0, density, card tint/sway, sloped placement, airborne-trample gate.
Owner is REMOTE — re-push jak1-grass-poc when verified. Default ON.

## OWNER POLISH#4 addendum — grass on ROCK/VERTICAL walls (2026-07-10)
Owner quote (verbatim, French):
"Par contre j'ai aussi l'impression que des parois de roches (texturés par de la roche sur les
parties verticales, par de l'herbe sur le dessus) ont aussi de l'herbe sur les parties rocheuses,
ça fait des effets bizarres où on va l'herbe a loin sur les parois et des fois des brins sortir de
la roche (et c'est pas le sol d'en dessous qui pose problème dans ce cas, l'herbe passant au travers
étant bien plus haut que le sol du dessous)"

Breakdown (do NOT reinterpret) — DISTINCT from the under-floor issue:
6. GRASS ON ROCK / VERTICAL WALLS: rock walls (vertical faces textured ROCK, top textured GRASS) are
   getting grass ON the ROCKY parts too — grass shows on the walls at distance, and blades poke OUT of
   the rock. This is NOT the under-floor case (the grass poking through the rock is far ABOVE the
   floor below). Root cause is likely: placement puts grass on triangles that are NOT the up-facing
   grass top (wrong texture-id match onto rock, OR no surface-NORMAL filter so vertical/steep faces
   get grass). FIX: only place grass on NEAR-HORIZONTAL, UP-FACING, GRASS-textured surfaces — filter
   by the triangle normal (reject steep/vertical faces) AND strictly by the grass texture-id (reject
   rock-textured faces). No blades on rock walls.

## OWNER CLARIFICATION on #6 (2026-07-10) — filter by TEXTURE FIRST
Owner (verbatim, deduplicated): "le placement devrait filtrer en fonction de la texture surtout,
si sur une normale c'est de la roche, pas d'herbe."
=> The PRIMARY filter is the TEXTURE, not the normal angle. If a triangle's texture is ROCK
(or anything that is NOT the grass ground texture), it gets NO grass — full stop, whatever its
orientation. The current bug is a TEXTURE mis-match (grass instances landing on rock-textured
faces). Make grass-texture-id detection STRICT and per-triangle: only triangles whose actual
sampled/assigned texture is the grass ground get grass; rock (and every non-grass texture) is
excluded. The surface-normal check is a secondary safety net, but the texture filter is the fix.

## OWNER POLISH ROUND #5 (2026-07-10) — sliders not showing + density slider + rock walls still
Owner quote (verbatim, French):
"On devrait pouvoir changer la distance max de la vraie herbe 3D et les grass cards, t'as pas
ajouté ça ! Et aussi on devrait pouvoir régler la densité et on a encore des brins dans les
parties verticales/ sans herbes étrangement"

Breakdown (do NOT reinterpret):
1. DISTANCE SLIDERS NOT VISIBLE: the near-blade + card view-distance sliders were ADDED IN CODE
   (pc-settings recharged-grass-near-dist=30 / recharged-grass-card-dist=95, menu rows 2-3 in
   progress-pc.gc) but they DO NOT SHOW in the Recharged Settings submenu on device — the owner
   cannot see/use them. ROOT CAUSE is almost certainly the submenu LIVE-LENGTH / row count not
   extended to include the 2 new rows (Goptions-reorder length machinery). FIX: make the two
   distance sliders actually APPEAR and be adjustable in the on-device menu (bump the submenu
   length; verify by a DEVICE screencap of the submenu SHOWING the two distance rows + prove
   changing them changes the render distance).
2. DENSITY SLIDER: add a THIRD adjustable setting — grass DENSITY — in the same Recharged submenu.
3. ROCK WALLS STILL HAVE GRASS: "on a encore des brins dans les parties verticales / sans herbe" —
   the texture-first filter is NOT fully effective; blades still appear on vertical/non-grass
   parts. Strengthen it: verify per-triangle grass-texture-id detection ACTUALLY excludes the rock
   faces (the mis-match persists), + the normal filter as backup. Prove on the ACTUAL rock-wall
   beat on device (screencap of a rock wall with NO blades), not by claim.
Keep everything that works. Owner REMOTE — re-push when the sliders are VISIBLE + rock walls clean.
The validator now requires DEVICE PROOF the sliders show (not just code keywords).

## OWNER POLISH ROUND #6 (2026-07-10) — "faut que ça claque" + dedicated grass sub-submenu
Owner quote (verbatim, French):
"J'ai l'impression que les grass cards sont trop denses et font beaucoup plus touffue que la vraie
herbe, et leur teinte est encore différente de la teinte de l'herbe 3D donc ça fait une transition
un peu bizarre (d'ailleurs la transition entre les deux est bizarre). Il y a toujours de l'herbe qui
passe au travers d'objets posés sur le sol où l'herbe est ajoutée (ça fait bizarre de voir des brins
d'herbe sortir d'un gros caillou) ... Et aussi on dirait que l'herbe n'est pas influencée par
'l'éclairage' (baked or not) donc autant sur les zones parfaitement éclairées où la texture est
identique aux couleurs de nos brins c'est nickel, autant d'autres endroits ça dénote car l'herbe
(texture plate) en dessous est plus foncée. J'oublie pas à quel point c'est impressionnant ce qu'on
à fait là, mais j'aimerais que ça colle aux attentes visuelles de nos jours, faut que ça claque et
que ça apporte vraiment un truc en plus ! Par contre les réglages n'apparaissent toujours pas dans
recharged settings, ça devrait être un sous-menu de ce sous-menu avec tous les settings pour l'herbe !"

Breakdown (do NOT reinterpret) — goal is "ça claque", modern visual bar:
1. CARDS TOO DENSE/TUFTED: the grass cards are denser/tuftier than the real 3D grass — reduce card
   density so cards read lighter than / consistent with the near blades.
2. CARD TINT STILL OFF + WEIRD TRANSITION: cards' tint STILL differs from the 3D grass, and the
   near→card TRANSITION reads weird. Match card tint to the near grass AND smooth the LOD transition
   (fade/blend the boundary so there's no visible seam/colour jump).
3. GRASS STILL CLIPS THROUGH GROUND OBJECTS: blades still poke out of objects sitting on the grass
   (e.g. a big rock/boulder) — the polish#4 "hide under overlapping objects" fix did NOT work.
   Re-do it and PROVE on a device beat (a rock/prop on grass with NO blades poking through).
4. GRASS IGNORES LIGHTING (baked/dynamic): the grass is a flat colour unaffected by the scene/baked
   lighting, so where the ground texture is DARKER (shadowed/baked-dark) the bright flat grass
   clashes. Make the grass RESPOND to the lighting — sample/apply the baked light (and/or the ground
   texture's local brightness) at each instance so blades darken/brighten to match the ground beneath.
   This is the #1 "ça claque" item: grass must sit in the lighting, not float above it.
5. SETTINGS STILL NOT APPEARING + RESTRUCTURE: the owner still does not see the grass settings in
   Recharged Settings. Build a DEDICATED nested "GRASS SETTINGS" SUB-SUBMENU under Recharged Settings
   that holds ALL grass settings (toggle + near-dist + card-dist + density + any new ones). This
   nested menu definitively fixes the "not appearing" (its own page, own length). PROVE with a device
   screencap of the nested Grass Settings page showing all rows.
Keep culling DROPPED=0 + all prior fixes. Owner REMOTE — re-push when verified (device screencaps).
