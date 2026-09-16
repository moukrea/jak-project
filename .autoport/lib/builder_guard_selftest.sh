#!/usr/bin/env bash
# lib/builder_guard_selftest.sh — LE TEMOIN A DEUX BRAS DE LA GARDE DU CONSTRUCTEUR D'APK
# (harness-builder-does-not-mistake-an-idle-gradle-daemon-for-a-build, 2026-09-17).
#
# CE QU'IL MESURE. La VRAIE garde de `.autoport/auto_build_apk.sh`, decoupee dans le fichier
# entre ses deux marqueurs et EXECUTEE, contre de VRAIS processus que ce script fait naitre :
#   * un demon Gradle INACTIF (comm `java`, ligne de commande relevee dans /proc, qui dort)
#       -> bras LIVRE : busy=0, hard=0, il est ECARTE       -> le build part
#       -> bras --off (l'ancienne regle, celle qui etait dans le fichier) : busy=1, hard=1
#          -> `continue`, et sur ce chemin l'ancien code n'ecrivait RIEN : le tick muet.
#   * le CLIENT gradle (releve du meme /proc)             -> busy=1, hard=1 des deux cotes
#   * un demon Gradle qui BRULE DU CPU                    -> busy=1, hard=1 : la garde neuve
#     n'est pas permissive en bloc, elle mesure.
#   * `ninja`                                             -> CONTROLE POSITIF : sans lui, une
#     tranche vide rendrait « tout passe » et les deux bras seraient verts par inaction.
#
# POURQUOI DE VRAIS PROCESSUS ET PAS UNE TABLE INVENTEE. La garde ne se contente pas de lire une
# ligne de commande : elle echantillonne utime+stime sur 10 s et compte les enfants. Une table
# simulee ne mesurerait que le decor du banc. On injecte donc UNIQUEMENT la liste de pids
# (`builder_pid_list`, la seule porte de la garde vers le systeme) ; comm, cmdline, CPU et
# enfants sont lus dans le VRAI /proc. Le banc reste deterministe — ce qu'un constructeur fait
# a cote ne peut pas changer son verdict — sans cesser d'etre reel.
#
# POURQUOI UNE TRANCHE. Si les marqueurs disparaissent, si l'indirection saute ou si
# l'etranglement du journal s'en va, ce script sort en 2 SANS PUBLIER et le recensement rougit.
# Il ne peut pas mesurer une copie qui aurait derive.
#
# LE TEMOIN « AVANT » NE S'ACCUSE PAS LUI-MEME. On ne lit pas `HEAD:` (qui devient MOI des le
# commit) : on remonte a la derniere revision ou le marqueur de la garde neuve est ABSENT, et on
# PUBLIE le commit retenu.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "bgb_selftest_ran=0"; exit 2; }
AP="$ROOT/.autoport"
SRC="$AP/auto_build_apk.sh"
FIX="$AP/lib/fixtures/gradle-cmdlines.tsv"
cd "$ROOT" || { echo "bgb_selftest_ran=0"; exit 2; }
pub(){ printf '%s=%s\n' "$1" "${2:--}"; }
mort(){ echo "bgb_selftest_ran=0"; pub bgb_abandon "$1"; exit 2; }

# ------------------------------------------------------------------ la VRAIE tranche ---------
TRANCHE=$(python3 - "$SRC" <<'PY' 2>/dev/null
import sys
src = open(sys.argv[1], encoding='utf-8', errors='replace').read()
b, e = "# >>> BUILDER-GUARD-BEGIN", "# <<< BUILDER-GUARD-END"
if b not in src or e not in src:
    sys.exit(1)
out = src[src.index(b):src.index(e)]
# La tranche DOIT porter l'indirection, la garde et l'etranglement, sinon le banc mesurerait
# autre chose que ce qui est livre.
for need in ("builder_pid_list(){", "builder_busy_counts(){", "say_cause(){",
             "builder_tick_record(){", "BUILDER_SAY_THROTTLE"):
    if need not in out:
        sys.exit(1)
sys.stdout.write(out)
PY
) || mort tranche-absente-ou-amputee
[ -n "$TRANCHE" ] || mort tranche-vide

[ -s "$FIX" ] || mort releves-gradle-absents
CL_CLIENT=$(awk -F'\t' '$1=="client"{print $3}' "$FIX" | head -1)
CL_DEMON=$(awk -F'\t' '$1=="demon"{print $3}' "$FIX" | head -1)
[ -n "$CL_CLIENT" ] && [ -n "$CL_DEMON" ] || mort releves-gradle-incomplets
case "$CL_DEMON" in *GradleDaemon*) ;; *) mort releve-demon-sans-GradleDaemon ;; esac

