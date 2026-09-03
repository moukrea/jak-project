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

# ---- CYCLE-3 artifact gates (owner verdict 2026-08-06) ----------------------------------------
# Every cycle-3 fix must be physically in the shipped objects before a frame runs. These are the
# strings and data keys the owner's complaints map onto, one for one.
for s in 'HD-PHYS2' 'authhold=' 'autheng=' 'authrel=' 'reseed=' 'burst=' 'frozen=' 'jdev:'; do
  n=$(strings -a "$ISO/GAME.CGO" | grep -c -- "$s" || true)
  [ "${n:-0}" -ge 1 ] || { say "FAIL: GAME.CGO carries no '$s' string — cycle-3 instrument not compiled in"; exit 1; }
done
say "artifact gate: GAME.CGO carries the cycle-3 instrument strings (HD-PHYS2/auth*/reseed/burst/frozen/jdev)"
NTAP=$(grep -c 'radius2=' recharged_assets/physics_chains.txt || true)
[ "${NTAP:-0}" -ge 10 ] || { say "FAIL: only ${NTAP:-0} tapered colliders — flared trousers/shoulders (owner C) not in the data"; exit 1; }
NCSK=$(grep -c 'colskip=' recharged_assets/physics_chains.txt || true)
[ "${NCSK:-0}" -ge 20 ] || { say "FAIL: only ${NCSK:-0} chains declare colskip= — freed roots would collide with their own skull"; exit 1; }
# authored-anim priority is DELIBERATELY NARROW. The first cut of this gate demanded >=20 chains,
# from a design that armed every anim=excite chain — and the run below measured why that design was
# wrong: the detector also sees a STATIC authored pose offset, so Daxter (0.53-1.36) and Samos'
# stock beard (a flat 0.425) sat permanently suspended, i.e. their physics was silently deleted.
# The bar is now the owner's two NAMED forced-action sites, on every look that has them:
# Jak's ears (jak-hd + eichar-lod0/jak-white-lod0 = 4 chains) and Keira's goggles (keira-hd,
# keira3-hd, assistant-* = 3 chains). Widening this number again without first reading a chain's
# measured `aratio:` is how you delete a character's physics without noticing.
NAUT=$(grep -cE '^chain .*authored=' recharged_assets/physics_chains.txt || true)
[ "${NAUT:-0}" -ge 7 ] || { say "FAIL: only ${NAUT:-0} chains declare authored= — authored-anim priority (owner A) not on Jak's ears + Keira's goggles"; exit 1; }
NAUTEAR=$(grep -cE '^chain ear[LR] .*authored=' recharged_assets/physics_chains.txt || true)
NAUTGOG=$(grep -cE '^chain goggles .*authored=' recharged_assets/physics_chains.txt || true)
[ "${NAUTEAR:-0}" -ge 4 ] || { say "FAIL: Jak's ears carry authored= on only ${NAUTEAR:-0} chains (need 4: both looks, L+R)"; exit 1; }
[ "${NAUTGOG:-0}" -ge 3 ] || { say "FAIL: Keira's goggles carry authored= on only ${NAUTGOG:-0} chains (need 3: keira-hd, keira3-hd, stock)"; exit 1; }
# owner cycle-3d Q names Daxter's ears explicitly — ND hand-keys them in many animations.
NAUTDAX=$(awk '/^\[model /{cur=($0 ~ /dax-hd|daxp-hd|sidekick-lod0/)?1:0; next} cur && /^chain ear[LR] .*authored=/{n++} END{print n+0}' recharged_assets/physics_chains.txt)
[ "${NAUTDAX:-0}" -ge 6 ] || { say "FAIL: Daxter's ears carry authored= on only ${NAUTDAX:-0} chains (need 6: dax-hd, daxp-hd, sidekick-lod0 x L/R) — owner Q"; exit 1; }
say "artifact gate: authored-anim priority armed on Jak's ears ($NAUTEAR), Keira's goggles ($NAUTGOG) and Daxter's ears ($NAUTDAX)"
# (F) the Keira straps regression: they must be GONE from the data, not merely retuned.
NSTRAP=$(grep -cE '^chain (top|bot)strap[LR] ' recharged_assets/physics_chains.txt || true)
[ "${NSTRAP:-0}" = 0 ] || { say "FAIL: $NSTRAP Keira strap chain(s) still declared — owner F asked for fixed-or-reverted, this is neither"; exit 1; }
# (E) Jak's ears, on BOTH his looks (HD companion + original stock rig).
for m in jak-hd eichar-lod0; do
  ne=$(awk -v m="$m" '
        /^\[model /   { cur=0; h=$0; sub(/^\[model /,"",h); sub(/\]$/,"",h);
                        n=split(h,a," "); for (i=1;i<=n;i++) if (a[i]==m) cur=1; next }
        cur && /^chain ear[LR] / { c++ }
        END { print c+0 }' recharged_assets/physics_chains.txt)
  [ "${ne:-0}" -ge 2 ] || { say "FAIL: model $m declares ${ne:-0} ear chains (<2) — owner E not in the data"; exit 1; }
done
say "artifact gate: cycle-3 DATA — $NTAP tapered colliders, $NCSK colskip chains, $NAUT authored chains, Keira straps reverted, Jak ears on both looks"

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
    # ---- CYCLE-3 WINDOW GATES ([HD-PHYS2] line) ------------------------------------------------
    N2=$(grep -ac '\[HD-PHYS2\] ag=' "$GKLOG" || true)
    [ "${N2:-0}" -ge 1 ] || { say "FAIL($TAG): no [HD-PHYS2] window line — the cycle-3 counters never printed"; OK=0; }
    # (B) owner bar: a spawn/teleport settle must never throw a chain past a third of its length.
    NBURST=$(grep -a 'burst=' "$GKLOG" | grep -cv 'burst=0 ' || true)
    [ "${NBURST:-0}" = 0 ] || { say "FAIL($TAG): $NBURST window(s) with burst!=0 — chains still go wild at spawn/transition"; OK=0; }
    # (D) owner bar: no DECLARED, class-live chain may sit frozen while its actor moves.
    NFRZ=$(grep -a 'frozen=' "$GKLOG" | grep -cv 'frozen=0 ' || true)
    [ "${NFRZ:-0}" = 0 ] || { say "FAIL($TAG): $NFRZ window(s) with frozen!=0 — a declared chain never moved while its actor did"; OK=0; }
    # (A) the suspension must RELEASE. A window that held the animation for all 300 frames means the
    # chain never got its physics back — engage without release is the failure mode this catches.
    # (A) "physics resumes after" — the per-CHAIN unbroken-suspension record. `authhold` counts
    # CHAIN-frames and hits 300 on any actor with a few suspended chains, so it can never answer
    # "was ONE chain never given back": holdmax can, and it is not reset by a window boundary.
    # 900 frames = 15 s of unbroken suspension is not a forced action any more, it is a stuck blend.
    NSTUCK=$(grep -a 'holdmax=' "$GKLOG" | awk '{if (match($0,/holdmax=[0-9]+/) && substr($0,RSTART+8,RLENGTH-8)+0 >= 900) n++} END {print n+0}')
    [ "${NSTUCK:-0}" = 0 ] || { say "FAIL($TAG): $NSTUCK window(s) with holdmax>=900 — a chain was suspended and never handed back"; OK=0; }
    HMAX=$(grep -a 'holdmax=' "$GKLOG" | awk '{if (match($0,/holdmax=[0-9]+/)) {v=substr($0,RSTART+8,RLENGTH-8)+0; if (v>m) m=v}} END {print m+0}')
    AENG=$(grep -a 'autheng=' "$GKLOG" | awk '{if (match($0,/autheng=[0-9]+/)) s+=substr($0,RSTART+8,RLENGTH-8)} END {print s+0}')
    AREL=$(grep -a 'authrel=' "$GKLOG" | awk '{if (match($0,/authrel=[0-9]+/)) s+=substr($0,RSTART+8,RLENGTH-8)} END {print s+0}')
    ARSD=$(grep -a 'reseed=' "$GKLOG" | awk '{if (match($0,/reseed=[0-9]+/)) s+=substr($0,RSTART+7,RLENGTH-7)} END {print s+0}')
    say "leg $TAG: cycle3 lines=$N2 burst-bad=$NBURST frozen-bad=$NFRZ engage=$AENG release=$AREL reseed=$ARSD holdmax=$HMAX stuck-windows=$NSTUCK"
    if [ "${AENG:-0}" -gt 0 ] && [ "${AREL:-0}" = 0 ]; then
      say "FAIL($TAG): the authored suspension ENGAGED $AENG time(s) and never RELEASED — physics does not resume"; OK=0; fi
    # ---- CYCLE-3b/3c/3d GATES ------------------------------------------------------------------
    # (O) an unsatisfiable constraint must SETTLE, never oscillate. jitter counts velocity REVERSALS
    # above a speed floor: a chain buzzing against a collider reverses every frame, and that is the
    # number behind the owner's "jitter comme un fou". `rested` counts the chain-frames the rest
    # state actually held a fighting chain still, so the mechanism is visible even when jitter is 0.
    JIT=$(grep -a 'jitter=' "$GKLOG" | awk '{if (match($0,/jitter=[0-9]+/)) {v=substr($0,RSTART+7,RLENGTH-7)+0; if (v>m) m=v}} END {print m+0}')
    JITW=$(grep -a 'jitter=' "$GKLOG" | awk '{if (match($0,/jitter=[0-9]+/) && substr($0,RSTART+7,RLENGTH-7)+0 > 60) n++} END {print n+0}')
    RST=$(grep -a 'rested=' "$GKLOG" | awk '{if (match($0,/rested=[0-9]+/)) s+=substr($0,RSTART+7,RLENGTH-7)} END {print s+0}')
    CLM=$(grep -a 'clamped=' "$GKLOG" | awk '{if (match($0,/clamped=[0-9]+/)) s+=substr($0,RSTART+8,RLENGTH-8)} END {print s+0}')
    # THE gate is the SUSTAINED fight, not the reversal count. A chain sliding along a moving body
    # reverses occasionally however well it behaves (measured: 73 isolated reversals on a Maia whose
    # rest state never even had to arm); what the owner sees is a chain reversing under contact frame
    # after frame. stickmax is that run length, it is what arms the rest damping at PHYS-STICK=12,
    # and 60 frames (1 s) of unbroken fighting is the point where "settling" stops being true.
    STK=$(grep -a 'stickmax=' "$GKLOG" | awk '{if (match($0,/stickmax=[0-9]+/)) {v=substr($0,RSTART+9,RLENGTH-9)+0; if (v>m) m=v}} END {print m+0}')
    # PERSISTENCE IS NOT THE SIN, OSCILLATION IS. The owner's rule is "si ca ne se conforme pas...
    # ca devrait juste RESTER TRANQUILLE tout en essayant TRANQUILLEMENT de se conformer" — a chain
    # may press against a collider indefinitely, it may not VIBRATE while doing it. So a long run is
    # only a failure when the same window also shows real reversal activity.
    BADW=$(grep -a 'stickmax=' "$GKLOG" | awk '{
        st=0; ji=0;
        if (match($0,/stickmax=[0-9]+/)) st=substr($0,RSTART+9,RLENGTH-9)+0;
        if (match($0,/jitter=[0-9]+/))   ji=substr($0,RSTART+7,RLENGTH-7)+0;
        if (st >= 60 && ji > 30) n++ } END {print n+0}')
    [ "${BADW:-0}" = 0 ] || { say "FAIL($TAG): $BADW window(s) where a chain fought a collider for >=60 frames AND kept reversing — oscillating, not settling"; OK=0; }
    # ...and a hard absurdity bound on the raw count, so a genuinely buzzing rig cannot hide behind
    # a short run length: 2 reversals per frame sustained over a window is not contact, it is noise.
    [ "${JIT:-0}" -lt 600 ] || { say "FAIL($TAG): jitter=$JIT in one window — that is not contact, that is buzzing"; OK=0; }
    # (P) the per-link influence profile must have NO step: that discontinuity IS the "cran" the
    # owner sees at mid-ear. Built bounded by the solver, graded here on what it actually built.
    ISTEP=$(grep -a 'inflstep=' "$GKLOG" | awk '{if (match($0,/inflstep=[0-9.]+/)) {v=substr($0,RSTART+9,RLENGTH-9)+0; if (v>m) m=v}} END {printf "%.4f", m+0}')
    awk -v v="$ISTEP" 'BEGIN{exit !(v+0 <= 0.4501)}' \
      || { say "FAIL($TAG): influence profile step $ISTEP > 0.45 — the per-link transition is discontinuous (owner P)"; OK=0; }
    NPROF=$(grep -ac '\[HD-PHYS-INFL\] ag=' "$GKLOG" || true)
    [ "${NPROF:-0}" -ge 1 ] || { say "FAIL($TAG): no [HD-PHYS-INFL] profile line — the per-link influence profile is not reported"; OK=0; }
    say "leg $TAG: cycle3bcd jitter-max=$JIT stick-max=$STK rested=$RST clamped=$CLM inflstep-max=$ISTEP profile-lines=$NPROF"
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
      # OWNER CYCLE-3 G MOVED THIS BAR, IN BOTH DIRECTIONS. Cycle 2 asked for "rien de fou" and this
      # gate held the chest under 300 units. Having seen it, the owner's verdict is "ca bouge un
      # poil, faut regarder a la loupe -- faudrait que ca jiggle BEAUCOUP PLUS que ca". So the FLOOR
      # becomes his new bar (400 units, ~10 cm; the cycle-2 build measured 272.4) and the ceiling
      # stops being a taste judgement -- taste is the owner's, never this script's -- and becomes an
      # ABSURDITY bound: 900 units is 22 cm of travel, which is broken, not bold.
      awk -v v="$CHEST" 'BEGIN{exit !(v+0 >= 400.0)}' \
        || { say "FAIL($TAG): keira chest deviation $CHEST < 400 units — owner cycle-3 G asked for much MORE than the 272.4 he judged too timid"; OK=0; }
      awk -v v="$CHEST" 'BEGIN{exit !(v+0 <= 900.0)}' \
        || { say "FAIL($TAG): keira chest deviation $CHEST > 900 units (22 cm) — that is not jiggle, that is broken"; OK=0; }
      # ---- (D) GOGGLES: were class=accessory -> gated off at the default level, and their lenses
      # would have torn off. Now primary + descendant re-glue: they must actually move.
      awk -v v="$GOG" 'BEGIN{exit !(v+0 > 0.0)}' \
        || { say "FAIL($TAG): keira goggles deviation is 0 — the accessory still has no physics (owner defect D)"; OK=0; }
      ;;
    expect-off)
      [ "$NWIN" = 0 ] || { say "FAIL($TAG): $NWIN window lines with physics?=#f — OFF is not off"; OK=0; }
      N2OFF=$(grep -ac '\[HD-PHYS2\] ag=' "$GKLOG" || true)
      [ "${N2OFF:-0}" = 0 ] || { say "FAIL($TAG): $N2OFF [HD-PHYS2] lines with physics?=#f — the cycle-3 counters run with physics OFF"; OK=0; }
      ;;
  esac
  kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true; GKPID=0; sleep 2
  [ "$OK" = 1 ]
}

