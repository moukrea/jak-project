#!/usr/bin/env bash
# lib/busy_guard_selftest.sh — LE TEMOIN A DEUX BRAS DE LA GARDE « BUILD EN COURS »
# (harness-busy-guard-matches-gradle-daemon, 2026-09-14).
#
# CE QU'IL MESURE. La VRAIE `busy_reason` de `lib/proof_run.sh`, decoupee dans le fichier et
# jouee dans un bac a sable sur une liste de processus INJECTEE :
#   * un vrai build (le client Gradle, ou l'APK en cours d'ecriture)   -> REFUSE
#   * un demon Gradle seul, inactif                                     -> LAISSE PASSER
#   * un shell dont la ligne de commande NOMME gradle                   -> LAISSE PASSER
# Les verdicts sortent cote a cote, et l'ANCIENNE regle (`[g]radle` dans la ligne de commande)
# est rejouee sur les MEMES tables : elle rend « en cours » sur les trois. C'est le temoin
# « avant », mesure, pas raconte — et il ne peut pas s'accuser lui-meme apres le commit,
# puisqu'il n'est pas lu dans l'historique.
#
# POURQUOI UNE LISTE INJECTEE (harness-test-suite-is-not-a-signal, 12/09). Lire les processus
# REELS de la machine ferait dependre le verdict de ce qu'un constructeur fait a cote : un banc
# dont la reponse change selon l'heure n'est pas un signal. `busy_procs` est donc remplacee, et
# c'est exactement le contrat que `tests/harness/test_proof_busy.py` verifie sur la vraie
# `busy_reason` (elle ne parle au systeme que par cette fonction).
#
# POURQUOI UNE TRANCHE (feedback : un test qui DECOUPE une tranche mesure son propre decoupage).
# La tranche est la VRAIE definition, pas une copie : si elle disparait ou se vide, ce script
# sort en 2 sans publier, et le recensement est ROUGE. La jambe `ctl_ninja` est le controle
# positif : elle prouve que le code decoupe REPOND, sinon « tout passe » serait vert par vide.
#
# LES LIGNES DE COMMANDE SONT DES RELEVES, PAS DES INVENTIONS : `lib/fixtures/gradle-cmdlines.tsv`
# les a lues dans /proc pendant un vrai `./gradlew help` (provenance dans son en-tete).
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "bg_selftest_ran=0"; exit 2; }
AP="$ROOT/.autoport"
PR="$AP/lib/proof_run.sh"
FIX="$AP/lib/fixtures/gradle-cmdlines.tsv"
VIEUX_MOTIF='[g]radle'

pub(){ printf '%s=%s\n' "$1" "${2:--}"; }

# ------------------------------------------------------------------ la VRAIE definition ------
TRANCHE=$(python3 - "$PR" <<'PY' 2>/dev/null
import sys
src = open(sys.argv[1], encoding='utf-8', errors='replace').read()
ouv = "\nbusy_reason(){"
if ouv not in src:
    sys.exit(1)
corps = src.split(ouv, 1)[1].split("\n}\n", 1)[0]
out = "busy_reason(){%s\n}\n" % corps
# La tranche DOIT passer par l'indirection, sinon le bac a sable mesurerait son propre decor.
if "busy_procs cmdline" not in out or "busy_procs comm" not in out:
    sys.exit(1)
sys.stdout.write(out)
PY
) || { echo "bg_selftest_ran=0"; echo "bg_slice_bytes=0"; exit 2; }
[ -n "$TRANCHE" ] || { echo "bg_selftest_ran=0"; echo "bg_slice_bytes=0"; exit 2; }

