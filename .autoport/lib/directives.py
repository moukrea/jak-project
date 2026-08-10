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


def serial():
    """The scope serial, bumped BY HAND when the scope genuinely changes.

    First cut hashed the whole prompt, which made a typo fix kill a healthy
    attempt -- a brake, not a circle. Keying on a deliberate serial means an
    attempt dies exactly when I mean it to, and prose edits cost nothing."""
    m = re.search(r"^SCOPE-SERIAL:\s*(\d+)", _dtext(), re.M)
    return int(m.group(1)) if m else 0


def _dtext():
    return DIRECTIVES.read_text() if DIRECTIVES.exists() else ""


def _scope_section():
    """Only the ACTIVE SCOPE block feeds the version, not the whole document."""
    t = _dtext()
    m = re.search(r"## PÉRIMÈTRE ACTIF.*?(?=\n## )", t, re.S)
    return m.group(0) if m else t


def version(phase_id=None):
    _txt, _spec, spec_txt, _prompt = parts(phase_id)
    h = hashlib.sha256()
    for chunk in (str(serial()), _scope_section(), spec_txt):
        h.update(chunk.encode())
        h.update(b"\0")
    return "v" + h.hexdigest()[:10]


ISSUED = ROOT / ".autoport" / ".directives_issued"


def issued_for_current_serial():
    """Versions already handed to a worker under the CURRENT serial. They stay
    acceptable: the scope did not change, so the attempt is not stale."""
    cur, out = serial(), set()
    if ISSUED.exists():
        for ln in ISSUED.read_text().splitlines():
            parts_ = ln.split()
            if len(parts_) == 2 and parts_[0].isdigit() and int(parts_[0]) == cur:
                out.add(parts_[1])
    out.add(version())
    return out


def block(phase_id=None):
    """The contract, inlined, with the echo instruction and the subagent rule."""
    txt, spec, spec_txt, _prompt = parts(phase_id)
    ver = version(phase_id)
    try:
        line = "%d %s\n" % (serial(), ver)
        if line not in (ISSUED.read_text() if ISSUED.exists() else ""):
            with ISSUED.open("a") as fh:
                fh.write(line)
    except Exception:
        pass
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
    if cmd == "accepted":
        print(" ".join(sorted(issued_for_current_serial())))
    else:
        print(version(pid) if cmd == "version" else block(pid))
