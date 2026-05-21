#!/usr/bin/env python3
"""Phase A1 — merge the arm64 classifier and the jak1 usage census into
the inventory JSON + Markdown summary.

Inputs:
  - ``goalc/compiler/IR.h``           (declared IR_* classes)
  - ``goalc/compiler/IR.cpp``         (do_codegen_arm64 bodies)
  - ``/tmp/A1-jak1-x86-stats.json``   (per-class emit counts from
                                       ``goalc --ir-emit-stats``)

Outputs:
  - ``.autoport/reports/A1-ir-inventory.json``
  - ``.autoport/reports/A1-ir-inventory.md``

Usage:
  python3 build_a1_inventory.py <IR.h> <IR.cpp> <stats.json> <out.json> <out.md>
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# Reuse the classifier in-process so the inventory is consistent with
# whatever the validator's deterministic-check sees.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from classify_ir_arm64 import classify  # noqa: E402


_CLASS_RE = re.compile(r"^class\s+(IR_[A-Za-z0-9_]+)\s", re.MULTILINE)


def declared_classes(ir_h: Path) -> list[str]:
    text = ir_h.read_text(encoding="utf-8", errors="replace")
    return _CLASS_RE.findall(text)


def main(argv: list[str]) -> int:
    if len(argv) != 6:
        print(
            "usage: build_a1_inventory.py <IR.h> <IR.cpp> <stats.json> <out.json> <out.md>",
            file=sys.stderr,
        )
        return 2

    ir_h = Path(argv[1])
    ir_cpp = Path(argv[2])
    stats_path = Path(argv[3])
    out_json = Path(argv[4])
    out_md = Path(argv[5])

    declared = declared_classes(ir_h)
    arm64_classified = classify(ir_cpp)
    stats = json.loads(stats_path.read_text(encoding="utf-8"))

    by_form: dict[str, dict] = {}
    real = stub = missing = 0
    uses_at_least_one = 0
    blockers: list[tuple[str, int]] = []

    for cls in declared:
        # Status: prefer the classifier's call. If the classifier has no
        # entry for the class (no do_codegen_arm64 body found in IR.cpp)
        # the IR has no arm64 dispatch at all.
        if cls in arm64_classified:
            status = arm64_classified[cls]
        else:
            status = "missing"

        if status == "real":
            real += 1
        elif status == "stub":
            stub += 1
        else:
            missing += 1

        rec = stats.get(cls)
        if isinstance(rec, dict):
            x86_count = int(rec.get("x86", 0))
        elif isinstance(rec, int):
            x86_count = rec
        else:
            x86_count = 0

        if x86_count > 0:
            uses_at_least_one += 1
        if x86_count > 0 and status != "real":
            blockers.append((cls, x86_count))

        by_form[cls] = {
            "arm64": status,
            "x86_emits_in_jak1": x86_count,
        }

    # Sort blockers descending by usage so A2 picks the highest-impact
    # forms first.
    blockers.sort(key=lambda kv: (-kv[1], kv[0]))

    summary = {
        "total_ir_classes_declared": len(declared),
        "arm64_real": real,
        "arm64_stub": stub,
        "arm64_missing": missing,
        "jak1_uses_at_least_one_emit": uses_at_least_one,
        "jak1_blockers": [name for name, _ in blockers],
    }

    inventory = {"summary": summary, "by_form": by_form}

    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(inventory, indent=2, sort_keys=True) + "\n")

    # --- Markdown ---
    rows = sorted(
        ((name, rec) for name, rec in by_form.items()),
        key=lambda kv: (-kv[1]["x86_emits_in_jak1"], kv[0]),
    )

    n = summary["total_ir_classes_declared"]
    n_used = summary["jak1_uses_at_least_one_emit"]
    n_real_in_use = sum(
        1
        for _, rec in by_form.items()
        if rec["arm64"] == "real" and rec["x86_emits_in_jak1"] > 0
    )
    n_blocked = len(summary["jak1_blockers"])

    lines: list[str] = []
    lines.append("# Phase A1 — AArch64 emitter IR inventory")
    lines.append("")
    lines.append(
        f"Of {n_used} IR forms used by jak1, {n_real_in_use} have real arm64 codegen; "
        f"{n_blocked} are stubs blocked for A2."
    )
    lines.append("")
    lines.append(
        f"Totals across all declared IR classes ({n}): "
        f"{summary['arm64_real']} real, {summary['arm64_stub']} stub, "
        f"{summary['arm64_missing']} missing."
    )
    lines.append("")
    lines.append("## Top blockers (A2 work list, descending by jak1 usage)")
    lines.append("")
    lines.append("| Rank | IR form | arm64 status | x86 emits in jak1 (`(mi)`) |")
    lines.append("|---:|---|---|---:|")
    rank = 0
    for name in summary["jak1_blockers"]:
        rank += 1
        rec = by_form[name]
        lines.append(
            f"| {rank} | `{name}` | {rec['arm64']} | {rec['x86_emits_in_jak1']:,} |"
        )
    lines.append("")
    lines.append("## Full inventory (descending by jak1 usage)")
    lines.append("")
    lines.append("| IR form | arm64 status | x86 emits in jak1 |")
    lines.append("|---|---|---:|")
    for name, rec in rows:
        lines.append(
            f"| `{name}` | {rec['arm64']} | {rec['x86_emits_in_jak1']:,} |"
        )
    lines.append("")
    lines.append("## How to regenerate")
    lines.append("")
    lines.append("```")
    lines.append(
        "build/goalc/goalc --user-auto --game jak1 --disable-ansi \\"
    )
    lines.append("    --ir-emit-stats /tmp/A1-jak1-x86-stats.json -c \"(mi)\"")
    lines.append(
        "python3 .autoport/lib/build_a1_inventory.py \\"
    )
    lines.append(
        "    goalc/compiler/IR.h goalc/compiler/IR.cpp \\"
    )
    lines.append(
        "    /tmp/A1-jak1-x86-stats.json \\"
    )
    lines.append(
        "    .autoport/reports/A1-ir-inventory.json \\"
    )
    lines.append(
        "    .autoport/reports/A1-ir-inventory.md"
    )
    lines.append("```")
    lines.append("")

    out_md.parent.mkdir(parents=True, exist_ok=True)
    out_md.write_text("\n".join(lines))

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
