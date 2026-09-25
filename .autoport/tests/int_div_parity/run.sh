#!/usr/bin/env bash
# int_div_parity test runner. Builds the host generator (gen) and the arm64
# runner, generates build/cases.bin, and executes it under qemu-user or on a
# USB-attached device (never a network address).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${REPO_ROOT}"

MODE="${1:-}"
SERIAL="${2:-}"

if [[ "${MODE}" != "qemu" && "${MODE}" != "device" ]]; then
  echo "usage: $0 <qemu|device> [serial]" >&2
  exit 2
fi

if [[ "${MODE}" == "device" ]]; then
  if [[ -z "${SERIAL}" ]]; then
    echo "error: device mode requires a serial" >&2
    exit 2
  fi
  if [[ "${SERIAL}" == *:* ]]; then
    echo "error: refusing a network-style serial (contains ':'): ${SERIAL}" >&2
    exit 2
  fi
fi

NDK="${ANDROID_NDK_HOME:-/home/emeric/Android/android-ndk-r27c}"
CLANG="${NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android29-clang"
if [[ ! -x "${CLANG}" ]]; then
  echo "error: NDK clang not found at ${CLANG}" >&2
  exit 2
fi

TEST_DIR="${REPO_ROOT}/.autoport/tests/int_div_parity"
BUILD_DIR="${TEST_DIR}/build"

if [[ ! -d "${BUILD_DIR}" ]]; then
  cmake -S "${TEST_DIR}" -B "${BUILD_DIR}" -DREPO_ROOT="${REPO_ROOT}" >/dev/null
fi
( cd "${BUILD_DIR}" && make -j >/dev/null )

# bionic's libc already provides pthread; -lpthread doesn't exist as a
# separate static archive in the NDK and fails the link.
"${CLANG}" -O2 -static -o "${BUILD_DIR}/runner" "${TEST_DIR}/runner.c"

cd "${TEST_DIR}"
"${BUILD_DIR}/gen"

CASES="${BUILD_DIR}/cases.bin"
echo "int_div_cases_sha256=$(sha256sum "${CASES}" | awk '{print $1}')"

if [[ "${MODE}" == "qemu" ]]; then
  echo "int_div_mode=qemu"
  qemu-aarch64-static "${BUILD_DIR}/runner" "${CASES}"
else
  echo "int_div_mode=device"
  echo "int_div_device_serial=${SERIAL}"
  REMOTE_DIR=/data/local/tmp/int_div_parity
  adb -s "${SERIAL}" shell "mkdir -p ${REMOTE_DIR}"
  adb -s "${SERIAL}" push "${BUILD_DIR}/runner" "${REMOTE_DIR}/runner" >/dev/null
  adb -s "${SERIAL}" push "${CASES}" "${REMOTE_DIR}/cases.bin" >/dev/null
  adb -s "${SERIAL}" shell "chmod 755 ${REMOTE_DIR}/runner"
  adb -s "${SERIAL}" shell "${REMOTE_DIR}/runner ${REMOTE_DIR}/cases.bin"
fi
