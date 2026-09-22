#!/usr/bin/env bash
# asset_pack_selftest.sh — LE BAC A SABLE DE LA GARDE PACK
# (harness-device-deploy-gate-must-compare-the-asset-pack, 22/09).
#
# LA CONDITION EST FABRIQUEE, PAS ATTENDUE. Le defaut ne se voit que sur un essai 100 % GOAL :
# le telephone porte deja le libgk.so local, mais le pack de code (`assets/bundle/jak1_cgo.zip`)
# de l'essai PRECEDENT. Ce banc fabrique exactement cet etat dans un depot jetable, avec un FAUX
# `adb` dont on choisit ce que le telephone porte, et lance le VRAI `lib/proof_run.sh` en mode
# appareil contre lui. Le pack local ne differe du pack de l'appareil que d'UN SEUL octet de
# GAME.CGO ; libgk.so n'est pas touche (md5 identiques dans TOUS les bras).
#
# LES CINQ BRAS :
#   egaux     pack identique, APK conforme dispo  -> AUCUNE installation, la course mesure
#                                                    (controle negatif : on ne repousse pas le pack)
#   goal      pack N-1 sur l'appareil, APK conforme -> la garde LIVRE, puis la course mesure le pack
#                                                    local (controle positif, porte d'APRES)
#   vieux     comme `goal`, GARDE-PACK RETIREE     -> la porte d'AVANT : `identique`,
#                                                    deploy_attempted=0, mesure sur le pack N-1
#   sansapk   pack N-1, aucun APK ne porte le local -> REFUS avant l'amorcage, preuve d'hier intacte
#   installko pack N-1, APK conforme, install KO    -> REFUS : un deploiement qui echoue est ROUGE
#
# LE BRAS D'ABSENCE EST FABRIQUE PAR RETRAIT DE BLOC (`GARDE-PACK/debut..fin`), pas par un
# commit : OFF doit egaler l'ABSENCE, et un ancrage `HEAD:` s'accuserait lui-meme des le commit.
#
# Sortie : des `cle=valeur` sur stdout. Il ne JUGE rien : la somme est dans lib/census/<item>.sh.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "selftest_ran=0"; exit 1; }
AP="$ROOT/.autoport"
SERIAL_FAKE="SANDBOXPACK1"
PKG="org.opengoal.gk.jak1"
ITEM="sandbox-pack"
BUNDLE_REL="android/app/src/jak1/assets-slim/bundle"

eval "$(python3 "$AP/lib/impossible.py" names "")"

SB=$(mktemp -d -t assetpack.XXXXXX) || { echo "selftest_ran=0"; exit 1; }
trap 'rm -rf "$SB"' EXIT
note(){ printf '[banc-pack] %s\n' "$*" >&2; }
kv(){ printf '%s=%s\n' "$1" "${2:--}"; }

