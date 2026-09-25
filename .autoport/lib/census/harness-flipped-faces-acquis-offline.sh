#!/usr/bin/env bash
# census/harness-flipped-faces-acquis-offline.sh — LE GARDE-FOU DES FACES A L'ENVERS RELIT LES ASSETS
# HORS LIGNE, ET LE MOTEUR NE PORTE PLUS D'INSTRUMENTATION DE CE SUJET.
#
# flipped_acquis_leftovers = somme des defauts suivants (doit valoir 0) :
#   flipped_acquis_absent            acquis/flipped-faces.sh n'existe pas
#   flipped_acquis_runs_game         lignes de l'acquis qui lancent/lisent le jeu (acq_x86_log, gk, OG_FLIP)
#   flipped_acquis_real_not_held     l'acquis, cache VIDE, ne rend pas « TENU » sur l'etat livre
#   flipped_acquis_negctl_not_held   CONTROLE NEGATIF : village3 seul, pack livre -> doit etre TENU
#   flipped_acquis_posctl_asset_missed  CONTROLE POSITIF : pack livre SANS village3.meshweld -> doit etre PLUS TENU
#   flipped_acquis_posctl_shader_missed CONTROLE POSITIF : shaders d'avant (8ac0afe896) -> doit etre PLUS TENU
#   flipped_engine_leftover_lines    references moteur a flip_census / floor_probe / OG_FLIP_* / u_floor_probe
#   flipped_engine_leftover_files    flip_census.{cpp,h} / floor_probe.{cpp,h} encore presents
#   flipped_cache_data_blind         acq_x86_log ne relance PAS la course apres un changement de donnees
#   flipped_cache_rerun_same_data    acq_x86_log relance la course alors que rien n'a change (cache mort)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
ROOT=$PWD
export TMPDIR="${TMPDIR:-$HOME/.autoport-tmp}"
mkdir -p "$TMPDIR" || exit 1
T=$(mktemp -d "$TMPDIR/flip-acq.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
die(){ printf 'census harness-flipped-faces-acquis-offline: %s\n' "$*" >&2; exit 1; }
ACQ=.autoport/acquis/flipped-faces.sh
PACK=android/app/src/jak1/assets-slim/bundle/jak1_custom.zip
CTL_LEVEL=village3

# --- 1. l'acquis existe et ne lance pas le jeu
ABSENT=0; RUNS=0
if [ -f "$ACQ" ]; then
  RUNS=$(grep -vE '^\s*#' "$ACQ" | grep -cE 'acq_x86_log|ACQ_GK|build/game/gk|OG_FLIP' || true)
else
  ABSENT=1
fi

# run_acq <nom> [VAR=VAL ...] : lance l'acquis avec un cache NEUF (la mesure est refaite), publie rc + verdict
run_acq(){
  local n="$1"; shift
  mkdir -p "$T/cache-$n"
  env ACQ_CACHE="$T/cache-$n" "$@" bash "$ACQ" > "$T/$n.out" 2>&1
  local rc=$?
  local verdict=autre
  grep -q 'PLUS TENU' "$T/$n.out" && verdict=plus_tenu
  grep -q '\] TENU :' "$T/$n.out" && verdict=tenu
  grep -q 'ACQUIS UNPROVABLE' "$T/$n.out" && verdict=unprovable
  printf '%s %s\n' "$rc" "$verdict"
  printf 'flipped_acquis_%s_rc=%s\nflipped_acquis_%s_verdict=%s\n' "$n" "$rc" "$n" "$verdict" >> "$T/keys"
  tail -1 "$T/$n.out" | tr ' ' '_' | cut -c1-400 | sed "s/^/flipped_acquis_${n}_line=/" >> "$T/keys"
}
: > "$T/keys"
REAL_BAD=1; NEG_BAD=1; POSA_BAD=1; POSS_BAD=1
if [ "$ABSENT" = 0 ]; then
  [ "$(run_acq real)" = "0 tenu" ] && REAL_BAD=0
  [ "$(run_acq negctl FLIP_LEVEL=$CTL_LEVEL)" = "0 tenu" ] && NEG_BAD=0
  # controle positif ASSET : le pack livre moins le compagnon du niveau de controle
  python3 - "$PACK" "$T/pack-sans.zip" "fr3/$CTL_LEVEL.meshweld" <<'PY' || die "copie du pack impossible"
import sys, zipfile
src, dst, drop = sys.argv[1:4]
n = 0
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(dst, 'w', zipfile.ZIP_STORED) as zo:
    for m in zi.infolist():
        if m.filename == drop:
            n += 1
            continue
        zo.writestr(m, zi.read(m.filename))
sys.exit(0 if n == 1 else 3)
PY
  # TOUS les niveaux : sur le seul niveau prive de compagnon, --check-orient ne relit aucun triangle
  # (le recensement s'arrete « rien relu », essai 1) — ce serait tester l'instrument, pas le verdict.
  [ "$(run_acq posctl_asset FLIP_PACK="$T/pack-sans.zip")" = "1 plus_tenu" ] && POSA_BAD=0
  # controle positif SHADER : les shaders du depot, trois d'entre eux remis a l'etat de 8ac0afe896
  cp -r game/graphics/opengl_renderer/shaders "$T/shaders-avant" || die "copie des shaders"
  for f in shade.glsl merc2.frag merc2.vert; do
    git show "8ac0afe896:game/graphics/opengl_renderer/shaders/$f" > "$T/shaders-avant/$f" || die "8ac0afe896:$f"
  done
  [ "$(run_acq posctl_shader FLIP_LEVEL=$CTL_LEVEL FLIP_SHADERS="$T/shaders-avant")" = "1 plus_tenu" ] && POSS_BAD=0
fi

# --- 2. le moteur ne porte plus l'instrumentation
PAT='\bflip_census\b|floor_probe\.h|\bfloor_probe::|OG_FLIP_PROBE|OG_FLIP_TOUR|u_floor_probe|floor_probe_out'
grep -rnE "$PAT" game common goalc android/CMakeLists.txt game/CMakeLists.txt > "$T/engine.txt" 2>/dev/null || true
ENG_LINES=$(grep -c . "$T/engine.txt" || true)
ENG_FILES=0
for f in flip_census.cpp flip_census.h floor_probe.cpp floor_probe.h; do
  [ -e "game/graphics/opengl_renderer/$f" ] && ENG_FILES=$((ENG_FILES + 1))
done
# temoin : le motif retrouve l'instrumentation dans l'arbre d'avant l'item (sinon il est aveugle)
ENG_CTRL=$(git grep -cE "$PAT" 29094b8130 -- game/graphics/opengl_renderer/background/TFragment.cpp 2>/dev/null \
  | awk -F: '{s+=$NF} END{print s+0}')
[ "${ENG_CTRL:-0}" -gt 0 ] || die "temoin aveugle : le motif moteur ne voit rien dans TFragment.cpp a 29094b8130"

# --- 3. cache des gardes x86 : un faux gk qui compte ses lancements, des donnees jetables
mkdir -p "$T/data" "$T/xcache"
printf 'a\n' > "$T/data/level.meshweld"
cat > "$T/fakegk" <<EOF
#!/usr/bin/env bash
echo run >> "$T/fakegk.count"; echo "FAKE-GK \$*"
EOF
chmod +x "$T/fakegk"
cachetest(){
  ACQ_GK="$T/fakegk" ACQ_CACHE="$T/xcache" ACQ_DATA_DIRS="$T/data" bash -c '
    . .autoport/acquis/_lib.sh
    acq_build_busy(){ return 1; }   # banc : on juge le cache, pas la garde anti-build
    acq_x86_log cachetest 20 X=1 >/dev/null'
  grep -c . "$T/fakegk.count" 2>/dev/null || echo 0
}
C1=$(cachetest); C2=$(cachetest)
printf 'b\n' > "$T/data/level.meshweld"      # une « recuisson » : memes noms, autres octets
C3=$(cachetest)
RERUN=$([ "$C1" = 1 ] && [ "$C2" = 1 ] && echo 0 || echo 1)
BLIND=$([ "$C3" = 2 ] && echo 0 || echo 1)

LEFT=$((ABSENT + RUNS + REAL_BAD + NEG_BAD + POSA_BAD + POSS_BAD + ENG_LINES + ENG_FILES + BLIND + RERUN))
cat "$T/keys"
cat <<EOF
flipped_acquis_absent=$ABSENT
flipped_acquis_runs_game=$RUNS
flipped_acquis_real_not_held=$REAL_BAD
flipped_acquis_negctl_not_held=$NEG_BAD
flipped_acquis_posctl_asset_missed=$POSA_BAD
flipped_acquis_posctl_shader_missed=$POSS_BAD
flipped_engine_leftover_lines=$ENG_LINES
flipped_engine_leftover_files=$ENG_FILES
flipped_engine_pattern_control_hits=$ENG_CTRL
flipped_cache_runs_first_second_after_rebake=$C1,$C2,$C3
flipped_cache_rerun_same_data=$RERUN
flipped_cache_data_blind=$BLIND
flipped_acquis_leftovers=$LEFT
EOF
