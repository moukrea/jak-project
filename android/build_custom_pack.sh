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
#   recharged_assets/physics_chains.txt (ALWAYS if present — secondary-motion chain defs)
#   (per-texture PBR material properties are NOT here any more — see the note at the
#    materials staging site below: they now ride the ASSET RELEASE, not the app.)
#   recharged_textures/<tpage>/<tex>/<tex>[ _height|_normal|_roughness].png  (ALWAYS — first-party set)
#   recharged_textures_baked/astc/<tpage>/<tex>/<tex>*.ktx2 + <tex>.stats.json
#                                 (IF PRESENT — GPU-compressed bake of the set above,
#                                  produced by tools/bake_recharged_textures.py; the PNGs
#                                  stay for the targets without ASTC)
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

# Les reglages issus de l'oeil de l'owner survivent a la regeneration du fichier de
# chaines (2026-08-11: deux series effacees, il a teste un APK sans ses corrections).
python3 "$(dirname "$0")/../.autoport/apply_owner_tuning.py" || true

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
    "${RHUD_SRC}"$'\t''physics_chains.txt'$'\t''recharged_assets/'
    "${RHUD_SRC}"$'\t''physics_mesh.txt'$'\t''recharged_assets/'
    "${RHUD_SRC}"$'\t''foliage_wind_protos.txt'$'\t''recharged_assets/'
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
#       jak-highres, highres, jak-hd, dax-hd, keira-hd, samos-hd) plus ANY *-hd-ag.go art-group.
# grep -Em1 (no downstream pipe) + here-string: avoids the pipefail+grep-q SIGPIPE trap.
nd_hd_exclusion_guard(){
  local zip="$1"
  [ -f "$zip" ] || fail "ND-HD guard: no zip at $zip"
  local listing bad
  listing="$(unzip -Z1 "$zip" 2>/dev/null || true)"
  bad="$(grep -Em1 '(^|/)enhanced/' <<< "$listing" || true)"
  [ -z "$bad" ] || fail "ND-HD LEAK: custom pack $zip carries an enhanced/ member ('$bad') — the ND-derived HD level fr3 must NOT ship in the APK (that would distribute Naughty Dog IP). It ships ONLY in the external pack (scripts/package_hd_assets.sh). Remove the enhanced staging from android/build_custom_pack.sh."
  bad="$(grep -Eim1 'hd_models|hd_anim|jak-highres|highres|jak-hd|dax-hd|keira-hd|samos-hd|-hd-ag\.go' <<< "$listing" || true)"
  [ -z "$bad" ] || fail "ND-HD LEAK: custom pack $zip carries an ND-derived HD asset ('$bad') — HD art is Naughty Dog IP and must ship only in the external pack, never the APK."
  echo "[custom-pack] ND-HD exclusion guard OK: no Naughty-Dog-derived HD asset in $zip (HD ships EXTERNAL per the owner IP rule)"
}

# --- recover the flag marker + invert the hash to the flag SET ---
# || true: grep -o | head -1 close the pipe early -> SIGPIPE(141) would abort under
# set -euo pipefail even on a successful match.
MARKER=$(grep -a -o 'ogflags:[a-zA-Z0-9:_.-]*' "$GAME_CGO" | head -1 || true)

# --- Gjak2-polish 2026-08-31 : LE MARQUEUR DE DRAPEAUX EST UNE NOTION PROPRE A JAK 1. ---
# Les drapeaux Recharged (hd-models, pbr, physics, recharged-hud, grass-overhang, ...) gatent du
# code qui n'existe QUE dans goal_src/jak1/pc/. jak2 et jak3 n'en embarquent aucun : leur jeu de
# drapeaux est vide PAR CONSTRUCTION, pas par oubli (goal_src/jak2/pc/recharged-flags.gc les pose
# tous a #f, et c'est ce qui permet au build jak2 de compiler du tout).
# Exiger d'eux un marqueur Recharged etait donc une erreur de categorie : le pack jak2 mourait sur
#   [custom-pack] FATAL: pre-flag-era CGO set — rebuild via ./build.sh android-arm64
# alors qu'aucune valeur de marqueur n'aurait ete a la fois acceptable ici ET pour deploy_verify
# (qui, lui, exige que le marqueur du CGO soit EGAL a celui du libgk s'il existe : un marqueur
# jak2 « vide » echouerait l'appariement, un marqueur copie de jak1 mentirait sur ce que jak2
# a compile). L'absence de marqueur est la seule reponse juste pour ces jeux — et deploy_verify
# la traite deja comme telle (« warn: device CGOs carry no ogflags marker »).
# JAK 1 N'EST PAS ASSOUPLI : pour lui le marqueur reste OBLIGATOIRE et son inversion aussi.
NO_FLAGS_BY_CONSTRUCTION=0
if [ -z "$MARKER" ] && [ "$GAME" != "jak1" ]; then
  NO_FLAGS_BY_CONSTRUCTION=1
