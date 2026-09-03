#!/usr/bin/env bash
# Phase Gtext-tone — LA VALEUR REELLEMENT UTILISEE, lue A L'EXECUTION.
#
# Le validateur de la phase exige de publier « les valeurs REELLEMENT utilisees a cote de
# celles de la table ». Lire le JSON source ne repond pas : le dossier a livre pendant 17
# jours une COPIE GELEE du texte (commit a137796a4a), PC juste et telephone faux, MEME commit.
# Decoder la banque construite (.autoport/gtt_bank_probe.py) repond a moitie : ca prouve
# l'octet livre, pas que le programme le RESOUT sur cet id-la.
#
# Ce script fait parler LE JEU. On demarre `gk` x86, on branche `goalc` en ecouteur, et on
# appelle la methode que le jeu appelle lui-meme pour afficher un texte :
#
#     (lookup-text! *common-text* (text-id press-start) #f)
#
# `format 0` ecrit dans la sortie standard de `gk` (patron deja employe par
# .autoport/ghint_x86.sh:51), qu'on relit ensuite. La chaine publiee est donc celle qui part
# vers `print-game-text`, pas une lecture de fichier faite a cote.
#
# On repete pour chaque langue en posant `(-> *pc-settings* text-language)` puis en appelant
# `load-game-text-info` (engine/ui/text.gc:186) — exactement ce que fait le menu de langue.
#
# `(build-game)` est envoye AVANT toute evaluation : goalc ne connait les symboles ni les
# signatures (`*common-text*`, `lookup-text!`, l'enum `text-id`) qu'apres avoir compile les
# sources. Sans lui, chaque forme envoyee echoue a la compilation et RIEN n'arrive au jeu —
# mesure : 0 ligne capturee, controle negatif muet. C'est le patron de .autoport/ghint_x86.sh.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

GK=${GK:-build-x86/game/gk}
GOALC=${GOALC:-build/goalc/goalc}
ISO=${ISO:-out/jak1/iso}
OUT=${1:-.autoport/reports/Gtext-tone/runtime-lookup.txt}

fail(){ echo "[rt] FATAL: $*" >&2; exit 1; }
[ -x "$GK" ] || fail "no $GK"
[ -x "$GOALC" ] || fail "no $GOALC"

# UN SEUL ECRIVAIN : si un constructeur reecrit out/jak1/iso pendant la course, ce qu'on lit
# n'est plus ce qu'on croit mesurer.
pgrep -f "build_arm64_full_consistent|gtt_build_android_text" >/dev/null \
  && fail "un constructeur ecrit dans $ISO — mesure refusee"

# Les ids du lot, avec leur nom symbolique (engine/ui/text-h.gc) : on interroge par NOM, donc
# une erreur d'id ne peut pas passer inapercue — le compilateur refuserait un nom inconnu.
IDS="press-start move-dpad select-file-to-save select-file-to-load insert-memcard \
memcard-space-requirement2 memcard-do-not-remove autosave-disabled-msg check-memcard \
autosave-warn-msg check-memcard-and-retry no-disc-msg bad-disc-msg"

LOGDIR=.autoport/reports/Gtext-tone; mkdir -p "$LOGDIR"
GKLOG="$LOGDIR/runtime-gk.log"; GCLOG="$LOGDIR/runtime-goalc.log"
: > "$GKLOG"; : > "$GCLOG"
FIFO=$(mktemp -u); mkfifo "$FIFO"
GCPID=""
cleanup(){ exec 3>&- 2>/dev/null || true; [ -n "$GCPID" ] && kill "$GCPID" 2>/dev/null; kill "$GKPID" 2>/dev/null; wait 2>/dev/null; rm -f "$FIFO"; }
trap cleanup EXIT

echo "[rt] demarrage de gk (log $GKLOG)"
# stdbuf -oL : la sortie de gk est BLOQUEE EN BLOCS quand elle est redirigee vers un fichier.
# Sans ca, les lignes `format 0` ne touchent le disque qu'a la mort du processus — et le
# comptage, fait avant, lisait 0 ligne alors que 70 etaient bien produites. Faux ROUGE.
stdbuf -oL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
for i in $(seq 1 90); do
  kill -0 "$GKPID" 2>/dev/null || { echo "[rt] gk est mort au demarrage"; tail -20 "$GKLOG"; exit 1; }
  grep -qE "link finish: logo($|-)" "$GKLOG" && { echo "[rt] demarre en ~${i}s"; break; }
  sleep 1
