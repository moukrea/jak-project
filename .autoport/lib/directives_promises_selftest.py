#!/usr/bin/env python3
"""Recensement des PROMESSES MACHINE du contrat (harness-directives-promises-are-implemented).

Le contrat rendu au worker (DIRECTIVES.md + l'en-tete de `directives.block()`) affirme que tel
juge « recalcule », « refuse », « lit ». Jusqu'au 25/09, « le validateur recalcule la version et
refuse un rapport qui en porte une perimee » n'etait tenu par AUCUN code. Ce banc extrait chaque
phrase de cette forme, exige qu'elle soit inscrite au REGISTRE avec une SONDE fonctionnelle, et
publie `directives_unkept_promises` (attendu : 0).

N'ECRIT JAMAIS dans les vrais fichiers du harnais : `directives.ISSUED`, `SERIAL_FILE`,
`DIRECTIVES`, `AUTOPORT` sont re-pointes dans un TemporaryDirectory et restaures en `finally`.
Sortie : une ligne `cle=valeur` par grandeur, valeurs sans espace.
"""
import ast
import re
import sys
import tempfile
from pathlib import Path

AUTOPORT = Path(__file__).resolve().parents[1]
LIB = AUTOPORT / "lib"
for _p in (str(AUTOPORT), str(LIB)):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import directives  # noqa: E402

ITEM_ID = "harness-directives-promises-are-implemented"
ORCH_PY = AUTOPORT / "orchestrator.py"

PROMISE_RX = re.compile(
    r"(?i)\b(le validateur|la porte(?: de fermeture)?|le juge|l'orchestrateur)\b"
    r"([^.]{0,120}?)\b(recalcule|refuse|rejette|lit)\b")
NEG_RX = re.compile(r"(?i)\bne\b")


def _clean(v):
    return re.sub(r"\s+", "_", str(v).strip())


# ------------------------------------------------------------------ extraction
def sentences(text):
    """Paragraphes joints (lignes d'un meme bloc), puis coupe sur `.` `;` `:` suivis d'un blanc."""
    out = []
    for para in re.split(r"\n\s*\n", text):
        joined = " ".join(ln.strip() for ln in para.splitlines())
        for s in re.split(r"[.;:](?=\s|$)", joined):
            s = " ".join(s.split())
            if s:
                out.append(s)
    return out


def extract(text):
    seen, out = set(), []
    for s in sentences(text):
        m = PROMISE_RX.search(s)
        if not m or NEG_RX.search(m.group(2)):
            continue
        if s not in seen:
            seen.add(s)
            out.append(s)
    return out


# ------------------------------------------------------------------ sondes
def _orch():
    import orchestrator  # noqa: PLC0415  (meme import que tests/harness/conftest.py)
    return orchestrator


def _func(tree, name):
    for n in ast.walk(tree):
        if isinstance(n, ast.FunctionDef) and n.name == name:
            return n
    return None


def _calls_attr(node, attr):
    return sum(1 for n in ast.walk(node) if isinstance(n, ast.Call)
               and isinstance(n.func, ast.Attribute) and n.func.attr == attr)


class _Sandbox:
    """Re-pointe le module `directives` sur un arbre jetable ; restaure en sortie."""
    KEYS = ("AUTOPORT", "DIRECTIVES", "SERIAL_FILE", "ISSUED")

    def __enter__(self):
        self.saved = {k: getattr(directives, k) for k in self.KEYS}
        self.td = tempfile.TemporaryDirectory()
        ap = Path(self.td.name) / ".autoport"
        (ap / "prompts").mkdir(parents=True)
        (ap / "DIRECTIVES.md").write_text("# DIRECTIVES factices\n\nRegle 1.\n", encoding="utf-8")
        (ap / "SCOPE-SERIAL").write_text("7\n", encoding="utf-8")
        directives.AUTOPORT = ap
        directives.DIRECTIVES = ap / "DIRECTIVES.md"
        directives.SERIAL_FILE = ap / "SCOPE-SERIAL"
        directives.ISSUED = ap / ".directives_issued"
        self.ap = ap
        return ap

    def __exit__(self, *exc):
        try:
            for k, v in self.saved.items():
                setattr(directives, k, v)
        finally:
            self.td.cleanup()
        return False


