"""Read-only inventories for the current shader artifact conservation check.

Expected outputs come from source filenames, independently of producer discovery.
The returned manifests describe measured bytes; this module writes no proof files.
"""

import hashlib
import json
from pathlib import Path


STAGES = {".vert", ".frag", ".tesc", ".tese"}
BLOB = "shaders_android_blob.h"


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _manifest(rows: list[dict]) -> str:
    return "".join(json.dumps(row, sort_keys=True, ensure_ascii=True) + "\n" for row in rows)


def source_inventory(src_dir: Path) -> dict:
    """Inventory all top-level shader/chunk sources or raise on unusable inputs."""
    rows = []
    expected = [BLOB]
    chunks = stages = total_bytes = 0
    for path in sorted(src_dir.iterdir(), key=lambda path: path.name):
        if path.suffix not in STAGES | {".glsl"}:
            continue
        if not path.is_file():
            raise ValueError(f"source is not a file: {path}")
        data = path.read_bytes()
        if not data:
            raise ValueError(f"empty source: {path}")
        rows.append({"name": path.name, "bytes": len(data), "sha256": _sha(data)})
        total_bytes += len(data)
        if path.suffix == ".glsl":
            chunks += 1
            expected.append(path.name)
        else:
            stages += 1
            expected.append(f"{path.stem}.android{path.suffix}")
    if not chunks or not stages:
        raise ValueError(f"incomplete source population: stages={stages}, chunks={chunks}")
    manifest = _manifest(rows)
    return {"expected": sorted(expected), "manifest": manifest,
            "sha256": _sha(manifest.encode()), "files": len(rows), "bytes": total_bytes}


def compare_outputs(before: Path, after: Path, expected: list[str]) -> dict:
    """Compare actual bytes for every expected output, continuing after read errors.

    Each bad arm/file and each byte divergence contributes one defect. Population
    guards are additional defects. Unlisted files (including dead residue) are ignored.
    """
    rows = []
    issues = []
    files = total_bytes = divergences = 0
    names = sorted(set(expected))
    if not names:
        issues.append("empty expected population")
    if BLOB not in names:
        issues.append("missing expected blob category")
    if not any(Path(name).suffix == ".glsl" for name in names):
        issues.append("missing expected chunk category")
    if not any(name.endswith(tuple(f".android{suffix}" for suffix in STAGES)) for name in names):
        issues.append("missing expected stage category")
    for name in names:
        row = {"name": name}
        contents = []
        if Path(name).name != name or name in {"", ".", ".."}:
            issues.append(f"invalid expected filename: {name}")
            rows.append({"name": name, "error": "invalid filename"})
            continue
        for arm, directory in (("before", before), ("after", after)):
            try:
                path = directory / name
                if not path.is_file():
                    raise OSError("missing or non-file output")
                data = path.read_bytes()
            except OSError as exc:
                row[arm] = {"error": type(exc).__name__, "detail": str(exc)}
                issues.append(f"{arm} {name}: {type(exc).__name__}: {exc}")
                contents.append(None)
                continue
            row[arm] = {"bytes": len(data), "sha256": _sha(data)}
            contents.append(data)
            if not data:
                row[arm]["error"] = "empty output"
                issues.append(f"{arm} {name}: empty output")
        if all(data is not None for data in contents):
            files += 1
            total_bytes += len(contents[0])
            if contents[0] != contents[1]:
                divergences += 1
                issues.append(f"different bytes: {name}")
        rows.append(row)
    if not total_bytes:
        issues.append("no bytes compared")
    manifest = _manifest(rows)
    return {"files": files, "bytes": total_bytes, "divergences": divergences,
            "defects": len(issues), "issues": issues, "manifest": manifest,
            "sha256": _sha(manifest.encode())}
