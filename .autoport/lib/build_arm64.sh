#!/usr/bin/env bash
# Shared incremental AArch64 build entry point; never configures a tree.
# Android APK, Android standalone and GNU/Linux qemu builds have distinct ABIs.
# Usage: build_arm64.sh [--dir build-android|build-arm64-android|build-arm64-linux]
#                      [--target TARGET ...] [-j [N]] [other cmake --build options]
# Default options: --target gk -j. Explicit options are forwarded unchanged.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"
DIR=build-android
if [[ ${1:-} == --dir ]]; then
    [[ $# -ge 2 ]] || { echo 'build_arm64: --dir requires a value' >&2; exit 2; }
    DIR=$2
    shift 2
fi
case "$DIR" in
    build-android|build-arm64-android) PLATFORM=Android ;;
    build-arm64-linux) PLATFORM=Linux ;;
    *) echo "build_arm64: unsupported tree $DIR (Android and GNU/Linux must remain separate)" >&2; exit 2 ;;
esac
[[ -f "$DIR/CMakeCache.txt" && -f "$DIR/build.ninja" ]] || {
    echo "build_arm64: $DIR is not configured; use its configure script first" >&2; exit 2;
}
# Read the generated toolchain identity, not the directory name alone.
shopt -s nullglob
SYSTEM_FILES=("$DIR"/CMakeFiles/*/CMakeSystem.cmake)
[[ ${#SYSTEM_FILES[@]} -gt 0 ]] || { echo 'build_arm64: toolchain identity missing' >&2; exit 2; }
for system_file in "${SYSTEM_FILES[@]}"; do
    grep -Eq "^set\\(CMAKE_SYSTEM_NAME \"$PLATFORM\"\\)" "$system_file" &&
    grep -Eq '^set\(CMAKE_SYSTEM_PROCESSOR "(aarch64|arm64)"\)' "$system_file" || {
        echo "build_arm64: incompatible toolchain in $system_file" >&2; exit 2;
    }
done
# A broken deps log cannot be used as the starting point for another build.
deps_ok() {
    local result
    result=$(ninja -C "$DIR" -t deps 2>&1 >/dev/null) || return 1
    [[ "$result" != *'premature end'* && "$result" != *'bad deps log'* ]]
}
if ! deps_ok; then
    ninja -C "$DIR" -t recompact
    deps_ok || { echo 'build_arm64: dependency log still corrupt after recompact' >&2; exit 3; }
fi
[[ $# -gt 0 ]] || set -- --target gk -j
printf 'build_arm64: tree=%s platform=%s\n' "$DIR" "$PLATFORM" >&2
exec cmake --build "$DIR" "$@"