def probe_stale(pub, report_verdict=None):
    """Contrôles positifs (refuses) + negatifs (acceptes) + cablage AST de close_gate."""
    rv = report_verdict or directives.report_verdict
    item = {"id": "x-item", "owner_test": False, "code_scope": "harnais"}
    with _Sandbox() as ap:
        cur = directives.version("x-item", item)
        s6, s7x, s7y, s7h = "v6666666666", "v7777777777", "v7a7a7a7a7a", "v7b7b7b7b7b"
        directives.ISSUED.write_text(
            f"6 {s6} x-item\n7 {s7x} x-item\n7 {s7y} y-item\n7 {s7h}\n", encoding="utf-8")
        rep = ap / "reports"
        rep.mkdir()

        def rpt(name, body):
            p = rep / name
            if body is not None:
                p.write_text(body, encoding="utf-8")
            return p

        positives = [
            rpt("p_serie6.txt", f"Verdict.\nDIRECTIVES {s6}\n"),
            rpt("p_sans_ligne.txt", "Verdict sans ligne de contrat.\n"),
            rpt("p_absent.txt", None),
            rpt("p_autre_item.txt", f"DIRECTIVES {s7y}\n"),
            rpt("p_courante_et_perimee.txt", f"DIRECTIVES {cur}\nDIRECTIVES {s6}\n"),
        ]
        negatives = [
            rpt("n_courante.txt", f"DIRECTIVES {cur}\n"),
            rpt("n_serie7_item.txt", f"DIRECTIVES {s7x}\n"),
            rpt("n_heritee.txt", f"DIRECTIVES {s7h}\n"),
        ]
        refused = sum(1 for p in positives if not rv("x-item", p, item=item)[0])
        accepted = sum(1 for p in negatives if rv("x-item", p, item=item)[0])
    tree = ast.parse(ORCH_PY.read_text(encoding="utf-8"))
    cg = _func(tree, "close_gate")
    calls = _calls_attr(cg, "report_verdict") if cg else 0
    # 25/09 (harness-directives-gate-reads-any-report-name) : close_gate appelle
    # `directives_gate`, qui juge le DOSSIER du rapport par `dir_verdict` -> `report_verdict`.
    dg = _func(tree, "directives_gate")
    if cg and dg and any(isinstance(n, ast.Call) and getattr(n.func, "id", "") == "directives_gate"
                         for n in ast.walk(cg)):
        calls += _calls_attr(dg, "dir_verdict")
    if pub is not None:
        pub["directives_stale_positive_refused"] = f"{refused}/{len(positives)}"
        pub["directives_stale_negative_accepted"] = f"{accepted}/{len(negatives)}"
        pub["directives_report_gate_calls"] = calls
    return refused == len(positives) and accepted == len(negatives) and calls >= 1


def probe_checkpoint(pub, worker_paths=None):
    orch = _orch()
    dirty = [".autoport/DIRECTIVES.md", ".autoport/state.json", "game/x.cpp"]
    saved = orch.dirty_paths
    orch.dirty_paths = lambda *a, **k: list(dirty)
    try:
        wp = worker_paths or orch.worker_paths
        right = {"id": "x-item", "harness_writes": [".autoport/DIRECTIVES.md"]}
        none_ = {"id": "x-item"}
        greedy = {"id": "x-item", "harness_writes": [".autoport/state.json"]}
        a = wp(right)
        checks = [
            ".autoport/DIRECTIVES.md" in a,
            ".autoport/state.json" not in a,
            "game/x.cpp" in a,
            ".autoport/DIRECTIVES.md" not in wp(none_),
            ".autoport/state.json" not in wp(greedy),
            ".autoport/DIRECTIVES.md" not in wp(),
        ]
    finally:
        orch.dirty_paths = saved
    tree = ast.parse(ORCH_PY.read_text(encoding="utf-8"))
    host = None
    for n in ast.walk(tree):
        if isinstance(n, ast.FunctionDef) and any(
                isinstance(m, ast.FunctionDef) and m.name == "_checkpoint" and m is not n
                for m in ast.walk(n)):
            host = n
            break
    calls = [n for n in ast.walk(host) if isinstance(n, ast.Call)
             and isinstance(n.func, ast.Name) and n.func.id == "worker_paths"] if host else []
    without = sum(1 for c in calls if not (c.args or c.keywords))
    if pub is not None:
        pub["directives_checkpoint_checks"] = f"{sum(checks)}/{len(checks)}"
        pub["directives_checkpoint_host"] = host.name if host else "introuvable"
        pub["directives_worker_paths_calls_total"] = len(calls)
        pub["directives_worker_paths_calls_without_item"] = without
    return all(checks) and host is not None and len(calls) >= 1 and without == 0