# ------------------------------------------------------------------------ les releves --------
[ -s "$FIX" ] || { echo "bg_selftest_ran=0"; echo "bg_fixture_rows=0"; exit 2; }
CL_CLIENT=$(awk -F'\t' '$1=="client"{print $3}' "$FIX" | head -1)
CL_DEMON=$(awk -F'\t' '$1=="demon"{print $3}' "$FIX" | head -1)
FIX_ROWS=$(awk -F'\t' '$1=="client"||$1=="demon"{n++} END{print n+0}' "$FIX")
[ -n "$CL_CLIENT" ] && [ -n "$CL_DEMON" ] || { echo "bg_selftest_ran=0"; echo "bg_fixture_rows=$FIX_ROWS"; exit 2; }
# Le shell qui NOMME gradle sans rien batir : la course de CET item porte le mot dans son
# propre argument, c'est la troisieme population que l'ancienne regle confondait.
CL_SHELL="bash .autoport/lib/proof_run.sh harness-busy-guard-matches-gradle-daemon x86"

SB=$(mktemp -d "${TMPDIR:-/tmp}/busyguard.XXXXXX") || { echo "bg_selftest_ran=0"; exit 2; }
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/apk"
APK="$SB/apk/app-jak1-debug.apk"
: > "$APK"

# `busy_procs` remplacee : meme contrat que le banc de tests (comm = nom entier, cmdline = ligne
# entiere). C'est la SEULE porte de `busy_reason` vers le systeme.
banc(){                     # $1=comms  $2=cmdlines  $3=age de l'APK en secondes (-1 = pas d'APK)
  local comms=$1 cmds=$2 age=$3 s="$SB/banc.sh"
  if [ "$age" -lt 0 ]; then rm -f "$APK"; else : > "$APK"; touch -d "@$(( $(date +%s) - age ))" "$APK"; fi
  {
    printf 'set -uo pipefail\nAP=.autoport\nlog(){ :; }\n'
    printf 'COMMS=%s\nCMDLINES=%s\n' "$(printf '%q' "$comms")" "$(printf '%q' "$cmds")"
    printf 'busy_procs(){\n  case "$1" in\n'
    printf '    comm)    printf "%%s\\n" "$COMMS"    | grep -qxE "$2" ;;\n'
    printf '    cmdline) printf "%%s\\n" "$CMDLINES" | grep -qE  "$2" ;;\n'
    printf '    *)       return 1 ;;\n  esac\n}\n'
    printf '%s\n' "$TRANCHE"
    printf 'busy_reason\n'
  } > "$s"
  ( cd "$SB" && AUTOPORT_BUSY_APK_GLOB="$SB/apk/*.apk" bash "$s" 2>/dev/null )
}
# L'ANCIENNE REGLE, rejouee sur la MEME table : une seule ligne, celle qui a ete retiree.
vieille(){                  # $1=cmdlines -> 1 si elle aurait bloque
  if printf '%s\n' "$1" | grep -qE "$VIEUX_MOTIF"; then echo 1; else echo 0; fi
}

DEFAUTS=0
leg(){                      # $1=nom $2=attendu(regex ancree, ou VIDE) $3=comms $4=cmdlines $5=age APK
  local nom=$1 att=$2 got ok
  got=$(banc "$3" "$4" "$5")
  # `grep -qE '^$'` ne rend RIEN sur une entree vide : elle n'a pas de ligne. « la garde laisse
  # passer » se teste donc sur l'absence de sortie, pas sur un motif.
  if [ "$att" = VIDE ]; then
    if [ -z "$got" ]; then ok=1; else ok=0; DEFAUTS=$((DEFAUTS+1)); fi
  elif printf '%s' "$got" | grep -qE "$att"; then ok=1; else ok=0; DEFAUTS=$((DEFAUTS+1)); fi
  pub "bg_leg_${nom}_ok" "$ok"
  pub "bg_leg_${nom}_got" "$(printf '%s' "${got:-VIDE}" | tr ' \t\n' '___')"
}

