#!/usr/bin/env bash
# preset_ctrl_run.sh — LE CONTROLE POSITIF DE NIVEAU SYSTEME : le preset de MAIA sur la chaine
# de KEIRA. Une seule variable change — le bloc `pk` du fichier livre — et rien d'autre.
#
# PERIMETRE (DIRECTIVES 2026-08-22 23:00) : on ne livre PAS la physique de Maia et on ne touche
# pas a son personnage. Ses chiffres sont un VECTEUR DE TEST sur la chaine de Keira.
#
# CE SCRIPT N'ECRIT NI `keira-room-x86.log` NI `keira-room-table.txt` : la course de controle
# n'est PAS la course livree, et un tableau qui decrirait une configuration qu'on ne livre pas
# serait le defaut du cycle 56 remis en place. Il ecrit vers `--out`, et il RESTAURE le fichier
# de chaines livre quoi qu'il arrive.
set -uo pipefail
cd "$(dirname "$0")/.."
GK=build/game/gk
ISO=out/jak1/iso
LIVRE=recharged_assets/physics_chains.txt
VECT="${1:-/tmp/physics_chains.maia.txt}"
LOG="${2:-/tmp/runB.log}"
SAVE=.autoport/backups/physics_chains.livre.txt
DLOCK=.autoport/.deploy-in-progress
_own_d=0
[ -f "$VECT" ] || { echo "FAIL: vecteur $VECT absent"; exit 1; }
mkdir -p .autoport/backups
cp -f "$LIVRE" "$SAVE"
_restore(){
  cp -f "$SAVE" "$LIVRE"
  [ "${GKPID:-}" ] && kill "$GKPID" 2>/dev/null
  [ "$_own_d" = 1 ] && rm -f "$DLOCK"
  echo "restaure: $LIVRE <- $SAVE ($(md5sum "$LIVRE" | cut -d' ' -f1))"
  return 0
}
trap _restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [ ! -f "$DLOCK" ]; then
  printf 'preset_ctrl_run pid=%s started=%s\n' "$$" "$(date -Is)" > "$DLOCK"; _own_d=1
fi
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
cp -f recharged_assets/hd_anim/keira-hd-ag.go out/jak1/obj/ || { echo "FAIL: ag absent"; exit 1; }
cp -f "$VECT" "$LIVRE"
echo "vecteur pose: $(md5sum "$LIVRE" | cut -d' ' -f1)"
: > "$LOG"
OG_PHYS_ROOM=1 OG_PHYS_ROOM_DELAY="${OG_PHYS_ROOM_DELAY:-600}" \
  stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
  -iso-data "$ISO" -- -boot -debug-mem > "$LOG" 2>&1 &
GKPID=$!
echo "gk pid=$GKPID log=$LOG"
ok=0
for i in $(seq 1 "${ROOM_TIMEOUT:-1800}"); do
  kill -0 "$GKPID" 2>/dev/null || { echo "gk arrete apres ${i}s"; break; }
  if grep -aq '^PHYSEND' "$LOG" 2>/dev/null; then ok=1; echo "PHYSEND apres ${i}s"; break; fi
  sleep 1
done
kill "$GKPID" 2>/dev/null
for i in $(seq 1 10); do kill -0 "$GKPID" 2>/dev/null || break; sleep 1; done
kill -9 "$GKPID" 2>/dev/null
grep -a "PHYSPSET" "$LOG" | head -6
[ "$ok" = 1 ] || { echo "FAIL: PHYSEND jamais atteint"; exit 1; }
echo "OK  ($(stat -c '%s' "$LOG") octets)"
