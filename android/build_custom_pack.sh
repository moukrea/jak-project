#!/usr/bin/env bash
# Grecharged-buildsys-packaging (autoport 2026-07-17): build the PORT-CUSTOM asset
# pack the slim APK ships alongside the CGO pack.
#
# OWNER STRUCTURAL RULE (2026-07-27): "tout ce qui n'est pas original (sorti du dump
# du jeu sans être modifié) doit être inclus à l'APK et pas dans les assets de base
# séparés !" The criterion is ORIGIN, not size. Everything our chain PRODUCES or
# MODIFIES ships INSIDE the APK — here. Only the untouched dump (out/<game>/iso,
# 1.1 GB of raw iso data + VAG audio) stays in the separate external base pack
# (scripts/package_game_assets.sh), which therefore never changes and can be laid
# down once and never re-pushed.
#
# WHY: the base pack is 1.44 GB and cannot fit in an APK, and the owner has no adb.
# While derived data lived only in the base pack, NO geometry fix could reach his
# phone by installing an APK — he played two-day-old geometry twice and reported that
# nothing had been fixed. With ZERO OVERLAP between the two packs there is no
# freshness conflict left to lose.
#
# The CGO pack (build_cgo_pack.sh) carries the arm64 code; THIS pack carries the
# port-custom + derived DATA:
#   fr3/<name>.fr3                (ALWAYS — DERIVED: our extractor's output)
#   fr3/<name>.meshweld           (ALWAYS — DERIVED: mesh-consolidation sidecar)
#   fr3/<name>.grassbake          (ALWAYS — validated feature)
#   recharged_assets/<name>.png   (ALWAYS — DELIVERY is no longer flag-gated)
#   recharged_textures/<tpage>/<tex>/<tex>[ _height|_normal|_roughness].png  (ALWAYS — first-party set)
#
# ARCHITECTURE IP EXCLUSION (owner 2026-08-02): the enhanced HD fr3 (fr3/enhanced/<name>.fr3) are
# DELIBERATELY NOT here any more. Those levels embed the HD character merc models, which derive from
# the user's Jak2/Jak3 dumps = Naughty Dog IP. Shipping them in the APK would distribute ND IP.
# They are generated locally from the dump and ship ONLY in the EXTERNAL asset pack
# (scripts/package_hd_assets.sh -> <game>_hd_assets.zip, extracted to <external root>/assets/fr3/
# enhanced/). nd_hd_exclusion_guard() below HARD-FAILS this build if any enhanced/ or hd-derived
# member ever leaks back into the custom pack.
#
# The flag SET is recovered from the compiled arm64 GAME.CGO marker
# ("ogflags:<hash>:<target>"): the 12-char hash is inverted by enumerating the 64
# subsets of {debug, grass-overhang, hd-models, pbr, recharged-hud, vulkan-support},
# hashing each alphabetical comma-join, and matching. (Same canonical scheme + flag
# universe as build.sh's FLAG_LIST — keep this list in sync when build.sh gains a flag,
# or a build with the new flag falsely reads as "pre-flag-era" here.)
#
# Output:
#   android/app/src/<game>/assets-slim/bundle/<game>_custom.zip           (paths preserved)
#   android/app/src/<game>/assets-slim/bundle/<game>_custom.manifest.properties
set -euo pipefail

GAME="${1:-jak1}"

cd "$(git rev-parse --show-toplevel)"
ROOT="$(pwd)"

fail(){ echo "[custom-pack] FATAL: $*" >&2; exit 1; }

ARM64_CODE="out/${GAME}-arm64-full/iso"
FR3_DIR="out/${GAME}/fr3"
# recharged HUD PNGs live at the repo root. Named ONCE so the staging loop and the
# missing-derived-file guard (4) below cannot drift apart on the source dir. Empty for
# jak2/jak3: the art is jak1 HUD gauges, and guard (4) reads the same variable, so
# gating it here gates BOTH sides at once (gating only one would hard-refuse the pack).
RHUD_SRC=""
[ "$GAME" = "jak1" ] && RHUD_SRC="recharged_assets"
OUT_DIR="android/app/src/${GAME}/assets-slim/bundle"
STAGE="out/${GAME}-custom-pack-stage"
ZIP_REL="${OUT_DIR}/${GAME}_custom.zip"
MANIFEST="${OUT_DIR}/${GAME}_custom.manifest.properties"
ZIP_ABS="${ROOT}/${ZIP_REL}"

