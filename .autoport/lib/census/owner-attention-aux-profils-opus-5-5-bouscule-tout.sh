#!/usr/bin/env bash
# census/owner-attention-aux-profils-opus-5-5-bouscule-tout.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `banned_model_paths`.
# Rien n'est ecrit dans le vrai arbre : chaque controle tourne sur une copie jetable (tmp/proj).
#
# LE DEFAUT (owner, 23/09, JAK-265) : « Claude Opus 5 est a bannir, Fable 5.1 aussi [...] faut etre
# surs que rien ne tourne ni sous Opus 5, ni sous Fable 5.1 ». Releve du jour : supervisor.sh repliait
# EN DUR sur claude-opus-5 (superviseur ET sous-agents), orchestrator.py gardait un repli
# claude-fable-5-1[1m], 6 profils sur 7 nommaient l'un ou l'autre.
#
# CE QU'IL MESURE — `banned_model_paths` = somme de :
#   R  REEL : `lib/model_ban.py` sur le vrai arbre (profils, essais croises, code du harnais, frontmatter
#      des sous-agents, settings lus par la CLI, FORCE des sous-agents, porte de lancement, processus
#      `claude` vivants). Chaque chemin est NOMME dans `banned_model_path_list`.
#   N  CONTROLE NEGATIF : la copie intacte doit rendre 0 (sinon le banc lui-meme ment).
#   C  CONTROLES POSITIFS, chacun sur sa copie ; un controle qui ne rougit pas compte 1 :
#      c1 supervisor.sh + repli `claude-opus-5` (celui du contrat) -> nomme supervisor.sh
#      c2 profil actif manager_model=claude-opus-5 -> lint `profile` + supervisor-env REFUSE
#         + supervisor.sh (DRYRUN) REFUSE + orchestrateur REFUSE a la frontiere d'item
#      c3 supervisor_model=claude-fable-5-1 -> supervisor.sh (DRYRUN) REFUSE
#      c4 bras d'essai croise worker_model=claude-opus-5 -> lint `trial` + orchestrateur REFUSE
#      c5 frontmatter `model: fable` -> lint `agent`
#      c6 FORCE retire de supervisor.sh -> lint `subagent-force`
#      c7 ancien repli Fable remis dans orchestrator.py -> lint `code` sur orchestrator.py
#      c8 settings `model: claude-fable-5-1` -> lint `settings`
#      c9 supervisor.sh declare « donnees » + litteral banni -> TOUJOURS compte (il lance une CLI)
#      c10 bannissement retire de model_profile.resolve -> lint `launch-gate`
#   U  INCONNU = DEFAUT : un terme qui plante compte 1.
# Informatif : ce que supervisor.sh lancerait vraiment (DRYRUN), le rapport `autoport cost --modeles`.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "banned_model_paths=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import json, os, re, shutil, subprocess, sys, tempfile
ROOT = os.getcwd()
AP = os.path.join(ROOT, ".autoport")
sys.path.insert(0, os.path.join(AP, "lib"))
OUT, dead, unmeasured = {}, [], []
def pub(k, v): OUT[k] = str(v).replace(" ", "_")
BANNED = "claude-opus-5"

# ------------------------------------------------------------------ R : le vrai arbre
real = []
try:
    import model_ban
    real = model_ban.scan(ROOT)
    pub("banned_model_paths_real", len(real))
    pub("banned_model_path_list", ",".join(f"{f['kind']}:{f['where']}" for f in real[:12]) or "aucun")
    kinds = {}
    for f in real:
        kinds[f["kind"]] = kinds.get(f["kind"], 0) + 1
    for k in ("profile", "trial", "codex-profile", "code", "agent", "settings", "subagent-force",
              "launch-gate", "process", "unreadable"):
        pub(f"banned_paths_{k.replace('-', '_')}", kinds.get(k, 0))
    files = list(model_ban.harness_code_files(__import__("pathlib").Path(ROOT)))
    pub("banned_scan_code_files", len(files))
    cfg = json.load(open(os.path.join(AP, "model-profiles.json")))
    pub("banned_ids", "+".join(cfg["banned_models"]["ids"]))
    pub("profiles_selectable", len(cfg.get("profiles") or {}))
    pub("profiles_retired", len([k for k in (cfg.get("retired_profiles") or {}) if not k.startswith("_")]))
except Exception as e:  # noqa: BLE001
    unmeasured.append("real"); print(f"# R a plante : {e!r}", file=sys.stderr)

# ------------------------------------------------------------------ copies jetables
COPY = [".autoport/model-profiles.json", ".autoport/supervisor.sh", ".autoport/orchestrator.py",
        ".autoport/SUPERVISOR_PROMPT.md", ".autoport/lib/model_profile.py", ".autoport/lib/model_ban.py",
        ".autoport/lib/cli_backend.py"]
COPY += [os.path.relpath(os.path.join(ROOT, ".claude", "agents", f), ROOT)
         for f in sorted(os.listdir(os.path.join(ROOT, ".claude", "agents"))) if f.endswith(".md")]

