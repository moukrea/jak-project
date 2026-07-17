#!/usr/bin/env bash
# Grecharged-buildsys-packaging (autoport 2026-07-17): assemble the distributable
# game PACKAGE for a target.
#
# Owner rule: the PACKAGE carries the engine + ALL port-custom artifacts (compiled
# CGO/DGO, rebuilt TXT banks, .grassbake, enhanced HD fr3, recharged PNGs). It must
# NEVER embed vanilla source-derived data — that ships separately as
# <game>_assets.zip (scripts/packaging/build_assets_archive.sh).
#
# Usage: package_release.sh <linux-x86_64|android-arm64> <game>
#
#   linux-x86_64  -> out/artifacts/app-<game>-linux-x86_64.tar.gz  (engine + custom)
#   android-arm64 -> out/artifacts/app-<game>-android-arm64.apk    (verified slim)
#
# Flag-set (risk R1): the flag SET is recovered from the binary/CGO ogflags marker
# by inverting the 12-char hash over the 16 subsets of the 4 flags; the gk marker
# MUST equal the GAME.CGO marker (no mixed flag-set package).
set -euo pipefail

TARGET="${1:-}"; GAME="${2:-}"
[ -n "$TARGET" ] && [ -n "$GAME" ] || { echo "usage: $0 <linux-x86_64|android-arm64> <game>" >&2; exit 1; }

cd "$(git rev-parse --show-toplevel)"
ROOT="$(pwd)"

fail(){ echo "[package] FATAL: $*" >&2; exit 1; }

OUT_DIR="out/artifacts"
mkdir -p "$OUT_DIR"

ALL_FLAGS=(grass-overhang hd-models recharged-hud vulkan-support)
# invert_hash <12-char-hash> -> echoes the matched canonical flag string (may be
# empty); returns 1 if no subset matches.
invert_hash() {
  local hash="$1" mask bit cand h
  local -a set_list
  for mask in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    set_list=()
    for bit in 0 1 2 3; do
      if (( (mask >> bit) & 1 )); then set_list+=("${ALL_FLAGS[$bit]}"); fi
    done
    cand=$(IFS=,; echo "${set_list[*]-}")
    h=$(printf '%s' "$cand" | sha256sum | cut -c1-12)
    if [ "$h" = "$hash" ]; then printf '%s' "$cand"; return 0; fi
  done
  return 1
}
# flag_on <canonical-str> <flag> -> 0 if flag present
flag_on(){ case ",$1," in *",$2,"*) return 0;; *) return 1;; esac; }