GAME_CGO="${ARM64_CODE}/GAME.CGO"
[ -f "$GAME_CGO" ] || fail "no $GAME_CGO — rebuild via ./build.sh android-arm64"

# --- HARD DATA-FRESHNESS GUARD -------------------------------------------------
# The libgk chain has refused to ship a stale BINARY for a long time:
# .autoport/ao_build_deploy_resume.sh will not deploy a libgk.so older than the
# newest source, and android/build_cgo_pack.sh hard-fails when the staged
# KERNEL.CGO differs from the arm64 build. The DATA had NO equivalent, and it cost
# two rounds: geometry corrections were "packaged" into an APK that did not carry
# them, the owner played stale geometry twice and reported that nothing had been
# fixed. The idempotent skip below is NOT a check — it only decides not to work, so
# it can happily hand back a stale zip. Therefore this guard runs on BOTH paths (the
# up-to-date/skip path AND a freshly written zip): a SKIP MUST BE ABLE TO FAIL.
# Every failure is a hard exit naming what to re-run.
data_freshness_guard(){
  local zip="$1"
  [ -f "$zip" ] || fail "data-freshness guard: no zip at $zip"

  # (1) BAKE NOT RE-RUN. If any bake source is newer than a sidecar, the sidecar
  #     was produced by OLD code. This is the check that would have caught rounds
  #     28 and 29: the orientation fix landed in the code and the offline bake was
  #     never re-run, so the corrected answer never existed on disk to be packaged
  #     in the first place — the packaging step was innocent, the input was stale.
  local bake_srcs=(
    common/custom_data/MeshConsolidate.cpp
    common/custom_data/MeshConsolidate.h
    common/custom_data/MeshSubdivide.cpp
    common/custom_data/MeshSubdivide.h
    common/custom_data/TFrag3Data.cpp
    tools/mesh_audit/main.cpp
  )
  local n_side=0 mw src
  if [ -d "$FR3_DIR" ]; then
    while IFS= read -r mw; do
      [ -n "$mw" ] || continue
      n_side=$((n_side + 1))
      for src in "${bake_srcs[@]}"; do
        # a source that does not exist is skipped, not fatal (tree layout may move).
        [ -f "$ROOT/$src" ] || continue
        if [ "$ROOT/$src" -nt "$mw" ]; then
          fail "STALE BAKE: $src ($(stat -c %y "$ROOT/$src")) is NEWER than the sidecar $mw ($(stat -c %y "$mw")) — the sidecar was baked by OLD code. Re-run the offline bake: tools/mesh_audit --game ${GAME} --bake   (then re-run this script)"
        fi
      done
    done < <(find "$FR3_DIR" -maxdepth 1 -type f -name '*.meshweld' 2>/dev/null | sort)
  fi

  # (2) STALE ZIP. Compare the BYTES of every fr3/ member against its source in
  #     out/<game>/fr3. This is a byte comparison ON PURPOSE: mtime alone is what
  #     let a stale zip pass (the skip path above trusts mtimes, and a zip can be
  #     newer than the sources yet still contain the previous generation's bytes).
  local n_fr3=0 zm srcp zmd5 smd5
  while IFS= read -r zm; do
    [ -n "$zm" ] || continue
    case "$zm" in */) continue;; esac   # zip directory entries carry no bytes
    srcp="$FR3_DIR/${zm#fr3/}"          # fr3/enhanced/x.fr3 -> <fr3>/enhanced/x.fr3
    [ -f "$srcp" ] || fail "STALE ZIP: member '$zm' of $zip has NO source at $srcp — the pack carries a file the tree no longer produces. Re-run: android/build_custom_pack.sh ${GAME}"
    zmd5=$( { unzip -p "$zip" "$zm" | md5sum | cut -d' ' -f1; } || true)
    smd5=$(md5sum "$srcp" | cut -d' ' -f1)
    if [ "$zmd5" != "$smd5" ]; then
      fail "STALE ZIP: member '$zm' (md5 $zmd5) in $zip does NOT match its source $srcp (md5 $smd5) — the APK would ship the PREVIOUS generation of this file. Delete $zip and re-run: android/build_custom_pack.sh ${GAME}"
    fi
    n_fr3=$((n_fr3 + 1))
  done < <(unzip -Z1 "$zip" 2>/dev/null | grep '^fr3/' || true)

  # (3) STALE FORMAT. The compiled-in expected bake version is the single source of
  #     truth; a sidecar whose embedded version differs is REJECTED at load by
  #     mesh_consolidate_apply_bake() and the runtime silently falls back to the
  #     ~45 s live pass. A version skew is therefore invisible except as a slow
  #     load — which is exactly how it went unnoticed.
  local kbv
  kbv=$(grep -oP 'constexpr u32 kBakeVersion = \K[0-9]+' "$ROOT/common/custom_data/MeshConsolidate.cpp" || true)
  [ -n "$kbv" ] || fail "data-freshness guard: could not read 'constexpr u32 kBakeVersion = <N>;' from common/custom_data/MeshConsolidate.cpp — the constant was renamed or moved. The guard REFUSES to pass blind; fix the guard's grep in android/build_custom_pack.sh"

  # .meshweld on disk: 8-byte LE raw-size prefix, then one zstd frame whose payload
  # starts with magic 'MCON' (4d 43 4f 4e) + u32 LE bake version.
  local n_ver=0 hdr magic vhex ver
  while IFS= read -r zm; do
    [ -n "$zm" ] || continue
    case "$zm" in */) continue;; esac
    # head -c 8 closes the pipe early -> SIGPIPE(141) upstream; || true keeps
    # set -o pipefail from aborting on a SUCCESSFUL read.
    hdr=$( { unzip -p "$zip" "$zm" | tail -c +9 | zstd -dcq 2>/dev/null | head -c 8 | od -A n -t x1 | tr -d ' \n'; } || true)
    if [ "${#hdr}" -ne 16 ]; then
      fail "STALE FORMAT: member '$zm' of $zip is not a readable sidecar (got ${#hdr}/16 header hex digits) — expected an 8-byte raw-size prefix + zstd frame starting with 'MCON'. The runtime would reject it and silently fall back to the ~45 s live consolidation pass. Re-run: tools/mesh_audit --game ${GAME} --bake"
    fi
    magic="${hdr:0:8}"; vhex="${hdr:8:8}"
    if [ "$magic" != "4d434f4e" ]; then
      fail "STALE FORMAT: member '$zm' of $zip has magic 0x$magic, expected 0x4d434f4e ('MCON') — not a mesh-consolidation sidecar. The runtime would reject it and silently fall back to the ~45 s live consolidation pass. Re-run: tools/mesh_audit --game ${GAME} --bake"
    fi
    ver=$(( 0x${vhex:0:2} | 0x${vhex:2:2} << 8 | 0x${vhex:4:2} << 16 | 0x${vhex:6:2} << 24 ))
    if [ "$ver" != "$kbv" ]; then
      fail "STALE FORMAT: member '$zm' of $zip has bake_version=$ver, expected $kbv (kBakeVersion in common/custom_data/MeshConsolidate.cpp). mesh_consolidate_apply_bake() REJECTS a version mismatch, so the runtime would silently fall back to the ~45 s live consolidation pass and the baked correction would never be applied. Re-run: tools/mesh_audit --game ${GAME} --bake   (then re-run this script)"
    fi
    n_ver=$((n_ver + 1))
  done < <(unzip -Z1 "$zip" 2>/dev/null | grep -E '^fr3/[^/]*\.meshweld$' || true)

  # (4) MISSING DERIVED FILE. Checks (2) and (3) walk the ZIP, so they can only ever
  #     judge what was already staged: a derived file that exists in out/<game>/ but
  #     was never staged passes both of them in complete silence. The APK simply would
  #     not carry it, and the runtime would fall back to whatever stale copy the
  #     external tree still holds — which is EXACTLY the failure this round exists to
  #     end (the owner played two-day-old geometry twice because the file the runtime
  #     opened came from external storage, not from the pack we corrected). So assert
  #     coverage in the OTHER direction too: every derived file ON DISK must have a
  #     member IN THE ZIP. Now that the base pack is iso-only, an uncovered derived
  #     file ships NOWHERE, so absence is a hard refusal, never a warning.
  #
  #     Member paths are constructed here with the SAME prefix+basename rule the
  #     staging loops use (fr3/<base>, recharged_assets/<base>); fr3/enhanced/ is NOT
  #     covered on purpose (ND-derived HD ships external — see nd_hd_exclusion_guard).
  #     so the two sides cannot disagree about where a file lands.
  local zlist
  zlist=$'\n'"$(unzip -Z1 "$zip" 2>/dev/null || true)"$'\n'
  # "<dir><TAB><name glob><TAB><in-zip prefix>" — dirs are repo-relative.
  # ARCHITECTURE IP: fr3/enhanced/ is intentionally NOT covered here — the ND-derived HD levels
  # ship in the EXTERNAL pack, never the APK. nd_hd_exclusion_guard() asserts their ABSENCE instead.
  local cov_specs=(
    "${FR3_DIR}"$'\t''*.fr3'$'\t''fr3/'
    "${FR3_DIR}"$'\t''*.meshweld'$'\t''fr3/'
    "${FR3_DIR}"$'\t''*.grassbake'$'\t''fr3/'
    "${RHUD_SRC}"$'\t''*.png'$'\t''recharged_assets/'
  )
  local n_cov=0 spec cdir cglob cpfx cbase want
  for spec in "${cov_specs[@]}"; do
    IFS=$'\t' read -r cdir cglob cpfx <<< "$spec"
    # a source dir that does not exist contributes nothing to cover (not fatal:
    # enhanced/ is optional, and jak2/jak3 have no fr3 tree yet).
    [ -d "$ROOT/$cdir" ] || continue
    while IFS= read -r cbase; do
      [ -n "$cbase" ] || continue
      want="${cpfx}${cbase}"
      # exact-LINE match against the member list, done in-shell: piping a big list
      # into `grep -q` SIGPIPEs the producer under `set -o pipefail`.
      if [[ "$zlist" != *$'\n'"$want"$'\n'* ]]; then
        fail "MISSING DERIVED FILE: $cdir/$cbase exists on disk but $zip has NO member '$want' — this derived file would ship in NEITHER pack (the external base pack is iso-only now), so the runtime would keep reading whatever stale copy external storage still holds. Re-run: android/build_custom_pack.sh ${GAME}"
      fi
      n_cov=$((n_cov + 1))
    done < <(find "$ROOT/$cdir" -maxdepth 1 -type f -name "$cglob" -printf '%f\n' 2>/dev/null | sort)
  done

  echo "[custom-pack] data-freshness guard OK: ${n_side} sidecars, ${n_fr3} fr3 members byte-identical to ${FR3_DIR}, bake_version=${kbv} (${n_ver} sidecar members version-checked), coverage ${n_cov}/${n_cov} derived files on disk present as members"
}

