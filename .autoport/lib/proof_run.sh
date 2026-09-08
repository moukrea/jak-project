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
# Usage : lib/proof_run.sh <item-id> <x86|device> [--timeout N] [--off]
#   HDR device: --hdr-campaign NOM --hdr-vantages vue[,vue] --hdr-hours 0,3,...
#   --hdr-prop debug.opengoal.KEY=VALUE (repeatable); --hdr-replace LOT:VUE:HEURE=VUE
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
HDR_AGGREGATE=""; HDR_PROPS=(); HDR_REPLACE=(); HDR_BATCH=""; HDR_REMOTE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --off)     OFF=1; shift ;;
    --hdr-campaign|--hdr-vantages|--hdr-hours|--hdr-prop|--hdr-replace|--hdr-aggregate-only)
      [ $# -ge 2 ] && [ -n "$2" ] || { echo "proof_run: $1 needs a value" >&2; exit 2; }
      case "$1" in
        --hdr-campaign) HDR_CAMPAIGN=$2 ;;
        --hdr-aggregate-only) HDR_AGGREGATE=$2 ;;
        --hdr-vantages) HDR_VANTAGES=$2 ;;
        --hdr-hours) HDR_HOURS=$2 ;;
        --hdr-prop) HDR_PROPS+=("$2") ;;
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
  [ "$ID" = lighting-hdr ] && [ "$MODE" = device ] && [ "$OFF" = 0 ] || {
    echo "proof_run: HDR batches require lighting-hdr device without --off" >&2; exit 2; }
  case "$HDR_CAMPAIGN" in *[!a-zA-Z0-9_-]*) echo "invalid HDR campaign name" >&2; exit 2 ;; esac
fi
if [ -n "$HDR_AGGREGATE" ]; then
  [ -n "$HDR_CAMPAIGN" ] || { echo "aggregate-only needs --hdr-campaign" >&2; exit 2; }
  case "$HDR_AGGREGATE" in *[!a-zA-Z0-9_-]*) echo "invalid HDR batch name" >&2; exit 2 ;; esac
fi
for kvp in "${HDR_PROPS[@]}"; do
  [[ "$kvp" =~ ^debug\.opengoal\.[a-zA-Z0-9_.]+=[a-zA-Z0-9_.,:/+\ -]*$ ]] || {
    echo "proof_run: invalid HDR property" >&2; exit 2; }
  case "${kvp%%=*}" in debug.opengoal.feature*|debug.opengoal.refset|debug.opengoal.refset.dir|debug.opengoal.refset.phases|debug.opengoal.refset.vantages|debug.opengoal.refset.hours|debug.opengoal.lighting|debug.opengoal.rt.light)
    echo "proof_run: property reserved by HDR campaign" >&2; exit 2 ;; esac
done

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
while IFS= read -r line; do
  case "$line" in
    ITEM_SERIAL=*)  ITEM_SERIAL=${line#ITEM_SERIAL=} ;;
    ITEM_TIMEOUT=*) ITEM_TIMEOUT=${line#ITEM_TIMEOUT=} ;;
    ITEM_ENV=*)     ENVS+=("${line#ITEM_ENV=}") ;;
    ITEM_PROP=*)    PROPS+=("${line#ITEM_PROP=}") ;;
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
  log "binaire absent : $BIN — rien a juger, aucune preuve ecrite."
  rm -f "$OUTFILE"; exit 3
fi
# Recompute from an immutable existing run, preserving its original execution
# timestamp and counters. This path performs no device action and never freshens a run.
if [ -n "$HDR_AGGREGATE" ]; then
  rm -f "$OUTFILE"
  HDR_BATCH="$D/batches/$HDR_CAMPAIGN/$HDR_AGGREGATE"
  TMP="$D/.proof$SUF.tmp.$$"
  if ! python3 - "$HDR_BATCH" "$BIN" > "$TMP" <<'HDR_REPLAY'
