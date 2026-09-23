#!/usr/bin/env bash
# census/harness-owner-test-requires-a-capture.sh — LE VERDICT DE L'ITEM.
#
# Lance par `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`) apres la course.
#
# LA GRANDEUR. `owner_test_capture_defects` = somme de termes, UN TERME NON MESURE COMPTE 1 :
#
#   T1 BANC      `tests/harness/test_owner_capture_gate.py` contre le VRAI close_gate : sans image
#                -> refus nomme ; image postee pendant l'essai -> passe ; image d'un essai
#                precedent -> refus ; « rien a installer / regarder » -> passe sans image
#                (controle) ; capture impossible + build publie -> passe ; sans build -> refus ;
#                post_comment ecrit le registre. Terme = tests rouges (1 si rien collecte).
#   T1' ABLATION le MEME banc, `owner_capture.judge` neutralise : les 3 cas de refus DOIVENT rougir,
#                sinon le banc est vert par construction. Terme = 1 si moins de 3 rouges.
#   T2 RELEVE    les passages en test (commits « EN ATTENTE DU TEST DE L'OWNER ») d'items visibles
#                dans les 7 jours avant la creation de l'item (21/09 00:55), juges sur le journal
#                de l'essai qui les a produits : commentaire `linear_sync --comment` portant une
#                image (`--attach` d'image ou `![`). Attendu >= 3, dont les trois cas nommes.
#                Terme = 1 sinon.
#   T3 CITEE     DIRECTIVES cite `CLOSE-GATE/capture` ET close_gate APPELLE `owner_capture.judge`
#                (noeud d'appel, pas une chaine). Terme = 1 sinon.
#   T4 VIVANT    les passages en test d'items visibles APRES l'installation de la porte, juges sur
#                le registre `logs/linear_comments.jsonl` (issues a/b/c de l'owner du 22/09) :
#                chaque issue (c) compte 1.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "owner_test_capture_defects=-1"; exit 1; }
cd "$ROOT" || exit 1
TMPD=$(mktemp -d) || { echo "owner_test_capture_defects=-1"; exit 1; }
trap 'rm -rf "$TMPD"' EXIT

cat > "$TMPD/capture_ablation.py" <<'PY'
import pytest


@pytest.fixture(autouse=True)
def _porte_capture_neutralisee(monkeypatch):
    import orchestrator
    oc = orchestrator.owner_capture
    monkeypatch.setattr(oc, "judge", lambda item, since, ap: dict(
        verdict=oc.HORS_CHAMP, why="ablation", comments=0, images=0, declared=0, build=""))
PY

BANC=.autoport/tests/harness/test_owner_capture_gate.py
timeout 300 python3 -m pytest -q -p no:cacheprovider "$BANC" --junitxml="$TMPD/on.xml" \
  > "$TMPD/on.log" 2>&1
PYTHONPATH="$TMPD${PYTHONPATH:+:$PYTHONPATH}" timeout 300 python3 -m pytest -q -p no:cacheprovider \
  -p capture_ablation "$BANC" --junitxml="$TMPD/off.xml" > "$TMPD/off.log" 2>&1

TMPD="$TMPD" python3 - <<'PY'
import ast, glob, json, os, re, subprocess, sys, time
import xml.etree.ElementTree as ET
from datetime import datetime

sys.path.insert(0, os.path.abspath(".autoport"))
from lib import owner_capture as OC
import yaml

OUT, ORDRE = {}, []
def pub(k, v):
    if k not in OUT:
        ORDRE.append(k)
    OUT[k] = str(v).replace(" ", "_")

TMPD = os.environ["TMPD"]
defects = 0

# ---- T1 / T1' -------------------------------------------------------------------------------
def junit(path):
    try:
        root = ET.parse(path).getroot()
    except (OSError, ET.ParseError):
        return None
    cases = root.iter("testcase")
    total, red = 0, []
    for c in cases:
        total += 1
        if c.find("failure") is not None or c.find("error") is not None:
            red.append(c.get("name"))
    return total, red

on, off = junit(os.path.join(TMPD, "on.xml")), junit(os.path.join(TMPD, "off.xml"))
if on is None or on[0] == 0:
    t1 = 1; pub("capture_gate_tests_total", 0); pub("capture_gate_tests_failed", -1)
else:
    t1 = len(on[1]); pub("capture_gate_tests_total", on[0]); pub("capture_gate_tests_failed", len(on[1]))
    pub("capture_gate_tests_red", ",".join(on[1]) or "-")
REFUS = ("test_visible_without_image_is_refused_with_the_reason",
         "test_image_of_a_previous_attempt_does_not_count",
         "test_impossible_capture_without_a_fresh_build_is_refused")
if off is None or off[0] == 0:
    t1b = 1; pub("capture_gate_ablation_red", -1)
else:
    rouges = [n for n in off[1] if n in REFUS]
    t1b = 0 if len(rouges) == len(REFUS) else 1
    pub("capture_gate_ablation_red", len(off[1]))
    pub("capture_gate_ablation_refusals_red", "%d/%d" % (len(rouges), len(REFUS)))
pub("capture_term_bench", t1); pub("capture_term_ablation", t1b)
defects += t1 + t1b

# ---- population des passages en test ----------------------------------------------------------
raw = yaml.safe_load(open(".autoport/backlog.yaml"))
items = raw.get("items", raw) if isinstance(raw, dict) else raw
bl = {it["id"]: it for it in items if isinstance(it, dict) and it.get("id")}

log = subprocess.run(["git", "log", "--since=2026-09-01", "--format=%ct|%s"],
                     capture_output=True, text=True).stdout.splitlines()