def world(tag):
    tmp = tempfile.mkdtemp(prefix=f"ban-census-{tag}-")
    root = os.path.join(tmp, "proj")
    for rel in COPY:
        dst = os.path.join(root, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(os.path.join(ROOT, rel), dst)
    home = os.path.join(tmp, "home")
    os.makedirs(os.path.join(home, ".claude"))
    return tmp, root, home

def lint(root, home):
    r = subprocess.run([sys.executable, os.path.join(root, ".autoport/lib/model_ban.py"), "--root", root,
                        "--home", home, "--no-processes", "--json"], capture_output=True, text=True, timeout=120)
    return json.loads(r.stdout)["paths"]

def edit(root, rel, fn):
    p = os.path.join(root, rel)
    s = open(p, encoding="utf-8").read()
    t = fn(s)
    if t == s:
        raise RuntimeError(f"graine sans effet dans {rel}")
    open(p, "w", encoding="utf-8").write(t)

def cfg_edit(root, fn):
    p = os.path.join(root, ".autoport/model-profiles.json")
    d = json.load(open(p)); fn(d); open(p, "w").write(json.dumps(d, indent=2))

def sup_dry(root):
    env = dict(os.environ, AUTOPORT_SUPERVISOR_DRYRUN="1", AUTOPORT_BACKEND="claude")
    env.pop("SUP_MODEL", None); env.pop("SUB_MODEL", None)
    r = subprocess.run(["bash", os.path.join(root, ".autoport/supervisor.sh"), "--check"], cwd=root,
                       env=env, capture_output=True, text=True, timeout=60)
    return r.returncode, r.stdout + r.stderr

def sup_env(root):
    r = subprocess.run([sys.executable, os.path.join(root, ".autoport/lib/model_profile.py"), "supervisor-env",
                        "--file", os.path.join(root, ".autoport/model-profiles.json")],
                       capture_output=True, text=True, timeout=60)
    return r.returncode

def orch_refuses(root, item):
    """L'orchestrateur REEL, pointe sur le profil de la copie : doit lever a la frontiere d'item."""
    import importlib, pathlib
    sys.path.insert(0, AP)
    o = importlib.import_module("orchestrator")
    saved = (o._PROFILE_PATH, o.BACKEND)
    try:
        o._PROFILE_PATH = pathlib.Path(root, ".autoport/model-profiles.json"); o.BACKEND = "claude"
        try:
            o._profile_at_item_boundary(item)
            return False
        except ValueError:
            return True
    finally:
        o._PROFILE_PATH, o.BACKEND = saved

def has(paths, kind, where_prefix=""):
    return [p for p in paths if p["kind"] == kind and p["where"].startswith(where_prefix)]

controls = {}
def control(name, fn):
    tmp = None
    try:
        tmp, root, home = world(name)
        ok, detail = fn(root, home)
        controls[name] = ok
        pub(f"ctl_{name}", 1 if ok else 0)
        if detail is not None:
            pub(f"ctl_{name}_detail", detail)
        if not ok:
            dead.append(name)
    except Exception as e:  # noqa: BLE001
        unmeasured.append(name); pub(f"ctl_{name}", "plante")
        print(f"# controle {name} a plante : {e!r}", file=sys.stderr)
    finally:
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)

# N — la copie intacte rend 0, et supervisor.sh (DRYRUN) y part sur le profil
def neg(root, home):
    p = lint(root, home)
    rc, out = sup_dry(root)
    pub("neg_copy_paths", len(p))
    return (len(p) == 0 and rc == 0 and "DRYRUN" in out), ",".join(f"{x['kind']}:{x['where']}" for x in p) or None
control("neg", neg)
if "neg" in dead:
    dead.remove("neg"); unmeasured.append("neg-copie-non-nulle")

# c1 — le controle du contrat : claude-opus-5 pose dans une copie de supervisor.sh
def c1(root, home):
    edit(root, ".autoport/supervisor.sh",
         lambda s: s.replace("exec claude \\\n", f'SUP_MODEL="${{SUP_MODEL:-{BANNED}}}"\nexec claude \\\n', 1))
    h = has(lint(root, home), "code", ".autoport/supervisor.sh:")
    return bool(h), (h[0]["where"] if h else "aucun")
control("c1_supervisor_literal", c1)

def c2(root, home):
    cfg_edit(root, lambda d: d["profiles"][d["active"]].__setitem__("manager_model", BANNED))
    l = bool(has(lint(root, home), "profile"))
    e = sup_env(root) != 0
    rc, out = sup_dry(root)
    s = rc != 0 and "DRYRUN" not in out
    o = orch_refuses(root, {"id": "x", "code_scope": "jeu"})
    return (l and e and s and o), f"lint={int(l)}/env={int(e)}/supervisor={int(s)}/orchestrateur={int(o)}"
control("c2_active_profile", c2)

def c3(root, home):
    cfg_edit(root, lambda d: d["profiles"][d["active"]].__setitem__("supervisor_model", "claude-fable-5-1"))
    rc, out = sup_dry(root)
    return (rc != 0 and "DRYRUN" not in out and "BANNI" in out), f"rc={rc}"
