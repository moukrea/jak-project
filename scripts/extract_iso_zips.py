#!/usr/bin/env python3
"""
Extract PS2 ISO contents from user-supplied zip files into iso_data/jak{1,2,3}/.

Matches the layout the OpenGOAL extractor (common/util/read_iso_file.cpp)
produces from a .iso:
  - Raw ISO9660 names (uppercase)
  - Strips the ';1' version suffix
  - Renames WATER_AN.CGO -> WATER-AN.CGO

Usage:
    python3 scripts/extract_iso_zips.py [--keep-iso] [--keep-zip] [--dry-run]

By default, both the temporary .iso and the original .zip are deleted after
successful extraction to free disk space.
"""

from __future__ import annotations
import argparse
import io
import os
import shutil
import sys
import time
import zipfile
from pathlib import Path

try:
    import pycdlib  # type: ignore
except ImportError:
    print("FATAL: pycdlib not installed. Run: python3 -m pip install --user pycdlib", file=sys.stderr)
    sys.exit(2)


REPO_ROOT = Path(__file__).resolve().parent.parent
DOWNLOADS = Path.home() / "Téléchargements"
if not DOWNLOADS.exists():
    DOWNLOADS = Path.home() / "Downloads"

# Match user's zip filenames to the OpenGOAL game keys. Matching is by
# substring on the filename (case-insensitive) for robustness.
GAME_PATTERNS = [
    ("jak1", ["precursor legacy", "jak and daxter", "jak1"]),
    ("jak2", ["jak ii", "jak 2", "jak2"]),
    ("jak3", ["jak 3", "jak iii", "jak3"]),
]


