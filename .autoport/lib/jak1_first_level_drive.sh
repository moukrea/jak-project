#!/usr/bin/env bash
# Phase 31 (autoport): drive jak1 from the title screen through the menu
# to the first level (training / Geyser Rock). Argument: the path to the
# active logcat tail file that the validator already populates.
#
# The runtime-side state machine for these transitions lives in
# game/kernel/jak1/android_bridge.cpp:weak_jak1_input_event — that
# function gates the title→progress and progress→training transitions
# on the correct buttons. This script's only job is to dispatch the
# `adb shell input tap` calls and wait for each state to land in
# logcat. It does NOT decide the destination state names; the bridge
# does, using the upstream symbols from goal_src/jak1/.
#
# Why a separate script rather than inlining into the validator:
#   * the brief lists it as deliverable #1;
#   * future phases (auto-saves, level warp, opening cinematic) extend
#     the same drive without touching the validator surface;
#   * the script is bash-only — no python — so it runs even when the
#     validator host strips PIL/Pillow.

set -uo pipefail

LOGCAT_LOG="${1:?usage: jak1_first_level_drive.sh <logcat-log-path>}"

log() {
    echo "  [drive] $*"
}

die() {
    echo "  [drive] FAIL: $*" >&2
    exit 1
}

# Wait for a regex to appear in the tailed logcat. The validator's
# own device_wait_for_marker lives behind device-validate.sh which we
# don't source here (the drive script must be runnable with just adb
# on PATH). Inlined, but identical semantics.
wait_for() {
    local regex="$1"
    local timeout_s="${2:-60}"
    local deadline=$(( $(date +%s) + timeout_s ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        if grep -qE "$regex" "$LOGCAT_LOG" 2>/dev/null; then
            local hit
            hit=$(grep -m1 -E "$regex" "$LOGCAT_LOG")
            log "matched '$regex' -> $hit"
            return 0
        fi
        sleep 1
    done
    return 1
}

# Resolve the START-button hitbox emitted by TouchControlsView.onSizeChanged
# (see android/app/src/main/java/.../TouchControlsView.java). The line is
#   touch-hitbox: start_button at (X,Y)-(W,H)
# `onSizeChanged` fires multiple times during Activity setup (initial
# measure, post-SDL-surface resize). Each pass re-emits the line — only
# the LAST one reflects the layout the user actually sees, so we tail
# rather than head. The reported (X,Y) is in view/device pixels and
# matches `adb shell input tap` coordinates 1:1.
resolve_hitbox_start() {
    local line
    line=$(grep -oE 'touch-hitbox: start_button at \([0-9]+,[0-9]+\)' "$LOGCAT_LOG" 2>/dev/null | tail -1 || true)
    if [ -n "$line" ]; then
        local pair
        pair=$(echo "$line" | grep -oE '\([0-9]+,[0-9]+\)' | head -1 | tr -d '()')
        TAP_START_X=${pair%,*}
        TAP_START_Y=${pair#*,}
        log "START hitbox from log: ($TAP_START_X, $TAP_START_Y)"
        return 0
    fi
    return 1
}

# Read the actual View dimensions the TouchControlsView reports via the
# "touch down view=WxH ..." log line — if any have been emitted. This is
# the same coordinate space the START hitbox above is expressed in and
# is robust across landscape/portrait activity layouts. Fallback: parse
# `wm size` which on the test device reports "Physical size: 1080x2400"
# in the natural orientation. `adb shell input tap` operates in those
# same natural-orientation pixels regardless of view rotation.
resolve_screen_size() {
    local line size
    # Prefer the Java side's view-dim log if present.
    line=$(grep -oE 'touch down view=[0-9]+x[0-9]+' "$LOGCAT_LOG" 2>/dev/null | tail -1 || true)
    if [ -n "$line" ]; then
        size=$(echo "$line" | grep -oE '[0-9]+x[0-9]+')
        SCREEN_W=${size%x*}
        SCREEN_H=${size#*x}
        log "view size from log: ${SCREEN_W}x${SCREEN_H}"
        return 0
    fi
    size=$(adb shell wm size 2>/dev/null | grep -oE '[0-9]+x[0-9]+' | head -1)
    if [ -z "$size" ]; then
        SCREEN_W=1080
        SCREEN_H=2400
        log "wm size unavailable, fallback ${SCREEN_W}x${SCREEN_H}"
        return 0
    fi
    SCREEN_W=${size%x*}
    SCREEN_H=${size#*x}
    log "wm size: ${SCREEN_W}x${SCREEN_H} (using as natural orientation)"
}

# ---------------------------------------------------------------------------
# Step 1: wait for the title state.
# ---------------------------------------------------------------------------
log "waiting for engine: state=title (budget 60s)"
wait_for 'engine: state=title' 60 \
    || die "kernel never reached title state — phase-30 regression?"

# Give the title screen a beat to settle. The renderer's first frame can
# lag the dispatcher's title emission by a frame or two; tapping before
# the input-audio subsystem has fully initialised drops the event.
sleep 3

resolve_screen_size
resolve_hitbox_start || {
    TAP_START_X=$((SCREEN_W / 2))
    TAP_START_Y=$((SCREEN_H * 80 / 100))
    log "no START hitbox in log; falling back to ($TAP_START_X, $TAP_START_Y)"
}

# ---------------------------------------------------------------------------
# Step 2: tap START, wait for progress.
# ---------------------------------------------------------------------------
log "tap START at ($TAP_START_X, $TAP_START_Y)"
adb shell input tap "$TAP_START_X" "$TAP_START_Y" \
    || die "adb input tap failed (device disconnected?)"

wait_for 'engine: state=progress' 30 \
    || die "title -> progress did not happen on START tap"

# Small pause: real menus auto-advance through any opening dialog
# (progress.gc has a 1-frame transient before the New Game cursor is
# selectable). The bridge advances immediately on SOUTH, so the pause
# also prevents two button events being collapsed by adb's tap timing.
sleep 2

# ---------------------------------------------------------------------------
# Step 3: tap SOUTH (× face button), wait for the level state.
#
# SOUTH hitbox in TouchControlsView is at (faceCx, faceCy + faceArm) with
# faceCx = w * 0.775 and faceCy + faceArm = h*0.75 + h*0.05 = h*0.80.
# Java logs only the START hitbox; we compute SOUTH from screen geometry.
# Hit radius is unit*0.07 of min(w,h), which on a 2300x1080 landscape is
# ~75 px — the tap target is generously sized so a few pixels of drift
# from layout differences are harmless.
# ---------------------------------------------------------------------------
TAP_SOUTH_X=$(( SCREEN_W * 775 / 1000 ))
TAP_SOUTH_Y=$(( SCREEN_H * 80 / 100 ))
log "tap SOUTH at ($TAP_SOUTH_X, $TAP_SOUTH_Y)"
adb shell input tap "$TAP_SOUTH_X" "$TAP_SOUTH_Y" \
    || die "adb input tap failed (device disconnected?)"

wait_for 'engine: state=training' 60 \
    || die "progress -> training did not happen on SOUTH tap"

log "first-level state reached: training (Geyser Rock)"
exit 0
