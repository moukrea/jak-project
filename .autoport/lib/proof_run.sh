#!/usr/bin/env bash
# lib/proof_run.sh — LE PRODUCTEUR DE PREUVE. C'est lui, et personne d'autre, qui ecrit
# `.autoport/reports/<item-id>/proof.txt`. Le worker ne peut taper aucun de ses champs :
# `source=`, `serial=`, `binary=`, `sha=`, `started_at=`, `duration_s=`, `crash=`, `frames=`
# sortent de la machine. Tout le reste est RECOPIE mot pour mot de la sortie du moteur.
#
# POURQUOI. Les 19 derniers validateurs ont juge 116 fois un texte ecrit par le worker et 0
# fois un binaire. Le chemin le plus court vers le vert etait donc « ecrire la ligne qui
# manque ». Ce fichier ferme ce chemin : un proof.txt ecrit a la main ne porte pas le sha du
# binaire present sur le disque, et le validateur le recalcule.
#
# POSER UN REGLAGE DE COURSE — LE SEUL CHEMIN QUI SURVIT (harness-proof-props-pin, 2026-09-12)
# --------------------------------------------------------------------------------------------
# Un worker qui veut epingler le regime de SA course (une sortie HDR, un drapeau Recharged, une
# echelle de rendu) ECRIT SON REGLAGE DANS L'ITEM DU BACKLOG :
#
#     proof_props:                      # course APPAREIL  -> `adb shell setprop`
#       - debug.opengoal.hdr.out=2
#     proof_env:                        # course x86       -> variable d'environnement
#       - OG_RECHARGED=1
#
# Il ne le pose JAMAIS par un `adb shell setprop` depuis l'hote avant de lancer la course :
# `lib/device_teardown.sh`, lance ici meme AVANT l'amorcage, efface TOUTES les
# `debug.opengoal.*` qu'il trouve sur l'appareil. Une propriete posee a la main meurt donc entre
# sa pose et la course, et la course mesure l'AUTRE regime sans que rien ne le dise. Seul
# `proof_props` survit : il voyage dans une variable de ce script et se repose APRES le teardown.
#
# CE QUE LA PREUVE PORTE DESORMAIS, pour que l'epinglage soit VERIFIABLE sans relire le backlog :
#   teardown_props_found / teardown_props_list   ce qui etait pose a l'arrivee, par son nom
#   proof_props_file / proof_props_extracted     ce que le fichier porte, ce qu'on en a tire
#   proof_props_effective / proof_props_lost     ce que l'appareil rend, et l'ECART avec le fichier
#   proof_prop_obs_<cle>                         la valeur RELUE apres l'amorcage, une par propriete
#
# Usage : lib/proof_run.sh <item-id> <x86|device> [--timeout N] [--off]
#   HDR x86/device: --hdr-campaign NOM --hdr-vantages vue[,vue] --hdr-hours 0,3,...
#   x86: --hdr-env OG_KEY=VALUE (repeatable); device: --hdr-prop debug.opengoal.KEY=VALUE (repeatable); --hdr-replace LOT:VUE:HEURE=VUE
#   --off   meme course, feature DESARMEE, ecrit proof-off.txt (controle d'ablation).
#
# Sorties : 0 = une preuve a ete ecrite (VERTE OU ROUGE : c'est le validateur qui juge).
#           2 = usage / item invalide.
#           3 = infrastructure (build en cours au-dela du plafond, binaire absent, appareil
#               absent). AUCUN proof.txt n'est ecrit et l'ancien est retire : une preuve doit
#               venir de la course qu'on vient de faire, jamais d'une course d'hier.
#
# CE QUE LE MOTEUR DOIT EMETTRE (pas encore branche — voir le rapport du chantier C) : lire
# `AUTOPORT_FEATURE`/`AUTOPORT_FEATURE_ARMED` (x86, environnement) ou `debug.opengoal.feature`
# et `debug.opengoal.feature.armed` (appareil, proprietes), puis ecrire
#     FEATURE <item-id> armed=<0|1> hits=<n>
# et une ligne `cle=valeur` SEULE SUR SA LIGNE par grandeur mesuree. Tant que ce n'est pas
# fait, ce script produit une preuve HONNETE ou la ligne FEATURE est absente — et le
# validateur est ROUGE. C'est le comportement voulu : on ne fabrique pas la ligne manquante.
set -uo pipefail

# ---------------------------------------------------------------------------- arguments ----
ID=""; MODE=""; TIMEOUT=""; OFF=0
HDR_CAMPAIGN=""; HDR_VANTAGES="legacy"; HDR_HOURS="0,3,6,9,12,15,18,21"
HDR_AGGREGATE=""; HDR_PROPS=(); HDR_ENVS=(); HDR_REPLACE=(); HDR_BATCH=""; HDR_REMOTE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --off)     OFF=1; shift ;;
    --hdr-campaign|--hdr-vantages|--hdr-hours|--hdr-prop|--hdr-env|--hdr-replace|--hdr-aggregate-only)
      [ $# -ge 2 ] && [ -n "$2" ] || { echo "proof_run: $1 needs a value" >&2; exit 2; }
      case "$1" in
        --hdr-campaign) HDR_CAMPAIGN=$2 ;;
        --hdr-aggregate-only) HDR_AGGREGATE=$2 ;;
        --hdr-vantages) HDR_VANTAGES=$2 ;;
        --hdr-hours) HDR_HOURS=$2 ;;
        --hdr-prop) HDR_PROPS+=("$2") ;;
        --hdr-env) HDR_ENVS+=("$2") ;;
        --hdr-replace) HDR_REPLACE+=(--replace "$2") ;;
      esac
      shift 2 ;;
    -h|--help) sed -n '1,30p' "$0"; exit 0 ;;
    -*)        echo "proof_run: option inconnue '$1'" >&2; exit 2 ;;
    *)         if [ -z "$ID" ]; then ID="$1"; elif [ -z "$MODE" ]; then MODE="$1";
               else echo "proof_run: argument en trop '$1'" >&2; exit 2; fi; shift ;;
  esac
done
[ -n "$ID" ] && [ -n "$MODE" ] || { echo "usage: lib/proof_run.sh <item-id> <x86|device> [--timeout N] [--off]" >&2; exit 2; }
case "$ID" in *[!a-z0-9-]*|"") echo "proof_run: item-id '$ID' invalide (kebab-case minuscule)" >&2; exit 2 ;; esac
case "$MODE" in x86|device) ;; *) echo "proof_run: mode '$MODE' inconnu (x86|device)" >&2; exit 2 ;; esac

if [ -n "$HDR_CAMPAIGN" ]; then
  [ "$ID" = lighting-hdr ] && [ "$OFF" = 0 ] || {
    echo "proof_run: HDR batches require lighting-hdr without --off" >&2; exit 2; }
  case "$HDR_CAMPAIGN" in *[!a-zA-Z0-9_-]*) echo "invalid HDR campaign name" >&2; exit 2 ;; esac
fi
if [ -n "$HDR_AGGREGATE" ]; then
  [ -n "$HDR_CAMPAIGN" ] || { echo "aggregate-only needs --hdr-campaign" >&2; exit 2; }
  case "$HDR_AGGREGATE" in *[!a-zA-Z0-9_-]*) echo "invalid HDR batch name" >&2; exit 2 ;; esac
fi
if { [ "$MODE" = x86 ] && [ "${#HDR_PROPS[@]}" -gt 0 ]; } ||
   { [ "$MODE" = device ] && [ "${#HDR_ENVS[@]}" -gt 0 ]; }; then
  echo "proof_run: use --hdr-env for x86 and --hdr-prop for device" >&2; exit 2
fi
for kvp in "${HDR_ENVS[@]}"; do
  [[ "$kvp" =~ ^OG_[A-Z0-9_]+= ]] && [[ "$kvp" != *$'\n'* ]] || {
    echo "proof_run: invalid HDR environment" >&2; exit 2; }
  case "${kvp%%=*}" in OG_REFSET|OG_REFSET_DIR|OG_REFSET_PHASES|OG_REFSET_VANTAGES|OG_REFSET_HOURS|OG_LIGHTING|OG_RT_LIGHT)
    echo "proof_run: environment reserved by HDR campaign" >&2; exit 2 ;;
  esac
done
for kvp in "${HDR_PROPS[@]}"; do
  [[ "$kvp" =~ ^debug\.opengoal\.[a-zA-Z0-9_.]+=[a-zA-Z0-9_.,:/+\ -]*$ ]] || {
    echo "proof_run: invalid HDR property" >&2; exit 2; }
  case "${kvp%%=*}" in debug.opengoal.feature*|debug.opengoal.refset|debug.opengoal.refset.dir|debug.opengoal.refset.phases|debug.opengoal.refset.vantages|debug.opengoal.refset.hours|debug.opengoal.lighting|debug.opengoal.rt.light)
    echo "proof_run: property reserved by HDR campaign" >&2; exit 2 ;; esac
done

# --- PROLOGUE-SANS-DOSSIER : les trois seules sorties 3 qui ne peuvent PAS ecrire d'etat
# nomme, parce qu'a ce point on ne sait pas encore ou l'ecrire. Tout ce qui suit passe par
# `die3`. La porte de l'item `harness-attempt-not-burned-by-foreign-cause` compte les
# sorties 3 nues APRES ce bloc : il doit y en avoir zero.
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "proof_run: pas dans un depot git" >&2; exit 3; }
cd "$ROOT" || exit 3
AP=.autoport
D=$AP/reports/$ID
mkdir -p "$D" || exit 3
SUF=""; [ "$OFF" = 1 ] && SUF="-off"
OUTFILE="$D/proof$SUF.txt"
RAWLOG="$D/proof$SUF-engine.log"
ARMED=1; [ "$OFF" = 1 ] && ARMED=0

