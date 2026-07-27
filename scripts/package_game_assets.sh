#!/usr/bin/env bash
# scripts/package_game_assets.sh <jak1|jak2|jak3> [--out <dir>]
#
# Produces the ARCH-INDEPENDENT "ORIGINAL GAME DUMP" archive for a game. Its content
# is out/<game>/iso ONLY — the untouched PS2 disc data (audio/text/vis/str + VAGWADs)
# as it came out of the dump. It DELIBERATELY excludes *.CGO/*.DGO — those are
# per-arch compiled code, shipped alongside the game binary, not with this archive.
#
# OWNER STRUCTURAL RULE (2026-07-27): "tout ce qui n'est pas original (sorti du dump
# du jeu sans être modifié) doit être inclus à l'APK et pas dans les assets de base
# séparés !" The criterion is ORIGIN, not size. So everything DERIVED — the .fr3
# levels (our extractor's output, carrying the weld/normals/orientation/pre-subdivision),
# the .meshweld and .grassbake sidecars, the enhanced-HD fr3, the recharged HUD PNGs —
# has MOVED OUT of this archive and into the APK's custom pack, built by
# android/build_custom_pack.sh. This archive is now pure original data: it never
# changes, so it can be laid down on a device ONCE and never re-pushed.
#
# The iso-only guard below enforces that, and it is the STRUCTURAL half of the
# round-30 fix. The bug was not that the external copy of a sidecar was old; it was
# that a SECOND COPY EXISTED AT ALL. With zero overlap between the two packs there is
# no freshness conflict left to lose. Bake-freshness responsibility now lives entirely
# in android/build_custom_pack.sh (its data_freshness_guard), which is where the
# derived data ships.
#
# Env:
#   PACK_LIST_ONLY=<non-empty>   Enumerate + run the iso-only guard, print the entry
#                                count and a per-top-level-prefix histogram (counts +
#                                total bytes), then exit 0 WITHOUT writing the ~1.1 GB
#                                zip. Use this to verify the original/derived split
#                                cheaply.
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

# out/<game>/fr3 is deliberately NOT referenced any more: nothing derived rides in
# this archive, so its presence/emptiness is not this script's business. The fr3 tree
# is validated by android/build_custom_pack.sh, which ships it.
[ -d "$ISO_DIR" ] || fail "no $ISO_DIR — run the PC extract/build first"
[ -n "$(find "$ISO_DIR" -maxdepth 1 -type f -print -quit)" ] || fail "$ISO_DIR is empty"

# --- Bake-freshness responsibility MOVED OUT ------------------------------------
# A round-30 bake-staleness preflight used to sit right here (bake-source mtime vs
# .meshweld, plus the embedded-kBakeVersion check). It no longer belongs in this
# script: this archive does not ship sidecars any more, so it has nothing to be stale
# about. Those checks now live where the derived data actually ships — see
# data_freshness_guard() in android/build_custom_pack.sh, which runs them on BOTH the
# idempotent-skip path and the freshly-written-zip path, and additionally refuses a
# pack that is MISSING a derived file present on disk (its check 4).
#
# What replaces it here is the INVERSE guard, further down once the index is built:
# nothing derived may ride in the base pack at all.

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

# That is the WHOLE index. Three enumerations used to follow this one and they are
# gone on purpose:
#   fr3/<file>              (26 .fr3 + 26 .meshweld + 3 .grassbake)
#   fr3/enhanced/<file>     (enhanced-HD overlay)
#   recharged_assets/<file>.png  (jak1 HUD)
# All three are DERIVED — produced or modified by our chain, not "sorti du dump du jeu
# sans être modifié" — so by the owner's structural rule they ship in the APK's custom
# pack (android/build_custom_pack.sh), never here. Keeping a second copy in this
# archive is precisely what let a STALE EXTERNAL COPY win for two rounds: the runtime
# resolved the sidecars from external storage, so a corrected pack inside the APK was
# read by nobody and the owner played two-day-old geometry twice. One copy, one owner.

FILE_COUNT=$(wc -l < "$INDEX" | tr -d ' ')
[ "$FILE_COUNT" -gt 0 ] || fail "no files selected for the archive"

# --- ISO-ONLY GUARD ------------------------------------------------------------
# Nothing derived may ride in the base pack. This is the structural half of the
# round-30 fix: the bug was not that the external copy was old, it was that a second
# copy existed at all.
BAD_ENTRY="$(cut -f1 "$INDEX" | grep -vE '^iso/[^/]+$' | head -1 || true)"
if [ -n "$BAD_ENTRY" ]; then
  fail "NON-ORIGINAL ENTRY '$BAD_ENTRY' in the base pack index — this archive carries out/${GAME}/iso ONLY (the untouched game dump). Everything our chain produces or modifies ships in the APK's custom pack: add it to android/build_custom_pack.sh instead. A second copy here is what let a stale external file beat the corrected one in the APK."
fi

# --- PACK_LIST_ONLY: verify the split without writing a 1.1 GB zip ---------------
# The zip write is the expensive part (~1.1 GB, minutes, and it is what a 97%-full
# disk cannot afford to do casually). Everything that DECIDES the archive's content —
# the enumeration and the iso-only guard above — has already run at this point, so the
# split is fully verifiable here. Exits BEFORE the python pack step.
if [ -n "${PACK_LIST_ONLY:-}" ]; then
  echo "[assets] PACK_LIST_ONLY: no zip will be written."
  echo "[assets]   game=${GAME}"
  echo "[assets]   entries=${FILE_COUNT}"
  echo "[assets]   top-level in-zip prefix histogram:"
  INDEX="$INDEX" python3 - <<'PY'
import os
counts, byts = {}, {}
with open(os.environ["INDEX"]) as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        entry, src = line.split("\t", 1)
        pfx = entry.split("/", 1)[0] + "/" if "/" in entry else "(root)"
        counts[pfx] = counts.get(pfx, 0) + 1
        byts[pfx] = byts.get(pfx, 0) + os.path.getsize(src)
for pfx in sorted(counts):
    print("[assets]     %-22s %5d entries  %14d bytes" % (pfx, counts[pfx], byts[pfx]))
print("[assets]     %-22s %5d entries  %14d bytes"
      % ("TOTAL", sum(counts.values()), sum(byts.values())))
PY
  exit 0
fi

echo "[assets] selected $FILE_COUNT files (out/${GAME}/iso ONLY — original dump data; all derived assets ship in the APK custom pack); computing content version + packing (nice)…"

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
    "# ORIGINAL GAME DUMP ONLY: every entry is iso/<file> from out/<game>/iso,\n"
    "# byte-identical to the disc extract. It carries NO derived data — no .fr3, no\n"
    "# .meshweld, no .grassbake, no enhanced/, no recharged_assets. All of that ships\n"
    "# inside the APK's custom pack (android/build_custom_pack.sh) per the owner rule\n"
    "# that anything not straight out of the dump belongs in the APK. Consequence:\n"
    "# this archive never changes, so it can be laid down once and never re-pushed.\n"
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
echo "[assets] done: $ZIP_ABS ($ZIP_BYTES bytes) — ORIGINAL DUMP ONLY (iso/); derived assets ship in the APK custom pack via android/build_custom_pack.sh"
echo "ARCHIVE $ZIP_ABS $ZIP_BYTES files=$FILE_COUNT vagwads=${VAG_LANGS:-none} content=iso-only"
