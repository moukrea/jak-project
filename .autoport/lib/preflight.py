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
ALLOWED to fix it. Harness/preflight defects are SUPERVISOR work and are printed
in the orchestrator log, never injected into the worker's prompt. Tree/code
defects are WORKER work and are injected.

Severity contract, deliberately not a brake:
  BLOCKER — this WILL waste a cycle (silent runtime failure, false green).
            Injected into the prompt as work to do first.
  WARN    — worth knowing, injected as a note, never stops anything.

HARD CAP (2026-09-03): at most MAX_PROMPT_FINDINGS findings ever reach the
worker's prompt; the overflow goes to the supervisor log. A preflight that
prints 147 lines is a brake, and the file's own rule already said so.

CONTRACT OF A CHECK (2026-09-03, the bug that killed this module for four days):
a check is a GENERATOR that YIELDS `(sev, code, message)` TRIPLES. It never
`return`s a tuple. `check_shield_untouched` returned a 2-tuple, `run()` did
`findings.extend(...)` on it — which appended its two STRINGS as two findings —
and `prompt_block` then raised `ValueError: not enough values to unpack` on the
first of them. The orchestrator swallowed the exception, so from 2026-08-30 to
2026-09-03 EVERY attempt logged `preflight unavailable` (278 occurrences) and
not one finding, worker or supervisor, was ever emitted. Two defences now:
`run()` validates the SHAPE of everything a check produces and turns a
malformed item into a PREFLIGHT-BROKEN finding instead of a crash, and
`tests/harness/test_preflight.py` asserts the triple shape for every check.

Adding a trap is three lines: a function that yields (sev, code, message), and
its name in CHECKS. Keep every check CHEAP (no builds, no device, no adb) —
preflight runs before each attempt and must stay under a second. A check that
needs a device belongs in `.autoport/acquis/`, not here.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# The worker's prompt never carries more than this many preflight findings.
MAX_PROMPT_FINDINGS = 5


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


def _list(pat):
    return [p.as_posix().replace(str(ROOT) + "/", "") for p in ROOT.glob(pat)]


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


def _live_autoport_scripts():
    """The `.autoport/*.sh` scripts of THIS cycle. The directory holds 624
    one-off campaign scripts of closed phases; reading all of them costs real
    time on every attempt and the findings it produces are about work nobody is
    doing. Same live-set rule as everywhere else in this file."""
    live = _active_set()
    out = []
    for p in sorted((ROOT / ".autoport").glob("*.sh")):
        if p.as_posix().replace(str(ROOT) + "/", "") in live:
            out.append(p)
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


# --------------------------------------------------------------------------
# TRAP 2 — pattern-kill that matches its own command line.
# Cost: `pkill -f "foo"` kills the caller (exit 144); a wait loop
# `while pgrep -f "foo"; do ...` waits on ITSELF forever, and the [f]oo bracket
# trick does NOT save the loop form. Has hung the harness overnight.
def check_self_matching_kills():
    for p in _live_autoport_scripts():
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
# TRAP 3 — une propriete de debogage laissee armee sur un appareil de l'owner.
# Cout REEL, 2026-08-28 : `debug.opengoal.cpad_inject` est restee a `x` sur
# l'appareil. Le jeu lit cette propriete en continu et `x` = bit 14 = CROIX, donc
# le bouton de SAUT etait TENU en permanence. Un bouton tenu n'emet aucun FRONT,
# et `(cpad-pressed? 0 x)` ne tire que sur le front : jeu injouable pendant des
# semaines, pendant que chaque controle de la chaine d'entree disait « saine »
# (les 228 evenements SDL arrivaient bien). Trois hypotheses ont ete refutees
# avant de trouver, toutes cherchaient une entree ABSENTE alors qu'elle etait
# COINCEE A 1.
_PROP = "debug.opengoal.cpad_inject"


def check_device_prop_leak():
    leakers = []
    scripts = _live_autoport_scripts()
    for p in scripts:
        txt = p.read_text(errors="ignore")
        if ("setprop %s" % _PROP) not in txt:
            continue
        # un nettoyage = la propriete remise a vide, ou le teardown appele
        cleared = re.search(r"setprop\s+%s\s+(''|\"\"|\s*$)" % re.escape(_PROP),
                            txt, re.M) or "device_teardown.sh" in txt
        if not cleared:
            leakers.append(p.name)
    if not leakers:
        return
    head = ", ".join(sorted(leakers)[:3]) + (" ..." if len(leakers) > 3 else "")
    yield ("BLOCKER", "DEVICE-PROP-LEAK",
           "%d script(s) de CE cycle posent `%s` sans jamais la vider (%s). Une "
           "valeur laissee la TIENT un bouton enfonce sur l'appareil de l'owner : "
           "plus aucun front, donc le jeu ne reagit plus a ce bouton, jusqu'au "
           "redemarrage. Ajouter `trap 'bash .autoport/lib/device_teardown.sh' EXIT` "
           "en tete de tout script qui touche un appareil, y compris quand il echoue."
           % (len(leakers), _PROP, head))