import datetime, hashlib, json, os, re, sys
from pathlib import Path
sys.path.insert(0, '.autoport/lib')
import hdr_batches as hdr
batch, binary = Path(sys.argv[1]), Path(sys.argv[2])
m = json.loads((batch / 'manifest.json').read_text())
if hdr.sha(binary) != m['provenance']['binary_sha256']:
    raise SystemExit('HDR aggregate: current binary differs from original run')
run = m['run']
if not re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ', run['started_at'] or ''):
    raise SystemExit('HDR aggregate: original timestamp unavailable')
raw = hdr.normalized((batch / 'engine.log').read_text(errors='replace'))
values = hdr.kv(raw)
measures = hdr.aggregate(batch.parent, batch.name, hdr.contract(Path('.')))
print('source=device')
print('serial=' + m['provenance']['serial'])
print('binary=' + str(binary))
print('sha=' + hdr.sha(binary)[:16])
print('started_at=' + run['started_at'])
print('duration_s=' + str(run['duration_s']))
print('crash=' + str(m['crash']))
frames = re.findall(r'^(?:A35-RENDER frame|PACE-SWAP n|AUTOPORT-FRAMES n)=(\d+)', raw, re.M)
print('frames=' + str(max(map(int, frames), default=0)))
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
    rm -f "$TMP"; log "HDR aggregate failed; no proof emitted"; exit 3
  fi
  mv -f "$TMP" "$OUTFILE"
  log "recomputed $OUTFILE from $HDR_BATCH with original timestamp"
  exit 0
fi

[ -n "$TIMEOUT" ] || TIMEOUT="$ITEM_TIMEOUT"
if [ -z "$TIMEOUT" ]; then if [ "$MODE" = x86 ]; then TIMEOUT=120; else TIMEOUT=180; fi; fi
case "$TIMEOUT" in *[!0-9]*|"") echo "proof_run: --timeout '$TIMEOUT' n'est pas un entier" >&2; exit 2 ;; esac

# ------------------------------------------------------- attendre qu'aucun build n'ecrive ----
# Un gk lance pendant que auto_build_apk.sh reecrit out/jak1/iso/ meurt en SIGILL sur un
# KERNEL.CGO a moitie ecrit, et un `--target gk` partiel casse l'ABI de goalc. Ces deux
# accidents ont ete lus comme des defauts du jeu. Ici on ATTEND : on ne rend jamais un faux
# rouge parce qu'un builder tournait.
WAITMAX="${AUTOPORT_PROOF_WAIT_MAX:-1800}"
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
    if pgrep -x "$pat" >/dev/null 2>&1; then echo "processus $pat en cours"; return 0; fi
  done
  # Le lanceur Java porte le nom de l'outil dans ses arguments.
  if pgrep -f '[g]radle' >/dev/null 2>&1; then echo "processus [g]radle en cours"; return 0; fi
  cgo=out/jak1/iso/GAME.CGO
  if [ -f "$cgo" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$cgo" 2>/dev/null || echo 0) ))
    if [ "$age" -lt 60 ]; then echo "GAME.CGO reecrit il y a ${age}s"; return 0; fi
  fi
  echo ""; return 0
}
waited=0
while :; do
  why=$(busy_reason)
  [ -z "$why" ] && break
  if [ "$waited" -ge "$WAITMAX" ]; then
    log "un build ecrit encore apres ${waited}s ($why) : ON N'A PAS MESURE. Relance quand il a fini."
    rm -f "$OUTFILE"; exit 3
  fi
  [ "$waited" = 0 ] && log "attente : $why"
  sleep 15; waited=$((waited+15))
done
[ "$waited" -gt 0 ] && log "build fini apres ${waited}s d'attente, on mesure."

# La preuve doit venir de la course qu'on lance MAINTENANT. On retire l'ancienne d'abord :
# si la course echoue, il ne reste rien qui puisse passer une porte.
rm -f "$OUTFILE"

