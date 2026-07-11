#!/usr/bin/env bash
# Validator — Grecharged-grass-poc: 3D grass PoC on the training level, gated (OFF==stock).
# Physical: gated renderer code + grass shader present in build, device screencap/video artifacts,
# report covers the 3 LOD tiers + breeze + trample + fps cost + OFF==stock.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Ggrass FAIL] $*" >&2; exit 1; }
ok(){ echo "[Ggrass ok] $*"; }

R=.autoport/reports/Grecharged-grass-poc/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*RECHARGED[[:space:]]+GRASS[[:space:]]+POC' "$R" || fail "report lacks RESULT: RECHARGED GRASS POC"
grep -qiE 'tra-grass|grass.*texture.*(detect|ground)|texture.*(id|match).*grass' "$R" || fail "placement must be driven by grass ground-texture detection (tra-grass)"
grep -qiE 'blade' "$R" || fail "must implement individual near blades"
grep -qiE 'size|scale' "$R" && grep -qiE 'orientation|rotation|yaw' "$R" && grep -qiE 'curv|bend|bent' "$R" || fail "blades need variable size + orientation + curvature"
grep -qiE 'flat.?color|no.?texture|couleur' "$R" || fail "PoC blades must be FLAT COLOR (no texture yet)"
grep -qiE 'breeze|wind|brise|sway' "$R" || fail "must implement breeze idle motion"
grep -qiE 'trample|flatten|écras|crush|bend.*(jak|player)|jak.*(walk|pos)' "$R" || fail "must implement the trample-under-Jak effect"
grep -qiE 'card' "$R" || fail "must implement mid-range grass cards (crossed quads)"
grep -qiE 'lod|distance|band|tier|far' "$R" || fail "must describe the 3-tier LOD (near blades / mid cards / far texture)"
grep -qiE 'training|geyser' "$R" || fail "PoC must be scoped to the training level"
grep -qiE 'fps|cost|perf' "$R" || fail "must report the fps cost on device"
grep -qiE 'off.*(stock|identical|unchanged)|stock.*off|no regression' "$R" || fail "must prove OFF == stock"
# OWNER OVERRIDE 2026-07-10: grass ships DEFAULT ON (toggle still exists; OFF == stock).
grep -qiE 'default[ -]?on|on by default|default.*#t|défaut.*(on|activ)|ships? (on|enabled)' "$R" || fail "owner override: grass must default ON (not OFF) — toggle still exists, OFF still == stock"
ok "report: placement + blades(size/orient/curve, flat-color) + breeze + trample + cards + LOD + training-only + fps + OFF==stock + DEFAULT ON"

# PHYSICAL: grass renderer/shader actually in the build
SO=build-android/lib/arm64-v8a/libgk.so
[ -f "$SO" ] || fail "no built Android libgk.so"
HITS=$(strings -a "$SO" 2>/dev/null | grep -ciE 'recharged.?grass|grass.?blade|grass_inst|g_grass')
[ "${HITS:-0}" -gt 0 ] || { HITS=$(grep -rli 'recharged.*grass\|grass.*blade\|grassPoc\|g_grass' game/graphics android 2>/dev/null | wc -l); [ "${HITS:-0}" -gt 0 ] || fail "no grass renderer code/strings found in build or source (stub)"; }
ok "grass renderer present ($HITS refs)"

