#!/usr/bin/env bash
# deploy_verify_assets.sh — PROVE the device is running the freshly-built GOAL
# code (CGO/DGO assets), not just the native libgk.so. Companion to
# deploy_verify.sh, which only covers libgk.so.
#
# WHY THIS EXISTS (2026-07-09): the HUD/menu/gameplay logic lives in GOAL code
# that compiles into out/<game>/iso/*.CGO|*.DGO. On the dev Redmi these are
# delivered via the slim-APK CGO pack unpacked to  run-as <pkg> files/cgo/<game>/
# (fake_iso scans it as an overlay). deploy_verify.sh passed while the device ran an INTERMEDIATE
# round-3 GAME.CGO — a fix "committed + built + libgk-deployed" but the GOAL
# CGOs never re-pushed => the owner saw stale HUD behavior. This guard catches it.
#
# Checks (all must pass):
#   1. FRESHNESS: newest out/<game>/iso/*.CGO|*.DGO is NEWER than the newest
#      goal_src/<game> source mtime (catches "edited GOAL but didn't rebuild").
#   2. FULL-SET MATCH: every *.CGO|*.DGO in out/<game>/iso/ has a byte-identical
#      (md5) counterpart at files/cgo/<game>/ on the device (catches a
#      partial/stale/never-pushed asset set).
#
# Usage: deploy_verify_assets.sh [SERIAL] [GAME]   (defaults: eae4df44 jak1)
# Exit 0 = device provably runs the fresh GOAL CGO/DGO set; nonzero = NOT.
#
# MODE PORTE (`--gate`, harness-device-deploy-gate-must-compare-the-asset-pack, 22/09) — voir le
# bloc qui suit. C'est CE mode que `lib/proof_run.sh` (chemin appareil) et `lib/deploy_verify.sh`
# (fermeture) appellent. Le mode historique ci-dessous reste tel quel pour un usage a la main.
set -uo pipefail

