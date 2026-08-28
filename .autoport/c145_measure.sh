#!/usr/bin/env bash
# c145_measure.sh — UNE SEULE FENETRE, TENUE DU DEBUT A LA FIN, POUR CONSTRUIRE PUIS MESURER.
#
# Cycle 144. La course precedente est morte en 17 s (SIGILL en edition de liens) parce que
# l'auto-constructeur a reecrit `out/jak1/iso/` entre la fin de mon `(mi)` et le demarrage de `gk`.
# Le verrou `.deploy-in-progress` etait pose — trop tard : le constructeur ne le consulte qu'au
# SOMMET de son cycle (auto_build_apk.sh:290), et un cycle deja parti va jusqu'au bout.
#
# La fenetre construction+mesure est donc UNE SEULE SECTION CRITIQUE, tenue par UN detenteur VIVANT
# (convention DIRECTIVES 2026-08-14 07:10 : PID + horodatage, jamais un `touch` nu ; nettoyage par
# trap, et on ne retire QUE le verrou qu'on a pose soi-meme).
set -uo pipefail
cd "$(dirname "$0")/.."
ISO=out/jak1/iso
LOCK=.autoport/.deploy-in-progress
OUT=.autoport/reports/Grecharged-secondary-motion

_own=0
_stale(){ [ -f "$1" ] || return 0
          local p; p=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$1" | head -1)
          [ -n "$p" ] || return 0
          kill -0 "$p" 2>/dev/null && return 1 || return 0; }
if _stale "$LOCK"; then
  printf 'c145_measure pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"; _own=1
else
  echo "FAIL: verrou de livraison detenu par un processus VIVANT ($(cat "$LOCK")) — on n'ecrase pas."; exit 1
fi
trap '[ "$_own" = 1 ] && rm -f "$LOCK"; return 0 2>/dev/null || true' EXIT

_iso_stamp(){ md5sum "$ISO/GAME.CGO" "$ISO/KERNEL.CGO" 2>/dev/null | cut -d' ' -f1 | tr '\n' ' '; }

# 1. attendre la FIN du cycle de constructeur deja parti (le verrou ci-dessus arrete le suivant)
echo "== attente d'un arbre calme (verrou pose, pid=$$) =="
q=0
for i in $(seq 1 240); do
  s1=$(_iso_stamp); sleep 5
  if [ -n "$s1" ] && [ "$s1" = "$(_iso_stamp)" ] && ! pgrep -x goalc >/dev/null 2>&1; then
    q=1; echo "arbre calme apres $(( i * 5 ))s"; break
  fi
done
[ "$q" = 1 ] || { echo "FAIL: l'arbre ne se calme pas apres 20 min"; exit 1; }

# 2. la construction documentee par le lanceur de salle, dans la fenetre tenue
echo "== (mi) =="
./build/goalc/goalc --user-auto --game jak1 -c '(mi)' > /tmp/c145_mi.log 2>&1
rc=$?; tail -2 /tmp/c145_mi.log
[ "$rc" = 0 ] || { echo "FAIL: (mi) a echoue (rc=$rc)"; exit 1; }
echo "empreinte ISO apres build : $(_iso_stamp)"

# 3. la course, dans la MEME fenetre — le lanceur voit le verrou vivant, le laisse en place
echo "== salle de test =="
ROOM_TIMEOUT=2400 bash .autoport/keira_room_x86.sh
echo "room rc=$?"