# ---------------------------------------------------------------------------------------------
# INTRO-CINEMATIC LEG (owner cycle-3b M + 3c N/O). Three of the owner's cycle-3b/3c complaints only
# exist in ONE place in the whole game: Maia and Gol are placed as entities in the `intro` level and
# nowhere else (the citadel/village3 art groups are spooled cutscene data with no entity and no
# process), and Jak lying down in close-up — the collar-jitter case — is that same cinematic. So the
# three are proven in a single leg instead of three.
# It is driven the way .autoport/gcine_audit_x86.sh already drives it: boot to the title, then
# `initialize! *game-info*` on "intro-start" over the goalc listener. A level warp cannot be used —
# the intro level has no continue point of its own.
run_intro_leg(){
  local TAG=INTRO GKLOG="$OUT/.smoke_gk_INTRO.log"; : > "$GKLOG"
  set_ini 'recharged-enhanced-models?' '#t'
  set_ini 'physics?' '#t'; set_ini 'physics-quality' 2
  set_ini 'hd-look-jak' 1; set_ini 'hd-look-daxter' 1
  set_ini 'hd-look-keira' 1; set_ini 'hd-look-samos' 1
  say ""; say "=== LEG INTRO: physics?=#t quality=2, intro cinematic (Maia + Gol + Jak lying down) ==="
  env OG_LEVEL_WARP=intro-start "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
  GKPID=$!
  local booted=0 i
  for i in $(seq 1 150); do
    kill -0 "$GKPID" 2>/dev/null || { say "FAIL(INTRO): gk exited during boot"; tail -25 "$GKLOG" >> "$R"; return 1; }
    grep -aqE "link finish: (default-menu|logo)" "$GKLOG" && { booted=1; break; }
    sleep 1
  done
  [ "$booted" = 1 ] || { say "FAIL(INTRO): boot timeout"; tail -25 "$GKLOG" >> "$R"; return 1; }
  sleep 4
  # NOT driven over the goalc listener: a fresh REPL has no symbol table for the running target, so
  # `*game-info*` does not resolve and the form dies with a Compilation Error while gk carries on at
  # the title — a leg that proves nothing while looking like it ran. The harness's own native warp
  # does the same job: OG_LEVEL_WARP takes a CONTINUE-POINT name, "intro-start" carries
  # (continue-flags intro) (level-info.gc:229-256), and that flag is what makes target-death.gc:149
  # call start-sequence-a — the intro cinematic, i.e. Misty Island with Gol, Maia and Jak lying down.
  local w=0
  for i in $(seq 1 120); do
    kill -0 "$GKPID" 2>/dev/null || { say "FAIL(INTRO): gk died before the warp"; tail -25 "$GKLOG" >> "$R"; return 1; }
    grep -aq 'LEVEL-WARP-SPAWN' "$GKLOG" && { w=1; break; }
    sleep 1
  done
  [ "$w" = 1 ] || { say "FAIL(INTRO): intro-start warp never fired"; tail -25 "$GKLOG" >> "$R"; return 1; }
  say "intro-start warp landed — watching ${INTROWATCH:-200}s"
  sleep "${INTROWATCH:-200}"
  local ALIVE=no; kill -0 "$GKPID" 2>/dev/null && ALIVE=yes
  local OK=1 CRASH
  CRASH=$(grep -acE 'SIGSEGV|SIGILL|Segmentation|Assertion' "$GKLOG" || true)
  [ "$ALIVE" = yes ] || { say "FAIL(INTRO): gk died"; OK=0; }
  [ "$CRASH" = 0 ] || { say "FAIL(INTRO): crash markers"; OK=0; }
  # ---- (M) per-ACTOR per-CHAIN activity, Maia and Gol BY NAME -------------------------------
  # "declare" is not "active": the wave-2 aggregate counters could not tell the difference, which
  # is exactly how two characters shipped with inert hair. cdev: is the per-chain window maximum,
  # so a chain that never moved reads its own 0 next to its own index.
  local m
  for m in evilsis-lod0 evilbro-lod0; do
    local NB NCH ACT DEAD
    NB=$(grep -ac "\[HD-PHYS\] init ag=$m " "$GKLOG" || true)
    NCH=$(grep -a "\[HD-PHYS\] init ag=$m " "$GKLOG" | grep -vc 'chains=0 ' || true)
    [ "${NB:-0}" -ge 1 ] || { say "FAIL(INTRO): $m never bound a physics slot — it did not spawn or the hook missed it"; OK=0; }
    [ "${NCH:-0}" -ge 1 ] || { say "FAIL(INTRO): $m bound with chains=0 — its chains resolve to nothing"; OK=0; }
    # every DECLARED chain of this actor must show a nonzero window deviation at least once
    read -r ACT DEAD <<<"$(grep -a "ag=$m .*cdev:" "$GKLOG" | awk '
      { s=substr($0, index($0,"cdev:")); n=split(s, t, " ");
        for (i=2;i<=n;i++){ split(t[i], kv, "="); if (kv[2]+0 > 0.0001) seen[kv[1]]=1; all[kv[1]]=1 } }
      END { a=0; d=0; for (k in all) { if (k in seen) a++; else d++ } print a, d }')"
    say "leg INTRO: $m chains active=${ACT:-0} never-moved=${DEAD:-0}"
    [ "${ACT:-0}" -ge 1 ] || { say "FAIL(INTRO): $m has NO chain with any measured displacement — declared but inert (owner M)"; OK=0; }
    [ "${DEAD:-0}" = 0 ] || { say "FAIL(INTRO): $m has ${DEAD} declared chain(s) that never moved (owner M)"; OK=0; }
    grep -a "ag=$m .*cdev:" "$GKLOG" | tail -1 >> "$R"
  done
  # ---- (N) Maia's own penetration audit, named ----------------------------------------------
  local MRES
  MRES=$(grep -a 'ag=evilsis-lod0 .*resid=' "$GKLOG" | grep -cv 'resid=0 ' || true)
  [ "${MRES:-0}" = 0 ] || { say "FAIL(INTRO): $MRES evilsis window(s) with resid!=0 — Maia's hair still ends frames inside her body"; OK=0; }
  local MRESN; MRESN=$(grep -ac 'ag=evilsis-lod0 .*resid=0 ' "$GKLOG" || true)
  say "leg INTRO: MAIA (evilsis-lod0) resid=0 in $MRESN window(s), bad=$MRES"
  # ---- (O) Jak's collar under sustained contact, lying down, close-up ------------------------
  local JIT JITW RST
  JIT=$(grep -a 'jitter=' "$GKLOG" | awk '{if (match($0,/jitter=[0-9]+/)) {v=substr($0,RSTART+7,RLENGTH-7)+0; if (v>m) m=v}} END {print m+0}')
  JITW=$(grep -a 'jitter=' "$GKLOG" | awk '{if (match($0,/jitter=[0-9]+/) && substr($0,RSTART+7,RLENGTH-7)+0 > 60) n++} END {print n+0}')
  RST=$(grep -a 'rested=' "$GKLOG" | awk '{if (match($0,/rested=[0-9]+/)) s+=substr($0,RSTART+7,RLENGTH-7)} END {print s+0}')
  local STK; STK=$(grep -a 'stickmax=' "$GKLOG" | awk '{if (match($0,/stickmax=[0-9]+/)) {v=substr($0,RSTART+9,RLENGTH-9)+0; if (v>m) m=v}} END {print m+0}')
  local IBADW; IBADW=$(grep -a 'stickmax=' "$GKLOG" | awk '{
      st=0; ji=0;
      if (match($0,/stickmax=[0-9]+/)) st=substr($0,RSTART+9,RLENGTH-9)+0;
      if (match($0,/jitter=[0-9]+/))   ji=substr($0,RSTART+7,RLENGTH-7)+0;
      if (st >= 60 && ji > 30) n++ } END {print n+0}')
  [ "${IBADW:-0}" = 0 ] || { say "FAIL(INTRO): $IBADW window(s) fighting >=60 frames AND reversing — the collar case still oscillates"; OK=0; }
  [ "${JIT:-0}" -lt 600 ] || { say "FAIL(INTRO): jitter=$JIT in one intro window — buzzing"; OK=0; }
  say "leg INTRO: jitter-max=$JIT stick-max=$STK rested-chain-frames=$RST"
  local NNAN NRES
  NNAN=$(grep -a 'nan-resets=' "$GKLOG" | grep -cv 'nan-resets=0 ' || true)
  NRES=$(grep -a 'resid=' "$GKLOG" | grep -cv 'resid=0 ' || true)
  [ "${NNAN:-0}" = 0 ] || { say "FAIL(INTRO): nan-resets nonzero"; OK=0; }
  if [ "${NRES:-0}" != 0 ]; then
    say "FAIL(INTRO): $NRES window(s) with residual penetrations — the offending chains, by name:"
    grep -a 'cres:' "$GKLOG" | awk '{
        ag=""; if (match($0,/ag=[a-z0-9-]+/)) ag=substr($0,RSTART+3,RLENGTH-3);
        s=substr($0, index($0,"cres:")); if (index(s," aratio:")>0) s=substr(s,1,index(s," aratio:")); n=split(s,t," ");
        for (i=2;i<=n;i++){ split(t[i],kv,"="); if (kv[2]+0>0) print "   "ag" chain "kv[1]" residual on "kv[2]" frame(s)" } }' | sort -u >> "$R"
    OK=0
  fi
  grep -a '\[HD-PHYS-INFL\] ag=sidekick-lod0\|\[HD-PHYS-INFL\] ag=dax-hd' "$GKLOG" | tail -1 >> "$R"
  say "leg INTRO: alive=$ALIVE crash=$CRASH nan-bad=$NNAN resid-bad=$NRES"
  kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true; GKPID=0; sleep 2
  [ "$OK" = 1 ]
}

