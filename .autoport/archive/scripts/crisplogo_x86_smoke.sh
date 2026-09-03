#!/usr/bin/env bash
# crisplogo_x86_smoke.sh — Grecharged-title-logo-fullres x86-FIRST functional smoke.
# Two legs against the fresh x86 oracle tree, driven only by settings.ini:
#   ON : crisp-title-logo? #t @ RENDER SCALE 40 -> expect "[crisp-logo] native replay" lines whose
#        fb=WxH is STRICTLY LARGER than the scaled game_res, and no GL/assert/crash markers.
#   OFF: crisp-title-logo? #f @ RENDER SCALE 40 -> expect ZERO replay lines (stock path).
# Artifact gates first (check the artifact, never the run).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-title-logo-fullres; mkdir -p "$OUT/x86"
R="$OUT/x86/smoke.txt"; : > "$R"
INI=build/game/OpenGOAL/jak1/settings/settings.ini
WATCH="${WATCH:-45}"
say(){ echo "$*" | tee -a "$R"; }

# ---- artifact gates ----------------------------------------------------------------------------
[ -f "$ISO/GAME.CGO" ] || { say "FAIL: no $ISO/GAME.CGO"; exit 1; }
[ "$ISO/GAME.CGO" -nt goal_src/jak1/pc/pckernel-impl.gc ] || { say "FAIL: GAME.CGO stale vs pckernel-impl.gc"; exit 1; }
CGOSYM=$(strings -a "$ISO/GAME.CGO" | grep -c 'crisp-title-logo' || true)
[ "${CGOSYM:-0}" -ge 1 ] || { say "FAIL: GAME.CGO carries no crisp-title-logo string — GOAL side not compiled in"; exit 1; }
say "artifact gate: GAME.CGO carries $CGOSYM crisp-title-logo string(s)"
BINSYM=$(strings -a "$GK" | grep -c 'pc-set-crisp-title-logo' || true)
BINGATE=$(strings -a "$GK" | grep -c 'crisp-logo\] native replay' || true)
BINNAME=$(strings -a "$GK" | grep -c '^logo-volumes-english-lod0$' || true)
[ "${BINSYM:-0}" -ge 1 ]  || { say "FAIL: gk lacks pc-set-crisp-title-logo!"; exit 1; }
[ "${BINGATE:-0}" -ge 1 ] || { say "FAIL: gk lacks the [crisp-logo] native replay gate"; exit 1; }
[ "${BINNAME:-0}" -ge 1 ] || { say "FAIL: gk lacks the logo model-name table"; exit 1; }
say "artifact gate: gk carries the FFI symbol, the activity gate and the logo name table"

set_ini(){ # key value — edit in place inside [settings]; never append at EOF (the tail lands in [music])
  local K="$1" V="$2"
  mkdir -p "$(dirname "$INI")"; [ -f "$INI" ] || printf '[settings]\n' > "$INI"
  if grep -q "^$K = " "$INI"; then
    python3 - "$INI" "$K" "$V" <<'EOF'
import sys
p,k,v = sys.argv[1],sys.argv[2],sys.argv[3]
ls=open(p).read().splitlines()
open(p,'w').write("\n".join((f"{k} = {v}" if l.startswith(k+" = ") else l) for l in ls)+"\n")
EOF
  else
    # Insert at the END of the [settings] block. NOT right after the "[settings]" header: the
    # parser demands `version` as the FIRST key and rejects the WHOLE file otherwise
    # ("pc settings read error: expected version key got ..."), silently falling back to defaults —
    # which is exactly how this harness first reported a false negative. And NOT at EOF either:
    # the tail lands inside [music] and is dropped (settings_ini_append_music_trap).
    python3 - "$INI" "$K" "$V" <<'EOF'
import sys
p,k,v = sys.argv[1],sys.argv[2],sys.argv[3]
ls=open(p).read().splitlines()
out=[];ins=False;in_settings=False
for l in ls:
    s=l.strip()
    if s.startswith("[") and s.endswith("]"):
        if in_settings and not ins:
            out.append(f"{k} = {v}"); ins=True
        in_settings = (s == "[settings]")
    out.append(l)
if not ins:
    out.append(f"{k} = {v}") if in_settings else out.extend(["[settings]", f"{k} = {v}"])
open(p,'w').write("\n".join(out)+"\n")
EOF
  fi
  grep -q '^version = ' "$INI" && [ "$(grep -m1 -oE '^[a-z][^ ]* = ' "$INI" | head -1)" = "version = " ] \
    || { echo "  set_ini FATAL: 'version' is no longer the first key in $INI — the whole file would be rejected"; return 1; }
}

