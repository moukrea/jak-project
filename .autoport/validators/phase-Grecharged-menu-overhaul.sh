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
grep -qiE 'boot|smoke|no crash' "$R" || fail "no smoke run"
grep -qiE 'capture (sweep|campaign)|pixel (statistics|fraction)' "$R" && fail "in-game visual measurement detected — banned"
echo "[Gmenus PASS]"
