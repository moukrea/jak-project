#!/usr/bin/env bash
# gprd_x86_leg.sh — phase Gpbr-props-reach-draw, une JAMBE x86 (un processus gk PAR NIVEAU).
#
# CE QU'ELLE MESURE. Pour chaque MATIERE rencontree a un draw : quelle entree de surfaces.json a
# ete trouvee, quelles valeurs sont RELUES dans l'objet programme GL (glGetUniformfv, pas nos
# variables), et si un draw les portait. Lignes PBRREACH / PBRVAL, produites par
# custom_tex::pbr_reach_section() et ecrites dans pbr_tan_diag.txt par kmachine — le meme canal
# pullable que l'appareil utilise deja.
#
# UN PROCESSUS PAR NIVEAU, ET C'EST UNE CORRECTION MESUREE. Les jambes A et A2 envoyaient les
# warps successifs au listener goalc — `(start 'play (get-continue-by-name ...))` puis
# `(initialize! *game-info* 'game #f "beach-start")`. Les deux sont partis sans une seule erreur
# et le journal ne montre QU'UN niveau charge (`level village1 has 10 PBR material(s)`, zero
# `link finish: beach*`). Un warp qui ne charge rien et ne dit rien est un faux denominateur : la
# couverture aurait ete publiee pour trois niveaux en n'en mesurant qu'un. On passe donc par
# OG_LEVEL_WARP (kmachine.cpp:5341), le meme chemin que l'appareil, un niveau par processus.
#
# DEUX AXES :
#   GPRD_PACK=on|off   off = les 14 rpacks du PACK GERE sont mis de cote, surfaces.json RESTE.
#                      C'est la configuration d'un joueur qui a la table (quelques Ko, livree en
#                      « extra » separe des shards — AssetPackDownloader.java:164-210) et PAS les
#                      223 Mo de cartes. Sans le bit 256, aucune de ses 172 matieres ne peut
#                      atteindre le chemin PBR : c'est la jambe qui le prouve.
#   GPRD_MM=0|1        1 = OG_MM_ON force la ligne de menu MODERN MATERIALS (livree a OFF).
#                      clearcoat et aniso ne franchissent u_mm_flags que derriere elle.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
REPO=$(pwd)
TAG=${1:?usage: gprd_x86_leg.sh <tag>}
GK=${GK:-build-x86/game/gk}
ISO=${ISO:-out/jak1/iso}
PACK=${GPRD_PACK:-on}
MM=${GPRD_MM:-0}
CONTS=${GPRD_CONTS:-village1-hut beach-start jungle-start}
HOLD=${GPRD_HOLD:-40}
OUT=.autoport/reports/Gpbr-props-reach-draw
mkdir -p "$OUT"
# Le recensement a son PROPRE fichier : pbr_tan_diag.txt a deux ecrivains qui s'ecrasent.
DIAG="$REPO/pbr_reach.txt"
export DISPLAY="${DISPLAY:-:0}"
export OG_MM_ON="$MM"

STASH=""
restore_pack() {
  if [ -n "$STASH" ] && [ -d "$STASH" ]; then
    mv "$STASH"/* managed_assets/jak1/ 2>/dev/null || true
    rmdir "$STASH" 2>/dev/null || true
    echo "[gprd] pack restaure ($(ls managed_assets/jak1/*.rpack 2>/dev/null | wc -l) rpack)"
  fi
}
trap restore_pack EXIT
if [ "$PACK" = off ]; then
  STASH=$(mktemp -d /tmp/gprd_pack_XXXXXX)
  mv managed_assets/jak1/*.rpack "$STASH"/ 2>/dev/null || true
  mv managed_assets/jak1/state.json "$STASH"/ 2>/dev/null || true
  echo "[gprd] PACK GERE mis de cote dans $STASH ($(ls "$STASH" | wc -l) fichiers) ; surfaces.json CONSERVE"
fi

LEG="$OUT/leg_$TAG.txt"
{
  echo "===== JAMBE $TAG  (pack=$PACK  modern-materials=$MM  niveaux='$CONTS'  hold=${HOLD}s) ====="
  echo "gk=$(ls -l --time-style=+%F' '%T "$GK" | awk '{print $6, $7}')  rpacks presents=$(ls managed_assets/jak1/*.rpack 2>/dev/null | wc -l)  surfaces.json=$( [ -f managed_assets/jak1/surfaces.json ] && echo present || echo ABSENT)"
} > "$LEG"

for C in $CONTS; do
  rm -f "$DIAG"
  GKLOG=$(mktemp /tmp/gprd_gk_XXXXXX.log)
  echo "[gprd] --- $TAG / $C ---"
  OG_LEVEL_WARP="$C" OG_LEVEL_WARP_DELAY=${GPRD_WARP_DELAY:-420} \
    "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem \
    > "$GKLOG" 2>&1 &
  GKPID=$!
  spawned=0
  for i in $(seq 1 150); do
    kill -0 "$GKPID" 2>/dev/null || { echo "[gprd] gk mort pendant $C"; break; }
    grep -qa "LEVEL-WARP-SPAWN" "$GKLOG" && { spawned=1; echo "[gprd] spawn ~${i}s"; break; }
    grep -qa "LEVEL-WARP-FAIL" "$GKLOG" && { echo "[gprd] LEVEL-WARP-FAIL"; break; }
    sleep 1
  done
  [ "$spawned" = 1 ] && sleep "$HOLD"
  kill "$GKPID" 2>/dev/null || true; wait "$GKPID" 2>/dev/null || true
  sleep 1
  cp -f "$GKLOG" "$OUT/gk_${TAG}_$C.log" 2>/dev/null || true
  {
    echo
    echo "---------- NIVEAU $C (spawn=$spawned) ----------"
    grep -a "\[pbrmat\] PARAMSRC\|surfaces.json parsed" "$GKLOG" | tail -2 || echo "(pas de table)"
    grep -a "managed_assets: .* shards" "$GKLOG" | tail -1 || echo "pack gere: AUCUN shard indexe"
    echo "niveaux charges : $(grep -aoE 'level [a-z0-9]+ has [0-9]+ PBR material' "$GKLOG" | sort -u | tr '\n' ';')"
    echo "matieres AUTHOREES SANS CARTE (bit 256) : $(grep -ac 'pbr authored-only material' "$GKLOG" || true)"
    echo "[surfaces] apply avec enregistrement : $(grep -a '\[surfaces\] apply' "$GKLOG" | grep -avc 'NO RECORD' || true)"
    echo "[surfaces] apply NO RECORD          : $(grep -ac 'NO RECORD' "$GKLOG" || true)"
    echo "plantages : $(grep -caE 'signal (4|6|11)|Segmentation' "$GKLOG" || true)"
    echo
    if [ -f "$DIAG" ] && grep -qa '^PBRREACH' "$DIAG"; then
      cp -f "$DIAG" "$OUT/diag_${TAG}_$C.txt"
      grep -a '^PBRREACH\|^PBRVAL\|^PBRNOTE' "$DIAG"
    else
      echo "(aucune ligne PBRREACH — le recensement n'a rien vu sur $C)"
    fi
  } >> "$LEG" 2>&1
  grep -a '^PBRREACH' "$OUT/diag_${TAG}_$C.txt" 2>/dev/null || echo "[gprd] pas de PBRREACH pour $C"
done
echo "[gprd] -> $LEG"