# ---------------------------------------------- L'ANCIENNE REGLE, LUE DANS L'HISTOIRE ---------
# `grep -c`, JAMAIS `grep -q` : sous `-o pipefail`, `-q` sort a la premiere correspondance et
# SIGPIPE le `git show`, donc le pipeline rend 141 sur un fichier qui PORTE le marqueur. La
# revision retenue comme « avant » serait alors la MIENNE, et le temoin d'avant rendrait zero.
AVANT_SHA=$(git log --format=%H -- .autoport/auto_build_apk.sh 2>/dev/null | while read -r sha; do
  if [ "$(git show "$sha:.autoport/auto_build_apk.sh" 2>/dev/null | grep -c 'BUILDER-GUARD-BEGIN')" = 0 ]; then
    printf '%s\n' "$sha"; break
  fi
done)
VIEUX_BUSY=""; VIEUX_HARD=""
if [ -n "$AVANT_SHA" ]; then
  # Les deux regex de l'ancienne garde, extraites du FICHIER D'AVANT — jamais recopiees a la
  # main : une copie divergerait en silence et le temoin « avant » mesurerait autre chose.
  VIEUX_BUSY=$(git show "$AVANT_SHA:.autoport/auto_build_apk.sh" 2>/dev/null \
    | grep -oE "grep -cE '\^\(cmake[^']*'" | sed "s/^grep -cE '//; s/'$//" | sed -n 1p)
  VIEUX_HARD=$(git show "$AVANT_SHA:.autoport/auto_build_apk.sh" 2>/dev/null \
    | grep -oE "grep -cE '\^\(cmake[^']*'" | sed "s/^grep -cE '//; s/'$//" | sed -n 2p)
fi
[ -n "$VIEUX_BUSY" ] && [ -n "$VIEUX_HARD" ] || mort ancienne-regle-introuvable-dans-l-histoire

# ------------------------------------------------------------ de VRAIS processus temoins -----
SB=$(mktemp -d "${TMPDIR:-/tmp}/bldguard.XXXXXX") || mort bac-a-sable-impossible
PIDS_NES=""
menage(){
  local p
  for p in $PIDS_NES; do kill -TERM "$p" 2>/dev/null; done
  sleep 1
  for p in $PIDS_NES; do kill -KILL "$p" 2>/dev/null; done
  rm -rf "$SB"
}
trap menage EXIT INT TERM
mkdir -p "$SB/bin"
cat > "$SB/faux.c" <<'CEOF'
#include <unistd.h>
#include <stdlib.h>
int main(void) {
  const char* s = getenv("SPIN");
  if (s && s[0] == '1') { volatile double x = 0; for (;;) x += 1.0; }
  for (;;) pause();
  return 0;
}
CEOF
cc -O0 -o "$SB/bin/java" "$SB/faux.c" 2>/dev/null || mort cc-absent-ou-en-echec
cp -f "$SB/bin/java" "$SB/bin/ninja" || mort copie-ninja-impossible

# LES TEMOINS NAISSENT DANS *CE* SHELL, JAMAIS DANS UNE SUBSTITUTION DE COMMANDE.
# `P=$(naitre ...)` mettait la fonction dans un SOUS-SHELL : le `$!` y etait juste, mais le
# `PIDS_NES` du parent restait VIDE. Le `trap` ne tuait donc personne, et chaque passage laissait
# quatre processus derriere lui — dont un qui brule un coeur a 100 % et un faux `ninja` que la
# garde du VRAI constructeur prend pour un build. Mesure : 8 orphelins apres deux passages.
# Le pid EXACT est retenu a la naissance (jamais de kill par motif : `pkill -f` se matche
# lui-meme, et la consigne l'interdit).
# shellcheck disable=SC2086
set -- $CL_DEMON;  shift
SPIN=0 "$SB/bin/java" "$@" >/dev/null 2>&1 &  P_IDLE=$!;  PIDS_NES="$PIDS_NES $P_IDLE"
SPIN=1 "$SB/bin/java" "$@" >/dev/null 2>&1 &  P_BUSY=$!;  PIDS_NES="$PIDS_NES $P_BUSY"
# shellcheck disable=SC2086
set -- $CL_CLIENT; shift
SPIN=0 "$SB/bin/java" "$@" >/dev/null 2>&1 &  P_CLI=$!;   PIDS_NES="$PIDS_NES $P_CLI"
SPIN=0 "$SB/bin/ninja" -C build-android >/dev/null 2>&1 & P_NINJA=$!; PIDS_NES="$PIDS_NES $P_NINJA"
sleep 1
for p in $P_IDLE $P_BUSY $P_CLI $P_NINJA; do
  [ -d "/proc/$p" ] || mort processus-temoin-mort-ne
  [ "$(cat "/proc/$p/comm" 2>/dev/null)" = java ] || [ "$(cat "/proc/$p/comm" 2>/dev/null)" = ninja ] \
    || mort comm-du-temoin-inattendu