# STRICT: device visual artifacts (screencap; video counts too)
FRAME=$(find .autoport/reports/Grecharged-grass-poc -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.mp4' \) -newermt '-2 days' 2>/dev/null | head -1)
[ -n "$FRAME" ] || fail "no device screencap/video artifact"
SZ=$(stat -c %s "$FRAME" 2>/dev/null || echo 0); [ "$SZ" -ge 20000 ] || fail "artifact $FRAME too small ($SZ B)"
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "report must assert jak1 foreground at capture"
ok "device visual artifact present ($FRAME)"

# GRASS RENDERER IS C++ (libgk) — the DEVICE must actually run the libgk that contains it.
# 2026-07-10: a report claimed "working on device". The RELIABLE proof is deploy_verify
# (build==APK-bundled==device-installed-APK libgk) PLUS the APK-bundled libgk actually
# containing grass strings. NOTE: this device extracts the native lib from INSIDE the APK
# at load time (extractNativeLibs=false) — it is NOT a readable file on disk, so any
# `run-as strings /data/app/.../lib/arm64/libgk.so` check FALSE-FAILS (No such file).
# Read the libgk out of the installed APK instead (host adb has pm-path + pull rights).
bash .autoport/lib/deploy_verify.sh eae4df44 jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL — device APK libgk != fresh build; the grass renderer never reached the device (reinstall the APK)"
ADB=/home/emeric/Android/platform-tools/adb
DP=$("$ADB" -s eae4df44 shell pm path org.opengoal.gk.jak1 2>/dev/null | sed 's/package://' | tr -d '\r' | head -1)
[ -n "$DP" ] || fail "jak1 not installed on device"
mkdir -p .autoport/tmp; DTMP=$(mktemp .autoport/tmp/gdv.XXXXXX.apk)
"$ADB" -s eae4df44 pull "$DP" "$DTMP" >/dev/null 2>&1 || fail "could not pull device APK"
DEVGRASS=$(unzip -p "$DTMP" lib/arm64-v8a/libgk.so 2>/dev/null | strings | grep -ciE 'recharged.?grass|grass.?blade|g_grass')
rm -f "$DTMP"
[ "${DEVGRASS:-0}" -gt 0 ] || fail "the installed device APK's libgk has NO grass renderer strings ($DEVGRASS) — the toggle has nothing to act on"
ok "device runs the grass libgk (APK-bundled: $DEVGRASS grass refs) + deploy_verify PASS"

# OWNER POLISH ROUND 2026-07-10: density++, blade-band reach, card tufts+wind+pop-in fix
grep -qiE 'densit|dense' "$R" || fail "polish: must increase 3D-blade DENSITY (owner #1 ask)"
grep -qiE '(blade|near).*(band|distance|reach|further|farther|extend|lod)|jak.*(in|dans).*grass|transition.*(distance|out)' "$R" || fail "polish: near-blade LOD band must reach far enough that Jak stands in real 3D grass"
grep -qiE '(card).*(tuft|blade|alpha|shape|texture)|tuft' "$R" || fail "polish: grass cards must read as tufts/blades, not blurry rectangles"
grep -qiE '(card).*(wind|sway|breeze)|wind.*card' "$R" || fail "polish: cards must sway in the wind like the near blades"
grep -qiE '(chunk|cull|lod).*(pop|drop|evict|disappear|stab|budget)|pop.?in|de.?instanc|empty (square|chunk|card)' "$R" || fail "polish: must fix the SYSTEMIC chunk de-instancing / culling pop-in (affects BOTH 3D blades AND cards)"
# OWNER FEEDBACK #2 (2026-07-10): length + culling proven WHILE MOVING + cards visible at distance.
grep -qiE 'long(er|ueur)|tall(er)?|height|hauteur' "$R" || fail "polish#2: grass must be a bit longer/taller"
grep -qiE 'card.*(distance|far|mid|band).*(render|visible|show|appear)|distance.*card|cards? at (a )?distance' "$R" || fail "polish#2: grass cards must actually render at distance (mid-LOD tier)"
grep -qiE 'in.?range.*(draw|drawn|vs)|chunk.*(count|drawn|instrument)|per.?frame.*(chunk|grass)' "$R" || fail "polish#2: must INSTRUMENT chunks in-range vs drawn (prove the culling root cause, not guess)"
# The culling bug only manifests WHILE MOVING — a static screencap can't prove the fix.
MOV=$(find .autoport/reports/Grecharged-grass-poc -type f -name '*.mp4' -newermt '-1 day' 2>/dev/null | grep -v '/x86/' | head -1)
[ -n "$MOV" ] || fail "polish#2: need a MOVING device capture (screenrecord .mp4) proving no zones disappear/unload while walking — a static frame can't prove the culling fix"
ok "polish#2 (length, cards-at-distance, chunk instrumentation, moving-capture proof) addressed"
ok "polish items (density, blade reach, card tufts, card wind, pop-in) addressed"

# OWNER POLISH#3 2026-07-10: density++, card tint match, card sway gentler, sloped-surface placement, airborne trample gate
grep -qiE 'densit|dense' "$R" || fail "polish#3: increase near-grass density again"
grep -qiE '(card).*(tint|colou?r|teinte|match).*(near|blade|match)|near.*card.*(colou?r|tint)|seamless colou?r' "$R" || fail "polish#3: distant cards must match the near-grass tint (no colour change with distance)"
grep -qiE '(card).*(sway|swing).*(reduc|gentl|less|lower|match)|sway.*amplitude' "$R" || fail "polish#3: card sway must be reduced to <= near-blade sway"
grep -qiE '(slope|sloped|non.?flat|per.?triangle|surface (height|y)|actual.*(height|ground y)|min.?y)' "$R" || fail "polish#3: grass must follow actual per-triangle surface height on sloped platforms (not a flat/min-Y reference)"
grep -qiE '(airborne|jump|in the air|altitude|jak.?y|above.*(ground|grass)).*(trample|gate|skip|bend)|trample.*(altitude|airborne|jump|jak.?y)' "$R" || fail "polish#3: trample must be gated by Jak altitude (no trample while airborne)"
grep -qiE 'dropped ?= ?0|no.*(drop|regress).*cull|cull.*no regress' "$R" || fail "polish#3: the culling fix (DROPPED=0) must NOT regress"
ok "polish#3 (density, card tint, card sway, sloped placement, airborne trample, culling kept) addressed"

# OWNER POLISH#4 2026-07-10: missing platforms, colour-match-texture, card-dist+adjustable, hide-under-objects, ledge-trample
grep -qiE '(missing|remaining|skipped|other).*(platform|surface)|all.*grass.?textured|why.*(skip|no grass)' "$R" || fail "polish#4: must place grass on the STILL-missing grass-textured platforms"
grep -qiE '(sample|match|derive).*(ground|underlying|floor).*(texture|colou?r)|texture.*colou?r.*(sample|match)|per.?location (tint|colou?r)' "$R" || fail "polish#4: grass colour must sample/match the underlying ground texture (no clash)"
grep -qiE '(adjustable|slider|setting).*(distance|view.?dist)|distance.*(adjustable|slider|setting|recharged setting)' "$R" || fail "polish#4: near-blade + card view-distances must be ADJUSTABLE settings"
grep -qiE '(card).*(further|farther|distance.*(increase|extend|push))|extend.*card.*distance' "$R" || fail "polish#4: card render distance must be pushed further out"
grep -qiE '(hide|cull|mask).*(grass).*(under|overlap|object|model|prop)|overlap.*(object|model).*(hide|cull|grass)' "$R" || fail "polish#4: must hide grass where a non-grass object overlaps the ground"
grep -qiE '(ledge|rebord|hang|grab).*(trample|part|spread|écart)|trample.*(ledge|hang|grab)' "$R" || fail "polish#4: ledge-grab must part the grass like walk-trample"
grep -qiE '(strict|per.?triangle|texture.?id).*(grass|texture).*(filter|match|only|exclude rock)|(rock|non.?grass).*(texture).*(exclude|reject|no grass|skip)' "$R" || fail "polish#4b: PRIMARY filter must be TEXTURE (per-triangle) — rock-textured faces get NO grass regardless of normal (owner clarification)"
ok "polish#4 (missing platforms, colour-match, card-dist+adjustable, hide-under-objects, ledge-trample, no-rock-walls) addressed"

# OWNER POLISH#5 2026-07-10: sliders must SHOW on device, density slider, rock walls clean
grep -qiE '(slider|distance|densit).*(show|visible|appear|device|menu length|live.?length|submenu (row|length))|menu.*(length|row).*(bump|extend|grass)' "$R" || fail "polish#5: distance/density sliders must actually SHOW in the on-device Recharged submenu (bump the live-length) — device screencap proof"
grep -qiE '(densit).*(slider|adjustable|setting|row)' "$R" || fail "polish#5: add an adjustable DENSITY slider in the Recharged submenu"
grep -qiE '(rock|vertical|non.?grass).*(no|zero|clean|excluded|0 blade|fixed)|no blades? on (rock|vertical|wall)' "$R" || fail "polish#5: rock/vertical faces must be CLEAN of grass (still leaking) — prove on the rock-wall beat"
grep -qiE '(submenu|recharged settings).*(screencap|screenshot|device).*(slider|distance|densit)|screencap.*submenu.*(slider|row)' "$R" || fail "polish#5: need a DEVICE screencap of the Recharged submenu SHOWING the distance+density sliders (not code keywords)"
ok "polish#5 (sliders visible on device, density slider, rock walls clean) addressed"

# OWNER POLISH#6 2026-07-10: card density/tint/transition, clip-through-objects, LIGHTING, dedicated grass sub-submenu
grep -qiE '(card).*(densit|tuft).*(reduc|less|lower|match)|reduce.*card' "$R" || fail "polish#6: reduce card density (too tufted vs near grass)"
grep -qiE '(transition|lod boundary|near.?to.?card|blend|fade).*(smooth|blend|fade|seamless)|smooth.*transition' "$R" || fail "polish#6: smooth the near->card LOD transition (no seam/colour jump)"
grep -qiE '(clip|poke|through|overlap).*(object|rock|prop|boulder)|hide.*(object|rock).*(work|fixed|proven)' "$R" || fail "polish#6: grass must NOT clip through ground objects (re-do the hide-under-objects, prove it)"
grep -qiE '(light|éclairage|baked|shadow|brightness|luminos).*(grass|blade|sample|apply|respond|match)|grass.*(light|baked|brightness)' "$R" || fail "polish#6: grass must RESPOND to lighting (sample baked/scene light so it matches the ground brightness)"
grep -qiE '(sub.?sub.?menu|nested.*(menu|submenu)|grass settings (page|submenu|menu))' "$R" || fail "polish#6: must build a dedicated NESTED grass-settings sub-submenu holding all grass settings"
grep -qiE '(screencap|screenshot).*(grass settings|nested|sub.?submenu|grass.?menu)' "$R" || fail "polish#6: need a device screencap of the nested Grass Settings page showing all rows"
ok "polish#6 (card density/tint/transition, no clip-through, lighting response, nested grass menu) addressed"

# OWNER POLISH#7 2026-07-11: clip-halo to visible footprint, clip ALL objects, coverage gaps, LIGHTING re-do
grep -qiE '(halo|ring|empty (zone|ring)).*(object|clip)|clip.*(visible|above.?ground|footprint|intersection|ground level)|(above.?ground|visible).*footprint' "$R" || fail "polish#7: object-clip must use the VISIBLE above-ground footprint (no oversized empty halo from the buried model)"
grep -qiE '(all|every|warp.?gate|button|prop).*(object|clip|overlap)|clip.*(all|every).*object|extend.*(clip|overlap).*object' "$R" || fail "polish#7: overlap-hide must cover ALL objects (warp-gate button, props), not just rocks"
grep -qiE '(coverage|gap|empty (zone|area)|open (area|ground)).*(fill|grass|no object)|fill.*(gap|empty|open)' "$R" || fail "polish#7: must fill coverage gaps (open grass-textured ground with no object still gets grass)"
grep -qiE '(light|lumin|baked|shade|brightness).*(sample|per.?location|match|vary|variation|darken)|grass.*(darken|match).*(ground|shade|light)' "$R" || fail "polish#7: grass lighting must SAMPLE per-location + vary (darken in shade, match ground) — not uniform flashy"
grep -qiE '(lit|shad).*(spot|beat|capture).*(match|brightness|light)|capture.*(lit|shaded)|lit.*and.*shad' "$R" || fail "polish#7: need device captures at a LIT spot AND a SHADED spot proving grass brightness matches the ground"
ok "polish#7 (clip footprint, all-objects, coverage, lighting variation, lit+shaded proof) addressed"

# OWNER POLISH#8 2026-07-11: shrub bald patches, platform edges, PER-INSTANCE (location-aware) lighting
grep -qiE '(shrub).*(alpha|mesh|footprint|occup|bald|around|block|exempt)|alpha.?transparent.*(shrub|block)' "$R" || fail "polish#8: shrubs must not leave bald patches (alpha-transparent shrub mesh must not block grass)"
grep -qiE '(edge|border|margin|bord).*(platform|surface|grass|reach|fill|extend)|reach.*(edge|border)' "$R" || fail "polish#8: grass must reach the EDGES of grass-textured platforms (no bald border margin)"
grep -qiE '(per.?instance|per.?location|per.?blade|world.?pos|location.?aware).*(light|sample|luminance)|light.*(per.?instance|per.?location|world.?pos|location.?aware)' "$R" || fail "polish#8: lighting must be PER-INSTANCE/location-aware (sample local light at each blade world pos), NOT one global value"
grep -qiE '(bright|lit).*(and|vs).*(shad|dark).*(same frame|same beat|differ)|same (frame|beat).*(bright|lit).*(shad|dark)|spatial variation' "$R" || fail "polish#8: prove spatial lighting variation — a bright zone AND shaded zone in the same beat with grass brightness differing"
grep -qiE '(dynamic|per.?frame|time.?of.?day|day.?night|re.?sampl|not frozen|not (static|baked once)).*(light|grass)|light.*(dynamic|per.?frame|time.?of.?day|day.?night|re.?sampl)' "$R" || fail "polish#8b: lighting must be DYNAMIC (track the time-of-day cycle, re-sampled), not sampled-once-and-frozen"
ok "polish#8 (shrub patches, platform edges, per-instance + DYNAMIC lighting, spatial-variation proof) addressed"

# OWNER POLISH#9 2026-07-11: per-triangle edge placement + GROUND baked-light sampling
grep -qiE '(per.?triangle|point.?in.?triangle|triangle (bound|edge|boundary)|inside.*triangle).*(placement|spawn|clip|test)|(no overflow|no.*(hole|bald)).*edge' "$R" || fail "polish#9: edge placement must be per-triangle (point-in-triangle), no block overflow past the edge, no holes at edges"
grep -qiE '(ground|tfrag|floor).*(baked|vertex ?colou?r|lightmap).*(sample|read|apply|match)|baked.*(vertex ?colou?r|lightmap).*(ground|grass|blade)' "$R" || fail "polish#9: must sample the GROUND BAKED light (tfrag vertex colour/lightmap under each blade), not a generic scene light"
grep -qiE '(baked|ground).*(dark).*(grass|blade|match)|grass.*match.*(baked|ground) (dark|light)' "$R" || fail "polish#9: prove the grass matches the ground where the BAKED light is dark (device capture)"
ok "polish#9 (per-triangle edges, ground baked-light sampling, match-dark proof) addressed"

git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "golden pristine"
echo "[Ggrass PASS] 3D grass PoC gated + 3-tier LOD + breeze/trample + device evidence. (owner play-test next)"
