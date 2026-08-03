#!/usr/bin/env bash
# scripts/package_hd_assets.sh <jak1|jak2|jak3> [--out <dir>]
#
# Produces the EXTERNAL "HD models" asset pack: <game>_hd_assets.zip.
#
# ============================================================================
# ARCHITECTURE IP (owner 2026-08-02) — why this pack exists and is SEPARATE
# ============================================================================
# The HD character models derive from the user's Jak 2 / Jak 3 dumps = Naughty
# Dog IP. Per the owner rule they must:
#   1. be GENERATED LOCALLY from the user's dump (gated on that dump — see below);
#   2. NEVER ship inside the APK / custom pack / binary (that would distribute ND IP);
#   3. ship in the EXTERNAL asset pack, loaded from external storage on device,
#      exactly like the original-game assets the user provides.
#
# This is DISTINCT from the two other packs, both of which EXCLUDE the enhanced fr3:
#   - the base pack  scripts/package_game_assets.sh -> <game>_assets.zip  (untouched
#     dump only; the hard-locked .autoport/lib/release_verify.sh refuses any
#     */enhanced/* member there, so the ND HD cannot ride the base pack);
#   - the APK custom pack  android/build_custom_pack.sh -> <game>_custom.zip  (our own
#     "Recharged" derived data; its nd_hd_exclusion_guard() refuses enhanced/ members).
#
# The pack's entries are  fr3/enhanced/<name>.fr3 . On device the owner picks this
# archive in LoaderActivity's generic archive extractor, which streams every entry
# into <gameRoot>/assets/, so it lands at <gameRoot>/assets/fr3/enhanced/<name>.fr3 —
# precisely where hd_fr3_path() (game/.../loader/Loader.cpp) resolves the enhanced fr3
# from (Loader's m_base_path == file_util::get_fr3_dir() == <external root>/assets/fr3).
#
# DUMPS GATE: HD is ND IP, so this pack is produced ONLY if the donor dump is present.
# Absent -> no HD pack (no-op success). Per-game donor mapping mirrors build.sh.
set -euo pipefail

usage(){ echo "usage: $0 <jak1|jak2|jak3> [--out <dir>]" >&2; exit 2; }

GAME="${1:-}"
[ -n "$GAME" ] || usage
shift || true
case "$GAME" in jak1|jak2|jak3) ;; *) echo "[hd-assets] FATAL: unknown game '$GAME'" >&2; usage;; esac

OUT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT_DIR="${2:-}"; shift 2 || usage;;
    --out=*) OUT_DIR="${1#--out=}"; shift;;
    *) echo "[hd-assets] FATAL: unknown arg '$1'" >&2; usage;;
  esac
done

fail(){ echo "[hd-assets] FATAL: $*" >&2; exit 1; }
log(){ echo "[hd-assets] $*"; }

cd "$(git rev-parse --show-toplevel)"
ROOT="$(pwd)"

[ -n "$OUT_DIR" ] || OUT_DIR="out/artifacts"
mkdir -p "$OUT_DIR"
OUT_ABS="$(cd "$OUT_DIR" && pwd)"

# Per-game donor dump (the ND rip source). Keep in sync with build.sh's mapping.
donor_dump_for_game(){ case "$1" in jak1) echo "iso_data/jak2";; *) echo "";; esac; }
DONOR_DUMP="$(donor_dump_for_game "$GAME")"

# --- DUMPS GATE ---------------------------------------------------------------
if [ -z "$DONOR_DUMP" ] || \
   [ -z "$(find "$DONOR_DUMP" -maxdepth 2 -type f ! -name '.gitignore' -print -quit 2>/dev/null)" ]; then
  log "donor dump '${DONOR_DUMP:-<none for $GAME>}' absent — HD is ND IP derived from it, so it is unavailable; no HD asset pack produced (stock)."
  # No-op success: with no dump there is no legitimate HD to package.
  exit 0
fi
log "donor dump '$DONOR_DUMP' present — packaging ND-derived HD for EXTERNAL delivery (never the APK)."

ENH_DIR="out/${GAME}/fr3/enhanced"
[ -d "$ENH_DIR" ] || fail "no $ENH_DIR — run the enhanced HD bake first (scripts/shell/build_enhanced_models.sh, or ./build.sh android-arm64 --hd-models)"

# --- Enumerate the enhanced fr3 (entries: fr3/enhanced/<file>) ----------------
INDEX="$(mktemp)"
trap 'rm -f "$INDEX"' EXIT
while IFS= read -r -d '' f; do
  base="$(basename "$f")"
  printf 'fr3/enhanced/%s\t%s\n' "$base" "$ROOT/$f" >> "$INDEX"
done < <(find "$ENH_DIR" -maxdepth 1 -type f -name '*.fr3' -print0 | sort -z)