# ============================================================ MODE PORTE ======================
# POURQUOI. `lib/device_binary_gate.sh` ne compare QUE `lib/arm64-v8a/libgk.so`. Le code GOAL
# voyage dans un AUTRE fichier de l'APK, `assets/bundle/<game>_cgo.zip` (GAME.CGO, ENGINE.CGO...),
# et ce fichier n'etait compare NULLE PART. Un essai 100 % GOAL laisse le binaire identique : la
# garde binaire rendait `identique`, n'installait rien, et la course mesurait le pack de l'essai
# PRECEDENT en le prenant pour le sien. hud-eco-gauge y a brule ses essais 11, 12, 13 et 16 ; le
# 17 n'a donne un chiffre juste que parce que l'APK a ete installe A LA MAIN
# (`reports/hud-eco-gauge/notes/essai17-livraison.sh`). Ce mode rend ce geste inutile.
#
# CE QU'IL COMPARE : LES OCTETS DU ZIP, des deux cotes. Ni une date, ni un tampon de version, ni
# le md5 du binaire.
#   local    = md5 de `android/app/src/<game>/assets-slim/bundle/<game>_cgo.zip`, le pack que le
#              constructeur a produit et qu'il embarque dans l'APK ;
#   appareil = md5 du MEME membre lu DANS l'APK installe (`unzip -p <base.apk> assets/bundle/...`
#              execute sur le telephone : 1,4 s sur le Redmi, rien n'est tire sur l'hote).
# Le tampon deballe (`files/.cgo_pack_stamp_<game>`) est publie A COTE, pour information : le
# LoaderActivity le remet d'aplomb au lancement suivant quand l'APK porte un autre pack.
#
# CE QU'IL DECIDE — les memes quatre mots que la garde binaire, lus par le meme appelant :
#   identique  les deux md5 sont egaux : rien n'est pousse, la course mesure (rc 0) ;
#   deploye    ecart, et un APK DEJA BATI par le constructeur porte le pack local ET le libgk.so
#              local : il est installe sous le verrou du constructeur, le md5 est RELU (rc 0) ;
#   refus      ecart que rien ne corrige, installation qui echoue, pack illisible sur un telephone
#              qui repond : ROUGE immediat, AVANT l'amorcage (rc = celui de la garde binaire) ;
#   inconnu    rien a comparer (pas de pack local, pas d'appareil, paquet absent) : publie, et
#              l'appelant garde ses propres chemins d'echec.
# `--no-deploy` (la fermeture) : un ecart est un `refus`, jamais une installation.
#
# LE DENOMINATEUR : une ligne par passage dans `.autoport/logs/device-asset-gate.tsv`.
# Usage : deploy_verify_assets.sh --gate [--binary <so>] [--item ID] [--arm SUF] [--serial S]
#                                        [--game G] [--no-deploy]
# Sortie : des `cle=valeur` sans espace sur stdout, les explications sur stderr.
if [ "${1:-}" = --gate ]; then
  shift
  export LC_ALL=C
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "asset_pack_gate_ran=0"; exit 2; }
  cd "$ROOT" || exit 2
  AP="$ROOT/.autoport"
  BIN=""; ITEM="-"; ARM=""; SERIAL_IN=""; GAME=jak1; NO_DEPLOY=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --binary)    BIN="${2:-}"; shift 2 ;;
      --item)      ITEM="${2:--}"; shift 2 ;;
      --arm)       ARM="${2:-}"; shift 2 ;;
      --serial)    SERIAL_IN="${2:-}"; shift 2 ;;
      --game)      GAME="${2:-jak1}"; shift 2 ;;
      --no-deploy) NO_DEPLOY=1; shift ;;
      *) shift ;;
    esac
  done
  note(){ printf '[garde-pack %s] %s\n' "$ITEM" "$*" >&2; }
  pub(){ local v="${2:-}"; v=$(printf '%s' "$v" | tr -s '[:space:]' '_'); printf '%s=%s\n' "$1" "${v:--}"; }

  # LE CODE DU REFUS N'EST ECRIT QU'A UN ENDROIT DU HARNAIS (`RC_REFUS` de la garde binaire) : on
  # le LIT. Illisible -> 1, jamais 0 : un refus qui sortirait en 0 serait un vert.
  RC_REFUS=$(sed -n 's/^RC_REFUS=\([0-9]\{1,\}\).*/\1/p' "$AP/lib/device_binary_gate.sh" 2>/dev/null | head -1)
  RC_REFUS=${RC_REFUS:-1}
  MD5_VIDE=d41d8cd98f00b204e9800998ecf8427e   # `md5sum` d'un flux vide : un membre ABSENT

  ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"; [ -x "$ADB" ] || ADB=adb
  PKG="${AUTOPORT_PKG:-org.opengoal.gk.$GAME}"
  PACK_MEMBRE="assets/bundle/${GAME}_cgo.zip"
  PACK_LOCAL="android/app/src/${GAME}/assets-slim/bundle/${GAME}_cgo.zip"
  MAN_LOCAL="android/app/src/${GAME}/assets-slim/bundle/${GAME}_cgo.manifest.properties"
  APK_GLOB="${AUTOPORT_APK_GLOB:-android/app/build/outputs/apk/*/*/*.apk}"
  LOCK="${AUTOPORT_DEPLOY_LOCK:-$AP/.deploy-in-progress}"
  REGISTRE="${AUTOPORT_ASSET_GATE_REGISTRY:-$AP/logs/device-asset-gate.tsv}"

  DECISION="inconnu"; RAISON="-"; RC=0
  LOCAL_MD5="-"; DEV_MD5="-"; DEV_MD5_AVANT="-"; LOCAL_VER="-"; DEV_STAMP="-"
  BIN_MD5="-"; DEPLOY_TENTE=0; DEPLOY_RC=-1; DEPLOY_SOURCE="-"; LOCK_ETAT="-"
  APK_CANDIDATS=0; APK_PACK_OK=0; APK_CONFORMES=0; SERIAL="-"

  fin(){
    mkdir -p "$(dirname "$REGISTRE")" 2>/dev/null
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ITEM" "${ARM:-livre}" "$DECISION" "$RC" \
      "$LOCAL_MD5" "$DEV_MD5" "$DEPLOY_TENTE" "$RAISON" >> "$REGISTRE" 2>/dev/null
    pub asset_pack_gate_ran 1
    pub asset_pack_decision "$DECISION"
    pub asset_pack_rc "$RC"
    pub asset_pack_reason "$RAISON"
    # COTE A COTE : l'empreinte locale et celle de l'appareil, en octets de zip.
    pub asset_pack_local_md5 "$LOCAL_MD5"
    pub asset_pack_device_md5 "$DEV_MD5"
    pub asset_pack_device_md5_before "$DEV_MD5_AVANT"
    pub asset_pack_local_version "$LOCAL_VER"
    pub asset_pack_device_stamp "$DEV_STAMP"
    pub asset_pack_serial "$SERIAL"
    pub asset_pack_no_deploy "$NO_DEPLOY"
    pub asset_pack_deploy_attempted "$DEPLOY_TENTE"
    pub asset_pack_deploy_rc "$DEPLOY_RC"
    pub asset_pack_deploy_source "$DEPLOY_SOURCE"
    pub asset_pack_lock_state "$LOCK_ETAT"
    pub asset_pack_apk_candidates "$APK_CANDIDATS"
    pub asset_pack_apk_with_local_pack "$APK_PACK_OK"
    pub asset_pack_apk_conforming "$APK_CONFORMES"
    case "$DECISION" in
      identique|deploye|refus) pub asset_pack_checked_before_measure 1 ;;
      *)                       pub asset_pack_checked_before_measure 0 ;;
    esac
    exit "$RC"
  }
  refus(){ DECISION="refus"; RC=$RC_REFUS; RAISON="$1"; shift; note "REFUS : $*"; fin; }

  # --------------------------------------------------------------------- le pack LOCAL --------
  # Pas de pack local = rien a comparer (APK autonome d'avant les packs, bac a sable d'un autre
  # item). On le DIT ; ce n'est pas un vert.
  if [ ! -s "$PACK_LOCAL" ]; then RAISON="pack-local-absent"; note "$PACK_LOCAL absent"; fin; fi
  LOCAL_MD5=$(md5sum "$PACK_LOCAL" 2>/dev/null | cut -d' ' -f1)
  [ -n "$LOCAL_MD5" ] || { LOCAL_MD5="-"; RAISON="md5-local-illisible"; fin; }
  LOCAL_VER=$(sed -n 's/^version=//p' "$MAN_LOCAL" 2>/dev/null | tr -d '\r' | head -1)
  if [ -n "$BIN" ] && [ -s "$BIN" ]; then BIN_MD5=$(md5sum "$BIN" | cut -d' ' -f1); fi

  # ---------------------------------------------------------------------- l'appareil ----------
  if [ -n "$SERIAL_IN" ]; then SERIAL="$SERIAL_IN"
  else SERIAL=$(bash "$AP/lib/pick_device.sh" 2>/dev/null) || SERIAL=""; fi
  if [ -z "$SERIAL" ] || [ "$SERIAL" = "-" ]; then SERIAL="-"; RAISON="aucun-appareil"; fin; fi
  if [ "$(timeout 15 "$ADB" -s "$SERIAL" get-state 2>/dev/null | tr -d '\r')" != device ]; then
    RAISON="appareil-hors-ligne"; fin
  fi
  lire_pack_appareil(){
    local p m
    p=$(timeout 20 "$ADB" -s "$SERIAL" shell pm path "$PKG" 2>/dev/null | sed 's/package://' | tr -d '\r' | head -1)
    [ -n "$p" ] || { echo "paquet-absent"; return 1; }
    m=$(timeout 180 "$ADB" -s "$SERIAL" shell "unzip -p $p $PACK_MEMBRE 2>/dev/null | md5sum" 2>/dev/null \
        | tr -d '\r' | awk '{print $1}' | head -1)
    case "$m" in ''|"$MD5_VIDE") echo "pack-appareil-illisible"; return 1 ;; esac
    echo "$m"
  }
  lire_tampon(){
    timeout 15 "$ADB" -s "$SERIAL" exec-out run-as "$PKG" cat "files/.cgo_pack_stamp_$GAME" 2>/dev/null \
      | tr -d '\r\n' | head -c 64
  }
  if ! DEV_MD5=$(lire_pack_appareil); then
    r="$DEV_MD5"; DEV_MD5="-"
    # Un paquet ABSENT : la garde binaire l'a deja dit (md5 illisible), l'appelant echoue plus
    # bas. Un paquet PRESENT dont le pack ne se lit pas : la garde serait AVEUGLE — rouge.
    [ "$r" = paquet-absent ] && { RAISON="$r"; fin; }
    refus "$r" "le telephone repond mais son pack ne se lit pas : on ne mesure pas a l'aveugle"
  fi
  DEV_STAMP=$(lire_tampon); DEV_STAMP=${DEV_STAMP:--}

  if [ "$DEV_MD5" = "$LOCAL_MD5" ]; then
    DECISION="identique"; RAISON="le-telephone-porte-le-pack-local"
    note "pack identique ($LOCAL_MD5) : rien a pousser"
    fin
  fi

  # ======================= ECART : ON LIVRE, OU ON REFUSE — JAMAIS ON NE MESURE ===============
  DEV_MD5_AVANT="$DEV_MD5"
  note "ECART : le telephone porte le pack $DEV_MD5, le build local $LOCAL_MD5"
  [ "$NO_DEPLOY" = 1 ] && refus "ecart-sans-livraison" "--no-deploy : l'appareil ne porte pas le pack local"

  # L'APK CONFORME porte le pack local ET le libgk.so local : installer un APK au bon pack mais
  # a un autre binaire defairait ce que la garde binaire vient d'etablir.
  apk_md5s(){
    python3 - "$1" "$PACK_MEMBRE" <<'PY' 2>/dev/null
import hashlib, sys, zipfile
def md5(z, n):
    try:
        with z.open(n) as f:
            h = hashlib.md5()
            for b in iter(lambda: f.read(1 << 20), b''):
                h.update(b)
            return h.hexdigest()
    except KeyError:
        return '-'
try:
    with zipfile.ZipFile(sys.argv[1]) as z:
        so = md5(z, 'lib/arm64-v8a/libgk.so')
        print(md5(z, sys.argv[2]), so)
except Exception:
    print('- -')
PY
  }
  APK_RETENU=""
  for apk in $APK_GLOB; do
    [ -f "$apk" ] || continue
    APK_CANDIDATS=$((APK_CANDIDATS + 1))
    read -r m_pack m_so <<<"$(apk_md5s "$apk")"
    [ "$m_pack" = "$LOCAL_MD5" ] || continue
    APK_PACK_OK=$((APK_PACK_OK + 1))
    [ "$BIN_MD5" = "-" ] || [ "$m_so" = "$BIN_MD5" ] || continue
    APK_CONFORMES=$((APK_CONFORMES + 1))
    [ -n "$APK_RETENU" ] || APK_RETENU="$apk"
  done
  if [ -z "$APK_RETENU" ]; then
    DEPLOY_SOURCE="aucun-apk-conforme"
    refus "aucun-apk-porte-le-pack-local" "$APK_CANDIDATS APK examines, $APK_PACK_OK portent le pack local, $APK_CONFORMES aussi le binaire local : seul le CONSTRUCTEUR peut en produire un"
  fi
  DEPLOY_SOURCE="$APK_RETENU"
  if [ -f "$LOCK" ]; then
    if bash "$AP/lib/pidguard.sh" holder "$LOCK" >/dev/null 2>&1; then
      LOCK_ETAT="tenu"
      refus "verrou-du-constructeur-tenu" "un APK conforme existe mais le constructeur tient le verrou : installer par-dessus un build livre un fichier a moitie ecrit"
    fi
    LOCK_ETAT="perime"
  else
    LOCK_ETAT="libre"
  fi

  # ---------------------------------------------------------------------- LA LIVRAISON --------
  DEPLOY_TENTE=1
  printf '%s pid=%s\n' "$0" "$$" > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
  note "verrou pose (pid=$$) ; installation de $APK_RETENU sur $SERIAL"
  timeout 900 "$ADB" -s "$SERIAL" install -r -d -t "$APK_RETENU" >&2
  DEPLOY_RC=$?
  rm -f "$LOCK"; trap - EXIT
  [ "$DEPLOY_RC" = 0 ] || refus "install-echouee-rc=$DEPLOY_RC" "l'installation a rendu $DEPLOY_RC"
  DEV_MD5=$(lire_pack_appareil) || DEV_MD5="-"
  DEV_STAMP=$(lire_tampon); DEV_STAMP=${DEV_STAMP:--}
  [ "$DEV_MD5" = "$LOCAL_MD5" ] || refus "apres-install-le-pack-differe-encore" "installe, et le telephone porte toujours $DEV_MD5"
  DECISION="deploye"; RAISON="apk-du-constructeur-installe"
  note "LIVRE : pack $LOCAL_MD5 sur $SERIAL ; le lancement le deballera"
  fin
