#!/usr/bin/env bash
# build.sh — unified build CLI (phase Grecharged-buildsys-flags, P1 of the build-system pillar).
#
#   ./build.sh <linux-x86_64|android-arm64|windows-x86_64> [--recharged-hud]
#              [--grass-overhang] [--hd-models] [--menu-overhaul] [--pbr] [--vulkan-support] [--yolo]
#              [--game jak1] [--no-cache] [--no-apk] [--package]
#              [--win-bin-dir <dir>]
#   --package: after the build, emit the distributable game PACKAGE + the separate
#              source-derived <game>_assets.zip under out/artifacts/.
#   --win-bin-dir: windows-x86_64 only — dir holding CI gk.exe (default out/ci/windows-x86_64).
#
# One command per target, wrapping the full pipeline (cmake + goalc CGOs + gradle APK).
# BUILD-TIME feature flags (owner 2026-07-17): a feature that is not requested is NOT in
# the build — neither in the binary (CMake -DOG_FEAT_* -> #ifdef) nor in the menus (the
# generated goal_src/jak1/pc/recharged-flags.gc defconstants make goalc skip the menu
# rows/labels/wiring entirely). --yolo = all four flags. Default = none (clean build).
# Validated features (grass base/precompute/shadow, ambient occlusion, foliage wind...)
# are ALWAYS included and are not flagged.
#
# FLAG-SET HASH (risk R1 — no mixed builds): the canonical flag set is hashed; the hash
# is embedded as "ogflags:<hash>:<target>" in BOTH the C++ binary (kboot.cpp marker via
# -DOG_FLAG_SET_ID) and the compiled CGOs (*og-flag-set-marker* via the generated GOAL
# constants). deploy_verify.sh / release_verify.sh refuse artifacts whose markers differ.
# The CGO cache below is keyed by the same hash (+ a source fingerprint).
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

usage() { sed -n '3,8p' "$0"; exit 1; }
die() { echo "[build FAIL] $*" >&2; exit 1; }
log() { echo "[build] $*"; }

# ---------------- argument parsing -> canonical flag set ----------------
[ $# -ge 1 ] || usage
TARGET="$1"; shift
case "$TARGET" in linux-x86_64|android-arm64|windows-x86_64) ;; *) die "unknown target '$TARGET' (linux-x86_64|android-arm64|windows-x86_64)";; esac
GAME="jak1"; USE_CACHE=1; BUILD_APK=1; DO_PACKAGE=0
F_HUD=0; F_OVERHANG=0; F_HDMODELS=0; F_PBR=0; F_VULKAN=0; F_DEBUG=0; F_MENUOVR=0
WIN_BIN_DIR="out/ci/windows-x86_64"
while [ $# -gt 0 ]; do
  case "$1" in
    --recharged-hud)  F_HUD=1;;
    --grass-overhang) F_OVERHANG=1;;
    --hd-models)      F_HDMODELS=1;;
    --pbr)            F_PBR=1;;
    --vulkan-support) F_VULKAN=1;;
    --debug)          F_DEBUG=1;;
    --menu-overhaul)  F_MENUOVR=1;;
    --yolo)           F_HUD=1; F_OVERHANG=1; F_HDMODELS=1; F_PBR=1; F_VULKAN=1;;
    --game)           GAME="$2"; shift;;
    --no-cache)       USE_CACHE=0;;
    --no-apk)         BUILD_APK=0;;
    --package)        DO_PACKAGE=1;;
    --win-bin-dir)    WIN_BIN_DIR="$2"; shift;;
    *) die "unknown option '$1'";;
  esac
  shift
done
[ "$GAME" = "jak1" ] || die "only jak1 is wired for now (jak2/jak3 inherit this pipeline later)"

# ---------------- ARCHITECTURE IP gate (owner 2026-08-02): HD models are ND IP ----------------
# The HD character models derive from the user's Jak 2 / Jak 3 dumps = Naughty Dog IP. Per the
# owner rule, --hd-models is POSSIBLE ONLY IF the corresponding donor dump is present. Without it
# the HD feature is UNAVAILABLE and the build must be byte-identical to a non-HD (stock) build — so
# we force the flag OFF *here*, BEFORE the canonical flag set is hashed. That makes the whole
# pipeline (flag-set hash, CMake OG_FEAT_*, recharged-flags.gc, CGO cache key, packs) a genuine
# stock build, not merely "HD compiled in but no assets". Per-game donor mapping (the ND rip source):
#   jak1 HD chars (eichar/sidekick/sage/assistant = Jak/Daxter/Samos/Keira) are ripped from the
#        Jak 2 dump (fr3_to_gltf on decompiler_out/jak2 <- iso_data/jak2) -> require iso_data/jak2.
hd_donor_dump_for_game() { case "$1" in jak1) echo "iso_data/jak2";; *) echo "";; esac; }
if [ $F_HDMODELS -eq 1 ]; then
  HD_DONOR="$(hd_donor_dump_for_game "$GAME")"
  if [ -n "$HD_DONOR" ] && \
     [ -n "$(find "$HD_DONOR" -maxdepth 2 -type f ! -name '.gitignore' -print -quit 2>/dev/null)" ]; then
    log "hd-models: donor dump '$HD_DONOR' present — HD (ND-derived) permitted for $GAME"
  else
    log "hd-models UNAVAILABLE: donor dump '${HD_DONOR:-<none for $GAME>}' absent — the HD models are"
    log "  Naughty Dog IP derived from that dump; without it the feature cannot be built or shipped."
    log "  Forcing --hd-models OFF; this build is byte-identical to a stock (non-HD) build."
    F_HDMODELS=0
  fi
