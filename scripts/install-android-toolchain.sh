#!/usr/bin/env bash
# install-android-toolchain.sh — host-side toolchain installer for the
# OpenGOAL Android port (autoport phases 12+).
#
# Installs (idempotent):
#   - OpenJDK 17 (Fedora package; requires sudo)
#   - Android SDK cmdline-tools (downloaded to ~/Android)
#   - SDK packages: platform-tools, platforms;android-34, build-tools;34.0.0
#   - System image for the smoke-test emulator (arm64-v8a)
#   - A named AVD (opengoal_arm64) ready to boot
#   - Gradle 8.7
#
# The Android NDK r27c at ~/Android/android-ndk-r27c is assumed already
# installed (from earlier autoport work). The script verifies and emits
# the canonical env in ~/.opengoal-android-env.sh so the validators can
# `source` it without depending on shell startup files.
#
# Usage:
#   ./scripts/install-android-toolchain.sh           # full install
#   ./scripts/install-android-toolchain.sh --check   # report only, no install
#
# This script DOES use `sudo` for one step (installing JDK via dnf).
# Everything else lands under $HOME/Android and is user-owned.

set -euo pipefail

# ---- Configuration ---------------------------------------------------------

ANDROID_ROOT="${ANDROID_ROOT:-$HOME/Android}"
CMDLINE_TOOLS_VERSION="11076708"  # latest stable as of NDK r27c era
GRADLE_VERSION="8.7"
SDK_PLATFORM="34"
SDK_BUILD_TOOLS="34.0.0"
NDK_NAME="android-ndk-r27c"
AVD_NAME="opengoal_arm64"
SYSTEM_IMAGE="system-images;android-${SDK_PLATFORM};google_apis;arm64-v8a"

ENV_FILE="$HOME/.opengoal-android-env.sh"

# ---- Helpers ---------------------------------------------------------------

GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[android-toolchain]${NC} $*"; }
warn() { echo -e "${YELLOW}[android-toolchain]${NC} $*"; }
fail() { echo -e "${RED}[android-toolchain] $*${NC}" >&2; exit 1; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then
    CHECK_ONLY=1
fi

# ---- Pre-flight ------------------------------------------------------------

require_cmd curl
require_cmd unzip
require_cmd sha256sum

mkdir -p "$ANDROID_ROOT"

# ---- 1. JDK 17 -------------------------------------------------------------

JAVA_OK=0
if command -v java >/dev/null 2>&1; then
    JV=$(java -version 2>&1 | head -1 | grep -oE '"[0-9]+(\.[0-9]+)*"' | tr -d '"' | head -1)
    JV_MAJOR=${JV%%.*}
    if [ "${JV_MAJOR:-0}" -ge 17 ]; then
        log "JDK already installed: $JV"
        JAVA_OK=1
    else
        warn "JDK $JV is too old; need 17+"
    fi
fi

# Fedora 43 retired java-17-openjdk-devel; pick the newest LTS the host
# repos actually ship. AGP 8.x + Gradle 8.7 work on JDK 17 or JDK 21.
# JDK 25/latest are too new for current AGP — prefer 21 LTS when available.
#
# IMPORTANT: don't use `dnf list available` to probe — it triggers a full
# repo metadata refresh which can silently block for many minutes while
# gnome-software or packagekit hold the dnf lock. Instead we walk the
# candidate list and just try the install; dnf itself fails fast on a
# missing package, with visible output.
JDK_CANDIDATES=(
    java-21-openjdk-devel       # LTS, AGP 8.5+ compatible — preferred
    java-17-openjdk-devel       # older LTS, kept on F39-F42
    java-25-openjdk-devel       # current non-LTS
    java-latest-openjdk-devel   # rolling-latest, last resort
)

try_install_jdk() {
    local pkg="$1"
    log "Trying $pkg via dnf (sudo)…"
    if [ "$(id -u)" -ne 0 ]; then
        sudo dnf install -y "$pkg"
    else
        dnf install -y "$pkg"
    fi
}

if [ "$JAVA_OK" -eq 0 ] && [ "$CHECK_ONLY" -eq 0 ]; then
    INSTALLED=0
    for cand in "${JDK_CANDIDATES[@]}"; do
        if try_install_jdk "$cand"; then
            log "Installed: $cand"
            INSTALLED=1
            break
        else
            warn "$cand not available, trying next…"
        fi
    done
    [ "$INSTALLED" -eq 1 ] || fail "no java-*-openjdk-devel package available via dnf"
    # Refresh PATH detection now that javac/java are installed.
    hash -r 2>/dev/null || true
    JAVA_OK=1
fi

# Locate JAVA_HOME for the env file.
if [ "$JAVA_OK" -eq 1 ]; then
    JAVA_BIN=$(readlink -f "$(command -v java)")
    JAVA_HOME_GUESS=$(dirname "$(dirname "$JAVA_BIN")")
    # On Fedora's openjdk layout, JAVA_HOME is one level up from bin/.
    if [ ! -x "$JAVA_HOME_GUESS/bin/javac" ]; then
        # Fallback: find via rpm.
        if command -v rpm >/dev/null 2>&1; then
            CAND=$(rpm -ql java-17-openjdk-devel 2>/dev/null | grep -E '/javac$' | head -1)
            [ -n "$CAND" ] && JAVA_HOME_GUESS=$(dirname "$(dirname "$CAND")")
        fi
    fi
fi

# ---- 2. NDK presence check -------------------------------------------------

NDK_PATH="$ANDROID_ROOT/$NDK_NAME"
if [ -d "$NDK_PATH" ]; then
    log "NDK present: $NDK_PATH"
elif [ -n "${ANDROID_NDK_HOME:-}" ] && [ -d "$ANDROID_NDK_HOME" ]; then
    NDK_PATH="$ANDROID_NDK_HOME"
    log "NDK present (via env): $NDK_PATH"
else
    fail "NDK r27c not found. Expected at $ANDROID_ROOT/$NDK_NAME (or set ANDROID_NDK_HOME)."
fi

# ---- 3. cmdline-tools ------------------------------------------------------

CMDLINE_DIR="$ANDROID_ROOT/cmdline-tools/latest"
if [ -x "$CMDLINE_DIR/bin/sdkmanager" ]; then
    log "cmdline-tools already installed at $CMDLINE_DIR"
elif [ "$CHECK_ONLY" -eq 1 ]; then
    warn "cmdline-tools missing — would install"
else
    log "Downloading Android cmdline-tools $CMDLINE_TOOLS_VERSION…"
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    ZIP="$TMP/cmdline-tools.zip"
    URL="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"
    curl -fsSL "$URL" -o "$ZIP" || fail "download failed: $URL"
    unzip -q "$ZIP" -d "$TMP/extracted"
    mkdir -p "$ANDROID_ROOT/cmdline-tools"
    rm -rf "$CMDLINE_DIR"
    # The zip extracts to a 'cmdline-tools/' dir; we want it under .../cmdline-tools/latest/.
    mv "$TMP/extracted/cmdline-tools" "$CMDLINE_DIR"
fi

SDKMANAGER="$CMDLINE_DIR/bin/sdkmanager"
AVDMANAGER="$CMDLINE_DIR/bin/avdmanager"

# ---- 4. SDK packages -------------------------------------------------------

if [ -x "$SDKMANAGER" ] && [ "$CHECK_ONLY" -eq 0 ]; then
    export JAVA_HOME="${JAVA_HOME:-$JAVA_HOME_GUESS}"
    export ANDROID_HOME="$ANDROID_ROOT"
    export ANDROID_SDK_ROOT="$ANDROID_HOME"

    log "Accepting Android SDK licenses…"
    yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true

    log "Installing SDK packages (platform-tools, platforms;android-${SDK_PLATFORM}, build-tools;${SDK_BUILD_TOOLS})…"
    "$SDKMANAGER" --install \
        "platform-tools" \
        "platforms;android-${SDK_PLATFORM}" \
        "build-tools;${SDK_BUILD_TOOLS}" \
        >/dev/null

    log "Installing emulator + arm64 system image (used for smoke test only — slow on x86 hosts)…"
    "$SDKMANAGER" --install \
        "emulator" \
        "$SYSTEM_IMAGE" \
        >/dev/null
elif [ "$CHECK_ONLY" -eq 1 ]; then
    for pkg in platform-tools "platforms;android-${SDK_PLATFORM}" "build-tools;${SDK_BUILD_TOOLS}"; do
        case "$pkg" in
            platform-tools)
                [ -x "$ANDROID_ROOT/platform-tools/adb" ] && log "ok: $pkg" || warn "missing: $pkg"
                ;;
            "platforms;android-${SDK_PLATFORM}")
                [ -d "$ANDROID_ROOT/platforms/android-${SDK_PLATFORM}" ] && log "ok: $pkg" || warn "missing: $pkg"
                ;;
            "build-tools;${SDK_BUILD_TOOLS}")
                [ -d "$ANDROID_ROOT/build-tools/${SDK_BUILD_TOOLS}" ] && log "ok: $pkg" || warn "missing: $pkg"
                ;;
        esac
    done
fi

# ---- 5. AVD ----------------------------------------------------------------

