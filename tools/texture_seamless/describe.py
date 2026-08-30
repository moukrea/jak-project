#!/usr/bin/env python3
"""Build a short description of what every texture depicts.

Two sources, in this order:

1. **The code.**  The game names things, and those names survive decompilation:
   the texture's own name, the tpage it lives in (level + category), the merc
   model / tie prototype / shrub prototype it is painted on, which levels it
   appears in, whether it tiles and how many times, and whether it is opaque,
   an alpha cutout, or blended.  This is free, exact, and already tells you
   that `vil-hut-wood-01` is painted on `vil1-roofsupport.mb` and `vil1-hut-door.mb`.

2. **Vision.**  What the image actually shows -- material, colour, motif --
   which no name gives you.  Textures are batched into labelled contact sheets
   and sent to Haiku through the `claude` CLI, one request per sheet rather
   than one per texture, because the per-request overhead dwarfs a 128x128
   image.

Stage 1 alone:   python3 describe.py <root> --tiling <csv> --draw-modes <dir> -o out.csv
Add stage 2:     ... --vision --batch 16 --jobs 6
"""

from __future__ import annotations

import argparse
import collections
import csv
import glob
import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image, ImageDraw

# tpage suffix -> what that bucket is for, in the engine's own terms
CATEGORY = {
    "tfrag": "level background geometry",
    "pris": "characters and animated props",
    "shrub": "foliage and small scattered props",
    "alpha": "transparent / additive effects",
    "water": "water surfaces",
}


def parse_tpage(tpage: str):
    m = re.match(r"^(.*)-vis-(tfrag|pris|shrub|alpha|water)$", tpage)
    if m:
        return m.group(1), CATEGORY[m.group(2)]
    special = {
        "common": (None, "shared across levels"),
        "Hud": (None, "on-screen HUD"),
        "effects": (None, "particle and effect sprites"),
        "environment-generic": (None, "generic environment"),
        "gamefontnew": (None, "font glyph atlas"),
        "eichar": (None, "Jak's own model"),
    }
    if tpage in special:
        return special[tpage]
    return None, "uncategorised"


def load_owners(draw_modes: Path):
    owners = collections.defaultdict(collections.Counter)
    alpha = collections.defaultdict(set)
    for f in sorted(glob.glob(str(draw_modes / "*-draw-modes.csv"))):
        with open(f) as fh:
            for r in csv.DictReader(fh):
                k = (r["tpage"], r["texture"])
                for o in r["owner"].split("|"):
                    if o:
                        owners[k][o] += 1
                alpha[k].add(("cutout" if r["alpha_test"] == "1" else None,
                              "blended" if r["alpha_blend"] == "1" else None))
    return owners, alpha


def code_context(row, owners, alpha) -> str:
    """One line of everything the code knows, written for a reader."""
    k = (row["tpage"], row["name"])
    level, cat = parse_tpage(row["tpage"])
    bits = [f"asset name '{row['name']}'", f"{row['width']}x{row['height']}", cat]
    if level:
        bits.append(f"level '{level}'")
    if row.get("levels"):
        lv = row["levels"].split("|")
        if len(lv) > 1 or (level and lv[0] != level):
            bits.append("used in " + ", ".join(lv[:4]))
    top = [o for o, _ in owners.get(k, collections.Counter()).most_common(3)]
    if top:
        bits.append("painted on " + ", ".join(top))
    if row.get("draw_kinds"):
        bits.append("drawn as " + row["draw_kinds"].replace("|", "+"))
    modes = {m for pair in alpha.get(k, set()) for m in pair if m}
    if modes:
        bits.append("+".join(sorted(modes)))
    v = row.get("verdict", "")
    if v == "both":
        bits.append(f"tiles both ways (up to {row.get('max_tiles_h') or '?'}x"
                    f"{row.get('max_tiles_v') or '?'})")
    elif v == "horizontal":
        bits.append("tiles horizontally only")
    elif v == "vertical":
        bits.append("tiles vertically only")
    elif v == "none":
        bits.append("never tiled")
    return "; ".join(bits)


# --------------------------------------------------------------------------
# vision
# --------------------------------------------------------------------------

CELL = 256
LABEL = 22


