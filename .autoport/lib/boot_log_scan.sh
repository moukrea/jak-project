#!/usr/bin/env bash
# boot_log_scan.sh — shared helper for validators to scan a captured
# logcat (the d4_run.sh BOOT_LOG output) and produce a comprehensive
# marker scoreboard + crash detection.
#
# Authored 2026-05-23 by the supervisor. Replaces the per-validator
# "grep -qE 'F DEBUG.*signal'" pattern that proved too narrow today —
# native crashes routed through Android's libsigchain (ART signal-chain
# coordinator) don't produce that exact log line, so the existing
# detection missed real crashes (1 Process-died + 80 libsigchain
# entries in a boot log my validator reported as "no crash").
#
# Usage from a validator:
#   source .autoport/lib/boot_log_scan.sh
#   boot_log_scoreboard <log-path>           # prints scoreboard table
#   boot_log_crashed   <log-path>            # exits 0 iff a crash is detected
#   boot_log_marker_count <log-path> <regex> # prints count for one marker
#
# All functions are read-only; they never modify the log or any state.

set +e  # never fail caller on a transient grep miss

# Print a comprehensive marker scoreboard for a captured logcat.
# Each marker shows its raw count, not just present/absent — this
# catches incremental progress like "gkernel: 2 → 10" that a boolean
# check misses.
boot_log_scoreboard() {
    local log="$1"
    if [ ! -s "$log" ]; then
        echo "  (boot log $log empty or missing)"
        return 1
    fi
    # TOTAL link-finish count is a single number that tracks how
    # deeply the boot has progressed through the GOAL CGO link chain.
    # Per-named-CGO markers below cover the major milestones; this
    # number catches everything else (math-camera, display, dma-*,
    # pckernel-*, etc. — boot can reach 40+ unique CGOs at full depth).
    local total_link total_unique
    total_link=$(grep -cE "link finish:" "$log" 2>/dev/null || echo 0)
    total_unique=$(grep -oE "link finish: \S+" "$log" 2>/dev/null | sort -u | wc -l)
    printf "  TOTAL link finishes: %d (%d unique CGOs linked)\n" "$total_link" "$total_unique"
    echo "  --- Boot progress markers (counts) ---"
    local markers=(
        "MainActivity onCreate done"
        "libgk.so loaded"
        "gk_sdl_main: entered"
        "goal_main: argv="
        "iop-runner: tid="
        "overlord init complete; signalling EE"
        "InitIOP OK"
        "Initialized GOAL heap"
        "Got DGO file header"
        "link finish: gcommon"
        "link finish: gkernel"
        "link finish: gstate"
        "link finish: logo"
        "engine: state="
        "android_renderer_run: entered"
        "android_renderer: sustained swap"
    )
    for m in "${markers[@]}"; do
        local c
        c=$(grep -cE "$m" "$log" 2>/dev/null || echo 0)
        printf "    %-42s %s\n" "$m" "$c"
    done
    echo "  --- Crash indicators (any > 0 = process crashed) ---"
    local crash_patterns=(
        "F DEBUG.*signal (6|11|4|7)"     # native fatal — narrow
        "F libc.*Fatal signal"           # libc-side fatal print
        "E libsigchain"                  # ART signal-chain error
        "ActivityManager: Process .*has died"
        "am_proc_died"
        "FATAL EXCEPTION"                # Java
        "jak1::InitMachine ABORT"        # D3-era dodge fingerprint
        "GK-DIAG"                        # claude's signal handler firing
    )
    for p in "${crash_patterns[@]}"; do
        local c
        c=$(grep -cE "$p" "$log" 2>/dev/null || echo 0)
        printf "    %-42s %s\n" "$p" "$c"
    done
}

# Return 0 iff the boot log shows ANY crash indicator.
# Use this in validators instead of the old narrow "F DEBUG signal" grep.
#
# Definition of "crashed":
#   - Any native fatal signal (F DEBUG / F libc) — narrow case
#   - E libsigchain (Android signal-chain error = native crash routed
#     through ART)
#   - ActivityManager: Process .* has died (unless we explicitly killed
#     it — caller should account for d4_run.sh's am force-stop)
#   - FATAL EXCEPTION (Java side)
#   - GK-DIAG dumps (claude's own signal handler firing means there
#     WAS a SIGSEGV that was caught)
#
# Returns 0 = crashed, 1 = clean.
boot_log_crashed() {
    local log="$1"
    [ -s "$log" ] || return 1   # empty log can't be inspected; not "crashed"
    grep -qE "F DEBUG.*signal (6|11|4|7)" "$log" 2>/dev/null && return 0
    grep -qE "F libc.*Fatal signal" "$log" 2>/dev/null && return 0
    grep -qE "E libsigchain" "$log" 2>/dev/null && return 0
    grep -qE "FATAL EXCEPTION" "$log" 2>/dev/null && return 0
    grep -qE "jak1::InitMachine ABORT" "$log" 2>/dev/null && return 0
    # claude's signal handler (GK-DIAG) firing also indicates a crash
    if [ "$(grep -cE 'GK-DIAG' "$log" 2>/dev/null)" -ge 10 ]; then
        return 0
    fi
    return 1
}

# Return the count of one specific marker (regex). Convenience wrapper.
boot_log_marker_count() {
    local log="$1"
    local pattern="$2"
    grep -cE "$pattern" "$log" 2>/dev/null || echo 0
}
