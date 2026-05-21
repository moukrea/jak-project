#!/usr/bin/env bash
# Capture the desktop x86_64 oracle trace — the ground truth the
# autoport must reproduce on Android.
#
# Produces under .autoport/oracle/:
#   jak1-desktop-trace.txt        — full verbose stdout/stderr of gk
#   jak1-desktop-summary.json     — extracted milestones + timestamps
#   jak1-desktop-syms.txt         — nm of build-x86/game/gk
#   jak1-desktop-state-samples/   — per-second JSON state snapshots
#   jak1-title.png                — title-screen reference screencap
#   (more captures as the run progresses)
#
# Strategy: run `gk --game jak1 --portable -fakeiso --verbose
# -iso-data <iso>` until we observe `engine: state=title` (or whatever
# the desktop runtime's title-state log line is — see
# game/kernel/jak1/gstate.cpp and gstate.gc). Run for 60s past title
# to also capture menu entry. Capture everything.
#
# The script is idempotent: running it again overwrites the oracle.
# Don't run during an autoport phase — it's a single-user resource.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

ORACLE_DIR=".autoport/oracle"
mkdir -p "$ORACLE_DIR" "$ORACLE_DIR/state-samples"

GK="build-x86/game/gk"
GOALC="build-x86/goalc/goalc"
if [ ! -x "$GK" ]; then
    echo "FAIL: $GK not found; build the desktop runtime first:" >&2
    echo "      cmake --build build-x86 --target gk" >&2
    exit 1
fi