# Grecharged-hd-models3: also carry the anim-retarget HD art-group (ND-derived, external-only).
# Entry hd/jak-hd-ag.go extracts to <gameRoot>/assets/hd/jak-hd-ag.go, which Loader.cpp copies at boot
# into <jak_project_dir>/out/jak1/obj/ (where GOAL loado resolves it). Never in the APK/binary.
HD_AG="recharged_assets/hd_anim/jak-hd-ag.go"
[ -f "$ROOT/$HD_AG" ] && printf 'hd/%s\t%s\n' "jak-hd-ag.go" "$ROOT/$HD_AG" >> "$INDEX"

FILE_COUNT=$(wc -l < "$INDEX" | tr -d ' ')
[ "$FILE_COUNT" -gt 0 ] || fail "$ENH_DIR holds no *.fr3 — nothing to package. Re-run the enhanced HD bake."

# --- HD-ONLY GUARD: every entry MUST be an enhanced fr3, nothing else ----------
# This pack carries ND-derived HD ONLY. Anything else here would be a routing mistake.
BAD_ENTRY="$(cut -f1 "$INDEX" | grep -vE '^(fr3/enhanced/[^/]+\.fr3|hd/[^/]+\.go)$' | head -1 || true)"
[ -z "$BAD_ENTRY" ] || fail "NON-HD ENTRY '$BAD_ENTRY' in the HD pack index — this archive carries fr3/enhanced/*.fr3 + hd/*.go (ND-derived HD) ONLY."

ZIP_ABS="$OUT_ABS/${GAME}_hd_assets.zip"
MANIFEST_TXT="$OUT_ABS/${GAME}_hd_assets.manifest.txt"

# --- Pack + content-derived version via python3 (deterministic order) ----------
export GAME FILE_COUNT DONOR_DUMP ZIP_ABS MANIFEST_TXT INDEX
python3 - <<'PY'
import hashlib, os, sys, zipfile

game         = os.environ["GAME"]
file_count   = int(os.environ["FILE_COUNT"])
donor        = os.environ["DONOR_DUMP"]
zip_abs      = os.environ["ZIP_ABS"]
manifest_txt = os.environ["MANIFEST_TXT"]
index_path   = os.environ["INDEX"]

entries = []
with open(index_path) as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        zip_entry, abs_source = line.split("\t", 1)
        entries.append((zip_entry, abs_source))
entries.sort(key=lambda e: e[0])
if len(entries) != file_count:
    sys.stderr.write(f"[hd-assets] FATAL: index has {len(entries)} entries, expected {file_count}\n")
    sys.exit(1)

md5 = hashlib.md5()
raw_bytes = 0
per_member = []
for zip_entry, src in entries:
    h = hashlib.sha256()
    with open(src, "rb") as fh:
        while True:
            chunk = fh.read(1 << 20)
            if not chunk:
                break
            md5.update(chunk)
            h.update(chunk)
            raw_bytes += len(chunk)
    per_member.append((zip_entry, h.hexdigest()))
version = "c" + md5.hexdigest()[:12]

manifest = (
    "# Generated by scripts/package_hd_assets.sh — do not edit.\n"
    "# EXTERNAL HD MODELS PACK — Naughty-Dog-DERIVED (from the user's Jak2/Jak3 dump).\n"
    "# Ships ONLY in external storage, NEVER in the APK / custom pack / binary. Extract to\n"
    "# <external root>/assets/ so entries land at <external root>/assets/fr3/enhanced/<name>.fr3,\n"
    "# where hd_fr3_path() (Loader.cpp) reads them when ENHANCED MODELS is ON. Gated on the\n"
    f"# donor dump {donor} being present at build time.\n"
    f"game={game}\n"
    f"donor_dump={donor}\n"
    f"class=nd-derived-hd-external\n"
    f"file_count={file_count}\n"
    f"raw_bytes={raw_bytes}\n"
    f"version={version}\n"
)
for zip_entry, sha in per_member:
    manifest += f"{zip_entry} {sha}\n"

tmp = zip_abs + ".tmp"
if os.path.exists(tmp):
    os.remove(tmp)
with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_STORED, allowZip64=True) as zf:
    for zip_entry, src in entries:
        zf.write(src, arcname=zip_entry)
    zf.writestr("hd_assets.manifest.properties", manifest)
os.replace(tmp, zip_abs)

with open(manifest_txt, "w") as fh:
    fh.write(manifest)

zip_bytes = os.path.getsize(zip_abs)
sys.stderr.write(
    f"[hd-assets]   version={version} raw={raw_bytes}B zip={zip_bytes}B files={file_count}\n"
)
PY

ZIP_BYTES=$(stat -c %s "$ZIP_ABS")
log "HD-ASSETS done: $ZIP_ABS ($ZIP_BYTES bytes, $FILE_COUNT enhanced fr3) — ND-derived, EXTERNAL-ONLY (never the APK), gated on $DONOR_DUMP"
echo "HD-ASSETS $ZIP_ABS $ZIP_BYTES files=$FILE_COUNT class=nd-derived-hd-external donor=$DONOR_DUMP"
