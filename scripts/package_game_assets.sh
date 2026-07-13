#!/usr/bin/env bash
# scripts/package_game_assets.sh <jak1|jak2|jak3> [--out <dir>]
#
# Produces the ARCH-INDEPENDENT "extracted original assets" archive for a game:
# the data that never changes across releases (audio/text/vis/str + renderer
# texture packs + jak1 recharged HUD PNGs). It DELIBERATELY excludes *.CGO/*.DGO
# — those are per-arch compiled code, shipped alongside the game binary, not with
# this archive.
#
# Rigor is modelled on android/build_asset_bundle.sh: hard-fail on missing/empty
# inputs, a CONTENT-derived version (md5 over all file contents in sorted path
# order), and NO language filtering — this REPLACES the old AGP 2 GB-cap
# workaround that dropped the non-English VAGWADs. All VAGWAD.<lang> present are
# archived.
#
# zip64-safe: jak2's raw data exceeds 4 GB, so we pack via python3's zipfile with
# allowZip64=True (streamed file-by-file from disk — no giant intermediate copy).
#
# Output (in out/artifacts/ by default):
#   <game>_assets.zip
#   <game>_assets.manifest.txt   (sibling copy of the in-zip manifest)
set -euo pipefail

usage(){ echo "usage: $0 <jak1|jak2|jak3> [--out <dir>]" >&2; exit 2; }

GAME="${1:-}"
[ -n "$GAME" ] || usage
shift || true
case "$GAME" in jak1|jak2|jak3) ;; *) echo "[assets] FATAL: unknown game '$GAME'" >&2; usage;; esac

OUT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT_DIR="${2:-}"; shift 2 || usage;;
    --out=*) OUT_DIR="${1#--out=}"; shift;;
    *) echo "[assets] FATAL: unknown arg '$1'" >&2; usage;;
  esac
done

fail(){ echo "[assets] FATAL: $*" >&2; exit 1; }

cd "$(git rev-parse --show-toplevel)"
ROOT="$(pwd)"

[ -n "$OUT_DIR" ] || OUT_DIR="out/artifacts"
mkdir -p "$OUT_DIR"
OUT_ABS="$(cd "$OUT_DIR" && pwd)"

ISO_DIR="out/${GAME}/iso"
FR3_DIR="out/${GAME}/fr3"
RHUD_DIR="recharged_assets"   # jak1 HUD PNGs (repo root)

[ -d "$ISO_DIR" ] || fail "no $ISO_DIR — run the PC extract/build first"
[ -d "$FR3_DIR" ] || fail "no $FR3_DIR — run the PC fr3 build first"
[ -n "$(find "$ISO_DIR" -maxdepth 1 -type f -print -quit)" ] || fail "$ISO_DIR is empty"
[ -n "$(find "$FR3_DIR" -maxdepth 1 -type f -print -quit)" ] || fail "$FR3_DIR is empty"

# --- Language completeness (NO filtering) --------------------------------------
# Collect every VAGWAD.<lang> present. For jak2 the owner wants FR audio restored,
# so HARD-FAIL if fewer than 2 distinct language banks are present.
mapfile -t VAGWADS < <(find "$ISO_DIR" -maxdepth 1 -type f -name 'VAGWAD.*' -printf '%f\n' | sort)
VAG_LANGS=""
for v in "${VAGWADS[@]}"; do
  lang="${v#VAGWAD.}"
  VAG_LANGS="${VAG_LANGS:+$VAG_LANGS,}$lang"
done
N_VAG=${#VAGWADS[@]}
echo "[assets] VAGWAD language banks found: $N_VAG${VAG_LANGS:+ ($VAG_LANGS)}"
if [ "$GAME" = "jak2" ] && [ "$N_VAG" -lt 2 ]; then
  fail "jak2 needs >=2 VAGWAD.<lang> banks (owner wants FR audio restored); found $N_VAG${VAG_LANGS:+ ($VAG_LANGS)} in $ISO_DIR"
fi

# --- Enumerate the archive's source files (relative paths + in-zip prefix) ------
# We build a NUL-delimited "index" of "<zip_entry>\t<abs_source>" lines and feed it
# to python3 for both the content-md5 version AND the zip writer (single ordering).
INDEX="$(mktemp)"
trap 'rm -f "$INDEX"' EXIT

# iso/<file> for every file in out/<game>/iso EXCEPT *.CGO / *.DGO
while IFS= read -r -d '' f; do
  base="$(basename "$f")"
  case "$base" in *.CGO|*.DGO) continue;; esac
  printf 'iso/%s\t%s\n' "$base" "$ROOT/$f" >> "$INDEX"
