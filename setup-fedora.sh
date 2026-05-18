#!/usr/bin/env bash
# setup-fedora.sh — one-shot system setup for the autoport orchestrator.
# Run with: sudo ./setup-fedora.sh
# Tested on Fedora 40+. For Fedora 39 or older, some package names may differ.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (sudo ./setup-fedora.sh)" >&2
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

echo "=========================================="
echo "  Autoport setup for Fedora"
echo "  Target user: $REAL_USER ($REAL_HOME)"
echo "=========================================="

# --- 1. System packages ---
echo
echo "[1/6] Installing system packages via dnf..."
dnf install -y \
    @development-tools \
    cmake \
    ninja-build \
    nasm \
    clang \
    clang-tools-extra \
    lld \
    git \
    git-lfs \
    tmux \
    jq \
    yq \
    curl \
    wget \
    unzip \
    python3 \
    python3-pip \
    python3-virtualenv \
    qemu-user-static \
    qemu-user-binfmt \
    qemu-system-aarch64 \
    mesa-libGL-devel \
    mesa-libEGL-devel \
    pulseaudio-libs-devel \
    SDL2-devel \
    openssl-devel \
    zlib-devel \
    libzstd-devel \
    nodejs \
    npm

# --- 2. AArch64 cross-compilation toolchain ---
echo
echo "[2/6] Installing AArch64 cross-compiler..."
dnf install -y \
    gcc-aarch64-linux-gnu \
    gcc-c++-aarch64-linux-gnu \
    binutils-aarch64-linux-gnu \
    glibc-static \
    || {
        echo "Some AArch64 packages unavailable on this Fedora release."
        echo "Trying alternate names..."
        dnf install -y \
            gcc-c++-aarch64-linux-gnu \
            cross-binutils-common \
            || true
    }

# --- 3. Register qemu-user binfmt handlers so we can run aarch64 ELFs natively ---
echo
echo "[3/6] Registering qemu binfmt handlers..."
systemctl enable --now systemd-binfmt.service || true
# Verify
if [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
    echo "WARNING: qemu-aarch64 binfmt not registered. You may need to reboot."
fi

# --- 4. Claude Code CLI ---
echo
echo "[4/6] Installing/updating Claude Code..."
sudo -u "$REAL_USER" npm config set prefix "$REAL_HOME/.npm-global" || true
sudo -u "$REAL_USER" bash -c "
    export PATH=\"$REAL_HOME/.npm-global/bin:\$PATH\"
    npm install -g @anthropic-ai/claude-code
    claude --version
"

# Make sure ~/.npm-global/bin is on PATH for the user
if ! sudo -u "$REAL_USER" grep -q 'npm-global/bin' "$REAL_HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$REAL_HOME/.bashrc"
    echo "Added ~/.npm-global/bin to PATH in .bashrc"
fi

# Verify version >= 2.1.139 (required for /goal and current hook schema)
INSTALLED=$(sudo -u "$REAL_USER" bash -c "
    export PATH=\"$REAL_HOME/.npm-global/bin:\$PATH\"
    claude --version
" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
echo "Claude Code installed: $INSTALLED"

# --- 5. Python venv for orchestrator ---
echo
echo "[5/6] Setting up Python venv at $REAL_HOME/.venv/autoport..."
sudo -u "$REAL_USER" python3 -m venv "$REAL_HOME/.venv/autoport"
sudo -u "$REAL_USER" "$REAL_HOME/.venv/autoport/bin/pip" install --upgrade pip
sudo -u "$REAL_USER" "$REAL_HOME/.venv/autoport/bin/pip" install \
    pyyaml \
    requests \
    rich

# --- 6. Android NDK (optional, only needed for phases 10-11) ---
echo
echo "[6/6] Android NDK..."
NDK_DIR="$REAL_HOME/Android/android-ndk-r27c"
if [ -d "$NDK_DIR" ]; then
    echo "Android NDK already present at $NDK_DIR"
else
    read -p "Download Android NDK r27c (~1.2GB)? [y/N] " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        sudo -u "$REAL_USER" mkdir -p "$REAL_HOME/Android"
        sudo -u "$REAL_USER" bash -c "
            cd '$REAL_HOME/Android'
            wget -q --show-progress https://dl.google.com/android/repository/android-ndk-r27c-linux.zip
            unzip -q android-ndk-r27c-linux.zip
            rm android-ndk-r27c-linux.zip
        "
        if ! sudo -u "$REAL_USER" grep -q 'ANDROID_NDK_HOME' "$REAL_HOME/.bashrc" 2>/dev/null; then
            echo "export ANDROID_NDK_HOME=$NDK_DIR" >> "$REAL_HOME/.bashrc"
        fi
        echo "NDK installed at $NDK_DIR"
    else
        echo "Skipped NDK. You can install it later for phases 10-11."
    fi
fi

# --- Final ---
echo
echo "=========================================="
echo "  Setup complete."
echo "=========================================="
echo
echo "Next steps:"
echo "  1. Re-login or run: source ~/.bashrc"
echo "  2. cd into your forked jak-project repo"
echo "  3. Run: ./install.sh"
echo "  4. Run: claude  (one-time, to accept workspace trust dialog, then /quit)"
echo "  5. Run: ./launch.sh"
echo
echo "Dedicated-laptop tip: disable lid-close suspend so the run survives"
echo "you closing the lid (otherwise the orchestrator pauses with the OS):"
echo
echo "  # GNOME (most common Fedora desktop):"
echo "  gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action 'nothing'"
echo "  gsettings set org.gnome.settings-daemon.plugins.power lid-close-battery-action 'nothing'"
echo
echo "  # Also at the systemd level (for redundancy):"
echo "  sudo sed -i 's/^#*HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf"
echo "  sudo sed -i 's/^#*HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf"
echo "  sudo systemctl restart systemd-logind"
echo
echo "If Claude Code is not yet authenticated, run 'claude' once interactively"
echo "to complete the OAuth login before launching the orchestrator."