done
# Le demon qui brule doit AVOIR brule quand on le mesurera : on le laisse prendre de l'avance.
sleep 1

# ------------------------------------------------------------------ le banc -------------------
BANC="$SB/banc.sh"
{
  printf 'set -uo pipefail\n'
  printf 'LOG=%q\nBUILDER_REG=%q\n' "$SB/journal.txt" "$SB/registre.tsv"
  printf 'PIDS=%q\n' "PLACEHOLDER"
  printf '%s\n' "$TRANCHE"
  printf 'LOG=%q\nBUILDER_REG=%q\n' "$SB/journal.txt" "$SB/registre.tsv"
  printf 'builder_pid_list(){ printf "%%s\\n" $PIDS; }\n'
  printf 'builder_busy_counts\n'
} > "$BANC"

neuve(){                                  # $1 = pids -> "busy hard idle pourquoi"
  local p=$1 s="$SB/run.sh"
  sed "s|^PIDS=.*|PIDS='$p'|" "$BANC" > "$s"
  ( cd "$ROOT" && bash "$s" 2>/dev/null )
}
# L'ANCIENNE REGLE, rejouee sur la MEME table. `ps -eo comm,args` est reconstruit depuis /proc
# pour les SEULS pids du bras : meme forme (« <comm> <ligne de commande> »), meme regex.
vieille(){                                # $1 = pids -> "busy hard"
  local p tbl="" b h
  for p in $1; do
    [ -d "/proc/$p" ] || continue
    tbl="$tbl$(cat "/proc/$p/comm" 2>/dev/null) $(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
"
  done
  b=$(printf '%s' "$tbl" | grep -vE '^(claude|codex) ' | grep -cE "$VIEUX_BUSY" || true)
  h=$(printf '%s' "$tbl" | grep -vE '^(claude|codex) ' | grep -cE "$VIEUX_HARD" || true)
  printf '%s %s' "$b" "$h"
}

DEFAUTS=0
A_TORT=0
jambe(){                    # $1=nom $2=pids $3=busy attendu $4=hard attendu $5=idle attendu
  local nom=$1 p=$2 ab=$3 ah=$4 ai=$5 busy hard idle why vb vh ok=1
  read -r busy hard idle why <<< "$(neuve "$p")"
  [ "${busy:--}" = "$ab" ] || ok=0
  [ "${hard:--}" = "$ah" ] || ok=0
  [ "${idle:--}" = "$ai" ] || ok=0
  [ "$ok" = 1 ] || DEFAUTS=$((DEFAUTS+1))
  read -r vb vh <<< "$(vieille "$p")"
  pub "bgb_${nom}_ok" "$ok"
  pub "bgb_${nom}_neuve" "busy=${busy:--},hard=${hard:--},idle=${idle:--}"
  pub "bgb_${nom}_vieille" "busy=${vb:--},hard=${vh:--}"
  pub "bgb_${nom}_why" "$(printf '%s' "${why:--}" | tr ' \t' '__')"
  printf '%s %s\n' "${vb:-0}" "${vh:-0}" > "$SB/.vieille.$nom"
}

# 0. CONTROLE POSITIF : le code decoupe REPOND. Sans lui, « tout passe » serait vert par vide.
jambe ctl_ninja      "$P_NINJA" 1 1 0
# 1. LE DEMON INACTIF — le defaut de cet item. La garde neuve l'ECARTE.
jambe demon_idle     "$P_IDLE"  0 0 1
# 2. LE CLIENT GRADLE — un vrai build, bloque des deux cotes.
jambe gradle_client  "$P_CLI"   1 1 0
# 3. LE DEMON QUI TRAVAILLE — la garde neuve ne laisse pas tout passer.
jambe demon_actif    "$P_BUSY"  1 1 0
# 4. LES QUATRE ENSEMBLE : le tri se fait par processus, pas en bloc.
jambe ensemble       "$P_IDLE $P_BUSY $P_CLI $P_NINJA" 3 3 1

