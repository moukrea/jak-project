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
  dir_verdict(item_id)  -> (ok, why, cause) : cherche la ligne dans report.txt, report.md,
                      handoff.md puis tout .md/.txt du dossier ; cause FORM (aucune ligne,
                      non compte) ou STALE (version perimee, refus de fond).
  report_verdict(item_id, path) -> (ok, why) : la porte de fermeture refuse un rapport
                      sans ligne `DIRECTIVES v...` ou qui en porte une perimee (hors
                      `accepted_for`). `.directives_issued` nomme l'item depuis le 25/09.

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


# INVISIBLE-CAPTURE/ (harness-invisible-item-comment-has-no-capture-boilerplate, 23/09) : le
# paragraphe capture de DIRECTIVES ne vaut que pour un chantier que l'owner va regarder. Rendu a
# tous, il a fait ecrire « Capture impossible ... Build a tester » sur un chantier de harnais
# (JAK-240) — owner : « gaspillage d'énergie ». Il est borne par ces deux lignes dans DIRECTIVES.md.
VISIBLE_ONLY_RX = re.compile(r"^<!-- chantier-visible -->\n(.*?)^<!-- /chantier-visible -->\n", re.M | re.S)


def _item(item_id):
    """L'item du backlog, ou None (backlog illisible : le paragraphe est rendu, comme avant)."""
    if not item_id:
        return None
    try:
        if str(AUTOPORT / "lib") not in sys.path:
            sys.path.insert(0, str(AUTOPORT / "lib"))
        import backlog as _bl   # noqa: PLC0415
        return _bl.load().get(item_id)
    except Exception:  # noqa: BLE001
        return None


def is_visible(item):
    """Meme juge que la porte CLOSE-GATE/capture (`owner_capture.is_visible`). Inconnu : visible."""
    if not item:
        return True
    try:
        import owner_capture as _oc   # noqa: PLC0415
        return _oc.is_visible(item)[0]
    except Exception:  # noqa: BLE001
        return True


def standing_orders(txt, visible):
    """DIRECTIVES.md tel qu'il est rendu : le bloc « chantier-visible » garde son texte (sans ses
    bornes) pour un chantier visible, disparait pour un chantier hors champ."""
    return VISIBLE_ONLY_RX.sub((lambda m: m.group(1)) if visible else "", txt)


def _body(item_id=None, item=None):
    """Exactly the contract text inlined for this item — what version() hashes.
    `item` : le dict du backlog (sinon relu par son id)."""
    txt, spath, stext = parts(item_id)
    txt = standing_orders(txt, is_visible(item if item is not None else _item(item_id)))
    out = [txt.strip()]
    if stext:
        out += ["", "---", "",
                f"## PÉRIMÈTRE DE CETTE TÂCHE — {spath.name}", "", stext.strip()]
    return "\n".join(out)


def version(item_id=None, item=None):
    h = hashlib.sha256()
    for chunk in (str(serial()), item_id or "", _body(item_id, item)):
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
            if len(f) in (2, 3) and f[0].isdigit() and int(f[0]) == cur:
                out.add(f[1])
    out.add(version())
    return out


def accepted_for(item_id, item=None):
    """Versions acceptables dans le rapport de CET item : celles emises sous la serie
    COURANTE pour lui (lignes `<serie> <ver> <item>`), plus sa version courante.

    Les lignes heritees a 2 champs (`<serie> <ver>`, ecrites avant le 25/09) ne nomment pas
    d'item : elles restent acceptees sous la serie courante, pour ne pas refuser un essai
    emis avant ce changement. Elles disparaissent d'elles-memes au prochain changement de serie."""
    cur, out = serial(), set()
    if ISSUED.exists():
        for ln in ISSUED.read_text(encoding="utf-8").splitlines():
            f = ln.split()
            if not f or not f[0].isdigit() or int(f[0]) != cur:
                continue
            if len(f) == 2 or (len(f) == 3 and f[2] == item_id):
                out.add(f[1])
    out.add(version(item_id, item))
    return out


REPORT_VERSION_RX = re.compile(r"DIRECTIVES (v[0-9a-f]{10})\b")


def _attendu(item_id, item=None):
    """Ce que la porte attend, SANS la forme `DIRECTIVES v…` : ce texte part dans le handoff,
    que la porte relit — il ne doit jamais s'y faire passer pour la ligne du worker."""
    return f"attendu la ligne `DIRECTIVES <version>` avec <version> = {version(item_id, item)}"


def report_verdict(item_id, report_path, item=None):
    """(ok, raison). Stricte : UNE version perimee dans le texte suffit a refuser."""
    p = Path(report_path)
    txt = p.read_text(encoding="utf-8", errors="replace") if p.is_file() else ""
    if not txt.strip():
        return False, f"rapport absent : {p} (la ligne `DIRECTIVES v...` ne peut pas etre lue)"
    found = sorted(set(REPORT_VERSION_RX.findall(txt)))
    if not found:
        return False, (f"le rapport ne porte aucune ligne `DIRECTIVES v...` ({p}) ; "
                       f"{_attendu(item_id, item)}")
    ok = accepted_for(item_id, item)
    stale = [v for v in found if v not in ok]
    if stale:
        return False, (f"version(s) perimee(s) dans le rapport : {', '.join(stale)} ; "
                       f"serie courante {serial()}, version courante de {item_id} : "
                       f"{version(item_id, item)}")
    return True, f"DIRECTIVES {', '.join(found)} acceptée (série {serial()})"


