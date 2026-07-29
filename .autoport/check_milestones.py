#!/usr/bin/env python3
"""Pre-flight for milestones.yaml — refuse a malformed phase entry BEFORE the orchestrator dies on it.

Written 2026-07-29 after making the SAME mistake twice in one day: hand-writing a phase entry with
four keys instead of the eight the orchestrator requires, and using repo-root-relative paths where
it expects paths relative to .autoport/. Each mistake cost a crash + a relaunch, and the owner saw
the framework "down" both times. Run this before every relaunch; it exits non-zero on any problem.
"""
import os, sys, yaml

# Only the keys the orchestrator actually dereferences. 158 legacy phases omit device/owner_verify
# and run fine, so demanding them would make this check useless noise instead of a guard.
REQUIRED = {"id", "name", "prompt", "validator"}
HERE = os.path.dirname(os.path.abspath(__file__))

def main():
    doc = yaml.safe_load(open(os.path.join(HERE, "milestones.yaml")))
    phases = doc if isinstance(doc, list) else doc.get("phases", doc)
    bad = 0
    for i, ph in enumerate(phases):
        pid = ph.get("id", f"<entry {i}>")
        missing = REQUIRED - set(ph)
        if missing:
            print(f"FAIL {pid}: missing keys {sorted(missing)}")
            bad += 1
            continue
        for key in ("prompt", "validator"):
            val = str(ph[key])
            if val.startswith(".autoport/") or val.startswith("/"):
                print(f"FAIL {pid}: {key} must be relative to .autoport/, got '{val}'")
                bad += 1
                continue
            path = os.path.join(HERE, val)
            if not os.path.isfile(path):
                print(f"FAIL {pid}: {key} '{val}' does not resolve to a file ({path})")
                bad += 1
    if bad:
        print(f"\n{bad} problem(s) — the orchestrator would crash or block on these.")
        return 1
    print(f"milestones OK: {len(phases)} phases, all keys present, all prompt/validator paths resolve")
    return 0

if __name__ == "__main__":
    sys.exit(main())