fi

# Canonical (alphabetical) enabled-flag list -> flag-set hash.
FLAG_LIST=()
[ $F_DEBUG -eq 1 ]    && FLAG_LIST+=("debug")
[ $F_OVERHANG -eq 1 ] && FLAG_LIST+=("grass-overhang")
[ $F_HDMODELS -eq 1 ] && FLAG_LIST+=("hd-models")
[ $F_MENUOVR -eq 1 ]  && FLAG_LIST+=("menu-overhaul")
[ $F_PBR -eq 1 ]      && FLAG_LIST+=("pbr")
[ $F_HUD -eq 1 ]      && FLAG_LIST+=("recharged-hud")
[ $F_VULKAN -eq 1 ]   && FLAG_LIST+=("vulkan-support")
FLAG_STR=$(IFS=,; echo "${FLAG_LIST[*]-}")
FLAG_HASH=$(printf '%s' "$FLAG_STR" | sha256sum | cut -c1-12)
MARKER="ogflags:${FLAG_HASH}:${TARGET}"
log "target=$TARGET game=$GAME flags='${FLAG_STR:-<none>}' flag-set-hash=$FLAG_HASH"
log "marker: $MARKER"

b() { [ "$1" -eq 1 ] && echo "#t" || echo "#f"; }   # GOAL boolean
o() { [ "$1" -eq 1 ] && echo "ON" || echo "OFF"; }  # CMake option
PLAT_ANDROID=0; [ "$TARGET" = "android-arm64" ] && PLAT_ANDROID=1

# ---------------- 1. generate the GOAL flag constants (single source of truth) ----------------
FLAGS_GC="goal_src/${GAME}/pc/recharged-flags.gc"
cat > "$FLAGS_GC" <<EOF
;;-*-Lisp-*-
(in-package goal)
;; !!! GENERATED by build.sh (Grecharged-buildsys-flags) — do not edit by hand !!!
;; Build-time feature flags. The tracked copy is the DEFAULT (no flags, linux-x86_64)
;; configuration; ./build.sh rewrites this file per invocation. Dual plumbing: these
;; GOAL constants gate menu rows/labels/wiring at COMPILE time (off => absent from the
;; CGOs); the matching C++ paths are gated by the OG_FEAT_* CMake defines generated
;; from the same flag set. The ogflags marker must match between libgk/gk and the CGOs
;; (risk R1: mixed flag-set builds are refused by deploy_verify/release_verify).

(defglobalconstant FLAG_RECHARGED_HUD $(b $F_HUD))
(defglobalconstant FLAG_RECHARGED_HUD_N $F_HUD)
(defglobalconstant FLAG_GRASS_OVERHANG $(b $F_OVERHANG))
(defglobalconstant FLAG_GRASS_OVERHANG_N $F_OVERHANG)
(defglobalconstant FLAG_HD_MODELS $(b $F_HDMODELS))
(defglobalconstant FLAG_HD_MODELS_N $F_HDMODELS)
(defglobalconstant FLAG_PBR $(b $F_PBR))
(defglobalconstant FLAG_PBR_N $F_PBR)
(defglobalconstant FLAG_VULKAN_SUPPORT $(b $F_VULKAN))
(defglobalconstant FLAG_VULKAN_SUPPORT_N $F_VULKAN)
;; Grecharged-menu-overhaul: --debug reveals the DEBUG options category (hidden, not removed, in final
;; builds). GOAL-only flag (no C++/CMake gate needed): it seeds the runtime *debug-menus-visible?* symbol
;; which conditions ONLY the display of the DEBUG category row — the debug menu code is compiled into
;; every build regardless.
(defglobalconstant FLAG_DEBUG_MENUS $(b $F_DEBUG))
(defglobalconstant FLAG_DEBUG_MENUS_N $F_DEBUG)
;; Gmenu-flag-off: the Grecharged-menu-overhaul refonte is BROKEN (phantom params, colliding
;; bindings, displacement selector lost — owner 2026-08-04) and is compiled OUT by default.
;; OFF (default) = the pre-overhaul functional menu; --menu-overhaul = the refonte, kept only
;; for its future rework phase. GOAL-only flag (no C++/CMake gate needed).
(defglobalconstant FLAG_MENU_OVERHAUL $(b $F_MENUOVR))
(defglobalconstant FLAG_MENU_OVERHAUL_N $F_MENUOVR)
(defglobalconstant PLATFORM_ANDROID $(b $PLAT_ANDROID))
(defglobalconstant OG_FLAG_SET_MARKER "$MARKER")
EOF
log "generated $FLAGS_GC"

