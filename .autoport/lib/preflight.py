#!/usr/bin/env python3
"""PREFLIGHT — the recurring traps of this project, encoded as machine checks.

Owner, 2026-08-11: "tu devrais toujours t'assurer de modifier le framework pour
regler les soucis eventuels, les erreurs qui reviennent et compagnie, le but
etant d'avoir un cercle vertueux, pas un frein sur lequel on se casse les dents".

The rule this file exists to enforce: **a trap that has cost us once must never
be able to cost us twice**. When a failure recurs, it does not go in a memory
note or in a supervisor's head — it goes here, as a check that runs on its own
before every attempt, and whose findings are INJECTED INTO THE WORKER'S PROMPT
so the framework warns the worker before it steps in the trap.

Audience contract (as important as severity): a finding goes to whoever is
ALLOWED to fix it. Validator/harness defects are SUPERVISOR work -- the worker is
forbidden from touching validators -- so they are printed in the orchestrator log
and never injected into the worker's prompt, where they would only push it to
break the rule. Tree/code defects are WORKER work and are injected.

Severity contract, deliberately not a brake:
  BLOCKER — this WILL waste a cycle (silent runtime failure, false green).
            Injected into the prompt as work to do first.
  WARN    — worth knowing, injected as a note, never stops anything.

Adding a trap is three lines: a function that yields (sev, code, message), and
its name in CHECKS. Keep every check CHEAP (no builds, no device) — preflight
runs before each attempt and must stay under a second.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class MissingInput(Exception):
    """A check whose input is absent must say so, never assume an empty file.
    A path typo once made GD-LINK accuse a perfectly linked object: a check that
    lies is worse than no check."""


def _read(p, required=False):
    fp = ROOT / p
    if not fp.exists():
        if required:
            raise MissingInput(str(p))
        return ""
    return fp.read_text(errors="ignore")


def _active_set():
    """Files this cycle actually touches: the working tree plus the last 20
    commits. Style checks apply HERE only -- auditing every archived script of
    every closed phase floods the prompt, and a flood is a brake."""
    out = set()
    for cmd in (["git", "-C", str(ROOT), "status", "--porcelain"],
                ["git", "-C", str(ROOT), "diff", "--name-only", "HEAD~20", "HEAD"]):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=25)
        except Exception:
            continue
        for ln in r.stdout.splitlines():
            f = ln[3:] if cmd[3] == "status" else ln
            out.add(f.strip().strip('"'))
    return out


# --------------------------------------------------------------------------
# TRAP 1 — a GOAL object compiled but linked into no DGO.
# Cost: goal_src/jak1/pc/*.gc builds clean, then every function pointer in it is
# 0 and the game takes a SIGILL at runtime. Diagnosed the hard way more than
# once (memory: compiled-but-unlinked-goal-object, new-goal-src-needs-dgo-gd).
def check_goal_objects_linked():
    gds = " ".join(_read(p) for p in _list("goal_src/jak1/dgos/*.gd"))
    gp = _read("goal_src/jak1/game.gp", required=True)   # NOT jak1.gp -- it does not exist
    for gc in sorted((ROOT / "goal_src" / "jak1" / "pc").glob("*.gc")):
        obj = gc.stem + ".o"
        if obj not in gds and ("pc/%s.gc" % gc.stem) not in gp:
            yield ("BLOCKER", "GD-LINK",
                   "%s is in no .gd and in no .gp: it will compile, then every "
                   "function pointer in it is 0 and the game SIGILLs at runtime. "
                   "Add \"%s\" to goal_src/jak1/dgos/game.gd and engine.gd next to "
                   "the other pc objects." % (gc.as_posix().replace(str(ROOT) + "/", ""), obj))


def _list(pat):
    return [p.as_posix().replace(str(ROOT) + "/", "") for p in ROOT.glob(pat)]


# --------------------------------------------------------------------------
# TRAP 2 — pattern-kill that matches its own command line.
# Cost: `pkill -f "foo"` kills the caller (exit 144); a wait loop
# `while pgrep -f "foo"; do ...` waits on ITSELF forever, and the [f]oo bracket
# trick does NOT save the loop form. Has hung the harness overnight.
def check_self_matching_kills():
    live = _active_set()
    for p in sorted((ROOT / ".autoport").glob("*.sh")):
        if p.as_posix().replace(str(ROOT) + "/", "") not in live:
            continue
        txt = p.read_text(errors="ignore")
        for m in re.finditer(r"^[^#\n]*\b(pkill|pgrep)\s+-f\s+(['\"]?)([^'\"\s|)]+)\2",
                             txt, re.M):
            pat = m.group(3)
            if "[" in pat:                      # bracket trick present
                continue
            line = txt[:m.start()].count("\n") + 1
            sev = "BLOCKER" if re.search(r"\b(while|until)\b", m.group(0)) else "WARN"
            yield (sev, "SELF-KILL",
                   "%s:%d `%s -f %s` has no bracket guard: it matches its own "
                   "command line (exit 144, or a wait loop that never ends). Use "
                   "[%s]%s, or wait on an artifact / match `ps -eo comm`."
                   % (p.name, line, m.group(1), pat, pat[0], pat[1:]))


# --------------------------------------------------------------------------
# TRAP 3 — `cmake -B` inside a harness script.
# Cost: a full reconfigure invalidates 1300+ objects incl. unrelated jak2
# mips2c. The owner's standing order is incremental builds only.
def check_no_cmake_reconfigure():
    live = _active_set()
    for p in sorted((ROOT / ".autoport").glob("*.sh")):
        if p.as_posix().replace(str(ROOT) + "/", "") not in live:
            continue
        txt = p.read_text(errors="ignore")
        for m in re.finditer(r"^[^#\n]*cmake\s+(-B|--build\s+\S+\s+-B)", txt, re.M):
            yield ("WARN", "CMAKE-B",
                   "%s:%d runs `cmake -B` (full reconfigure, ~1300 objects). "
                   "Incremental `cmake --build <dir> --target gk` unless a build "
                   "OPTION changed." % (p.name, txt[:m.start()].count("\n") + 1))



def _live_validators(phase_id):
    """This cycle's validator plus any validator being edited. Scanning the ~230
    validators of closed phases produced 65KB of true-but-irrelevant findings --
    a flood is a brake, and it buries the one line that matters."""
    live = _active_set()
    out = []
    if phase_id:
        v = ROOT / ".autoport" / "validators" / ("phase-%s.sh" % phase_id)
        if v.exists():
            out.append(v)
    for f in live:
        if f.startswith(".autoport/validators/") and f.endswith(".sh"):
            fp = ROOT / f
            if fp.exists() and fp not in out:
                out.append(fp)
    return out


# --------------------------------------------------------------------------
# TRAP 4 — `set -o pipefail` + `grep -q` in a validator.
# Cost: grep -q exits early, SIGPIPEs the writer, and the pipeline's non-zero
# status silently flips a gate. This produced a false green once already.
def check_validator_pipefail_grepq(phase_id=None):
    for p in _live_validators(phase_id):
        txt = p.read_text(errors="ignore")
        if "pipefail" not in txt:
            continue
        for m in re.finditer(r"^[^#\n]*\|\s*grep\s+(-\w*q\w*)\s", txt, re.M):
            yield ("BLOCKER", "PIPEFAIL-GREPQ",
                   "%s:%d pipes into `grep -q` under `set -o pipefail`: grep exits "
                   "early, the writer takes SIGPIPE and the gate silently flips. "
                   "Use `grep -c`/a variable, or drop pipefail on that line."
                   % (p.name, txt[:m.start()].count("\n") + 1))


# --------------------------------------------------------------------------
# TRAP 5 — a negated character class written [^\n] in a validator grep.
# Cost: in POSIX grep that class excludes the LETTER n, not newline, so the gate
# matches nothing and reads green. Cost us a false green.
def check_validator_negated_class(phase_id=None):
    for p in _live_validators(phase_id):
        txt = p.read_text(errors="ignore")
        for m in re.finditer(r"grep[^\n]*\[\^\\n\]", txt):
            yield ("BLOCKER", "GREP-NEG-N",
                   "%s:%d grep uses [^\\n], which excludes the LETTER n in POSIX "
                   "grep, not a newline: the gate matches nothing and reads green."
                   % (p.name, txt[:m.start()].count("\n") + 1))


# --------------------------------------------------------------------------
# TRAP 6 — the phase's own report is older than the artifacts it describes.
# Cost: a stale report passes gates that describe work from a previous attempt.
def check_report_not_stale(phase_id=None):
    if not phase_id:
        return
    rep = ROOT / ".autoport" / "reports" / phase_id / "report.txt"
    if not rep.exists():
        return
    try:
        out = subprocess.run(["git", "-C", str(ROOT), "status", "--porcelain"],
                             capture_output=True, text=True, timeout=20).stdout
    except Exception:
        return
    newer = []
    for ln in out.splitlines():
        f = ln[3:].strip().strip('"')
        fp = ROOT / f
        if fp.suffix in (".gc", ".cpp", ".h", ".py") and fp.exists() \
           and fp.stat().st_mtime > rep.stat().st_mtime + 60:
            newer.append(f)
    if newer:
        yield ("WARN", "REPORT-STALE",
               "the report predates %d changed source file(s) (%s%s): rewrite it "
               "from THIS attempt's numbers, never leave a previous attempt's text."
               % (len(newer), ", ".join(newer[:3]), " ..." if len(newer) > 3 else ""))


CHECKS = [
    check_goal_objects_linked,
    check_self_matching_kills,
    check_no_cmake_reconfigure,
    check_validator_pipefail_grepq,
    check_validator_negated_class,
    check_report_not_stale,
]


def run(phase_id=None):
    findings = []
    for fn in CHECKS:
        try:
            args = (phase_id,) if fn.__code__.co_argcount else ()
            findings.extend(fn(*args))
        except MissingInput as e:                   # the CHECK is broken, not the tree
            findings.append(("WARN", "PREFLIGHT-BROKEN",
                             "%s cannot run: input %s is missing. Fix the check "
                             "before trusting its silence." % (fn.__name__, e)))
        except Exception as e:                      # a check must never break a run
            findings.append(("WARN", "PREFLIGHT-ERR", "%s: %s" % (fn.__name__, e)))
    return findings


SUPERVISOR_CODES = {"PIPEFAIL-GREPQ", "GREP-NEG-N", "PREFLIGHT-BROKEN",
                    "PREFLIGHT-ERR"}


def split(phase_id=None):
    """(worker-owned, supervisor-owned) findings."""
    f = run(phase_id)
    return ([x for x in f if x[1] not in SUPERVISOR_CODES],
            [x for x in f if x[1] in SUPERVISOR_CODES])


def prompt_block(phase_id=None):
    """The WORKER's findings, formatted for injection into its instructions."""
    f, _sup = split(phase_id)
    blockers = [x for x in f if x[0] == "BLOCKER"]
    if not f:
        return ""
    out = ["## PREFLIGHT — pièges connus détectés dans l'arbre AVANT que tu commences",
           "",
           "Ces points viennent de checks automatiques du framework, pas d'une opinion :",
           "chacun a déjà coûté un cycle par le passé. Les BLOCKER se règlent EN PREMIER.",
           ""]
    for sev, code, msg in blockers + [x for x in f if x[0] != "BLOCKER"]:
        out.append("* **%s [%s]** %s" % (sev, code, msg))
    out += ["", "---", ""]
    return "\n".join(out)


if __name__ == "__main__":
    pid = sys.argv[1] if len(sys.argv) > 1 else None
    if "--json" in sys.argv:
        print(json.dumps([{"sev": s, "code": c, "msg": m} for s, c, m in run(pid)], indent=2))
    else:
        f = run(pid)
        for sev, code, msg in f:
            print("[%s %s] %s" % (sev, code, msg))
        print("preflight: %d finding(s), %d blocker(s)"
              % (len(f), sum(1 for x in f if x[0] == "BLOCKER")))
        sys.exit(0)
