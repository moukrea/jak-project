#!/usr/bin/env bash
# census/harness-supervisor-reader-must-be-the-supervisor.sh — LE VERDICT DE L'ITEM.
#
# Lance par `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`) apres la course.
#
# LA QUESTION : qui a le droit de tamponner `.supervisor-seen.json`, c'est-a-dire d'eteindre
# l'alarme « superviseur mort » ? Jusqu'au 23/09 : toute session sans variable de worker.
# Desormais : une session qui PROUVE etre le superviseur (registre, lanceur, conversation deja
# prouvee, reveil de supervision — `supervisor_alive.PREUVES`).
#
# TROIS TERMES
#   1. AVANT, sur 7 jours de vrais transcripts : les sessions qui ont soumis un prompt (donc fait
#      tourner le crochet), classees worker / superviseur / autre, et celles qui TAMPONNAIENT
#      sans etre le superviseur sous la regle d'avant.
#   2. POPULATION SEMEE, rejouee par le VRAI crochet (`wake_gate.py`) sous DEUX bras : le code
#      LIVRE et le code CONDAMNE (commit epingle, marqueur verifie). Huit sessions fabriquees,
#      de vrais processus nommes `claude` : quatre superviseurs (a tamponner) et quatre autres
#      (owner a la main, juge sous le superviseur, worker sous le superviseur, pid recycle).
#      Le bras condamne DOIT tamponner des sessions etrangeres et les NOMMER (controle positif) ;
#      le bras livre doit en tamponner zero ET tamponner les quatre superviseurs (controle
#      negatif : une regle qui ne tamponne rien serait verte par inaction).
#   3. APRES, le journal reel `logs/supervisor-seen.jsonl` : tout tampon sans preuve compte.
#
# `supervisor_foreign_stamps` = tampons etrangers du bras livre + tampons sans preuve du journal
#   reel + superviseurs NON tamponnes + cas non mesures + (1 si le controle positif ne rougit
#   pas). INCONNU = DEFAUT : chaque composante est publiee a part.
#
# RIEN ICI N'ECRIT DANS L'ETAT DU HARNAIS : les deux bras sont des COPIES dans un dossier jetable
# (le livre est compare octet a octet au depot), et tous les chemins passent par les surcharges
# `AUTOPORT_SUPERVISOR_*`.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "supervisor_foreign_stamps=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import glob, hashlib, json, os, shutil, subprocess, sys, tempfile, time
from datetime import datetime, timezone

sys.path.insert(0, os.path.abspath(".autoport"))
sys.path.insert(0, os.path.abspath(".autoport/lib"))
import supervisor_alive as SA
import wake_gate as WG

OUT, ORDRE = {}, []
def pub(k, v):
    if k not in ORDRE:
        ORDRE.append(k)
    OUT[k] = v

TMP = tempfile.mkdtemp(prefix="sup-reader-census-")
# Le code d'AVANT : dernier etat du tampon « pas un worker = lecteur ». Epingle, et verifie par
# MARQUEUR : un temoin lu a HEAD serait le code livre des le commit.
CONDAMNE = "720e2c3d8d"
defauts = {}

# =================================================================== 1. AVANT, 7 jours reels
TRANSCRIPTS = os.path.expanduser("~/.claude/projects/-home-emeric-code-jak-project")
SELF_DECLARE_TS = datetime(2026, 9, 22, 21, 54, 44, tzinfo=timezone.utc)   # 720e2c3d8d
REGISTRE_TS = datetime(2026, 9, 22, 13, 18, 26, tzinfo=timezone.utc)      # d14e1ddfc4

def texte_prompt(msg):
    c = msg.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
            return None
        t = [b.get("text") for b in c if isinstance(b, dict) and b.get("type") == "text"]
        return "\n".join(x for x in t if x) if t else None
    return None

def est_worker(t):
    tl = " ".join(t.split()).lower()
    return "## cet essai" in tl or "directives — autorité supérieure" in tl