CMAKE_FEATURE_ARGS=(
  "-DOG_FEAT_RECHARGED_HUD=$(o $F_HUD)"
  "-DOG_FEAT_GRASS_OVERHANG=$(o $F_OVERHANG)"
  "-DOG_FEAT_HD_MODELS=$(o $F_HDMODELS)"
  "-DOG_FEAT_PBR=$(o $F_PBR)"
  "-DOG_FEAT_VULKAN_SUPPORT=$(o $F_VULKAN)"
  "-DOG_FLAG_SET_ID=${FLAG_HASH}:${TARGET}"
)

# ---------------- CGO cache (keyed by flag-set hash + source fingerprint) ----------------
# Key = flag-set hash + backend + sha256 over goal_src, the generated flags file (already
# in goal_src), the text-bank inputs and the goalc binary. Over-invalidation is safe;
# stale reuse is not.
# Grecharged-loader-packfix: *.gd (the DGO manifests) MUST be part of the key. They decide
# which objects get LINKED into each CGO, so editing one changes the output while every
# .gc byte stays identical — the cache then serves a stale CGO and the "rebuild" is a
# silent no-op. That is how mesh-browser-pc.o survived a full rebuild still unlinked.
src_fingerprint() { # $1 = goalc binary path
  { find "goal_src" "game/assets/${GAME}" -type f \( -name '*.gc' -o -name '*.gp' -o -name '*.gs' -o -name '*.gd' -o -name '*.json' \) -print0 2>/dev/null | sort -z | xargs -0 sha256sum
    sha256sum "$1"
  } | sha256sum | cut -c1-16
}

CACHE_ROOT=".autoport/cgo-cache/${GAME}"
run_goalc_iso() { # $1 = goalc, $2 = log tag ; full forced iso build into out/<game>/iso
  local goalc="$1" tag="$2" logf=".autoport/logs/build-${2}.log"
  mkdir -p .autoport/logs out/${GAME}/obj
  find "out/${GAME}/obj" -maxdepth 1 -type f \( -name '*.o' -o -name '*.go' \) -delete
  log "goalc ($tag) (make-group \"iso\" :force #t) — several minutes..."
  "$goalc" --user-auto --game "$GAME" --disable-ansi -c '(make-group "iso" :force #t)' > "$logf" 2>&1 \
    || { tail -40 "$logf" >&2; die "goalc $tag build failed (log: $logf)"; }
  grep -qE "Successfully built all [0-9]+ targets" "$logf" || { tail -40 "$logf" >&2; die "goalc $tag did not finish"; }
  log "$(grep -oE 'Successfully built all [0-9]+ targets in [0-9.]+s' "$logf" | head -1)"
}

