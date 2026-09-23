#!/usr/bin/env python3
"""Read-only defect probes for leftovers 1, 2 and 8; same probes at any git revision."""
import ast
import json
from pathlib import Path
import subprocess
import tempfile
import types


def _read(root, path, revision):
    if revision is None:
        return (root / path).read_text()
    return subprocess.run(["git", "-C", str(root), "show", f"{revision}:{path}"],
                          check=True, capture_output=True, text=True).stdout


def _scope_module(source):
    # Isolate the scope API, without importing or executing any verdict machinery.
    tree = ast.parse(source)
    names = {"normalise", "scope_decision", "scope_census", "code_free_item"}
    constants = {"CODE_FREE_PATTERNS", "SCOPE_FIELDS", "SCOPE_FIELD", "SCOPE_SANS_CODE",
                 "SCOPE_AVEC_CODE", "SRC_FIELD", "SRC_FLAG", "SRC_PROSE", "SRC_SILENT", "SRC_BAD",
                 "SCOPE_A_CADRER", "SRC_UNFRAMED"}
    tree.body = [n for n in tree.body if isinstance(n, ast.Assign) and any(
                    isinstance(t, ast.Name) and t.id in constants for t in n.targets)
                 or isinstance(n, ast.FunctionDef) and n.name in names]
    module = types.ModuleType("scope_probe")
    import re
    import unicodedata
    module.__dict__.update(re=re, unicodedata=unicodedata)
    exec(compile(tree, "<scope-api>", "exec"), module.__dict__)
    return module


def _guard_probe(source):
    # Execute the actual registered checks against a minimal tree containing a
    # deliberately missing GUARD. No repository sources, git state or devices touched.
    tree = ast.parse(source)
    tree.body = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.ClassDef))
                 or isinstance(n, ast.Assign) and not any(
                     isinstance(t, ast.Name) and t.id == "ROOT" for t in n.targets)]
    import re
    env = dict(Path=Path, re=re, subprocess=subprocess)
    exec(compile(tree, "<preflight-checks>", "exec"), env)
    with tempfile.TemporaryDirectory(prefix="leftovers-guard-") as directory:
        root = Path(directory)
        (root / ".autoport").mkdir()
        (root / "goal_src/jak1").mkdir(parents=True)
        (root / "goal_src/jak1/game.gp").write_text("")
        (root / ".autoport/PITFALLS.md").write_text(
            "GUARD leftovers-probe missing-file REQUIRED-MARKER\n")
        env.update(ROOT=root, _active_set=lambda: set())
        findings = env["run"]()
    return {"checks": [fn.__name__ for fn in env["CHECKS"]],
            "missing_guard_findings": findings,
            "guard_detected": any("leftovers-probe" in str(f) for f in findings)}


def run_checks(root, revision=None):
    root = Path(root).resolve()
    read = lambda path: _read(root, path, revision)
    module = _scope_module(read(".autoport/lib/gate_verdict.py"))
    conflict = {"id": "conflict", "code_scope": "engine", "no_code": True,
                "out_of_scope": "Ne touche à aucun code du jeu."}
    census = module.scope_census([conflict])
    decision = module.code_free_item(conflict)
    published = census.get("contradictions_count")
    import yaml
    live = module.scope_census(yaml.safe_load(read(".autoport/backlog.yaml"))["items"])
    point1 = {"defects": int(published != 1 or decision[0] is not False),
              "published_contradictions": published, "code_free": decision[0],
              "census": census,
              "live_contradictions_count": live.get("contradictions_count"),
              "live_contradictions": live.get("contradictions")}
    tree = ast.parse(read(".autoport/orchestrator.py"))
    messages = [n.value for n in ast.walk(tree) if isinstance(n, ast.Constant)
                and isinstance(n.value, str) and "CLOSE-GATE/code:" in n.value]
    point2 = {"defects": int(len(messages) != 1 or "code_scope:" not in messages[0]
                            or "mets `no_code: true`" in messages[0]),
              "messages": messages}
    guard = _guard_probe(read(".autoport/lib/preflight.py"))
    doc = read(".autoport/PITFALLS.md")
    promise = "vérifie à chaque tentative que le verrou est toujours en place" in doc
    honest = "ne lit pas ce registre" in doc and "ne garantit donc aucune alerte" in doc
    point8 = {"defects": int(not guard["guard_detected"] and (promise or not honest)),
              "promises_guard_check": promise, "documents_limit": honest, **guard}
    return {"point_1": point1, "point_2": point2, "point_8": point8}


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--revision")
    args = parser.parse_args()
    print(json.dumps(run_checks(args.root, args.revision), indent=2, ensure_ascii=False))