fi
# ========================================================== fin du MODE PORTE =================
# LE COMPARATEUR DE FRAICHEUR, RESOLU AVANT LE `cd` (voir lib/deploy_verify.sh).
FR_LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/freshness.sh
cd "$(git rev-parse --show-toplevel)"
# shellcheck source=freshness.sh
. "$FR_LIB" || { echo "DEPLOY-ASSETS FAIL: lib/freshness.sh introuvable ($FR_LIB) — ce script ne compare plus aucun horodatage lui-meme et refuse de deviner." >&2; exit 1; }
SERIAL="${1:-eae4df44}"
GAME="${2:-jak1}"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG="org.opengoal.gk.${GAME}"
# CRITICAL: the device is arm64 — it MUST match the ARM64 CGO build tree, NOT the
# x86 tree (out/<game>/iso). Pushing x86 CGOs to the arm64 device SIGILLs at frame 0
# (2026-07-09 incident: pushed out/jak1/iso x86 5958c908 over the device's arm64
# 998b05ce -> illegal instruction). ISO_DIR override wins; else prefer -arm64-full.
if [ -n "${3:-}" ]; then ISO_DIR="$3"
elif [ -d "out/${GAME}-arm64-full/iso" ]; then ISO_DIR="out/${GAME}-arm64-full/iso"
elif [ -d "out/${GAME}-arm64/iso" ]; then ISO_DIR="out/${GAME}-arm64/iso"
else ISO_DIR="out/${GAME}/iso"; fi
die() { echo "DEPLOY-ASSETS FAIL: $*" >&2; exit 1; }

