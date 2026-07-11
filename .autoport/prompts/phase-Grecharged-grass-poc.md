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

## OWNER POLISH ROUND #7 (2026-07-11) — rock walls OK + transition OK, but clip-halo/coverage/LIGHTING broken
Owner quote (verbatim, French):
"Alors une bonne nouvelle, plus d'herbe sur les parties rocheuses. Par contre... OK ça clip plus a
travers des rochers posés sur le sol (des modèles 3D qui doivent passer a travers du sol) mais en
fait ça fait comme des zones vides autours des éléments plutôt que s'arrêter pile a l'intermédiaire
où le rocher posé fais l'intermédiaire avec le sol) en gros j'ai l'impression que le modèle 3D dudit
rocher est plus gros sous le sol, et que le calcul du clipping prend en compte la partie non visible.
Et ça fonctionne que pour les rochers, le bouton pour la warp gate a de l'herbe qui clip au travers
de fou, d'autres objets aussi... Et c'est bizarre mais sur les plateformes on a des zones vides qui
n'ont aucun objet qui gênent donc qui devrait avoir de l'herbe, gênant par ce qu'on se retrouve avec
une texture d'herbe plate visible sans herbe 3D dessus. La transition herbe 3D -> grass card est bien
mieux, ça c'est cool. Par contre l'adaptation au lighting est complètement pété, l'herbe est ultra
éclairée tout du long, partout exactement pareil, bien plus 'lumineuse' que la texture du sol de
partout, même aux endroits les plus éclairés... Aucune variation, pas du tout adapté à l'endroit où
elle est, et ce partout, peut importe le moment de la journée, peut importe si la zone est ombrée ou
pas, c'est juste 'flashy' de partout"

GOOD (keep, do not regress): rock/vertical faces CLEAN; the 3D-grass -> card transition is much better.
Breakdown (do NOT reinterpret) — fix these 4:
1. OBJECT-CLIP HALO TOO BIG: the hide-under-objects now leaves an oversized EMPTY HALO around objects
   instead of stopping exactly at the ground/object intersection. Owner's insight: the object's 3D
   model extends BIGGER UNDER the ground, and the clip test uses that non-visible underground volume.
   Clip only to the VISIBLE above-ground footprint (intersection at ground level), not the full/buried
   model — no empty ring around objects.
2. CLIP ONLY WORKS FOR ROCKS: other objects still clip through grass badly — the WARP-GATE BUTTON has
   grass poking through "de fou", plus other props. Extend the overlap-hide to ALL objects on grass
   (warp-gate button, props, etc.), not just rocks.
3. COVERAGE GAPS: on platforms there are EMPTY ZONES with NO blocking object that SHOULD have grass —
   you see flat grass texture with no 3D grass on top. Fill those (why are open grass-textured areas
   skipped? density/placement holes). Grass-textured ground with nothing on it must get grass.
