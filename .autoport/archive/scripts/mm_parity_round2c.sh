#!/usr/bin/env bash
# mm_parity_round2c.sh — reprise apres diagnostic du SIGSEGV de goalc arm64.
#
# LA CAUSE, ETABLIE (pas supposee) :
#   backtrace : Level::serialize -> TfragTree::serialize -> from_pod_vector<u16>(&baked_tangents)
#               -> Serializer::read_or_write(size=10163781085027882753) -> memmove -> SIGSEGV
#   le « pointeur » du vecteur vaut 0x73656e6867756f72, soit les octets ASCII « roughnes » —
#   du TEXTE glTF pris pour un pointeur. Signature d'un decalage de champ, pas d'un mauvais calcul.
#   Et le decalage a une cause mecanique :
#       build-arm64/common/libcommon.so      31 aout 01:37   RECONSTRUIT (contient baked_tangents)
#       build-arm64/decompiler/libdecomp.so  26 aout 17:59   PERIME
#       build-arm64/goalc/goalc              26 aout 18:00   PERIME
#       build-arm64/goalc/libcompiler.so     26 aout 18:00   PERIME
#   or `baked_tangents` est entre dans common/custom_data/Tfrag3Data.h le 2026-08-27 04:47
#   (commit 4e221250a9). 930 objets sur 1002 de build-arm64 sont ANTERIEURS a ce changement.
#   libcompiler.so construit donc un tfrag3::Level a l'ANCIENNE disposition et le passe a
#   Level::serialize de libcommon.so, compile a la NOUVELLE : le champ lu n'est pas le bon.
#   goalc x86 (arbre build/, reconstruit le 28 aout) reussit sur LA MEME cible, 1323/1323 —
#   c'est ce qui prouve que la donnee d'entree est saine et que l'arbre est le fautif.
#
# RIEN DE TOUT CECI NE VIENT DE NOS COMPTEURS : goalc ne lie pas le renderer.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ulimit -c 0   # 3 core dumps de 350 Mo ont deja rempli le disque cette nuit

LOCK=.autoport/.deploy-in-progress
LOG=.autoport/logs/mm_parity_round2c.txt
mkdir -p .autoport/logs
: > "$LOG"
say(){ echo "$(date +%H:%M:%S) $*" | tee -a "$LOG"; }
fail(){ say "[round2c FAIL] $*"; exit 1; }

if [ -f "$LOCK" ]; then
  holder=$(awk '{for(i=1;i<=NF;i++) if($i ~ /^pid=/){sub(/^pid=/,"",$i); print $i}}' "$LOCK" | head -1)
  if [ -n "${holder:-}" ] && kill -0 "$holder" 2>/dev/null; then
    fail "verrou tenu par un PID VIVANT ($holder)"
  fi
  say "verrou perime (detenteur '${holder:-vide}' mort) — remplace"
fi
printf 'mm-parity-round2c pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
say "verrou pris (pid=$$)  HEAD=$(git rev-parse --short HEAD)"

# ------------------------------------ 1. reparer l'arbre goalc arm64 (INCREMENTAL)
# On ne reconfigure PAS : `cmake -B build-arm64` invaliderait les 1002 objets d'un coup.
# La cible `goalc` retire par dependance les 930 objets perimes et relie les trois .so.
say "cmake --build build-arm64 --target goalc (930/1002 objets perimes)"
if ! timeout 7200 cmake --build build-arm64 --target goalc -j"$(nproc)" >> "$LOG" 2>&1; then
  tail -40 "$LOG"; fail "reconstruction de build-arm64 echouee"
fi
say "build-arm64 goalc reconstruit"
say "  goalc      : $(date -r build-arm64/goalc/goalc '+%F %T')"
say "  libcompiler: $(date -r build-arm64/goalc/libcompiler.so '+%F %T')"
say "  libcommon  : $(date -r build-arm64/common/libcommon.so '+%F %T')"
say "  libdecomp  : $(date -r build-arm64/decompiler/libdecomp.so '+%F %T')"
n=$(find build-arm64 -name '*.o' -not -newermt "2026-08-27 04:47" 2>/dev/null | wc -l)
say "  objets encore anterieurs au changement d'en-tete : $n (0 attendu)"

# ---------------------------------------------- 2. jeu de donnees arm64 coherent
say "build_arm64_full_consistent.sh"
if ! timeout 5400 bash .autoport/build_arm64_full_consistent.sh >> "$LOG" 2>&1; then
  say "--- 30 dernieres lignes du log goalc arm64 ---"
  tail -30 .autoport/logs/full-arm64-mi.log 2>/dev/null | tee -a "$LOG"
  fail "build arm64 coherent echoue"
fi
say "build arm64 coherent OK"

STAGE_MD5=$(md5sum out/jak1-arm64-full/iso/KERNEL.CGO 2>/dev/null | cut -d' ' -f1)
ORACLE_MD5=$(md5sum out/jak1/iso/KERNEL.CGO 2>/dev/null | cut -d' ' -f1)
say "md5 stage  : $STAGE_MD5"
say "md5 oracle : $ORACLE_MD5"
[ -n "$STAGE_MD5" ] || fail "pas de KERNEL.CGO stage"
[ "$STAGE_MD5" != "$ORACLE_MD5" ] || fail "le stage EGALE l'oracle x86 — refus de livrer un SIGILL"
n=$(ls out/jak1-arm64-full/iso/*.CGO out/jak1-arm64-full/iso/*.DGO 2>/dev/null | wc -l)
say "fichiers stages : $n (28 attendus)"
[ "$n" -eq 28 ] || fail "jeu arm64 incomplet ($n/28)"

# ------------------------------------------------------------------- 3. APK
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
say "=== FIN round2c ==="
exit $rc