# ================================================================= fabrication d'un bras =====
# $1 nom ; $2 dossier ; $3 pack de l'appareil (local|ancien) ; $4 APK (conforme|aucun)
# $5 1 = GARDE-PACK retiree ; $6 1 = l'installation echoue
monte_bras() {
  local nom=$1 dir=$2 packdev=$3 apk=$4 sans_garde=$5 install_ko=$6
  mkdir -p "$dir/.autoport/lib" "$dir/build-android/lib/arm64-v8a" "$dir/$BUNDLE_REL" || return 1
  printf 'faux libgk du banc pack, bras %s, %s\n' "$nom" "$RANDOM$RANDOM" \
    > "$dir/build-android/lib/arm64-v8a/libgk.so"
  local so_md5
  so_md5=$(md5sum "$dir/build-android/lib/arm64-v8a/libgk.so" | awk '{print $1}')

  git -C "$dir" init -q >/dev/null 2>&1 || return 1              # git-sandbox-ok
  git -C "$dir" config user.email pack@sandbox >/dev/null 2>&1   # git-sandbox-ok
  git -C "$dir" config user.name pack >/dev/null 2>&1            # git-sandbox-ok

  local rel
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    mkdir -p "$dir/$(dirname "$rel")" || return 1
    cp "$ROOT/$rel" "$dir/$rel" || return 1
  done < <(bash "$AP/lib/verdict_sources.sh" "$ITEM" list)
  chmod +x "$dir/.autoport/lib/"*.sh 2>/dev/null
  chmod +x "$dir/.autoport/acquis/"*.sh "$dir/.autoport/validators/"*.sh 2>/dev/null
  # La garde n'arrive dans le bac que par la CITATION que `proof_run.sh` en fait. Absente, le
  # bras n'a rien a mesurer : on le dit, on ne le devine pas.
  if [ ! -s "$dir/.autoport/lib/deploy_verify_assets.sh" ]; then
    note "bras $nom : lib/deploy_verify_assets.sh n'est pas dans les sources du verdict"
    return 1
  fi

  if [ "$sans_garde" = 1 ]; then
    awk 'index($0,"GARDE-PACK/debut"){f=1} !f{print} index($0,"GARDE-PACK/fin"){f=0}' \
      "$dir/.autoport/lib/proof_run.sh" > "$dir/pr.tmp" || return 1
    local avant apres
    avant=$(wc -l < "$dir/.autoport/lib/proof_run.sh"); apres=$(wc -l < "$dir/pr.tmp")
    kv "arm_${nom}_bloc_retire_lignes" "$((avant - apres))"
    mv -f "$dir/pr.tmp" "$dir/.autoport/lib/proof_run.sh" || return 1
  fi

  cat > "$dir/.autoport/backlog.yaml" <<YAML
version: 1
items:
  - id: $ITEM
    status: in-progress
    device: true
    owner_test: false
    feature: bac a sable de la garde pack
    proof_timeout: 8
YAML

  # LES DEUX PACKS : N-1 (sur l'appareil) et N (local), qui ne different que d'UN octet de
  # GAME.CGO. Memes dates de membre : la seule difference du zip est celle de cet octet (et le
  # CRC qui la suit).
  python3 - "$dir/pack-ancien.zip" "$dir/$BUNDLE_REL/jak1_cgo.zip" "$nom" <<'PY' || return 1
import sys, zipfile
ancien, nouveau, nom = sys.argv[1], sys.argv[2], sys.argv[3]
cgo = bytearray(b'GOAL essai N-1 du banc pack, bras %s ' % nom.encode() + bytes(range(256)) * 8)
eng = b'ENGINE.CGO inchange ' * 64
def ecrit(chemin, game):
    with zipfile.ZipFile(chemin, 'w', zipfile.ZIP_DEFLATED) as z:
        for n, data in (('GAME.CGO', game), ('ENGINE.CGO', eng)):
            zi = zipfile.ZipInfo(n, date_time=(2026, 9, 22, 12, 0, 0))
            zi.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(zi, bytes(data))
ecrit(ancien, cgo)
cgo2 = bytearray(cgo); cgo2[40] ^= 0x01          # UN SEUL octet observable
ecrit(nouveau, cgo2)
print(sum(1 for a, b in zip(cgo, cgo2) if a != b), file=open(ancien + '.octets', 'w'))
PY
  kv "arm_${nom}_octets_modifies_game_cgo" "$(cat "$dir/pack-ancien.zip.octets")"
  printf 'version=v-nouveau\nfile_count=2\n' > "$dir/$BUNDLE_REL/jak1_cgo.manifest.properties"
  local md5_local md5_ancien
  md5_local=$(md5sum "$dir/$BUNDLE_REL/jak1_cgo.zip" | awk '{print $1}')
  md5_ancien=$(md5sum "$dir/pack-ancien.zip" | awk '{print $1}')
  printf '%s\n' "$md5_local" > "$dir/packlocal"
  printf '%s\n' "$md5_ancien" > "$dir/packancien"
  if [ "$packdev" = local ]; then printf '%s\n' "$md5_local" > "$dir/packdev"
  else printf '%s\n' "$md5_ancien" > "$dir/packdev"; fi
  # Le binaire est IDENTIQUE dans tous les bras : c'est l'essai 100 % GOAL.
  printf '%s\n' "$so_md5" > "$dir/md5dev"
  printf '%s\n' "$so_md5" > "$dir/md5local"
  printf 'debug.opengoal.placeholder=0\n' > "$dir/props"
  : > "$dir/logcat"
  [ "$install_ko" = 1 ] && : > "$dir/install_ko"

  # L'APK DU CONSTRUCTEUR : un vrai zip qui porte le libgk local ET le pack local.
  mkdir -p "$dir/apks"
  if [ "$apk" = conforme ]; then
    python3 - "$dir/apks/app-jak1-debug.apk" "$dir/build-android/lib/arm64-v8a/libgk.so" \
              "$dir/$BUNDLE_REL/jak1_cgo.zip" <<'PY' || return 1
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as z:
    z.write(sys.argv[2], 'lib/arm64-v8a/libgk.so')
    z.write(sys.argv[3], 'assets/bundle/jak1_cgo.zip')
PY
    printf '%s\n' "$so_md5" > "$dir/apkmd5"
    printf '%s\n' "$md5_local" > "$dir/apkpackmd5"
  fi

  # ------------------------------------------------------------------------- le faux adb -----
  # Il imite EXACTEMENT ce que proof_run.sh, device_teardown.sh, pick_device.sh,
  # device_binary_gate.sh et deploy_verify_assets.sh envoient. `unzip -p ... | md5sum` rend le
  # pack que porte le faux telephone ; `install` y fait atterrir le libgk ET le pack de l'APK ;
  # `am start` fait ecrire au faux moteur le pack qu'il a CHARGE.
  cat > "$dir/adb" <<'ADB_EOF'
#!/usr/bin/env bash
D=$(cd "$(dirname "$0")" && pwd)
P="$D/props"; L="$D/logcat"
get(){ sed -n "s/^$(printf '%s' "$1" | sed 's/[.[\*^$]/\\&/g')=//p" "$P" | tail -1; }
set_(){ local k=$1 v=$2 t; t=$(mktemp); grep -v "^$(printf '%s' "$k" | sed 's/[.[\*^$]/\\&/g')=" "$P" > "$t" 2>/dev/null
        [ -n "$v" ] && printf '%s=%s\n' "$k" "$v" >> "$t"; mv -f "$t" "$P"; }
[ "${1:-}" = devices ] && { printf 'List of devices attached\nSANDBOXPACK1\tdevice\n'; exit 0; }
[ "${1:-}" = -s ] || exit 1
shift 2
case "${1:-}" in
  get-state) echo device ;;
  install)
    echo "install" >> "$D/installs"
    if [ -f "$D/install_ko" ]; then echo "Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]"; exit 1; fi
    [ -s "$D/apkmd5" ] && cp -f "$D/apkmd5" "$D/md5dev"
    [ -s "$D/apkpackmd5" ] && cp -f "$D/apkpackmd5" "$D/packdev"
    echo Success ;;
  logcat)
    [ "${2:-}" = -c ] && { : > "$L"; exit 0; }
    exec tail -n +1 -f "$L" ;;
  shell|exec-out)
    shift
    [ "${1:-}" = run-as ] && shift 2
    [ "${1:-}" = sh ] && shift 2
    # shellcheck disable=SC2046
    set -- $(printf '%s ' "$@" | sed "s/''/ /g; s/'//g")
    case "${1:-}" in
      getprop)
        if [ -z "${2:-}" ]; then
          while IFS= read -r l; do [ -n "$l" ] && printf '[%s]: [%s]\n' "${l%%=*}" "${l#*=}"; done < "$P"
        elif [ "$2" = ro.product.model ]; then echo SANDBOX_Fake
        else get "$2"; fi ;;
      setprop) set_ "$2" "${3:-}" ;;
      pm) echo "package:/data/app/sandbox/base.apk" ;;
      unzip) printf '%s  -\n' "$(cat "$D/packdev")" ;;
      md5sum) printf '%s  %s\n' "$(cat "$D/md5dev")" "${2:-}" ;;
      pidof) [ -f "$D/started" ] && echo 4242 ;;
      cmd) echo "org.opengoal.gk.jak1/org.opengoal.gk.LoaderActivity" ;;
      dumpsys) echo "mWakefulness=Awake" ;;
      am)
        case "${2:-}" in
          start)
            : > "$D/started"
            { for n in 60 120 180 240 300 360 420 480 540 600; do
                printf '09-22 10:00:00.000 I/GK_STDOUT( 4242): AUTOPORT-FRAMES n=%s\n' "$n"
                printf '09-22 10:00:00.000 I/GK_STDOUT( 4242): FEATURE %s armed=1 hits=%s\n' \
                       "$(get debug.opengoal.feature)" "$n"
              done
              printf '09-22 10:00:00.000 I/GK_STDOUT( 4242): sandbox_engine_pack_md5_vu=%s\n' "$(cat "$D/packdev")"
              printf '09-22 10:00:00.000 I/GK_STDOUT( 4242): sandbox_engine_md5_vu=%s\n' "$(cat "$D/md5dev")"
            } >> "$L" ;;
          force-stop) rm -f "$D/started" ;;
        esac ;;
      *) : ;;
    esac ;;
  *) : ;;
