#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
TAG="Gplayability-input-and-loadgate"
REP=".autoport/reports/$TAG/report.txt"
F=0
fail(){ F=$((F+1)); echo "[$TAG FAIL] $1"; }
ok(){ echo "[$TAG ok] $1"; }

# 1. Le bouton A doit arriver jusqu'au moteur. Preuve : une trace le montrant.
if [ -f "$REP" ] && grep -qE 'sdl_button=0' "$REP"; then
  ok "le bouton A (index SDL 0) atteint le moteur, trace publiee"
else
  fail "aucune trace 'sdl_button=0' dans $REP — rien ne prouve que le bouton de saut arrive"
fi

# 2. La cause doit avoir ete etablie par MESURE cote manette, pas devinee.
if [ -f "$REP" ] && grep -qiE 'getevent|EV_KEY|code 30[4-9]|BTN_' "$REP"; then
  ok "la cause est etablie par une mesure cote peripherique"
else
  fail "aucune mesure cote manette (getevent / EV_KEY / BTN_) dans $REP — ne pas deviner l'index"
fi

# 3. Barriere de chargement : elle doit exister dans le code.
if grep -rqE 'load_gate|loading_barrier|wait_for_level_ready|scene_ready' game/ common/ --include=*.cpp --include=*.h 2>/dev/null; then
  ok "une barriere de chargement existe dans le moteur"
else
  fail "aucune barriere de chargement — la scene demarre toujours sans attendre ses donnees"
fi

# 4. L'ecart son/image doit etre chiffre avant/apres sur la MEME sequence.
if [ -f "$REP" ] && grep -qiE 'ecart|delta|decalage' "$REP" && grep -qiE 'ms' "$REP" \
   && grep -qiE 'avant' "$REP" && grep -qiE 'apres' "$REP"; then
  ok "l'ecart son/image est chiffre avant/apres"
else
  fail "aucun ecart son/image chiffre avant/apres, en ms, sur la meme sequence, dans $REP"
fi

# 5. Non-regression des acquis memoire et chargement.
if [ -f "$REP" ]; then
  M=$(grep -oiE '(pic|peak|rss)[^0-9]{0,12}([0-9]{3,5})' "$REP" | grep -oE '[0-9]{3,5}' | sort -rn | head -1)
  if [ -n "${M:-}" ] && [ "$M" -le 900 ]; then
    ok "pic memoire ${M} Mo (<= 900, l'acquis tient)"
  else
    fail "pic memoire ${M:-inconnu} Mo — l'acquis valide etait 817 Mo sur la Shield, ne pas le perdre"
  fi
else
  fail "aucun rapport dans $REP"
fi

[ "$F" -gt 0 ] && { echo "[$TAG] $F verdict(s) en echec"; exit 1; }
echo "[$TAG] toutes les gates passent"
exit 0