# --- ND-DERIVED HD EXCLUSION GUARD (owner IP rule 2026-08-02) -------------------
# The HD character models derive from the user's Jak2/Jak3 dumps = Naughty Dog IP, so they must
# NEVER ship inside the APK / custom pack. They are generated locally from the dump and ship ONLY
# in the EXTERNAL asset pack (scripts/package_hd_assets.sh -> <game>_hd_assets.zip, extracted to
# <external root>/assets/fr3/enhanced/). This guard HARD-FAILS the pack build if any ND-derived HD
# asset name ever leaks into the custom pack. Runs on BOTH the idempotent-skip path and the
# freshly-written path (mirrors data_freshness_guard: a SKIP MUST BE ABLE TO FAIL). Two routes:
#   (a) directory route — the enhanced level fr3 carry the SAME filenames as stock (GAME.fr3,
#       village1.fr3), so the discriminator is the enhanced/ subdirectory, not the basename.
#   (b) name route — the HD art-group / rip-source / retarget tokens (hd_models, hd_anim,
#       jak-highres, highres, jak-hd).
# grep -Em1 (no downstream pipe) + here-string: avoids the pipefail+grep-q SIGPIPE trap.
nd_hd_exclusion_guard(){
  local zip="$1"
  [ -f "$zip" ] || fail "ND-HD guard: no zip at $zip"
  local listing bad
  listing="$(unzip -Z1 "$zip" 2>/dev/null || true)"
  bad="$(grep -Em1 '(^|/)enhanced/' <<< "$listing" || true)"
  [ -z "$bad" ] || fail "ND-HD LEAK: custom pack $zip carries an enhanced/ member ('$bad') — the ND-derived HD level fr3 must NOT ship in the APK (that would distribute Naughty Dog IP). It ships ONLY in the external pack (scripts/package_hd_assets.sh). Remove the enhanced staging from android/build_custom_pack.sh."
  bad="$(grep -Eim1 'hd_models|hd_anim|jak-highres|highres|jak-hd' <<< "$listing" || true)"
  [ -z "$bad" ] || fail "ND-HD LEAK: custom pack $zip carries an ND-derived HD asset ('$bad') — HD art is Naughty Dog IP and must ship only in the external pack, never the APK."
  echo "[custom-pack] ND-HD exclusion guard OK: no Naughty-Dog-derived HD asset in $zip (HD ships EXTERNAL per the owner IP rule)"
}