4. LIGHTING COMPLETELY BROKEN (#1 priority): the grass is ULTRA-LIT everywhere, EXACTLY the same
   everywhere, much BRIGHTER than the ground texture everywhere (even in the brightest spots), NO
   variation, not adapted to location, regardless of time-of-day or shade — just "flashy" everywhere.
   The polish#6 lighting attempt FAILED. Re-do it properly: the grass must sample the actual scene /
   baked lighting (and/or the ground texture's local luminance) PER-LOCATION so blades DARKEN in shade
   and MATCH the ground brightness — real variation across the level and across time-of-day, never a
   uniform flashy over-bright. Prove with device captures at a LIT spot AND a SHADED spot showing the
   grass brightness matching the ground beneath at each.
Keep culling DROPPED=0 + all prior fixes. Owner REMOTE — re-push when verified (device captures at lit+shaded).

## OWNER POLISH ROUND #8 (2026-07-11) — clipping OK, but shrub/edge coverage + lighting still GLOBAL not per-location
Owner quote (verbatim, French):
"Alors le clipping est meilleur en effet. Par contre les shrubs d'herbe d'origine ont beaucoup
d'espace où on voit la texture plate d'origine autour sans herbe, probablement parce que leur mesh
occupe l'espace bien que non visible en alpha, ça fait un peu tâche. Notre herbe 3D et les grass
cards n'arrivent pas au bords des plateformes qui ont de la texture d'herbe au sol, laissant des
zones avec la texture plate uniquement, à corriger. Pour le lighting, certes c'est plus flashy, mais
j'ai l'impression que l'herbe est teinté de la même exacte façon de partout, donc elle paraît sombre
sur les zones très éclairées, ok sur les zones moyennement éclairées, un peu trop lumineuse sur les
zones ombragées, c'est toujours pas adapté ! J'ai l'impression que c'est le même 'lighting pickup'
appliqué à la totalité de l'herbe plutôt que location aware"

GOOD (keep): clipping is better. Fix these 3:
1. SHRUB BALD PATCHES: the original grass SHRUBS leave a lot of empty flat-texture space around them
   with no grass — because the shrub MESH occupies that footprint even though it's alpha-transparent
   (invisible) there. Grass placement treats the shrub's whole mesh bounds as occupied. Fix: do NOT
   let the shrub's alpha-transparent mesh area block grass — place grass under/around shrubs (block
   only where the shrub is actually opaque, or exempt shrubs from the overlap-hide entirely).
2. GRASS DOESN'T REACH PLATFORM EDGES: our 3D grass + cards stop short of the EDGES of grass-textured
   platforms, leaving a bald margin of flat texture at the borders. Extend placement to the actual
   edges of grass-textured surfaces (fill the border triangles).
3. LIGHTING STILL GLOBAL, NOT LOCATION-AWARE (#1 priority — owner's precise diagnosis): the grass is
   tinted the EXACT SAME everywhere, so it looks DARK on very-lit zones, OK on medium zones, TOO
   BRIGHT on shaded zones. It's ONE global "lighting pickup" applied to ALL grass, not per-location.
   Fix: sample the lighting PER-INSTANCE at each blade/card's WORLD POSITION (the local baked/scene
   light where that blade actually stands), so lit-zone grass is bright and shaded-zone grass is dark
   — real spatial variation, not a single global value. Prove with device captures of a bright zone
   AND a shaded zone in the SAME frame/beat showing the grass brightness differing correctly between
   them.
Keep culling DROPPED=0 + all prior fixes. Owner REMOTE — re-push when verified.

## OWNER REMINDER on #8 lighting (2026-07-11) — it's DYNAMIC (time-of-day), not frozen
Owner (verbatim): "Peut-être un détail, le lighting change sur la journée, c'est pas figé, tu
devrais le savoir mais je te le rappelle quand même"
=> The per-instance lighting must be DYNAMIC: the scene light changes over the day/night cycle,
so do NOT sample once at load/placement and freeze it. Re-sample the CURRENT scene/baked light
(per-frame or as the time-of-day updates) so the grass tracks sunrise/day/dusk/night correctly —
grass gets brighter at midday, darker at dusk/night, matching the ground at that moment. Both
LOCATION-aware (per-instance world pos) AND TIME-aware (follows the day cycle). Prove the time
dimension too if feasible (grass brightness at two different times-of-day differs).

## OWNER POLISH ROUND #9 (2026-07-11) — best integration so far; edges (block overflow/holes) + GROUND baked-light
Owner quote (verbatim, French):
"Alors c'est clairement la meilleure intégration so far... On a des zones ombragées, ça fit beaucoup
mieux. Les plateformes sont pleines d'herbes pour la plupart, mais il y a quand même problème avec
les bords des plateformes, ça donne des trous sur le dessus (pas partout, à certaines, où l'herbe
n'est pas présente et on voit la texture d'herbe plate... Et sur d'autre bordures étrangement on a
l'herbe qui va un peu trop loin, débordant de la plateforme (comme si l'herbe était positionnée par
bloc et que ce bloc dépassait un peu). Aussi, la couleur du sol change a plein d'endroits durant la
journée (baked lighting) et bien que l'herbe est globalement mieux intégrée, ça se reflète pas du
tout sur l'herbe 3D, donc notre herbe 3D fait tâche quand le baked lighting sur les textures d'herbe
les rend plus sombres... En gros tu prends toujours pas en compte le baked lighting du sol il
semblerait (qui dépend de l'emplacement+du moment du jour)."

GOOD (keep): best integration so far; shaded zones fit much better; platforms mostly full.
Breakdown (do NOT reinterpret) — 2 items:
1. PLATFORM EDGE PLACEMENT (block-based, imprecise): on SOME borders grass leaves HOLES (flat texture
   visible at the edge), on OTHERS grass OVERFLOWS past the platform edge ("comme si l'herbe était
   positionnée par bloc et que ce bloc dépassait un peu"). The placement is BLOCK/GRID-based and does
   not respect the exact triangle boundary at edges. Fix: clip placement precisely to the grass-
   textured TRIANGLE boundaries — an instance only spawns if its base is INSIDE a grass triangle;
   no overflow past the platform edge, no bald holes at the edge. Per-triangle/point-in-triangle
   test, not a coarse block/grid.
2. GROUND BAKED-LIGHTING (the real one the owner means): the GROUND's colour changes at many spots
   during the day because of BAKED LIGHTING (the tfrag ground's baked vertex colours / lightmap,
   location- AND time-of-day dependent). iteration 8 improved integration but the 3D grass still does
   NOT reflect the GROUND's baked light — so where the baked light darkens the grass TEXTURE, our 3D
   grass stays bright and clashes. Fix: sample the ACTUAL GROUND BAKED LIGHT at each blade's position
   — read the tfrag ground's baked vertex colour / lightmap value under the blade (interpolated on
   the triangle), and apply it to the blade so the 3D grass darkens/brightens EXACTLY like the ground
   texture beneath it, at that location and that time-of-day. Not a generic scene light — the ground's
   own baked value. Prove with device captures where the baked ground is dark: the grass must match.
Keep culling DROPPED=0 + all prior fixes. Owner REMOTE — re-push when verified.

## IMPLEMENTATION NOTE for #9 baked-light sampling (supervisor + owner, 2026-07-11) — keep it cheap
The GROUND baked lighting is NOT separable into (spatial constant) x (global time factor) — the
SHADOW PATTERN itself moves with time-of-day, so two spots at the same instant differ and a spot
changes its pattern over the day. So the ground's CURRENT baked vertex colour must be sampled
live. Do it PERFORMANTLY:
- PRECOMPUTE ONCE (at placement): for each grass instance, store which GROUND TRIANGLE it sits on
  + its BARYCENTRIC weights. This never changes.
- LIVE (cheap): fetch the triangle's 3 CURRENT baked vertex colours (the engine already computes
  these to draw the tfrag ground this frame) and barycentric-interpolate with the stored weights
  -> the baked colour under the blade right now. No geometry search per frame — just 3 reads + a lerp.
- DECOUPLE the update rate from the frame rate: the day cycle is slow, so re-evaluate the per-instance
  baked colour a few times per second (or only when time-of-day advances meaningfully), NOT every
  frame. Cache it on the instance between updates.
- Do NOT re-scan geometry or per-blade-per-frame CPU sample — that would tank fps. The gate's fps
  ON-vs-OFF device report must stay acceptable (this is how a naive impl gets caught).

## OWNER POLISH ROUND #10 (2026-07-11) — LIGHTING PERFECT; only edges left (block-granular, must be per-BLADE)
Owner quote (verbatim, French):
"Alors pour la dernière itération, le lighting est enfin parfait ! On a bien l'herbe qui suit tout au
long de la journée, c'est nickel ! Par contre on a toujours des brins qui dépassent des bordures et
des zones vide près des bordures sans herbe où du coup on a que la texture plate ça fait tâche encore !
L'idée de faire par triangle, on dirait que tu fais genre si ça fit pas, on met pas le block d'herbe,
si ça déborde un peu on met le block d'herbe quitte à ce que ça déborde au lieu de cut sur le triangle...
Enfin un truc comme ça... On y est vraiment presque, ça claque !"

DONE (do NOT regress): the day-cycle lighting is PERFECT — grass follows time-of-day correctly.
ONLY ITEM #10 — EDGE PLACEMENT is still BLOCK-GRANULAR, not per-blade:
- Symptom: blades STILL overflow past platform borders, AND empty zones near borders have no grass
  (flat texture shows, clashes).
- Owner's precise diagnosis (correct): the per-triangle test is applied at BLOCK granularity — a whole
  grass BLOCK is placed if it roughly fits and skipped if it doesn't, "if it overflows a bit you place
  the block anyway instead of cutting at the triangle". So near edges you get either overflow (block
  kept) or holes (block dropped).