# ------------------------------- LES DEUX BRAS, COTE A COTE, SUR LE DEMON INACTIF SEUL --------
# Bras LIVRE : busy=0 -> la boucle ne fait pas `continue`, le build part.
# Bras --off (l'ancienne regle) : busy=1 ET hard=1 -> `continue`, et la patience de 20 min ne
# s'applique JAMAIS puisqu'elle exige hard==0. Deux mecanismes distincts, comptes separement :
# c'est exactement ce que la cause connue du 16/09 decrit.
read -r VB VH < "$SB/.vieille.demon_idle"
read -r NB NH NI _ <<< "$(neuve "$P_IDLE")"
[ "${VB:-0}" -ge 1 ] 2>/dev/null && A_TORT=$((A_TORT+1))
[ "${VH:-0}" -ge 1 ] 2>/dev/null && A_TORT=$((A_TORT+1))
pub bgb_livre_decision   "$([ "${NB:-1}" = 0 ] && echo build-autorise || echo bloque)"
pub bgb_off_decision     "$([ "${VB:-0}" -ge 1 ] && echo continue-sans-build || echo build-autorise)"
pub bgb_off_patience_morte "$([ "${VH:-0}" -ge 1 ] && echo 1 || echo 0)"
pub bgb_vieille_regle_bloque_a_tort "$A_TORT"
pub bgb_vieille_busy_regex "$(printf '%s' "$VIEUX_BUSY" | tr -d ' ')"
pub bgb_vieille_hard_regex "$(printf '%s' "$VIEUX_HARD" | tr -d ' ')"
pub bgb_avant_commit "${AVANT_SHA:0:12}"

# --------------------------------------------- LE JOURNAL : jamais muet, jamais noye ----------
# Trois appels de la MEME cause dans la meme minute : UNE ligne de journal, TROIS lignes de
# registre. Puis une cause differente : DEUX lignes de journal. C'est la regle « au plus une
# ligne par cause et par 20 min » ET « aucun tick muet », mesurees ensemble.
J="$SB/j2.txt"; R="$SB/r2.tsv"
{
  printf 'set -uo pipefail\nLOG=%q\nBUILDER_REG=%q\n' "$J" "$R"
  printf '%s\n' "$TRANCHE"
  printf 'LOG=%q\nBUILDER_REG=%q\n' "$J" "$R"
  printf 'busy=0; hard=0; idle_daemons=0\n'
  printf 'say_cause ctl "premiere"\nsay_cause ctl "deuxieme"\nsay_cause ctl "troisieme"\n'
  printf 'say_cause autre "quatrieme"\n'
  printf 'BUILDER_SAY_THROTTLE=0\nsay_cause ctl "cinquieme-sans-etranglement"\n'
} > "$SB/journal_test.sh"
( cd "$ROOT" && bash "$SB/journal_test.sh" >/dev/null 2>&1 )
J_LIG=$(grep -c . "$J" 2>/dev/null || echo 0)
R_LIG=$(grep -c . "$R" 2>/dev/null || echo 0)
pub bgb_journal_lignes "$J_LIG"
pub bgb_registre_lignes "$R_LIG"
pub bgb_journal_causes "$(cut -f3 "$R" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//' || echo -)"
# 3 appels `ctl` etrangles -> 1 ligne ; `autre` -> 2 ; `ctl` etranglement a 0 -> 3.
[ "${J_LIG:-0}" = 3 ] || { DEFAUTS=$((DEFAUTS+1)); pub bgb_journal_faute etranglement-inattendu; }
[ "${R_LIG:-0}" = 5 ] || { DEFAUTS=$((DEFAUTS+1)); pub bgb_registre_faute registre-etrangle; }

# ---------------------------------------- l'observation vivante (publiee, non jugee) ----------
# NOS PROPRES TEMOINS SONT ECARTES : ils portent GradleDaemon par construction, et les compter
# ferait dire a cette observation le contraire de ce qu'elle observe.
LIVE=0
for p in /proc/[0-9]*; do
  [ "$(cat "$p/comm" 2>/dev/null)" = java ] || continue
  case " $PIDS_NES " in *" ${p#/proc/} "*) continue ;; esac
  case "$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)" in *GradleDaemon*) LIVE=$((LIVE+1)) ;; esac
done
pub bgb_demons_gradle_vivants "$LIVE"

# AUCUN TEMOIN NE SURVIT A CE SCRIPT. On le MESURE au lieu de l'esperer : le menage tire ici,
# avant la publication, et ce qui reste vivant est un chiffre que le recensement juge.
RESTANTS=0
for p in $PIDS_NES; do kill -TERM "$p" 2>/dev/null; done
sleep 1
for p in $PIDS_NES; do kill -KILL "$p" 2>/dev/null; done
sleep 1
for p in $PIDS_NES; do [ -d "/proc/$p" ] && RESTANTS=$((RESTANTS+1)); done
pub bgb_temoins_nes "$(printf '%s' "$PIDS_NES" | wc -w)"
pub bgb_temoins_restants "$RESTANTS"

pub bgb_tranche_octets "${#TRANCHE}"
pub bgb_src_sha "$(sha256sum "$SRC" 2>/dev/null | cut -c1-16)"
pub bgb_fixture_sha "$(sha256sum "$FIX" 2>/dev/null | cut -c1-16)"
pub bgb_children_lisible "$([ -r "/proc/$$/task/$$/children" ] && echo 1 || echo 0)"
pub bgb_legs_failed "$DEFAUTS"
pub bgb_selftest_ran 1
exit 0