log(){ printf '[proof_run %s] %s\n' "$ID" "$*" >&2; }
# --- FIN-DU-PROLOGUE-SANS-DOSSIER ---

# UNE PREUVE IMPOSSIBLE SE LIT « IMPOSSIBLE », JAMAIS « PAS PRODUITE ». Ce script sortait en 3
# en EFFACANT proof.txt et sans rien ecrire d'autre : binaire absent, appareil absent, ou
# verrou de deploiement tenu au-dela de la borne. Le 2026-09-12 le constructeur a tenu
# `.autoport/.deploy-in-progress` 6 h 38 d'affilee — aucune preuve n'etait possible pendant ce
# temps et aucun compteur ne le disait. `die3` ecrit un etat NOMME a cote de proof.txt (jamais
# DEDANS : une preuve impossible ne devient pas une preuve parce qu'on l'a nommee), puis sort
# en 3 comme avant.
WAITED_S=0          # secondes reellement attendues qu'un build finisse
BUSY_WHY=""         # ce qui occupait la machine, tel que busy_reason l'a nomme
die3(){
  local raison="$1"; shift
  local detail="$*"
  log "PREUVE IMPOSSIBLE ($raison) : $detail"
  rm -f "$OUTFILE"
  bash "$AP/lib/proof_impossible.sh" "$D" "$ID" "$SUF" "$raison" "$detail" \
       "$WAITED_S" "${WAITMAX:-0}" "$BUSY_WHY" || true
  exit 3
}

# Une ligne de plus dans le bloc que proof.txt recopie apres les champs de la machine. Les cles
# posees ici viennent du RUNNER (ce qu'il a lu, pose, relu), jamais du moteur.
EXTRA=""
extra(){ EXTRA="${EXTRA:+$EXTRA
}$*"; }
# `debug.opengoal.hdr.out` -> `hdr_out` : la cle de proof.txt doit tenir dans [A-Za-z0-9_].
prop_key(){ printf '%s' "${1#debug.opengoal.}" | tr -c 'A-Za-z0-9_' '_'; }

# NORMALISATION DE LA SORTIE DU MOTEUR. Rien n'arrive nu : sur x86 le journal prefixe chaque
# ligne du temps ecoule (`    4.423 CINEVP ...`), sur l'appareil `logcat -v time` prefixe la
# date, le niveau, le tag et le pid (`09-03 10:12:44.123 I/GK_STDOUT( 1234): ...`). Ancrer un
# motif sur `^` sans enlever ces prefixes, c'est ne rien trouver, jamais.
norm(){ sed -E 's/\r$//
                s/^[0-9]{2}-[0-9]{2} [0-9:.]+ +[A-Z]\/[^(]*\( *[0-9]+\): *//
                s/^[[:space:]]*[0-9]+\.[0-9]+[[:space:]]+//
                s/^\[[0-9:]+\] *//' "$1"; }

# ---------------------------------------------------------- l'item, s'il est deja ecrit ----
# lib/backlog.py est le chantier D et peut ne pas exister encore : on retombe alors sur une
# lecture directe du yaml, et a defaut sur les valeurs par defaut. Un runner qui meurt parce
# qu'un fichier d'un autre chantier n'est pas la ne prouve rien du tout.
ITEM_SERIAL=""; ITEM_TIMEOUT=""; ENVS=(); PROPS=()
# CE QUE LE FICHIER PORTE, avant tout filtrage : le premier des trois chiffres de la trace. Un
# `proof_props` de trois lignes dont une sans `=` rend ici 3 et extrait 2 ; sans ce compte, la
# ligne perdue serait invisible et la course mesurerait un regime incomplet en silence.
ITEM_PROP_FILE=0; ITEM_ENV_FILE=0
while IFS= read -r line; do
  case "$line" in
    ITEM_SERIAL=*)  ITEM_SERIAL=${line#ITEM_SERIAL=} ;;
    ITEM_TIMEOUT=*) ITEM_TIMEOUT=${line#ITEM_TIMEOUT=} ;;
    ITEM_ENV=*)     ENVS+=("${line#ITEM_ENV=}") ;;
    ITEM_PROP=*)    PROPS+=("${line#ITEM_PROP=}") ;;
    ITEM_PROP_FILE=*) ITEM_PROP_FILE=${line#ITEM_PROP_FILE=} ;;
    ITEM_ENV_FILE=*)  ITEM_ENV_FILE=${line#ITEM_ENV_FILE=} ;;
  esac
done < <(python3 - "$ID" 2>/dev/null <<'PY'
import sys, os
sys.path.insert(0, os.path.join('.autoport', 'lib'))
it = None
try:
    import backlog
    it = backlog.load().get(sys.argv[1])
except Exception:
    try:
        import yaml
        doc = yaml.safe_load(open('.autoport/backlog.yaml', encoding='utf-8')) or {}
        for cand in (doc.get('items') or []):
            if cand.get('id') == sys.argv[1]:
                it = cand
                break
    except Exception:
        it = None
if not it:
    raise SystemExit(0)
if it.get('device_serial'):
    print("ITEM_SERIAL=%s" % it['device_serial'])
if it.get('proof_timeout'):
    print("ITEM_TIMEOUT=%s" % it['proof_timeout'])
for key, tag in (('proof_env', 'ITEM_ENV'), ('proof_props', 'ITEM_PROP')):
    val = it.get(key) or []
    if isinstance(val, str):
        val = [val]
    # Ce que le FICHIER porte : compte AVANT le filtre `=`. C'est le premier des trois chiffres
    # que la preuve publie ; l'ecart avec le second nomme les lignes que ce lecteur a jetees.
    print("%s_FILE=%d" % (tag, len(val)))
    for entry in val:
        entry = str(entry).replace("\n", " ")
        if "=" in entry:
            print("%s=%s" % (tag, entry))
PY
)

# --------------------------------------------------------------------- le binaire juge ----
if [ "$MODE" = x86 ]; then
  BIN=build/game/gk
else
  BIN=build-android/lib/arm64-v8a/libgk.so   # le build ARM64 LIVRE. build-arm64/ n'a jamais
fi                                            # produit de binaire : c'est un faux rouge.
if [ ! -s "$BIN" ]; then
  die3 binaire-absent "$BIN est absent ou vide : rien a juger"
fi
# Recompute from an immutable existing run, preserving its original execution
# timestamp and counters. This path performs no device action and never freshens a run.
if [ -n "$HDR_AGGREGATE" ]; then
  rm -f "$OUTFILE"
  HDR_BATCH="$D/batches/$HDR_CAMPAIGN/$HDR_AGGREGATE"
  TMP="$D/.proof$SUF.tmp.$$"
  if ! python3 - "$HDR_BATCH" "$BIN" "$MODE" > "$TMP" <<'HDR_REPLAY'
import datetime, hashlib, json, os, re, sys
from pathlib import Path
sys.path.insert(0, '.autoport/lib')
import hdr_batches as hdr
batch, binary = Path(sys.argv[1]), Path(sys.argv[2])
m = json.loads((batch / 'manifest.json').read_text())
if hdr.sha(binary) != m['provenance']['binary_sha256']:
    raise SystemExit('HDR aggregate: current binary differs from original run')
source = m['provenance'].get('source', 'device')
if source != sys.argv[3]:
    raise SystemExit('HDR aggregate: execution source mismatch')
if source == 'x86' and hdr.source_snapshot(Path('.')) != m['provenance']['sources']:
    raise SystemExit('HDR aggregate: current sources differ from original run')
run = m['run']
if not re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ', run['started_at'] or ''):
    raise SystemExit('HDR aggregate: original timestamp unavailable')
raw = hdr.normalized((batch / 'engine.log').read_text(errors='replace'))
values = hdr.kv(raw)
measures = hdr.aggregate(batch.parent, batch.name, hdr.contract(Path('.')))
print('source=' + source)
if source == 'device':
    print('serial=' + m['provenance']['serial'])
print('binary=' + str(binary))
print('sha=' + hdr.sha(binary)[:16])
print('started_at=' + run['started_at'])
print('duration_s=' + str(run['duration_s']))
print('crash=' + str(m['crash']))
pattern = (r'^(?:PACE-SWAP-X86|AUTOPORT-FRAMES) n=(\d+)' if source == 'x86'
           else r'^(?:A35-RENDER frame|PACE-SWAP n|AUTOPORT-FRAMES n)=(\d+)')
frames = re.findall(pattern, raw, re.M)
count = max(map(int, frames), default=0)
print('frames=' + str(count + int(source == 'x86' and count > 0)))
feature = re.findall(r'^FEATURE lighting-hdr armed=[01] hits=\d+.*$', raw, re.M)
if feature:
    print(feature[-1])
reserved = {'source', 'serial', 'binary', 'sha', 'started_at', 'duration_s', 'crash', 'frames',
            'local_lib_md5', 'device_lib_md5', 'device_serial', 'device_model'}
for key, value in values.items():
    if key not in reserved and key not in measures:
        print(key + '=' + value)
for key, value in measures.items():
    print(key + '=' + str(value))
print('hdr_batch_manifest=' + str(batch / 'manifest.json'))
sys.stdout.flush()
original_end = datetime.datetime.fromisoformat(run['started_at'].replace('Z', '+00:00')).timestamp() + run['duration_s']
os.utime(sys.stdout.fileno(), (original_end, original_end))
HDR_REPLAY
  then
    rm -f "$TMP"; die3 hdr-replay "l'agregation HDR du lot $HDR_BATCH a echoue"
  fi
  mv -f "$TMP" "$OUTFILE"
  log "recomputed $OUTFILE from $HDR_BATCH with original timestamp"
  exit 0
fi

[ -n "$TIMEOUT" ] || TIMEOUT="$ITEM_TIMEOUT"
if [ -z "$TIMEOUT" ]; then if [ "$MODE" = x86 ]; then TIMEOUT=120; else TIMEOUT=180; fi; fi
case "$TIMEOUT" in *[!0-9]*|"") echo "proof_run: --timeout '$TIMEOUT' n'est pas un entier" >&2; exit 2 ;; esac