control("c3_supervisor_model", c3)

def c4(root, home):
    def f(d):
        t = d["trials"]["subagent-model"]; t["active"] = True
        for arm in t["arms"].values():
            arm["worker_model"] = BANNED
    cfg_edit(root, f)
    l = bool(has(lint(root, home), "trial"))
    o = orch_refuses(root, {"id": "harness-x", "code_scope": "harnais"})
    return (l and o), f"lint={int(l)}/orchestrateur={int(o)}"
control("c4_trial_arm", c4)

def c5(root, home):
    edit(root, ".claude/agents/autoport-researcher.md",
         lambda s: s.replace("\neffort:", "\nmodel: fable\neffort:", 1))
    return bool(has(lint(root, home), "agent")), None
control("c5_agent_frontmatter", c5)

def c6(root, home):
    edit(root, ".autoport/supervisor.sh", lambda s: s.replace("export CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1\n", "", 1))
    return bool(has(lint(root, home), "subagent-force", ".autoport/supervisor.sh")), None
control("c6_force_removed", c6)

def c7(root, home):
    edit(root, ".autoport/orchestrator.py",
         lambda s: s.replace('"manager_model": "", "manager_effort": "", "worker_model": "",',
                             '"manager_model": "claude-fable-5-1[1m]", "manager_effort": "high", '
                             '"worker_model": "claude-fable-5-1[1m]",', 1))
    h = has(lint(root, home), "code", ".autoport/orchestrator.py:")
    return len(h) >= 2, f"{len(h)}_litteraux"
control("c7_orchestrator_fallback", c7)

def c8(root, home):
    open(os.path.join(home, ".claude", "settings.json"), "w").write(json.dumps({"model": "claude-fable-5-1"}))
    return bool(has(lint(root, home), "settings")), None
control("c8_settings", c8)

def c9(root, home):
    cfg_edit(root, lambda d: d["banned_models"].setdefault("data_only", {}).__setitem__(
        ".autoport/supervisor.sh", "controle"))
    edit(root, ".autoport/supervisor.sh",
         lambda s: s.replace("exec claude \\\n", f'SUB_MODEL="${{SUB_MODEL:-{BANNED}}}"\nexec claude \\\n', 1))
    return bool(has(lint(root, home), "code", ".autoport/supervisor.sh:")), None
control("c9_data_only_cannot_hide_a_launcher", c9)

def c10(root, home):
    edit(root, ".autoport/lib/model_profile.py", lambda s: s.replace("    if hits:\n", "    if False and hits:\n", 1))
    return bool(has(lint(root, home), "launch-gate")), None
control("c10_launch_gate_removed", c10)

pub("controls_total", len(controls))
pub("controls_alive", sum(1 for v in controls.values() if v))
pub("controls_dead", len(dead))
pub("controls_dead_list", ",".join(dead) or "aucun")
pub("banned_terms_unmeasured", len(unmeasured))
pub("banned_terms_unmeasured_list", ",".join(unmeasured) or "aucun")

# ------------------------------------------------------------------ informatif
try:
    env = dict(os.environ, AUTOPORT_SUPERVISOR_DRYRUN="1", AUTOPORT_BACKEND="claude")
    r = subprocess.run(["bash", os.path.join(AP, "supervisor.sh"), "--check"], cwd=ROOT, env=env,
                       capture_output=True, text=True, timeout=60)
    m = re.search(r"DRYRUN model=(\S+) effort=(\S+) workers=(\S+) force=(\S+)", r.stdout)
    pub("supervisor_launch_rc", r.returncode)
    if m:
        pub("supervisor_launch_model", m.group(1)); pub("supervisor_launch_effort", m.group(2))
        pub("supervisor_launch_workers", m.group(3)); pub("supervisor_launch_force", m.group(4))
except Exception as e:  # noqa: BLE001
    pub("supervisor_launch_rc", "plante")
try:
    r = subprocess.run([sys.executable, os.path.join(AP, "lib", "model_cost_report.py"), "--json"],
                       capture_output=True, text=True, timeout=120)
    rep = json.loads(r.stdout)
    pub("model_cost_report_rc", r.returncode)
    pub("model_cost_alerts", len(rep.get("alerts") or []))
    pub("banned_model_attempts_7d", rep.get("banned_model_attempts", "?"))
    pub("model_cost_attempts_read", rep.get("attempts_read", "?"))
    arms = [f"{t}:{a}" for t, v in (rep.get("trials") or {}).items() if isinstance(v, dict)
            for a in (v.get("arms") or v)]
    pub("trial_arms_published", len(arms))
except Exception as e:  # noqa: BLE001
    pub("model_cost_report_rc", "plante"); print(f"# rapport de cout : {e!r}", file=sys.stderr)

OUT["banned_model_paths"] = str(len(real) + len(dead) + len(unmeasured))
for k, v in OUT.items():
    print(f"{k}={v}")
PY