# --- recover the flag marker + invert the hash to the flag SET ---
# || true: grep -o | head -1 close the pipe early -> SIGPIPE(141) would abort under
# set -euo pipefail even on a successful match.
MARKER=$(grep -a -o 'ogflags:[a-zA-Z0-9:_.-]*' "$GAME_CGO" | head -1 || true)
[ -n "$MARKER" ] || fail "pre-flag-era CGO set — rebuild via ./build.sh android-arm64"
# marker = ogflags:<hash>:<target>
HASH="${MARKER#ogflags:}"; HASH="${HASH%%:*}"
[ -n "$HASH" ] || fail "malformed marker '$MARKER'"

# Enumerate 32 subsets of the 5 flags (alphabetical universe), hash each canonical
# (alphabetical comma-join) string, match against HASH.
ALL_FLAGS=(debug grass-overhang hd-models pbr recharged-hud vulkan-support)
F_DEBUG=0; F_OVERHANG=0; F_HDMODELS=0; F_PBR=0; F_HUD=0; F_VULKAN=0
FOUND=0; MATCHED_STR=""
for mask in $(seq 0 63); do
  set_list=()
  for bit in 0 1 2 3 4 5; do
    if (( (mask >> bit) & 1 )); then set_list+=("${ALL_FLAGS[$bit]}"); fi
  done
  cand=$(IFS=,; echo "${set_list[*]-}")
  h=$(printf '%s' "$cand" | sha256sum | cut -c1-12)
  if [ "$h" = "$HASH" ]; then
    FOUND=1; MATCHED_STR="$cand"
    for fl in "${set_list[@]-}"; do
      case "$fl" in
        debug)          F_DEBUG=1;;
        grass-overhang) F_OVERHANG=1;;
        hd-models)      F_HDMODELS=1;;
        pbr)            F_PBR=1;;
        recharged-hud)  F_HUD=1;;
        vulkan-support) F_VULKAN=1;;
      esac
    done
    break
  fi