# Phase Grecharged-external-assets (2026-07): the slim APK ships the arm64
# CGO/DGO set as a "CGO pack" that LoaderActivity unpacks to files/cgo/<game>/
# (fake_iso scans it FIRST as an overlay). This is now the ONLY device engine
# location — the legacy adb-pushed engine-overlay path is retired.
DEV_DIR="files/cgo/${GAME}"
"$ADB" -s "$SERIAL" shell "run-as $PKG sh -c 'ls files/cgo/${GAME}/*.CGO'" >/dev/null 2>&1 \
  || die "no CGO overlay on device at $DEV_DIR (run-as $PKG) — engine pack never unpacked?"
echo "  device CGO dir: $DEV_DIR"

[ -d "$ISO_DIR" ] || die "no build dir $ISO_DIR"
echo "  ref arm64 build tree: $ISO_DIR"
LOCAL_FILES=$(cd "$ISO_DIR" && ls *.CGO *.DGO 2>/dev/null)
[ -n "$LOCAL_FILES" ] || die "no CGO/DGO in $ISO_DIR"
N_LOCAL=$(echo "$LOCAL_FILES" | wc -l)

# 1. Freshness: newest built asset vs newest GOAL source.
# A LA NANOSECONDE, DES DEUX COTES (harness-subsecond-freshness-is-blind, 2026-09-12). Les deux
# cotes etaient tronques a la seconde entiere par `cut -d. -f1`, puis compares par `-lt` : un
# `.gc` reecrit dans la seconde qui suit l'ecriture du dernier CGO etait INVISIBLE, et le `echo`
# ci-dessous imprimait un vert IMMERITE sur une chaine GOAL perimee. Meme faute, meme jour, meme
# correctif que `lib/deploy_verify.sh` — l'egalite est DOUTEUSE, pas fraiche.
FR_SITE=deploy_verify_assets/cgo-vs-goal_src
NEWEST_BUILT_NS=$(find "$ISO_DIR" -type f \( -name '*.CGO' -o -name '*.DGO' \) -printf '%T@\n' 2>/dev/null | fr_plus_recent_ns)
NEWEST_SRC_NS=$(find "goal_src/${GAME}" -type f -printf '%T@\n' 2>/dev/null | fr_plus_recent_ns)
NEWEST_BUILT=$(( NEWEST_BUILT_NS / 1000000000 )); NEWEST_SRC=$(( NEWEST_SRC_NS / 1000000000 ))
if [ "$NEWEST_SRC_NS" != 0 ] && [ "$NEWEST_BUILT_NS" != 0 ]; then
  case "$(fr_verdict "$NEWEST_BUILT_NS" "$NEWEST_SRC_NS")" in
    perime)  die "built CGO/DGO ($(date -d @$NEWEST_BUILT +%H:%M:%S), ${NEWEST_BUILT_NS}ns) OLDER than newest goal_src/$GAME ($(date -d @$NEWEST_SRC +%H:%M:%S), ${NEWEST_SRC_NS}ns) — rebuild the GOAL chain before deploy" ;;
    douteux) die "le CGO/DGO le plus recent et la source GOAL la plus recente portent le MEME horodatage a la nanoseconde ($NEWEST_BUILT_NS) : DOUTEUX, pas frais. Rebatis la chaine GOAL avant de deployer." ;;
  esac
