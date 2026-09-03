#!/usr/bin/env bash
# mm_parity_round2b.sh — reprise du round 2 apres l'echec de l'APK.
#
# CE QUI A BLOQUE, ET CE N'EST PAS NOTRE CHANGEMENT. `:app:bundleJak1CgoPack` a refuse de
# fabriquer l'APK :
#     [cgo-pack] FATAL: staged KERNEL.CGO == x86 oracle (would SIGILL on the arm64 device)
# La garde a RAISON, et je l'ai verifiee moi-meme : out/jak1-arm64-full/iso/KERNEL.CGO et
# out/jak1/iso/KERNEL.CGO rendent le MEME md5 (dae65e14f5676b4a645124ffbbf5a1b6). Le jeu de
# donnees « arm64 » stagé est en realite l'oracle x86, contamine le 2026-08-31 a 01:31 : la
# course arm64 de 02:43 est morte sans imprimer sa ligne « Successfully built all N targets »,
# donc l'etape 2 (staging) n'a jamais rafraichi le stage.
#
# On rebatit donc le jeu arm64 COHERENT avant de reemballer. Rien de tout ceci ne vient de nos
# compteurs : `cmake --build build-android --target gk` a reussi en 26 s et le libgk arm64 LIVRE
# porte deja les 4 marqueurs neufs (mm_note_bind x4, 'PBR BINDS', 'STATE-PUSHES', 'WITHOUT bit8').
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

LOCK=.autoport/.deploy-in-progress
LOG=.autoport/logs/mm_parity_round2b.txt
mkdir -p .autoport/logs
: > "$LOG"
say(){ echo "$(date +%H:%M:%S) $*" | tee -a "$LOG"; }
fail(){ say "[round2b FAIL] $*"; exit 1; }

if [ -f "$LOCK" ]; then
  holder=$(awk '{for(i=1;i<=NF;i++) if($i ~ /^pid=/){sub(/^pid=/,"",$i); print $i}}' "$LOCK" | head -1)
  if [ -n "${holder:-}" ] && kill -0 "$holder" 2>/dev/null; then
    fail "verrou tenu par un PID VIVANT ($holder) — on n'efface JAMAIS un verrou a la main"
  fi
  say "verrou perime (detenteur '${holder:-vide}' mort) — remplace"
fi
printf 'mm-parity-round2b pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
say "verrou pris (pid=$$)  HEAD=$(git rev-parse --short HEAD)"

ORACLE_MD5=$(md5sum out/jak1/iso/KERNEL.CGO 2>/dev/null | cut -d' ' -f1)
say "md5 oracle x86 AVANT : $ORACLE_MD5"
say "md5 stage      AVANT : $(md5sum out/jak1-arm64-full/iso/KERNEL.CGO 2>/dev/null | cut -d' ' -f1)"

# --------------------------------------------- 1. jeu de donnees arm64 coherent
# Deux builds complets (arm64 puis restauration de l'oracle x86) : c'est long par construction.
say "build_arm64_full_consistent.sh (arm64 complet + restauration de l'oracle x86)"
if ! timeout 5400 bash .autoport/build_arm64_full_consistent.sh >> "$LOG" 2>&1; then
  say "--- 40 dernieres lignes ---"; tail -40 "$LOG"
  say "--- 25 dernieres lignes du log goalc arm64 ---"; tail -25 .autoport/logs/full-arm64-mi.log 2>/dev/null | tee -a "$LOG"
  fail "build arm64 coherent echoue"
fi
say "build arm64 coherent OK"

# GARDE, la meme que celle du cgo-pack, mais AVANT de payer 3 minutes de gradle : le stage ne
# doit plus etre l'oracle. Un stage egal a l'oracle SIGILLerait sur l'appareil.
STAGE_MD5=$(md5sum out/jak1-arm64-full/iso/KERNEL.CGO 2>/dev/null | cut -d' ' -f1)
NEW_ORACLE_MD5=$(md5sum out/jak1/iso/KERNEL.CGO 2>/dev/null | cut -d' ' -f1)
say "md5 stage      APRES : $STAGE_MD5"
say "md5 oracle x86 APRES : $NEW_ORACLE_MD5"
[ -n "$STAGE_MD5" ] || fail "pas de KERNEL.CGO stage"
[ "$STAGE_MD5" != "$NEW_ORACLE_MD5" ] || fail "le stage EGALE encore l'oracle x86 — refus de livrer un SIGILL"
n=$(ls out/jak1-arm64-full/iso/*.CGO out/jak1-arm64-full/iso/*.DGO 2>/dev/null | wc -l)
say "fichiers stages : $n (28 attendus)"
[ "$n" -eq 28 ] || fail "jeu arm64 incomplet ($n/28)"

# ------------------------------------------------------------------- 2. APK
say "gradle :app:clean assembleJak1Debug"
if ! ( cd android && timeout 3000 ./gradlew :app:clean assembleJak1Debug >> "../$LOG" 2>&1 ); then
  say "--- 40 dernieres lignes ---"; tail -40 "$LOG"; fail "gradle echoue"
fi
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
[ -f "$APK" ] || fail "pas d'APK"
say "APK: $(stat -c%s "$APK") octets"

# --------------------------------------------------------- 3. preuve appareil
say "mm_device_proof.sh all"
bash .autoport/mm_device_proof.sh all >> "$LOG" 2>&1
rc=$?
say "mm_device_proof rc=$rc"
say "=== FIN round2b ==="
exit $rc