done
[ "$FOUND" -eq 1 ] || fail "pre-flag-era CGO set — rebuild via ./build.sh android-arm64"
echo "[custom-pack] marker=$MARKER  flags='${MATCHED_STR:-<none>}' (hud=$F_HUD overhang=$F_OVERHANG hd-models=$F_HDMODELS pbr=$F_PBR vulkan=$F_VULKAN)"

mkdir -p "$OUT_DIR"
rm -rf "$STAGE"
mkdir -p "$STAGE"

MEMBERS=()   # zip-relative paths staged (for count + version)

# 1. recharged HUD PNGs — ALWAYS, whenever the source dir exists.
#    DELIVERY IS NO LONGER FLAG-GATED. These PNGs are ours (not original dump data),
#    so under the owner's structural rule the external base pack no longer carries
#    them at all. A flag-gated custom pack would therefore leave them NOWHERE: build
#    with recharged-hud OFF and the files would vanish from both packs, and the next
#    build with the flag ON would have to remember to re-pack. The build flag still
#    gates the FEATURE at runtime (the game only reads these when recharged-hud is
#    compiled in) — it must no longer gate DELIVERY. Costs ~11 MB in the APK.
#    NOTE: guard (4) below asserts the same set from the disk side, using this same
#    condition, so staging and coverage cannot disagree.
if [ -d "$ROOT/$RHUD_SRC" ]; then
  mkdir -p "$STAGE/recharged_assets"
  n_png=0
  while IFS= read -r png; do
    [ -n "$png" ] || continue
    base="$(basename "$png")"
    ln -s "$png" "$STAGE/recharged_assets/$base"
    MEMBERS+=("recharged_assets/$base")
    n_png=$((n_png + 1))
  done < <(find "$ROOT/$RHUD_SRC" -maxdepth 1 -type f -name '*.png' 2>/dev/null | sort)
  [ "$n_png" -gt 0 ] || fail "$RHUD_SRC/ exists but holds no *.png — the base pack no longer carries the recharged HUD, so an empty set here means the HUD ships NOWHERE. Restore the PNGs or delete the dir."
  echo "[custom-pack] recharged HUD PNGs: $n_png (delivery ungated; runtime feature flag hud=$F_HUD)"
