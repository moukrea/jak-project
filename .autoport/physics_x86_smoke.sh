#!/usr/bin/env bash
# physics_x86_smoke.sh — Grecharged-secondary-motion x86-FIRST smoke (state-dumps-x86-first rule).
#
# Four legs against the same fresh --hd-models --pbr --physics build, driven ONLY by the settings
# the menu writes (physics? / physics-quality in settings.ini):
#   LEG L2  "max":     physics?=#t quality=2, primary looks    -> [HD-PHYS] init chains>0 on the
#                      spawned companions, window state dumps with nan-resets=0, bounded maxdev.
#   LEG L0  "light":   physics?=#t quality=0, primary looks    -> same bar at the light level.
#   LEG BONUS "looks": physics?=#t quality=1, bonus looks 2222 -> per-look params resolve (init
#                      lines for jak2-hd/daxp-hd/keira3-hd/ysamos-hd with chains>0).
#   LEG OFF "off":     physics?=#f                             -> ZERO [HD-PHYS] window lines
#                      (full in-game disable; init lines alone are allowed = resolution only).
# PASS bar per leg: boot OK, params-loaded line names >=8 models, the leg's [HD-PHYS] expectations,
# no crash markers, gk alive WATCH seconds. nan-resets MUST be 0 everywhere.
# Physical artifact gate up front: the built GAME.CGO must CONTAIN the [HD-PHYS] format strings
# (check the artifact, never the run — feedback_make_recurrence_impossible).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-secondary-motion; mkdir -p "$OUT"
R="$OUT/x86_smoke.txt"; : > "$R"
WATCH="${WATCH:-150}"
INI=build/game/OpenGOAL/jak1/settings/settings.ini
say(){ echo "$*" | tee -a "$R"; }

# ---- staleness + artifact gates ----------------------------------------------------------------
[ -f "$ISO/GAME.CGO" ] || { say "FAIL: no $ISO/GAME.CGO"; exit 1; }
[ "$ISO/GAME.CGO" -nt goal_src/jak1/pc/jak-hd-physics.gc ] || { say "FAIL: GAME.CGO stale vs jak-hd-physics.gc"; exit 1; }
[ "$ISO/GAME.CGO" -nt goal_src/jak1/pc/pckernel-impl.gc ] || { say "FAIL: GAME.CGO stale vs pckernel-impl.gc"; exit 1; }
[ -f recharged_assets/physics_chains.txt ] || { say "FAIL: no recharged_assets/physics_chains.txt"; exit 1; }
# physical artifact: the CGO carries the sim's format strings and the settings carry the flag
STR=$(strings -a "$ISO/GAME.CGO" | grep -c 'HD-PHYS' || true)
[ "$STR" -ge 3 ] || { say "FAIL: GAME.CGO carries $STR HD-PHYS strings (<3) — physics not compiled in"; exit 1; }
say "artifact gate: GAME.CGO carries $STR [HD-PHYS] format strings"
# the binary must expose the FFI (verify_binary_flags equivalent, local)
# grep -c (never -q) so the pipe is fully consumed under pipefail (SIGPIPE-141 trap)
FFI=$(strings -a build/game/gk | grep -c 'pc-physics-joint-role' || true)
if [ "${FFI:-0}" -lt 1 ]; then
  say "FAIL: gk binary lacks pc-physics-joint-role — OG_FEAT_PHYSICS not built"; exit 1; fi
say "artifact gate: gk exposes the pc-physics FFI"
ENH=out/jak1/fr3/enhanced/GAME.fr3
[ -f "$ENH" ] || { say "FAIL: no enhanced GAME.fr3 — bake first"; exit 1; }

