#!/usr/bin/env bash
# mm_parity_round2.sh — Grecharged-materials-modern-parity, round 2.
#
# Enchaine, SOUS VERROU, la seule sequence qui donne une preuve de provenance honnete :
#   commit -> build arm64 incremental -> APK propre -> preuve d'appareil.
#
# POURQUOI LE COMMIT EST *AVANT* LA COURSE. La preuve de la tentative 1 portait
# `HEAD: ecdf64b118`, un commit qui ne contient PAS UNE LIGNE du code teste (la course a
# tourne sur un arbre non commite, fige 4 h plus tard dans b21c4ae750). L'en-tete de
# provenance designait donc un commit etranger au sujet de la preuve. On commite d'abord.
#
# POURQUOI LE VERROU. `.autoport/auto_build_apk.sh` tourne en permanence et rebatit sur tout
# nouveau commit ; il ecrirait out/jak1/iso/ et reinstallerait un APK PENDANT la course. Il
# honore `.autoport/.deploy-in-progress` a condition que le detenteur soit VIVANT (garde
# `kill -0` ajoutee le 2026-08-31 01:05). Le verrou est donc pose avec le PID DE CE SCRIPT,
# jamais avec le `$$` d'un appel d'outil — celui-la sort dans la seconde et nomme un mort.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

LOCK=.autoport/.deploy-in-progress
LOG=.autoport/logs/mm_parity_round2.txt
mkdir -p .autoport/logs
: > "$LOG"
say(){ echo "$(date +%H:%M:%S) $*" | tee -a "$LOG"; }
fail(){ say "[round2 FAIL] $*"; exit 1; }

if [ -f "$LOCK" ]; then
  holder=$(awk '{for(i=1;i<=NF;i++) if($i ~ /^pid=/){sub(/^pid=/,"",$i); print $i}}' "$LOCK" | head -1)
  if [ -n "${holder:-}" ] && kill -0 "$holder" 2>/dev/null; then
    fail "verrou deja tenu par un PID VIVANT ($holder) — on n'efface JAMAIS un verrou a la main"
  fi
  say "verrou perime (detenteur '${holder:-vide}' mort) — on le remplace"
fi
printf 'mm-parity-round2 pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
say "verrou pris (pid=$$)"

# ---------------------------------------------------------------- 1. commit
if ! git diff --quiet || ! git diff --cached --quiet; then
  git add -A game/graphics/opengl_renderer/loader/CustomTextureReplacements.cpp \
             game/graphics/opengl_renderer/loader/CustomTextureReplacements.h \
             game/graphics/opengl_renderer/background/background_common.cpp \
             game/kernel/jak1/kmachine.cpp \
             .autoport/mm_device_proof.sh .autoport/mm_parity_round2.sh \
             .autoport/mm_parity_round2.msg 2>&1 | tee -a "$LOG"
  git commit -q -F .autoport/mm_parity_round2.msg 2>&1 | tee -a "$LOG" || say "rien a commiter"
fi
say "HEAD = $(git rev-parse --short HEAD)"

# ------------------------------------------------- 2. build arm64 INCREMENTAL
# INTERDIT de reconfigurer (`cmake -B build-android`) : cela invalide 1300+ objets, dont les
# mips2c de jak2 qu'on ne touche pas. Cible unique.
say "cmake --build build-android --target gk (incremental)"
if ! timeout 3600 cmake --build build-android --target gk -j"$(nproc)" >> "$LOG" 2>&1; then
  tail -40 "$LOG"; fail "build arm64 gk echoue"
fi
say "gk arm64 OK"

# CONTROLE D'ARTEFACT, pas de source : le .so LIVRE doit porter le nouveau texte. Sur ce projet
# une TU sous drapeau de fonctionnalite a deja avale du code neuf sans que personne ne le voie,
# et la preuve avait ete prise sur build-x86 ou le drapeau est ON.
for s in mm_note_bind "PBR BINDS" "STATE-PUSHES" "WITHOUT bit8"; do
  n=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -cF "$s" || true)
  say "  arm64 libgk carries '$s' : $n"
  [ "${n:-0}" -ge 1 ] || fail "le libgk arm64 NE porte PAS '$s' — le code neuf n'a pas atteint l'artefact livre"
done

# ------------------------------------------------------------------- 3. APK
# `:app:clean` avant l'assemble : un assemble incremental repete gonfle l'APK par espace mort
# (588 Mo -> 1019 Mo constate le 2026-08-11), et l'owner telecharge cet APK.
say "gradle :app:clean assembleJak1Debug"
if ! ( cd android && timeout 3000 ./gradlew :app:clean assembleJak1Debug >> "../$LOG" 2>&1 ); then
  tail -40 "$LOG"; fail "gradle echoue"
fi
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
[ -f "$APK" ] || fail "pas d'APK"
say "APK: $(stat -c%s "$APK") octets"

# --------------------------------------------------------- 4. preuve appareil
say "mm_device_proof.sh all"
bash .autoport/mm_device_proof.sh all >> "$LOG" 2>&1
rc=$?
say "mm_device_proof rc=$rc"
say "=== FIN round2 ==="
exit $rc