done < <(find "$ISO_DIR" -maxdepth 1 -type f -print0)

# fr3/<file> for every file in out/<game>/fr3
while IFS= read -r -d '' f; do
  printf 'fr3/%s\t%s\n' "$(basename "$f")" "$ROOT/$f" >> "$INDEX"
done < <(find "$FR3_DIR" -maxdepth 1 -type f -print0)

# recharged_assets/<file>.png (jak1 HUD), if the dir exists
N_RHUD=0
if [ -d "$RHUD_DIR" ]; then
  while IFS= read -r -d '' f; do
    printf 'recharged_assets/%s\t%s\n' "$(basename "$f")" "$ROOT/$f" >> "$INDEX"
    N_RHUD=$((N_RHUD + 1))
  done < <(find "$RHUD_DIR" -maxdepth 1 -type f -name '*.png' -print0)
fi

FILE_COUNT=$(wc -l < "$INDEX" | tr -d ' ')
[ "$FILE_COUNT" -gt 0 ] || fail "no files selected for the archive"

echo "[assets] selected $FILE_COUNT files (iso data + fr3${N_RHUD:+ + $N_RHUD recharged PNGs}); computing content version + packing (nice)…"

ZIP_ABS="$OUT_ABS/${GAME}_assets.zip"
MANIFEST_TXT="$OUT_ABS/${GAME}_assets.manifest.txt"

# --- Pack + version via python3 (zip64-safe, streamed) --------------------------
# Sorted by zip-entry path for a deterministic order. version = md5 of all file
# CONTENTS in that sorted order (== build_asset_bundle.sh content-derived scheme).
export GAME FILE_COUNT VAG_LANGS ZIP_ABS MANIFEST_TXT INDEX
nice python3 - <<'PY'
import hashlib, os, sys, zipfile

game        = os.environ["GAME"]
file_count  = int(os.environ["FILE_COUNT"])
vag_langs   = os.environ.get("VAG_LANGS", "")
zip_abs     = os.environ["ZIP_ABS"]
manifest_txt= os.environ["MANIFEST_TXT"]
index_path  = os.environ["INDEX"]

entries = []  # (zip_entry, abs_source)
with open(index_path, "r") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        zip_entry, abs_source = line.split("\t", 1)
        entries.append((zip_entry, abs_source))

# Deterministic: sort by in-zip path.
entries.sort(key=lambda e: e[0])

if len(entries) != file_count:
    sys.stderr.write(f"[assets] FATAL: index has {len(entries)} entries, expected {file_count}\n")
    sys.exit(1)

# --- content-md5 version (streamed, ~1.6 GiB for jak1) ---
md5 = hashlib.md5()
raw_bytes = 0
for zip_entry, src in entries:
    with open(src, "rb") as fh:
        while True:
            chunk = fh.read(1 << 20)
            if not chunk:
                break
            md5.update(chunk)
            raw_bytes += len(chunk)
version = "c" + md5.hexdigest()[:12]

manifest = (
    "# Generated by scripts/package_game_assets.sh — do not edit.\n"
    f"game={game}\n"
    f"file_count={file_count}\n"
    f"raw_bytes={raw_bytes}\n"
    f"version={version}\n"
    f"vagwad_langs={vag_langs}\n"
)

tmp = zip_abs + ".tmp"
if os.path.exists(tmp):
    os.remove(tmp)

with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED,
                     allowZip64=True, compresslevel=6) as zf:
    for zip_entry, src in entries:
        # streamed from disk by zipfile.write — no full-file read into memory.
        zf.write(src, arcname=zip_entry)
    zf.writestr("assets.manifest.properties", manifest)

os.replace(tmp, zip_abs)

with open(manifest_txt, "w") as fh:
    fh.write(manifest)

zip_bytes = os.path.getsize(zip_abs)
sys.stderr.write(
    f"[assets]   version={version} raw={raw_bytes}B zip={zip_bytes}B files={file_count}\n"
)
PY

ZIP_BYTES=$(stat -c %s "$ZIP_ABS")
echo "[assets] done: $ZIP_ABS ($ZIP_BYTES bytes)"
echo "ARCHIVE $ZIP_ABS $ZIP_BYTES files=$FILE_COUNT vagwads=${VAG_LANGS:-none}"