# ------------------------------------------- les sources qui PRODUISENT CE verdict, epinglees ----
# harness-verdict-integrity, 2026-09-12. Le validateur epinglait la fraicheur du MOTEUR
# (`game/ common/ android/ goal_src/`) et ignorait `.autoport/`. Le verdict d'un item de harnais
# vit pourtant dans `lib/census/<id>.sh` et dans les scripts qu'il appelle : editables APRES la
# course, sans temoin. On publie ICI — AVANT la course, AVANT le recensement, donc avant que
# quoi que ce soit puisse se reecrire sous la porte — le nombre de fichiers epingles et leur
# empreinte. `validators/generic.sh` la RECALCULE a la lecture : une valeur recopiee ne prouve
# que la recopie. La liste sort du meme nommeur des deux cotes (lib/verdict_sources.sh).
while IFS= read -r vsl; do [ -n "$vsl" ] && extra "$vsl"; done < <(bash "$AP/lib/verdict_sources.sh" "$ID" kv 2>/dev/null)

# ------------------------------------------------------- attendre qu'aucun build n'ecrive ----
# Un gk lance pendant que auto_build_apk.sh reecrit out/jak1/iso/ meurt en SIGILL sur un
# KERNEL.CGO a moitie ecrit, et un `--target gk` partiel casse l'ABI de goalc. Ces deux
# accidents ont ete lus comme des defauts du jeu. Ici on ATTEND : on ne rend jamais un faux
# rouge parce qu'un builder tournait.
WAITMAX="${AUTOPORT_PROOF_WAIT_MAX:-1800}"
# LA SEULE PORTE DE SORTIE DE CETTE GARDE VERS LE SYSTEME (harness-test-suite-is-not-a-signal,
# 2026-09-12). `busy_reason` n'interroge plus les processus en direct : elle passe par ici, et le
# banc de tests remplace CETTE fonction par une liste INJECTEE. Avant, le test qui verifie qu'un
# prompt citant « ninja » ne bloque pas lisait les processus REELS de la machine : il rougissait
# des qu'un vrai constructeur arm64 tournait au meme moment. Un test dont le verdict depend de ce
# que la machine fait a cote n'est pas un signal.
#   $1 = comm     -> le NOM du processus, correspondance ENTIERE (pgrep -x)
#   $2 = cmdline  -> la LIGNE DE COMMANDE complete, correspondance partielle (pgrep -f)
# Le lanceur Java ne s'appelle pas « gradle » : son nom est « java » et l'outil vit dans ses
# arguments. C'est pourquoi les deux lectures existent, et pourquoi elles ne sont pas
# interchangeables : chercher « goalc » dans les lignes de commande accuserait le prompt qui
# cite `goalc/`.
busy_procs(){
  case "$1" in
    comm)    pgrep -x "$2" >/dev/null 2>&1 ;;
    cmdline) pgrep -f "$2" >/dev/null 2>&1 ;;
    *)       return 1 ;;
  esac
}
busy_reason(){
  local f="$AP/.deploy-in-progress" p pat cgo age
  if [ -f "$f" ]; then
    p=$(sed -n 's/.*pid=\([0-9]\{1,\}\).*/\1/p' "$f" | head -1)
    # Un verrou dont le PID est MORT ne vaut rien : le shell d'un appel d'outil sort dans la
    # seconde et laisse un verrou qui nomme un cadavre. On l'ignore, en le disant.
    if [ -n "${p:-}" ] && kill -0 "$p" 2>/dev/null; then echo "deploy-in-progress pid=$p vivant"; return 0; fi
    [ -n "${p:-}" ] && log "verrou $f ignore : pid=$p est mort"
  fi
  # Les compilateurs se reconnaissent au nom du processus : le prompt d'un superviseur
  # peut contenir « goalc/ » dans ses arguments sans qu'aucun compilateur tourne.
  for pat in '[n]inja(-build)?' '[g]oalc' '[c]c1plus'; do
    if busy_procs comm "$pat"; then echo "processus $pat en cours"; return 0; fi
  done
  # Le lanceur Java porte le nom de l'outil dans ses arguments.
  if busy_procs cmdline '[g]radle'; then echo "processus [g]radle en cours"; return 0; fi
  cgo=out/jak1/iso/GAME.CGO
  if [ -f "$cgo" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$cgo" 2>/dev/null || echo 0) ))
    if [ "$age" -lt 60 ]; then echo "GAME.CGO reecrit il y a ${age}s"; return 0; fi
  fi
  echo ""; return 0
}
waited=0
first_why=""
while :; do
  why=$(busy_reason)
  [ -z "$why" ] && break
  [ -z "$first_why" ] && first_why=$why
  if [ "$waited" -ge "$WAITMAX" ]; then
    WAITED_S=$waited; BUSY_WHY=$why
    die3 build-en-cours "un build ecrit encore apres ${waited}s (borne ${WAITMAX}s) : $why"
  fi
  [ "$waited" = 0 ] && log "attente : $why"
  sleep 15; waited=$((waited+15))
done
[ "$waited" -gt 0 ] && log "build fini apres ${waited}s d'attente, on mesure."
WAITED_S=$waited
BUSY_WHY=$first_why

# LE VERROU, MESURE MEME QUAND ON N'A PAS ATTENDU. Un `proof_wait_s=0` ne dit rien tout seul :
# il faut savoir s'il y avait un verrou, s'il repondait encore, et depuis quand il etait la.
# Le 2026-09-12 le constructeur a tenu le sien 6 h 38 sans qu'aucune grandeur ne le dise.
LOCK_F="$AP/.deploy-in-progress"; LOCK_PID="-"; LOCK_ALIVE=0; LOCK_AGE=-1
if [ -f "$LOCK_F" ]; then
  LOCK_PID=$(sed -n 's/.*pid=\([0-9]\{1,\}\).*/\1/p' "$LOCK_F" | head -1); LOCK_PID=${LOCK_PID:--}
  [ "$LOCK_PID" != "-" ] && kill -0 "$LOCK_PID" 2>/dev/null && LOCK_ALIVE=1
  LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_F" 2>/dev/null || date +%s) ))
fi
extra "proof_wait_s=$WAITED_S"
extra "proof_wait_max_s=$WAITMAX"
extra "proof_wait_why=${BUSY_WHY:--}"
extra "deploy_lock_pid=$LOCK_PID"
extra "deploy_lock_alive=$LOCK_ALIVE"
extra "deploy_lock_age_s=$LOCK_AGE"
# LE MEME ETAT, LU PAR LE RECENSEMENT DE CETTE COURSE. proof.txt n'existe pas encore quand le
# recensement tourne : sans ce fichier, un item de harnais ne pourrait juger l'attente que sur
# du texte de script. Ecrit ici, il vient de LA course en train de se faire.
{
  echo "proof_wait_s=$WAITED_S"
  echo "proof_wait_max_s=$WAITMAX"
  echo "proof_wait_why=${BUSY_WHY:--}"
  echo "deploy_lock_pid=$LOCK_PID"
  echo "deploy_lock_alive=$LOCK_ALIVE"
  echo "deploy_lock_age_s=$LOCK_AGE"
  echo "proof_wait_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$D/proof$SUF-wait.txt"

# L'ECRIVAIN ET LE LECTEUR, VERIFIES L'UN CONTRE L'AUTRE, A CHAQUE COURSE (NOMMAGE/un-seul-endroit).
# Le fichier qu'on vient d'ecrire doit porter EXACTEMENT le nom que `lib/impossible.py` derive
# pour CE bras : ce module est le seul que les recensements interrogent. Le 12/09, le bras
# d'ablation ecrivait son attente pendant qu'un lecteur cherchait un nom code EN DUR, celui du
# bras livre : l'attente de l'ablation n'etait lue par personne, sous une porte verte. On ne le
# detecte pas apres coup — une divergence de nom ne survit plus a une course.
WAITNAME=$(python3 "$AP/lib/impossible.py" name wait "$SUF" 2>/dev/null)
[ -s "$D/${WAITNAME:-nom-non-derive}" ] || die3 nommage-divergent \
  "l'attente de ce bras n'est pas lisible sous le nom que lib/impossible.py derive ('${WAITNAME:--}') : un lecteur du bras '${SUF:-livre}' lirait un fichier que personne n'ecrit"
log "attente de ce bras publiee sous '$WAITNAME', nom derive par lib/impossible.py"

# HYGIENE DES ETATS « PREUVE IMPOSSIBLE » (PURGE/etat-perime). Un etat qui ne decrit plus le
# present s'en va ICI, au point de production : celui de cet item et de CE bras, qu'on est en
# train de re-mesurer, et ceux des AUTRES items, que plus personne n'essaie. L'autre bras de cet
# item n'est jamais touche : une ablation impossible pendant qu'on mesure le bras livre doit
# rester lisible, sinon un essai brulerait pour une machine indisponible que plus rien ne
# nommerait. Non bloquant : l'hygiene ne doit jamais empecher une mesure.
if PURGED=$(python3 "$AP/lib/impossible.py" purge --reports "$AP/reports" --item "$ID" --arm "$SUF" 2>&1); then
  log "hygiene des etats impossibles : $(printf '%s' "$PURGED" | tail -1)"
else
  log "hygiene des etats impossibles : echec (non bloquant) — $(printf '%s' "$PURGED" | tail -1)"
fi

# La preuve doit venir de la course qu'on lance MAINTENANT. On retire l'ancienne d'abord :
# si la course echoue, il ne reste rien qui puisse passer une porte. L'etat nomme de la course
# PRECEDENTE part avec elle : une cle de texte qu'on ne vide jamais finit par accuser une
# course qui n'existe plus.
rm -f "$OUTFILE" "$D/proof$SUF-impossible.txt"

SHA=$(sha256sum "$BIN" | cut -c1-16)
STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
T0=$(date +%s)
CRASH=0; FRAMES=0; SERIAL=""

# L'ENVIRONNEMENT DU PROCESSUS MESURE, PAS CELUI DU SHELL QUI EXPORTE
# (harness-verdict-integrity, 2026-09-12). La boucle d'export relit `printenv` : elle attrape un
# `export` refuse, jamais un lanceur qui filtrerait l'environnement. Le cote appareil n'a pas ce
# trou — `proof_prop_obs_*` interroge l'appareil lui-meme. Ici on lit `/proc/<pid>/environ` du
# `gk` REELLEMENT lance. `timeout` forke : le processus mesure est son ENFANT, et on l'identifie
# par son `exe`, jamais par un nom. UNE SEULE definition pour les DEUX lancements x86 (course
# ordinaire et campagne HDR) : un lecteur ecrit deux fois diverge, et la moitie non corrigee
# publierait « epingle » sans avoir rien lu.
lire_environ_mesure(){  # lire_environ_mesure <pid-du-lanceur>
  local lanceur=$1 binreal mpid mexe procenv obs kvp
  local lu=0 nb=-1 match=0 liste="" shellnb
  binreal=$(readlink -f "$BIN" 2>/dev/null)
  mpid=""; mexe="-"
  for _try in $(seq 1 40); do
    for cand in $(pgrep -P "$lanceur" 2>/dev/null) "$lanceur"; do
      [ "$(readlink -f "/proc/$cand/exe" 2>/dev/null)" = "$binreal" ] || continue
      mpid="$cand"; mexe=$(basename "$binreal"); break
    done
    [ -n "$mpid" ] && break
    kill -0 "$lanceur" 2>/dev/null || break
    sleep 0.25
  done
  shellnb=$(printenv | grep -cE '^[A-Za-z_][A-Za-z0-9_]*=')
  if [ -n "$mpid" ] && [ -r "/proc/$mpid/environ" ]; then
    procenv="$D/.procenv$SUF.$$"
    tr '\0' '\n' < "/proc/$mpid/environ" > "$procenv" 2>/dev/null
    if [ -s "$procenv" ]; then
      lu=1
      nb=$(grep -cE '^[A-Za-z_][A-Za-z0-9_]*=' "$procenv")
      for kvp in ${ENVS+"${ENVS[@]}"}; do
        obs=$(sed -n "s/^${kvp%%=*}=//p" "$procenv" | tail -1)
        extra "proof_env_proc_obs_$(prop_key "${kvp%%=*}")=${obs:--}"
        liste="${liste:+$liste,}${kvp%%=*}"
        [ "$obs" = "${kvp#*=}" ] && match=$((match+1))
      done
    fi
    rm -f "$procenv"
  fi
  [ "$lu" = 1 ] || log "environnement du processus mesure NON RELU (pid='${mpid:--}')"
  extra "proof_env_proc_pid=${mpid:--}"
  extra "proof_env_proc_exe=$mexe"
  extra "proof_env_proc_read=$lu"
  extra "proof_env_proc_count=$nb"
  extra "proof_env_shell_count=$shellnb"
  # L'ECART EST LA GRANDEUR QUI COMPTE : ce que le shell porte moins ce que le processus mesure
  # porte vraiment. Un lanceur qui filtre se lit ICI, et nulle part ailleurs.
  if [ "$lu" = 1 ]; then extra "proof_env_proc_gap=$((shellnb - nb))"
  else extra "proof_env_proc_gap=-1"; fi
  extra "proof_env_proc_match=$match"
  extra "proof_env_proc_list=${liste:--}"
  # LA MEME LECTURE, DANS UN FICHIER NOMME PAR L'AUTORITE. `proof.txt` n'existe pas encore quand
  # le recensement de harnais tourne : sans ce fichier, un item de harnais ne pourrait juger la
  # relecture que sur du texte de script. Ecrit ici, il vient de LA course en cours.
  local nom; nom=$(python3 "$AP/lib/impossible.py" name env "$SUF" 2>/dev/null)
  [ -n "$nom" ] || return 0
  { echo "proof_env_proc_pid=${mpid:--}"
    echo "proof_env_proc_exe=$mexe"
    echo "proof_env_proc_read=$lu"
    echo "proof_env_proc_count=$nb"
    echo "proof_env_shell_count=$shellnb"
    echo "proof_env_proc_match=$match"
    echo "proof_env_proc_list=${liste:--}"
    echo "proof_env_binary=$binreal"
    echo "proof_env_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$D/$nom"
  log "environnement du processus mesure publie sous '$nom' (pid=${mpid:--} lues=$nb shell=$shellnb)"
}

# HDR x86 helpers: own only the exact child PID, including interruption cleanup.
hdr_x86_stop(){
  if [ -n "${HDR_XPID:-}" ] && kill -0 "$HDR_XPID" 2>/dev/null; then
    kill -TERM "$HDR_XPID" 2>/dev/null || true
    for ((stop_wait=0; stop_wait<5; stop_wait++)); do
      kill -0 "$HDR_XPID" 2>/dev/null || break
      sleep 1
    done
    kill -KILL "$HDR_XPID" 2>/dev/null || true
  fi
}
hdr_captures_complete(){
  local complete_captures temporal_samples published_captures published_steps published_temporal published_pairs
      complete_captures=$(sed -nE 's/.*REFSET done steps=([1-9][0-9]*) captured=\1 .*missing=0.*/\1/p' "$RAWLOG" | tail -1)
      temporal_samples=$(sed -nE 's/.*refset_temporal_samples=([1-9][0-9]*)$/\1/p' "$RAWLOG" | tail -1)
      temporal_samples=${temporal_samples:-1}
      # Pairing can be published before the final capture. Wait for the last
      # capture's counters too, before stopping their producer.
      published_captures=$(sed -nE 's/.*refset_captured=([0-9]+)$/\1/p' "$RAWLOG" | tail -1)
      published_steps=$(sed -nE 's/.*refset_steps=([0-9]+)$/\1/p' "$RAWLOG" | tail -1)
      published_temporal=$(sed -nE 's/.*refset_temporal_captured=([0-9]+)$/\1/p' "$RAWLOG" | tail -1)
      published_pairs=$(sed -nE 's/.*hdr_paired=([^[:space:]]*)$/\1/p' "$RAWLOG" | tail -1)
      if [ -n "$complete_captures" ] && [ "$temporal_samples" -le 16 ] && \
          [ "$published_captures" = "$complete_captures" ] && \
          [ "$published_steps" = "$complete_captures" ] && \
          { [ "$temporal_samples" -eq 1 ] || [ "$published_temporal" = "$complete_captures" ]; } && \
          [ "$((complete_captures % (2 * temporal_samples)))" -eq 0 ] && \
          [[ "$published_pairs" =~ ^(0|[1-9][0-9]*)$ ]] && \
          [ "${#published_pairs}" -le "${#complete_captures}" ] && \
          [ "$published_pairs" -le "$((complete_captures / (2 * temporal_samples)))" ]; then
        return 0
      fi
  return 1
}
hdr_x86_run(){
  local launch_time rc
  HDR_XPID=""; HDR_STOPPED=0
  trap 'hdr_x86_stop' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  stdbuf -oL -eL "$@" > "$RAWLOG" 2>&1 &
  HDR_XPID=$!
  lire_environ_mesure "$HDR_XPID"
  launch_time=$(date +%s)
  while kill -0 "$HDR_XPID" 2>/dev/null; do
    if hdr_captures_complete; then
      HDR_STOPPED=1; log "HDR x86 final captures and pairing counters published; stopping pid=$HDR_XPID"
      break
    fi
    if [ "$(( $(date +%s) - launch_time ))" -ge "$TIMEOUT" ]; then
      HDR_STOPPED=1; log "HDR x86 timeout; stopping pid=$HDR_XPID"
      break
    fi
    sleep 1
  done
  [ "$HDR_STOPPED" = 0 ] || hdr_x86_stop
  wait "$HDR_XPID"; rc=$?
  HDR_XPID=""
  trap - EXIT INT TERM
  if [ "$HDR_STOPPED" = 1 ] && { [ "$rc" = 143 ] || [ "$rc" = 137 ]; }; then return 0; fi
  return "$rc"
}
# End HDR x86 helpers.

# ============================================================================== x86 =========
if [ "$MODE" = x86 ]; then
  export DISPLAY="${DISPLAY:-:0}"
  if [ -z "${XAUTHORITY:-}" ]; then
    for x in /run/user/"$(id -u)"/.mutter-Xwaylandauth.*; do [ -e "$x" ] && export XAUTHORITY="$x"; done
  fi
  export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
  export OG_PACE_MEASURE=1                 # la seule ligne par image que le moteur sait deja
  export AUTOPORT_FEATURE="$ID"            # emettre. Sert a compter frames=, rien d'autre.
  export AUTOPORT_FEATURE_ARMED="$ARMED"
  # LA TRACE DE `proof_env`, symetrique de `proof_props` cote appareil. Rien ne l'efface ici (il
  # n'y a pas de teardown sur le bureau), mais un `export` refuse — nom invalide, ligne du
  # backlog sans `=` — laisserait la course sur le regime par DEFAUT sans un mot. On relit donc
  # l'environnement REELLEMENT pose, on ne se contente pas de redire ce qu'on voulait poser.
  ENV_EFFECTIVE=0; ENV_LIST=""; ENV_LOST_LIST=""
  for kvp in ${ENVS+"${ENVS[@]}"}; do
    export "${kvp}"
    ENV_LIST="${ENV_LIST:+$ENV_LIST,}${kvp%%=*}"
    if [ "$(printenv "${kvp%%=*}" 2>/dev/null)" = "${kvp#*=}" ]; then
      ENV_EFFECTIVE=$((ENV_EFFECTIVE+1))
      extra "proof_env_obs_$(prop_key "${kvp%%=*}")=${kvp#*=}"
    else
      ENV_LOST_LIST="${ENV_LOST_LIST:+$ENV_LOST_LIST,}${kvp%%=*}"
      log "EPINGLAGE PERDU : ${kvp%%=*} demande '${kvp#*=}', l'environnement rend '$(printenv "${kvp%%=*}" 2>/dev/null)'"
    fi
  done
  extra "proof_env_file=$ITEM_ENV_FILE"
  extra "proof_env_extracted=${#ENVS[@]}"
  extra "proof_env_effective=$ENV_EFFECTIVE"
  extra "proof_env_lost=$((ITEM_ENV_FILE - ENV_EFFECTIVE))"
  extra "proof_env_list=${ENV_LIST:--}"
  extra "proof_env_lost_list=${ENV_LOST_LIST:--}"
  if [ -n "$HDR_CAMPAIGN" ]; then
    HDR_BATCH="$D/batches/$HDR_CAMPAIGN/$(date -u +%Y%m%dT%H%M%S)-$$"
    HDR_REMOTE="$ROOT/$HDR_BATCH/local-captures"
    for kvp in "${HDR_ENVS[@]}"; do export "$kvp"; done
    unset OG_LIGHTING
    export OG_RT_LIGHT=1 OG_REFSET=capture OG_REFSET_DIR="$HDR_REMOTE"
    export OG_REFSET_PHASES=2,3 OG_REFSET_VANTAGES="$HDR_VANTAGES" OG_REFSET_HOURS="$HDR_HOURS"
    log "HDR x86 snapshot: binary, portable settings and rendering sources"
    python3 "$AP/lib/hdr_batches.py" prepare --source x86 --batch "$HDR_BATCH" \
      --binary "$BIN" --vantages "$HDR_VANTAGES" --hours "$HDR_HOURS" "${HDR_REPLACE[@]}" \
      || die3 hdr-prepare-x86 "hdr_batches.py prepare a echoue sur $HDR_BATCH"
  fi
  log "x86 : $BIN pendant ${TIMEOUT}s (armed=$ARMED)"
  # stdbuf : une sortie redirigee est bufferisee par BLOCS. 70 lignes produites, 0 comptees,
  # c'est arrive. -oL force la ligne a ligne AVANT qu'on en compte une seule.
  if [ -n "$HDR_BATCH" ]; then
    hdr_x86_run "$BIN" --game jak1 --portable -fakeiso --verbose --disable-ansi \
      -iso-data out/jak1/iso -- -boot -debug-mem
    rc=$?
    [ "$rc" = 0 ] || { CRASH=1; log "gk est sorti en $rc"; }
  else
    stdbuf -oL -eL timeout -k 5 "$TIMEOUT" "$BIN" \
        --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso \
        -- -boot -debug-mem > "$RAWLOG" 2>&1 &
    RUNPID=$!
    lire_environ_mesure "$RUNPID"
    wait "$RUNPID"
    rc=$?
    case "$rc" in
      0|124|137) CRASH=0 ;;   # 124/137 = arret demande par le producteur
      *) CRASH=1; log "gk est sorti en $rc" ;;
    esac
  fi
  grep -qaE 'SIGSEGV|SIGILL|SIGABRT|terminate called|Segmentation fault' "$RAWLOG" && CRASH=1
  if [ -n "$HDR_BATCH" ]; then
    cp "$RAWLOG" "$HDR_BATCH/engine.log" || die3 hdr-log-x86 "copie du journal vers $HDR_BATCH impossible"
    python3 "$AP/lib/hdr_batches.py" finish --source x86 --batch "$HDR_BATCH" \
      --binary "$BIN" --remote "$HDR_REMOTE" --crash "$CRASH" \
      --started-at "$STARTED" --duration-s "$(( $(date +%s) - T0 ))" \
      || die3 hdr-finish-x86 "hdr_batches.py finish a echoue sur $HDR_BATCH"
  fi

# =========================================================================== appareil =======
else
  # L'appareil est CHOISI a l'execution : n'importe lequel branche en USB fait l'affaire, et la
  # preuve dira lequel. Un numero de serie ecrit en dur a coute une nuit entiere le 2026-09-06,
  # quand le Honor de l'owner occupait le port USB a la place du Redmi.
  # L'epingle de l'ITEM (`device_serial`) est STRICTE : pas de repli sur un autre telephone.
  # Une epingle venue de l'environnement seul reste souple (voir lib/pick_device.sh).
  _pin_strict=""; [ -z "${ANDROID_SERIAL:-}" ] && [ -n "$ITEM_SERIAL" ] && _pin_strict=1
  SERIAL=$(ANDROID_SERIAL="${ANDROID_SERIAL:-$ITEM_SERIAL}" ANDROID_SERIAL_STRICT="$_pin_strict" \
           bash "$AP/lib/pick_device.sh") || die3 appareil-non-choisi "pick_device.sh n'a designe aucun appareil USB"
  case "$SERIAL" in
    *[0-9].[0-9]*.[0-9]*|*:*)
      die3 appareil-reseau "serial '$SERIAL' est une adresse reseau ; la SHIELD est INTERDITE" ;;
  esac
  ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"; [ -x "$ADB" ] || ADB=adb
  PKG="${AUTOPORT_PKG:-org.opengoal.gk.jak1}"
  PIDDIR="$AP/.logcat"; mkdir -p "$PIDDIR"
  export AUTOPORT_LOGCAT_PIDDIR="$PIDDIR"
  # LE TEARDOWN DE FIN DIT CE QU'IL EFFACE, COMME CELUI DU DEBUT (harness-verdict-integrity,
  # 2026-09-12). Il tourne QUOI QU'IL ARRIVE : c'est lui qui empeche une propriete oubliee de
  # tenir un bouton enfonce jusqu'a la semaine prochaine. Mais il ne recevait pas
  # `AUTOPORT_TEARDOWN_REPORT` : ce qu'il effacait APRES la course restait muet, et la course
  # suivante repartait d'un etat dont personne n'avait le releve. Il ecrit desormais son rapport
  # sous le nom que `lib/impossible.py` derive, et ses cles rejoignent `proof.txt` quand une
  # preuve a bien ete ecrite. Les cles sont TOUJOURS ecrites : un zero s'y lit « rien n'etait
  # pose », jamais « pas regarde ».
  TEARDOWN_FIN_FAIT=0
  teardown_fin(){
    [ "$TEARDOWN_FIN_FAIT" = 0 ] || return 0
    TEARDOWN_FIN_FAIT=1
    local rep nom
    rep="$D/.teardown-fin$SUF.$$.txt"; rm -f "$rep"
    AUTOPORT_TEARDOWN_REPORT="$rep" bash "$AP/lib/device_teardown.sh" "$SERIAL" >&2 || true
    nom=$(python3 "$AP/lib/impossible.py" name teardown "$SUF" 2>/dev/null)
    [ -n "$nom" ] || nom=".teardown-fin$SUF.txt"
    if [ -s "$rep" ]; then
      sed 's/^teardown_/teardown_fin_/' "$rep" > "$D/$nom"
    else
      { echo "teardown_fin_ran=0";           echo "teardown_fin_skip=rapport-absent"
        echo "teardown_fin_props_found=0";   echo "teardown_fin_props_list=-"
        echo "teardown_fin_props_cleared=0"; echo "teardown_fin_props_resisted=0"
        echo "teardown_fin_resisted_list=-"; echo "teardown_fin_getprop_ok=0"
        echo "teardown_fin_getprop_total=0"; echo "teardown_fin_props_source=aucun"
      } > "$D/$nom"
    fi
    rm -f "$rep"
    # LES CLES REJOIGNENT LA PREUVE QUAND IL Y EN A UNE. Une preuve impossible (`die3`) a efface
    # `proof.txt` : on n'en fabrique pas une en y ajoutant des lignes.
    [ -s "$OUTFILE" ] && cat "$D/$nom" >> "$OUTFILE"
    log "teardown de fin : $(sed -n 's/^teardown_fin_props_found=//p' "$D/$nom") propriete(s) trouvee(s) posee(s) [$(sed -n 's/^teardown_fin_props_list=//p' "$D/$nom")], publie sous '$nom'"
  }
  trap 'teardown_fin' EXIT

  if [ "$(timeout 15 "$ADB" -s "$SERIAL" get-state 2>/dev/null | tr -d '\r')" != device ]; then
    die3 appareil-absent "adb ne voit pas $SERIAL : aucune preuve APPAREIL possible"
  fi
  # md5 du .so REELLEMENT INSTALLE. Un commit qui ne touche que du C++ n'atteint pas toujours
  # le telephone (« deja a jour » avec le vieux libgk) : cette ligne rend l'ecart VISIBLE.
  # Quand le .so n'est pas extrait de l'APK on ecrit POURQUOI, jamais rien : une case vide se
  # lit « verifie » alors qu'elle veut dire « pas regarde ».
  LOCAL_MD5=$(md5sum "$BIN" | cut -d' ' -f1)
  APKPATH=$(timeout 20 "$ADB" -s "$SERIAL" shell pm path "$PKG" 2>/dev/null | sed 's/package://' | tr -d '\r' | head -1)
  DEV_MD5="absent-chemin-introuvable"
  if [ -n "$APKPATH" ]; then
    DEV_MD5=$(timeout 90 "$ADB" -s "$SERIAL" shell "md5sum $(dirname "$APKPATH")/lib/arm64/libgk.so 2>/dev/null" \
              | tr -d '\r' | awk '{print $1}' | head -1)
    [ -n "$DEV_MD5" ] || DEV_MD5="absent-so-non-extrait-de-l-apk"
  fi
  # SUR QUOI la preuve a tourne : deux appareils aux cadences tres differentes rendent des
  # chiffres incomparables, et rien ne le disait.
  DEV_MODEL=$(timeout 10 "$ADB" -s "$SERIAL" shell getprop ro.product.model 2>/dev/null | tr -d '\r' | tr ' ' '_')
  extra "local_lib_md5=$LOCAL_MD5"
  extra "device_lib_md5=$DEV_MD5"
  extra "device_serial=$SERIAL"
  extra "device_model=${DEV_MODEL:-inconnu}"

  # L'ECRAN DOIT ETRE ALLUME AVANT LE `am start`, SINON ON MESURE DU NOIR.
  # Mesure du 2026-09-03 02:16 : appareil `mWakefulness=Asleep`, l'activite est passee
  # onResume -> onPause -> onStop dans la meme seconde, `gk` n'a jamais demarre, et 480 s
  # d'observation ont rendu ZERO ligne — ce qui se lit exactement comme « aucun defaut ».
  # C'est un FAUX ROUGE d'instrument : le seul ajout ici est de rendre la course possible,
  # aucun champ de proof.txt n'en depend. On ne touche AUCUN reglage systeme durable
  # (`svc power stayon` n'est pas pose) : l'activite du jeu tient l'ecran elle-meme
  # (LoaderActivity.java:178, FLAG_KEEP_SCREEN_ON).
  timeout 15 "$ADB" -s "$SERIAL" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
  timeout 15 "$ADB" -s "$SERIAL" shell wm dismiss-keyguard >/dev/null 2>&1
  # ECRAN VERROUILLE : MIUI REFUSE la surface a NOTRE paquet, et ca se lit comme un moteur mort.
  # Mesure du 2026-09-11 (lighting-legacy-purge, essais 3 a 5 brules) : ecran ALLUME, activite
  # lancee, `surfaceCreated` puis `surfaceDestroyed` 117 ms plus tard, jamais recreee =>
  # `g_renderer_ready` jamais pose => fil GOAL bloque => `A37-HANG frame stuck at 1` =>
  # `frames=0`. La cause n'est ni le mode poche ni l'orientation : c'est l'app-op MIUI 10020
  # (« afficher sur l'ecran verrouille ») a `ignore` sur org.opengoal.gk.jak1, qui emet
  # `MIUILOG- Show when locked PermissionDenied pkg : org.opengoal.gk.jak1` (66 occurrences).
  # Passe a `allow` : 0 refus, 0 `surfaceDestroyed`, `A35-RENDER renderer ready`, 7080 images —
  # appareil toujours face contre table et verrouille. On ne touche que l'app-op de NOTRE paquet ;
  # aucun reglage systeme de l'owner. Un echec ici n'arrete rien : il se lit dans le journal.
  if OP_AVANT=$(timeout 15 "$ADB" -s "$SERIAL" shell appops get "$PKG" 2>/dev/null \
                | tr -d '\r' | sed -n 's/^MIUIOP(10020): \([a-z]*\).*/\1/p' | head -1) \
     && [ -n "$OP_AVANT" ] && [ "$OP_AVANT" != allow ]; then
    timeout 15 "$ADB" -s "$SERIAL" shell appops set "$PKG" 10020 allow >/dev/null 2>&1
    OP_APRES=$(timeout 15 "$ADB" -s "$SERIAL" shell appops get "$PKG" 2>/dev/null \
               | tr -d '\r' | sed -n 's/^MIUIOP(10020): \([a-z]*\).*/\1/p' | head -1)
    log "app-op MIUI 10020 (afficher sur ecran verrouille) : $OP_AVANT -> ${OP_APRES:-inconnu}"
  fi
  WAKE=$(timeout 15 "$ADB" -s "$SERIAL" shell dumpsys power 2>/dev/null \
         | grep -o 'mWakefulness=[A-Za-z]*' | head -1 | tr -d '\r')
  log "ecran : ${WAKE:-inconnu}"

  timeout 20 "$ADB" -s "$SERIAL" shell am force-stop "$PKG" >/dev/null 2>&1
  # LE TEARDOWN DIT CE QU'IL EFFACE. Il tourne AVANT qu'on pose quoi que ce soit et vide toutes
  # les `debug.opengoal.*` : ce qu'il trouve pose est, par construction, ce qu'un worker avait
  # pose depuis l'hote — et c'est precisement ce qui disparaissait sans un mot. Le rapport est
  # recopie tel quel dans proof.txt ; son absence se lit « le teardown n'a rien ecrit ».
  TDREPORT="$D/.teardown$SUF.$$.txt"; rm -f "$TDREPORT"
  AUTOPORT_TEARDOWN_REPORT="$TDREPORT" bash "$AP"/lib/device_teardown.sh "$SERIAL" >/dev/null 2>&1
  if [ -s "$TDREPORT" ]; then
    while IFS= read -r tdl; do [ -n "$tdl" ] && extra "$tdl"; done < "$TDREPORT"
    log "teardown : $(sed -n 's/^teardown_props_found=//p' "$TDREPORT") propriete(s) trouvee(s) posee(s) [$(sed -n 's/^teardown_props_list=//p' "$TDREPORT")]"
  else
    extra "teardown_ran=0"; extra "teardown_skip=rapport-absent"
    extra "teardown_props_found=0"; extra "teardown_props_list=-"
    extra "teardown_props_cleared=0"; extra "teardown_props_resisted=0"
    extra "teardown_resisted_list=-"
  fi
  rm -f "$TDREPORT"
  timeout 20 "$ADB" -s "$SERIAL" exec-out run-as "$PKG" sh -c "rm -f files/gk_crash.txt files/$ID.txt" >/dev/null 2>&1
  timeout 15 "$ADB" -s "$SERIAL" shell "setprop debug.opengoal.feature '$ID'" >/dev/null 2>&1
  timeout 15 "$ADB" -s "$SERIAL" shell "setprop debug.opengoal.feature.armed '$ARMED'" >/dev/null 2>&1
  # LES TROIS CHIFFRES DE LA TRACE. Ce que le fichier porte, ce qu'on en a extrait, ce que
  # L'APPAREIL rend une fois le teardown passe et les proprietes reposees. L'ecart entre le
  # premier et le troisieme est la grandeur qui compte : c'est la perte silencieuse d'hier.
  PROP_EFFECTIVE=0; PROP_LOST=0; PROP_LIST=""; PROP_LOST_LIST=""
  for kvp in ${PROPS+"${PROPS[@]}"}; do
    timeout 15 "$ADB" -s "$SERIAL" shell "setprop ${kvp%%=*} '${kvp#*=}'" >/dev/null 2>&1
    eff=$(timeout 15 "$ADB" -s "$SERIAL" shell "getprop ${kvp%%=*}" 2>/dev/null | tr -d '\r')
    PROP_LIST="${PROP_LIST:+$PROP_LIST,}${kvp%%=*}"
    if [ "$eff" = "${kvp#*=}" ]; then
      PROP_EFFECTIVE=$((PROP_EFFECTIVE+1))
    else
      PROP_LOST=$((PROP_LOST+1))
      PROP_LOST_LIST="${PROP_LOST_LIST:+$PROP_LOST_LIST,}${kvp%%=*}"
      log "EPINGLAGE PERDU : ${kvp%%=*} demande '${kvp#*=}', l'appareil rend '${eff:-vide}'"
    fi
  done
  extra "proof_props_file=$ITEM_PROP_FILE"
  extra "proof_props_extracted=${#PROPS[@]}"
  extra "proof_props_effective=$PROP_EFFECTIVE"
  extra "proof_props_lost=$((ITEM_PROP_FILE - PROP_EFFECTIVE))"
  extra "proof_props_rejected=$PROP_LOST"
  extra "proof_props_list=${PROP_LIST:--}"
  extra "proof_props_lost_list=${PROP_LOST_LIST:--}"

  if [ -n "$HDR_CAMPAIGN" ]; then
    HDR_BATCH="$D/batches/$HDR_CAMPAIGN/$(date -u +%Y%m%dT%H%M%S)-$$"
    HDR_REMOTE="/data/data/$PKG/files/hdr-$(date +%s)-$$"
    for kvp in "debug.opengoal.lighting=" "debug.opengoal.rt.light=1" "${HDR_PROPS[@]}" \
        "debug.opengoal.refset=capture" "debug.opengoal.refset.dir=$HDR_REMOTE" \
        "debug.opengoal.refset.phases=2,3" "debug.opengoal.refset.vantages=$HDR_VANTAGES" \
        "debug.opengoal.refset.hours=$HDR_HOURS"; do
      timeout 15 "$ADB" -s "$SERIAL" shell "setprop ${kvp%%=*} '${kvp#*=}'" \
        || die3 hdr-setprop "setprop ${kvp%%=*} a echoue sur $SERIAL"
      effective=$(timeout 15 "$ADB" -s "$SERIAL" shell getprop "${kvp%%=*}" | tr -d '\r')
      [ "$effective" = "${kvp#*=}" ] || die3 hdr-prop-non-appliquee "${kvp%%=*} relu a '$effective'"
    done
    python3 "$AP/lib/hdr_batches.py" prepare --batch "$HDR_BATCH" --adb "$ADB" \
      --serial "$SERIAL" --pkg "$PKG" --binary "$BIN" --vantages "$HDR_VANTAGES" \
      --hours "$HDR_HOURS" "${HDR_REPLACE[@]}" \
      || die3 hdr-prepare-appareil "hdr_batches.py prepare a echoue sur $HDR_BATCH"
    log "HDR batch: $HDR_BATCH ; refset=$HDR_REMOTE"
  fi

  timeout 15 "$ADB" -s "$SERIAL" logcat -c >/dev/null 2>&1
  stdbuf -oL "$ADB" -s "$SERIAL" logcat -v time > "$RAWLOG" 2>&1 &
  LPID=$!; echo "$LPID" > "$PIDDIR/$ID$SUF.pid"

  COMP=$(timeout 20 "$ADB" -s "$SERIAL" shell cmd package resolve-activity --brief "$PKG" 2>/dev/null \
         | tr -d '\r' | grep "^$PKG/" | head -1)
  [ -n "$COMP" ] || COMP="$PKG/org.opengoal.gk.LoaderActivity"
  log "appareil $SERIAL : $COMP pendant ${TIMEOUT}s (armed=$ARMED)"
  timeout 30 "$ADB" -s "$SERIAL" shell am start -n "$COMP" >/dev/null 2>&1
  sleep 8
  PID0=$(timeout 15 "$ADB" -s "$SERIAL" shell pidof "$PKG" 2>/dev/null | tr -d '\r' | awk '{print $1}')
  elapsed=8
  while [ "$elapsed" -lt "$TIMEOUT" ]; do
    sleep 5; elapsed=$((elapsed+5))
    if [ -n "$HDR_BATCH" ]; then
      if grep -qaF 'GK-DIAG A36-TREE at-crash frame=' "$RAWLOG"; then
        CRASH=1; log "HDR process emitted its crash trace; collecting the failed batch"; break
      fi
      # pidof exits 1 for an absent process; normalize only that remote status,
      # so an adb transport failure or timeout cannot declare a crash.
      if [ -n "$PID0" ] && PID_NOW=$(timeout 5 "$ADB" -s "$SERIAL" shell \
          "pidof '$PKG' || test \$? -eq 1" 2>/dev/null); then
        PID_NOW=$(printf '%s' "$PID_NOW" | tr -d '\r' | awk '{print $1}')
        if [ "$PID_NOW" != "$PID0" ]; then
          CRASH=1; log "HDR process changed or disappeared (before=$PID0 after=$PID_NOW); collecting the failed batch"; break
        fi
      fi
      complete_captures=$(sed -nE 's/.*REFSET done steps=([1-9][0-9]*) captured=\1 .*missing=0.*/\1/p' "$RAWLOG" | tail -1)
      temporal_samples=$(sed -nE 's/.*refset_temporal_samples=([1-9][0-9]*)$/\1/p' "$RAWLOG" | tail -1)
      temporal_samples=${temporal_samples:-1}
      # Pairing can be published before the final capture. Wait for the last
      # capture's counters too, before stopping their producer.
      published_captures=$(sed -nE 's/.*refset_captured=([0-9]+)$/\1/p' "$RAWLOG" | tail -1)
      published_steps=$(sed -nE 's/.*refset_steps=([0-9]+)$/\1/p' "$RAWLOG" | tail -1)
      published_temporal=$(sed -nE 's/.*refset_temporal_captured=([0-9]+)$/\1/p' "$RAWLOG" | tail -1)
      if [ -n "$complete_captures" ] && [ "$temporal_samples" -le 16 ] && \
          [ "$published_captures" = "$complete_captures" ] && \
          [ "$published_steps" = "$complete_captures" ] && \
          { [ "$temporal_samples" -eq 1 ] || [ "$published_temporal" = "$complete_captures" ]; } && \
          [ "$((complete_captures % (2 * temporal_samples)))" -eq 0 ] && \
          grep -qaE "hdr_paired=$((complete_captures / (2 * temporal_samples)))$" "$RAWLOG"; then
        log "HDR captures and paired measurements published after ${elapsed}s"; break
      fi
    fi
  done

  PID1=$(timeout 15 "$ADB" -s "$SERIAL" shell pidof "$PKG" 2>/dev/null | tr -d '\r' | awk '{print $1}')
  if [ -z "$PID1" ] || { [ -n "$PID0" ] && [ "$PID0" != "$PID1" ]; }; then
    CRASH=1; log "le processus a change ou disparu (avant=$PID0 apres=$PID1)"
  fi
  if timeout 20 "$ADB" -s "$SERIAL" exec-out run-as "$PKG" sh -c 'cat files/gk_crash.txt 2>/dev/null' \
     | tr -d '\r' | grep -qa .; then CRASH=1; log "files/gk_crash.txt present"; fi

  # LE REGIME OBSERVE, PAS LE REGIME DEMANDE. Relu sur l'appareil APRES l'amorcage : une cle par
  # propriete epinglee. C'est ce qui rend l'epinglage verifiable dans la preuve seule, sans
  # relire le backlog — et ce qui distingue « pose puis efface » de « pose et tenu ».
  PROP_OBS=0; PROP_OBS_MATCH=0
  for kvp in ${PROPS+"${PROPS[@]}"}; do
    obs=$(timeout 15 "$ADB" -s "$SERIAL" shell "getprop ${kvp%%=*}" 2>/dev/null | tr -d '\r')
    extra "proof_prop_obs_$(prop_key "${kvp%%=*}")=${obs:--}"
    PROP_OBS=$((PROP_OBS+1))
    [ "$obs" = "${kvp#*=}" ] && PROP_OBS_MATCH=$((PROP_OBS_MATCH+1))
  done
  extra "proof_props_observed=$PROP_OBS"
  extra "proof_props_observed_match=$PROP_OBS_MATCH"
  extra "proof_prop_obs_feature=$(timeout 15 "$ADB" -s "$SERIAL" shell 'getprop debug.opengoal.feature' 2>/dev/null | tr -d '\r' | sed 's/^$/-/')"


  if [ -n "$HDR_BATCH" ]; then
    # Stop the producer before closing its log: otherwise captures can land
    # after their effective-setting trace has already been disconnected.
    if ! timeout 20 "$ADB" -s "$SERIAL" shell am force-stop "$PKG" >/dev/null 2>&1; then
      die3 hdr-arret-producteur "am force-stop $PKG a echoue sur $SERIAL"
    fi
    sleep 1  # Let the live logcat reader drain the stopped process's tail.
  fi
  # Le moteur peut publier ses cle=valeur dans logcat ET dans files/<id>.txt : on lit les deux.
  timeout 30 "$ADB" -s "$SERIAL" exec-out run-as "$PKG" sh -c "cat files/$ID.txt 2>/dev/null" \
    >> "$RAWLOG" 2>/dev/null
  kill "$LPID" 2>/dev/null; wait "$LPID" 2>/dev/null; rm -f "$PIDDIR/$ID$SUF.pid"
  if [ -n "$HDR_BATCH" ]; then
    # The producer and its log reader are stopped; collect immutable sources.
    cp "$RAWLOG" "$HDR_BATCH/engine.log" || die3 hdr-log-appareil "copie du journal vers $HDR_BATCH impossible"
    python3 "$AP/lib/hdr_batches.py" finish --batch "$HDR_BATCH" --adb "$ADB" \
      --serial "$SERIAL" --pkg "$PKG" --binary "$BIN" --remote "$HDR_REMOTE" \
      --crash "$CRASH" --started-at "$STARTED" --duration-s "$(( $(date +%s) - T0 ))" \
      || die3 hdr-collecte "hdr_batches.py finish a echoue sur $HDR_BATCH"
  fi
