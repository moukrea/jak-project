#!/usr/bin/env bash
# Gcutscene-npc-flicker — CAMPAGNE x86 : le recensement des PNJ sur des cinematiques REELLES,
# avec l'ablation des modeles HD SUR LE MEME BINAIRE (seul `recharged-enhanced-models?` change).
#
# Les scenes sont atteintes sans joueur humain : quatre continue-points de jak1 portent un
# `continue-flags` qui DECLENCHE une cinematique tout seul (engine/target/target-death.gc:230-271),
# et le hook `OG_LEVEL_WARP` (kmachine.cpp:5312) fait exactement
# `(start 'play (get-continue-by-name *game-info* "<nom>"))`.
#
# VERROU DE LIVRAISON : ce script REECRIT out/jak1/iso en objets x86. Le constructeur automatique
# y ecrit de l'arm64 des qu'une source change (memoire : « un commit declenche un cycle [full] qui
# met out/jak1/iso en ARM64 »). Il pose donc `.deploy-in-progress` avec SON PID et un trap, comme
# l'exige DIRECTIVES 2026-08-14 07:10 — le PID d'un shell d'appel d'outil serait mort dans la
# seconde.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

OUT=.autoport/reports/Gcutscene-npc-flicker; mkdir -p "$OUT"
R="$OUT/x86_campagne.txt"
GK=build/game/gk; ISO=out/jak1/iso
INI=build/game/OpenGOAL/jak1/settings/settings.ini
SCENES="${SCENES:-intro-start village1-intro village1-warp village1-demo-convo}"
WATCH="${WATCH:-150}"
LEGS="${LEGS:-hd0 hd1}"
SKIP_BUILD="${SKIP_BUILD:-0}"

export DISPLAY="${DISPLAY:-:0}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

say(){ echo "$*" | tee -a "$R"; }
: > "$R"
say "===== campagne x86 recensement PNJ — $(date -Is) ====="
say "scenes: $SCENES"
say "jambes: $LEGS   watch=${WATCH}s"

LOCK=.autoport/.deploy-in-progress
# NPCF_LOCK_HELD=1 : l'appelant tient DEJA le verrou pour toute la duree de sa campagne. Sans ca,
# chaque invocation le poserait et le retirerait, et la fenetre entre deux invocations laisserait
# le constructeur automatique refaire out/jak1/iso en ARM64 sous nos pieds.
if [ "${NPCF_LOCK_HELD:-0}" = "1" ]; then
  say "verrou de livraison tenu par l'appelant ($(cat "$LOCK" 2>/dev/null))"
elif [ -f "$LOCK" ]; then
  H=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$LOCK" | head -1)
  if [ -n "$H" ] && kill -0 "$H" 2>/dev/null; then
    say "FAIL: livraison en cours (pid=$H) — on ne construit pas par-dessus"; exit 1
  fi
  say "verrou orphelin ($(cat "$LOCK")) — le detenteur est mort, on continue"
fi
if [ "${NPCF_LOCK_HELD:-0}" = "1" ]; then
  trap '[ -f "$OUT/.ini.pre" ] && cp "$OUT/.ini.pre" "$INI"' EXIT
else
  printf 'npcf_x86_campagne pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
  trap 'rm -f "$LOCK"; [ -f "$OUT/.ini.pre" ] && cp "$OUT/.ini.pre" "$INI"' EXIT
fi

cp "$INI" "$OUT/.ini.pre"

# --- objets GOAL x86 -----------------------------------------------------------------------------
if [ "$SKIP_BUILD" != 1 ]; then
  say "-- (make-group \"iso\") en x86 (out/jak1/iso porte peut-etre de l'arm64)"
  if ! timeout 1800 ./build/goalc/goalc --user-auto --cmd '(make-group "iso")' > "$OUT/goal_build.log" 2>&1; then
    say "FAIL: compilation GOAL"; tail -30 "$OUT/goal_build.log" | tee -a "$R"; exit 1
  fi
  say "   GOAL x86 OK ($(grep -ac . "$OUT/goal_build.log") lignes)"
fi

# --- art-groups HD (le pack externe ne voyage pas dans le depot) ---------------------------------
mkdir -p out/jak1/obj
for c in jak dax keira samos; do
  cp -f "recharged_assets/hd_anim/$c-hd-ag.go" out/jak1/obj/ 2>/dev/null || say "   (pas de $c-hd-ag.go)"
done

set_ini(){ # cle valeur
  if grep -q "^$1 = " "$INI"; then sed -i "s|^$1 = .*|$1 = $2|" "$INI"
  else printf '%s = %s\n' "$1" "$2" >> "$INI"; fi
}

run_one(){ # $1 leg  $2 scene
  local leg="$1" scene="$2"
  local log="$OUT/gk-$leg-$scene.log"; : > "$log"
  OG_LEVEL_WARP="$scene" "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
      -iso-data "$ISO" -- -boot -debug-mem > "$log" 2>&1 &
  local pid=$!
  local booted=0
  for i in $(seq 1 180); do
    kill -0 "$pid" 2>/dev/null || break
    grep -aq 'LEVEL-WARP.*start .play' "$log" && { booted=1; break; }
    sleep 1
  done
  if [ "$booted" = 1 ]; then
    say "   [$leg/$scene] warp parti — observation ${WATCH}s"
    sleep "$WATCH"
  else
    say "   [$leg/$scene] AUCUN warp (gk mort ou delai) — on publie quand meme ce qui est sorti"
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  local nsc npf ncy nev
  nsc=$(grep -ac '^NPCSCENE ' "$log" || true)
  npf=$(grep -ac '^NPCFLICK ' "$log" || true)
  nev=$(grep -ac '^NPCFLICK-EV ' "$log" || true)
  ncy=$(grep -a '^NPCFLICK ' "$log" | sed -n 's/.*cycles=\([0-9]*\).*/\1/p' | paste -sd+ | bc 2>/dev/null)
  say "   [$leg/$scene] NPCSCENE=$nsc NPCFLICK=$npf evenements=$nev cycles=${ncy:-0}"
  grep -a '^NPCSCENE \|^NPCFLICK ' "$log" >> "$R" || true
}

for leg in $LEGS; do
  case "$leg" in
    hd1) set_ini 'recharged-enhanced-models?' '#t'; set_ini 'recharged-master?' '#t'
         set_ini 'hd-look-jak' '1'; set_ini 'hd-look-daxter' '1'
         set_ini 'hd-look-keira' '1'; set_ini 'hd-look-samos' '1'
         say "-- JAMBE hd1 : modeles HD ACTIFS" ;;
    hd0) set_ini 'recharged-enhanced-models?' '#f'
         say "-- JAMBE hd0 : modeles HD ETEINTS (ablation, meme binaire)" ;;
  esac
  for sc in $SCENES; do run_one "$leg" "$sc"; done
done

say "===== fin — $(date -Is) ====="