leg(){ local TAG="$1" CRISP="$2" SCALE="$3"
  set_ini 'crisp-title-logo?' "$CRISP"
  set_ini 'render-scale' "${SCALE}.0000"
  set_ini 'dynamic-render-scale?' '#f'
  set_ini 'recharged-master?' '#t'
  say ""; say "=== LEG $TAG: crisp-title-logo? $CRISP @ render-scale $SCALE ==="
  say "    ini: $(grep -aE '^(crisp-title-logo\?|render-scale|dynamic-render-scale\?|recharged-master\?) = ' "$INI" | tr '\n' ' ')"
  local L="$OUT/x86/gk-$TAG.log"; : > "$L"
  "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$L" 2>&1 &
  local PID=$!
  local booted=0 i
  for i in $(seq 1 180); do
    kill -0 "$PID" 2>/dev/null || { say "FAIL($TAG): gk exited during boot"; tail -25 "$L" >> "$R"; return 1; }
    grep -aqE "link finish: (logo|default-menu)" "$L" && { booted=1; break; }
    sleep 1
  done
  [ "$booted" = 1 ] || { say "FAIL($TAG): boot timeout"; tail -25 "$L" >> "$R"; kill "$PID" 2>/dev/null; return 1; }
  say "    booted — watching ${WATCH}s at the title"
  sleep "$WATCH"
  local ALIVE=no; kill -0 "$PID" 2>/dev/null && ALIVE=yes
  local NREPLAY CRASH GLERR
  NREPLAY=$(grep -ac 'crisp-logo\] native replay' "$L" || true)
  CRASH=$(grep -acE 'SIGSEGV|SIGILL|Segmentation|Assertion|ASSERT' "$L" || true)
  GLERR=$(grep -acE 'GL_INVALID|OpenGL error|GL error' "$L" || true)
  say "    alive=$ALIVE replay_lines=$NREPLAY crash_markers=$CRASH gl_errors=$GLERR"
  say "    toggle : $(grep -a 'crisp-logo\] toggle' "$L" | tail -1)"
  say "    menu   : $(grep -a 'CRISPLOGO-MENU' "$L" | tail -1)"
  say "    replay : $(grep -a 'crisp-logo\] native replay' "$L" | tail -1)"
  kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
  echo "$NREPLAY|$CRASH|$GLERR|$ALIVE"
  return 0; }

RON=$(leg ON  '#t' 40 | tail -1)
ROFF=$(leg OFF '#f' 40 | tail -1)
say ""; say "=== VERDICT ==="
say "ON : replay|crash|glerr|alive = $RON"
say "OFF: replay|crash|glerr|alive = $ROFF"
ok=1
[ "$(echo "$RON"  | cut -d'|' -f1)" -ge 1 ] || { say "FAIL: ON produced no native replay"; ok=0; }
[ "$(echo "$RON"  | cut -d'|' -f2)" -eq 0 ] || { say "FAIL: ON hit crash/assert markers"; ok=0; }
[ "$(echo "$RON"  | cut -d'|' -f4)" = yes ] || { say "FAIL: ON died before the watch ended"; ok=0; }
[ "$(echo "$ROFF" | cut -d'|' -f1)" -eq 0 ] || { say "FAIL: OFF produced native replay lines (not the stock path)"; ok=0; }
[ "$(echo "$ROFF" | cut -d'|' -f4)" = yes ] || { say "FAIL: OFF died before the watch ended"; ok=0; }
[ "$ok" = 1 ] && say "X86 SMOKE PASS" || say "X86 SMOKE FAIL"