- FIX: the point-in-triangle test must be PER-BLADE (per individual instance), NOT per-block. Test EACH
  blade's OWN base position: it spawns iff its base is inside a grass-textured triangle; otherwise it is
  dropped individually. This gives a clean per-blade boundary that hugs the exact triangle edge — no
  overflow past the border, no bald holes near the border. (If placement is chunk/grid-based, evaluate
  each candidate instance individually within the chunk against the triangle set; do not accept/reject
  whole chunks/blocks.)
- Prove on device: a platform border screencap where the grass stops EXACTLY at the edge (no blade
  beyond it, no bald flat-texture margin inside it).
Keep culling DROPPED=0 + lighting + all prior fixes. Owner REMOTE — re-push when the borders are clean.

## OWNER POLISH ROUND #11 (2026-07-11) — EDGES STILL BROKEN (floating overflow + holes). No more claims without a DEVICE EDGE CLOSE-UP.
Owner quote (verbatim, French):
"on a encore de L'herbe qui dépasse des plateformes (flottante) et des zones sans herbes, tu t'es
foutu de ma gueule là t'a pas fait ce qui était annoncé c'est pas possible !"

REALITY: the round#9/#10 boundary-classification + inset heuristics FAILED — the platform edges STILL
show (a) FLOATING grass past the platform silhouette AND (b) bald holes near borders. The current model
(GrassRenderer.cpp: bAB/bBC/bCA boundary flags, lip-sharing, per-edge insets, GROUND_UPNESS 0.35) is
not converging — it produces BOTH symptoms at once. STOP layering heuristics; find the ROOT of the two
distinct symptoms and fix each:
1. FLOATING OVERFLOW (grass beyond the visible platform, over the void): this is NOT solved by a
   point-in-triangle test alone, because the grass-textured MESH triangles themselves can extend past
   the visible platform silhouette (overhang), and/or a blade's HEIGHT/WIDTH at the rim pokes out over
   the edge. Diagnose which: (a) do the grass tris overhang the visible edge? (compare tri extent vs the
   platform rim) and/or (b) is it blade height/width at rim instances? Fix the actual cause — e.g. clip
   instances to the true rim (not the raw tri extent), and/or shrink/omit blades within one blade-radius
   of a true boundary edge so no geometry crosses the rim.
2. HOLES NEAR EDGES: the boundary inset is too aggressive / mis-classifies interior seams as boundaries,
   leaving a bald margin short of the rim. An instance's base inside a grass tri must NOT be dropped just
   for being near an edge unless that edge is a TRUE platform rim.
MANDATORY VERIFICATION (this is the new gate — the report keyword pass is NOT enough):
- Produce a DEVICE CLOSE-UP screencap of an actual platform EDGE (walk Jak to a platform rim, camera on
  the border) named `p11_edge_closeup_*.png`, clearly showing grass stopping EXACTLY at the rim — NO
  blade floating past it, NO bald flat-texture margin inside it. The supervisor will EYEBALL this exact
  close-up before any release; a wide spawn shot does NOT count.
Keep culling DROPPED=0 + the (perfect) lighting + all prior fixes. Owner REMOTE.

## SUPERVISOR CODE DIAGNOSIS (2026-07-11) — placement IS per-triangle; the real cause is EDGE-LIP tris
Read GrassRenderer.cpp PHASE 2 (lines ~647-694): each blade base IS a barycentric point INSIDE a real
grass triangle (gi.px = p0 + r1*e1 + r2*e2, with the r1+r2>1 reflection) — NOT a flat predefined block.
So "place blades on triangles" is ALREADY done. The owner's block-perception is a symptom, not the cause.