def make_sheet(rows, root: Path, out: Path, cols: int = 4):
    """Contact sheet, one numbered cell per texture, on a checkerboard so that
    transparency reads as transparency instead of as black."""
    n = len(rows)
    rowsn = (n + cols - 1) // cols
    sheet = Image.new("RGB", (cols * CELL, rowsn * (CELL + LABEL)), (32, 32, 36))
    d = ImageDraw.Draw(sheet)
    for i, r in enumerate(rows):
        cx, cy = (i % cols) * CELL, (i // cols) * (CELL + LABEL)
        check = Image.new("RGB", (CELL, CELL), (150, 150, 150))
        dc = ImageDraw.Draw(check)
        for y in range(0, CELL, 16):
            for x in range(0, CELL, 16):
                if (x // 16 + y // 16) % 2:
                    dc.rectangle([x, y, x + 15, y + 15], fill=(110, 110, 110))
        with Image.open(root / r["path"]) as im:
            im = im.convert("RGBA")
            # PS2 alpha is 0..128; stretch it so half-opaque does not read as opaque
            a = im.getchannel("A").point(lambda v: min(255, v * 2))
            im.putalpha(a)
            check.paste(im.resize((CELL, CELL), Image.NEAREST), (0, 0),
                        im.resize((CELL, CELL), Image.NEAREST))
        sheet.paste(check, (cx, cy))
        d.rectangle([cx, cy + CELL, cx + CELL - 1, cy + CELL + LABEL - 1], fill=(20, 20, 24))
        d.text((cx + 6, cy + CELL + 5), f"#{i + 1}  {r['name'][:34]}", fill=(235, 235, 235))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    return out


PROMPT = """Read the image at {sheet}. It is a contact sheet of {n} textures from the \
PlayStation 2 game Jak and Daxter, laid out left to right, top to bottom, each cell \
labelled with its number. They are shown on a grey checkerboard: checkerboard showing \
through means the texture is transparent there.

For each numbered cell, write one short sentence (max 20 words) saying what the texture \
depicts: the material or subject, its colours, and any motif or structure. Describe what \
you SEE. The notes below are what the game's own data says about each one -- use them to \
disambiguate, do not just repeat them, and if the image plainly contradicts a note, trust \
the image.

{context}

Reply with ONLY a JSON array, no prose and no code fence:
[{{"n": 1, "desc": "..."}}, ...] with exactly {n} entries."""


def run_vision(sheet: Path, rows, model: str, timeout: int):
    ctx = "\n".join(f"#{i + 1}: {r['_ctx']}" for i, r in enumerate(rows))
    prompt = PROMPT.format(sheet=sheet, n=len(rows), context=ctx)
    exe = subprocess.run(["bash", "-lc", "type -P claude"], capture_output=True, text=True)
    claude = exe.stdout.strip() or "claude"
    p = subprocess.run(
        [claude, "-p", prompt, "--model", model, "--allowed-tools", "Read"],
        capture_output=True, text=True, timeout=timeout,
    )
    txt = p.stdout.strip()
    m = re.search(r"\[.*\]", txt, re.S)
    if not m:
        return None, txt[:300]
    try:
        return json.loads(m.group(0)), None
    except json.JSONDecodeError as e:
        return None, f"{e}: {txt[:300]}"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root", type=Path)
    ap.add_argument("--tiling", type=Path, required=True, help="report from engine_truth.py")
    ap.add_argument("--draw-modes", type=Path, required=True)
    ap.add_argument("-o", "--out", type=Path, required=True)
    ap.add_argument("--vision", action="store_true")
    ap.add_argument("--batch", type=int, default=16)
    ap.add_argument("--jobs", type=int, default=6)
    ap.add_argument("--model", default="claude-haiku-4-5-20251001")
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--limit", type=int, default=0, help="only the first N textures (smoke test)")
    ap.add_argument("--refresh", action="store_true", help="ignore cached sheet answers")
    ap.add_argument("--sheet-dir", type=Path,
                    default=Path("/tmp/texture-sheets"), help="where contact sheets are written")
    args = ap.parse_args()

    with open(args.tiling) as fh:
        rows = list(csv.DictReader(fh))
    owners, alpha = load_owners(args.draw_modes)
    for r in rows:
        r["_ctx"] = code_context(r, owners, alpha)
        r["owners"] = "|".join(o for o, _ in owners.get((r["tpage"], r["name"]),
                                                        collections.Counter()).most_common(3))
        r["description"] = ""
    if args.limit:
        rows = rows[: args.limit]

    if args.vision:
        batches = [rows[i:i + args.batch] for i in range(0, len(rows), args.batch)]
        print(f"{len(rows)} textures -> {len(batches)} sheets of {args.batch}, "
              f"{args.jobs} at a time, model {args.model}")
        failures = []

        def work(idx_batch):
            idx, batch = idx_batch
            # 251 requests is long enough that losing them all to one failure
            # matters; a completed sheet is cached and skipped on a rerun.
            cache = args.sheet_dir / f"sheet-{idx:04d}.json"
            got, err = None, None
            if cache.exists() and not args.refresh:
                try:
                    got = json.loads(cache.read_text())
                except json.JSONDecodeError:
                    got = None
            if got is None:
                sheet = make_sheet(batch, args.root, args.sheet_dir / f"sheet-{idx:04d}.png")
                got, err = run_vision(sheet, batch, args.model, args.timeout)
                if got is not None:
                    cache.write_text(json.dumps(got))
            if got is None:
                return idx, batch, err
            by_n = {int(e["n"]): str(e.get("desc", "")) for e in got if "n" in e}
            for i, r in enumerate(batch):
                r["description"] = by_n.get(i + 1, "")
            return idx, batch, None

        done = 0
        with ThreadPoolExecutor(max_workers=args.jobs) as ex:
            for idx, batch, err in ex.map(work, list(enumerate(batches))):
                done += 1
                if err:
                    failures.append((idx, err))
                if done % 10 == 0 or done == len(batches):
                    filled = sum(1 for r in rows if r["description"])
                    print(f"  {done}/{len(batches)} sheets, {filled} descriptions, "
                          f"{len(failures)} failed sheets")
        if failures:
            print(f"\n{len(failures)} sheets produced no usable JSON:")
            for idx, err in failures[:5]:
                print(f"  sheet {idx}: {err[:160]}")

    cols = ["path", "tpage", "name", "width", "height", "verdict", "source",
            "max_tiles_h", "max_tiles_v", "draw_kinds", "owners", "levels",
            "description", "code_context"]
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with open(args.out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            r["code_context"] = r["_ctx"]
            w.writerow(r)
    print(f"\ncsv -> {args.out}")
    if args.vision:
        n = sum(1 for r in rows if r["description"])
        print(f"{n}/{len(rows)} textures carry a vision description")


if __name__ == "__main__":
    main()
