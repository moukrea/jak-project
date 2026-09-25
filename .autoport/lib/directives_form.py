#!/usr/bin/env python3
"""Refus de FORME de la porte DIRECTIVES — recensement du passé et recensement de l'item.

harness-directives-gate-reads-any-report-name (25/09). Jusqu'à ce jour la porte ne lisait que
`reports/<id>/report.txt`. Un essai VERT dont le rapport portait la ligne `DIRECTIVES v…` sous
un autre nom (report.md, handoff.md) était refusé ET compté.

  past_refusals(autoport_dir) -> un dict par refus DIRECTIVES trouvé dans
      `logs/<id>/validator-NNN.txt`. Pour un refus « absent / aucune ligne », le dossier du
      rapport est RECONSTRUIT tel qu'il était à l'instant du refus (fichiers dont le mtime
      précède celui du journal) ; `misnamed` = un fichier autre que report.txt y portait la
      ligne, `found` le nomme, `still_blind` = la porte d'aujourd'hui, rejouée sur une copie
      de ce dossier, ne la trouverait toujours pas.

  census -> les clés `directives_gate_*` publiées dans proof.txt par
      `lib/census/harness-directives-gate-reads-any-report-name.sh`.
"""
import ast
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))
import directives as dv  # noqa: E402

# Les refus `CLOSE-GATE/directives-forme:` (depuis le 25/09) ne sont deja pas comptes : exclus.
GATE_RX = re.compile(r"^CLOSE-GATE/directives: (.*)$", re.M)
FORM_RX = re.compile(r"rapport absent|aucune ligne|ne porte aucune ligne|aucun rapport")
SEQ_RX = re.compile(r"validator-(\d+)\.txt$")


def _reconstruct(report_dir: Path, at: float, dst: Path) -> list[str]:
    """Copie dans `dst` les candidats-rapports qui existaient déjà à l'instant `at`."""
    kept = []
    for c in dv.report_candidates(report_dir):
        if c.is_file() and c.stat().st_mtime <= at:
            shutil.copy2(c, dst / c.name)
            kept.append(c.name)
    return kept


def past_refusals(autoport_dir) -> list[dict]:
    ap = Path(autoport_dir)
    out = []
    for vlog in sorted((ap / "logs").glob("*/validator-*.txt")):
        try:
            txt = vlog.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        m = GATE_RX.search(txt)
        if not m:
            continue
        item = vlog.parent.name
        sm = SEQ_RX.search(vlog.name)
        seq = int(sm.group(1)) if sm else 0
        why = m.group(1).strip()
        rec = {"item": item, "attempt": seq, "key": f"{item}#{seq}", "log": str(vlog),
               "why": why[:200], "kind": "form" if FORM_RX.search(why) else "stale",
               "misnamed": False, "found": "", "reconstructed": [], "still_blind": False}
        if rec["kind"] == "form":
            at = vlog.stat().st_mtime
            with tempfile.TemporaryDirectory(prefix="dform-") as td:
                kept = _reconstruct(ap / "reports" / item, at, Path(td))
                rec["reconstructed"] = kept
                carriers = [n for n in kept if n != "report.txt" and dv.REPORT_VERSION_RX.search(
                    (Path(td) / n).read_text(encoding="utf-8", errors="replace"))]
                if carriers:
                    rec["misnamed"] = True
                    rec["found"] = carriers[0]
                    p, _read, _old = dv.find_report(item, td)
                    rec["still_blind"] = p is None
        out.append(rec)
    return out


# ------------------------------------------------------------------ recensement de l'item
ITEM = "harness-directives-gate-reads-any-report-name"


def _controls(orch, item: dict) -> dict:
    """Bancs jetables, jugés par la VRAIE porte (`orchestrator.directives_gate`)."""
    cur = dv.version(ITEM, item)
    cases = {
        # nom : (fichiers, statut attendu)
        "pos_report_md": ({"report.md": f"verdict\nDIRECTIVES {cur}\n"}, "pass"),
        "pos_handoff_md": ({"handoff.md": f"## ETABLI\nDIRECTIVES {cur}\n"}, "pass"),
        "pos_other_name": ({"rapport-final.md": f"DIRECTIVES {cur}\n"}, "pass"),
        "pos_txt_without_line_md_with": ({"report.txt": "pas de ligne\n",
                                          "report.md": f"DIRECTIVES {cur}\n"}, "pass"),
        "neg_stale_in_md": ({"report.md": "DIRECTIVES v0000000000\n"}, "fail"),
        "neg_stale_in_txt": ({"report.txt": "DIRECTIVES v0000000000\n",
                              "report.md": f"DIRECTIVES {cur}\n"}, "fail"),
        "neg_no_line_anywhere": ({"report.md": "rien\n", "FINDINGS.txt": "AUCUN\n",
                                  "proof.txt": f"x=DIRECTIVES {cur}\n"}, "form"),
    }
    # Le motif de refus que l'orchestrateur pose EN TETE du handoff ne doit jamais se faire
    # passer pour la ligne du worker a l'essai suivant (la porte relit handoff.md).
    with tempfile.TemporaryDirectory(prefix="dform-ctl-") as td:
        _st, reason = orch.directives_gate(ITEM, item, 0.0, report_dir=Path(td))
    dit = orch.requalify_form_attempt({"retries": {}}, ITEM, reason)[1]
    cases["neg_gate_reason_in_handoff"] = (
        {"handoff.md": "## Porte de fermeture (ecrit par l'orchestrateur)\n" + reason + "\n"
                       + dit + "\n"}, "form")
    res = {}
    for name, (files, want) in cases.items():
        with tempfile.TemporaryDirectory(prefix="dform-ctl-") as td:
            for fn, body in files.items():
                (Path(td) / fn).write_text(body, encoding="utf-8")
            got, _why = orch.directives_gate(ITEM, item, 0.0, report_dir=Path(td))
            # Bras « porte d'avant » : le seul report.txt. Il doit refuser les controles
            # positifs, sinon ces controles ne discriminent rien.
            old_ok = dv.report_verdict(ITEM, Path(td) / "report.txt", item=item)[0]
        res[name] = (got, want, old_ok)
    return res


