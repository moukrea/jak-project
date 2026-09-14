#!/usr/bin/env python3
"""Inventory runtime objects against Ninja's graph; quarantine only proven orphans."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def inventory(directory):
    directory = Path(directory).resolve()
    runtime = directory / "game/CMakeFiles/runtime.dir"
    if runtime.is_symlink():
        raise ValueError("runtime.dir must not be a symlink")
    result = subprocess.run(["ninja", "-C", str(directory), "-t", "targets", "all"],
                            text=True, capture_output=True, check=True)
    graph = sorted({line.rsplit(": ", 1)[0] for line in result.stdout.splitlines()
                    if line.startswith("game/CMakeFiles/runtime.dir/")
                    and line.rsplit(": ", 1)[0].endswith(".o")})
    disk = sorted(str(p.relative_to(directory)) for p in runtime.rglob("*.o")
                  if p.is_file())
    # A real runtime directory with no parsed object edges is an unknown graph,
    # never permission to move every object.
    if disk and not graph:
        raise ValueError("runtime objects exist but Ninja returned no runtime object edges")
    orphans = sorted(set(disk) - set(graph))
    return {"directory": str(directory), "disk": disk, "graph": graph,
            "orphans": orphans, "disk_count": len(disk), "graph_count": len(graph),
            "orphan_count": len(orphans),
            "manifest_sha256": hashlib.sha256((directory / "build.ninja").read_bytes()).hexdigest()}


def quarantine(directory):
    before = inventory(directory)
    directory = Path(before["directory"])
    destination = directory / ".orphan-objects" / f"{time.time_ns()}-{os.getpid()}"
    if destination.parent.is_symlink() or not destination.resolve().is_relative_to(directory):
        raise ValueError("quarantine escapes build directory")
    if hashlib.sha256((directory / "build.ninja").read_bytes()).hexdigest() != before["manifest_sha256"]:
        raise ValueError("Ninja manifest changed during inventory")
    moved = []
    for name in before["orphans"]:
        source = directory / name
        if source.is_symlink() or not source.resolve().is_relative_to(directory):
            raise ValueError(f"object escapes build directory: {name}")
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        source.rename(target)
        moved.append(name)
    after = inventory(directory)
    if after["orphan_count"] or after["manifest_sha256"] != before["manifest_sha256"]:
        raise ValueError("runtime cleanup incomplete or Ninja manifest changed")
    return {"before": before, "after": after, "moved": moved,
            "quarantine": str(destination) if moved else "-"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", default="build")
    parser.add_argument("--quarantine", action="store_true")
    parser.add_argument("--kv", action="store_true")
    args = parser.parse_args()
    result = quarantine(args.dir) if args.quarantine else inventory(args.dir)
    if args.kv:
        before = result["before"] if args.quarantine else result
        after = result["after"] if args.quarantine else result
        print(f"bx_orphans_before={before['orphan_count']}")
        print(f"bx_orphans_after={after['orphan_count']}")
        print(f"bx_orphans_moved={len(result.get('moved', []))}")
        print(f"bx_orphans_quarantine={result.get('quarantine', '-')}")
    else:
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
