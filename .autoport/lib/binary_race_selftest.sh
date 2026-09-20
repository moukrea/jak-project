#!/usr/bin/env bash
# lib/binary_race_selftest.sh — LE BANC DE LA COURSE ENTRE LE JUGE ET LE CONSTRUCTEUR.
#
# (harness-judge-binary-race-with-builder, 2026-09-20.) Il ne JUGE rien : la somme et la polarite
# « inconnu = defaut » vivent dans `lib/census/harness-judge-binary-race-with-builder.sh`.
#
# TROIS AXES, SUR DU CODE REEL ET DES PROCESSUS REELS :
#
#   A. LE JUGE. Le VRAI `validators/generic.sh`, dans un depot jetable. Une course est jouee,
#      le binaire du disque est REMPLACE — c'est le build qui tombe entre la course et le
#      verdict — puis le juge passe. Trois jambes : apres remplacement il ne se plaint pas ;
#      avec une preuve qui ment sur son empreinte il se plaint (CONTROLE : sans cette jambe, un
#      juge devenu aveugle passerait la premiere) ; sans temoin de gel il se plaint aussi.
#      La jambe `avant` rejoue l'ANCIENNE regle sur le MEME arbre : elle dit combien la fenetre
#      coutait, et sans elle « zero plainte » se lirait « il n'y avait rien a voir ».
#
#   B. LE VERROU. `lib/pidguard.sh` sur de VRAIS processus, dont le marqueur d'aout mot pour mot.
#      Le bras d'AVANT est `kill -0` nu sur la MEME entree : il rend « detenteur vivant », et
#      c'est ce qui a fait attendre 25 minutes puis construire par-dessus une course.
#
#   C. LA COURSE EN VOL. `lib/proof_inflight.sh` sur de VRAIS verrous d'ecrivain, plus la
#      lecture STATIQUE du vrai `auto_build_apk.sh` : la garde doit se trouver APRES la patience
#      depassee et AVANT l'ecriture, sinon elle ne garde rien.
#
# Sortie : des `cle=valeur` sur stdout, les explications sur stderr.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "brs_selftest_ran=0"; exit 1; }
AP="$ROOT/.autoport"
SB=$(mktemp -d -t binrace.XXXXXX) || { echo "brs_selftest_ran=0"; exit 1; }
TUES=""
nettoyer(){ for p in $TUES; do kill "$p" 2>/dev/null; done; rm -rf "$SB"; }
trap nettoyer EXIT
kv(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }
note(){ printf '[binrace] %s\n' "$*" >&2; }

# Les noms des fichiers d'une course sortent de l'autorite (NOMMAGE/un-seul-endroit).
eval "$(python3 "$AP/lib/impossible.py" names "" 2>/dev/null)"
[ -n "${AP_NAME_proof:-}" ] && [ -n "${AP_NAME_binary:-}" ] && [ -n "${AP_NAME_writer:-}" ] || {
  kv brs_selftest_ran 0; kv brs_panne autorite-de-nommage-muette; exit 1; }

# ============================================================== A. LE JUGE, DANS UN DEPOT JETABLE
SBID=sandbox-binary-race

monte(){   # monte <dossier>
  local d=$1
  mkdir -p "$d/.autoport/reports/$SBID" "$d/build/game" "$d/game" "$d/common" "$d/android" "$d/goal_src" || return 1
  git -C "$d" init -q >/dev/null 2>&1 || return 1        # git-sandbox-ok
  git -C "$d" config user.email br@sandbox >/dev/null 2>&1  # git-sandbox-ok
  git -C "$d" config user.name br >/dev/null 2>&1           # git-sandbox-ok
  # LE BAC A SABLE COPIE CE QUE LE JUGE IMPORTE, en entier : un juge auquel il manque un module
  # sort avant d'atteindre la ligne qu'on mesure, et les DEUX bras rendent alors zero plainte.
  cp -a "$AP/lib" "$d/.autoport/lib" || return 1
  cp -a "$AP/validators" "$d/.autoport/validators" || return 1
  printf 'version: 1\nitems:\n  - id: %s\n    status: in-progress\n    device: false\n    frames_min: 1\n    gate:\n      key: br_gate\n      op: "=="\n      value: 0\n' "$SBID" > "$d/.autoport/backlog.yaml"
  printf 'le binaire que la COURSE a mesure\n' > "$d/build/game/gk"
  chmod +x "$d/build/game/gk"
}

gele(){    # gele <dossier> -> l'empreinte figee sur stdout
  ( cd "$1" && bash .autoport/lib/binary_freeze.sh freeze "$SBID" "" build/game/gk 2>/dev/null ) \
    | sed -n 's/^proof_binary_frozen_sha=//p' | tail -1
}

ecrit_preuve(){  # ecrit_preuve <dossier> <sha-annonce>
  local d=$1 sha=$2
  {
    echo "source=x86"
    echo "binary=build/game/gk"
    echo "sha=$sha"
    echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "duration_s=1"
    echo "crash=0"
    echo "frames=10"
    echo "br_gate=0"
  } > "$d/.autoport/reports/$SBID/$AP_NAME_proof"
}