package_linux() {
  local gk="build/game/gk"
  [ -f "$gk" ] || fail "no $gk — build the linux gk first (./build.sh linux-x86_64)"
  local ISO_DIR="out/${GAME}/iso" FR3_DIR="out/${GAME}/fr3"
  [ -d "$ISO_DIR" ] || fail "no $ISO_DIR"

  # marker from gk binary. || true: grep -m1 SIGPIPE guard.
  local m_gk
  m_gk=$(strings "$gk" | grep -m1 '^ogflags:' || true)
  [ -n "$m_gk" ] || fail "no ogflags marker in $gk — rebuild via ./build.sh linux-x86_64"
  # R1 gate: gk marker == out/<game>/iso/GAME.CGO marker.
  local m_cgo
  [ -f "$ISO_DIR/GAME.CGO" ] || fail "no $ISO_DIR/GAME.CGO"
  m_cgo=$(grep -a -o 'ogflags:[a-zA-Z0-9:_.-]*' "$ISO_DIR/GAME.CGO" | head -1 || true)
  [ "$m_gk" = "$m_cgo" ] || fail "mixed flag-set package: gk marker '$m_gk' != GAME.CGO marker '$m_cgo'"

  local hash="${m_gk#ogflags:}"; hash="${hash%%:*}"
  local flags
  flags=$(invert_hash "$hash") || fail "gk ogflags hash '$hash' matches no flag subset — rebuild via ./build.sh linux-x86_64"
  echo "[package] linux marker=$m_gk flags='${flags:-<none>}'"

  local F_HUD=0 F_HDMODELS=0
  flag_on "$flags" recharged-hud && F_HUD=1
  flag_on "$flags" hd-models && F_HDMODELS=1

  local APPDIR="out/${GAME}-pkg-stage/app-${GAME}-linux-x86_64"
  rm -rf "out/${GAME}-pkg-stage"
  mkdir -p "$APPDIR/iso" "$APPDIR/custom/fr3"

  # gk copy (real copy, not symlink — the engine binary).
  cp -f "$gk" "$APPDIR/gk"
  chmod +x "$APPDIR/gk"

  # data/ = the runtime PROJECT dir gk requires (setup_project_path): shader
  # sources + font metadata, read via get_jak_project_dir() at runtime. These are
  # port-maintained engine files -> package per the owner rule. run.sh passes
  # --proj-path to it; gk also writes log/ + imgui.ini there (extracted dir is
  # writable). Without this dir gk exits 1 at "Failed to initialize project path".
  local n_shader=0
  mkdir -p "$APPDIR/data/game/graphics/opengl_renderer/shaders"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    ln -s "$ROOT/$f" "$APPDIR/data/game/graphics/opengl_renderer/shaders/$(basename "$f")"
    n_shader=$((n_shader + 1))
  done < <(find game/graphics/opengl_renderer/shaders -maxdepth 1 -type f \( -name '*.vert' -o -name '*.frag' \) | sort)
  [ "$n_shader" -gt 0 ] || fail "no shader sources under game/graphics/opengl_renderer/shaders"
  local n_font=0
  if [ -d game/assets/fonts ]; then
    mkdir -p "$APPDIR/data/game/assets/fonts"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      ln -s "$ROOT/$f" "$APPDIR/data/game/assets/fonts/$(basename "$f")"
      n_font=$((n_font + 1))
    done < <(find game/assets/fonts -maxdepth 1 -type f | sort)
  fi
  # sdl_controller_db.txt (input_manager) + the per-game runtime assets
  # (subtitle/text jsons read by subtitles_v1/v2 at boot — read_text_file throws
  # on absence). Dir symlinks; tar -h + find -L dereference them.
  [ -f game/assets/sdl_controller_db.txt ] || fail "no game/assets/sdl_controller_db.txt"
  ln -s "$ROOT/game/assets/sdl_controller_db.txt" "$APPDIR/data/game/assets/sdl_controller_db.txt"
  [ -d "game/assets/${GAME}" ] || fail "no game/assets/${GAME}"
  ln -s "$ROOT/game/assets/${GAME}" "$APPDIR/data/game/assets/${GAME}"
  # repl_wrapper's find_username() directory-iterates goal_src/user at init and
  # THROWS if the dir is missing — ship it empty.
  mkdir -p "$APPDIR/data/goal_src/user"

  # iso/ = ALL *.CGO *.DGO *.TXT (symlink farm; tar -h dereferences).
  local n_code=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    ln -s "$ROOT/$ISO_DIR/$f" "$APPDIR/iso/$f"
    n_code=$((n_code + 1))
  done < <(find "$ISO_DIR" -maxdepth 1 -type f \( -name '*.CGO' -o -name '*.DGO' -o -name '*.TXT' \) -printf '%f\n' | sort)
  [ "$n_code" -gt 0 ] || fail "no CGO/DGO/TXT port code in $ISO_DIR"

  # custom/fr3/*.grassbake (always, if present)
  local n_bake=0
  if [ -d "$FR3_DIR" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      ln -s "$ROOT/$f" "$APPDIR/custom/fr3/$(basename "$f")"
      n_bake=$((n_bake + 1))
    done < <(find "$FR3_DIR" -maxdepth 1 -type f -name '*.grassbake' 2>/dev/null | sort)
  fi

  # custom/recharged_assets/*.png per flag set
  local n_png=0
  if [ "$F_HUD" -eq 1 ] && [ "$GAME" = "jak1" ]; then
    mkdir -p "$APPDIR/custom/recharged_assets"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      ln -s "$ROOT/$f" "$APPDIR/custom/recharged_assets/$(basename "$f")"
      n_png=$((n_png + 1))
    done < <(find "$ROOT/recharged_assets" -maxdepth 1 -type f -name '*.png' 2>/dev/null | sort)
    [ "$n_png" -gt 0 ] || fail "flag recharged-hud ON but no recharged_assets/*.png"
  fi

  # custom/fr3/enhanced/*.fr3 per flag set
  local n_enh=0
  if [ "$F_HDMODELS" -eq 1 ]; then
    local ENH="$FR3_DIR/enhanced"
    mkdir -p "$APPDIR/custom/fr3/enhanced"
    if [ -d "$ENH" ]; then
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        ln -s "$ROOT/$f" "$APPDIR/custom/fr3/enhanced/$(basename "$f")"
        n_enh=$((n_enh + 1))
      done < <(find "$ENH" -maxdepth 1 -type f -name '*.fr3' 2>/dev/null | sort)
    fi
    [ "$n_enh" -gt 0 ] || fail "flag hd-models ON but $ENH missing/empty — run android/build_enhanced_models.sh"
  fi

  # run.sh launcher
  cat > "$APPDIR/run.sh" <<EOF
#!/usr/bin/env bash
# app-${GAME}-linux-x86_64 launcher. Usage: ./run.sh --game-root <dir> [extra gk args...]
# <dir> = directory where ${GAME}_assets.zip was extracted (contains assets/iso and assets/fr3).
set -euo pipefail
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
[ "\${1:-}" = "--game-root" ] && [ -n "\${2:-}" ] || { echo "usage: \$0 --game-root <extracted-assets-dir> [gk args...]" >&2; exit 1; }
ROOT="\$2"; shift 2
exec "\$DIR/gk" --proj-path "\$DIR/data" --game-root "\$ROOT" --iso-overlay "\$DIR/iso" --custom-assets "\$DIR/custom" -boot -fakeiso "\$@"
EOF
  chmod +x "$APPDIR/run.sh"

  echo "[package] staged: code=$n_code grassbake=$n_bake png=$n_png enhanced=$n_enh shaders=$n_shader fonts=$n_font"

  # --- manifest: one line per member (deref shas via readlink) ---
  local MAN="$OUT_DIR/app-${GAME}-linux-x86_64.manifest.txt"
  {
    echo "# Generated by scripts/packaging/package_release.sh — do not edit."
    echo "# app-${GAME}-linux-x86_64  flags='${flags:-<none>}'  marker=$m_gk"
    echo "# columns: <path>  <sha256>  <bytes>  <class>"
    # engine
    printf 'gk  %s  %s  class=port-engine\n' \
      "$(sha256sum "$APPDIR/gk" | cut -d' ' -f1)" "$(stat -c %s "$APPDIR/gk")"
    printf 'run.sh  %s  %s  class=port-engine\n' \
      "$(sha256sum "$APPDIR/run.sh" | cut -d' ' -f1)" "$(stat -c %s "$APPDIR/run.sh")"
    # members (follow symlinks for content)
    while IFS= read -r rel; do
      local real cls
      real="$APPDIR/$rel"
      case "$rel" in
        iso/*.CGO|iso/*.DGO|iso/*.TXT) cls="port-code";;
        custom/*)                      cls="port-custom";;
        data/*)                        cls="port-engine";;
        *)                             cls="port-custom";;
      esac
      # sha256sum dereferences symlinks by default (no -L flag exists); stat -L
      # follows the link for the real byte size.
      printf '%s  %s  %s  class=%s\n' "$rel" \
        "$(sha256sum "$real" | cut -d' ' -f1)" \
        "$(stat -Lc %s "$real")" "$cls"
    done < <(cd "$APPDIR" && find -L iso custom data -type f | grep -vE '^(gk|run\.sh)$' | sort)
  } > "$MAN"

  # --- tar (deref symlinks) ---
  local TAR="$OUT_DIR/app-${GAME}-linux-x86_64.tar.gz"
  rm -f "$TAR"
  ( cd "out/${GAME}-pkg-stage" && tar -hczf "$ROOT/$TAR" "app-${GAME}-linux-x86_64" )
  rm -rf "out/${GAME}-pkg-stage"

  echo "[package] DONE $TAR"
  echo "[package]   sha256=$(sha256sum "$TAR" | cut -d' ' -f1)"
  echo "[package]   manifest=$MAN"
}

package_android() {
  # newest app-<game>-debug.apk under android/
  local APK
  APK=$(find android -name "app-${GAME}-debug.apk" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)
  [ -n "$APK" ] || fail "no app-${GAME}-debug.apk under android/ — build the APK first (./build.sh android-arm64)"
  echo "[package] source APK: $APK"

  # NEGATIVE GATE: the APK must embed NO vanilla source-derived data.
  # Listing goes to a FILE first: `printf big | grep -q` under pipefail can
  # SIGPIPE the producer when grep exits early, turning a MATCH into a
  # false-PASS of the gate (the known pipefail+grep-q class).
  local LISTF; LISTF=$(mktemp)
  unzip -l "$APK" > "$LISTF"
  local LISTING; LISTING=$(cat "$LISTF")
  # NO assets/bundle/<game>_assets.zip
  if [[ "$LISTING" == *"assets/bundle/${GAME}_assets.zip"* ]]; then
    rm -f "$LISTF"; fail "APK embeds assets/bundle/${GAME}_assets.zip — vanilla data must NOT be in the APK"
  fi
  # NO iso_data/ entry
  if [[ "$LISTING" == *"iso_data/"* ]]; then
    rm -f "$LISTF"; fail "APK embeds an iso_data/ entry — verbatim disc data must NOT be in the APK"
  fi
  # NO assets/**.fr3 entry (stock fr3 = vanilla-derived; ships in the archive)
  if grep -qE 'assets/[^ ]*\.fr3( |$)' "$LISTF"; then
    local off
    off=$(grep -oE 'assets/[^ ]*\.fr3' "$LISTF" | head -1 || true)
    rm -f "$LISTF"
    fail "APK embeds a stock fr3 asset ($off) — vanilla-derived fr3 must NOT be in the APK"
  fi
  rm -f "$LISTF"
  echo "[package] negative gate PASS: no vanilla data embedded"

  local DST="$OUT_DIR/app-${GAME}-android-arm64.apk"
  cp -f "$APK" "$DST"

  # manifest: full APK listing + nested listings of the bundle zips, classified.
  local MAN="$OUT_DIR/app-${GAME}-android-arm64.manifest.txt"
  local CGO_ZIP="assets/bundle/${GAME}_cgo.zip"
  local CUSTOM_ZIP="assets/bundle/${GAME}_custom.zip"
  local T; T=$(mktemp -d)
  {
    echo "# Generated by scripts/packaging/package_release.sh — do not edit."
    echo "# app-${GAME}-android-arm64 (slim APK; vanilla data ships as ${GAME}_assets.zip)"
    echo "# === APK top-level listing (class=engine unless a bundle zip below) ==="
    printf '%s\n' "$LISTING"
    if unzip -o -q "$APK" "$CGO_ZIP" -d "$T" 2>/dev/null && [ -f "$T/$CGO_ZIP" ]; then
      echo "# === nested ${CGO_ZIP} members (class=port-code) ==="
      unzip -l "$T/$CGO_ZIP" | sed 's/$/  class=port-code/'
    fi
    if unzip -o -q "$APK" "$CUSTOM_ZIP" -d "$T" 2>/dev/null && [ -f "$T/$CUSTOM_ZIP" ]; then
      echo "# === nested ${CUSTOM_ZIP} members (class=port-custom) ==="
      unzip -l "$T/$CUSTOM_ZIP" | sed 's/$/  class=port-custom/'
    fi
  } > "$MAN"
  rm -rf "$T"

  echo "[package] DONE $DST"
  echo "[package]   sha256=$(sha256sum "$DST" | cut -d' ' -f1)"
  echo "[package]   manifest=$MAN"
}

case "$TARGET" in
  linux-x86_64)  package_linux;;
  android-arm64) package_android;;
  *) fail "unknown target '$TARGET' (linux-x86_64|android-arm64)";;
esac
