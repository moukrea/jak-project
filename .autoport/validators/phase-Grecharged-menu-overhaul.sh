#!/usr/bin/env bash
set -uo pipefail
R=".autoport/reports/Grecharged-menu-overhaul/report.txt"
fail(){ echo "[Gmenus FAIL] $*" >&2; exit 1; }
[ -f "$R" ] || fail "no report"
grep -qE '^RESULT: PASS' "$R" || fail "no RESULT: PASS (WIP does not gate)"
# ordering: the freecam v2 phase must be closed first (shared files)
python3 -c "
import json,sys; s=json.load(open('.autoport/state.json'))
sys.exit(0 if 'Grecharged-mesh-browser' in (s.get('completed') or []) or 'Grecharged-mesh-browser' in (s.get('validator_passed') or []) else 1)
" || fail "mesh-browser v2 not closed — same menu files, do not interleave"
# title screen conditional
grep -qiE 'continuer|continue' "$R" || fail "no Continue entry"
grep -qiE '(no save|aucune sauvegarde)[^.]{0,80}(new game|nouvelle partie)[^.]{0,60}(first|premier|hidden|cach)' "$R" || fail "no-save ordering (New first, Load hidden) not evidenced"
grep -qiE '(load|charger)[^.]{0,60}(first|premier)[^.]{0,60}(save|sauvegarde)' "$R" || fail "with-saves ordering (Load/Continue first) not evidenced"
grep -qiE '(quit|quitter)[^.]{0,80}(title|titre)[^.]{0,60}(quit|jeu|game)' "$R" || fail "quit flow (title return / full quit) not evidenced"
# unified options — ONE graphics zone, organized BY FUNCTION not by origin (owner 2026-08-01)
for c in JOUABILITE GRAPHISMES AUDIO COMMANDES DEBUG; do
  grep -qiE "$c" "$R" || fail "category $c missing from the new 5-category tree"
done
# AFFICHAGE + RENDU must be FUSED into GRAPHISMES — origin-based split is BANNED
grep -qiE '(affichage.{0,12}rendu|rendu.{0,12}affichage)[^.]{0,90}(fusion|merged|unifi|une seule|single)' "$R" \
  || grep -qiE '(fusion|fused|merged|unifi|une seule)[^.]{0,90}graphism' "$R" \
  || fail "AFFICHAGE and RENDU not fused into a single GRAPHISMES zone (origin split still present)"
grep -qiE '(fonction|function)[^.]{0,70}(pas|not|jamais|never|non)[^.]{0,30}(origine|origin)' "$R" \
  || fail "the by-FUNCTION-not-by-ORIGIN principle is not evidenced in the report"
# GRAPHISMES function subsections — recharged rows woven in beside the original ones
for g in "ecran|écran|screen" "performance" "materi|matéri|material" "eclair|éclair|light" "veget|végét|foliage|grass" "interface|hud"; do
  grep -qiE "$g" "$R" || fail "GRAPHISMES function subsection missing: $g"
done
grep -qiE '(master|recharged)[^.]{0,70}(tete|tête|head|top|haut)[^.]{0,70}graphism' "$R" \
  || fail "Recharged MASTER not at the head of the unified GRAPHISMES zone"
grep -qiE 'group header|en-tete de groupe|header row|non[- ]selectable' "$R" || fail "group headers not implemented"
grep -qiE '(live|visible)[^.]{0,50}(value|valeur)[^.]{0,60}(100 ?%|every row|toutes les lignes)' "$R" || fail "live value display not proven on 100% of rows"
grep -qiE 'hint' "$R" || fail "hints line not implemented"
# owner decisions
grep -qiE 'display mode[^.]{0,80}(restored|retabli)' "$R" || fail "Android-hidden rows not restored"
grep -qiE 'sans effet sur mobile|no effect on mobile' "$R" || fail "restored rows lack the mobile hint"
grep -qiE 'FLAG_DEBUG_MENUS|--debug' "$R" || fail "the --debug build flag gating the Debug category is not evidenced"
grep -qiE '(hidden|cache)[^.]{0,50}(not (removed|stripped)|pas supprime)' "$R" || fail "Debug must be hidden-not-removed in final builds"
grep -qiE 'ENG[ ,].*FRE[ ,].*GER[ ,].*ITA[ ,].*JAP[ ,].*SPA|6 (langues|languages)' "$R" || fail "full 6-language coverage of new labels/hints not evidenced"
grep -qiE '(mapping|correspondance|old *-> *new|ancien.*nouveau)' "$R" || fail "no old->new location mapping for every existing row (the 'user not lost' guard)"
grep -qiE 'recharged[^.]{0,90}(dissol|dissous|integr|ventil|woven|fondu)[^.]{0,90}(fonction|function|materi|matéri|eclair|éclair|veget|végét|graphism)' "$R" || fail "Recharged settings not integrated BY FUNCTION into GRAPHISMES (must NOT be a separate RENDU category)"
grep -qiE 'menu-tree' "$R" || fail "menu-tree.md not rewritten"
grep -qiE '(persist|prefs|sauvegarde des reglages)[^.]{0,60}(kept|conserve|unchanged|intact)' "$R" || fail "settings persistence keys not proven kept"
# ---- V2 VISUAL REDESIGN (owner 2026-08-02 reopen): hologram menu projected by the comm ship ----
grep -qiE '(hint)[^.]{0,80}(on-?screen|dans l.?ecran|visible|within|bornes)[^.]{0,80}(pause|main|titre|title|tous|all)' "$R" \
  || fail "V2: off-screen hint bug on the main/pause menu not proven fixed (hint Y within screen bounds on all screens)"