# ---- CYCLE-2 artifact gates (check the ARTIFACT, never the run) --------------------------------
# Every cycle-2 fix must be physically present in the shipped objects before a single frame runs.
for s in 'PHYS-MENU' 'rootdev=' 'resid=' 'desc=' 'reglue='; do
  n=$(strings -a "$ISO/GAME.CGO" | grep -c -- "$s" || true)
  [ "${n:-0}" -ge 1 ] || { say "FAIL: GAME.CGO carries no '$s' string — cycle-2 code not compiled in"; exit 1; }
done
say "artifact gate: GAME.CGO carries the cycle-2 instrument strings (PHYS-MENU/rootdev/resid/desc/reglue)"
FFI2=$(strings -a build/game/gk | grep -c 'pc-physics-collider-is-joint2' || true)
[ "${FFI2:-0}" -ge 1 ] || { say "FAIL: gk lacks pc-physics-collider-is-joint2 — capsule FFI not built"; exit 1; }
say "artifact gate: gk exposes the capsule collider FFI"
NCAP=$(grep -c '^capsule ' recharged_assets/physics_chains.txt || true)
[ "${NCAP:-0}" -ge 20 ] || { say "FAIL: only ${NCAP:-0} capsule colliders declared — the body volume is still symbolic"; exit 1; }
NRL=$(grep -c 'rootlock=' recharged_assets/physics_chains.txt || true)
[ "${NRL:-0}" -ge 8 ] || { say "FAIL: only ${NRL:-0} chains declare rootlock= — hair roots still float"; exit 1; }
say "artifact gate: physics_chains.txt declares $NCAP capsules and $NRL root-locked chains"

# ---- WAVE 2 artifact gates: physics on the whole STOCK cast ------------------------------------
# The stock-cast chains are declared by JOINT NAME against rigs we do not author. A mistyped name
# does not crash — the chain resolves to nothing and that character silently has no physics, in a
# level this smoke may never visit. So the names are checked against the SHIPPED RIGS themselves,
# offline, for all of them at once (see .autoport/physics_chains_lint.py).
python3 .autoport/physics_chains_lint.py | tee -a "$R"
[ "${PIPESTATUS[0]}" = 0 ] || { say "FAIL: physics_chains.txt names joints that the shipped rigs do not have"; exit 1; }
NSTOCK=$(grep -c '^\[model .*-lod0' recharged_assets/physics_chains.txt || true)
[ "${NSTOCK:-0}" -ge 20 ] || { say "FAIL: only ${NSTOCK:-0} stock rig sections — the cast-wide wave is not in the data"; exit 1; }
say "artifact gate: $NSTOCK stock rig sections declared (wave-2 cast)"
for s in 'HD-PHYS-RIDER' 'rider='; do
  n=$(strings -a "$ISO/GAME.CGO" | grep -c -- "$s" || true)
  [ "${n:-0}" -ge 1 ] || { say "FAIL: GAME.CGO carries no '$s' string — the wave-2 rider is not compiled in"; exit 1; }
done
say "artifact gate: GAME.CGO carries the wave-2 rider instrument strings"
FFI3=$(strings -a build/game/gk | grep -c 'pc-physics-generation' || true)
[ "${FFI3:-0}" -ge 1 ] || { say "FAIL: gk lacks pc-physics-generation — the hot-reload FFI is not built"; exit 1; }
say "artifact gate: gk exposes the params-generation FFI (hot reload)"