if [ -x "$AVDMANAGER" ] && [ "$CHECK_ONLY" -eq 0 ]; then
    if "$AVDMANAGER" list avd 2>/dev/null | grep -q "Name: $AVD_NAME"; then
        log "AVD '$AVD_NAME' already exists"
    else
        log "Creating AVD '$AVD_NAME' from $SYSTEM_IMAGE…"
        echo "no" | "$AVDMANAGER" create avd \
            -n "$AVD_NAME" \
            -k "$SYSTEM_IMAGE" \
            -d "pixel_6" \
            --force >/dev/null || warn "AVD creation failed; smoke tests will skip emulator"
    fi
fi

# ---- 6. Gradle -------------------------------------------------------------

GRADLE_DIR="$ANDROID_ROOT/gradle-${GRADLE_VERSION}"
if [ -x "$GRADLE_DIR/bin/gradle" ]; then
    log "Gradle ${GRADLE_VERSION} already installed at $GRADLE_DIR"
elif [ "$CHECK_ONLY" -eq 1 ]; then
    warn "Gradle ${GRADLE_VERSION} missing — would install"
else
    log "Downloading Gradle ${GRADLE_VERSION}…"
    TMP2=$(mktemp -d)
    ZIP2="$TMP2/gradle.zip"
    URL2="https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip"
    curl -fsSL "$URL2" -o "$ZIP2" || fail "download failed: $URL2"
    unzip -q "$ZIP2" -d "$ANDROID_ROOT"
    rm -rf "$TMP2"
fi

# ---- 7. Emit env file ------------------------------------------------------

if [ "$CHECK_ONLY" -eq 0 ]; then
    # Re-resolve JAVA_HOME after dnf install, since the env may not have
    # been updated. Prefer JAVA_HOME_GUESS (from `java` on PATH after install),
    # fall back to the highest /usr/lib/jvm/java-*-openjdk dir.
    if [ -z "${JAVA_HOME_GUESS:-}" ] || [ ! -x "${JAVA_HOME_GUESS}/bin/javac" ]; then
        FALLBACK_JH=$(ls -d /usr/lib/jvm/java-*-openjdk 2>/dev/null \
            | grep -vE 'java-(25|26|latest)' \
            | sort -V | tail -1)
        # If only the brand-new ones exist, take whatever is there.
        [ -z "$FALLBACK_JH" ] && FALLBACK_JH=$(ls -d /usr/lib/jvm/java-*-openjdk 2>/dev/null | sort -V | tail -1)
        [ -n "$FALLBACK_JH" ] && JAVA_HOME_GUESS="$FALLBACK_JH"
    fi

    log "Writing $ENV_FILE (JAVA_HOME=${JAVA_HOME_GUESS:-<unresolved>})"
    cat > "$ENV_FILE" <<EOF
# Generated by scripts/install-android-toolchain.sh — source for Android builds.
export JAVA_HOME="${JAVA_HOME_GUESS:-/usr/lib/jvm/java-21-openjdk}"
export ANDROID_HOME="$ANDROID_ROOT"
export ANDROID_SDK_ROOT="$ANDROID_ROOT"
export ANDROID_NDK_HOME="$NDK_PATH"
export GRADLE_HOME="$GRADLE_DIR"
export PATH="\$JAVA_HOME/bin:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/emulator:\$GRADLE_HOME/bin:\$PATH"
EOF
    chmod +x "$ENV_FILE"
fi

# ---- 8. Verification -------------------------------------------------------

# shellcheck source=/dev/null
. "$ENV_FILE" 2>/dev/null || true

log "Verifying tool versions:"
java -version 2>&1 | head -1 | sed 's/^/  java: /'
"$ANDROID_ROOT/platform-tools/adb" --version 2>/dev/null | head -1 | sed 's/^/  adb:  /' || warn "adb not found"
"$ANDROID_ROOT/build-tools/${SDK_BUILD_TOOLS}/aapt2" version 2>/dev/null | head -1 | sed 's/^/  aapt2: /' || warn "aapt2 not found"
"$ANDROID_ROOT/build-tools/${SDK_BUILD_TOOLS}/apksigner" version 2>/dev/null | head -1 | sed 's/^/  apksigner: /' || warn "apksigner not found"
"$GRADLE_DIR/bin/gradle" --version 2>/dev/null | grep -E '^Gradle' | head -1 | sed 's/^/  /' || warn "gradle not found"
"$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android29-clang" --version 2>&1 | head -1 | sed 's/^/  ndk:  /' || warn "NDK clang not found"

log "Done. To use in your current shell:  source $ENV_FILE"
log "The autoport validators source it automatically."