grep -qiE '(hint)[^.]{0,80}(derived|derive|calcul|relative|from)[^.]{0,60}(container|cadre|conteneur|holo|frame)' "$R" \
  || fail "V2: hint Y not derived from the menu container frame (still a magic constant)"
grep -qiE '(100 ?%|every row|toutes les lignes|chaque ligne)[^.]{0,60}(hint)' "$R" \
  || fail "V2: hints not on 100% of rows (need a per-screen with-hint == total counter)"
grep -qiE '(section)[^.]{0,80}(distinct|hierarch|hiérarch|indent|retrait|underlin|soulign|not.*item|pas.*item)' "$R" \
  || fail "V2: group headers still read as items — sections must be visually distinct (hierarchy)"
grep -qiE '(hublot|porthole|orange)[^.]{0,80}(removed|supprim|retir|drop|no longer|plus de|gone)' "$R" \
  || fail "V2: porthole texture / orange overlay not proven removed from the menu draw path"
grep -qiE '(holo)[^.]{0,90}(<=? ?0?\.5|50 ?%|half|moiti|moitié)[^.]{0,60}(width|largeur|screen|ecran|écran)' "$R" \
  || fail "V2: hologram container width not proven <= half screen width"
grep -qiE '(holo)[^.]{0,80}(left|gauche)[^.]{0,80}(margin|marge)' "$R" \
  || fail "V2: hologram not left-aligned with margins from the edges"
grep -qiE '(holo)[^.]{0,80}(draw|render)[^.]{0,40}(count|compteur|> ?0|per.?frame)' "$R" \
  || fail "V2: no per-frame draw proof that the hologram frame renders while the menu is open"
grep -qiE '(ship|vaisseau|drone|projector|projecteur)[^.]{0,80}(spawn|apparai|despawn|open|ferm|close)[^.]{0,60}(menu|count|compteur)' "$R" \
  || fail "V2: comm-ship projector not proven spawned on menu open / despawned on close"
grep -qiE '(ship|vaisseau|drone)[^.]{0,80}(orbit|orbite|around|autour)[^.]{0,80}(orient|face|vers|toward|center|centre)' "$R" \
  || fail "V2: ship does not orbit while oriented toward the hologram center (per-frame transform)"
grep -qiE '(beam|faisceau)[^.]{0,80}(draw|render|dessin)[^.]{0,40}(count|compteur|> ?0)' "$R" \
  || fail "V2: projection light beam not proven drawn"
# ---- V3 (owner rejected V2 "bâclé"): CODE-level checks, not report keywords ----
# A. generic type-fallback hints must be DELETED from the text banks (objective)
FRTX="game/assets/jak1/text/game_custom_text_fr-FR.json"
if [ -f "$FRTX" ]; then
  grep -qiE 'PARCOURS LES CHOIX|R.GLE CETTE VALEUR' "$FRTX" \
    && fail "V3-A: generic type-fallback hints still present in fr-FR text bank (must be deleted; every row needs a bespoke hint)"
fi
grep -qiE '(0 (row|ligne)|aucune ligne|no row)[^.]{0,80}(generic|generique|générique|par.?type|type.?fallback)' "$R" \
  || fail "V3-A: report must prove 0 rows use a generic/by-type hint (every row bespoke: what + impact)"
grep -qiE '(hint)[^.]{0,80}(impact|consequence|conséquence|what.*change|ce que.*change|perf)' "$R" \
  || fail "V3-A: hints must explain the setting AND its impact, not the control type"
# B. hologram flicker/scanlines must be ANIMATED (frame/time-driven), not static
grep -qiE '(flicker|scanline)[^.]{0,90}(per.?frame|chaque frame|frame.?count|time|animat|advanc|avance|defil|défil)' "$R" \
  || fail "V3-B: hologram flicker/scanlines not proven ANIMATED per-frame (must not be static lines)"