fi

# 1bis. MESH BROWSER INDEX — ALWAYS. DERIVED data (produced by tools/mesh_index from a
#    tools/tess_sign sweep), so by the owner's structural rule it ships INSIDE the APK.
#    The debug mesh browser is useless without it: the index is what lists every mesh of a
#    level with its material, centroid, bounding box and offline grade, sorted worst-first.
#    Caught at delivery time: the browser was about to ship with ZERO index entries.
MIDX_SRC="custom_assets/${GAME}/mesh_index"
if [ -d "$ROOT/$MIDX_SRC" ]; then
  mkdir -p "$STAGE/mesh_index"
  n_midx=0
  while IFS= read -r idx; do
    [ -n "$idx" ] || continue
    base="$(basename "$idx")"
    ln -s "$idx" "$STAGE/mesh_index/$base"
    MEMBERS+=("mesh_index/$base")
    n_midx=$((n_midx + 1))
  done < <(find "$ROOT/$MIDX_SRC" -maxdepth 1 -type f -name 'mesh_index_*.txt' 2>/dev/null | sort)
  [ "$n_midx" -gt 0 ] || fail "$MIDX_SRC/ exists but holds no mesh_index_*.txt"
  echo "[custom-pack] mesh-browser index: $n_midx level(s)"
fi