def probe_findings(pub):
    src = ORCH_PY.read_text(encoding="utf-8")
    cg = _func(ast.parse(src), "close_gate")
    return bool(cg) and "findings_gate" in (ast.get_source_segment(src, cg) or "")


REGISTRY = [
    ("stale-report-refused", re.compile(r"recalcule la version et refuse un rapport"), probe_stale),
    ("directives-follows-checkpoint", None, probe_checkpoint),
    ("findings-read-by-close-gate", re.compile(r"porte de fermeture lit ce fichier"), probe_findings),
]


def classify(promises):
    """Promesses extraites qui ne matchent AUCUNE ancre du registre."""
    return [p for p in promises
            if not any(rx is not None and rx.search(p) for _i, rx, _f in REGISTRY)]


def contract_text():
    return directives._dtext() + "\n\n" + directives.block(ITEM_ID, record=False)


def main():
    pub, kept = {}, {}
    for pid, _rx, fn in REGISTRY:
        try:
            kept[pid] = bool(fn(pub))
        except Exception as e:  # noqa: BLE001
            kept[pid] = False
            pub[f"directives_error_{pid.replace('-', '_')}"] = _clean(f"{type(e).__name__}:{e}")[:160]

    text = contract_text()
    extracted = extract(text)
    unreg = classify(extracted)
    unkept_ids = [pid for pid, _r, _f in REGISTRY if not kept[pid]] + \
        [f"non-enregistree:{_clean(p)[:60]}" for p in unreg]
    unkept = len(unkept_ids)

    # --- contrôles fabriques : le banc doit rougir la ou on SAIT qu'il y a un defaut
    ctrl = {}
    try:
        fab = extract(text + "\n\nLe juge refuse un rapport sans titre.\n")
        ctrl["extractor"] = len(classify(fab)) == len(unreg) + 1
    except Exception:  # noqa: BLE001
        ctrl["extractor"] = False
    try:
        orch = _orch()
        dirty = [".autoport/DIRECTIVES.md", ".autoport/state.json", "game/x.cpp"]
        fake = lambda item=None: sorted(p for p in dirty if not orch._is_harness_state(p))  # noqa: E731
        ctrl["checkpoint"] = not probe_checkpoint(None, worker_paths=fake)
    except Exception:  # noqa: BLE001
        ctrl["checkpoint"] = False
    try:
        ctrl["stale"] = not probe_stale(None, report_verdict=lambda *a, **k: (True, "tout passe"))
    except Exception:  # noqa: BLE001
        ctrl["stale"] = False
    blind = not all(ctrl.values())
    if blind:
        unkept += 1000

    pub["directives_promises_extracted"] = len(extracted)
    pub["directives_promises_registered"] = len(REGISTRY)
    pub["directives_promises_total"] = len(REGISTRY) + len(unreg)
    pub["directives_promises_kept"] = sum(kept.values())
    for pid, _r, _f in REGISTRY:
        pub[f"directives_promise_{pid.replace('-', '_')}"] = "kept" if kept[pid] else "unkept"
    for i, p in enumerate(extracted, 1):
        pub[f"directives_extracted_{i}"] = _clean(p)[:160]
    pub["directives_control_extractor_red"] = int(ctrl["extractor"])
    pub["directives_control_checkpoint_red"] = int(ctrl["checkpoint"])
    pub["directives_control_stale_red"] = int(ctrl["stale"])
    pub["directives_selftest_blind"] = int(blind)
    pub["directives_unkept_list"] = ",".join(unkept_ids) if unkept_ids else "aucune"
    pub["directives_unkept_promises"] = unkept
    for k, v in pub.items():
        print(f"{k}={_clean(v)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
