#!/usr/bin/env bash
# lib/device_binary_gate.sh — LA VERIFICATION PRECEDE LA MESURE.
#
# POURQUOI (harness-proof-run-device-deploys-or-refuses-first). `lib/proof_run.sh <id> device`
# NE DEPLOYAIT RIEN : il lancait l'application DEJA INSTALLEE, mesurait 400 s, et le seul
# temoin d'un binaire perime — `device_lib_md5 != local_lib_md5` — arrivait au fond de
# `proof.txt`, une fois la course finie. Le symptome que ca produit est
# `proof_feature_state=absent` : l'instrument de l'item n'est pas dans le .so du telephone.
# Chaque item appareil a donc reinvente la meme garde dans son coin (l'essai 2 de
# `hdr-shadow-range` s'est ecrit `notes/deploy.sh`, sortie 4 sur ecart de md5). Une perte qui se
# repete se rend impossible AU POINT DE PRODUCTION, jamais detectable au point de controle.
#
# CE QU'IL FAIT, ET DANS CET ORDRE :
#   1. il lit le md5 du `libgk.so` LOCAL et celui du `libgk.so` REELLEMENT installe ;
#   2. egaux          -> `identique`, rc 0 : la course peut mesurer ;
#   3. differents     -> il cherche un APK DEJA BATI dont le `lib/arm64-v8a/libgk.so` porte le
#                        md5 local. S'il en trouve un ET que le verrou du CONSTRUCTEUR est
#                        libre, il l'installe, relit le md5, et rend `deploye`, rc 0 ;
#   4. sinon          -> `refus`, rc 6, TOUT DE SUITE. Rien n'est mesure, rien n'est efface.
#   5. illisible      -> `inconnu`, rc 0 : l'appelant garde ses propres chemins d'echec. Ce
#                        script ne prononce jamais « preuve impossible » a la place d'un autre.
#
# CE QU'IL NE FAIT PAS. Il ne BATIT rien : ni `cmake --build build-android`, ni gradle. Le
# constructeur et le publieur ne sont pas de son ressort — il ne fait que LIVRER un artefact que
# le constructeur a deja produit, et seulement sous le verrou de celui-ci. Un `adb install` hors
# de ce verrou pendant qu'un build ecrit l'APK livre un fichier a moitie ecrit.
#
# LE DENOMINATEUR. Chaque passage ecrit UNE ligne dans le registre append-only
# `.autoport/logs/device-binary-gate.tsv`. « Zero course sur binaire perime » sans population,
# c'est zero sur zero, c'est-a-dire rien. Le registre est la seule population qui dise sur
# combien de courses la garde a decide, et ce qu'elle a decide.
#
# Usage : lib/device_binary_gate.sh --binary <so> [--item ID] [--arm SUF] [--serial S]
# Sortie : des `cle=valeur` sur stdout (sans espace : `proof.txt` jette toute valeur a espace),
#          les explications sur stderr.
# Codes  : 0 = la course peut continuer (identique | deploye | inconnu)
#          6 = REFUS : le telephone porte un AUTRE binaire et rien ne permet de le corriger.
#              Le code n'est ecrit QU'ICI (`RC_REFUS`) ; l'appelant refuse sur la DECISION
#              (`proof_binary_decision=refus`) et propage ce code, il ne le retape pas.
#          2 = usage.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "proof_binary_gate_ran=0"; exit 2; }
cd "$ROOT" || exit 2
AP="$ROOT/.autoport"

BIN=""; ITEM="-"; ARM=""; SERIAL_IN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --binary) BIN="${2:-}"; shift 2 ;;
    --item)   ITEM="${2:--}"; shift 2 ;;
    --arm)    ARM="${2:-}"; shift 2 ;;
    --serial) SERIAL_IN="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$BIN" ] || { echo "proof_binary_gate_ran=0"; echo "usage: device_binary_gate.sh --binary <so>" >&2; exit 2; }

note(){ printf '[garde-binaire %s] %s\n' "$ITEM" "$*" >&2; }
# Toute valeur publiee passe par ici : les espaces deviennent des `_`, parce que le moissonneur
# de `proof.txt` ne retient que `^cle=[^espace]+$` et qu'une valeur a espace est publiee pour
# personne. Une valeur vide devient `-` : une case vide se lit « verifie », pas « pas regarde ».
pub(){ local v="${2:-}"; v=$(printf '%s' "$v" | tr -s '[:space:]' '_'); printf '%s=%s\n' "$1" "${v:--}"; }