# chain NAME -> index within its model, read from the data file (never a hardcoded index: the gates
# must survive any reordering of the chains file).
chain_idx(){ # chain_idx <model> <chainname>
  awk -v m="$1" -v c="$2" '
    /^\[model /  { cur=$2; sub(/\]$/,"",cur); i=-1; next }
    /^chain /    { if (cur==m) { i++; if ($2==c) { print i; exit } } }
  ' recharged_assets/physics_chains.txt
}
# how many chains of a model carry a given class — so the "is this chain live at this level?" gate
# is derived from the data, not from a number typed into the script.
class_count(){ # class_count <model> <primary|secondary|accessory>
  awk -v m="$1" -v k="class=$2" '
    /^\[model / { cur=$2; sub(/\]$/,"",cur); next }
    /^chain /   { if (cur==m) for (i=3; i<=NF; i++) if ($i==k) n++ }
    END { print n+0 }' recharged_assets/physics_chains.txt
}
KCP=$(class_count keira-hd primary); KCS=$(class_count keira-hd secondary); KCA=$(class_count keira-hd accessory)
say "keira-hd class census: primary=$KCP secondary=$KCS accessory=$KCA"
KIDX_CHESTR=$(chain_idx keira-hd chestR); KIDX_GOG=$(chain_idx keira-hd goggles)
KIDX_HAIR=$(chain_idx keira-hd backhair)
[ -n "$KIDX_CHESTR" ] && [ -n "$KIDX_GOG" ] && [ -n "$KIDX_HAIR" ] \
  || { say "FAIL: could not resolve keira-hd chain indices from physics_chains.txt"; exit 1; }
say "keira-hd chain indices: chestR=$KIDX_CHESTR backhair=$KIDX_HAIR goggles=$KIDX_GOG"

# ---- stage the 10 HD art-groups ---------------------------------------------------------------
mkdir -p out/jak1/obj
for c in jak-hd dax-hd keira-hd samos-hd jak2-hd jak3-hd daxp-hd keira3-hd ysamos-hd jakm-hd; do
  cp -f "recharged_assets/hd_anim/$c-ag.go" out/jak1/obj/ || { say "FAIL: stage $c-ag.go"; exit 1; }
done
say "staged 10 HD art-groups into out/jak1/obj"

# ---- settings.ini (same trap rules as hd5: never append at EOF) --------------------------------
[ -f "$INI" ] || { say "FAIL: no $INI (run gk once to create it)"; exit 1; }
cp "$INI" "$OUT/.settings.ini.pre-smoke"
set_ini(){
  if grep -q "^$1 " "$INI"; then sed -i "s|^$1 .*|$1 = $2|" "$INI"
  else sed -i "/^recharged-enhanced-models? = /a $1 = $2" "$INI"
       grep -q "^$1 = $2$" "$INI" || { say "FAIL: could not insert $1"; exit 1; }
  fi
}
restore_ini(){ [ -f "$OUT/.settings.ini.pre-smoke" ] && cp "$OUT/.settings.ini.pre-smoke" "$INI" || true; }
grep -q '^version = #x' "$INI" || { say "FAIL: settings.ini has no version stamp"; exit 1; }
if grep -q '^recharged-master? = #f' "$INI"; then say "FAIL: recharged-master? #f would force STOCK"; exit 1; fi
set_ini 'recharged-enhanced-models?' '#t'

GKPID=0
cleanup(){ [ "${GKPID:-0}" -gt 0 ] && kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true; restore_ini; }
trap cleanup EXIT