grep -qiE 'progress-pc.gc' "$R" && grep -qniE 'flicker|scanline|holo.*noise|rim|glow' goal_src/jak1/pc/progress-pc.gc >/dev/null \
  || fail "V3-B: no flicker/scanline/rim-glow code in the holo draw path"
# C. drone must be a real 3D entity/process (not a 2D HUD sprite), visible in-frustum
grep -qiE '(drone|ship|projector|projecteur)[^.]{0,90}(entity|process|3d|world|monde|frustum|in.?view|devant la cam)' "$R" \
  || fail "V3-C: comm-drone not proven a real 3D entity in-frustum (was a 2D HUD sprite)"
grep -qiE '(drone|ship|projector)[^.]{0,80}(2d|hud|sprite)[^.]{0,40}(only|seul|instead|au lieu)' "$R" \
  && fail "V3-C: drone is still a 2D HUD sprite — must be a 3D entity orbiting in the scene"
# D. sections spatially separated (gap + indent constant), not inline colored rows
grep -qiE '(section|group)[^.]{0,80}(gap|espace|spacing|indent|retrait)[^.]{0,40}(constant|defconstant|px|pixel)' "$R" \
  || fail "V3-D: sections not spatially separated (need an inter-section gap + option indent constant)"
# E. porthole removed from the PAUSE menu specifically
grep -qiE '(hublot|porthole|window|fenetre|fenêtre)[^.]{0,80}(pause)[^.]{0,60}(removed|supprim|retir|remplac|replac|gone|plus)' "$R" \
  || fail "V3-E: porthole background not proven removed from the PAUSE menu (owner still sees it)"
# ---- V4 (owner 3rd visual reject 'AI slop'): replicate Jak2 holo + layout fixes ----
grep -qiE '(jak2|jak 2)[^.]{0,90}(replic|repliqu|copie|copied|port|ported|reuse|reprend)[^.]{0,60}(holo|menu|scanline|font)' "$R" \
  || fail "V4: report must prove the Jak2 menu/holo rendering was REPLICATED from goal_src/jak2, not re-approximated"
grep -qiE '(text|texte)[^.]{0,60}(center|centr)[^.]{0,60}(holo|frame|cadre)' "$R" || fail "V4: menu text not centered in the holo frame"
grep -qiE '(line|ligne|row)[^.]{0,50}(spacing|espacement|interligne|pitch)[^.]{0,50}(reduc|resserr|tight|smaller|diminu)' "$R" || fail "V4: line spacing not tightened"
grep -qiE '(hint)[^.]{0,60}(clamp|clamped|within|dans|inside|borne)[^.]{0,50}(holo|frame|cadre)' "$R" || fail "V4: hint not clamped inside the holo frame (was escaping)"
grep -qiE '(font|texte|text)[^.]{0,70}(holo|scanlin|tint|teint|projection)[^.]{0,50}(integr|part|rendu avec|with)' "$R" || fail "V4: font not rendered as part of the holo effect"
grep -qiE '(drone|ship|projector)[^.]{0,70}(visible|on-?screen|a l.?ecran|frustum|render)[^.]{0,40}(orbit|beam|faisceau)' "$R" || fail "V4: drone+beam still not proven visibly orbiting/projecting"
grep -qiE 'eae4df44' "$R" || fail "V3-CRASH: no DEVICE boot proof (report must show a real boot on Redmi eae4df44, not a desktop smoke)"
grep -qiE '(exit-info|pid)[^.]{0,80}(alive|vivant|no.*crash|pas.*crash|reason ?!?= ?5|no reason.?5|clean)' "$R" \
  || fail "V3-CRASH: report must prove the device boot is crash-free (exit-info no reason=5 + pid alive at t+150s on eae4df44)"
grep -qiE '(press|appu|inject|cpad).{0,40}start' "$R" || fail "V4-CRASH: device proof must PRESS START to OPEN the menu, not just boot to title (SIGSEGV ee_base-4 was on menu-open)"
grep -qiE '(menu|options|graphism)[^.]{0,70}(open|ouvert|navig|alive|vivant|no.?crash|pas.*crash|survi)' "$R" || fail "V4-CRASH: no proof the MENU actually OPENS without crashing on device"
grep -qiE 'gk_crash' "$R" || fail "V4-CRASH: report must show files/gk_crash.txt state AFTER opening the menu (absent/unchanged = no new SIGSEGV)"
grep -qiE 'capture (sweep|campaign)|pixel (statistics|fraction)' "$R" && fail "in-game visual measurement detected — banned"
echo "[Gmenus PASS]"