RC_REFUS=6         # le code du refus, ecrit une seule fois dans tout le harnais
DECISION="inconnu"; RAISON="-"; RC=0
DEV_MD5="-"; DEV_MD5_AVANT="-"; LOCAL_MD5="-"
DEPLOY_TENTE=0; DEPLOY_RC=-1; DEPLOY_SOURCE="-"
LOCK_ETAT="-"; APK_CANDIDATS=0; APK_CONFORMES=0
SERIAL="-"; APKPATH=""

ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"; [ -x "$ADB" ] || ADB=adb
PKG="${AUTOPORT_PKG:-org.opengoal.gk.jak1}"
# Les APK que le CONSTRUCTEUR a deja produits. Le glob est reglable pour qu'un bac a sable
# puisse fabriquer la condition au lieu de l'attendre.
APK_GLOB="${AUTOPORT_APK_GLOB:-android/app/build/outputs/apk/*/*/*.apk}"
LOCK="${AUTOPORT_DEPLOY_LOCK:-$AP/.deploy-in-progress}"
REGISTRE="${AUTOPORT_BINARY_GATE_REGISTRY:-$AP/logs/device-binary-gate.tsv}"

fin(){
  # LE REGISTRE, AVANT LA SORTIE, QUEL QUE SOIT LE VERDICT. Un registre qu'on n'ecrit que dans
  # le cas heureux ne peut pas servir de denominateur.
  mkdir -p "$(dirname "$REGISTRE")" 2>/dev/null
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ITEM" "${ARM:-livre}" "$DECISION" "$RC" \
    "$LOCAL_MD5" "$DEV_MD5" "$DEPLOY_TENTE" "$RAISON" >> "$REGISTRE" 2>/dev/null
  pub proof_binary_gate_ran 1
  pub proof_binary_decision "$DECISION"
  pub proof_binary_rc "$RC"
  pub proof_binary_reason "$RAISON"
  pub proof_binary_local_md5 "$LOCAL_MD5"
  pub proof_binary_device_md5 "$DEV_MD5"
  pub proof_binary_device_md5_before "$DEV_MD5_AVANT"
  pub proof_binary_serial "$SERIAL"
  # LE TEMOIN QUE LA PORTE LIT : la verification a-t-elle eu lieu AVANT la mesure. Il vaut 1
  # des que les deux md5 ont ete LUS et compares, jamais sur une intention.
  case "$DECISION" in
    identique|deploye|refus) pub proof_binary_checked_before_measure 1 ;;
    *)                       pub proof_binary_checked_before_measure 0 ;;
  esac
  pub proof_binary_deploy_attempted "$DEPLOY_TENTE"
  pub proof_binary_deploy_rc "$DEPLOY_RC"
  pub proof_binary_deploy_source "$DEPLOY_SOURCE"
  pub proof_binary_lock_state "$LOCK_ETAT"
  pub proof_binary_apk_candidates "$APK_CANDIDATS"
  pub proof_binary_apk_conforming "$APK_CONFORMES"
  exit "$RC"
}

# ------------------------------------------------------------------- le md5 du .so LOCAL ----
if [ ! -s "$BIN" ]; then
  RAISON="binaire-local-absent"; note "$BIN absent ou vide"; fin
fi
LOCAL_MD5=$(md5sum "$BIN" 2>/dev/null | cut -d' ' -f1)
[ -n "$LOCAL_MD5" ] || { RAISON="md5-local-illisible"; fin; }

# ------------------------------------------------------------------------- l'appareil -------
# L'appareil est CHOISI par le seul nommeur d'appareil du harnais. Ce script n'en connait aucun.
if [ -n "$SERIAL_IN" ]; then
  SERIAL="$SERIAL_IN"
else
  SERIAL=$(bash "$AP/lib/pick_device.sh" 2>/dev/null) || SERIAL=""
fi
if [ -z "$SERIAL" ] || [ "$SERIAL" = "-" ]; then
  SERIAL="-"; RAISON="aucun-appareil"; note "aucun appareil : la garde ne decide rien, l'appelant garde ses chemins"; fin
fi
if [ "$(timeout 15 "$ADB" -s "$SERIAL" get-state 2>/dev/null | tr -d '\r')" != device ]; then
  RAISON="appareil-hors-ligne"; fin
fi

# ------------------------------------------------------- le md5 du .so REELLEMENT installe ---
lire_md5_appareil(){
  local p m
  p=$(timeout 20 "$ADB" -s "$SERIAL" shell pm path "$PKG" 2>/dev/null | sed 's/package://' | tr -d '\r' | head -1)
  [ -n "$p" ] || { echo ""; return 1; }
  APKPATH="$p"
  m=$(timeout 90 "$ADB" -s "$SERIAL" shell "md5sum $(dirname "$p")/lib/arm64/libgk.so 2>/dev/null" \
      | tr -d '\r' | awk '{print $1}' | head -1)
  [ -n "$m" ] || { echo ""; return 1; }
  echo "$m"
}
DEV_MD5=$(lire_md5_appareil) || DEV_MD5=""
if [ -z "$DEV_MD5" ]; then
  DEV_MD5="-"; RAISON="md5-appareil-illisible"
  note "le .so du telephone n'est pas lisible ($PKG) : la garde ne decide rien"
  fin
fi

