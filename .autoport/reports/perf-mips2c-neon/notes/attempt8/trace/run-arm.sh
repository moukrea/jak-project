#!/bin/bash
set -u
trace=.autoport/reports/perf-mips2c-neon/notes/attempt8/trace
binary=.autoport/reports/perf-mips2c-neon/notes/attempt7/block-parity-arm-gcc
qemu-aarch64 -L /usr/aarch64-linux-gnu -g 12348 "$binary" > "$trace/qemu.log" 2>&1 &
qemu_pid=$!
trap 'kill "$qemu_pid" 2>/dev/null || true' EXIT
gdb -nx -batch -x "$trace/arm.gdb" "$binary" > "$trace/arm.log" 2>&1
gdb_rc=$?
printf 'gdb_rc=%s qemu_pid=%s\n' "$gdb_rc" "$qemu_pid"
exit "$gdb_rc"