def _requalify_bench(orch) -> dict:
    st = {"retries": {"x": 3}}
    v1, _ = orch.requalify_form_attempt(st, "x", "CLOSE-GATE/directives-forme: banc")
    r1 = st["retries"]["x"]
    verdicts = [v1]
    for _ in range(orch.MAX_FORM_IN_A_ROW):
        st["retries"]["x"] += 1           # l'essai suivant est compté AVANT la porte
        v, _ = orch.requalify_form_attempt(st, "x", "banc")
        verdicts.append(v)
    return {"first": v1, "retries_after_first": r1, "last": verdicts[-1],
            "retries_after_all": st["retries"]["x"]}


def _close_gate_calls_helper(orch_path: Path) -> int:
    tree = ast.parse(orch_path.read_text(encoding="utf-8"))
    for fn in ast.walk(tree):
        if isinstance(fn, ast.FunctionDef) and fn.name == "close_gate":
            return sum(1 for n in ast.walk(fn) if isinstance(n, ast.Call)
                       and getattr(n.func, "id", "") == "directives_gate")
    return 0


def census() -> int:
    ap = HERE.parent
    sys.path.insert(0, str(ap))
    import orchestrator as orch  # noqa: E402
    item = dv._item(ITEM) or {"id": ITEM}
    penalty, why = 0, []

    ctl = _controls(orch, item)
    old_refused = sum(1 for n, v in ctl.items() if n.startswith("pos_") and not v[2])
    print(f"directives_gate_old_reader_refuses_positives={old_refused}/"
          f"{sum(1 for n in ctl if n.startswith('pos_'))}")
    ctl = {n: v[:2] for n, v in ctl.items()}
    for name, (got, want) in ctl.items():
        print(f"directives_gate_control_{name}={got}")
        if got != want:
            penalty += 1
            why.append(f"{name}:{got}!={want}")
    pos_ok = sum(1 for n, (g, w) in ctl.items() if n.startswith("pos_") and g == w)
    neg_ok = sum(1 for n, (g, w) in ctl.items() if n.startswith("neg_") and g == w)
    print(f"directives_gate_positive_controls_ok={pos_ok}/"
          f"{sum(1 for n in ctl if n.startswith('pos_'))}")
    print(f"directives_gate_negative_controls_ok={neg_ok}/"
          f"{sum(1 for n in ctl if n.startswith('neg_'))}")

    b = _requalify_bench(orch)
    print(f"directives_gate_form_requalify_first={b['first']}")
    print(f"directives_gate_form_retries_after_first={b['retries_after_first']}")
    print(f"directives_gate_form_requalify_after_cap={b['last']}")
    print(f"directives_gate_form_retries_after_cap={b['retries_after_all']}")
    if not (b["first"] == "requalifie" and b["retries_after_first"] == 2
            and b["last"] == "bloque" and b["retries_after_all"] == 2):
        penalty += 1
        why.append("requalification-forme")

    calls = _close_gate_calls_helper(ap / "orchestrator.py")
    print(f"directives_gate_close_gate_calls={calls}")
    if calls != 1:
        penalty += 1
        why.append(f"close_gate_calls={calls}")

    past = past_refusals(ap)
    mis = [r for r in past if r["misnamed"]]
    blind = [r for r in mis if r["still_blind"]]
    print(f"directives_gate_past_refusals={len(past)}")
    print(f"directives_gate_past_form_refusals={sum(1 for r in past if r['kind'] == 'form')}")
    print(f"directives_gate_past_misnamed={len(mis)}")
    print("directives_gate_past_misnamed_list="
          + (",".join(f"{r['key']}:{r['found']}" for r in mis) or "-"))
    # Refus de forme dont le dossier n'a laisse AUCUN fichier anterieur au refus (reecrit
    # depuis) : on ne sait pas s'il portait la ligne ailleurs. Nommes, jamais rembourses.
    unk = [r["key"] for r in past if r["kind"] == "form" and not r["reconstructed"]]
    print(f"directives_gate_past_form_undetermined={len(unk)}")
    print("directives_gate_past_form_undetermined_list=" + (",".join(unk) or "-"))
    print(f"directives_gate_past_misnamed_still_blind={len(blind)}")
    penalty += len(blind)
    if blind:
        why.append("aveugle:" + ",".join(r["key"] for r in blind))

    try:
        state = json.loads((ap / "state.json").read_text())
    except (OSError, ValueError):
        state = {}
    refunded = ((state.get("directives_form") or {}).get("refunded") or {})
    applied = [r["key"] for r in mis if r["key"] in refunded]
    pending = [r["key"] for r in mis if r["key"] not in refunded]
    print(f"directives_gate_refunds_applied={len(applied)}")
    print(f"directives_gate_refunds_pending={len(pending)}")
    print("directives_gate_refunds_pending_list=" + (",".join(pending) or "-"))

    print(f"directives_gate_misnamed_refusals_why={';'.join(why) or '-'}")
    print(f"directives_gate_misnamed_refusals={penalty}")
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "past"
    if cmd == "census":
        sys.exit(census())
    for r in past_refusals(HERE.parent):
        print(json.dumps(r, ensure_ascii=False))
