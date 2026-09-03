#!/usr/bin/env bash
# gfu_font_live_proof.sh — PREUVE SUR L'APPAREIL que (a) le jeu demarre avec la
# nouvelle police et (b) les deux atlas Urbanist sont REELLEMENT charges par le
# telephone. Android a sa propre boucle de frame : la presence du code sur x86 ne
# prouve rien ici, seule une trace de l'appareil compte.
#
# POURQUOI ON STREAME AU LIEU D'ECHANTILLONNER — defaut d'instrument paye une fois :
# une premiere version lisait `logcat -d -t 4000` APRES coup et rapportait
# « 0 remplacement », donc un FAUX ROUGE. Le remplacement de texture sort au
# CHARGEMENT (t+10 s) et la course produit ~16 000 lignes : les lignes cherchees
# etaient deja sorties du tampon. Un evenement de DEMARRAGE se capture depuis AVANT
# le lancement, jamais dans un instantane borne pris ensuite.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=${ADB:-/home/emeric/Android/platform-tools/adb}
S=${1:-eae4df44}; P=org.opengoal.gk.jak1
RAW=${RAW:-.autoport/reports/Gfont-urbanist/logcat-full.txt}
mkdir -p "$(dirname "$RAW")"
trap 'bash .autoport/device_teardown.sh >/dev/null 2>&1 || true' EXIT

$ADB -s $S shell am force-stop $P >/dev/null 2>&1
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
$ADB -s $S exec-out run-as $P rm -f files/gk_crash.txt >/dev/null 2>&1
$ADB -s $S shell logcat -c >/dev/null 2>&1
( $ADB -s $S shell logcat -v time > "$RAW" 2>&1 ) & LPID=$!
sleep 2
COMP=$($ADB -s $S shell cmd package resolve-activity --brief $P 2>/dev/null | tr -d '\r' | grep "^${P}/" | head -1)
[ -n "$COMP" ] || COMP="$P/org.opengoal.gk.LoaderActivity"
$ADB -s $S shell am start -n "$COMP" >/dev/null 2>&1
echo "lancement $COMP — capture continue 180 s"
sleep 180
PID=$($ADB -s $S shell pidof $P | tr -d '\r')
CRASH=$($ADB -s $S exec-out run-as $P sh -c 'ls files/gk_crash.txt 2>/dev/null' | tr -d '\r' | grep -c gk_crash || true)
kill $LPID 2>/dev/null; wait $LPID 2>/dev/null
$ADB -s $S shell am force-stop $P >/dev/null 2>&1

NB=$(grep -ac 'A35-RENDER frame=' "$RAW" || true)
NG=$(grep -ac 'master-mode=game' "$RAW" || true)
NF=$(grep -a 'custom texture replacement' "$RAW" | grep -ac gamefontnew || true)
echo "lignes capturees : $(wc -l < "$RAW")"
echo "--- (a) demarrage ---"; grep -am1 'A35-RENDER frame=' "$RAW"; grep -am1 'master-mode=game' "$RAW"
echo "pid=$PID gk_crash=$CRASH frames=$NB game=$NG"
echo "--- (b) atlas Urbanist charges sur l'appareil ---"
grep -a 'custom texture replacement' "$RAW" | grep -a gamefontnew
echo "remplacements de police : $NF (attendu 2 : ascii.12lo + ascii.24lo)"
[ "$NB" -gt 0 ] && [ "$NG" -gt 0 ] && [ "$NF" -eq 2 ] && [ "$CRASH" -eq 0 ] && [ -n "$PID" ] \
  && { echo "PREUVE APPAREIL OK"; exit 0; }
echo "PREUVE APPAREIL ECHOUEE"; exit 1