# 2. grassbake precompute tables — ALWAYS (validated feature; 0 is OK).
if [ -d "$FR3_DIR" ]; then
  mkdir -p "$STAGE/fr3"
  n_bake=0
  while IFS= read -r gb; do
    [ -n "$gb" ] || continue
    base="$(basename "$gb")"
    ln -s "$ROOT/$gb" "$STAGE/fr3/$base"
    MEMBERS+=("fr3/$base")
    n_bake=$((n_bake + 1))
  done < <(find "$FR3_DIR" -maxdepth 1 -type f -name '*.grassbake' 2>/dev/null | sort)
  echo "[custom-pack] grassbake tables: $n_bake"

  # 2b. Grecharged-mesh-consolidation sidecars — ALWAYS (0 is OK: a level without one just runs the
  #     live pass). These carry the consolidated weld: shared normals, snapped positions, blended
  #     baked-colour indices and seam weights. Measured on the Redmi they cut village1's load from
  #     67.0 s to 22.1 s, so shipping them is not an optimisation, it is the difference between a
  #     playable load and a minute of black screen. Built by: tools/mesh_audit --game <g> --bake.
  n_mesh=0
  while IFS= read -r mw; do
    [ -n "$mw" ] || continue
    base="$(basename "$mw")"
    ln -s "$ROOT/$mw" "$STAGE/fr3/$base"
    MEMBERS+=("fr3/$base")
    n_mesh=$((n_mesh + 1))
  done < <(find "$FR3_DIR" -maxdepth 1 -type f -name '*.meshweld' 2>/dev/null | sort)
  echo "[custom-pack] mesh-consolidation sidecars: $n_mesh"

  # 2c. STOCK .fr3 LEVELS — ALWAYS. These are NOT original dump data: they are OUR
  #     EXTRACTOR'S OUTPUT, and they carry every geometry correction the port has made
  #     — the consolidated weld, the recomputed/oriented normals, the tangent frames
  #     and the pre-subdivision. Under the owner's structural rule they are "not
  #     original", so they belong in the APK.
  #     They used to live ONLY in the external base pack (scripts/package_game_assets.sh),
  #     which is 1.44 GB and CANNOT FIT IN AN APK. That is why rounds 28-30 could not
  #     deliver: the corrected geometry existed on disk and in a pack the phone never
  #     read, while the runtime kept opening a two-day-old copy from external storage.
  #     Shipping them here is what makes a geometry fix deliverable BY APK INSTALL ALONE
  #     — which matters because the owner has no adb.
  n_fr3lev=0
  while IFS= read -r lv; do
    [ -n "$lv" ] || continue
    base="$(basename "$lv")"
    ln -s "$ROOT/$lv" "$STAGE/fr3/$base"
    MEMBERS+=("fr3/$base")
    n_fr3lev=$((n_fr3lev + 1))
  done < <(find "$FR3_DIR" -maxdepth 1 -type f -name '*.fr3' 2>/dev/null | sort)
  echo "[custom-pack] stock fr3 levels: $n_fr3lev"
fi

# 2d. FIRST-PARTY recharged replacement textures — ALWAYS (committed owner-made set at
#     custom_assets/<game>/recharged_textures/<tpage>/<texname>/{<texname>.png + _height/
#     _normal/_roughness}; the base swap needs no build flag, the PBR maps feed the PBR
#     pipeline when compiled in). Extracted by LoaderActivity to <custom root>/
#     recharged_textures/** (zip paths preserved); runtime scans
#     get_bundled_recharged_textures_dir(). 0 is OK (set absent).
RTEX_SRC="custom_assets/${GAME}/recharged_textures"
if [ -d "$ROOT/$RTEX_SRC" ]; then
  n_rtex=0
  while IFS= read -r tf; do
    [ -n "$tf" ] || continue
    rel="${tf#"$ROOT/$RTEX_SRC/"}"
    mkdir -p "$STAGE/recharged_textures/$(dirname "$rel")"
    ln -s "$tf" "$STAGE/recharged_textures/$rel"
    MEMBERS+=("recharged_textures/$rel")
    n_rtex=$((n_rtex + 1))
  done < <(find "$ROOT/$RTEX_SRC" -type f -name '*.png' 2>/dev/null | sort)
  echo "[custom-pack] recharged textures: $n_rtex"
fi

# 3. enhanced HD fr3 — ARCHITECTURE IP (owner 2026-08-02): DELIBERATELY NOT STAGED HERE.
# The enhanced levels embed HD character merc models derived from the user's Jak2/Jak3 dumps =
# Naughty Dog IP. Putting them in the APK would distribute ND IP. They ship ONLY in the EXTERNAL
# asset pack (scripts/package_hd_assets.sh -> <game>_hd_assets.zip), which the owner extracts to
# <external root>/assets/fr3/enhanced/ — exactly where hd_fr3_path() (Loader.cpp) reads them. The
# nd_hd_exclusion_guard() call further down PROVES none of them leaked into this pack.