if [ "$DEV_MD5" = "$LOCAL_MD5" ]; then
  DECISION="identique"; RAISON="le-telephone-porte-le-binaire-local"
  note "md5 identiques ($LOCAL_MD5) : la course peut mesurer"
  fin
fi

# ============================ ECART : ON DEPLOIE, OU ON REFUSE — JAMAIS ON NE MESURE =========
DEV_MD5_AVANT="$DEV_MD5"
note "ECART : le telephone porte $DEV_MD5, le build local $LOCAL_MD5"

# LE VERROU APPARTIENT AU CONSTRUCTEUR. On ne pose le notre que s'il est LIBRE, et on l'ecrit
# comme les DIRECTIVES l'exigent : le PID dedans, le nettoyage installe. Un verrou dont le PID
# ne repond plus a `kill -0` est perime immediatement — le shell d'un appel d'outil meurt dans
# la seconde et laisse un verrou qui nomme un cadavre.
verrou_libre(){
  local p
  if [ -f "$LOCK" ]; then
    p=$(sed -n 's/.*pid=\([0-9]\{1,\}\).*/\1/p' "$LOCK" | head -1)
    if [ -n "${p:-}" ] && kill -0 "$p" 2>/dev/null; then LOCK_ETAT="tenu-pid=$p"; return 1; fi
    LOCK_ETAT="perime-pid=${p:-inconnu}"
    return 0
  fi
  LOCK_ETAT="libre"; return 0
}

# L'APK CONFORME : celui dont le `libgk.so` embarque PORTE le md5 local. On ne se fie pas a une
# date ni a un chemin — « un chemin n'est pas une date », et un APK plus recent peut avoir ete
# bati sur un AUTRE .so. On lit le contenu.
md5_dans_apk(){
  python3 - "$1" <<'PY' 2>/dev/null
import hashlib, sys, zipfile
try:
    with zipfile.ZipFile(sys.argv[1]) as z:
        for nom in ('lib/arm64-v8a/libgk.so', 'lib/arm64/libgk.so'):
            try:
                with z.open(nom) as f:
                    h = hashlib.md5()
                    for bloc in iter(lambda: f.read(1 << 20), b''):
                        h.update(bloc)
                    print(h.hexdigest())
                    break
            except KeyError:
                continue
except Exception:
    pass
PY
}

APK_RETENU=""
for apk in $APK_GLOB; do
  [ -f "$apk" ] || continue
  APK_CANDIDATS=$((APK_CANDIDATS + 1))
  m=$(md5_dans_apk "$apk")
  if [ "$m" = "$LOCAL_MD5" ]; then
    APK_CONFORMES=$((APK_CONFORMES + 1))
    [ -n "$APK_RETENU" ] || APK_RETENU="$apk"
  fi
done

if [ -z "$APK_RETENU" ]; then
  DECISION="refus"; RC=$RC_REFUS; RAISON="aucun-apk-porte-le-binaire-local"
  DEPLOY_SOURCE="aucun-apk-conforme"
  note "$APK_CANDIDATS APK examines, aucun ne porte $LOCAL_MD5 : seul le CONSTRUCTEUR peut"
  note "en produire un. REFUS avant l'appareil — aucune mesure sur un binaire perime."
  fin
fi

if ! verrou_libre; then
  DECISION="refus"; RC=$RC_REFUS; RAISON="verrou-du-constructeur-tenu"
  DEPLOY_SOURCE="$APK_RETENU"
  note "un APK conforme existe ($APK_RETENU) mais le verrou du constructeur est $LOCK_ETAT :"
  note "installer par-dessus un build en cours livre un fichier a moitie ecrit. REFUS."
  fin
fi

# ------------------------------------------------------------------------ LA LIVRAISON ------
DEPLOY_SOURCE="$APK_RETENU"
DEPLOY_TENTE=1
printf '%s pid=%s\n' "$0" "$$" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
note "verrou pose (pid=$$) ; installation de $APK_RETENU sur $SERIAL"
timeout 600 "$ADB" -s "$SERIAL" install -r -d -t "$APK_RETENU" >&2
DEPLOY_RC=$?
rm -f "$LOCK"; trap - EXIT

if [ "$DEPLOY_RC" != 0 ]; then
  DECISION="refus"; RC=$RC_REFUS; RAISON="install-echouee-rc=$DEPLOY_RC"
  note "l'installation a rendu $DEPLOY_RC : REFUS, on ne mesure pas."
  fin
fi

DEV_MD5=$(lire_md5_appareil) || DEV_MD5=""
[ -n "$DEV_MD5" ] || DEV_MD5="-"
if [ "$DEV_MD5" != "$LOCAL_MD5" ]; then
  DECISION="refus"; RC=$RC_REFUS; RAISON="apres-install-le-md5-differe-encore"
  note "installe, et le telephone porte toujours $DEV_MD5 : REFUS."
  fin
fi
DECISION="deploye"; RAISON="apk-du-constructeur-installe"
note "LIVRE : $LOCAL_MD5 sur $SERIAL ; la course peut mesurer"
fin
