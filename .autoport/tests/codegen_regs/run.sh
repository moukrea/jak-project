#!/usr/bin/env bash
# perf-codegen-arm64-regs test runner. Builds the host counter (count-bin) from
# game/system/codegen_arm64_regs.h — the SAME header the engine scans on the
# device — and runs verify.py, which checks the shipped bundle against the
# goalc dump and cross-checks the counts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
mkdir -p "${BUILD_DIR}"

g++ -O2 -std=c++17 -I"${REPO_ROOT}" "${SCRIPT_DIR}/count.cpp" -o "${BUILD_DIR}/count-bin"

exec python3 "${SCRIPT_DIR}/verify.py" \
  --dump "${REPO_ROOT}/out/jak1/codegen-regs" \
  --pack "${REPO_ROOT}/android/app/src/jak1/assets-slim/bundle/jak1_cgo.zip" \
  --count-bin "${BUILD_DIR}/count-bin" \
  --log "${BUILD_DIR}/verify.log" \
  "$@"