try:
    now = datetime.now(timezone.utc)
    debut = now.timestamp() - 7 * 86400
    sess = {}
    for fp in glob.glob(os.path.join(TRANSCRIPTS, "*.jsonl")):
        if os.path.getmtime(fp) < debut:
            continue
        sid = os.path.basename(fp)[:-6]
        with open(fp, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if d.get("type") != "user" or d.get("isSidechain"):
                    continue
                msg = d.get("message") or {}
                if msg.get("role") != "user":
                    continue
                t = texte_prompt(msg)
                ts = d.get("timestamp")
                if t is None or not ts:
                    continue
                try:
                    tsd = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                except ValueError:
                    continue
                if tsd.timestamp() < debut:
                    continue
                sess.setdefault(sid, []).append((tsd, t))
    classes = {"worker": 0, "superviseur": 0, "autre": 0}
    etrangers, etrangers_prompts, sup_tampons = [], 0, 0
    for sid, ps in sess.items():
        ps.sort(key=lambda x: x[0])
        textes = [t for _, t in ps]
        # Un worker se reconnait a son PREMIER prompt (celui de l'orchestrateur) : le superviseur
        # CITE des prompts d'essai dans ses reveils, et « un prompt quelconque » le classait worker.
        if est_worker(textes[0]):
            cl = "worker"
        elif any(WG.est_un_reveil(t) for t in textes):
            cl = "superviseur"
        else:
            cl = "autre"
        classes[cl] += 1
        apres = [x for x, _ in ps if x >= SELF_DECLARE_TS]
        if cl == "autre" and apres:
            etrangers.append(sid[:8])
            etrangers_prompts += len(apres)
        if cl == "superviseur" and any(x >= REGISTRE_TS for x, _ in ps):
            sup_tampons += 1
    pub("supervisor_before_window_days", 7)
    pub("supervisor_before_sessions", len(sess))
    pub("supervisor_before_sessions_worker", classes["worker"])
    pub("supervisor_before_sessions_supervisor", classes["superviseur"])
    pub("supervisor_before_sessions_other", classes["autre"])
    pub("supervisor_before_stamping_supervisor_sessions", sup_tampons)
    # Sous la regle d'avant, une session « autre » qui soumet un prompt apres 720e2c3d8d TAMPONNE.
    pub("supervisor_before_foreign_sessions", len(etrangers))
    pub("supervisor_before_foreign_prompts", etrangers_prompts)
    pub("supervisor_before_foreign_ids", ",".join(sorted(etrangers)) or "-")
    pub("supervisor_before_rule_since", "2026-09-22T23:54:44+02:00")
except Exception as e:  # noqa: BLE001
    pub("supervisor_before_error", type(e).__name__)
    defauts["avant-non-mesure"] = 1

# ================================================================ 2. POPULATION SEMEE, 2 BRAS
BIN = os.path.join(TMP, "bin")
os.makedirs(BIN)
os.symlink(os.path.realpath(sys.executable), os.path.join(BIN, "claude"))
DRIVER = os.path.join(TMP, "session.py")
with open(DRIVER, "w") as fh:
    fh.write(r'''
import json, os, subprocess, sys, time
spec = json.load(open(sys.argv[1]))
def stat_start(pid):
    raw = open("/proc/%d/stat" % pid).read()
    return int(raw[raw.rfind(")") + 2:].split()[19])
me, st = os.getpid(), stat_start(os.getpid())
res = {"pid": me, "start": st, "comm": open("/proc/%d/comm" % me).read().strip()}
if spec.get("register_self"):
    json.dump({"pid": me, "start": str(st), "tty": "-"}, open(spec["terminal"], "w"))
if spec.get("declare"):
    d = spec["declare"]
    json.dump([{"ts": 0, "pid": me if d.get("pid") == "self" else d.get("pid"),
                "start": st + d.get("start_delta", 0), "session": d.get("session", "-"),
                "via": d.get("via", "lanceur")}], open(spec["declared"], "w"))
env = dict(spec["env"])
# Le pire cas : un fils HERITE du CLAUDE_PID de son pere (l'orchestrateur du 23/09 portait
# encore celui du superviseur du 22).
herite = os.environ.get("CLAUDE_PID") if spec.get("inherit_claude_pid") else None
env["CLAUDE_PID"] = herite or str(me)
if spec.get("child"):
    ch = spec["child"]
    open(ch["spec_path"], "w").write(json.dumps(ch))
    p = subprocess.Popen([spec["claude_bin"], __file__, ch["spec_path"]], env=env)
    for _ in range(300):
        if os.path.exists(ch["ready"]):
            break
        time.sleep(0.05)
    res["child_pid"] = p.pid
if spec.get("hook"):
    r = subprocess.run([spec["python"], spec["hook"]],
                       input=json.dumps({"prompt": spec["prompt"], "session_id": spec["session_id"]}),
                       env=env, capture_output=True, text=True, timeout=60)
    res["rc"] = r.returncode
open(spec["ready"] + ".tmp", "w").write(json.dumps(res))
os.replace(spec["ready"] + ".tmp", spec["ready"])
time.sleep(120)
''')

def arme(nom, sources):
    lib = os.path.join(TMP, nom, ".autoport", "lib")
    os.makedirs(lib)
    for f, contenu in sources.items():
        with open(os.path.join(lib, f), "wb") as fh:
            fh.write(contenu)
    return os.path.join(lib, "wake_gate.py")

def md5(b):
    return hashlib.md5(b).hexdigest()

livre_src = {f: open(".autoport/lib/%s" % f, "rb").read()
             for f in ("wake_gate.py", "supervisor_alive.py")}
try:
    cond_src = {f: subprocess.run(["git", "show", "%s:.autoport/lib/%s" % (CONDAMNE, f)],
                                  capture_output=True, check=True).stdout
                for f in ("wake_gate.py", "supervisor_alive.py")}
    marqueur = (b"_sa.self_declare(" in cond_src["wake_gate.py"]
                and b"def self_declare" in cond_src["supervisor_alive.py"]
                and b"stamp_reader" not in cond_src["wake_gate.py"])
except (subprocess.CalledProcessError, OSError):
    cond_src, marqueur = None, False
pub("supervisor_condemned_commit", CONDAMNE)
pub("supervisor_condemned_marker", 1 if marqueur else 0)
HOOK = {"livre": arme("livre", livre_src)}
if marqueur:
    HOOK["condamne"] = arme("condamne", cond_src)
pub("supervisor_livre_md5_matches_repo",
    1 if all(md5(open(os.path.join(os.path.dirname(HOOK["livre"]), f), "rb").read()) == md5(b)
             for f, b in livre_src.items()) else 0)

REVEIL = ("Point de supervision autoport : lis `./.autoport/autoport status`, le digest et les "
          "retours de l'owner, puis decide. " + "Surveillance periodique de l'orchestrateur. " * 12)
pub("supervisor_seed_wake_is_wake", 1 if WG.est_un_reveil(REVEIL) else 0)
COURT = "question de l'owner"

# (nom, classe attendue, preuve attendue du bras livre, construction)
CAS = [
    ("superviseur-registre", "sup", "registre", {"register_self": True}),
    ("superviseur-lanceur", "sup", "lanceur", {"declare": {"pid": "self", "via": "lanceur"}}),
    ("superviseur-reveil", "sup", "reveil", {"prompt": REVEIL}),
    ("superviseur-reprise", "sup", "session",
     {"declare": {"pid": 999999, "session": "conv-du-superviseur", "via": "reveil"},
      "session_id": "conv-du-superviseur"}),
    ("owner-a-la-main", "autre", SA.NON_DECLARE, {}),
    ("juge-sous-le-superviseur", "autre", SA.NON_DECLARE,
     {"register_self": True, "child_env": {"AUTOPORT_ROLE": "supervisor"}}),
    ("worker-sous-le-superviseur", "autre", "worker",
     {"register_self": True, "child_env": {"AUTOPORT_ATTEMPT_ID": "temoin@1#0"}}),
    ("lanceur-pid-recycle", "autre", SA.NON_DECLARE,
     {"declare": {"pid": "self", "via": "lanceur", "start_delta": 7}}),
]
pub("supervisor_cases_total", len(CAS))
pub("supervisor_cases_supervisor", sum(1 for c in CAS if c[1] == "sup"))
pub("supervisor_cases_other", sum(1 for c in CAS if c[1] == "autre"))

base_env = {k: v for k, v in os.environ.items()
            if k not in ("AUTOPORT_ATTEMPT_ID", "AUTOPORT_PHASE_ID", "CLAUDE_PID",
                         "AUTOPORT_ROLE") and not k.startswith("AUTOPORT_SUPERVISOR_")}
procs = []
res = {}
for bras, hook in HOOK.items():
    for nom, classe, preuve, c in CAS:
        d = os.path.join(TMP, bras, nom)
        os.makedirs(d)
        f = {"terminal": os.path.join(d, "terminal.json"),
             "seen": os.path.join(d, "seen.json"),
             "declared": os.path.join(d, "declared.json"),
             "log": os.path.join(d, "seen.jsonl")}
        env = dict(base_env, AUTOPORT_SUPERVISOR_TERMINAL=f["terminal"],
                   AUTOPORT_SUPERVISOR_SEEN=f["seen"], AUTOPORT_SUPERVISOR_DECLARED=f["declared"],
                   AUTOPORT_SUPERVISOR_SEEN_LOG=f["log"])
        spec = {"env": env, "terminal": f["terminal"], "declared": f["declared"],
                "claude_bin": os.path.join(BIN, "claude"),
                "python": os.path.realpath(sys.executable),
                "ready": os.path.join(d, "ready.json"),
                "register_self": c.get("register_self", False), "declare": c.get("declare")}
        tache = {"hook": hook, "prompt": c.get("prompt", COURT),
                 "session_id": c.get("session_id", "conv-%s" % nom)}
        if "child_env" in c:
            spec["child"] = dict(tache, env=dict(env, **c["child_env"]),
                                 inherit_claude_pid=True, python=spec["python"],
                                 spec_path=os.path.join(d, "child.json"),
                                 ready=os.path.join(d, "child-ready.json"),
                                 terminal=f["terminal"], declared=f["declared"])
            lecteur = spec["child"]["ready"]
        else:
            spec.update(tache)
            lecteur = spec["ready"]
        sp = os.path.join(d, "spec.json")
        json.dump(spec, open(sp, "w"))
        p = subprocess.Popen([os.path.join(BIN, "claude"), DRIVER, sp],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        procs.append(p)
        for _ in range(600):
            if os.path.exists(spec["ready"]) and os.path.exists(lecteur):
                break
            time.sleep(0.05)
        r = {"mesure": False, "tampon": False, "proof": "-", "why_probe": "-"}
        try:
            info = json.load(open(lecteur))
            r["mesure"] = info.get("comm") == "claude" and info.get("rc") == 0
            seen = SA.read_seen_record(f["seen"])
            r["tampon"] = bool(seen.get("ts"))
            r["proof"] = seen.get("proof", "-") if r["tampon"] else "-"
            r["pid_session"] = seen.get("pid") == info.get("pid")
            # L'ALARME : le releve LIVRE, sur ce qu'a laisse ce bras, voit-il un lecteur vivant ?
            rel = SA.probe(state_file=os.path.join(d, "aucun-registre.json"),
                           seen_file=f["seen"], launches=os.path.join(d, "aucun.jsonl"))
            r["why_probe"] = rel["why"]
            r["probe_vivant"] = bool(rel["alive"])
            if bras == "livre":
                lignes = [json.loads(x) for x in open(f["log"])] if os.path.exists(f["log"]) else []
                r["journal"] = lignes[-1].get("proof", "-") if lignes else "-"
        except (OSError, ValueError):
            pass
        res[(bras, nom)] = r
for p in procs:
    p.terminate()
for p in procs:
    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        p.kill()

non_mesures = sum(1 for r in res.values() if not r["mesure"])
if "condamne" not in HOOK:
    non_mesures += len(CAS)
pub("supervisor_cases_unmeasured", non_mesures)

def compte(bras, classe):
    return [n for n, cl, _, _ in CAS if cl == classe and res.get((bras, n), {}).get("tampon")]

etr_livre = compte("livre", "autre")
sup_livre = compte("livre", "sup")
manques = [n for n, cl, _, _ in CAS if cl == "sup" and n not in sup_livre]
pub("supervisor_seeded_foreign_stamps", len(etr_livre))
pub("supervisor_seeded_foreign_names", ",".join(etr_livre) or "-")
pub("supervisor_true_stamps", len(sup_livre))
pub("supervisor_missed_true_stamps", len(manques))
pub("supervisor_missed_true_names", ",".join(manques) or "-")
# La preuve lue par le crochet livre est-elle CELLE attendue, cas par cas ?
detail = []
preuve_fausse = 0
for n, cl, attendu, _ in CAS:
    r = res.get(("livre", n), {})
    obtenu = r.get("proof") if r.get("tampon") else r.get("journal", "-")
    ok = obtenu == attendu and (not r.get("tampon") or r.get("pid_session"))
    preuve_fausse += 0 if ok else 1
    detail.append("%s:%s" % (n, obtenu))
pub("supervisor_livre_proofs", ",".join(detail))
pub("supervisor_livre_proof_mismatch", preuve_fausse)

if "condamne" in HOOK:
    etr_cond = compte("condamne", "autre")
    pub("supervisor_condemned_foreign_stamps", len(etr_cond))
    pub("supervisor_condemned_foreign_names", ",".join(etr_cond) or "-")
    pub("supervisor_condemned_true_stamps", len(compte("condamne", "sup")))
    # Le tampon etranger laisse par l'ancien code eteint-il encore l'alarme sous le releve livre ?
    rallume = [n for n in etr_cond if res[("condamne", n)].get("probe_vivant")
               and res[("condamne", n)].get("why_probe") == SA.VIVANT_HORS_REGISTRE]
    pub("supervisor_old_foreign_stamp_keeps_alarm_off", len(rallume))
    pub("supervisor_old_foreign_stamp_probe",
        res[("condamne", "owner-a-la-main")].get("why_probe", "-"))
    controle_positif = 0 if etr_cond else 1
else:
    pub("supervisor_condemned_foreign_stamps", -1)
    controle_positif, rallume = 1, []
pub("supervisor_positive_control_failed", controle_positif)

# ================================================================== 3. APRES : journal reel
live_etr, live_st, live_ref = 0, 0, {}
try:
    with open(SA.SEEN_LOG) as fh:
        for line in fh:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if rec.get("decision") == "tampon":
                live_st += 1
                if rec.get("proof") not in SA.PREUVES:
                    live_etr += 1
            else:
                live_ref[rec.get("proof", "-")] = live_ref.get(rec.get("proof", "-"), 0) + 1
except OSError:
    pass
pub("supervisor_live_stamps", live_st)
pub("supervisor_live_foreign_stamps", live_etr)
pub("supervisor_live_refused", sum(live_ref.values()))
pub("supervisor_live_refused_by_reason",
    ",".join("%s:%d" % kv for kv in sorted(live_ref.items())) or "-")

total = (len(etr_livre) + live_etr + len(manques) + non_mesures + controle_positif
         + preuve_fausse + len(rallume) + sum(defauts.values()))
pub("supervisor_foreign_stamps_denominator", len(CAS) + live_st)
pub("supervisor_foreign_stamps", total)

shutil.rmtree(TMP, ignore_errors=True)
for k in ORDRE:
    v = OUT[k]
    v = "-" if v is None or v == "" else str(v).replace(" ", "_")
    print("%s=%s" % (k, v))
PY