fi
echo "  ok: $N_LOCAL built CGO/DGO newer than newest goal_src/$GAME"

# 2. Full-set md5 match: local build vs device (one adb round-trip).
DEV_MD5=$("$ADB" -s "$SERIAL" shell "run-as $PKG sh -c 'cd $DEV_DIR 2>/dev/null && md5sum *.CGO *.DGO 2>/dev/null'" 2>/dev/null | tr -d '\r')
[ -n "$DEV_MD5" ] || die "no CGO/DGO on device at $DEV_DIR (run-as $PKG) — assets never pushed?"
# Build an associative map basename->md5 from device output.
declare -A DMAP
while read -r h f; do [ -n "$h" ] && DMAP["$(basename "$f")"]="$h"; done <<< "$DEV_MD5"

MISMATCH=0; MISSING=0
while read -r f; do
  [ -z "$f" ] && continue
  L=$(md5sum "$ISO_DIR/$f" | cut -d' ' -f1)
  D="${DMAP[$f]:-}"
  if [ -z "$D" ]; then echo "  MISSING on device: $f"; MISSING=$((MISSING+1));
  elif [ "$L" != "$D" ]; then echo "  STALE on device: $f (build=$L dev=$D)"; MISMATCH=$((MISMATCH+1)); fi
done <<< "$LOCAL_FILES"