THE REAL ROOT of overflow+holes (owner rounds #9/#10/#11 kept oscillating here):
- POLISH#8 lowered GROUND_UPNESS to 0.35 to INCLUDE the steep EDGE-LIP triangles at platform rims (to
  fill the bald edge margin). But those lip tris face OUTWARD/DOWNWARD over the drop, so blade BASES land
  on the lip that overhangs the void -> the "floating grass past the platform". The POLISH#11 shader
  rim-clamp only limits a blade's horizontal SPREAD, NOT its base position, so bases on the overhanging
  lip still float.
- Excluding the lips (higher upness) removes the overflow but re-opens the bald margin = the "holes".
That is the exact overflow<->holes tradeoff the code has been trading. Neither the upness knob nor the
spread-clamp resolves it because the problem is BASE PLACEMENT on outward/downward rim-lip triangles.

TARGETED FIX (round #12 — one clean idea, not more heuristic layering):
1. Do NOT place blade BASES on steep outward-facing rim-lip triangles (the ones that overhang the drop).
   Keep the STRICT grass-texture filter; classify a tri as a "rim lip" if it is steep (upness in the
   ~0.2..0.6 band) AND its steep-descent direction points AWAY from the adjacent flat grass top (i.e. it
   drops off the platform). Exclude those from base placement -> no floating overflow.
2. To avoid the bald margin that exclusion caused before: EXTEND the flat-top grass tris' base placement
   right up to the shared TOP RIM edge (the edge the flat top shares with the excluded lip). Blades near
   that top rim grow WORLD-UP (not along a tilted normal) and keep the POLISH#11 rim-clamp so their
   spread never crosses the rim. Result: grass full to the exact top edge, none hanging past it.
3. Net: coverage = the FLAT walkable top, clipped exactly at the top rim; no base on the overhanging lip.

MANDATORY: a device platform-EDGE CLOSE-UP (p11/p12_edge_closeup_*.png) at a real raised platform rim
(with the drop visible) showing grass ending EXACTLY at the top edge — no floating blade, no bald margin.
The SUPERVISOR eyeballs this exact close-up before any release. Keep DROPPED=0 + lighting + all else.

## SUPERVISOR DIAGNOSIS #2 (2026-07-11) — the owner's "block" IS the 0.5m OCCUPANCY GRID
Owner (verbatim): "j'ai toujours l'impression que tu poses des blocks complets d'herbe au lieu de clip
sur les tris... enfin un truc du style" + on the current build: grass MISSING on Jak's OWN platform
(flat texture, holes) AND grass FLOATING on DISTANT platforms (in the void) — NOT overhang texture.
Code finding (GrassRenderer.cpp ~751-780): base placement is per-triangle, BUT the object-hide uses a
0.5m XZ OCCUPANCY GRID (OCC_CELL_M=0.5) with a 3x3 DILATION (+1 cell). It CULLS grass in 0.5m CELL-
BLOCKS and expands by one cell everywhere -> block-shaped BALD HOLES on the platform (the owner's
"missing grass" / "block" perception), likely mis-firing on a nearby/above TIE vertex even with no real
object on that spot. The distant-platform FLOATING = the lip-fix not applied to distant/TIE platform tris.
NEXT TARGETED FIX when resumed:
1. OCCUPANCY GRID: remove/greatly shrink the 3x3 dilation; make the object-cull per-INSTANCE (test each
   blade vs the actual object footprint) instead of nuking whole 0.5m cells; tighten OCC_LO/HI so only a
   real object ON the grass culls it. This kills the block-shaped holes on the platform.
2. DISTANT PLATFORM FLOATING: apply the rim/lip exclusion + clamp to TIE-model platform tris too (not
   just the spawn tfrag), so distant raised platforms don't have grass hanging in the void.
Verified via an owner-annotated screenshot showing both defects (base capture: p11_edge_closeup_crawl_*).

## OWNER ROUND #13 (2026-07-11) — killer feature, finish it. Two targeted causes.
Owner: "Non on parke pas, je veux boucler les soucis sur l'herbe, c'est une killer feature, faut pas
se louper, et c'est justement pour ça que je suis relou avec." -> targeted fix, no parking.

Fix EXACTLY these two (from SUPERVISOR DIAGNOSIS #2), nothing else, keep everything that works
(lighting, density, transition, rock-clean):
1. BLOCK-SHAPED BALD HOLES on the platform = the 0.5m OCCUPANCY GRID (OCC_CELL_M) + its 3x3 DILATION.
   - REMOVE the 3x3 dilation entirely.
   - Make the object-hide PER-INSTANCE: for each blade, cull it ONLY if a real object (TIE) footprint
     actually covers its own (px,pz) within [OCC_LO,OCC_HI] above its ground Y — no 0.5m cell nuking,
     no neighbour expansion. Tighten OCC_LO/HI so ONLY an object sitting ON the grass culls it.
   - OBJECTIVE PROOF: log occ_culled and WHERE. On an OPEN platform with no object, occ_culled must be
     ~0 (no bald holes). Report the number + that culls occur only under actual props.
2. FLOATING grass on DISTANT platforms = the rim/lip exclusion + shader rim-clamp are applied to the
   spawn tfrag but NOT to distant TIE-model platforms. Apply the SAME lip-tri base exclusion + true-rim
   clamp to TIE platform triangles, so distant raised platforms have grass that stops at their top rim,
   none hanging in the void.

VERIFICATION (this is doable + what the owner uses): a WIDE spawn gameplay screencap on device (Jak on
his platform, distant platforms visible) named p13_wide_*.png, ON and OFF, same spot. The report must
state: no bald block-holes on Jak's platform (occ_culled~0 there), no floating grass on distant
platforms. The SUPERVISOR eyeballs the p13_wide ON shot for (a) bald holes on the near platform and
(b) floating grass on the far platforms before any push. Keep DROPPED=0 + lighting.

## OWNER CORRECTION on ROUND #13 overflow (2026-07-11)
Owner (verbatim): "C'est pas que lointain où ça dépasse hein ! Si je me colle à la plateforme, ça
dépasse toujours..."
=> The FLOATING OVERFLOW is UNIVERSAL — NEAR platforms too (walk right up to one, grass still hangs
past the edge), not just distant TIE ones. So the round#12 lip-exclusion + shader rim-clamp is NOT
working on ANY platform. Do not narrow item #2 to distant TIE platforms. ROOT-CAUSE why the fix does
not fire at all:
- Is the TRUE-RIM edge classification (bAB/bBC/bCA = edge used by exactly one kept grass tri) actually
  detecting the platform rims? If the rim edge is shared with a NON-grass (rock/void) triangle, is that
  correctly counted as a boundary? Add a device/log count: how many kept tris have >=1 boundary edge,
  how many blades get a finite rim_dist (clamped) vs NO_RIM. If ~0 blades are clamped, the rim detection
  is broken -> the clamp never triggers -> universal overflow.
- Verify the shader ACTUALLY reads gspare(rim_dist) and clamps total XZ offset to it (not silently
  ignored / wrong units). A blade with height/curve/sway must have its horizontal reach hard-limited so
  no vertex crosses the rim, on EVERY platform.
- If blade BASES themselves sit on lip tris that overhang the void, exclude those bases everywhere (near
  AND far), per the diagnosis.
Prove on a NEAR platform the owner can walk to: p13_wide + a near-edge shot showing grass stopping at
the rim. Supervisor eyeballs both. Keep DROPPED=0 + lighting + no block holes.

## OWNER ROUND#13 VERDICT (2026-07-11, verbatim) -> ROUND#14 (floating ONLY)
"Alors pour l'herbe on est sur un 50% corrigé ! Plus de trous sur les bords des plateformes, mais on a
encore de l'herbe qui dépasse dans le vide sur les bordures."
=> HOLES ON PLATFORM EDGES = FIXED (round#13 per-instance object-cull). KEEP IT, do NOT regress.
=> FLOATING OVERFLOW past the platform rim into the VOID = STILL BROKEN. This is now the ONLY target.

## STOP GUESSING — DISCRIMINATE the floating mechanism with instrumentation
The floating has survived FIVE fixes (upness gate; POLISH#11 per-blade rim clamp; POLISH#12 overhang-lip
base exclusion; round#13 transitive lip exclusion + TIE rim clamp). So the assumed cause ("bases on
tilted lip tris + unclamped horizontal offset") is INCOMPLETE or the fix never reaches the real overflow.
Do NOT ship a 6th guess. First DISCRIMINATE, with device instrumentation at a REAL edge, among:

- **H-A blade GEOMETRY overflow:** the base is at/inside the rim, but the blade's rendered silhouette
  (HEIGHT x lean/curve/wind at the TIP + half CARD-WIDTH) sticks out past the rim. The rim-clamp clamps
  the base/center horizontal offset but NOT the full blade extent (tip lean + half width). 
  DISCRIMINATOR: count per frame the blades whose FINAL rendered horizontal position (post-clamp,
  INCLUDING tip lean + half width) exceeds their own rim edge. If >0 => H-A (the clamp leaks geometry).
- **H-B base past the VISIBLE silhouette:** the grass GROUND triangle extends BEYOND the visible platform
  drop-edge (render/collision mesh overhangs the wall), so bases inside the tri are already over the void
  and dmin (distance to the TRIANGLE edge) is positive there. Lip-exclusion can't catch it (these are
  FLAT tops, not tilted lips). DISCRIMINATOR: render near-rim blades as BARE BASE POINTS (height->0). If
  the points themselves appear over the void => H-B (bases past silhouette; dmin is vs the wrong edge).
- **H-C it's the CARDS, not the 3D blades:** the mid-distance crossed grass CARDS are wider and may get
  NO rim clamp. DISCRIMINATOR: toggle cards off; if the overflow vanishes => H-C (clamp/exclude cards too).

## Fix the CONFIRMED mechanism(s), then PROVE with an edge close-up
Likely H-A (clamp the FULL horizontal silhouette: base_offset + wind/lean-at-tip + half_width <= dmin, or
better: scale blade HEIGHT->0 as dmin->0 so a rim blade is a stub that cannot lean out) and/or H-B
(compute dmin against the TRUE drop silhouette / inset from the real edge, not the raw grass-tri edge).
Whatever the discriminator proves — fix THAT. Keep the holes fix.

## CAPTURE MANDATE (the recurring failure) — supervisor WILL eyeball the edge close-up before any push
Rounds #11-#13 never landed a real rim-over-void close-up (only open-field wides). Round#14 MUST:
drive Jak to a KNOWN raised edge (Geyser Rock start platform drop, or a training terrace with a clear
void below), pitch the camera DOWN at the rim, and screencap a CLOSE-UP where the platform edge + the
void below are both in frame, ON vs OFF. Name it p14_rim_closeup_*.png. If nav can't reach an edge, use
any debug/free camera. NO open-field wide counts as edge proof. The supervisor eyeballs p14_rim_closeup
for floating BEFORE any jak-builds push; the owner's playtest is the final gate.

## OWNER ROUND#14 VERDICT (2026-07-11, verbatim) -> ROUND#15 (floating on SOME platforms)
"Alors j'ai testé le dernier build, c'est mieux, mais ça dépasse toujours sur certaines plateformes !
Ça devrait pas être si compliqué de faire arrêter toute herbe au bord bordel ! C'est mieux mais c'est
toujours pas ça !"
=> Round#14 height-taper IMPROVED it (works where rim_dist is correct) but grass STILL overflows on
SOME platforms. He is right that stopping grass at an edge should not need 7 rounds. The height-taper
mechanism is FINE; the problem is its INPUT.

## ROOT CAUSE (why #14 is partial): rim_dist comes from FRAGILE mesh-edge topology
`rim_dist` (fed to the height-taper) is derived from the grass-triangle BOUNDARY edges / true-rim
detection. On some platforms the topology defeats this: TIE multi-fragment meshes, edges SHARED with
adjacent grass (so a real drop-off is not flagged as a boundary), overhang lips the topological
exclusion misses, non-manifold seams. There rim_dist is too large -> full-height grass -> overflow.
This is exactly the "some platforms" symptom. Six rounds of patching the mesh-edge detection kept
leaking because the FOUNDATION (topology-based edge distance) is fragile.

## ROUND#15 FIX — topology-INDEPENDENT distance-to-edge field (robust by construction)
Replace the mesh-edge rim_dist with a distance field computed from actual GROUND COVERAGE, not triangle
edges:
1. Rasterize the walkable/solid ground into a FINE top-down 2D coverage mask (~0.1 m cells, NOT 0.5 m;
   NO dilation). Use the SOLID platform extent — if grass triangles overhang the visible platform, clamp
   coverage to the true solid silhouette (prefer the collision/floor extent or the non-lip solid tris),
   so an overhang lip is NOT counted as ground.
2. Distance transform -> rim_dist(x,z) = distance from any point to the nearest NON-ground cell. This is
   correct on EVERY platform regardless of mesh topology.
3. Feed this rim_dist to the EXISTING smooth height-taper (height/lean/width -> 0 as rim_dist -> 0).
   Because the field is continuous and fine, grass shortens smoothly to the exact edge everywhere: no
   floating (edge is real) AND no bald block-margin (continuous, not a coarse grid). The round#13 holes
   fix and DROPPED=0 are NOT regressed.
This is NOT the old 0.5 m OCCUPANCY grid (that did coarse block CULLING + 3x3 dilation = block holes).
This is a fine CONTINUOUS distance field driving a smooth taper — holes cannot recur.

## DISCIPLINE (same as round#14 — instrument, don't guess a 7th time)
On the SPECIFIC platforms that still overflow (ask the supervisor for the owner's named spots; else find
platforms where mesh-edge rim_dist is large right next to a real drop): INSTRUMENT rim_dist (mesh-edge
value vs the new coverage-distance value) and CONFIRM the mesh-edge value is the culprit BEFORE swapping.
Then prove the coverage-distance field gives correct rim_dist there.

## CAPTURE MANDATE (supervisor eyeballs before push)
Capture close-ups at MULTIPLE previously-overflowing platform edges (not one), ON vs OFF, named
p15_edge_<spot>_*.png, each showing grass stopping exactly at the rim over the void. Use level.warp.pos
to reach real rims (blind cpad nav never lands them). Supervisor eyeballs; owner playtest = final gate.

## OWNER ROUND#15 VERDICT (2026-07-11, verbatim) -> ROUND#16 (use the EXACT mesh, kill the raster)
"Je pense que le principe de carrés d'herbe de 0.5x0.5 est nul, ça s'adapte pas aux reliefs, ça suit pas
les bordures... Enfin c'est merdique ! On a le mesh du sol, on sait où la texture plate d'herbe apparaît,
autant utiliser ça ! Parce que oui, ça dépasse toujours à plein d'endroits, c'est encore manqué ! Allé
tu corriges !"
=> STILL overflows in MANY places. Owner's directive: STOP approximating with grids/rasters. The ground
MESH + the grass TEXTURE region already define exactly where grass belongs, following relief + borders.
Use THAT as the authoritative placement AND boundary.

## SUPERVISOR CODE READ (2026-07-11, GrassRenderer.cpp — do NOT trust prior round reports, verified here)
The persistent overflow has ONE root that every round left standing: the edge/boundary detection is the
EDGE-COUNT method — "an edge is a rim/boundary iff used by exactly ONE kept grass triangle" (the
bAB/bBC/bCA flags, PHASE 1 lip exclusion ~L629-694, POLISH#11 rim_dist). On TIE / MULTI-FRAGMENT grass
platforms the SAME physical edge appears in separate fragments' triangle lists (and float-position
mismatches), so a true outer edge is counted as used by >=2 tris -> NOT flagged as a boundary. TWO
failures result:
  (1) the OVERHANG-LIP exclusion (PHASE 1.5) misses the drooping grass-textured edge tris (upness
      0.35..0.5 admitted by GROUND_UPNESS=0.35) -> grass BASES are PLACED on outward/downward lip tris
      -> blades hang past the platform silhouette = the overflow the owner sees "à plein d'endroits".
  (2) rim_dist misses the real rim -> no height-taper there.
Round#15 patched only (2) with a 0.1 m RASTER coverage field (cov_cell 0.1m, FLOOR_UPNESS=0.5) — which
APPROXIMATES + stair-steps the border ("ça suit pas les bordures") and does NOT stop (1) (bases still on
lips). There is ALSO a placement/coverage MISMATCH: placement keeps upness>=0.35 but the coverage
silhouette is upness>=0.5, so grass is placed on tris the boundary field doesn't consider solid.

## ROUND#16 FIX — exact mesh geometry, ROBUST edge detection, NO raster
1. ROBUST TRUE-EDGE DETECTION: dedup triangle edges by QUANTIZED WORLD POSITION (reuse the QUANT hashing
   ~L600) across ALL fragments/tris BEFORE counting, so a shared physical edge is counted once and a
   real outer border edge (used by exactly one triangle in world space) is correctly flagged — on TIE
   multi-fragment platforms too. This is the single fix that unblocks BOTH the lip exclusion and the rim
   clamp. VERIFY on device: count true-border edges before/after the dedup on a TIE platform that
   overflowed (expect many more real borders found).
2. PLACEMENT = the grass-textured tris only, and EXCLUDE the overhang-lip tris using the robust border
   (a tilted tri whose downhill edge is now-correctly a true border = a drooping lip -> no bases).
3. CLIP/TAPER from the EXACT triangle edges (point-to-true-rim-edge distance in world units, the
   POLISH#9 edge geometry already at L317/L538), NOT the raster. rim_dist = exact min distance to the
   nearest TRUE border edge. REMOVE the 0.1 m coverage-raster as the boundary source (it approximates).
4. Resolve the upness mismatch: one consistent grass region (place + boundary use the SAME tris).
Net: grass base only on real walkable grass-textured tris, clamped to the EXACT mesh edge -> stops on the
border that follows relief by construction. No grid, no raster, no stair-step. Keep DROPPED=0 density,
day-cycle light, object-cull, sliders. DEFAULT ON, OFF==stock.

## DISCIPLINE + CAPTURE (7 rounds failed — be exact, supervisor eyeballs)
Instrument the robust-edge count vs the old count on the overflowing platforms FIRST (prove the miss).
Capture close-ups at SEVERAL previously-overflowing edges p16_edge_*_on vs _off; supervisor eyeballs
BEFORE push; owner playtest = final gate.

## ROUND#16 FALSIFIED the edge-detection premise -> ROUND#17 (the REAL root: render-mesh cantilever)
Round#16 implemented robust world-position true-edge detection AND INSTRUMENTALLY FALSIFIED the
supervisor's premise: robust boundary_edges=1989 vs old raw-1cm boundary_raw=1991 (delta -2). Edge
detection was NEVER missing borders. The re-diagnosis (by elimination) found the TRUE root:
=> The grass-textured RENDER mesh CANTILEVERS PAST the visible/COLLISION platform edge (PS2 visual
   meshes routinely overhang the walkable collision floor). Grass placed correctly on the render-mesh
   grass tris still sits BEYOND the visible drop, because those overhanging tri edges are INTERIOR in the
   RENDER mesh (shared with more overhanging tris) -> no render-mesh edge method can ever flag them.
This is why 8 rounds failed: all of them (placement, lip-exclusion, mesh-edge rim, coverage raster,
robust edge dedup) worked on the RENDER-MESH boundary, but the render mesh itself overhangs the true edge.

## ROUND#17 FIX — bound grass by the WALKABLE-FLOOR / COLLISION silhouette, not the render mesh
1. INSTRUMENT FIRST (discipline that just saved us): on a platform the owner reaches that overflows,
   MEASURE the offset between the render-mesh grass edge and the COLLISION/walkable-floor edge
   (collide-mesh / pat / where Jak can stand). PROVE the cantilever (render edge is past the collision
   edge by X cm) before implementing. If NOT confirmed, keep digging — do NOT ship a 9th guess.
2. CONFIRM ACCESS: determine how the grass builder (GrassRenderer.cpp, at level-load static place) can
   read the level COLLISION / walkable-floor silhouette (collide-mesh/pat in the engine collision
   system). If the renderer cannot directly reach it, define the minimal bridge to get the walkable
   silhouette (or a distance-to-walkable-edge field) to the grass builder.
3. BOUND grass PLACEMENT + CLIP by the COLLISION/walkable-floor silhouette: a blade exists only where
   there is walkable floor at/below it, and its rim_dist = distance to the COLLISION edge (where Jak can
   stand), so grass shortens/stops at the TRUE walkable edge — not the overhanging render-mesh edge.
   Keep the existing height-taper + clamp machinery; only the BOUNDARY SOURCE changes (render mesh ->
   collision floor). Keep DROPPED=0 density, day-cycle light, object-cull, sliders. DEFAULT ON, OFF==stock.
Note: the owner's "use the mesh" was right in spirit (use real geometry, not a grid) — but the correct
geometry is the COLLISION floor, not the render mesh which overhangs it.

## DISCIPLINE + CAPTURE (owner frustrated, 8 rounds — instrument, prove, supervisor eyeballs)
Prove the cantilever with numbers first; capture p17_edge_* close-ups at previously-overflowing platforms
ON vs OFF; supervisor eyeballs BEFORE any push; owner playtest = final gate.

## OWNER CORRECTION on ROUND#17 (2026-07-11, verbatim) — collision is a CLIP, not the base
"Ça me paraît bancal, et rien ne me dit que l'herbe n'est pas un block de 0.5x0.5 plat au lieu de suivre
le relief du mesh... Puis si tu te bases sur la collision, t'as pas l'info de si oui ou non c'est de
l'herbe car pas de texture sur la collision... Ça peut servir pour vérifier, mais pas comme seule base."
Owner is RIGHT on both counts:
1. COLLISION HAS NO TEXTURE INFO -> it cannot tell WHERE grass is. It must NOT be the placement basis.
   PLACEMENT STAYS the grass-TEXTURED RENDER MESH (barycentric on the real tri plane — relief-following,
   PROVEN: GrassRenderer.cpp:943 `gi.py = r.p0y + r1*r.e1y + r2*r.e2y` = interpolated REAL vertex heights,
   NOT a flat 0.5 block). Collision is used ONLY as an ADDITIONAL CLIP.
2. So the model is an INTERSECTION: grass exists where (a) the render mesh is grass-TEXTURED AND (b) it is
   over the walkable COLLISION floor. Clip/taper grass at the COLLISION edge -> removes the render-mesh
   CANTILEVER (the overhang past the visible/walkable edge) that forms the flat protruding "block" the
   owner sees. Placement/texture/relief all come from the render mesh; collision only trims the overhang.

## Round#17 (corrected) steps
1. INSTRUMENT: prove the cantilever (render-mesh grass edge is past the collision/walkable edge by X cm)
   on an overflowing platform. Also PROVE relief-following to the owner: capture a BUMPY grass platform
   showing grass bases conforming to the bumps (not a flat plane) — kill the "flat 0.5 block" doubt with
   a real frame + the :943 barycentric reference.
2. KEEP placement = grass-textured render mesh (barycentric, relief). Do NOT make collision the base.
3. ADD a collision-floor CLIP: for each grass blade, if its (px,pz) is beyond the walkable collision-floor
   silhouette (or within a taper of the collision edge), taper/cull it — the existing height-taper +
   clamp machinery, but the CLIP boundary = the COLLISION edge (where Jak stands), applied ON TOP of the
   grass-textured placement. Grass = textured-mesh ∩ walkable-floor, stopping at the collision edge.
4. Confirm collision-mesh access from the grass builder; define the minimal bridge if needed.

## OWNER ROUND#17 VERDICT (2026-07-11, verbatim, ANGRY) -> ROUND#18 (revert collision, PURE mesh)
"C'est un poil mieux, mais il y a quand même des endroits où ça dépasse des plateformes (comme avant) et
surtout il y a des bandes sans herbes 3D genre une ligne droite de 50cm de large sur plusieurs mètres, à
plusieurs endroits... Et l'herbe clip toujours au travers des coffres et du bouton pour activer le
portail... Enfin bref c'est toujours pas bon... Base toi sur les putains de mesh directement et place
l'herbe directement sur les mesh et pas avec tes putains de blocks de 50x50cm bordel tu commences à me
casser les couilles"
=> THREE problems, and the owner is furious. Honor his directive LITERALLY.

## ROUND#17's COLLISION CLIP IS THE REGRESSION — REVERT IT
The collision mesh is a DIFFERENT mesh from the render mesh. col_rim (PHASE 1.6) DROPS a blade whose base
is past the walkable-collision rim. Wherever the collision silhouette DIVERGES from the grass render area
— along the collision tris' long STRAIGHT edges — grass is dropped in a straight band = the owner's "ligne
droite de 50cm de large sur plusieurs mètres, à plusieurs endroits". Collision-as-clip was a supervisor
misstep (owner warned: "la collision peut servir à vérifier, pas comme seule base"). 
=> REVERT PHASE 1.6 + the col_rim application entirely. No collision clip. Restore pure grass-textured-
   mesh placement. Verify the 50cm bald strips are GONE.

## OWNER DIRECTIVE — PURE MESH, sub-triangle, NO coarse overlay
Placement is already per-triangle barycentric (GrassRenderer.cpp:943 confirmed, follows relief). The
"blocks 50x50cm" perception = the training ground TRIANGLES are ~0.5 m, so any per-tri place/cull/overflow
decision reads at that granularity. The cure the owner keeps asking for: decisions must be SUB-TRIANGLE.
1. INSTRUMENT ON DEVICE FIRST (show the owner, do not guess): measure the actual granularity of BOTH the
   overflow and the bald bands. Dump the grass-tri size distribution + WHERE overflow blades sit (which
   tri, is that tri's edge a texture boundary or interior). Prove the 50cm source with numbers/overlay.
2. Clip each blade PURELY to the grass-textured-mesh boundary: per-blade point-in-triangle + the exact
   distance to the true grass-texture boundary edge (where the grass-textured tri set ENDS = where the
   artist's grass texture meets rock/other = the real platform edge). NO grid, NO raster, NO collision.
   The grass-TEXTURE boundary on the mesh IS the authoritative edge (owner: "on sait où la texture d'herbe
   apparaît, autant utiliser ça"). Clamp blade geometry so nothing crosses that boundary; taper height so
   nothing floats; but the boundary source = the grass-texture extent on the render mesh, nothing coarser.
3. Do NOT re-introduce any overlay coarser than the mesh (no 0.5 m grid, no raster, no collision silhouette).

## FOLD IN THE OBJECT-CLIP (owner now lists it as a current defect, not backlog)
Grass still clips THROUGH the crates and the portal-activation button. Extend the object-cull to non-TIE
ground-resting objects (crates, the portal button = game-objects/actors, not TIE), cull by the GROUND-
CONTACT footprint (not the buried full mesh). Fix it in THIS round.

## DISCIPLINE + CAPTURE (owner furious, 9 rounds — instrument, prove, supervisor eyeballs)
Prove the 50cm source + the fix with device instrumentation + close-ups: overflow gone, bald strips gone,
grass on crates/button gone, relief followed. p18_* frames; supervisor eyeballs BEFORE any push.