SHA=$(sha256sum "$BIN" | cut -c1-16)
STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
T0=$(date +%s)
CRASH=0; FRAMES=0; SERIAL=""; EXTRA=""

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
  for kvp in ${ENVS+"${ENVS[@]}"}; do export "${kvp}"; done
  log "x86 : $BIN pendant ${TIMEOUT}s (armed=$ARMED)"
  # stdbuf : une sortie redirigee est bufferisee par BLOCS. 70 lignes produites, 0 comptees,
  # c'est arrive. -oL force la ligne a ligne AVANT qu'on en compte une seule.
  stdbuf -oL -eL timeout -k 5 "$TIMEOUT" "$BIN" \
      --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data out/jak1/iso \
      -- -boot -debug-mem > "$RAWLOG" 2>&1
  rc=$?
  case "$rc" in
    0|124|137) CRASH=0 ;;   # 124/137 = c'est NOUS qui l'avons arrete au bout du temps demande
    *)         CRASH=1; log "gk est sorti en $rc" ;;
  esac
  grep -qaE 'SIGSEGV|SIGILL|SIGABRT|terminate called|Segmentation fault' "$RAWLOG" && CRASH=1

# =========================================================================== appareil =======
else
  # L'appareil est CHOISI a l'execution : n'importe lequel branche en USB fait l'affaire, et la
  # preuve dira lequel. Un numero de serie ecrit en dur a coute une nuit entiere le 2026-09-06,
  # quand le Honor de l'owner occupait le port USB a la place du Redmi.
  SERIAL="${ANDROID_SERIAL:-}"; [ -n "$SERIAL" ] || SERIAL="$ITEM_SERIAL"
  [ -n "$SERIAL" ] || SERIAL=$(bash "$AP/lib/pick_device.sh") || { rm -f "$OUTFILE"; exit 3; }
  case "$SERIAL" in
    *[0-9].[0-9]*.[0-9]*|*:*)
      log "serial '$SERIAL' est une adresse reseau. La SHIELD (192.168.1.32) est INTERDITE."
      rm -f "$OUTFILE"; exit 3 ;;
  esac
  if [ -n "$HDR_CAMPAIGN" ] && [ "$SERIAL" != eae4df44 ]; then
    log "HDR campaign restricted to authorized Redmi eae4df44"; exit 3
  fi
  ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"; [ -x "$ADB" ] || ADB=adb
  PKG="${AUTOPORT_PKG:-org.opengoal.gk.jak1}"
  PIDDIR="$AP/.logcat"; mkdir -p "$PIDDIR"
  export AUTOPORT_LOGCAT_PIDDIR="$PIDDIR"
  # Le teardown tourne QUOI QU'IL ARRIVE : c'est lui qui empeche une propriete oubliee de
  # tenir un bouton enfonce jusqu'a la semaine prochaine.
  trap 'bash '"$AP"'/lib/device_teardown.sh "'"$SERIAL"'" >&2 || true' EXIT

  if [ "$(timeout 15 "$ADB" -s "$SERIAL" get-state 2>/dev/null | tr -d '\r')" != device ]; then
    log "appareil $SERIAL absent : aucune preuve APPAREIL possible."
    rm -f "$OUTFILE"; exit 3
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
  EXTRA="local_lib_md5=$LOCAL_MD5"$'\n'"device_lib_md5=$DEV_MD5"$'\n'"device_serial=$SERIAL"$'\n'"device_model=${DEV_MODEL:-inconnu}"

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
  WAKE=$(timeout 15 "$ADB" -s "$SERIAL" shell dumpsys power 2>/dev/null \
         | grep -o 'mWakefulness=[A-Za-z]*' | head -1 | tr -d '\r')
  log "ecran : ${WAKE:-inconnu}"

  timeout 20 "$ADB" -s "$SERIAL" shell am force-stop "$PKG" >/dev/null 2>&1
  bash "$AP"/lib/device_teardown.sh "$SERIAL" >/dev/null 2>&1
  timeout 20 "$ADB" -s "$SERIAL" exec-out run-as "$PKG" sh -c "rm -f files/gk_crash.txt files/$ID.txt" >/dev/null 2>&1
  timeout 15 "$ADB" -s "$SERIAL" shell "setprop debug.opengoal.feature '$ID'" >/dev/null 2>&1
  timeout 15 "$ADB" -s "$SERIAL" shell "setprop debug.opengoal.feature.armed '$ARMED'" >/dev/null 2>&1
  for kvp in ${PROPS+"${PROPS[@]}"}; do
    timeout 15 "$ADB" -s "$SERIAL" shell "setprop ${kvp%%=*} '${kvp#*=}'" >/dev/null 2>&1
  done

  if [ -n "$HDR_CAMPAIGN" ]; then
    HDR_BATCH="$D/batches/$HDR_CAMPAIGN/$(date -u +%Y%m%dT%H%M%S)-$$"
    HDR_REMOTE="/data/data/$PKG/files/hdr-$(date +%s)-$$"
    for kvp in "debug.opengoal.lighting=" "debug.opengoal.rt.light=1" "${HDR_PROPS[@]}" \
        "debug.opengoal.refset=capture" "debug.opengoal.refset.dir=$HDR_REMOTE" \
        "debug.opengoal.refset.phases=2,3" "debug.opengoal.refset.vantages=$HDR_VANTAGES" \
        "debug.opengoal.refset.hours=$HDR_HOURS"; do
      timeout 15 "$ADB" -s "$SERIAL" shell "setprop ${kvp%%=*} '${kvp#*=}'" || exit 3
      effective=$(timeout 15 "$ADB" -s "$SERIAL" shell getprop "${kvp%%=*}" | tr -d '\r')
      [ "$effective" = "${kvp#*=}" ] || { log "HDR property did not apply: ${kvp%%=*}"; exit 3; }
    done
    python3 "$AP/lib/hdr_batches.py" prepare --batch "$HDR_BATCH" --adb "$ADB" \
      --serial "$SERIAL" --pkg "$PKG" --binary "$BIN" --vantages "$HDR_VANTAGES" \
      --hours "$HDR_HOURS" "${HDR_REPLACE[@]}" || exit 3
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
      if [ -n "$complete_captures" ] && grep -qaE "hdr_paired=$((complete_captures / 2))$" "$RAWLOG"; then
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

  if [ -n "$HDR_BATCH" ]; then
    # Stop the producer before closing its log: otherwise captures can land
    # after their effective-setting trace has already been disconnected.
    if ! timeout 20 "$ADB" -s "$SERIAL" shell am force-stop "$PKG" >/dev/null 2>&1; then
      log "HDR producer stop failed: no batch or proof emitted"; exit 3
    fi
    sleep 1  # Let the live logcat reader drain the stopped process's tail.
  fi
  # Le moteur peut publier ses cle=valeur dans logcat ET dans files/<id>.txt : on lit les deux.
  timeout 30 "$ADB" -s "$SERIAL" exec-out run-as "$PKG" sh -c "cat files/$ID.txt 2>/dev/null" \
    >> "$RAWLOG" 2>/dev/null
  kill "$LPID" 2>/dev/null; wait "$LPID" 2>/dev/null; rm -f "$PIDDIR/$ID$SUF.pid"
  if [ -n "$HDR_BATCH" ]; then
    # The producer and its log reader are stopped; collect immutable sources.
    cp "$RAWLOG" "$HDR_BATCH/engine.log" || exit 3
    python3 "$AP/lib/hdr_batches.py" finish --batch "$HDR_BATCH" --adb "$ADB" \
      --serial "$SERIAL" --pkg "$PKG" --binary "$BIN" --remote "$HDR_REMOTE" \
      --crash "$CRASH" --started-at "$STARTED" --duration-s "$(( $(date +%s) - T0 ))" || { log "HDR batch collection failed"; exit 3; }
  fi
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
                    k!="device_lib_md5") printf "%s=%s\n", k, v[k]}}')
rm -f "$NORM"

if [ -n "$HDR_BATCH" ]; then
  HDR_MEASURES=$(python3 "$AP/lib/hdr_batches.py" aggregate --batch "$HDR_BATCH") || {
    log "HDR aggregate failed: no proof emitted"; exit 3; }
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
  ) || { log "HDR owner measurements failed: no proof emitted"; exit 3; }
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
