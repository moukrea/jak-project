#!/usr/bin/env bash
# census/hdr-output-visible.sh — LE STIMULUS DE REGIME, ET LA REMONTEE DE CE QUE LE MOTEUR EN DIT.
#
# POURQUOI CE SCRIPT EXISTE.
# --------------------------
# Le livrable de l'item exige que la course FASSE changer le regime : « Un zero d'evenements se lit
# "le regime n'a pas change pendant la mesure", jamais "rien a corriger" ». Or sur l'appareil de
# preuve (Redmi Note 9 Pro, API 31) le regime ne bouge pas tout seul : R2 est impossible (l'ecran
# n'annonce pas le BT.2020) et R1 s'achete au retro-eclairage, donc a luminosite maximale la marge
# vaut 1,000 a toutes les images — c'est ce que le chantier C a mesure (`r0_frames=3300`).
#
# CE QU'IL FAIT, ET CE QU'IL NE FAIT PAS.
# ---------------------------------------
# Il NE TOUCHE PAS au code du regime. Il ecrit la propriete que le moteur LIT DEJA depuis toujours,
# `debug.tracing.screen_brightness` — la consigne de retro-eclairage publiee par le SYSTEME, seule
# entree vivante de `measured_grant()`. La marge vaut `consigne_lue / base`, ou la base est la
# consigne relevee AVANT que le levier soit pose et gelee ensuite. Faire monter la consigne au-dessus
# de la base accorde la marge ; la ramener a la base la retire. Deux ecritures, deux changements de
# regime, aucune ligne de decision touchee.
#
# Il NE FABRIQUE AUCUN VERDICT. Les cles `hdr_visible_*` qu'il imprime sont celles que le MOTEUR a
# publiees, relues dans son propre journal et reemises telles quelles : c'est le moteur qui compte
# les images perimees, pas ce script. Ce que le script publie EN PROPRE porte le prefixe
# `hdr_visible_stim_` et ne decrit que SES gestes : ce qu'il a ecrit, ce qu'il a relu, ce qu'il a vu.
#
# POLARITE. Un stimulus qui n'a pas tourne (jeu mort, base inutilisable, propriete non appliquee) ne
# fabrique rien : il le DIT, les changements de regime restent a leur compte d'avant et la porte
# rougit sur `hdr_visible_d1_no_change`. C'est la sortie correcte, pas un accident.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "hdr_visible_stim_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

ADB="${ADB:-${ANDROID_HOME:-$HOME/Android}/platform-tools/adb}"
[ -x "$ADB" ] || ADB=$(command -v adb) || { echo "hdr_visible_stim_ran=0"; exit 1; }
PKG="${PKG:-org.opengoal.gk.jak1}"

pub() { printf '%s=%s\n' "$1" "${2:--}"; }

# ---------------------------------------------------------------- l'appareil, et lui seul ------
SERIAL=$(bash "$AP/lib/pick_device.sh" 2>/dev/null | tr -d '\r' | head -1)
case "$SERIAL" in
  '' ) pub hdr_visible_stim_ran 0; pub hdr_visible_stim_reason aucun-appareil; exit 1 ;;
  *:* ) pub hdr_visible_stim_ran 0; pub hdr_visible_stim_reason appareil-reseau-interdit; exit 1 ;;
esac
pub hdr_visible_stim_serial "$SERIAL"

PID=$(timeout 15 "$ADB" -s "$SERIAL" shell pidof "$PKG" 2>/dev/null | tr -d '\r' | awk '{print $1}')
if [ -z "$PID" ]; then
  # Le jeu s'est arrete avant le recensement : aucun stimulus n'est possible. On le DIT, et les
  # comptes du moteur restent ceux de la course — la porte les jugera tels quels.
  pub hdr_visible_stim_ran 0
  pub hdr_visible_stim_alive 0
  pub hdr_visible_stim_reason jeu-arrete-avant-le-recensement
  exit 0
fi
pub hdr_visible_stim_alive 1

