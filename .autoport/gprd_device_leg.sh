#!/usr/bin/env bash
# gprd_device_leg.sh — phase Gpbr-props-reach-draw, une JAMBE APPAREIL (Redmi eae4df44).
#
# Le canal de preuve est le MEME que celui deja en service pour le PBR : le fichier pullable
# files/pbr_tan_diag.txt, ecrit par kmachine a chaque changement de generation du recensement.
# Aucune mesure visuelle (interdite en permanence) : ce sont des nombres.
#
# GARDES, chacune posee parce qu'une tentative anterieure de ce depot est morte dessus :
#   * FRAICHEUR : on exige dans le libgk.so DE L'APK les chaines que CETTE phase ajoute. Un
#     marqueur de drapeaux peut etre identique entre deux builds ; les symboles, non.
#   * DEBUG EPINGLE : le settings.ini vivant portait `pbr-displacement = 0` (defaut livre 1).
#     Une course prise dans cet etat mesure le MODE DEBUG. On RETABLIT LES DEFAUTS LIVRES et on
#     publie l'avant/apres pour audit — on ne regle rien.
#   * PROPRIETES DEBUG LAISSEES : les props de warp sont EFFACEES en sortie (trap), parce qu'une
#     propriete oubliee tient un bouton enfonce pour toutes les courses suivantes.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-adb}"
S="${S:-eae4df44}"; PKG=org.opengoal.gk.jak1
CONT="${GPRD_CONT:-village1-hut}"
TAG="${1:-dev_$CONT}"
HOLD="${GPRD_HOLD:-70}"
OUT=.autoport/reports/Gpbr-props-reach-draw; mkdir -p "$OUT"
P="$OUT/leg_$TAG.txt"; : > "$P"
adbs(){ "$ADB" -s "$S" "$@"; }
say(){ echo "$*" | tee -a "$P"; }
die(){ say "[gprd-dev FAIL] $*"; exit 1; }
# GPRD_DEV_PACK=off : on met de cote le state.json du PACK GERE sur l'appareil (les rpacks
# restent, mais l'index n'a plus rien a lire) EN GARDANT surfaces.json. C'est, sur le vrai
# materiel, la configuration d'un joueur qui a la table et pas les 223 Mo de cartes — l'etat
# que AssetPackDownloader.java:164-210 installe explicitement quand aucun shard ne correspond.
# La restauration est dans le trap : une jambe interrompue ne laisse pas l'appareil ampute.
DEVPACK="${GPRD_DEV_PACK:-on}"
MA=files/managed_assets/jak1
restore_devpack(){
  if [ "$DEVPACK" = off ] && [ -s "$OUT/settings-prerun_$TAG.ini" ]; then
    adbs push "$OUT/settings-prerun_$TAG.ini" /storage/emulated/0/OpenGOAL/jak1/settings.ini >/dev/null 2>&1 || true
    echo "  settings restaures : $(adbs shell "grep -aE '^managed-assets.' /storage/emulated/0/OpenGOAL/jak1/settings.ini" </dev/null 2>&1 | tr -d '\r')" | tee -a "$P"
  fi
  if [ "$DEVPACK" = off ]; then
    adbs shell "run-as $PKG sh -c 'mv $MA/state.json.gprd-bak $MA/state.json'" </dev/null >/dev/null 2>&1 || true
    echo "  pack appareil restaure : state.json = $(adbs shell "run-as $PKG sh -c 'ls $MA/ | grep state'" </dev/null 2>&1 | tr -d '\r')" | tee -a "$P"
  fi
}
cleanup(){ adbs shell 'setprop debug.opengoal.level.warp ""; setprop debug.opengoal.level.warp.pos ""' </dev/null >/dev/null 2>&1 || true; restore_devpack; }
trap cleanup EXIT

say "===== JAMBE APPAREIL $TAG  (continue=$CONT hold=${HOLD}s) ====="