fi

# ======================================== recensement de harnais (generique) ================
# Un item dont la grandeur ne vit PAS dans une image — le backlog, les scripts, l'historique —
# n'a aucun moyen de faire publier sa cle par le moteur. Le seul chemin honnete restait d'ajouter
# un module C++ a `game/` pour un verdict qui ne touche pas au jeu (builder-checkpoint-steals-work).
# Ce crochet le rend inutile : si `lib/census/<item-id>.sh` existe, il est LANCE ici, apres la
# course, et sa sortie `cle=valeur` rejoint celle du moteur dans le MEME journal, moissonnee par
# la MEME regle. Il n'ecrit rien dans proof.txt : ni les champs de la machine, ni sa propre ligne.
# POLARITE : un recensement qui echoue n'ecrit pas ses cles, donc le validateur est ROUGE. On ne
# fabrique jamais la cle manquante.
#
# LE RECENSEMENT EST LUI AUSSI UN TEMOIN (proof-feature-hits-is-vacuous, 2026-09-12). Un item de
# harnais n'a AUCUN site dans le moteur : son `proof_feature_own_hits` vaut zero, et c'est normal.
# La porte a donc besoin de savoir que SON instrument a tourne — sinon « aucun site moteur » et
# « instrument jamais lance » se lisent pareil. Ces trois cles sortent de la MACHINE :
#   proof_census_present  le crochet existe-t-il pour cet item
#   proof_census_rc       ce que le recensement a rendu (0 = abouti ; -1 = pas de crochet)
#   proof_census_keys     combien de `cle=valeur` il a produites
# ET ELLES NE SONT PAS FALSIFIABLES PAR LUI. Sa sortie passait jusqu'ici directement dans le
# journal du moteur, ou le moissonneur ne distingue pas les deux voix : un recensement pouvait
# donc ecrire son propre `proof_census_rc=0`, ou le `proof_feature_*` que le moteur seul doit
# produire, et juger sa propre course. On la filtre au POINT DE PRODUCTION, et on publie le
# nombre de lignes jetees.
CENSUS="$AP/lib/census/$ID.sh"
if [ -f "$CENSUS" ]; then
  CT0=$(date +%s)
  COUT="$D/.census$SUF.out.$$"
  log "recensement de harnais : $CENSUS (armed=$ARMED)"
  if AUTOPORT_CENSUS_ID="$ID" AUTOPORT_CENSUS_ARMED="$ARMED" AUTOPORT_CENSUS_DIR="$D" \
     timeout -k 15 "${AUTOPORT_CENSUS_TIMEOUT:-900}" bash "$CENSUS" \
     > "$COUT" 2>"$D/proof$SUF-census.log"; then
    CRC=0
    log "recensement fini en $(( $(date +%s) - CT0 ))s"
  else
    CRC=$?
    log "recensement SORTI EN ERREUR (code $CRC) apres $(( $(date +%s) - CT0 ))s : ses cles"
    log "manqueront a proof.txt et le validateur sera rouge. Journal : $D/proof$SUF-census.log"
  fi
  CKEYS=$(grep -cE '^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+$' "$COUT" 2>/dev/null || true)
  CDROP=$(grep -cE '^(proof_feature_|proof_census_)[A-Za-z0-9_]*=' "$COUT" 2>/dev/null || true)
  grep -vE '^(proof_feature_|proof_census_)[A-Za-z0-9_]*=' "$COUT" >> "$RAWLOG" 2>/dev/null
  [ "${CDROP:-0}" = 0 ] || log "$CDROP ligne(s) du recensement JETEE(S) : un recensement ne publie ni proof_feature_*, ni proof_census_*"
  rm -f "$COUT"
  extra "proof_census_present=1"
  extra "proof_census_rc=$CRC"
  extra "proof_census_keys=${CKEYS:-0}"
  extra "proof_census_dropped=${CDROP:-0}"