TMP=$(mktemp -d) || { echo "hdr_visible_stim_ran=0"; exit 1; }
TAIL="$TMP/logcat.txt"
cleanup() {
  [ -n "${LPID:-}" ] && kill "$LPID" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

# Son propre lecteur de journal : celui de `proof_run.sh` est deja mort quand ce crochet demarre,
# et le tampon circulaire de l'appareil ne garde que quelques secondes a la cadence du jeu. On
# n'efface RIEN (`logcat -c` detruirait la course qui vient d'avoir lieu) : on se branche en aval.
stdbuf -oL "$ADB" -s "$SERIAL" logcat -v brief > "$TAIL" 2>/dev/null &
LPID=$!
sleep 2

# `last_key <cle>` : la DERNIERE valeur que le moteur a publiee pour cette cle, dans la fenetre que
# ce script a enregistree. Vide si le moteur ne l'a pas dite : inconnu, jamais zero.
last_key() {
  sed -nE "s/.*[^A-Za-z0-9_]($1)=([^[:space:]]+).*/\\2/p" "$TAIL" | tail -1
}

# ------------------------------------------------------- la base que le MOTEUR a gelee ---------
# Elle n'est pas devinee : le moteur la publie (`hdr_visible_bl_base_x10000`). C'est elle qui fixe
# ou se trouve la frontiere 1,005 de `regime_now()`, donc elle qui dit quelles consignes ecrire.
BASE_X=""
for _ in 1 2 3 4 5 6 7 8; do
  BASE_X=$(last_key hdr_visible_bl_base_x10000)
  [ -n "$BASE_X" ] && break
  sleep 3
done
if [ -z "$BASE_X" ] || [ "$BASE_X" -le 0 ] 2>/dev/null; then
  pub hdr_visible_stim_ran 0
  pub hdr_visible_stim_reason base-non-publiee-par-le-moteur
  pub hdr_visible_stim_base_x10000 "${BASE_X:--1}"
  exit 0
fi
pub hdr_visible_stim_base_x10000 "$BASE_X"

# La consigne « avec marge » : trois fois la base, bornee a 1,0 (la consigne systeme est normalisee
# sur [0, 1] et une valeur au-dessus de 1 ne decrirait aucun panneau). Il faut que la marge depasse
# 1,005 — le seuil de `regime_now()` — donc que la base laisse de la place au-dessus d'elle.
HI_X=$(( BASE_X * 3 ))
[ "$HI_X" -gt 10000 ] && HI_X=10000
RATIO_X1000=$(( HI_X * 1000 / BASE_X ))
pub hdr_visible_stim_ratio_x1000 "$RATIO_X1000"
if [ "$RATIO_X1000" -le 1005 ]; then
  # Base trop haute pour qu'aucune consigne physique ne rende de marge : c'est la memoire
  # « marge HDR < API 34 = ACHETEE au retro-eclairage » — a luminosite MAX le levier ne rend rien.
  pub hdr_visible_stim_ran 0
  pub hdr_visible_stim_unusable_base 1
  pub hdr_visible_stim_reason base-trop-haute-aucune-marge-exprimable
  exit 0
fi
pub hdr_visible_stim_unusable_base 0

fmt_x10000() { awk -v v="$1" 'BEGIN{printf "%.6f", v/10000.0}'; }

STEPS=0
APPLIED=0
GRANTS=""
REGIMES=""
step() {  # step <valeur_x10000> <libelle>
  local want; want=$(fmt_x10000 "$1")
  STEPS=$((STEPS+1))
  timeout 15 "$ADB" -s "$SERIAL" shell "setprop debug.tracing.screen_brightness '$want'" >/dev/null 2>&1
  sleep 10
  local back; back=$(timeout 15 "$ADB" -s "$SERIAL" shell getprop debug.tracing.screen_brightness 2>/dev/null | tr -d '\r')
  # La propriete a-t-elle TENU ? Le systeme la republie des que le panneau bouge reellement ; si
  # elle a ete reecrite sous nous, le moteur a mesure autre chose et il faut que ca se voie.
  [ "$back" = "$want" ] && APPLIED=$((APPLIED+1))
  pub "hdr_visible_stim_step${STEPS}_want" "$want"
  pub "hdr_visible_stim_step${STEPS}_readback" "${back:--}"
  local g r
  g=$(last_key hdr_visible_grant_x1000); r=$(last_key hdr_visible_regime_now)
  pub "hdr_visible_stim_step${STEPS}_grant_x1000" "${g:--1}"
  pub "hdr_visible_stim_step${STEPS}_regime" "${r:--1}"
  GRANTS="${GRANTS:+$GRANTS,}${g:--1}"
  REGIMES="${REGIMES:+$REGIMES,}${r:--1}"
}

# QUATRE ECRITURES, TROIS FRONTIERES. base -> haut -> base -> haut : le regime doit traverser le
# seuil trois fois. Un seul aller-retour suffirait au critere (deux changements) ; on en demande un
# de plus pour qu'un changement rate par ordonnancement ne condamne pas la course.
step "$BASE_X" base
step "$HI_X"   haut
step "$BASE_X" base
step "$HI_X"   haut

kill "$LPID" 2>/dev/null; wait "$LPID" 2>/dev/null; LPID=""

pub hdr_visible_stim_steps "$STEPS"
pub hdr_visible_stim_applied "$APPLIED"
pub hdr_visible_stim_grants "${GRANTS:--}"
pub hdr_visible_stim_regimes "${REGIMES:--}"
DISTINCT=$(printf '%s' "$REGIMES" | tr ',' '\n' | grep -v '^-1$' | sort -u | grep -c .)
pub hdr_visible_stim_regimes_distinct "${DISTINCT:-0}"
pub hdr_visible_stim_ran 1

# ------------------------------------------- CE QUE LE MOTEUR DIT APRES LE STIMULUS ------------
# Reemission telle quelle de la DERNIERE valeur publiee par le moteur pour chacune de ses cles
# `hdr_visible_*`. Le lecteur de journal de `proof_run.sh` est mort avant ce crochet : sans cette
# reemission, la preuve porterait les comptes d'AVANT le stimulus. On ne reecrit aucune valeur, on
# ne complete aucune cle absente, et on ne touche a aucune cle d'un autre item.
COUNT=0
while IFS= read -r line; do
  case "$line" in
    hdr_visible_stim_*) continue ;;  # les siennes ne se relisent pas : elles viennent d'etre dites
  esac
  printf '%s\n' "$line"
  COUNT=$((COUNT+1))
done < <(sed -nE 's/.*[^A-Za-z0-9_](hdr_visible_[A-Za-z0-9_]+=[^[:space:]]+).*/\1/p' "$TAIL" \
         | awk -F= '{v[$1]=substr($0, index($0,"=")+1)} END {for (k in v) print k "=" v[k]}' \
         | sort)
pub hdr_visible_stim_reemitted "$COUNT"
exit 0
