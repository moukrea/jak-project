#!/usr/bin/env bash
# Grecharged-hud-jak1 round 5: pre-build ONLY the C++ trees for the new flag set
# (recharged-hud added). build.sh's own cmake+ninja step is replicated EXACTLY so the
# later ./build.sh runs find both trees up to date and only do the GOAL/CGO/APK work.
# Kept separate so GOAL edits can land while the (long) C++ rebuild runs — goalc is
# NOT invoked here, so there is no mixed-CGO race.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
source .autoport/lib/android-env.sh >/dev/null 2>&1 || true

FLAGS=( -DOG_FEAT_RECHARGED_HUD=ON
        -DOG_FEAT_GRASS_OVERHANG=OFF
        -DOG_FEAT_HD_MODELS=ON
        -DOG_FEAT_PBR=ON
        -DOG_FEAT_PHYSICS=ON
        -DOG_FEAT_VULKAN_SUPPORT=OFF )
HASH=37b4745dfd43   # sha256("hd-models,pbr,physics,recharged-hud") | cut -c1-12

echo "=== [1/2] linux-x86_64 cmake configure ==="
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release "${FLAGS[@]}" \
      "-DOG_FLAG_SET_ID=${HASH}:linux-x86_64" > .autoport/logs/rhud5-cmake-linux.log 2>&1
echo "=== [1/2] linux-x86_64 ninja gk goalc ==="
cmake --build build --target gk goalc -j"$(nproc)" > .autoport/logs/rhud5-ninja-linux.log 2>&1
echo "=== linux DONE $(date -Is) ==="

echo "=== [2/2] android-arm64 cmake configure ==="
cmake -S . -B build-android -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-29 \
  -DGOALC_BACKEND=arm64 -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  "${FLAGS[@]}" "-DOG_FLAG_SET_ID=${HASH}:android-arm64" > .autoport/logs/rhud5-cmake-android.log 2>&1
echo "=== [2/2] android-arm64 ninja gk ==="
cmake --build build-android --target gk -j"$(nproc)" > .autoport/logs/rhud5-ninja-android.log 2>&1
echo "=== android DONE $(date -Is) ==="

nm -C build-android/lib/arm64-v8a/libgk.so | grep -ci load_recharged_hud_textures || true
nm -C build/game/gk | grep -ci load_recharged_hud_textures || true
echo "=== ALL C++ PREBUILD DONE $(date -Is) ==="