# 0. CONTROLE POSITIF : le code decoupe REPOND. Sans lui, une tranche vide rendrait « tout
#    passe » et les deux bras seraient verts par inaction.
leg ctl_ninja '^processus \[n\]inja' "ninja" "ninja -C build-android" -1
# 1. UN VRAI BUILD : le client Gradle releve dans /proc pendant `./gradlew help`.
leg build_client '^processus \[g\]radle en cours$' "java" "$CL_CLIENT" -1
# 2. UN VRAI BUILD QUI LIVRE : l'APK reecrit a l'instant, demon present.
leg build_apk '^APK reecrit il y a [0-9]+s$' "java" "$CL_DEMON" 3
# 3. LE DEMON SEUL, INACTIF : APK vieux de deux heures. Il doit PASSER.
leg demon_idle VIDE "java" "$CL_DEMON" 7200
# 4. UN SHELL QUI NOMME GRADLE — la course de cet item elle-meme. Elle doit PASSER.
leg shell_nomme_gradle VIDE "bash" "$CL_SHELL" 7200

# ------------------------------------------------- le temoin « avant », sur les MEMES tables --
# L'ancienne regle ne distingue pas : elle bloque les trois. Non nul = le defaut existait.
V_CLIENT=$(vieille "$CL_CLIENT"); V_DEMON=$(vieille "$CL_DEMON"); V_SHELL=$(vieille "$CL_SHELL")
pub bg_vieille_regle_client "$V_CLIENT"
pub bg_vieille_regle_demon "$V_DEMON"
pub bg_vieille_regle_shell "$V_SHELL"
pub bg_vieille_regle_bloque_a_tort $(( V_DEMON + V_SHELL ))

# LA DONNEE, LUE DIRECTEMENT : le motif retenu est-il DANS la ligne du demon ? Non. Dans celle
# du client ? Oui. C'est le fait sur lequel toute la separation repose ; il se lit sans bac a sable.
NOUVEAU_MOTIF='[G]radleWrapperMain|org\.[g]radle\.launcher\.GradleMain|[G]radleWorkerMain|[g]radle-wrapper\.jar'
pub bg_motif_dans_demon  "$(printf '%s\n' "$CL_DEMON"  | grep -cE "$NOUVEAU_MOTIF")"
pub bg_motif_dans_client "$(printf '%s\n' "$CL_CLIENT" | grep -cE "$NOUVEAU_MOTIF")"
# Le motif du script et celui relu ici doivent etre le MEME : deux litteraux divergent en silence.
pub bg_motif_est_celui_du_script \
  "$(grep -cF -- "$NOUVEAU_MOTIF" "$PR" 2>/dev/null)"

# ---------------------------------------- l'observation vivante (publiee, non jugee) ----------
# S'il y a un demon Gradle VIVANT sur cette machine a la seconde ou ce script tourne, on dit ce
# que chaque regle en fait. Machine-dependant par nature : c'est une OBSERVATION, le verdict est
# porte par les jambes ci-dessus.
LIVE_PID=-1; LIVE_OLD=-1; LIVE_NEW=-1
for p in /proc/[0-9]*; do
  [ "$(cat "$p/comm" 2>/dev/null)" = java ] || continue
  l=$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null) || continue
  case "$l" in *GradleDaemon*) ;; *) continue ;; esac
  LIVE_PID=${p#/proc/}
  LIVE_OLD=$(printf '%s\n' "$l" | grep -cE "$VIEUX_MOTIF")
  LIVE_NEW=$(printf '%s\n' "$l" | grep -cE "$NOUVEAU_MOTIF")
  break
done
pub bg_live_daemon_pid "$LIVE_PID"
pub bg_live_vieille_regle "$LIVE_OLD"
pub bg_live_nouvelle_regle "$LIVE_NEW"

pub bg_slice_bytes "${#TRANCHE}"
pub bg_fixture_rows "$FIX_ROWS"
pub bg_fixture_sha "$(sha256sum "$FIX" 2>/dev/null | cut -c1-16)"
pub bg_legs_failed "$DEFAUTS"
pub bg_selftest_ran 1
exit 0