FAILED=0
# ONLY_INTRO=1 runs the single expensive leg on its own — the other six are unaffected by the
# cinematic work and re-running them to iterate on it would be 20 minutes of nothing.
if [ "${ONLY_INTRO:-0}" = 1 ]; then
  run_intro_leg && say "[physics x86 smoke INTRO-ONLY PASS]" || { say "[physics x86 smoke INTRO-ONLY FAIL]"; exit 1; }
  exit 0
fi
run_leg "L2-max"    '#t' 2 1 1 1 1 expect-phys || FAILED=1
run_leg "L0-light"  '#t' 0 1 1 1 1 expect-phys || FAILED=1
run_leg "BONUS"     '#t' 1 2 2 2 2 expect-phys || FAILED=1
run_leg "GAMEPLAY"  '#t' 1 1 1 1 1 expect-gameplay "village1-hut" "-130.5 34.5 202.4" || FAILED=1
run_leg "OFF"       '#f' 1 1 1 1 1 expect-off  || FAILED=1
run_leg "STOCKLOOK" '#t' 1 1 1 1 1 expect-rider "village1-hut" "-130.5 34.5 202.4" || FAILED=1
run_intro_leg || FAILED=1

say ""
if [ "$FAILED" = 0 ]; then say "[physics x86 smoke PASS] all six legs green"; else say "[physics x86 smoke FAIL] see legs above"; fi
exit "$FAILED"