FILE_COUNT=${#MEMBERS[@]}

# content-derived version: md5 of member contents (empty-content md5 for 0 members),
# same c<hash> scheme as build_cgo_pack.sh.
if [ "$FILE_COUNT" -eq 0 ]; then
  VERSION="c$(printf '' | md5sum | cut -c1-12)"
  RAW_BYTES=0
else
  VERSION="c$( for m in "${MEMBERS[@]}"; do printf '%s\0' "$STAGE/$m"; done \
      | sort -z | xargs -0 md5sum | md5sum | cut -c1-12 )"
  RAW_BYTES=$(find -L "$STAGE" -type f -printf '%s\n' | awk '{s+=$1} END{print s+0}')
fi

# --- idempotent skip (version + file_count + mtime) ---
if [ -f "$ZIP_REL" ] && [ -f "$MANIFEST" ]; then
  cv=$(grep -E '^version=' "$MANIFEST" | cut -d= -f2 || echo "")
  cfc=$(grep -E '^file_count=' "$MANIFEST" | cut -d= -f2 || echo "")
  SRC_DIRS=("$FR3_DIR")
  [ -d "$ROOT/custom_assets/${GAME}/recharged_textures" ] && SRC_DIRS+=("$ROOT/custom_assets/${GAME}/recharged_textures")
  # HUD PNG delivery is no longer flag-gated (see section 1), so neither is its
  # mtime watch: gating it on F_HUD would let a touched PNG slip past the skip.
  if [ -d "$ROOT/$RHUD_SRC" ]; then SRC_DIRS+=("$ROOT/$RHUD_SRC"); fi
  newest=$(find "${SRC_DIRS[@]}" -type f -printf '%T@\n' 2>/dev/null | awk 'BEGIN{m=0}{t=int($1); if(t>m)m=t} END{print m}')
  zmt=$(stat -c %Y "$ZIP_REL")
  if [ "$cv" = "$VERSION" ] && [ "$cfc" = "$FILE_COUNT" ] && { [ -z "$newest" ] || [ "$zmt" -ge "$newest" ]; }; then
    echo "[custom-pack] up to date: $ZIP_REL (version=$VERSION file_count=$cfc)"
    # A SKIP MUST BE ABLE TO FAIL: the version/count/mtime triple above only proves
    # the zip matches what THIS script would stage, never that the staged data is a
    # current answer. Guard the skip too, or a stale pack sails straight into the APK.
    data_freshness_guard "$ZIP_REL"
    nd_hd_exclusion_guard "$ZIP_REL"
    rm -rf "$STAGE"
    exit 0
  fi
fi

echo "[custom-pack] packing $FILE_COUNT members → $ZIP_REL… (incl. ${n_fr3lev:-0} stock fr3 levels — DERIVED, moved out of the external base pack per the owner structural rule)"
rm -f "$ZIP_ABS"
if [ "$FILE_COUNT" -eq 0 ]; then
  # `zip -r stage/*` fails on an empty stage; create an empty (but valid) zip.
  python3 -c "import zipfile; zipfile.ZipFile('$ZIP_ABS','w').close()"
else
  (
    cd "$STAGE"
    # preserve zip paths (recharged_assets/, fr3/, recharged_textures/, mesh_index/).
    # -n: store these suffixes without deflating. Now that the ~214 MB of stock .fr3 ride along,
    # deflate would burn minutes of CPU for nothing — measured, village1.fr3 gives back 1.4%
    # (11759452 -> 11592718), and .meshweld is already zstd'd, .png already deflated.
    zip -r -6 -X -q -n '.fr3:.meshweld:.grassbake:.png' "$ZIP_ABS" .
  )
fi
ZIP_BYTES=$(stat -c %s "$ZIP_ABS")

cat > "$MANIFEST" <<EOF
# Generated by android/build_custom_pack.sh — do not edit.
version=${VERSION}
game=${GAME}
file_count=${FILE_COUNT}
raw_bytes=${RAW_BYTES}
flags=${MARKER}
EOF

rm -rf "$STAGE"

# Guard the freshly written zip too: staging from symlinks does not prove the
# LINKED-TO bytes are a current bake, nor that the format still matches the code.
data_freshness_guard "$ZIP_REL"
# ARCHITECTURE IP: prove no Naughty-Dog-derived HD asset leaked into the APK custom pack.
nd_hd_exclusion_guard "$ZIP_REL"

echo "[custom-pack] done: $ZIP_REL"
echo "[custom-pack]   files=$FILE_COUNT  raw=${RAW_BYTES}B  zip=${ZIP_BYTES}B  version=$VERSION  flags=$MARKER  fr3_levels=${n_fr3lev:-0}"