done
grep -qE "link finish: logo($|-)" "$GKLOG" || fail "gk n'a jamais atteint 'link finish: logo'"
sleep 3

timeout 300 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
sleep 5
echo "[rt] (build-game) — necessaire pour que goalc connaisse les symboles"
echo '(build-game)' >&3
for i in $(seq 1 300); do
  sleep 1
  grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && { echo "[rt] build-game fini en ~${i}s"; break; }
done
grep -qiE "Successfully built all|Build Successful" "$GCLOG" || { echo "[rt] build-game n'a pas abouti; fin de $GCLOG :"; tail -25 "$GCLOG"; fail "build-game"; }
sleep 4

# Controle NEGATIF, tire en premier : un id qui n'existe pas doit rendre "UNKNOWN ID ..."
# (engine/ui/text.gc:106). S'il rend autre chose, l'instrument ne lit pas ce qu'on croit.
echo '(format 0 "GTT-CTRL ~S~%" (lookup-text! *common-text* (the text-id 4095) #f))' >&3
sleep 2

for L in "0 en-US" "1 fr-FR" "2 de-DE" "3 es-ES" "4 it-IT"; do
  set -- $L; N=$1; TAG=$2
  echo "[rt] langue $N ($TAG)"
  echo "(set! (-> *pc-settings* text-language) (the pc-language $N))" >&3
  echo "(load-game-text-info \"common\" '*common-text* *common-text-heap*)" >&3
  sleep 2
  # on republie la langue REELLEMENT chargee par la banque, pas celle qu'on a demandee :
  # si le chargement echoue en silence, les deux nombres divergent et ca se voit.
  echo "(format 0 \"GTT-LANG $TAG demandee=$N chargee=~D~%\" (-> *common-text* language-id))" >&3
  for S in $IDS; do
    echo "(format 0 \"GTT $TAG $S ~S~%\" (lookup-text! *common-text* (text-id $S) #f))" >&3
  done
  sleep 3
done
sleep 3
echo "[rt] fermeture du tuyau et arret de gk (derniere vidange de tampon)"
exec 3>&-
[ -n "$GCPID" ] && kill "$GCPID" 2>/dev/null
kill -TERM "$GKPID" 2>/dev/null
wait "$GKPID" 2>/dev/null
sleep 1

mkdir -p "$(dirname "$OUT")"
{
  echo "# Gtext-tone — lookup-text! LU A L'EXECUTION sur gk x86"
  echo "# gk=$GK  iso-data=$ISO  $(date -Is)"
  echo "# Chaque ligne est la valeur rendue par (lookup-text! *common-text* (text-id <nom>) #f),"
  echo "# imprimee par le jeu lui-meme via (format 0 ...). Interrogation par NOM SYMBOLIQUE."
  echo "#"
  grep -a "^GTT-CTRL" "$GKLOG" | sed 's/^/# controle negatif (id inexistant) : /'
  echo ""
  grep -aE "^GTT( |-LANG)" "$GKLOG"
} > "$OUT"

# `~S` imprime le CONTENU de la chaine, sans guillemets : ne pas en exiger.
CTRL=$(grep -ac "^GTT-CTRL UNKNOWN ID 4095" "$GKLOG")
N=$(grep -ac "^GTT " "$GKLOG")
echo "[rt] lignes de resolution capturees : $N   controle negatif tire : $CTRL"
if [ "$CTRL" -lt 1 ]; then echo "[rt] --- fin de $GCLOG ---"; tail -30 "$GCLOG"; fi
[ "$CTRL" -ge 1 ] || fail "le controle negatif n'a PAS tire — l'instrument ne lit pas lookup-text!"
[ "$N" -ge 60 ] || fail "seulement $N lignes capturees (attendu >= 60) — la course n'a pas abouti"
echo "[rt] -> $OUT"
