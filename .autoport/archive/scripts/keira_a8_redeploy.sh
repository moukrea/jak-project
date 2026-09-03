#!/usr/bin/env bash
# keira_a8_redeploy.sh — CLOSE-GATE fix, attempt 8 of Grecharged-secondary-motion.
#
# CE QUI A ECHOUE, ET POURQUOI (diagnostic mesure, rien de suppose) :
#
#   Le validateur de phase sort 0. Ce qui a echoue est la close-gate :
#     DEPLOY-VERIFY FAIL: custom pack STALE on device:
#       stamp 'c35d886d2c371' != built version 'ceb901590eec4'
#
#   Cause racine, lue dans le log du constructeur (.autoport/logs/auto_build_apk.txt) :
#     19:48:47 APK pret pour le commit 613218dfa3 — le publieur prendra le relais
#     19:48:47 device: org.opengoal.gk.jak1 au premier plan sur le Redmi
#              (mesure du superviseur) — installation differee
#
#   Le constructeur a bati un ensemble coherent (CGO arm64 19:46, pack custom 19:48,
#   APK 19:48) puis a REFUSE de l'installer parce que le jeu etait au premier plan sur
#   le Redmi. Et surtout : il ecrit son tampon de contenu (`echo "$h" > "$STAMP"`)
#   AVANT d'installer. Une installation differee n'est donc JAMAIS reprise — au tour
#   suivant le contenu n'a pas change, la boucle `continue`, et le telephone reste
#   indefiniment en arriere du build. Le differe n'etait pas une attente, c'etait un
#   abandon silencieux.
#
#   Mesure a 19:59, avant ce script :
#     - jeu au premier plan sur le Redmi ? NON (com.miui.home au focus, aucun process
#       org.opengoal). La mesure qui justifiait le differe etait finie depuis longtemps.
#     - pack custom : device c35d886d2c371 != bati ceb901590eec4
#     - pack CGO    : device c22e3680d7b22 != bati cddf6d8b3ac41
#     - libgk       : chaine build==APK==device OK (aucun changement C++ : c'est bien
#       un retard de DONNEES + GOAL, pas de moteur natif).
#
# NIVEAU DE BUILD (consigne permanente : le chemin le moins cher qui prouve) :
#   libgk.so  : AUCUN REBUILD — la chaine build==APK==device passe deja.
#   GOAL/CGO  : AUCUN REBUILD — GAME.CGO arm64 (19:46) est plus recent que les deux
#               sources du moteur (jak-hd-physics.gc 19:10, phys-room.gc 19:17).
#   packs+APK : AUCUN REBUILD — l'APK de 19:48 embarque deja la version ceb901590eec4,
#               et le membre recharged_assets/physics_chains.txt du pack est
#               byte-identique au fichier de l'arbre (md5 9d7701c8fd2679c05518b3daf225904f).
#   => il ne reste QUE l'installation. C'est le seul travail qui n'a pas ete fait.
#
# Jamais de kill par motif, jamais de rm -rf sur du code. Chaque etape echoue en disant
# quoi relancer.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"
GAME=jak1
PKG="org.opengoal.gk.${GAME}"
OUT=.autoport/reports/Grecharged-secondary-motion
mkdir -p "$OUT"
LOG="$OUT/a8_redeploy.log"; : > "$LOG"
say(){ echo "[a8] $(date +%H:%M:%S) $*" | tee -a "$LOG"; }
die(){ echo "[a8 FAIL] $*" | tee -a "$LOG"; exit 1; }

CUS_MAN="android/app/src/${GAME}/assets-slim/bundle/${GAME}_custom.manifest.properties"
CGO_MAN="android/app/src/${GAME}/assets-slim/bundle/${GAME}_cgo.manifest.properties"
APK="android/app/build/outputs/apk/${GAME}/debug/app-${GAME}-debug.apk"