# ISO data dir — must contain the user's extracted PS2 disc files.
ISO_DIR=""
for cand in iso_data/jak1 out/jak1/iso; do
    if [ -d "$cand" ] && ls "$cand"/*.CGO >/dev/null 2>&1; then
        ISO_DIR="$cand"; break
    fi
done
if [ -z "$ISO_DIR" ]; then
    echo "FAIL: no jak1 ISO data found under iso_data/jak1 or out/jak1/iso." >&2
    exit 1
fi
echo "  ISO data: $ISO_DIR"

# 1. Dump the desktop binary's symbol table.
echo "== capturing desktop symbol table =="
nm --defined-only --demangle --print-size "$GK" 2>/dev/null \
    | sort > "$ORACLE_DIR/jak1-desktop-syms.txt"
SYM_COUNT=$(wc -l < "$ORACLE_DIR/jak1-desktop-syms.txt")
echo "  $SYM_COUNT defined symbols"

# 2. Spawn gk in the background; capture stdout + stderr.
TRACE="$ORACLE_DIR/jak1-desktop-trace.txt"
SUMMARY="$ORACLE_DIR/jak1-desktop-summary.json"
: > "$TRACE"
echo "== launching $GK --game jak1 --portable -fakeiso --verbose -iso-data $ISO_DIR =="

# Note: we do NOT pass --no-display because we want the real render
# path to run. The actual SDL window appears on the user's desktop;
# they can leave it alone. The screencap step uses `import` or
# `gnome-screenshot` to grab it.

"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
      -iso-data "$ISO_DIR" \
      -- -boot -debug-mem \
    > "$TRACE" 2>&1 &
GK_PID=$!
trap "kill $GK_PID 2>/dev/null || true" EXIT
echo "  gk pid: $GK_PID"

# 3. Watch the trace for milestone events; capture screencaps when
# each fires. The milestones below are REAL log markers emitted by the
# upstream OpenGOAL runtime (verified against a working gk run on
# 2026-05-21 after the autoport's arm64-corrupted CGOs were regenerated
# with build/goalc/goalc). Earlier `engine: state=...` strings were
# claude-side fabrication that no upstream code actually emits — see
# SUPERVISOR_JOURNAL.md 2026-05-21 entry.
MILESTONES=(
    "dkernel: boot mode"
    "InitIOP OK"
    "Initialized GOAL heap"
    "Got DGO file header for KERNEL.CGO"
    "link finish: gkernel"
    "link finish: gstate"
    "link finish: default-menu"
    "link finish: default-menu-pc"
)
declare -A SEEN

# Helper: grab the desktop screen. Prefer gnome-screenshot; fall back
# to ImageMagick's `import` against the gk window. As a last resort,
# capture the full root.
screencap_desktop() {
    local out="$1"
    if command -v gnome-screenshot >/dev/null 2>&1; then
        gnome-screenshot -w -f "$out" 2>/dev/null || \
            gnome-screenshot -f "$out" 2>/dev/null
        return
    fi
    if command -v import >/dev/null 2>&1; then
        # Wait for the gk window to register, then capture it.
        local win
        win=$(xdotool search --name "OpenGOAL" 2>/dev/null | head -1)
        if [ -n "$win" ]; then
            import -window "$win" "$out" 2>/dev/null && return
        fi
        import -window root "$out" 2>/dev/null && return
    fi
    if command -v scrot >/dev/null 2>&1; then
        scrot "$out" 2>/dev/null && return
    fi
    return 1
}

# Per-second state-sample loop: meminfo, /proc stats, currently last
# few trace lines. Cheap, lets us reconstruct timing.
sample_state() {
    local n=$1
    local sample="$ORACLE_DIR/state-samples/t-$(printf '%04d' "$n").json"
    if ! kill -0 "$GK_PID" 2>/dev/null; then echo "  gk exited"; return 1; fi
    local rss vsz
    read rss vsz < <(ps -o rss=,vsz= -p "$GK_PID" 2>/dev/null || echo "0 0")
    local last_line
    last_line=$(tail -1 "$TRACE" 2>/dev/null | sed 's/"/\\"/g' | tr -d '\n')
    cat > "$sample" <<EOF
{
  "t_seconds": $n,
  "gk_pid": $GK_PID,
  "rss_kb": ${rss:-0},
  "vsz_kb": ${vsz:-0},
  "trace_tail": "$last_line"
}
EOF
}

# Cap: 10 minutes wall clock. Title is usually visible within ~60s; we
# go longer to also capture menu entry.
MAX_SEC=600
echo "== watching trace for milestones (up to ${MAX_SEC}s) =="

t0=$(date +%s)
n=0
while :; do
    now=$(date +%s)
    elapsed=$((now - t0))
    if [ "$elapsed" -ge "$MAX_SEC" ]; then
        echo "  hit ${MAX_SEC}s cap"
        break
    fi
    if ! kill -0 "$GK_PID" 2>/dev/null; then
        echo "  gk exited at t=${elapsed}s"
        break
    fi
    # Probe for each milestone we haven't yet seen.
    all_seen=1
    for m in "${MILESTONES[@]}"; do
        if [ -z "${SEEN[$m]:-}" ]; then
            all_seen=0
            if grep -qE "$m" "$TRACE" 2>/dev/null; then
                SEEN[$m]="$elapsed"
                slug=$(echo "$m" | tr '[:upper:] ' '[:lower:]_' | tr -dc 'a-z0-9_-')
                shot="$ORACLE_DIR/desktop-shot-${slug}.png"
                screencap_desktop "$shot" && \
                    echo "  [${elapsed}s] ✓ milestone hit: '$m' → screencap $shot" || \
                    echo "  [${elapsed}s] ✓ milestone hit: '$m' (screencap unavailable)"
                # Aliases: when title hits, also snapshot as the canonical
                # reference the autoport compares against.
                if [ "$m" = "engine: state=title" ] && [ -f "$shot" ]; then
                    cp "$shot" "$ORACLE_DIR/jak1-title.png"
                fi
            fi
        fi
    done
    sample_state "$n"; n=$((n + 1))
    [ "$all_seen" -eq 1 ] && [ "$elapsed" -ge 60 ] && {
        echo "  all milestones observed; capturing another 30s of normal play then stopping"
        sleep 30
        break
    }
    sleep 1
done

# 4. Clean shutdown.
echo "== stopping gk =="
kill -TERM "$GK_PID" 2>/dev/null || true
sleep 3
kill -KILL "$GK_PID" 2>/dev/null || true
wait "$GK_PID" 2>/dev/null || true
trap - EXIT

# 5. Write the summary JSON.
echo "== writing summary =="
$HOME/.venv/autoport/bin/python <<PYEOF
import json, os
seen = {}
EOF_LINES=open("$TRACE").read().count('\n')
milestones = [$(for m in "${MILESTONES[@]}"; do printf '"%s",' "$m"; done)]
for m in milestones:
    t = "${SEEN[\"X\"]:-}"
    # The shell-side associative array isn't accessible from python; reread.
seen_text = """$(declare -p SEEN 2>/dev/null)"""
import re
for line in seen_text.split('\n'):
    mo = re.match(r'\s*\[(.+?)\]="(\d+)"', line)
    if mo: seen[mo.group(1).strip("\"'")] = int(mo.group(2))
out = {
    "captured_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
    "iso_dir": "$ISO_DIR",
    "trace_lines": EOF_LINES,
    "trace_path": "$TRACE",
    "milestones_seen": seen,
    "milestones_missing": [m for m in milestones if m not in seen],
    "symbols_file": "$ORACLE_DIR/jak1-desktop-syms.txt",
    "symbol_count": int(open("$ORACLE_DIR/jak1-desktop-syms.txt").read().count("\n")),
    "state_samples_dir": "$ORACLE_DIR/state-samples",
}
with open("$SUMMARY", "w") as f:
    json.dump(out, f, indent=2)
print(f"  summary written: $SUMMARY")
print(f"  trace lines: {EOF_LINES}")
print(f"  milestones seen: {len(seen)}/{len(milestones)}")
for m in milestones:
    mark = "✓" if m in seen else "✗"
    t = seen.get(m, "?")
    print(f"    {mark} {m}  (t={t}s)")
PYEOF

echo
echo "== oracle capture complete =="
echo "   $ORACLE_DIR/"
ls -la "$ORACLE_DIR/" 2>/dev/null