# harness-directives-gate-reads-any-report-name (25/09). La porte ne lisait que `report.txt` ;
# aucun prompt ne nommait ce fichier, et l'essai 8 de lighting-shadows, porte VERTE, a ete
# refuse et COMPTE parce que son rapport s'appelait `report.md`. La ligne est maintenant
# cherchee dans le dossier du rapport, sous ces noms d'abord, puis dans tout autre .md/.txt
# de premier niveau qui n'est ni une preuve ni les signalements.
REPORT_NAMES = ("report.txt", "report.md", "handoff.md")
_NOT_A_REPORT = re.compile(r"^(proof.*\.txt|FINDINGS\.txt)$", re.I)
# Cause d'un refus : FORM = aucune ligne lisible (rien n'est dit du perimetre) ; STALE = une
# version perimee est ecrite (l'essai a travaille sur un perimetre abandonne). Seul STALE est
# un refus de fond ; l'orchestrateur ne compte pas un refus FORM (voir `form_refusal_uncounted`).
FORM, STALE = "form", "stale"


def report_candidates(report_dir):
    d = Path(report_dir)
    others = sorted(x for x in (d.glob("*") if d.is_dir() else [])
                    if x.is_file() and x.suffix.lower() in (".txt", ".md")
                    and x.name not in REPORT_NAMES and not _NOT_A_REPORT.match(x.name))
    return [d / n for n in REPORT_NAMES] + others


def expected_report(item_id):
    """Le fichier que le prompt nomme au lancement, et que la porte lit en premier."""
    return AUTOPORT / "reports" / item_id / REPORT_NAMES[0]


def find_report(item_id, report_dir=None, since=None):
    """(chemin du premier rapport portant `DIRECTIVES v...` ou None, noms lus, vieux ?).

    `since` (epoch, debut de l'essai) : les fichiers ecrits PENDANT l'essai sont lus d'abord,
    les restes d'un essai anterieur ensuite — un vieux rapport ne masque jamais le neuf."""
    d = Path(report_dir) if report_dir else AUTOPORT / "reports" / item_id
    fresh, old = [], []
    for c in report_candidates(d):
        if c.is_file():
            (old if since is not None and c.stat().st_mtime < float(since) else fresh).append(c)
    read = []
    for c in fresh + old:
        read.append(c.name + (" (anterieur a l'essai)" if c in old else ""))
        if REPORT_VERSION_RX.search(c.read_text(encoding="utf-8", errors="replace")):
            return c, read, c in old
    return None, read, False


def dir_verdict(item_id, report_dir=None, item=None, since=None):
    """(ok, raison, cause) sur le dossier du rapport. cause : "" si ok, sinon FORM ou STALE.

    STALE n'est rendu que pour un fichier ecrit PENDANT l'essai : une version perimee laissee
    par un essai anterieur ne dit rien de celui-ci, qui n'a rien ecrit — c'est FORM."""
    d = Path(report_dir) if report_dir else AUTOPORT / "reports" / item_id
    p, read, is_old = find_report(item_id, d, since)
    attendu = f"{_attendu(item_id, item)} dans {d / REPORT_NAMES[0]}"
    if p is None:
        return False, (f"aucun rapport ne porte `DIRECTIVES v...` dans {d} "
                       f"(lus : {', '.join(read) or 'aucun'}) ; {attendu}"), FORM
    ok, why = report_verdict(item_id, p, item=item)
    if ok:
        return True, f"{p.name} : {why}", ""
    if is_old:
        return False, (f"{p.name} est anterieur a l'essai et porte une version perimee "
                       f"({why}) ; cet essai n'a ecrit aucune ligne ; {attendu}"), FORM
    return False, f"{p.name} : {why}", STALE


def _record(ver, item_id=None):
    try:
        line = ("%d %s %s\n" % (serial(), ver, item_id)) if item_id else ("%d %s\n" % (serial(), ver))
        if line not in (ISSUED.read_text(encoding="utf-8") if ISSUED.exists() else ""):
            with ISSUED.open("a", encoding="utf-8") as fh:
                fh.write(line)
    except Exception:
        pass


def block(item_id=None, record=True, item=None):
    """The contract, inlined. Raises DirectivesTooLarge past MAX_BLOCK_BYTES."""
    if item is None:
        item = _item(item_id)
    ver = version(item_id, item)
    if record:
        _record(ver, item_id)
    out = [
        "## DIRECTIVES — autorité supérieure à tout ce qui suit",
        "",
        f"Version courante : **DIRECTIVES {ver}**. Écris cette ligne, littéralement,",
        f"dans ton rapport (`DIRECTIVES {ver}`)"
        + (f", le fichier `.autoport/reports/{item_id}/{REPORT_NAMES[0]}`" if item_id else "")
        + ". La porte de fermeture recalcule la version",
        "et refuse un rapport qui n'en porte aucune ou en porte une périmée : c'est ce qui",
        "empêche de travailler des heures sur un périmètre abandonné.",
        "",
        "Chaque prompt de sous-agent commence par le périmètre de sa tâche et cette ligne.",
        "",
        _body(item_id, item),
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
    elif cmd == "report":
        if len(sys.argv) > 3 and Path(sys.argv[3]).is_file():
            _ok, _why = report_verdict(item, sys.argv[3], item=_item(item))
        else:
            _ok, _why, _ = dir_verdict(item, sys.argv[3] if len(sys.argv) > 3 else None,
                                       item=_item(item))
        print(_why)
        sys.exit(0 if _ok else 1)
    elif cmd == "size":
        print(len(block(item, record=False).encode("utf-8")))
    elif cmd == "block":
        print(block(item))
    else:
        print(version(item))