# --- PREFLIGHT ---------------------------------------------------------------------
# Match sur le NOM du process (ps -eo comm), jamais sur un motif dans les arguments :
# un grep sur les args matcherait ce script lui-meme et il s'auto-bloquerait.
busy=$(ps -eo comm --no-headers | awk '$1=="goalc"||$1=="cmake"||$1=="ninja"||$1=="cc1plus"{print $1}' | sort -u | tr '\n' ' ')
[ -z "$busy" ] || die "un build tourne ($busy) — refuse d'installer par-dessus. Attends-le ou arrete-le par PID EXACT."
w=$(ps -eo pid,args --no-headers | grep '[a]uto_build_apk\.sh' | awk '{print $1}' | tr '\n' ' ')
[ -z "$w" ] || die "auto_build_apk.sh est vivant (PID: $w) : il rebatirait GAME.CGO pendant l'install. Arrete-le par PID EXACT, relance ce script, puis redemarre-le."
[ -f "$APK" ] || die "pas d'APK a $APK"
say "preflight OK : aucun compilateur, aucun constructeur d'APK arme"

# Le verrou de livraison doit couvrir TOUT le cycle install + boot LoaderActivity :
# c'est la fenetre ou aucun compilateur ne tourne, donc celle ou le constructeur se
# croit libre de repartir sur le meme arbre.
LOCK=.autoport/.deploy-in-progress
printf 'keira_a8_redeploy.sh pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
say "verrou de livraison pose ($LOCK)"

WANT_CUS=$(grep -E '^version=' "$CUS_MAN" | cut -d= -f2)
WANT_CGO=$(grep -E '^version=' "$CGO_MAN" | cut -d= -f2)

# --- ETAT AVANT (preuve de ce qu'on corrige, pas une affirmation) --------------------
say "=== AVANT ==="
say "pack custom : bati=$WANT_CUS  device=$($ADB -s "$S" exec-out run-as "$PKG" cat "files/.custom_pack_stamp_${GAME}" 2>/dev/null | tr -d '\r\n')"
say "pack CGO    : bati=$WANT_CGO  device=$($ADB -s "$S" exec-out run-as "$PKG" cat "files/.cgo_pack_stamp_${GAME}" 2>/dev/null | tr -d '\r\n')"

# L'APK doit EMBARQUER la version batie, sinon on installerait un APK perime et le
# tampon ne bougerait pas — la panne d'attente la plus couteuse de cette famille.
APK_CUS=$(unzip -p "$APK" "assets/bundle/${GAME}_custom.manifest.properties" 2>/dev/null | grep -E '^version=' | cut -d= -f2)
[ "$APK_CUS" = "$WANT_CUS" ] || die "l'APK embarque le pack custom '$APK_CUS' alors que l'arbre a bati '$WANT_CUS' — repackage l'APK (gradle) avant d'installer"
APK_CGO=$(unzip -p "$APK" "assets/bundle/${GAME}_cgo.manifest.properties" 2>/dev/null | grep -E '^version=' | cut -d= -f2)
[ "$APK_CGO" = "$WANT_CGO" ] || die "l'APK embarque le pack CGO '$APK_CGO' alors que l'arbre a bati '$WANT_CGO' — repackage l'APK (gradle) avant d'installer"
say "APK verifie : il embarque bien custom=$APK_CUS et cgo=$APK_CGO"

# --- INSTALL ------------------------------------------------------------------------
say "=== INSTALL (585 Mo, plusieurs minutes) ==="
$ADB -s "$S" shell svc power stayon true >/dev/null 2>&1
timeout 1800 "$ADB" -s "$S" install -r "$APK" >> "$LOG" 2>&1 \
  || die "adb install a echoue — voir $LOG (si MIUI a affiche une boite de dialogue, elle est a debloquer)"
say "install OK"

# --- DEBALLAGE ----------------------------------------------------------------------
# Lancement par l'activite RESOLUE (LoaderActivity), JAMAIS MainActivity : MainActivity
# court-circuite l'extraction et n'ecrit aucun tampon, donc l'APK serait installe sans
# que les donnees soient jamais deballees.
COMP=$("$ADB" -s "$S" shell cmd package resolve-activity --brief "$PKG" 2>/dev/null | tr -d '\r' | grep "^${PKG}/" | head -1)
[ -n "$COMP" ] || COMP="${PKG}/org.opengoal.gk.LoaderActivity"
say "activite resolue : $COMP"
"$ADB" -s "$S" shell am force-stop "$PKG" >/dev/null 2>&1
"$ADB" -s "$S" shell am start -n "$COMP" >/dev/null 2>&1