PASS_RX = re.compile(r"^\[autoport/([^\]]+)\] .*EN ATTENTE DU TEST DE L'OWNER")
passages = []
for ln in log:
    ct, _, subj = ln.partition("|")
    m = PASS_RX.match(subj)
    if m:
        passages.append((int(ct), m.group(1)))

IMG_EXT = re.compile(r"--attach\b[^\n|;&]*\.(png|jpe?g|gif|webp)\b", re.I)

def attempt_for(iid, when):
    best = None
    for f in glob.glob(".autoport/logs/%s/attempt-*.jsonl" % iid):
        try:
            with open(f, errors="replace") as fh:
                first = json.loads(fh.readline())
            st = datetime.fromisoformat(first["started_at"]).timestamp()
        except Exception:
            continue
        if st <= when and (best is None or st > best[0]):
            best = (st, f)
    return best[1] if best else None

def attempt_posted_image(path):
    """(commentaires postes, dont avec image) — lus sur les commandes Bash du journal de l'essai."""
    n = img = 0
    with open(path, errors="replace") as fh:
        for ln in fh:
            if "linear_sync" not in ln or "--comment" not in ln:
                continue
            try:
                d = json.loads(ln)
            except ValueError:
                continue
            for c in ((d.get("message") or {}).get("content") or []):
                if not isinstance(c, dict) or c.get("type") != "tool_use":
                    continue
                cmd = str((c.get("input") or {}).get("command") or "")
                if "linear_sync" in cmd and "--comment" in cmd:
                    n += 1
                    if IMG_EXT.search(cmd) or "![" in cmd:
                        img += 1
    return n, img

# ---- T2 : releve des 7 jours avant la creation de l'item ---------------------------------------
FIN = datetime.fromisoformat("2026-09-21T00:55:00+02:00").timestamp()
DEBUT = FIN - 7 * 86400
NOMMES = {"hud-eco-gauge", "grass-blade-variants", "grass-interaction-direction"}
sans, avec, inconnus, hors = [], 0, 0, 0
for ct, iid in passages:
    if not (DEBUT <= ct <= FIN):
        continue
    it = bl.get(iid)
    if it is None:
        inconnus += 1; continue
    if not OC.is_visible(it)[0]:
        hors += 1; continue
    f = attempt_for(iid, ct)
    if f is None:
        inconnus += 1; continue
    n, img = attempt_posted_image(f)
    if img:
        avec += 1
    else:
        sans.append("%s@%s" % (iid, datetime.fromtimestamp(ct).strftime("%m%d-%H%M")))
nommes_vus = sorted({s.split("@")[0] for s in sans} & NOMMES)
pub("capture_survey_window", "%s..%s" % (datetime.fromtimestamp(DEBUT).strftime("%m%d-%H%M"),
                                          datetime.fromtimestamp(FIN).strftime("%m%d-%H%M")))
pub("capture_survey_visible_without_image", len(sans))
pub("capture_survey_visible_with_image", avec)
pub("capture_survey_out_of_scope", hors)
pub("capture_survey_unknown", inconnus)
pub("capture_survey_named_found", "%d/%d" % (len(nommes_vus), len(NOMMES)))
pub("capture_survey_list", ",".join(sans) or "-")
t2 = 0 if (len(sans) >= 3 and len(nommes_vus) == len(NOMMES)) else 1
pub("capture_term_survey", t2)
defects += t2

# ---- T3 : DIRECTIVES cite la porte, close_gate l'appelle ----------------------------------------
dir_cite = open(".autoport/DIRECTIVES.md", encoding="utf-8").read().count("CLOSE-GATE/capture")
appel = 0
tree = ast.parse(open(".autoport/orchestrator.py").read())
for fn in ast.walk(tree):
    if isinstance(fn, ast.FunctionDef) and fn.name == "close_gate":
        for n in ast.walk(fn):
            if (isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr == "judge"
                    and isinstance(n.func.value, ast.Name) and n.func.value.id == "owner_capture"):
                appel += 1
pub("capture_directives_cites", dir_cite)
pub("capture_close_gate_calls", appel)
t3 = 0 if (dir_cite >= 1 and appel >= 1) else 1
pub("capture_term_cited", t3)
defects += t3

# ---- T4 : passages VIVANTS depuis l'installation de la porte -----------------------------------
inst = subprocess.run(["git", "log", "--reverse", "--format=%ct", "-S", "owner_capture.judge", "--",
                       ".autoport/orchestrator.py"], capture_output=True, text=True).stdout.split()
depuis = float(inst[0]) if inst else time.time()
pub("capture_gate_installed", datetime.fromtimestamp(depuis).strftime("%Y%m%d-%H%M") if inst else "non-commite")
vivants = {"capture": 0, "livre": 0, "defaut": 0, "hors-champ": 0, "sans-essai": 0}
for ct, iid in passages:
    if ct < depuis:
        continue
    it = bl.get(iid)
    f = attempt_for(iid, ct) if it else None
    if it is None or f is None:
        vivants["sans-essai"] += 1; continue
    with open(f, errors="replace") as fh:
        st = datetime.fromisoformat(json.loads(fh.readline())["started_at"]).timestamp()
    vivants[OC.judge(it, st, ".autoport")["verdict"]] += 1
for k, v in vivants.items():
    pub("capture_live_%s" % k.replace("-", "_"), v)
t4 = vivants["defaut"] + vivants["sans-essai"]
pub("capture_term_live", t4)
defects += t4

pub("capture_ledger_rows", sum(1 for _ in open(".autoport/logs/linear_comments.jsonl"))
    if os.path.exists(".autoport/logs/linear_comments.jsonl") else 0)
pub("owner_test_capture_defects", defects)
for k in ORDRE:
    print("%s=%s" % (k, OUT[k]))
PY