# ---- 1. FRAICHEUR DE L'ARTEFACT ------------------------------------------------------------
APK=$(find android -name 'app-jak1-debug.apk' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
[ -n "$APK" ] || die "aucun APK bati"
say "APK: $APK ($(stat -c%s "$APK") octets, bati $(date -d @"$(stat -c%Y "$APK")" +%F' '%T))"
unzip -p "$APK" lib/arm64-v8a/libgk.so > /tmp/gprd_libgk.so || die "libgk illisible dans l'APK"
for sym in PBRREACH PBRVAL 'pbr authored-only material' pbr_reach_section; do
  n=$(strings /tmp/gprd_libgk.so | grep -cF "$sym" || true)
  [ "${n:-0}" -ge 1 ] || die "libgk de l'APK sans '$sym' — build perime, la jambe mesurerait le code d'avant"
  say "  libgk porte '$sym' (x$n)"
done
rm -f /tmp/gprd_libgk.so

# ---- 2. INSTALLATION -----------------------------------------------------------------------
say "-- installation --"
adbs install -r -d "$APK" 2>&1 | tail -2 | tee -a "$P"
adbs shell "pm list packages $PKG" </dev/null | tee -a "$P"

# ---- 3. DEFAUTS LIVRES DANS settings.ini ---------------------------------------------------
SET=/storage/emulated/0/OpenGOAL/jak1/settings.ini
adbs shell cat "$SET" </dev/null > /tmp/gprd_settings.ini 2>/dev/null || die "pas de settings.ini"
[ -s /tmp/gprd_settings.ini ] || die "settings.ini vide"
cp /tmp/gprd_settings.ini "$OUT/settings-prerun_$TAG.ini"
say "  settings AVANT : $(grep -aE '^(pbr-displacement|pbr-isolate|pbr-materials.|modern-materials.|recharged-master.|managed-assets.) =' /tmp/gprd_settings.ini | tr '\n' ' ')"
sed -i 's/^pbr-displacement = .*/pbr-displacement = 1/' /tmp/gprd_settings.ini
sed -i 's/^pbr-isolate = .*/pbr-isolate = 0/' /tmp/gprd_settings.ini
if [ "$DEVPACK" = off ]; then
  # ABLATION PAR L'INTERRUPTEUR LIVRE, apres DEUX tentatives ratees qu'il faut nommer :
  #   - `run-as PKG mv a b` rend 0 et NE FAIT RIEN (jambe H : 14 shards indexes apres un
  #     renommage « reussi ») ;
  #   - renommer state.json ne suffit pas non plus (jambe I : verifie absent, et le journal dit
  #     quand meme « 14 shards ... from .../state.json ») — LoaderActivity.downloadManagedAssets()
  #     tourne A CHAQUE demarrage et RECRIT state.json par rename avant que le moteur le lise.
  # Le seul levier qui tienne est celui que le jeu expose : `managed-assets?`, lu par
  # ManagedAssets.cpp:84 pour toute la couche rpack. surfaces.json continue d'etre lu (il vient de
  # install_dir, pas du niveau rpack), ce qui EST la configuration a mesurer.
  sed -i 's/^managed-assets? = .*/managed-assets? = #f/' /tmp/gprd_settings.ini
fi
adbs push /tmp/gprd_settings.ini "$SET" >/dev/null || die "push settings.ini impossible"
adbs shell cat "$SET" </dev/null > /tmp/gprd_settings_after.ini 2>/dev/null || true
say "  settings APRES : $(grep -aE '^(pbr-displacement|pbr-isolate) =' /tmp/gprd_settings_after.ini | tr '\n' ' ')"
cp /tmp/gprd_settings_after.ini "$OUT/settings-used_$TAG.ini" 2>/dev/null || true

if [ "$DEVPACK" = off ]; then
  # `run-as PKG mv a b` rend 0 ET NE FAIT RIEN — mesure de la jambe H, qui a publie 14 shards
  # indexes apres un renommage « reussi ». Il faut un shell explicite, et on VERIFIE le resultat
  # au lieu de faire confiance au code de retour : une ablation qui ne tire pas est un faux vert.
  adbs shell "run-as $PKG sh -c 'mv $MA/state.json $MA/state.json.gprd-bak'" </dev/null >/dev/null 2>&1 || true
  st=$(adbs shell "run-as $PKG sh -c 'ls $MA/ | grep -c \"^state.json$\"'" </dev/null 2>&1 | tr -d "\r")
  [ "${st:-1}" = 0 ] || die "state.json toujours en place ($st) — l'ablation n'a pas tire"
  say "  PACK GERE de l'appareil mis de cote (state.json renomme, verifie absent) ; surfaces.json CONSERVE"
fi

# ---- 4. COURSE -----------------------------------------------------------------------------
LOG="$OUT/logcat_$TAG.log"
adbs shell "run-as $PKG rm -f files/pbr_tan_diag.txt files/pbr_reach.txt" </dev/null >/dev/null 2>&1 || true
adbs shell "am force-stop $PKG" </dev/null
sleep 2
adbs shell "setprop debug.opengoal.level.warp $CONT" </dev/null
adbs logcat -b all -c </dev/null || true
adbs shell "monkey -p $PKG -c android.intent.category.LAUNCHER 1" </dev/null >/dev/null 2>&1
( adbs logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/gprd_lc.pid )
say "-- course lancee, attente du spawn (<=180s) --"
ok=0
for i in $(seq 1 180); do
  sleep 1
  grep -qa "LEVEL-WARP-SPAWN" "$LOG" && { ok=1; say "  spawn a ~${i}s"; break; }
  grep -qaE "LEVEL-WARP-FAIL|signal (4|6|7|11) \(SIG" "$LOG" && { say "  echec/plantage a ~${i}s"; break; }
done
[ "$ok" = 1 ] || say "  ATTENTION : pas de LEVEL-WARP-SPAWN"
sleep "$HOLD"
kill "$(cat /tmp/gprd_lc.pid 2>/dev/null)" 2>/dev/null || true

# ---- 5. RECOLTE ----------------------------------------------------------------------------
# Gpbr-props-reach-draw : le recensement a son PROPRE fichier. `pbr_tan_diag.txt` a DEUX
# ecrivains (kmachine.cpp et TFrag3Data.cpp) et le dernier ecrase l'autre : la course F a
# rendu 62 lignes de couverture de tangentes et ZERO PBRREACH sur l'appareil, la ou le meme
# binaire en publiait 40 sur x86. On tire les deux, mais le verdict se lit dans pbr_reach.txt.
adbs shell "run-as $PKG cat files/pbr_reach.txt" </dev/null > "$OUT/diag_$TAG.txt" 2>/dev/null || true
adbs shell "run-as $PKG cat files/pbr_tan_diag.txt" </dev/null > "$OUT/tandiag_$TAG.txt" 2>/dev/null || true
say "-- recolte --"
say "  logcat : $(wc -l < "$LOG") lignes"
say "  diag   : $(wc -l < "$OUT/diag_$TAG.txt") lignes"
say "  plantages : $(grep -caE 'signal (4|6|7|11) \(SIG' "$LOG" || true)"
say "  [pbrmat] PARAMSRC : $(grep -a '\[pbrmat\] PARAMSRC' "$LOG" | tail -1)"
say "  surfaces.json analyse : $(grep -a 'surfaces.json parsed' "$LOG" | tail -1)"
say "  matieres AUTHOREES SANS CARTE (bit 256) : $(grep -ac 'pbr authored-only material' "$LOG" || true)"
say "  [surfaces] apply avec enregistrement : $(grep -a '\[surfaces\] apply' "$LOG" | grep -avc 'NO RECORD' || true)"
say "  [surfaces] apply NO RECORD          : $(grep -ac 'NO RECORD' "$LOG" || true)"
say ""
say "-- LE RECENSEMENT (files/pbr_tan_diag.txt, tire de l'appareil) --"
if grep -qa '^PBRREACH' "$OUT/diag_$TAG.txt"; then
  grep -a '^PBRREACH\|^PBRVAL\|^PBRNOTE' "$OUT/diag_$TAG.txt" | tee -a "$P" >/dev/null
  grep -a '^PBRREACH' "$OUT/diag_$TAG.txt"
else
  say "(aucune ligne PBRREACH dans le diag tire de l'appareil)"
fi
say "[gprd-dev] -> $P"