# --------------------------------------------------------------------------
# TRAP 4 — the item's own proof/report is older than the artifacts it describes.
# Cost: a stale report passes gates that describe work from a previous attempt.
def check_report_not_stale(item_id=None):
    if not item_id:
        return
    rep_dir = ROOT / ".autoport" / "reports" / item_id
    rep = None
    for name in ("proof.txt", "report.txt"):
        cand = rep_dir / name
        if cand.exists():
            rep = cand
            break
    if rep is None:
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
               "%s predates %d changed source file(s) (%s%s): it describes a "
               "PREVIOUS attempt. Re-run the proof from THIS attempt's build, "
               "never leave the previous run's numbers in place."
               % (rep.name, len(newer), ", ".join(newer[:3]),
                  " ..." if len(newer) > 3 else ""))


CHECKS = [
    check_goal_objects_linked,     # GD-LINK
    check_self_matching_kills,     # SELF-KILL
    check_device_prop_leak,        # DEVICE-PROP-LEAK
    check_report_not_stale,        # REPORT-STALE
]


def _valid_finding(x):
    return (isinstance(x, tuple) and len(x) == 3
            and all(isinstance(p, str) for p in x))


def run(item_id=None):
    """Every finding is a `(sev, code, message)` triple of strings.

    A check that produces anything else is reported as PREFLIGHT-BROKEN rather
    than allowed to raise: the whole module went dark for four days because one
    malformed value reached an unpacking site (see the module docstring)."""
    findings = []
    for fn in CHECKS:
        try:
            args = (item_id,) if fn.__code__.co_argcount else ()
            produced = list(fn(*args) or ())
        except MissingInput as e:                   # the CHECK is broken, not the tree
            findings.append(("WARN", "PREFLIGHT-BROKEN",
                             "%s cannot run: input %s is missing. Fix the check "
                             "before trusting its silence." % (fn.__name__, e)))
            continue
        except Exception as e:                      # a check must never break a run
            findings.append(("WARN", "PREFLIGHT-ERR", "%s: %s" % (fn.__name__, e)))
            continue
        for item in produced:
            if _valid_finding(item):
                findings.append(item)
            else:
                findings.append((
                    "WARN", "PREFLIGHT-BROKEN",
                    "%s produced %r, which is not a (sev, code, message) triple of "
                    "strings. A check YIELDS triples; it never returns a tuple."
                    % (fn.__name__, item)))
    return findings


SUPERVISOR_CODES = {"PREFLIGHT-BROKEN", "PREFLIGHT-ERR"}


def split(item_id=None):
    """(worker-owned, supervisor-owned) findings."""
    f = run(item_id)
    return ([x for x in f if x[1] not in SUPERVISOR_CODES],
            [x for x in f if x[1] in SUPERVISOR_CODES])


def prompt_findings(item_id=None):
    """(injected, overflow, supervisor).

    `injected` is capped at MAX_PROMPT_FINDINGS, BLOCKERs first. `overflow` is
    everything the cap dropped — the orchestrator prints it in its own log so a
    dropped finding is visible to a human, never silently lost."""
    worker, sup = split(item_id)
    ordered = ([x for x in worker if x[0] == "BLOCKER"]
               + [x for x in worker if x[0] != "BLOCKER"])
    return ordered[:MAX_PROMPT_FINDINGS], ordered[MAX_PROMPT_FINDINGS:], sup


def prompt_block(item_id=None):
    """The WORKER's findings, formatted for injection into its instructions."""
    injected, overflow, _sup = prompt_findings(item_id)
    if not injected:
        return ""
    out = ["## PREFLIGHT — pièges connus détectés dans l'arbre AVANT que tu commences",
           "",
           "Ces points viennent de checks automatiques du framework, pas d'une opinion :",
           "chacun a déjà coûté un cycle par le passé. Les BLOCKER se règlent EN PREMIER.",
           ""]
    for sev, code, msg in injected:
        out.append("* **%s [%s]** %s" % (sev, code, msg))
    if overflow:
        out += ["", "(%d autre(s) constat(s) au-delà du plafond de %d : ils sont dans le "
                "log de l'orchestrateur, pas ici.)" % (len(overflow), MAX_PROMPT_FINDINGS)]
    out += ["", "---", ""]
    return "\n".join(out)


if __name__ == "__main__":
    iid = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else None
    if "--json" in sys.argv:
        print(json.dumps([{"sev": s, "code": c, "msg": m} for s, c, m in run(iid)], indent=2))
    else:
        f = run(iid)
        for sev, code, msg in f:
            print("[%s %s] %s" % (sev, code, msg))
        print("preflight: %d finding(s), %d blocker(s), cap %d"
              % (len(f), sum(1 for x in f if x[0] == "BLOCKER"), MAX_PROMPT_FINDINGS))
        sys.exit(0)