got_cus=""; got_cgo=""
for i in $(seq 1 60); do
  sleep 10
  got_cus=$("$ADB" -s "$S" exec-out run-as "$PKG" cat "files/.custom_pack_stamp_${GAME}" 2>/dev/null | tr -d '\r\n')
  got_cgo=$("$ADB" -s "$S" exec-out run-as "$PKG" cat "files/.cgo_pack_stamp_${GAME}" 2>/dev/null | tr -d '\r\n')
  [ $(( i % 6 )) -eq 0 ] && say "deballage en cours (${i}0s) : custom='$got_cus' cgo='$got_cgo'"
  [ "$got_cus" = "$WANT_CUS" ] && [ "$got_cgo" = "$WANT_CGO" ] && break
done

say "=== APRES ==="
say "pack custom : bati=$WANT_CUS  device=$got_cus"
say "pack CGO    : bati=$WANT_CGO  device=$got_cgo"
[ "$got_cus" = "$WANT_CUS" ] || die "pack custom NON deballe (device '$got_cus' != '$WANT_CUS') — relance LoaderActivity ou reinstalle"
[ "$got_cgo" = "$WANT_CGO" ] || die "pack CGO NON deballe (device '$got_cgo' != '$WANT_CGO') — relance LoaderActivity ou reinstalle"
say "les deux tampons relus SUR LE TELEPHONE correspondent aux versions baties"

# --- L'OVERRIDE EXTERNE, QUE deploy_verify NE VOIT PAS -------------------------------
# Trace d'execution du 2026-08-11 20:08 sur le Redmi, apres une install pourtant certifiee :
#   [hd-phys] PARAMSRC=external-override
#             path=/storage/emulated/0/OpenGOAL/jak1/assets/recharged_assets/physics_chains.txt
# Ce fichier datait de 15:49 (md5 4055f571...) alors que le pack livrait 9d7701c8... Le moteur
# donne la PRIORITE a la copie externe (kmachine.cpp, pc_physics_parse_file) pour que l'owner
# n'ait pas a retelecharger 581 Mo pour une raideur. deploy_verify ne regarde que le pack
# app-prive : il peut donc passer au vert pendant que le jeu tourne sur des parametres vieux de
# quatre heures. On synchronise toutes les sources que le moteur peut LIRE, pas seulement celle
# que la gate regarde.
EXT=/storage/emulated/0/OpenGOAL/jak1/assets/recharged_assets
ext_md5=$("$ADB" -s "$S" shell "md5sum $EXT/physics_chains.txt 2>/dev/null" | tr -d '\r' | cut -d' ' -f1)
loc_md5=$(md5sum recharged_assets/physics_chains.txt | cut -d' ' -f1)
say "override externe : device=$ext_md5 arbre=$loc_md5"
if [ -n "$ext_md5" ] && [ "$ext_md5" != "$loc_md5" ]; then
  "$ADB" -s "$S" push recharged_assets/physics_chains.txt "$EXT/physics_chains.txt" >> "$LOG" 2>&1 \
    || die "push de l'override externe echoue"
  ext_md5=$("$ADB" -s "$S" shell "md5sum $EXT/physics_chains.txt 2>/dev/null" | tr -d '\r' | cut -d' ' -f1)
  [ "$ext_md5" = "$loc_md5" ] || die "override externe toujours different apres push ($ext_md5)"
  say "override externe resynchronise — md5 relu sur le telephone = $ext_md5"
fi

# On laisse le telephone propre : l'app ne reste pas en arriere-plan apres un test.
"$ADB" -s "$S" shell am force-stop "$PKG" >/dev/null 2>&1
say "app arretee (telephone laisse propre)"
say "DONE — relance maintenant .autoport/lib/deploy_verify.sh $S $GAME"
