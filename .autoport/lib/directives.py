#!/usr/bin/env python3
"""Directive transmission — the contract inlined into a worker's prompt.

What travels: the standing orders (`.autoport/DIRECTIVES.md`, ~3 KB) and, when it
exists, the scope of THIS item (`.autoport/prompts/SCOPE-<item_id>.md`). Nothing
else. Until 2026-09-03 this module inlined the whole of DIRECTIVES.md plus the
first `SPEC-*.md` it named, which shipped 167 285 characters of Keira breast
physics into every phase, cutscenes and fonts included, for ~1 % of on-topic text.

  version(item_id) -> short hash over the serial, the item id and the text that is
                      ACTUALLY inlined for that item. One version per item, so a
                      scope change kills only the attempts it concerns.
  block(item_id)   -> that text, plus the line the report must echo back.

Hard cap: MAX_BLOCK_BYTES. Over it, block() raises instead of truncating — a
launch must fail loudly, because a silently trimmed contract is how the worker
ends up obeying a rule it never received.
"""
import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AUTOPORT = ROOT / ".autoport"
DIRECTIVES = AUTOPORT / "DIRECTIVES.md"
SERIAL_FILE = AUTOPORT / "SCOPE-SERIAL"
ISSUED = AUTOPORT / ".directives_issued"

MAX_BLOCK_BYTES = 12288


class DirectivesTooLarge(RuntimeError):
    """The assembled contract busted the cap. Raised, never swallowed."""


def _dtext():
    return DIRECTIVES.read_text(encoding="utf-8") if DIRECTIVES.exists() else ""


def scope_path(item_id):
    """The per-item scope. Absent is normal: standing orders alone are a contract."""
    if not item_id:
        return None
    return AUTOPORT / "prompts" / f"SCOPE-{item_id}.md"


def _scope_text(item_id):
    p = scope_path(item_id)
    return p.read_text(encoding="utf-8") if p and p.exists() else ""


def serial():
    """The scope serial, bumped BY HAND when the scope genuinely changes.

    Hashing the whole prompt made a typo fix kill a healthy attempt -- a brake,
    not a circle. A deliberate serial means an attempt dies exactly when we mean
    it to, and prose edits cost nothing."""
    if SERIAL_FILE.exists():
        m = re.search(r"\d+", SERIAL_FILE.read_text(encoding="utf-8"))
        if m:
            return int(m.group(0))
    m = re.search(r"^SCOPE-SERIAL:\s*(\d+)", _dtext(), re.M)
    return int(m.group(1)) if m else 0


def parts(item_id=None):
    """(standing orders, scope path or None, scope text)."""
    return _dtext(), scope_path(item_id), _scope_text(item_id)


def _body(item_id=None):
    """Exactly the contract text inlined for this item — what version() hashes."""
    txt, spath, stext = parts(item_id)
    out = [txt.strip()]
    if stext:
        out += ["", "---", "",
                f"## PÉRIMÈTRE DE CETTE TÂCHE — {spath.name}", "", stext.strip()]
    return "\n".join(out)


def version(item_id=None):
    h = hashlib.sha256()
    for chunk in (str(serial()), item_id or "", _body(item_id)):
        h.update(chunk.encode("utf-8"))
        h.update(b"\0")
    return "v" + h.hexdigest()[:10]


def issued_for_current_serial():
    """Versions already handed to a worker under the CURRENT serial. They stay
    acceptable: the scope did not change, so the attempt is not stale."""
    cur, out = serial(), set()
    if ISSUED.exists():
        for ln in ISSUED.read_text(encoding="utf-8").splitlines():
            f = ln.split()
            if len(f) == 2 and f[0].isdigit() and int(f[0]) == cur:
                out.add(f[1])
    out.add(version())
    return out


def _record(ver):
    try:
        line = "%d %s\n" % (serial(), ver)
        if line not in (ISSUED.read_text(encoding="utf-8") if ISSUED.exists() else ""):
            with ISSUED.open("a", encoding="utf-8") as fh:
                fh.write(line)
    except Exception:
        pass


def block(item_id=None, record=True):
    """The contract, inlined. Raises DirectivesTooLarge past MAX_BLOCK_BYTES."""
    ver = version(item_id)
    if record:
        _record(ver)
    out = [
        "## DIRECTIVES — autorité supérieure à tout ce qui suit",
        "",
        f"Version courante : **DIRECTIVES {ver}**. Écris cette ligne, littéralement,",
        f"dans ton rapport (`DIRECTIVES {ver}`). Le validateur recalcule la version et refuse",
        "un rapport qui en porte une périmée : c'est ce qui empêche de travailler des heures",
        "sur un périmètre abandonné.",
        "",
        "Chaque prompt de sous-agent commence par le périmètre de sa tâche et cette ligne.",
        "",
        _body(item_id),
        "",
        "---",
        "",
    ]
    text = "\n".join(out)
    size = len(text.encode("utf-8"))
    if size > MAX_BLOCK_BYTES:
        spath = scope_path(item_id)
        detail = f"{spath} ({len(_scope_text(item_id).encode('utf-8'))} o)" \
            if spath and spath.exists() else "aucun SCOPE"
        raise DirectivesTooLarge(
            f"contrat inliné pour '{item_id or '(aucun item)'}' : {size} octets pour un "
            f"plafond de {MAX_BLOCK_BYTES}. DIRECTIVES.md = "
            f"{len(_dtext().encode('utf-8'))} o, périmètre = {detail}. "
            "Raccourcis l'un des deux ; le lancement ne doit pas partir tronqué."
        )
    return text


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "version"
    item = sys.argv[2] if len(sys.argv) > 2 else None
    if cmd == "accepted":
        print(" ".join(sorted(issued_for_current_serial())))
    elif cmd == "size":
        print(len(block(item, record=False).encode("utf-8")))
    elif cmd == "block":
        print(block(item))
    else:
        print(version(item))