else
  extra "proof_census_present=0"
  extra "proof_census_rc=-1"
  extra "proof_census_keys=0"
  extra "proof_census_dropped=0"
fi

# ============================================== recopie de ce que le MOTEUR a dit ===========
T1=$(date +%s)
NORM="$D/.proof$SUF.norm.$$"
norm "$RAWLOG" > "$NORM" 2>/dev/null

if [ "$MODE" = x86 ]; then
  FRAMES=$(grep -aoE '^(PACE-SWAP-X86|AUTOPORT-FRAMES) n=[0-9]+' "$NORM" | grep -oE '[0-9]+$' | sort -n | tail -1)
  FRAMES=$(( ${FRAMES:-0} + 0 )); [ "$FRAMES" -gt 0 ] && FRAMES=$((FRAMES+1))
else
  FRAMES=$(grep -aoE '^(A35-RENDER frame|PACE-SWAP n|AUTOPORT-FRAMES n)=[0-9]+' "$NORM" | grep -oE '[0-9]+$' | sort -n | tail -1)
  FRAMES=$(( ${FRAMES:-0} + 0 ))
fi

FEATLINE=$(grep -aE "^FEATURE $ID armed=[01] hits=[0-9]+" "$NORM" | tail -1)
# Les `cle=valeur` SEULES SUR LEUR LIGNE, derniere valeur gagnante, les champs reserves du
# runner exclus : le moteur ne peut pas se faire passer pour la machine qui l'a lance.
# `next` DANS UN BLOC `END` EST UNE ERREUR FATALE POUR gawk (2026-09-03) :
#     awk: ligne de commande:5: error: « next » est utilise dans l'action END
# L'awk sortait donc en erreur A CHAQUE COURSE, `KVLINES` restait VIDE, et proof.txt ne portait
# JAMAIS la moindre ligne `cle=valeur`. Mesure : course appareil du 2026-09-03 15:20, le moteur
# publie `npc_culled_in_frustum=0` 240 fois dans son journal, proof.txt n'en porte aucune et le
# validateur rend « le proof ne porte pas 'npc_culled_in_frustum=' : le moteur doit emettre cette
# grandeur ». Le moteur l'emettait. AUCUN item du backlog, quel qu'il soit, ne pouvait passer sa
# porte tant que cette ligne etait la. Le filtre est simplement retourne en condition positive.
KVLINES=$(grep -aE '^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+$' "$NORM" \
  | awk -F= '{k=$1; sub(/^[^=]*=/,"",$0); v[k]=$0; if(!(k in seen)){seen[k]=1; ord[++n]=k}}
             END{for(i=1;i<=n;i++){k=ord[i];
                 if(k!="source" && k!="serial" && k!="binary" && k!="sha" && k!="started_at" &&
                    k!="duration_s" && k!="crash" && k!="frames" && k!="local_lib_md5" &&
                    k!="device_lib_md5" && k !~ /^proof_census_/) printf "%s=%s\n", k, v[k]}}')
rm -f "$NORM"

if [ -n "$HDR_BATCH" ]; then
  HDR_MEASURES=$(python3 "$AP/lib/hdr_batches.py" aggregate --batch "$HDR_BATCH") || {
    die3 hdr-agregation "hdr_batches.py aggregate a echoue sur $HDR_BATCH"; }
  # The aggregate owns these verdicts and every key it emits, including owner cases.
  KVLINES=$(awk -F= 'NR==FNR {replaced[$1]=1; next}
    !($1 in replaced) && $1 !~ /^(hdr_tonemap_defects|hdr_defect_1_saturation|hdr_defect_2_hl_contrast|hdr_defect_3_curve|hdr_defect_4_origine_lumiere_set|hdr_defect_5_sites_three_configs|hdr_defect_6_intermediate_narrowing)$/ {print}' \
    <(printf '%s\n' "$HDR_MEASURES") <(printf '%s\n' "$KVLINES"))
  KVLINES+=$'\n'"$HDR_MEASURES"
  EXTRA+=$'\n'"hdr_campaign=$HDR_CAMPAIGN"$'\n'"hdr_batch_manifest=$HDR_BATCH/manifest.json"
elif [ "$ID" = lighting-hdr ] && [ "$ARMED" = 1 ]; then
  KVLINES=$(python3 - "$AP/lib" "$D" "$KVLINES" <<'HDR_OWNER'
import re, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import hdr_batches as hdr
values = hdr.kv(sys.argv[3])
metrics, diagnostics = hdr.owner_regressions(hdr.contract(Path('.')))
total = values.pop('hdr_tonemap_defects', None)
if total is not None and re.fullmatch(r'[0-9]+', total):
    values['hdr_tonemap_defects'] = int(total) + metrics['hdr_defect_7_owner_regressions']
values.update(metrics)
hdr.dump(Path(sys.argv[2]) / 'measurements.json', {'owner_regressions': diagnostics})
for key, value in values.items():
    print(f'{key}={value}')
HDR_OWNER
  ) || die3 hdr-mesures-owner "hdr_batches.owner_regressions a echoue"
fi

TMP="$D/.proof$SUF.tmp.$$"
{
  echo "source=$MODE"
  [ -n "$SERIAL" ] && echo "serial=$SERIAL"
  echo "binary=$BIN"
  echo "sha=$SHA"
  echo "started_at=$STARTED"
  echo "duration_s=$((T1-T0))"
  echo "crash=$CRASH"
  echo "frames=$FRAMES"
  [ -n "$EXTRA" ] && printf '%s\n' "$EXTRA"
  if [ -n "$FEATLINE" ]; then printf '%s\n' "$FEATLINE"
  else echo "# FEATURE $ID absente de la sortie du moteur : le moteur n'emet pas encore cette ligne."; fi
  [ -n "$KVLINES" ] && printf '%s\n' "$KVLINES"
} > "$TMP"
# tmp + rename : un validateur ne doit JAMAIS lire un proof.txt a moitie ecrit.
mv -f "$TMP" "$OUTFILE"
log "ecrit $OUTFILE (frames=$FRAMES crash=$CRASH duree=$((T1-T0))s) ; sortie moteur : $RAWLOG"
exit 0
