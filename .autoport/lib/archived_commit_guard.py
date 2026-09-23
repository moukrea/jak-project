#!/usr/bin/env python3
"""lib/archived_commit_guard.py — hook git `commit-msg` (ARCHIVE-OWNER/, harness-owner-archive-of-running-item-is-safe).

Un ESSAI (`AUTOPORT_PHASE_ID` pose par l'orchestrateur dans l'environnement du worker) ne commite rien sous
`[autoport/<id>]` quand l'owner a archive <id> : l'orchestrateur coupe l'essai au tick suivant, ce hook ferme
la fenetre entre l'archivage et la coupure. Hors essai (superviseur, owner, orchestrateur), il laisse passer.
Le backlog lu est celui de l'arbre qui commite (`AUTOPORT_BACKLOG` pour un banc).
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

LABEL = re.compile(r"^\[autoport/([^\]\s]+)\]")


def refused(message: str, backlog_path, env=None) -> str:
    """-> motif du refus, ou "" si le commit peut passer."""
    env = os.environ if env is None else env
    if not env.get("AUTOPORT_PHASE_ID"):
        return ""
    m = LABEL.match((message or "").lstrip())
    if not m:
        return ""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import backlog as B
    try:
        st = (B.load(str(backlog_path)).get(m.group(1)) or {}).get("status")
    except Exception:  # noqa: BLE001 — un backlog illisible ne bloque pas un commit
        return ""
    if st != "archived":
        return ""
    return ("[autoport archive-guard] REFUS : %s est ARCHIVE par l'owner ; un essai ne commite rien "
            "en son nom" % m.group(1))


def main(argv) -> int:
    if len(argv) < 2:
        return 0
    try:
        msg = Path(argv[1]).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return 0
    bp = os.environ.get("AUTOPORT_BACKLOG")
    if not bp:
        top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip()
        bp = str(Path(top or ".") / ".autoport" / "backlog.yaml")
    why = refused(msg, bp)
    if why:
        sys.stderr.write(why + "\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