fi
# Initialises AVANT la bifurcation : la branche « sans drapeaux » doit laisser des F_* definis
# (set -u), et la branche jak1 les reecrit depuis l'inversion du hash.
F_DEBUG=0; F_OVERHANG=0; F_HDMODELS=0; F_PBR=0; F_HUD=0; F_VULKAN=0; F_PHYSICS=0

if [ "$NO_FLAGS_BY_CONSTRUCTION" -eq 1 ]; then
  # Tous les F_* sont deja a 0 ci-dessous ; rien de flag-gate ne sera stage.
  echo "[custom-pack] $GAME : aucun marqueur ogflags dans GAME.CGO — jeu de drapeaux VIDE par construction (aucune fonctionnalite Recharged n'existe hors de jak1). Inversion du hash sautee."
else
[ -n "$MARKER" ] || fail "pre-flag-era CGO set — rebuild via ./build.sh android-arm64"
# marker = ogflags:<hash>:<target>
HASH="${MARKER#ogflags:}"; HASH="${HASH%%:*}"
[ -n "$HASH" ] || fail "malformed marker '$MARKER'"

# Enumerate 256 subsets of the 8 flags (alphabetical universe), hash each canonical
# (alphabetical comma-join) string, match against HASH.
ALL_FLAGS=(debug grass-overhang hd-models menu-overhaul pbr physics recharged-hud vulkan-support)
FOUND=0; MATCHED_STR=""
for mask in $(seq 0 255); do
  set_list=()
  for bit in 0 1 2 3 4 5 6 7; do
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
        physics)        F_PHYSICS=1;;
        recharged-hud)  F_HUD=1;;
        vulkan-support) F_VULKAN=1;;
      esac
    done
    break
  fi
done
[ "$FOUND" -eq 1 ] || fail "pre-flag-era CGO set — rebuild via ./build.sh android-arm64"
echo "[custom-pack] marker=$MARKER  flags='${MATCHED_STR:-<none>}' (hud=$F_HUD overhang=$F_OVERHANG hd-models=$F_HDMODELS pbr=$F_PBR physics=$F_PHYSICS vulkan=$F_VULKAN)"
fi

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

# 1ter. PHYSICS CHAIN DEFINITION — ALWAYS, whenever it exists. Same delivery rule as the
#    recharged PNGs above: the file is ours (not dump data), the base pack is iso-only, so a
#    flag-gated delivery would leave it in NO pack at all. The --physics build flag gates the
#    FEATURE at runtime, never the DELIVERY. NB: the PNG loop above only globs *.png, so this
#    .txt needs its own staging line (guard (4) covers it from the disk side too).
if [ -f "$ROOT/$RHUD_SRC/physics_chains.txt" ]; then
  mkdir -p "$STAGE/recharged_assets"
  ln -s "$ROOT/$RHUD_SRC/physics_chains.txt" "$STAGE/recharged_assets/physics_chains.txt"
  MEMBERS+=("recharged_assets/physics_chains.txt")
  echo "[custom-pack] physics chain definition: 1 (delivery ungated; runtime feature flag physics=$F_PHYSICS)"
fi
# (C14) MESH-SAMPLE DATA — same delivery rule as physics_chains.txt: derived data of ours, iso-only
# base pack, so a flag-gated delivery would ship it nowhere. Without it the runtime logs
# MESHSRC=none and the mesh-surface audit reports meshtested=0 ("not measured", never a clean 0).
if [ -f "$ROOT/$RHUD_SRC/physics_mesh.txt" ]; then
  mkdir -p "$STAGE/recharged_assets"
  ln -s "$ROOT/$RHUD_SRC/physics_mesh.txt" "$STAGE/recharged_assets/physics_mesh.txt"
  MEMBERS+=("recharged_assets/physics_mesh.txt")
  echo "[custom-pack] physics mesh samples: 1 (delivery ungated; runtime feature flag physics=$F_PHYSICS)"