juge(){   # juge <dossier> -> la sortie du juge, sur une ligne
  ( cd "$1" && AUTOPORT_PHASE_ID="$SBID" bash .autoport/validators/generic.sh 2>&1 ) | tr '\n' ';'
}

# Les deux plaintes que la ligne mesuree peut produire, comptees separement.
plaintes(){ printf '%s' "$1" | grep -c 'binaire que la COURSE a mesure'; }
plaintes_sans_gel(){ printf '%s' "$1" | grep -c 'aucune empreinte FIGEE'; }

# ---- A1 : une course jouee, PUIS le binaire du disque remplace, PUIS le verdict --------------
D1="$SB/apres-rebuild"
if monte "$D1"; then
  SHA1=$(gele "$D1")
  ecrit_preuve "$D1" "$SHA1"
  # LE BUILD QUI TOMBE ENTRE LA COURSE ET LE VERDICT. C'est exactement ce qu'a fait
  # `auto_build_apk.sh` quatre fois le 20/09 entre 14:16 et 14:26.
  printf 'un AUTRE binaire, bati apres la course\n' > "$D1/build/game/gk"
  DISQUE=$(sha256sum "$D1/build/game/gk" | cut -c1-16)
  M1=$(juge "$D1")
  kv brs_a1_monte 1
  kv brs_a1_sha_course "$SHA1"
  kv brs_a1_sha_disque "$DISQUE"
  # LA CONDITION EST-ELLE PRESENTE ? Sans ce 1, « zero plainte » ne dirait rien : il faut que le
  # disque DIFFERE vraiment de ce que la course a mesure, sinon les deux bras sont d'accord.
  kv brs_a1_disque_a_change "$([ "$SHA1" != "$DISQUE" ] && echo 1 || echo 0)"
  kv brs_a1_plaintes "$(plaintes "$M1")"
  kv brs_a1_plaintes_sans_gel "$(plaintes_sans_gel "$M1")"
  # LE BRAS D'AVANT, sur le MEME arbre : ce que l'ANCIENNE regle aurait dit ici.
  kv brs_a1_avant_aurait_refuse "$([ "$SHA1" != "$DISQUE" ] && echo 1 || echo 0)"
else
  kv brs_a1_monte 0
fi

# ---- A2 : CONTROLE — une preuve qui ment sur son empreinte reste ROUGE -----------------------
D2="$SB/empreinte-menteuse"
if monte "$D2"; then
  SHA2=$(gele "$D2")
  ecrit_preuve "$D2" "0000000000000000"
  M2=$(juge "$D2")
  kv brs_a2_monte 1
  kv brs_a2_sha_course "$SHA2"
  kv brs_a2_plaintes "$(plaintes "$M2")"
else
  kv brs_a2_monte 0
fi

# ---- A3 : une preuve SANS temoin de gel est refusee ------------------------------------------
D3="$SB/sans-gel"
if monte "$D3"; then
  ecrit_preuve "$D3" "$(sha256sum "$D3/build/game/gk" | cut -c1-16)"
  M3=$(juge "$D3")
  kv brs_a3_monte 1
  kv brs_a3_plaintes_sans_gel "$(plaintes_sans_gel "$M3")"
else
  kv brs_a3_monte 0
fi

# ---- A4 : le juge relit-il ENCORE le disque ? lu sur le texte du juge livre ------------------
# LES COMMENTAIRES NE SONT PAS DU CODE. Le juge CITE l'ancienne ligne dans son commentaire pour
# dire pourquoi elle est partie : un `grep` nu la recompte et accuse un innocent. On ne lit que
# les lignes executables.
juge_code(){ grep -v '^[[:space:]]*#' "$AP/validators/generic.sh" 2>/dev/null; }
kv brs_a4_juge_lit_le_disque "$(juge_code | grep -c 'sha256sum "\$bin"')"
kv brs_a4_juge_lit_le_gel    "$(juge_code | grep -c 'binary_freeze.sh verify')"

# ================================================== B. LE VERROU, SUR DE VRAIS PROCESSUS =======
# shellcheck source=/dev/null
. "$AP/lib/pidguard.sh"
tail -f /dev/null & VIC=$!; TUES="$TUES $VIC"
raison(){ pg_lock_holder "$1" | sed -n 's/^pidguard_reason=//p'; }
tenu(){ pg_lock_holder "$1" >/dev/null && echo 1 || echo 0; }