assert_iso_set() { # $1 = dir ; 28 CGO/DGO + marker present
  local n; n=$(ls "$1"/*.CGO "$1"/*.DGO 2>/dev/null | wc -l)
  [ "$n" -eq 28 ] || die "expected 28 CGO/DGO in $1, got $n"
  local m; m=$(grep -ha -o 'ogflags:[a-zA-Z0-9:_.-]*' "$1"/GAME.CGO | head -1 || true)
  [ "$m" = "$MARKER" ] || die "CGO marker '$m' != expected '$MARKER' in $1 (mixed flag-set build?)"
}

cache_store() { # $1 = cache dir, $2 = src iso dir
  rm -rf "$1"; mkdir -p "$1"
  cp -f "$2"/*.CGO "$2"/*.DGO "$1"/
  cp -f "$2"/*.TXT "$1"/ 2>/dev/null || true
  { echo "flags=$FLAG_STR"; echo "flag_hash=$FLAG_HASH"; echo "marker=$MARKER";
    echo "date=$(date -Is)"; echo "commit=$(git rev-parse --short HEAD)"; } > "$1/CACHE_MANIFEST"
}
cache_restore() { # $1 = cache dir, $2 = dst iso dir
  mkdir -p "$2"
  cp -f "$1"/*.CGO "$1"/*.DGO "$2"/
  cp -f "$1"/*.TXT "$2"/ 2>/dev/null || true
}

# ---------------- per-target pipelines ----------------
REPORT_DIR=".autoport/reports"
mkdir -p "$REPORT_DIR"

verify_binary_flags() { # $1 = binary path (gk or libgk.so) ; symbol-level per-flag proof
  local bin="$1" s
  s=$(strings "$bin" | grep -m1 '^ogflags:' || true)
  [ "$s" = "$MARKER" ] || die "$bin marker '$s' != expected '$MARKER'"
  check() { # name, expected 0/1, pattern
    local c; c=$(strings "$bin" | grep -c -- "$3" || true)
    if [ "$2" -eq 1 ]; then [ "$c" -ge 1 ] || die "$bin: flag $1 ON but marker '$3' absent"
    else [ "$c" -eq 0 ] || die "$bin: flag $1 OFF but marker '$3' present ($c)"; fi
  }
  check grass-overhang "$F_OVERHANG" "pc-set-grass-overhang!"
  check hd-models "$F_HDMODELS" "pc-enhanced-models-available?"
  check pbr "$F_PBR" "pc-set-pbr!"
  ncheck() { # name, expected 0/1, nm symbol substring
    local c; c=$(nm -C "$bin" 2>/dev/null | grep -ci -- "$3" || true)
    if [ "$2" -eq 1 ]; then [ "$c" -ge 1 ] || die "$bin: flag $1 ON but symbol '$3' absent"
    else [ "$c" -eq 0 ] || die "$bin: flag $1 OFF but symbol '$3' present ($c)"; fi
  }
  ncheck recharged-hud "$F_HUD" "load_recharged_hud_textures"
  # vulkan.cpp is desktop-only (never in the android TU list)
  [ "$TARGET" = "linux-x86_64" ] && ncheck vulkan-support "$F_VULKAN" "gRendererVulkan" || true
  # positive controls: validated features must ALWAYS be present
  local pc; pc=$(strings "$bin" | grep -c "pc-set-recharged-grass!" || true)
  [ "$pc" -ge 1 ] || die "$bin: validated feature control pc-set-recharged-grass! missing"
  log "binary flag proof OK: $bin"
}

build_linux() {
  log "== linux-x86_64: cmake configure + build (gk, goalc) =="
  cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release "${CMAKE_FEATURE_ARGS[@]}" > .autoport/logs/build-linux-cmake.log 2>&1 \
    || { tail -20 .autoport/logs/build-linux-cmake.log >&2; die "cmake configure failed"; }
  cmake --build build --target gk goalc -j"$(nproc)" > .autoport/logs/build-linux-ninja.log 2>&1 \
    || { tail -30 .autoport/logs/build-linux-ninja.log >&2; die "ninja build failed"; }
  build/goalc/goalc --version 2>&1 | grep -q x86 || die "build/goalc/goalc is not the x86 backend"

  local fp cache
  fp=$(src_fingerprint build/goalc/goalc)
  cache="$CACHE_ROOT/x86-${FLAG_HASH}-${fp}"
  if [ $USE_CACHE -eq 1 ] && [ -f "$cache/CACHE_MANIFEST" ]; then
    log "CGO cache HIT ($cache) — restoring 28 CGO/DGO"
    cache_restore "$cache" "out/${GAME}/iso"
  else
    if [ $USE_CACHE -eq 1 ]; then log "CGO cache MISS ($cache)"; fi
    run_goalc_iso build/goalc/goalc "x86-${FLAG_HASH}"
    assert_iso_set "out/${GAME}/iso"
    if [ $USE_CACHE -eq 1 ]; then cache_store "$cache" "out/${GAME}/iso"; fi
  fi
  assert_iso_set "out/${GAME}/iso"
  verify_binary_flags build/game/gk

  { echo "target=$TARGET"; echo "flags=$FLAG_STR"; echo "flag_hash=$FLAG_HASH"; echo "marker=$MARKER";
    echo "gk_sha=$(sha256sum build/game/gk | cut -c1-16)"; echo "date=$(date -Is)";
    echo "cgo_cache=$cache"; } > "$REPORT_DIR/last-build-flags-linux-x86_64.txt"
  log "DONE linux-x86_64: build/game/gk + out/${GAME}/iso (28 CGO/DGO), marker $MARKER"
}

build_android() {
  # host arm64-backend goalc (flag-independent tool)
  [ -x build-arm64/goalc/goalc ] || die "build-arm64/goalc/goalc missing — build the arm64-backend goalc tree first"
  build-arm64/goalc/goalc --version 2>&1 | grep -q arm64 || die "build-arm64 goalc is not the arm64 backend"
  [ -x build/goalc/goalc ] || die "build/goalc/goalc (x86, for the oracle restore) missing"

  log "== android-arm64: NDK cmake configure + libgk.so =="
  [ -n "${ANDROID_NDK_HOME:-}" ] || { [ -f .autoport/lib/android-env.sh ] && source .autoport/lib/android-env.sh || true; }
  [ -n "${ANDROID_NDK_HOME:-}" ] || die "ANDROID_NDK_HOME not set (source .autoport/lib/android-env.sh)"
  cmake -S . -B build-android -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-29 \
    -DGOALC_BACKEND=arm64 -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    "${CMAKE_FEATURE_ARGS[@]}" > .autoport/logs/build-android-cmake.log 2>&1 \
    || { tail -20 .autoport/logs/build-android-cmake.log >&2; die "android cmake configure failed"; }
  cmake --build build-android --target gk -j"$(nproc)" > .autoport/logs/build-android-ninja.log 2>&1 \
    || { tail -30 .autoport/logs/build-android-ninja.log >&2; die "android ninja build failed"; }
  verify_binary_flags build-android/lib/arm64-v8a/libgk.so

  # arm64 CGOs (flag-keyed cache), staged to out/<game>-arm64-full/iso like
  # .autoport/build_arm64_full_consistent.sh, then the x86 oracle is restored.
  local fp_arm fp_x86 cache_arm cache_x86 STAGE="out/${GAME}-arm64-full/iso"
  fp_arm=$(src_fingerprint build-arm64/goalc/goalc)
  fp_x86=$(src_fingerprint build/goalc/goalc)
  cache_arm="$CACHE_ROOT/arm64-${FLAG_HASH}-${fp_arm}"
  mkdir -p "$STAGE"
  if [ $USE_CACHE -eq 1 ] && [ -f "$cache_arm/CACHE_MANIFEST" ]; then
    log "arm64 CGO cache HIT ($cache_arm) — restoring stage"
    rm -f "$STAGE"/*.CGO "$STAGE"/*.DGO
    cache_restore "$cache_arm" "$STAGE"
  else
    if [ $USE_CACHE -eq 1 ]; then log "arm64 CGO cache MISS ($cache_arm)"; fi
    run_goalc_iso build-arm64/goalc/goalc "arm64-${FLAG_HASH}"
    assert_iso_set "out/${GAME}/iso"
    rm -f "$STAGE"/*.CGO "$STAGE"/*.DGO
    cp -f out/${GAME}/iso/*.CGO out/${GAME}/iso/*.DGO "$STAGE"/
    if [ $USE_CACHE -eq 1 ]; then cache_store "$cache_arm" "$STAGE"; fi
    # restore the x86 oracle in out/<game>/iso (desktop/harness expects x86 there);
    # the x86 restore uses the SAME flag set (marker matches this build).
    local cache_x86_restore="$CACHE_ROOT/x86-${FLAG_HASH}-${fp_x86}"
    if [ $USE_CACHE -eq 1 ] && [ -f "$cache_x86_restore/CACHE_MANIFEST" ]; then
      log "x86 oracle restore from cache ($cache_x86_restore)"
      cache_restore "$cache_x86_restore" "out/${GAME}/iso"
    else
      run_goalc_iso build/goalc/goalc "x86-restore-${FLAG_HASH}"
      if [ $USE_CACHE -eq 1 ]; then cache_store "$cache_x86_restore" "out/${GAME}/iso"; fi
    fi
  fi
  assert_iso_set "$STAGE"
  local n; n=$(ls "$STAGE"/*.CGO "$STAGE"/*.DGO | wc -l)
  log "arm64 consistent set: $n files at $STAGE"

  # Grecharged-loader-packfix: regenerate the ANDROID text-bank overrides from the
  # text sources that were just compiled. build_cgo_pack.sh PREFERS any bank found in
  # out/<game>-android-text/ over the freshly built desktop bank, so a one-shot copy
  # of that dir silently freezes Android's text at the day it was made: every text id
  # added afterwards renders as "UNKNOWN ID <n>" on device only. That is exactly how
  # the MESH BROWSER row (#x1728) shipped as "UNKNOWN ID 5928" while every desktop
  # build showed the right label. Deriving the overrides on every build is the only
  # thing that keeps them honest — the dir holds EN/FR only (the two languages with
  # an android override json); all other languages fall through to the fresh banks.
  if [ "$GAME" = "jak1" ] && [ -x .autoport/gtt_build_android_text.sh ]; then
    log "== android text-bank overrides (EN/FR press-start + current text ids) =="
    bash .autoport/gtt_build_android_text.sh > .autoport/logs/build-android-text.log 2>&1 \
      || { tail -20 .autoport/logs/build-android-text.log >&2; die "android text-bank override build failed"; }
    grep -aq 'MESH BROWSER' "out/${GAME}-android-text/0COMMON.TXT" \
      || die "android EN bank lacks a text id the desktop bank has — the override went stale again"
    log "android text overrides refreshed: $(ls out/${GAME}-android-text/*COMMON.TXT | wc -l) bank(s)"
  fi

  # Grecharged-hd-models3 (BRICK 2): enhanced HD character fr3 overlay. SURGICAL merc swap on
  # the stock fr3 (tools/hd_merc_swap) — only the 4 replaced characters change; EVERY
  # non-character draw stays byte-identical to stock (integrity-gated inside the bake, which
  # is what kills the round-2 "tout violet" ground). --hd-models bakes it here; the flag also
  # gates the runtime enhanced/ lookup (hd_fr3_path in Loader.cpp).
  #
  # ARCHITECTURE IP (owner 2026-08-02): the enhanced fr3 embed ND-derived HD merc models. This block
  # only runs when F_HDMODELS is still 1, which the dumps gate above guarantees means the donor dump
  # is present. The output does NOT go into the APK: package_hd_assets.sh routes it to the EXTERNAL
  # asset pack, and android/build_custom_pack.sh refuses to stage any enhanced/ member.
  if [ "$GAME" = "jak1" ] && [ $F_HDMODELS -eq 1 ]; then
    log "== enhanced HD models: surgical merc-swap bake (flag hd-models ON, donor dump present) =="
    scripts/shell/build_enhanced_models.sh > .autoport/logs/build-enhanced-models.log 2>&1 \
      || { tail -40 .autoport/logs/build-enhanced-models.log >&2; die "enhanced HD model bake failed"; }
    nenh=$(ls out/${GAME}/fr3/enhanced/*.fr3 2>/dev/null | wc -l)
    if [ "$nenh" -eq 0 ]; then
      # build_enhanced_models.sh no-op'd. The dumps gate guarantees the donor dump is present, so the
      # only remaining reason is the prepped HD art (recharged_assets/hd_models/*.glb) being absent.
      # Refuse with an actionable message rather than shipping a flag with no ND assets behind it.
      tail -5 .autoport/logs/build-enhanced-models.log >&2
      die "hd-models ON and donor dump present, but NO enhanced fr3 were produced — the prepped HD art (recharged_assets/hd_models/*.glb) is missing. Regenerate it from the dump (scripts/shell/prep_hd_actor_glb.py + goalc build_actor) or drop --hd-models (stock)."
    fi
    # anim-retarget (2026-08-03): the bake now APPENDS jak-hd-lod0 (append-only) instead of the old
    # re-rig REPLACE of 4 characters (that REPLACE deformed them = the owner's "carnage"). Verify the
    # append fired + integrity of GAME.fr3 only (village1 no longer touched -> Samos/Keira stay stock).
    grep -q "APPENDED .*jak-hd-lod0" .autoport/logs/build-enhanced-models.log \
      || die "enhanced bake: expected an 'APPENDED … jak-hd-lod0' line, got none"
    grep -q "integrity gate PASS for GAME.fr3" .autoport/logs/build-enhanced-models.log \
      || die "enhanced bake: integrity gate did not pass for GAME.fr3"
    log "enhanced HD fr3 baked: $nenh file(s), jak-hd-lod0 appended, integrity gate PASS"

    # ARCHITECTURE IP: route the ND-derived HD fr3 to the EXTERNAL asset pack (never the APK).
    log "== external HD asset pack (ND-derived HD -> external storage, NOT the APK) =="
    scripts/package_hd_assets.sh "$GAME" > .autoport/logs/build-hd-assets.log 2>&1 \
      || { tail -20 .autoport/logs/build-hd-assets.log >&2; die "external HD asset pack build failed"; }
    grep -q "HD-ASSETS done" .autoport/logs/build-hd-assets.log \
      || { tail -20 .autoport/logs/build-hd-assets.log >&2; die "external HD asset pack not produced"; }
    log "external HD asset pack ready: $(grep -m1 'HD-ASSETS done' .autoport/logs/build-hd-assets.log | sed 's/^\[hd-assets\] //')"
  fi

  if [ $BUILD_APK -eq 1 ]; then
    log "== gradle assembleJak1Debug (packs CGO zip + libgk.so) =="
    # Grecharged-loader-packfix: delete the previous APK first. AGP's zipflinger updates
    # an existing output archive IN PLACE — when an entry changes size it appends the new
    # copy and leaves the old bytes as unreferenced dead space. The custom pack growing
    # 191->426 MB therefore produced a 1.0 GB APK holding 426 MB of garbage (measured:
    # 426,105,660 bytes of gaps) that the owner had to download and store. With no prior
    # archive zipflinger writes a compact one: same content, 580 MB, 0 bytes of gaps.
    rm -f android/app/build/outputs/apk/${GAME}/debug/app-${GAME}-debug.apk
    ( cd android && ./gradlew assembleJak1Debug -q ) > .autoport/logs/build-android-gradle.log 2>&1 \
      || { tail -30 .autoport/logs/build-android-gradle.log >&2; die "gradle assemble failed"; }
    local APK
    APK=$(find android -name "app-${GAME}-debug.apk" -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
    [ -n "$APK" ] || die "no APK produced"
    # R1 pairing proof inside the APK: libgk marker == CGO-pack marker.
    mkdir -p .autoport/tmp; local T; T=$(mktemp -d .autoport/tmp/bw.XXXXXX)
    unzip -p "$APK" lib/arm64-v8a/libgk.so > "$T/libgk.so"
    local m_so m_cgo
    # || true: grep -m1 / head -1 close the pipe early -> SIGPIPE(141) upstream would
    # abort the whole script under set -euo pipefail even though the match succeeded.
    m_so=$(strings "$T/libgk.so" | grep -m1 '^ogflags:' || true)
    unzip -o -q "$APK" "assets/bundle/${GAME}_cgo.zip" -d "$T"
    unzip -o -q "$T/assets/bundle/${GAME}_cgo.zip" GAME.CGO -d "$T"
    m_cgo=$(grep -a -o 'ogflags:[a-zA-Z0-9:_.-]*' "$T/GAME.CGO" | head -1 || true)
    # Grecharged-hd-models boot-crash guard (2026-08-02): the APK ships gradle's
    # jniLibs copy of libgk.so (android/app/build.gradle.kts copyNativeLibs), but
    # this block only compared its MARKER. A marker-fresh / FEATURE-stale libgk —
    # correct "ogflags:<hash>:<target>" stamp yet built with the OG_FEAT_* define
    # OFF, so the pc-* C binding is absent — therefore passed. On device that left
    # the FLAG_HD_MODELS GOAL code (hud-classes-pc.gc: pc-set-recharged-enhanced-models!)
    # calling an UNBOUND symbol -> value-slot 0 -> BLR ee_base -> sig=4 SIGILL at
    # boot; our handler eats the signal (no tombstone) and the system reaps the
    # defunct process as exit-info reason=2 / subreason=3 (TOO MANY EMPTY PROCS).
    # verify_binary_flags already runs on build-android/lib/libgk.so, but the
    # SHIPPED .so is the jniLibs copy — feature-verify THAT one too so a stale
    # jniLibs copy (or any marker/feature desync) can never be packaged.
    verify_binary_flags "$T/libgk.so"
    rm -rf "$T"
    [ "$m_so" = "$MARKER" ] || die "APK libgk marker '$m_so' != '$MARKER'"
    [ "$m_cgo" = "$MARKER" ] || die "APK CGO marker '$m_cgo' != '$MARKER' — MIXED FLAG-SET APK (R1)"
    log "APK flag-set pairing OK: $MARKER (libgk == CGO pack) — $APK"
    { echo "target=$TARGET"; echo "flags=$FLAG_STR"; echo "flag_hash=$FLAG_HASH"; echo "marker=$MARKER";
      echo "libgk_sha=$(sha256sum build-android/lib/arm64-v8a/libgk.so | cut -c1-16)";
      echo "apk=$APK"; echo "date=$(date -Is)"; echo "cgo_cache=$cache_arm"; } > "$REPORT_DIR/last-build-flags-android-arm64.txt"
  fi
  log "DONE android-arm64: libgk.so + $STAGE + APK, marker $MARKER"
}

verify_winbin_flags() { # $1 = gk.exe path ; strings-based per-flag proof (PE has no reliable nm)
  local bin="$1"
  check() { # name, expected 0/1, pattern
    local c; c=$(strings "$bin" | grep -c -- "$3" || true)
    if [ "$2" -eq 1 ]; then [ "$c" -ge 1 ] || die "$bin: flag $1 ON but marker '$3' absent"
    else [ "$c" -eq 0 ] || die "$bin: flag $1 OFF but marker '$3' present ($c)"; fi
  }
  check grass-overhang "$F_OVERHANG" "pc-set-grass-overhang!"
  check hd-models "$F_HDMODELS" "pc-enhanced-models-available?"
  check pbr "$F_PBR" "pc-set-pbr!"
  # positive control: validated feature must ALWAYS be present
  local pc; pc=$(strings "$bin" | grep -c "pc-set-recharged-grass!" || true)
  [ "$pc" -ge 1 ] || die "$bin: validated feature control pc-set-recharged-grass! missing"
  log "winbin flag proof OK: $bin"
}

build_windows() {
  # x86-backend goalc builds the CGOs locally (same tool as build_linux).
  [ -x build/goalc/goalc ] || die "build/goalc/goalc (x86) missing — build the linux goalc tree first (./build.sh linux-x86_64)"
  build/goalc/goalc --version 2>&1 | grep -q x86 || die "build/goalc/goalc is not the x86 backend"

  # CI-provided Windows engine binaries (GitHub artifact 'opengoal-windows-port' = build/bin).
  [ -f "$WIN_BIN_DIR/gk.exe" ] || die "no $WIN_BIN_DIR/gk.exe — download from a green Port CI run: gh run download -R moukrea/jak-project -n opengoal-windows-port -D out/ci/windows-x86_64"

  # gk.exe marker check (strings only; PE has no reliable nm). || true: grep -m1 SIGPIPE guard.
  local m_gk
  m_gk=$(strings "$WIN_BIN_DIR/gk.exe" | grep -m1 '^ogflags:' || true)
  [ "$m_gk" = "$MARKER" ] || die "$WIN_BIN_DIR/gk.exe marker '$m_gk' != expected '$MARKER' (mixed flag-set / stale CI artifact?)"
  verify_winbin_flags "$WIN_BIN_DIR/gk.exe"

  # x86 CGOs with the WINDOWS marker, staged like the android path.
  local fp fp_x86 cache STAGE="out/${GAME}-windows/iso"
  fp=$(src_fingerprint build/goalc/goalc)
  fp_x86="$fp"
  cache="$CACHE_ROOT/x86win-${FLAG_HASH}-${fp}"
  mkdir -p "$STAGE"
  if [ $USE_CACHE -eq 1 ] && [ -f "$cache/CACHE_MANIFEST" ]; then
    log "x86win CGO cache HIT ($cache) — restoring stage"
    rm -f "$STAGE"/*.CGO "$STAGE"/*.DGO "$STAGE"/*.TXT
    cache_restore "$cache" "$STAGE"
  else
    if [ $USE_CACHE -eq 1 ]; then log "x86win CGO cache MISS ($cache)"; fi
    run_goalc_iso build/goalc/goalc "x86win-${FLAG_HASH}"
    assert_iso_set "out/${GAME}/iso"
    rm -f "$STAGE"/*.CGO "$STAGE"/*.DGO "$STAGE"/*.TXT
    # cache_store/cache_restore copy CGO/DGO + TXT — the package ships the TXT banks too.
    cache_store "$cache" "out/${GAME}/iso"
    cache_restore "$cache" "$STAGE"
    # restore the x86 oracle in out/<game>/iso (desktop/harness expects the linux-marker
    # oracle there); same flag set. Mirror build_android's restore path faithfully.
    local cache_x86_restore="$CACHE_ROOT/x86-${FLAG_HASH}-${fp_x86}"
    if [ $USE_CACHE -eq 1 ] && [ -f "$cache_x86_restore/CACHE_MANIFEST" ]; then
      log "x86 oracle restore from cache ($cache_x86_restore)"
      cache_restore "$cache_x86_restore" "out/${GAME}/iso"
    else
      run_goalc_iso build/goalc/goalc "x86-restore-${FLAG_HASH}"
      if [ $USE_CACHE -eq 1 ]; then cache_store "$cache_x86_restore" "out/${GAME}/iso"; fi
    fi
  fi
  assert_iso_set "$STAGE"
  local n; n=$(ls "$STAGE"/*.CGO "$STAGE"/*.DGO | wc -l)
  log "windows consistent set: $n files at $STAGE"

  { echo "target=$TARGET"; echo "flags=$FLAG_STR"; echo "flag_hash=$FLAG_HASH"; echo "marker=$MARKER";
    echo "gk_exe_sha=$(sha256sum "$WIN_BIN_DIR/gk.exe" | cut -c1-16)"; echo "date=$(date -Is)";
    echo "cgo_cache=$cache"; } > "$REPORT_DIR/last-build-flags-windows-x86_64.txt"
  log "DONE windows-x86_64: $WIN_BIN_DIR/gk.exe + $STAGE (windows-marker CGOs), marker $MARKER"
}

mkdir -p .autoport/logs
case "$TARGET" in
  linux-x86_64)
    build_linux
    if [ $DO_PACKAGE -eq 1 ]; then
      log "== --package: source-derived assets archive + linux-x86_64 package =="
      scripts/packaging/build_assets_archive.sh "$GAME"
      scripts/packaging/package_release.sh linux-x86_64 "$GAME"
    fi
    ;;
  android-arm64)
    build_android
    if [ $DO_PACKAGE -eq 1 ] && [ $BUILD_APK -eq 1 ]; then
      log "== --package: source-derived assets archive + android-arm64 package =="
      scripts/packaging/build_assets_archive.sh "$GAME"
      scripts/packaging/package_release.sh android-arm64 "$GAME"
    elif [ $DO_PACKAGE -eq 1 ]; then
      log "--package requested but --no-apk given: skipping android-arm64 package (needs the APK)"
    fi
    ;;
  windows-x86_64)
    build_windows
    if [ $DO_PACKAGE -eq 1 ]; then
      log "== --package: source-derived assets archive + windows-x86_64 package =="
      scripts/packaging/build_assets_archive.sh "$GAME"
      WIN_BIN_DIR="$WIN_BIN_DIR" scripts/packaging/package_release.sh windows-x86_64 "$GAME"
    fi
    ;;
esac
log "flag matrix: recharged-hud=$(o $F_HUD) grass-overhang=$(o $F_OVERHANG) hd-models=$(o $F_HDMODELS) pbr=$(o $F_PBR) vulkan-support=$(o $F_VULKAN)  hash=$FLAG_HASH"