fi
# (C15) LEXIQUE DE VEGETATION TIE (Grecharged-foliage-wind3, defaut D2) — meme regle de livraison
# que les deux ci-dessus : c'est une donnee A NOUS, le pack de base est iso-seul, donc une
# livraison conditionnee par un drapeau ne l'expedierait NULLE PART. Et son absence est un mode de
# defaillance SILENCIEUX : le moteur classe alors zero prototype comme vegetation, plus aucune
# plante statique ne bouge, et rien ne plante — le journal publie `lexique=0` sur la ligne
# `TIE sway-cover`, et c'est la SEULE trace. La boucle des PNG plus haut ne globe que *.png, donc
# ce .txt a besoin de sa propre ligne, exactement comme physics_chains.txt.
if [ -f "$ROOT/$RHUD_SRC/foliage_wind_protos.txt" ]; then
  mkdir -p "$STAGE/recharged_assets"
  ln -s "$ROOT/$RHUD_SRC/foliage_wind_protos.txt" "$STAGE/recharged_assets/foliage_wind_protos.txt"
  MEMBERS+=("recharged_assets/foliage_wind_protos.txt")
  echo "[custom-pack] lexique de vegetation TIE: 1 (livraison inconditionnelle; sans lui, zero balancement statique)"
fi
# (Gpbr-material-props) PER-TEXTURE MATERIAL PROPERTIES ARE DELIBERATELY NOT STAGED HERE.
#    The previous phase shipped recharged_assets/materials.txt inside this pack. The owner
#    (2026-08-29) ruled that out: « ces props doivent faire partie du repo Recharged assets, pas
#    dans l'APK ». They are now authored per material in moukrea/recharged-assets, published as a
#    release EXTRA (manifest `extras`, kind "surfaces") and installed by the asset manager into
#    managed_assets/<game>/surfaces.json — the same tier as the texture packs they describe.
#    Putting a copy back in this pack would defeat that AND create a second source of truth that
#    silently wins or loses depending on which tier the loader checks first, so there is no
#    staging line here on purpose. The owner's kilobyte-push route survives untouched: a
#    surfaces.json dropped in the EXTERNAL asset dir still beats the installed one.

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

# 2a-bis. Ggrass-density-presets — GARDE DURE : UN BAKE QUI SERA REFUSE NE PART PAS.
#
# Le moteur refuse un bake dont `fr3_size` ne correspond pas au `.fr3` qu'il charge, et il n'a
# PLUS de repli en direct : un bake perime ne degrade plus le chargement, il supprime l'herbe.
# C'est exactement le defaut mesure sur le Redmi (« fr3 size mismatch » a chaque chargement), et
# il ne se voyait qu'a l'execution, sur l'appareil. On le rend visible ICI, au moment ou le
# fichier entre dans le pack, en relisant l'en-tete du bake et en le comparant au fr3 qui part
# avec lui — les deux etant les fichiers EXACTS que l'APK embarque.
for gb in "$STAGE"/fr3/*.grassbake; do
  [ -e "$gb" ] || continue
  gbbase="$(basename "$gb")"
  hdrline="$(python3 "$ROOT/scripts/shell/grassbake_header.py" "$gb" 2>&1)" \
    || fail "grassbake guard: en-tete illisible pour $gbbase — $hdrline"
  gblev="$(sed -n 's/.* niveau=\([^ ]*\).*/\1/p' <<< "$hdrline")"
  gbsz="$(sed -n 's/.* fr3_size=\([0-9]*\).*/\1/p' <<< "$hdrline")"
  [ -n "$gblev" ] && [ -n "$gbsz" ] || fail "grassbake guard: en-tete incomplet pour $gbbase — $hdrline"
  # le nom doit porter le palier : le moteur ne resout QUE <niveau>.<palier>.grassbake
  case "$gbbase" in
    "$gblev".very-low.grassbake|"$gblev".low.grassbake|"$gblev".medium.grassbake|"$gblev".high.grassbake|"$gblev".very-high.grassbake) ;;
    *) fail "grassbake guard: '$gbbase' ne porte pas de palier connu (attendu $gblev.<very-low|low|medium|high|very-high>.grassbake) — le moteur ne le resoudrait JAMAIS, il ne doit pas alourdir le pack";;
  esac
  gbfr3="$STAGE/fr3/$gblev.fr3"
  [ -e "$gbfr3" ] || fail "grassbake guard: '$gbbase' cuit pour le niveau '$gblev' mais aucun $gblev.fr3 n'entre dans le pack"
  gbfr3sz="$(stat -Lc %s "$gbfr3")"
  [ "$gbsz" = "$gbfr3sz" ] || fail "grassbake guard: '$gbbase' porte fr3_size=$gbsz alors que le $gblev.fr3 LIVRE fait $gbfr3sz octets — le moteur le REFUSERAIT a l'arrivee et le niveau perdrait son herbe. Regenere : scripts/shell/build_grass_bakes.sh"
  echo "[custom-pack] grassbake OK: $gbbase (niveau=$gblev fr3_size=$gbsz == $gblev.fr3 livre)"
