#!/usr/bin/env python3
"""Directive transmission — one version stamp shared by the orchestrator, the
worker prompt, the subagents and the validator.

The owner, 2026-08-11: "t'arrives pas a faire descendre a tes agents les
changements et ca gaspille des heures a ne pas le faire". Measured on
Grecharged-secondary-motion attempt 2: 6 subagents spawned, 0 carried the
contract, and the phase prompt still pointed at a scope the supervisor had
narrowed hours earlier. The channel did not exist; this file is the channel.

  version  -> a short hash over DIRECTIVES.md + the SPEC it designates + the
              phase prompt. Any edit to any of the three changes it.
  block    -> the text INLINED into the worker prompt (no path to maybe-open:
              the contract travels with the instructions), plus the line the
              report must echo back.

The validator recomputes `version` and rejects a report carrying a stale one,
so a mid-attempt directive change costs one failed validation instead of hours.
"""
import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DIRECTIVES = ROOT / ".autoport" / "DIRECTIVES.md"


def _spec_path(directives_text):
    """The SPEC is named INSIDE DIRECTIVES.md, so retargeting the contract is a
    one-line edit there rather than a code change here."""
    m = re.search(r"`(\.autoport/prompts/SPEC-[^`]+\.md)`", directives_text)
    return ROOT / m.group(1) if m else None


def parts(phase_id=None):
    txt = DIRECTIVES.read_text() if DIRECTIVES.exists() else ""
    spec = _spec_path(txt)
    spec_txt = spec.read_text() if spec and spec.exists() else ""
    prompt_txt = ""
    if phase_id:
        p = ROOT / ".autoport" / "prompts" / f"phase-{phase_id}.md"
        prompt_txt = p.read_text() if p.exists() else ""
    return txt, spec, spec_txt, prompt_txt


def version(phase_id=None):
    txt, _spec, spec_txt, prompt_txt = parts(phase_id)
    h = hashlib.sha256()
    for chunk in (txt, spec_txt, prompt_txt):
        h.update(chunk.encode())
        h.update(b"\0")
    return "v" + h.hexdigest()[:10]


def block(phase_id=None):
    """The contract, inlined, with the echo instruction and the subagent rule."""
    txt, spec, spec_txt, _prompt = parts(phase_id)
    ver = version(phase_id)
    out = [
        "## DIRECTIVES — AUTORITÉ SUPÉRIEURE À TOUT CE QUI SUIT",
        "",
        f"Version courante : **DIRECTIVES {ver}**. Écris cette ligne, littéralement,",
        "dans ton rapport (`DIRECTIVES " + ver + "`). Le validateur recalcule la version et",
        "refuse un rapport qui en porte une périmée — c'est ce qui empêche de travailler des",
        "heures sur un périmètre abandonné.",
        "",
        "**Transmission aux sous-agents (obligatoire).** Chaque prompt de sous-agent doit",
        "commencer par le périmètre actif et la ligne `DIRECTIVES " + ver + "`. Les définitions",
        "d'agents leur imposent de relire `.autoport/DIRECTIVES.md` avant d'agir : si tu changes",
        "de périmètre, relance-les, ne les laisse pas finir sur l'ancien.",
        "",
        txt.strip(),
    ]
    if spec_txt:
        out += [
            "",
            "---",
            f"## CONTRAT DE PÉRIMÈTRE — {spec.name} (inliné : rien à aller chercher)",
            "",
            spec_txt.strip(),
        ]
    out += ["", "---", ""]
    return "\n".join(out)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "version"
    pid = sys.argv[2] if len(sys.argv) > 2 else None
    print(version(pid) if cmd == "version" else block(pid))
