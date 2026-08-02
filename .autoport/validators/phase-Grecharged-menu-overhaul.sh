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
grep -qiE 'boot|smoke|no crash' "$R" || fail "no smoke run"
grep -qiE 'capture (sweep|campaign)|pixel (statistics|fraction)' "$R" && fail "in-game visual measurement detected — banned"
echo "[Gmenus PASS]"