def human(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024  # type: ignore[assignment]
    return f"{n:.1f} TB"


def find_zip_for_game(downloads: Path, hints: list[str]) -> Path | None:
    if not downloads.exists():
        return None
    for entry in sorted(downloads.iterdir()):
        if entry.suffix.lower() != ".zip":
            continue
        low = entry.name.lower()
        for hint in hints:
            if hint in low:
                return entry
    return None


def stream_iso_from_zip(zip_path: Path, dest_iso: Path) -> None:
    """Copy the first *.iso member of `zip_path` to `dest_iso`."""
    dest_iso.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as zf:
        iso_member = next(
            (m for m in zf.infolist() if m.filename.lower().endswith(".iso")), None
        )
        if iso_member is None:
            raise RuntimeError(f"No .iso member inside {zip_path.name}")
        total = iso_member.file_size
        print(f"  unzip → {dest_iso.name}  ({human(total)})", flush=True)
        with zf.open(iso_member, "r") as src, open(dest_iso, "wb") as dst:
            copied = 0
            chunk = 16 * 1024 * 1024
            tick = time.monotonic()
            while True:
                buf = src.read(chunk)
                if not buf:
                    break
                dst.write(buf)
                copied += len(buf)
                if time.monotonic() - tick > 5:
                    pct = 100.0 * copied / total
                    print(f"    {pct:5.1f}%  {human(copied)}/{human(total)}", flush=True)
                    tick = time.monotonic()


def _clean_iso_name(name: str) -> str:
    # ISO9660 file names have a ';N' version suffix; OpenGOAL strips it.
    if ";" in name:
        name = name.split(";", 1)[0]
    # Special-case OpenGOAL rename (common/util/read_iso_file.cpp).
    if name == "WATER_AN.CGO":
        return "WATER-AN.CGO"
    return name


def extract_iso_to_dir(iso_path: Path, out_dir: Path) -> int:
    """Walk the ISO9660 filesystem and write each file under out_dir.

    Returns number of files written.
    """
    iso = pycdlib.PyCdlib()
    iso.open(str(iso_path))
    out_dir.mkdir(parents=True, exist_ok=True)

    n_files = 0
    bytes_written = 0
    tick = time.monotonic()

    try:
        # Walk raw ISO9660 ('iso_path' keyword tells pycdlib to use the
        # ISO9660 namespace; Rock Ridge / Joliet are not enabled by default).
        for dirpath, _dirnames, filenames in iso.walk(iso_path="/"):
            # dirpath looks like '/' or '/DGO' (uppercase, no ';1' suffix on dirs)
            rel = dirpath.lstrip("/")
            local_dir = out_dir / rel
            local_dir.mkdir(parents=True, exist_ok=True)
            for raw_name in filenames:
                clean = _clean_iso_name(raw_name)
                iso_file = dirpath.rstrip("/") + "/" + raw_name
                target = local_dir / clean
                with open(target, "wb") as fout:
                    iso.get_file_from_iso_fp(fout, iso_path=iso_file)
                n_files += 1
                bytes_written += target.stat().st_size
                if time.monotonic() - tick > 5:
                    print(f"    {n_files} files, {human(bytes_written)}", flush=True)
                    tick = time.monotonic()
    finally:
        iso.close()

    return n_files


def verify_extraction(out_dir: Path) -> tuple[bool, str]:
    """OpenGOAL's first sanity check: extracted dir must contain DGO/."""
    if not (out_dir / "DGO").is_dir():
        # Some PS2 ISOs put files under a SYSTEM.CNF-pointed root; check
        # one level down in case pycdlib produced a single top-level dir.
        subs = [p for p in out_dir.iterdir() if p.is_dir()]
        if len(subs) == 1 and (subs[0] / "DGO").is_dir():
            return False, f"DGO/ found nested under {subs[0].name}/ — flatten manually"
        return False, "no DGO/ directory found"
    n_dgo = sum(1 for _ in (out_dir / "DGO").iterdir())
    return True, f"DGO/ present with {n_dgo} entries"


def process_game(
    game: str,
    zip_path: Path,
    keep_iso: bool,
    keep_zip: bool,
    dry_run: bool,
) -> bool:
    print(f"\n=== {game.upper()} ===")
    print(f"  zip: {zip_path}  ({human(zip_path.stat().st_size)})")
    target = REPO_ROOT / "iso_data" / game
    # The repo ships an empty placeholder dir with only a .gitignore;
    # treat that as empty. Skip only if there's already real content.
    real_entries = (
        [p for p in target.iterdir() if not p.name.startswith(".")]
        if target.exists()
        else []
    )
    if real_entries:
        print(f"  iso_data/{game}/ already has {len(real_entries)} entries — "
              f"skipping (delete its contents to re-run)")
        return True

    if dry_run:
        print("  (dry-run) would unzip → extract → place under iso_data/")
        return True

    # Stage the temp .iso outside iso_data/ so it can't collide with the
    # extracted contents that land in the same dir.
    staging = REPO_ROOT / ".tmp-iso-staging"
    staging.mkdir(exist_ok=True)
    tmp_iso = staging / f"{game}.iso"
    try:
        stream_iso_from_zip(zip_path, tmp_iso)
        print(f"  iso extract → iso_data/{game}/")
        n = extract_iso_to_dir(tmp_iso, target)
        print(f"  wrote {n} files")
        ok, msg = verify_extraction(target)
        print(f"  verify: {msg}")
        if not ok:
            print(f"  FAIL: {msg}", file=sys.stderr)
            return False
    except Exception as e:
        print(f"  ERROR during {game}: {e}", file=sys.stderr)
        return False
    finally:
        if tmp_iso.exists() and not keep_iso:
            tmp_iso.unlink()
            print(f"  rm {tmp_iso.name}")

    if not keep_zip:
        zip_size = zip_path.stat().st_size
        zip_path.unlink()
        print(f"  rm {zip_path.name}  (freed {human(zip_size)})")

    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep-iso", action="store_true",
                        help="keep the temporary .iso file after extraction")
    parser.add_argument("--keep-zip", action="store_true",
                        help="keep the original ~/Téléchargements/*.zip file")
    parser.add_argument("--dry-run", action="store_true",
                        help="show what would be done without writing")
    parser.add_argument("--game", choices=("jak1", "jak2", "jak3"),
                        help="process only the specified game")
    args = parser.parse_args()

    print(f"repo root: {REPO_ROOT}")
    print(f"downloads: {DOWNLOADS}")
    if not DOWNLOADS.exists():
        print(f"FATAL: downloads directory not found", file=sys.stderr)
        return 1

    failed = []
    for game, hints in GAME_PATTERNS:
        if args.game and game != args.game:
            continue
        zip_path = find_zip_for_game(DOWNLOADS, hints)
        if zip_path is None:
            print(f"\n=== {game.upper()} ===")
            print(f"  no zip matching {hints} found in {DOWNLOADS}, skipping")
            continue
        ok = process_game(game, zip_path, args.keep_iso, args.keep_zip, args.dry_run)
        if not ok:
            failed.append(game)

    print()
    if failed:
        print(f"FAILED: {failed}")
        return 1
    print("All extractions complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