[ "$MISSING" -eq 0 ] || die "$MISSING asset(s) missing on device — push the full set to $DEV_DIR"
[ "$MISMATCH" -eq 0 ] || die "$MISMATCH asset(s) STALE on device — device runs OLD GOAL code (re-push out/$GAME/iso/ to $DEV_DIR)"
echo "DEPLOY-ASSETS PASS: device $SERIAL runs the fresh GOAL set ($N_LOCAL/$N_LOCAL CGO/DGO byte-identical to $ISO_DIR)."

# 3. *COMMON.TXT match (jak1 only). The text banks carry the menu strings (e.g. the
# AO carousell values); they ride the cgo pack overlay (files/cgo/<game>). A stale
# re-extract or a never-pushed bank shows the owner "unknown ID". Match every device
# TXT against the banks the build produced:
#   - files/cgo/<game>/*COMMON.TXT  vs  out/<game>/iso/  (the banks the cgo pack ships)
# We only assert on TXT files PRESENT on the device: fail on content mismatch, or on
# a device TXT with no local counterpart; do NOT fail on extra local files.
if [ "$GAME" = "jak1" ]; then
  # android-text-overrides-dropped (2026-09-12) : LE GOLDEN EST `out/<game>/iso`, POINT.
  # Cet appel visait `out/<game>-android-text` — le dossier de l'overlay de texte android, qui
  # n'existe plus (la variante tactile vit desormais sous son propre id dans le banc normal).
  # `[ -d "$ldir" ]` rendait donc 0 avec un « skip », et TOUTE la verification TXT de l'appareil
  # etait sautee en silence, y compris pour les 23 bancs bureau qui, eux, existaient. Une garde
  # d'existence qui saute quand sa cible disparait ne protege plus rien : c'est la meme faute que
  # le `[ -x <script archive> ]` de build_cgo_pack.sh, qui est ce qui a fait perdre le texte.
  # Le parametre de repli reste en place (non utilise) plutot que de changer la signature.
  txt_match(){ # $1=device dir  $2=local override dir  $3=label  $4=local fallback dir
    local ddir="$1" ldir="$2" label="$3" ldir2="${4:-}"
    "$ADB" -s "$SERIAL" shell "run-as $PKG sh -c 'ls $ddir/*COMMON.TXT'" >/dev/null 2>&1 || { echo "  ($label) no device TXT at $ddir — skip"; return 0; }
    [ -d "$ldir" ] || { echo "  ($label) no local dir $ldir — skip"; return 0; }
    local dtxt lf lmd5 dmd5 tmiss=0 tmis=0 n=0
    dtxt=$("$ADB" -s "$SERIAL" shell "run-as $PKG sh -c 'cd $ddir 2>/dev/null && md5sum *COMMON.TXT 2>/dev/null'" 2>/dev/null | tr -d '\r')
    [ -n "$dtxt" ] || { echo "  ($label) no device TXT at $ddir — skip"; return 0; }
    while read -r dmd5 df; do
      [ -n "$dmd5" ] || continue
      df=$(basename "$df"); n=$((n+1))
      if [ -f "$ldir/$df" ]; then lf="$ldir/$df"
      elif [ -n "$ldir2" ] && [ -f "$ldir2/$df" ]; then lf="$ldir2/$df"
      else echo "  ($label) device TXT $df has NO local counterpart in $ldir or ${ldir2:-<none>}"; tmiss=$((tmiss+1)); continue; fi
      lmd5=$(md5sum "$lf" | cut -d' ' -f1)
      if [ "$lmd5" != "$dmd5" ]; then echo "  ($label) STALE TXT on device: $df (build=$lmd5 dev=$dmd5 golden=$lf)"; tmis=$((tmis+1)); fi
    done <<< "$dtxt"
    [ "$tmiss" -eq 0 ] || die "$tmiss device TXT($label) lack a local counterpart — text source out of sync"
    [ "$tmis"  -eq 0 ] || die "$tmis device TXT($label) STALE — device shows OLD text (re-push $label banks)"
    echo "  ok ($label): $n device *COMMON.TXT byte-identical to override/desktop goldens"
  }
  txt_match "files/cgo/${GAME}"      "out/${GAME}/iso"  "banques"
fi