esac
exit 0
ADB_EOF
  chmod +x "$dir/adb"

  mkdir -p "$dir/.autoport/reports/$ITEM"
  printf 'source=device\nframes=4242\ncrash=0\nmarqueur=preuve-de-la-course-precedente\n' \
    > "$dir/.autoport/reports/$ITEM/$AP_NAME_proof"
  printf 'seal_sha=abc\nexit_sha=abc\n' > "$dir/.autoport/reports/$ITEM/$AP_NAME_seal"
  sha256sum "$dir/.autoport/reports/$ITEM/$AP_NAME_proof" | cut -c1-64 > "$dir/proof-avant.sha"
  return 0
}

# ============================================================== la course d'un bras ===========
court_bras() {
  local nom=$1 dir=$2
  local pf="$dir/.autoport/reports/$ITEM/$AP_NAME_proof"
  local prev="$dir/.autoport/reports/$ITEM/$AP_NAME_prev_proof"
  ( cd "$dir" && ANDROID_SERIAL="$SERIAL_FAKE" ADB="$dir/adb" AUTOPORT_PKG="$PKG" \
      AUTOPORT_APK_GLOB="$dir/apks/*.apk" \
      AUTOPORT_PROOF_WAIT_MAX=60 AUTOPORT_LOGCAT_PIDDIR="$dir/.logcat" \
      timeout -k 10 240 bash .autoport/lib/proof_run.sh "$ITEM" device --timeout 8 \
  ) >"$dir/run.log" 2>&1
  local rc=$?
  note "bras $nom : proof_run sorti en $rc"
  kv "arm_${nom}_rc" "$rc"
  kv "arm_${nom}_started" "$([ -f "$dir/started" ] && echo 1 || echo 0)"
  kv "arm_${nom}_installs" "$(grep -c . "$dir/installs" 2>/dev/null || echo 0)"
  kv "arm_${nom}_pack_local" "$(cat "$dir/packlocal")"
  kv "arm_${nom}_pack_ancien" "$(cat "$dir/packancien")"
  kv "arm_${nom}_pack_dev_final" "$(cat "$dir/packdev")"

  # LA DECISION VIENT DU REGISTRE DE LA GARDE : sur un refus il n'y a pas de proof.txt.
  local reg="$dir/.autoport/logs/device-asset-gate.tsv"
  if [ -s "$reg" ]; then
    kv "arm_${nom}_decision" "$(tail -1 "$reg" | cut -f4)"
    kv "arm_${nom}_gate_rc"  "$(tail -1 "$reg" | cut -f5)"
    kv "arm_${nom}_raison"   "$(tail -1 "$reg" | cut -f9 | tr -d '\n')"
  else
    kv "arm_${nom}_decision" absent
    kv "arm_${nom}_gate_rc" -1
    kv "arm_${nom}_raison" registre-absent
  fi

  local avant apres
  avant=$(cat "$dir/proof-avant.sha"); apres=""
  [ -s "$pf" ] && apres=$(sha256sum "$pf" | cut -c1-64)
  if [ "$apres" = "$avant" ]; then kv "arm_${nom}_preuve_precedente" intacte
  elif [ -s "$prev" ] && [ "$(sha256sum "$prev" | cut -c1-64)" = "$avant" ]; then
    kv "arm_${nom}_preuve_precedente" archivee
  else kv "arm_${nom}_preuve_precedente" perdue; fi

  if [ -s "$pf" ] && ! grep -q '^marqueur=preuve-de-la-course-precedente$' "$pf"; then
    kv "arm_${nom}_proof" 1
    local vu
    vu=$(sed -n 's/^sandbox_engine_pack_md5_vu=//p' "$pf" | tail -1)
    kv "arm_${nom}_pack_mesure" "$vu"
    # LA GRANDEUR DE L'ITEM : une course qui a MESURE un pack qui n'est pas le pack local.
    if [ -z "$vu" ]; then kv "arm_${nom}_mesure_sur_pack_perime" -1
    elif [ "$vu" != "$(cat "$dir/packlocal")" ]; then kv "arm_${nom}_mesure_sur_pack_perime" 1
    else kv "arm_${nom}_mesure_sur_pack_perime" 0; fi
    # Ce que CHAQUE porte a ecrit dans la preuve, cote a cote.
    local k
    for k in proof_binary_decision proof_binary_deploy_attempted asset_pack_decision \
             asset_pack_deploy_attempted asset_pack_local_md5 asset_pack_device_md5_before \
             asset_pack_device_md5 asset_pack_checked_before_measure; do
      kv "arm_${nom}_p_${k}" "$(sed -n "s/^${k}=//p" "$pf" | tail -1)"
    done
  else
    kv "arm_${nom}_proof" 0
    kv "arm_${nom}_pack_mesure" -
    kv "arm_${nom}_mesure_sur_pack_perime" 0
  fi
}

#          nom      pack appareil  APK       garde retiree  install KO
BRAS="egaux:local:conforme:0:0 goal:ancien:conforme:0:0 vieux:ancien:conforme:1:0 sansapk:ancien:aucun:0:0 installko:ancien:conforme:0:1"
montes=0; courus=0
for spec in $BRAS; do
  IFS=: read -r nom pk apk sg ko <<<"$spec"
  if monte_bras "$nom" "$SB/$nom" "$pk" "$apk" "$sg" "$ko"; then
    montes=$((montes + 1))
    court_bras "$nom" "$SB/$nom"
    courus=$((courus + 1))
  else
    note "bras $nom : montage impossible"
    kv "arm_${nom}_rc" -1; kv "arm_${nom}_decision" montage-impossible
    kv "arm_${nom}_proof" 0; kv "arm_${nom}_started" -1
    kv "arm_${nom}_preuve_precedente" inconnue
  fi
done
kv selftest_arms_montes "$montes"
kv selftest_arms_courus "$courus"
kv selftest_ran 1