run_leg(){ # run_leg <tag> <physics #t/#f> <quality> <lookJ> <lookD> <lookK> <lookS> <mode expect-phys|expect-off|expect-gameplay> [warp-level] [warp-pos]
  local TAG="$1" PHY="$2" QUAL="$3" LJ="$4" LD="$5" LK="$6" LS="$7" MODE="$8" WARP="${9:-}" WPOS="${10:-}"
  local GKLOG="$OUT/.smoke_gk_$TAG.log"; : > "$GKLOG"
  # expect-rider deliberately runs with ENHANCED MODELS OFF. That is not a weaker leg: it is the
  # only configuration in which the four main characters are NOT covered by an HD companion, so the
  # stock-actor rider is what has to give Jak / Daxter / Keira / Samos their secondary motion. It is
  # the owner's "physics on EVERY look, including the original ones", proven directly.
  local ENHSET='#t'; [ "$MODE" = expect-rider ] && ENHSET='#f'
  set_ini 'recharged-enhanced-models?' "$ENHSET"
  set_ini 'physics?' "$PHY"; set_ini 'physics-quality' "$QUAL"
  set_ini 'hd-look-jak' "$LJ"; set_ini 'hd-look-daxter' "$LD"
  set_ini 'hd-look-keira' "$LK"; set_ini 'hd-look-samos' "$LS"
  say ""
  say "=== LEG $TAG: physics?=$PHY quality=$QUAL looks $LJ$LD$LK$LS warp=${WARP:-none} ==="
  local envs=()
  [ -n "$WARP" ] && envs+=("OG_LEVEL_WARP=$WARP" "OG_LEVEL_WARP_POS=$WPOS")
  env "${envs[@]}" "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
  GKPID=$!
  local booted=0 i
  for i in $(seq 1 150); do
    kill -0 "$GKPID" 2>/dev/null || { say "FAIL($TAG): gk exited during boot"; tail -25 "$GKLOG" >> "$R"; return 1; }
    grep -aqE "link finish: (default-menu|logo)" "$GKLOG" && { booted=1; break; }
    sleep 1
  done
  [ "$booted" = 1 ] || { say "FAIL($TAG): boot timeout"; tail -25 "$GKLOG" >> "$R"; return 1; }
  if [ -n "$WARP" ]; then
    local w=0
    for i in $(seq 1 120); do
      kill -0 "$GKPID" 2>/dev/null || { say "FAIL($TAG): gk died pre-warp"; tail -25 "$GKLOG" >> "$R"; return 1; }
      grep -aq 'LEVEL-WARP-SPAWN' "$GKLOG" && { w=1; break; }
      sleep 1
    done
    [ "$w" = 1 ] || { say "FAIL($TAG): level warp never fired"; tail -25 "$GKLOG" >> "$R"; return 1; }
    say "warp landed ($WARP)"
  fi
  say "booted — watching ${WATCH}s"
  sleep "$WATCH"
  local ALIVE=no; kill -0 "$GKPID" 2>/dev/null && ALIVE=yes
  local OK=1
  if [ "$MODE" = expect-rider ]; then
    grep -aq 'HD-MODELS fr3-select GAME: ENHANCED' "$GKLOG" && { say "FAIL($TAG): GAME is ENHANCED but this leg needs the STOCK looks"; OK=0; }
  else
    grep -aq 'HD-MODELS fr3-select GAME: ENHANCED' "$GKLOG" || { say "FAIL($TAG): GAME not ENHANCED"; OK=0; }
  fi
  local CRASH; CRASH=$(grep -acE 'SIGSEGV|SIGILL|Segmentation|Assertion' "$GKLOG" || true)
  local NINIT NWIN NNAN NREST NLOAD
  NINIT=$(grep -ac '\[HD-PHYS\] init ag=' "$GKLOG" || true)
  NWIN=$(grep -ac '\[HD-PHYS\].*window: chains=' "$GKLOG" || true)
  # any window line with a nonzero nan-resets fails everything
  NNAN=$(grep -a 'nan-resets=' "$GKLOG" | grep -cv 'nan-resets=0 ' || true)
  NREST=$(grep -ac 'rest-converged' "$GKLOG" || true)
  NLOAD=$(grep -ac 'params loaded' "$GKLOG" || true)
  say "leg $TAG: alive=$ALIVE init=$NINIT windows=$NWIN nan-bad=$NNAN rest=$NREST params-loaded=$NLOAD crash=$CRASH"
  [ "$ALIVE" = yes ] || OK=0
  [ "$CRASH" = 0 ] || OK=0

  # ---- (E) MENU BINDING GATE — every leg, physics on or off -----------------------------------
  # The owner's regression: the PHYSICS DETAIL row opened the MESH BROWSER because the wiring
  # indexed the tail by hand and forgot a row. The rows are self-locating now; this proves it on
  # the artifact that actually shipped, and proves the mesh-browser button was left alone.
  if grep -aq '\[PHYS-MENU\] FATAL' "$GKLOG"; then
    say "FAIL($TAG): [PHYS-MENU] FATAL — physics rows not found / mis-ordered"; OK=0
  fi
  NMENU=$(grep -ac '\[PHYS-MENU\].*next-is-meshbrowser=1' "$GKLOG" || true)
  if [ "${NMENU:-0}" -lt 1 ]; then
    say "FAIL($TAG): no '[PHYS-MENU] rows wired ... next-is-meshbrowser=1' line — the DETAIL row is not provably distinct from the mesh browser"
    grep -a '\[PHYS-MENU\]' "$GKLOG" | head -3 >> "$R"; OK=0
  else
    say "leg $TAG: menu rows self-located, mesh-browser button intact ($NMENU line(s))"
  fi

  # ---- CYCLE-2 STRUCTURAL GATES (only meaningful when the sim ran) ------------------------------
  if [ "$NWIN" -gt 0 ]; then
    # (B) a LOCKED chain root must never drift: rootdev is read back FROM THE BONE after write-back.
    NROOT=$(grep -a 'rootdev=' "$GKLOG" | grep -cv 'rootdev=0\.0000 ' || true)
    [ "${NROOT:-0}" = 0 ] || { say "FAIL($TAG): $NROOT window(s) with rootdev!=0 — a locked hair root moved"; OK=0; }
    # colliders: pushing out is not the bar — ENDING the frame outside the body is.
    NRES=$(grep -a 'resid=' "$GKLOG" | grep -cv 'resid=0 ' || true)
    [ "${NRES:-0}" = 0 ] || { say "FAIL($TAG): $NRES window(s) with residual penetrations — chains end frames inside the body"; OK=0; }
    # (A) the authored pseudo-wind is actually being replaced on at least one chain.
    NREG=$(grep -a 'reglue=' "$GKLOG" | awk '{if (match($0,/reglue=[0-9]+/) && substr($0,RSTART+7,RLENGTH-7)+0 > 0) n++} END {print n+0}')
    [ "${NREG:-0}" -ge 1 ] || { say "FAIL($TAG): no window reports reglue>0 — the fake-wind neutralization never ran"; OK=0; }
    # (D) the anti-tear pass: keira's goggle lenses are non-simulated children of a simulated joint.
    NDESC=$(grep -a 'ag=keira' "$GKLOG" | awk '{if (match($0,/desc=[0-9]+/) && substr($0,RSTART+5,RLENGTH-5)+0 > 0) n++} END {print n+0}')
    # Every chain whose class bit is live at this level MUST be in the active set. This is the gate
    # that would have caught defect D at level 1 (goggles were class=accessory, classmask=3, so the
    # chain silently "rode rigidly" and the owner saw no physics on the glasses).
    KBAD=$(grep -a 'ag=keira-hd .*window:' "$GKLOG" | awk -v p="$KCP" -v s="$KCS" -v a="$KCA" '
      { cm=0; act=0;
        if (match($0,/cm=[0-9]+/))  cm=substr($0,RSTART+3,RLENGTH-3)+0;
        if (match($0,/act=[0-9]+/)) act=substr($0,RSTART+4,RLENGTH-4)+0;
        e=0; if (cm%2>=1) e+=p; if (int(cm/2)%2>=1) e+=s; if (int(cm/4)%2>=1) e+=a;
        if (act < e) { n++; print "  cm="cm" act="act" expected>="e > "/dev/stderr" } }
      END { print n+0 }' 2>>"$R")
    [ "${KBAD:-0}" = 0 ] || { say "FAIL($TAG): $KBAD keira window(s) where a class-live chain was NOT simulated"; OK=0; }
    say "leg $TAG: rootdev-bad=$NROOT resid-bad=$NRES reglue-windows=$NREG keira-desc-windows=${NDESC:-0} class-gate-bad=${KBAD:-0}"
  fi

  # ---- WAVE 2 GATES: the sim runs on STOCK actors, not just HD companions -----------------------
  # Everything above is shared with the companions (the rootdev/resid/nan greps scan ALL window
  # lines, riders included). These three are what makes wave 2 a fact rather than a claim.
  if [ "$MODE" = expect-gameplay ] || [ "$MODE" = expect-rider ]; then
    grep -a 'PARAMSRC=' "$GKLOG" | head -1 >> "$R"
    grep -aq 'PARAMSRC=' "$GKLOG" || { say "FAIL($TAG): no PARAMSRC= line — which params file the run read is unproven"; OK=0; }
    # a rider BOUND: an init line whose params key is a shipped rig (-lod0-jg, never one of our
    # -hd companion names), flagged rider=1, that resolved at least one chain.
    NRIDE=$(grep -a '\[HD-PHYS\] init ag=' "$GKLOG" | grep -a 'rider=1' | grep -ac 'ag=[a-z0-9-]*-lod0 ' || true)
    NRIDE0=$(grep -a '\[HD-PHYS\] init ag=' "$GKLOG" | grep -a 'rider=1' | grep -a 'ag=[a-z0-9-]*-lod0 ' | grep -c 'chains=0 ' || true)
    RACT=$(grep -a '\[HD-PHYS-RIDER\] window:' "$GKLOG" | awk '{if (match($0,/active=[0-9]+/) && substr($0,RSTART+7,RLENGTH-7)+0 > 0) n++} END {print n+0}')
    RWIN=$(grep -ac 'ag=[a-z0-9-]*-lod0 .*window: chains=' "$GKLOG" || true)
    # The rig DISCOVERY log must exist in every leg: it is what distinguishes "this level holds no
    # configured character" from "the hook never ran". Its absence is always a code failure.
    NSEEN=$(grep -ac '\[HD-PHYS-RIDER\] rig ' "$GKLOG" || true)
    [ "${NSEEN:-0}" -ge 1 ] || { say "FAIL($TAG): no '[HD-PHYS-RIDER] rig' discovery line — the post-anim hook never ran on any stock actor"; OK=0; }
    if [ "$MODE" = expect-rider ]; then
      # Here the four mains ARE uncovered stock actors, so riders MUST bind, step and dump state.
      [ "${NRIDE:-0}" -ge 1 ] || { say "FAIL($TAG): no stock actor was bound as a physics rider — wave 2 never ran"; OK=0; }
      [ "$((NRIDE - NRIDE0))" -ge 1 ] || { say "FAIL($TAG): every rider resolved chains=0 — the stock rigs bound but simulate nothing"; OK=0; }
      [ "${RACT:-0}" -ge 1 ] || { say "FAIL($TAG): no [HD-PHYS-RIDER] window with active>0 — riders bound but never stepped"; OK=0; }
      [ "${RWIN:-0}" -ge 1 ] || { say "FAIL($TAG): no stock-rig [HD-PHYS] window state dump"; OK=0; }
    fi
    grep -a '\[HD-PHYS-RIDER\] rig ' "$GKLOG" | sort -u >> "$R"
    # DATA gate: in the level this leg actually visits, no declared chain may fail to resolve.
    # (The names are proven for the whole cast offline; this proves the HIERARCHY assumptions —
    # single path, no branch, real anchor — for the rigs that really spawned.)
    NBADC=$(grep -a '\[HD-PHYS\] ag=' "$GKLOG" | grep -cE 'chain [0-9]+ (invalid|DROPPED)' || true)
    [ "${NBADC:-0}" = 0 ] || {
      say "FAIL($TAG): $NBADC chain(s) failed to resolve in this level — the declared hierarchy is wrong"
      grep -a '\[HD-PHYS\] ag=' "$GKLOG" | grep -E 'chain [0-9]+ (invalid|DROPPED)' | sort -u | head -20 >> "$R"; OK=0; }
    NREORD=$(grep -ac 're-ordered from the rig hierarchy' "$GKLOG" || true)
    say "leg $TAG: riders-bound=$NRIDE (chains=0: $NRIDE0) rider-windows=$RWIN rider-active-windows=$RACT bad-chains=$NBADC re-ordered=$NREORD"
    grep -a '\[HD-PHYS\] init ag=' "$GKLOG" | grep -a 'rider=1' | sort -u >> "$R"
  fi
  case "$MODE" in
    expect-phys)
      [ "$NLOAD" -ge 1 ] || { say "FAIL($TAG): no 'params loaded' line"; OK=0; }
      # init lines must report chains>0 on at least 2 companions (title spawns jak+dax drivers)
      local NCH; NCH=$(grep -a '\[HD-PHYS\] init ag=' "$GKLOG" | grep -vc 'chains=0 ' || true)
      [ "$NCH" -ge 1 ] || { say "FAIL($TAG): no companion resolved any chain"; OK=0; }
      [ "$NWIN" -ge 1 ] || { say "FAIL($TAG): no [HD-PHYS] window state dump"; OK=0; }
      [ "$NNAN" = 0 ] || { say "FAIL($TAG): nan-resets nonzero — sim exploded"; OK=0; }
      # bounded: no window line may report maxdev >= 5000 units (~1.2m) at title idle
      local NBIG; NBIG=$(grep -a 'maxdev=' "$GKLOG" | awk -F'maxdev=' '{print $2}' | awk '{if ($1+0 >= 5000.0) n++} END {print n+0}')
      [ "$NBIG" = 0 ] || { say "FAIL($TAG): $NBIG window(s) with maxdev>=5000 — not bounded"; OK=0; }
      say "leg $TAG: chains-resolving-inits=$NCH bounded-windows=yes"
      ;;
    expect-gameplay)
      # same bar as expect-phys PLUS at least one MOVING window: the driver pose visibly animated
      # (anchmove>0) and the sim actually deviated (maxdev>0) yet stayed bounded. This is the
      # sustained-real-animation state dump (title press-start windows are parked: anchmove=0
      # -> the chain self-tracks its own rest exactly, maxdev=0 by construction).
      [ "$NLOAD" -ge 1 ] || { say "FAIL($TAG): no 'params loaded' line"; OK=0; }
      local NCH2; NCH2=$(grep -a '\[HD-PHYS\] init ag=' "$GKLOG" | grep -vc 'chains=0 ' || true)
      [ "$NCH2" -ge 1 ] || { say "FAIL($TAG): no companion resolved any chain"; OK=0; }
      [ "$NWIN" -ge 1 ] || { say "FAIL($TAG): no [HD-PHYS] window state dump"; OK=0; }
      [ "$NNAN" = 0 ] || { say "FAIL($TAG): nan-resets nonzero — sim exploded"; OK=0; }
      local NBIG2; NBIG2=$(grep -a 'maxdev=' "$GKLOG" | awk -F'maxdev=' '{print $2}' | awk '{if ($1+0 >= 5000.0) n++} END {print n+0}')
      [ "$NBIG2" = 0 ] || { say "FAIL($TAG): $NBIG2 window(s) with maxdev>=5000 — not bounded"; OK=0; }
      # 'anchmove=' not 'window: chains=': the dump is two format calls; on device logcat they
      # flush as two lines (x86 file logs keep them joined — this grep works for both).
      local NMOVDEV; NMOVDEV=$(grep -a 'anchmove=' "$GKLOG" | awk '{
        am=0; md=0;
        if (match($0, /anchmove=[0-9.]+/)) am=substr($0, RSTART+9, RLENGTH-9)+0;
        if (match($0, /maxdev=[0-9.]+/))   md=substr($0, RSTART+7, RLENGTH-7)+0;
        if (am > 1.0 && md > 0.5 && md < 5000.0) n++ } END {print n+0}')
      [ "$NMOVDEV" -ge 1 ] || { say "FAIL($TAG): no MOVING bounded window (anchor animated + sim deviating)"; OK=0; }
      say "leg $TAG: chains-resolving-inits=$NCH2 moving-bounded-windows=$NMOVDEV"
      # ---- (C) KEIRA CHEST: the owner's "ça bouge pas d'un poil" defect ------------------------
      # The slot-wide maxdev was always dominated by hair/strap tips, so an inert chest was
      # invisible to it. Gate the chest chain's OWN per-chain deviation, from BOTH sides:
      #   floor  — it must clear the analytic spring-gravity sag (g*gravity/omega^2 =
      #            40140.8*0.06/(2*pi*1.3)^2 = 36.1 units), i.e. it is really being simulated;
      #   ceiling— "rien de fou": 400 units (~10 cm) is the top of subtle.
      CHEST=$(grep -a 'ag=keira.*cdev:' "$GKLOG" | awk -v i="$KIDX_CHESTR" '
        { s=substr($0, index($0,"cdev:"));
          if (match(s, " " i "=[0-9.]+")) { v=substr(s, RSTART+length(i)+2, RLENGTH-length(i)-2)+0; if (v>m) m=v } }
        END { printf "%.4f", m+0 }')
      GOG=$(grep -a 'ag=keira.*cdev:' "$GKLOG" | awk -v i="$KIDX_GOG" '
        { s=substr($0, index($0,"cdev:"));
          if (match(s, " " i "=[0-9.]+")) { v=substr(s, RSTART+length(i)+2, RLENGTH-length(i)-2)+0; if (v>m) m=v } }
        END { printf "%.4f", m+0 }')
      say "leg $TAG: keira chest chain max deviation = $CHEST units ; goggles chain = $GOG units"
      awk -v v="$CHEST" 'BEGIN{exit !(v+0 >= 20.0)}' \
        || { say "FAIL($TAG): keira chest deviation $CHEST < 20 units — the chest chain is still INERT (owner defect C)"; OK=0; }
      # 300 units (~7.3 cm) is BELOW the chain's geometric maximum (the 22 deg cone on a 977-unit
      # lever allows 366), so this ceiling can actually trip — it is a real bound on "subtle", not
      # decoration.
      awk -v v="$CHEST" 'BEGIN{exit !(v+0 <= 300.0)}' \
        || { say "FAIL($TAG): keira chest deviation $CHEST > 300 units — that is not 'rien de fou'"; OK=0; }
      # ---- (D) GOGGLES: were class=accessory -> gated off at the default level, and their lenses
      # would have torn off. Now primary + descendant re-glue: they must actually move.
      awk -v v="$GOG" 'BEGIN{exit !(v+0 > 0.0)}' \
        || { say "FAIL($TAG): keira goggles deviation is 0 — the accessory still has no physics (owner defect D)"; OK=0; }
      ;;
    expect-off)
      [ "$NWIN" = 0 ] || { say "FAIL($TAG): $NWIN window lines with physics?=#f — OFF is not off"; OK=0; }
      ;;
  esac
  kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true; GKPID=0; sleep 2
  [ "$OK" = 1 ]
}

FAILED=0
run_leg "L2-max"    '#t' 2 1 1 1 1 expect-phys || FAILED=1
run_leg "L0-light"  '#t' 0 1 1 1 1 expect-phys || FAILED=1
run_leg "BONUS"     '#t' 1 2 2 2 2 expect-phys || FAILED=1
run_leg "GAMEPLAY"  '#t' 1 1 1 1 1 expect-gameplay "village1-hut" "-130.5 34.5 202.4" || FAILED=1
run_leg "OFF"       '#f' 1 1 1 1 1 expect-off  || FAILED=1
run_leg "STOCKLOOK" '#t' 1 1 1 1 1 expect-rider "village1-hut" "-130.5 34.5 202.4" || FAILED=1

say ""
if [ "$FAILED" = 0 ]; then say "[physics x86 smoke PASS] all six legs green"; else say "[physics x86 smoke FAIL] see legs above"; fi
exit "$FAILED"