done

# 2d. FIRST-PARTY recharged replacement textures — ALWAYS (committed owner-made set at
#     custom_assets/<game>/recharged_textures/<tpage>/<texname>/{<texname>.png + _height/
#     _normal/_roughness}; the base swap needs no build flag, the PBR maps feed the PBR
#     pipeline when compiled in). Extracted by LoaderActivity to <custom root>/
#     recharged_textures/** (zip paths preserved); runtime scans
#     get_bundled_recharged_textures_dir(). 0 is OK (set absent).
RTEX_SRC="custom_assets/${GAME}/recharged_textures"
RTEXB_SRC="custom_assets/${GAME}/recharged_textures_baked/astc"
# Gshield-load-and-crash: un materiau ENTIEREMENT cuit n'embarque plus ses PNG dans le pack
# ANDROID. Mesure: le pack passait de 429 223 609 a 516 813 859 octets (+20,4 %) en gardant les
# deux jeux, et la Shield a DEJA refuse un APK faute de place (INSTALL_FAILED_INSUFFICIENT_STORAGE,
# git log du 2026-08-26). Les PNG restent dans le depot pour le bureau x86, qui n'a pas d'ASTC et
# garde son chemin inchange.
# DEUX CONDITIONS, toutes les deux necessaires, sinon on garde les PNG du materiau :
#   1. chaque .png du materiau a son .ktx2 cuit — un materiau a moitie cuit qui perdrait ses PNG
#      n'aurait plus rien a montrer ;
#   2. le materiau ne porte PAS de _orm.png — l'ORM est deballe en trois plans (AO/rugosite/metal)
#      par le SEUL chemin PNG (LoaderStages.cpp:614-639) ; servir sa base depuis le niveau cuit
#      ferait disparaitre l'occlusion et le metal de ce materiau sans que rien ne le dise.
rtex_material_fully_baked(){
  local mdir="$1" rel_m bdir f stem
  rel_m="${mdir#"$ROOT/$RTEX_SRC/"}"
  bdir="$ROOT/$RTEXB_SRC/$rel_m"
  [ -d "$bdir" ] || return 1
  compgen -G "$mdir/*_orm.png" >/dev/null 2>&1 && return 1
  for f in "$mdir"/*.png; do
    [ -e "$f" ] || return 1
    stem="$(basename "$f" .png)"
    [ -f "$bdir/$stem.ktx2" ] || return 1
  done
  return 0
}
# (Gfont-regression, owner 2026-09-02 : « ça utilise des glyphs chinois de la font par défaut »)
# LA POLICE EST UN ACQUIS VALIDE ET ELLE VOYAGE ICI. Les deux atlas Urbanist sont GENERES
# localement (gitignore : ils compositent des pixels Naughty Dog) — sur un arbre propre le dossier
# n'existe pas, la boucle ci-dessous n'embarque rien, et le jeu retombe SANS ERREUR sur l'atlas
# d'origine, dont les cellules a-z de la grande police sont des kanji, avec un texte deja converti
# en minuscules. Un pack sans police n'est pas un pack degrade, c'est un jeu illisible : on
# regenere, et si ca echoue on REFUSE le pack. (Le texte, lui, part par le pack CGO : les deux
# moities de l'acquis n'ont pas le meme vehicule, d'ou cette garde au goulot du vehicule qui manque.)
FONT_ATLAS_DIR="$ROOT/$RTEX_SRC/gamefontnew"
if [ ! -s "$FONT_ATLAS_DIR/ascii.12lo.png" ] || [ ! -s "$FONT_ATLAS_DIR/ascii.24lo.png" ]; then
  echo "[custom-pack] POLICE : atlas Urbanist absent de $FONT_ATLAS_DIR — regeneration (gen_game_atlas.py)" >&2
  ( cd "$ROOT" && python3 recharged_assets/font/gen_game_atlas.py ) >&2 || true
fi
if [ ! -s "$FONT_ATLAS_DIR/ascii.12lo.png" ] || [ ! -s "$FONT_ATLAS_DIR/ascii.24lo.png" ]; then
  echo "[custom-pack] REFUS : les atlas de police Urbanist manquent et ne se regenerent pas ; un pack sans eux livre des kanji a la place des minuscules (acquis owner 2026-08-30)" >&2
  exit 1
fi
echo "[custom-pack] police Urbanist : 2 atlas presents ($(stat -c %s "$FONT_ATLAS_DIR/ascii.12lo.png")+$(stat -c %s "$FONT_ATLAS_DIR/ascii.24lo.png") octets)"

if [ -d "$ROOT/$RTEX_SRC" ]; then
  n_rtex=0
  n_rtex_skip=0
  declare -A RTEX_DECIDED=()
  while IFS= read -r tf; do
    [ -n "$tf" ] || continue
    mdir="$(dirname "$tf")"
    if [ -z "${RTEX_DECIDED[$mdir]:-}" ]; then
      if rtex_material_fully_baked "$mdir"; then RTEX_DECIDED[$mdir]=skip; else RTEX_DECIDED[$mdir]=keep; fi
    fi
    if [ "${RTEX_DECIDED[$mdir]}" = skip ]; then
      n_rtex_skip=$((n_rtex_skip + 1)); continue
    fi
    rel="${tf#"$ROOT/$RTEX_SRC/"}"
    mkdir -p "$STAGE/recharged_textures/$(dirname "$rel")"
    ln -s "$tf" "$STAGE/recharged_textures/$rel"
    MEMBERS+=("recharged_textures/$rel")
    n_rtex=$((n_rtex + 1))
  done < <(find "$ROOT/$RTEX_SRC" -type f -name '*.png' 2>/dev/null | sort)
  echo "[custom-pack] recharged textures: $n_rtex png embarques, $n_rtex_skip remplaces par leur cuisson ASTC"
fi

# 2e. BAKED recharged textures (KTX2/ASTC) — ALWAYS IF PRESENT, never required.
#     WHY: measured on the SHIELD, `stage texture took 1799 ms` at worst. Each PBR
#     material is 4 maps of 2048x2048 PNG, and the PNG path DECODES each one TWICE
#     (probe pass + re-fetch before upload, 151-330 ms per decode) and then spends
#     68-235 ms in glGenerateMipmap. The KTX2 path already in the engine (managed
#     pack) does an equivalent material in 87 ms: no decode, no mip generation, and
#     the GPU keeps 3.56 bpp (ASTC 6x6) instead of 32 bpp — the Redmi was holding
#     256 MB of RSS in uncompressed 2048x2048 RGBA maps.
#     PRODUCED BY: tools/bake_recharged_textures.py (needs astcenc; THIS SCRIPT DOES
#     NOT — baking is a separate step and its absence must never break a packaging).
#     The PNGs above are NOT removed: the x86 desktop has no ASTC and keeps its path.
#     Ships the .ktx2 AND the <material>.stats.json sidecars: those statistics
#     (normal-map DC, height mean / robust half-range / feature wavelength) used to
#     be computed at runtime FROM THE DECODED PIXELS, so without a decode they have
#     no other source and the material would render with default parameters.
if [ -d "$ROOT/$RTEXB_SRC" ]; then
  n_rtexb=0
  n_rtexb_k=0
  while IFS= read -r tf; do
    [ -n "$tf" ] || continue
    rel="${tf#"$ROOT/$RTEXB_SRC/"}"
    mkdir -p "$STAGE/recharged_textures_baked/astc/$(dirname "$rel")"
    ln -s "$tf" "$STAGE/recharged_textures_baked/astc/$rel"
    MEMBERS+=("recharged_textures_baked/astc/$rel")
    n_rtexb=$((n_rtexb + 1))
    case "$tf" in *.ktx2) n_rtexb_k=$((n_rtexb_k + 1));; esac
  done < <(find "$ROOT/$RTEXB_SRC" -type f \( -name '*.ktx2' -o -name '*.stats.json' \) \
             2>/dev/null | sort)
  echo "[custom-pack] baked recharged textures (ASTC/KTX2): $n_rtexb members ($n_rtexb_k .ktx2)"
else
  echo "[custom-pack] baked recharged textures (ASTC/KTX2): none (run tools/bake_recharged_textures.py — optional)"
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
  # A RE-BAKE must invalidate the pack exactly like a re-authored PNG does: without
  # this line a fresh KTX2 set would sit on disk while the APK kept the previous one.
  [ -d "$ROOT/custom_assets/${GAME}/recharged_textures_baked" ] && SRC_DIRS+=("$ROOT/custom_assets/${GAME}/recharged_textures_baked")
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
    # .ktx2 joins the list for the same reason: ASTC is a fixed-rate BLOCK format, already
    # compressed, so deflating it burns CPU on both sides (pack build AND phone extraction)
    # for a rounding error.
    zip -r -6 -X -q -n '.fr3:.meshweld:.grassbake:.png:.ktx2' "$ZIP_ABS" .
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