printf 'who=vrai pid=%s starttime=%s at=1\n' "$VIC" "$(pg_starttime "$VIC")" > "$SB/l_tenu"
printf 'who=faux pid=%s starttime=1 at=1\n' "$VIC" > "$SB/l_recycle"
# LE MARQUEUR DU 20/09, MOT POUR MOT : pid vivant par recyclage, date de pose vieille d'un mois.
printf 'keira_room_x86 pid=%s started=2026-08-19T14:14:52\n' "$VIC" > "$SB/l_aout"
printf 'un verrou sans pid\n' > "$SB/l_sans_pid"
kv brs_b_tenu           "$(tenu "$SB/l_tenu")"
kv brs_b_tenu_raison    "$(raison "$SB/l_tenu")"
kv brs_b_recycle        "$(tenu "$SB/l_recycle")"
kv brs_b_recycle_raison "$(raison "$SB/l_recycle")"
kv brs_b_aout           "$(tenu "$SB/l_aout")"
kv brs_b_aout_raison    "$(raison "$SB/l_aout")"
kv brs_b_sans_pid       "$(tenu "$SB/l_sans_pid")"
kv brs_b_sans_pid_raison "$(raison "$SB/l_sans_pid")"
# LE BRAS D'AVANT, sur la MEME entree : `kill -0` nu tenait le verrou pour vivant.
kv brs_b_avant_kill0_aout "$(kill -0 "$VIC" 2>/dev/null && echo 1 || echo 0)"

# ==================================================== C. LA COURSE EN VOL, VUE SUR SON VERROU ==
DC="$SB/envol"
mkdir -p "$DC/.autoport/reports/item-jetable" && cp -a "$AP/lib" "$DC/.autoport/lib" \
  && git -C "$DC" init -q >/dev/null 2>&1                    # git-sandbox-ok
LW="$DC/.autoport/reports/item-jetable/$AP_NAME_writer"
inflight(){ ( cd "$DC" && bash .autoport/lib/proof_inflight.sh count 2>/dev/null ); }
printf 'pid=%s\nstarttime=%s\narm=livre\n' "$VIC" "$(pg_starttime "$VIC")" > "$LW"
kv brs_c_vue        "$(inflight)"
printf 'pid=%s\nstarttime=1\narm=livre\n' "$VIC" > "$LW"
kv brs_c_recycle    "$(inflight)"
kill "$VIC" 2>/dev/null; wait "$VIC" 2>/dev/null
printf 'pid=%s\nstarttime=1\narm=livre\n' "$VIC" > "$LW"
kv brs_c_mort       "$(inflight)"

# ---- C statique : la garde est-elle APRES la patience et AVANT l'ecriture ? ------------------
ABA="$AP/auto_build_apk.sh"
n_pat=$(grep -n '25 min au premier plan sans relache' "$ABA" | head -1 | cut -d: -f1)
n_gar=$(awk -v d="${n_pat:-0}" 'NR>d && /preuve_en_vol reconciliation --attendre/{print NR; exit}' "$ABA")
n_ins=$(awk -v d="${n_pat:-0}" 'NR>d && /install -r "\$APKX"/{print NR; exit}' "$ABA")
kv brs_c_ligne_patience "${n_pat:--1}"
kv brs_c_ligne_garde    "${n_gar:--1}"
kv brs_c_ligne_install  "${n_ins:--1}"
kv brs_c_garde_encadre \
   "$([ -n "${n_pat:-}" ] && [ -n "${n_gar:-}" ] && [ -n "${n_ins:-}" ] && \
      [ "$n_pat" -lt "$n_gar" ] && [ "$n_gar" -lt "$n_ins" ] && echo 1 || echo 0)"
# LE MOTIF DE LIGNE DE COMMANDE A-T-IL DISPARU ? Un shell qui NOMME le motif se matche lui-meme :
# c'est le defaut deja paye le 12/09 sur le demon Gradle. On compte le motif tel qu'il etait ecrit.
# (Et ici aussi : le commentaire du constructeur CITE l'ancien motif pour dire pourquoi il est
# parti. Compter les commentaires, c'est recenser des legendes.)
kv brs_c_motif_cmdline "$(grep -v '^[[:space:]]*#' "$ABA" 2>/dev/null | grep -cF '[p]roof_run')"

# ---- C statique : plus AUCUNE garde de verrou de livraison sur un `kill -0` nu ---------------
# LA POPULATION, PUIS LE DEFAUT. Un fichier qui LIT `.deploy-in-progress` et qui teste la vie
# d'un pid doit passer par `lib/pidguard.sh` : sinon il ne distingue pas un detenteur d'un numero
# RECYCLE. `archive/` est hors population — il ne tourne plus.
POP=0; SANS=0; NOMS_SANS=""
while IFS= read -r f; do
  case "$f" in *"/archive/"*) continue ;; esac
  POP=$((POP+1))
  grep -q 'kill -0' "$f" 2>/dev/null || continue
  grep -q 'pidguard' "$f" 2>/dev/null && continue
  SANS=$((SANS+1)); NOMS_SANS="${NOMS_SANS:+$NOMS_SANS,}$(basename "$f")"
done < <(grep -rlF '.deploy-in-progress' "$AP"/*.sh "$AP"/lib/*.sh "$AP"/lib/census/*.sh 2>/dev/null | sort -u)
kv brs_c_verrou_lecteurs      "$POP"
kv brs_c_gardes_sans_pidguard "$SANS"
kv brs_c_gardes_sans_noms     "${NOMS_SANS:--}"

kv brs_selftest_ran 1
