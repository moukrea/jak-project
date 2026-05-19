#!/usr/bin/env bash
# Sourced by autoport phase 12+ validators. Loads the host Android
# toolchain env produced by scripts/install-android-toolchain.sh.
#
# Validators rely on these to invoke aapt2/apksigner/gradle/adb/emulator
# without depending on the user's interactive shell startup files.

# Prefer the install-script-generated env if present.
if [ -f "$HOME/.opengoal-android-env.sh" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.opengoal-android-env.sh"
fi

# Sensible defaults so we still produce a coherent error if the user
# hasn't run the install script.
: "${ANDROID_HOME:=$HOME/Android}"
: "${ANDROID_SDK_ROOT:=$ANDROID_HOME}"
: "${ANDROID_NDK_HOME:=$ANDROID_HOME/android-ndk-r27c}"
: "${GRADLE_HOME:=$ANDROID_HOME/gradle-8.7}"

export ANDROID_HOME ANDROID_SDK_ROOT ANDROID_NDK_HOME GRADLE_HOME

# Make sure cmdline-tools/platform-tools/emulator/build-tools/gradle are on PATH.
_BT_DIR=$(find "$ANDROID_HOME/build-tools" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort -V | tail -1)
export PATH="\
${ANDROID_HOME}/cmdline-tools/latest/bin:\
${ANDROID_HOME}/platform-tools:\
${ANDROID_HOME}/emulator:\
${_BT_DIR}:\
${GRADLE_HOME}/bin:\
${PATH}"

require_android_tool() {
    # Usage: require_android_tool <name> <hint>
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "FAIL: required tool '$1' not on PATH after sourcing android-env.sh" >&2
        echo "      $2" >&2
        return 1
    fi
    return 0
}
