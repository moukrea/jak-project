#!/usr/bin/env bash
# census/harness-census-fake-backlog-matches-real-api.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `census_fake_api_drift`.
#
# LE DEFAUT (23/09, FINDINGS de quatre workers) : chaque recensement Linear recopiait a la main sa classe `FakeBL`.
# a0d1b96220 a fait passer `apply_owner_move` / `pull_owner` par `Backlog.update` ; les faux de
# `harness-linear-pull-reads-archived-tickets` et `harness-linear-stale-map-never-fakes-an-owner-move` n'avaient pas
# `update` : leur simulation levait, owner_archived_comments_lost=1 et fake_owner_moves=5 — deux acquis rouges sur une
# panne du BANC, 4 controles positifs morts. Correctif : UN faux partage, `lib/census/fake_backlog.py`, qui n'est pas
# une recopie mais la VRAIE classe `Backlog` sur un fichier jetable (+ le vrai module, chemins par defaut rediriges).
#
# CE QU'IL MESURE — `census_fake_api_drift` = somme de :
#   M  membres du backlog que linear_sync UTILISE (lus sur son AST : attributs d'un backlog `bl` / `B.load()`, et `B.x`
#      du module) absents d'un faux : le faux partage (instancie, `hasattr`), chaque classe `Fake(B|BL|Backlog)*` et
#      chaque faux module `X.B = SimpleNamespace(...)` encore ecrits dans un recensement (lus sur l'AST de chaque bloc
#      python de `lib/census/*`). Un `__getattr__` attrape-tout ne FOURNIT rien : il avale l'appel sans l'effet.
#   P  faux PRIVES restants (classe, faux module, ou patch `X.B.load = ...` du vrai module partage), 1 chacun : une
#      recopie de l'API derive au prochain changement, meme complete aujourd'hui.
#   G  les deux gardes nommees par le livrable, rejouees : leur simulation leve ou un de leurs controles est mort, 1
#      chacun (pull en `CENSUS_CONTROLS_ONLY=1` ; stale-map en entier, il n'a pas ce mode).
#   INCONNU = DEFAUT : un terme non mesure compte 1 ; un controle de CE recensement qui ne tient pas compte 1.
# CONTROLES : C+classe = l'ancien FakeBL du recensement pull (sans `update`) doit etre NOMME avec `update` manquant ;
# C+module = `m.B = SimpleNamespace(load=...)` doit nommer `build_sha` ; C+partage = un bac a sable ampute (module
# sans `build_sha`, backlog sans `update`) doit nommer les deux. C- = une classe complete rend 0, et le vrai
# `Backlog` / le vrai module fournissent TOUT ce que linear_sync utilise (sinon l'extraction est fausse).
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "census_fake_api_drift=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import ast, os, re, subprocess, sys, types
from pathlib import Path
sys.path.insert(0, '.autoport')

OUT = {}
def pub(k, v): OUT[k] = str(v).replace(" ", "_")
unmeasured, dead = [], []
CENSUS_DIR = Path(".autoport/lib/census")
SHARED = CENSUS_DIR / "fake_backlog.py"
FAKE_CLASS = re.compile(r"^Fake(B|BL|Backlog)\w*$")

# ======================================================= U : ce que linear_sync UTILISE du backlog ==
def used_members(src):
    """-> (membres utilises sur un objet backlog, membres utilises sur le module B). Un objet backlog = un nom `bl`,
    `B.load(...)`, `_CTX.get("bl")`, un `a or b` qui en contient un, ou un parametre d'une fonction locale qui recoit
    l'un d'eux a un site d'appel (propage jusqu'au point fixe)."""
    tree = ast.parse(src)
    defs = {n.name: n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
    bl_names = {"<module>": {"bl"}}
    per_fn = {name: {"bl"} for name in defs}

    def is_bl(v, names):
        if isinstance(v, ast.Name):
            return v.id in names
        if isinstance(v, ast.Call) and isinstance(v.func, ast.Attribute):
            f = v.func
            if isinstance(f.value, ast.Name) and f.value.id == "B" and f.attr == "load":
                return True
            if f.attr == "get" and v.args and isinstance(v.args[0], ast.Constant) and v.args[0].value == "bl":
                return True
        if isinstance(v, ast.BoolOp):
            return any(is_bl(x, names) for x in v.values)
        return False

    def owner_fn(node, parents):
        p = parents.get(node)
        while p is not None and not isinstance(p, (ast.FunctionDef, ast.AsyncFunctionDef)):
            p = parents.get(p)
        return p.name if p is not None else "<module>"

    parents = {c: n for n in ast.walk(tree) for c in ast.iter_child_nodes(n)}
    changed = True
    while changed:
        changed = False
        for n in ast.walk(tree):
            if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id in defs:
                here = per_fn.get(owner_fn(n, parents), bl_names["<module>"])
                params = [a.arg for a in defs[n.func.id].args.args]
                for i, a in enumerate(n.args):
                    if i < len(params) and is_bl(a, here) and params[i] not in per_fn[n.func.id]:
                        per_fn[n.func.id].add(params[i]); changed = True
                for kw in n.keywords:
                    if kw.arg in params and is_bl(kw.value, here) and kw.arg not in per_fn[n.func.id]:
                        per_fn[n.func.id].add(kw.arg); changed = True
    cls, mod = set(), set()
    for n in ast.walk(tree):
        if isinstance(n, ast.Attribute):
            names = per_fn.get(owner_fn(n, parents), bl_names["<module>"])
            if is_bl(n.value, names):
                cls.add(n.attr)
            if isinstance(n.value, ast.Name) and n.value.id == "B":
                mod.add(n.attr)
    return cls, mod


def real_class_members(B):
    inst = set()
    for n in ast.walk(ast.parse(Path(B.__file__).read_text())):
        if isinstance(n, ast.ClassDef) and n.name == "Backlog":
            for f in n.body:
                if isinstance(f, ast.FunctionDef) and f.name == "__init__":
                    for a in ast.walk(f):
                        if isinstance(a, ast.Attribute) and isinstance(a.value, ast.Name) and a.value.id == "self" \
                                and isinstance(a.ctx, ast.Store):
                            inst.add(a.attr)
    return set(dir(B.Backlog)) | inst


try:
    from lib import backlog as B
    USED_CLS, USED_MOD = used_members(Path(".autoport/linear_sync.py").read_text())
    real_cls = real_class_members(B)
    # un attribut lu sur un backlog qui n'est PAS du backlog (ex. une methode de dict) = extraction fausse ou bogue
    stray_cls = sorted(USED_CLS - real_cls)
    stray_mod = sorted(a for a in USED_MOD if not hasattr(B, a))
    USED_CLS &= real_cls
    pub("census_fake_api_used_class", len(USED_CLS))
    pub("census_fake_api_used_class_list", ",".join(sorted(USED_CLS)))
    pub("census_fake_api_used_module", len(USED_MOD))
    pub("census_fake_api_used_module_list", ",".join(sorted(USED_MOD)))
    pub("census_fake_api_used_stray", ",".join(stray_cls + ["B." + a for a in stray_mod]) or "-")
    if stray_mod:
        dead.append("C-:module_reel_incomplet:" + ",".join(stray_mod))
    if len(USED_CLS) < 3 or len(USED_MOD) < 3:
        unmeasured.append("usage:denominateur_trop_petit")
except Exception as e:  # noqa: BLE001
    unmeasured.append("usage:" + str(e)[:80])
    USED_CLS, USED_MOD = set(), set()
    pub("census_fake_api_used_error", str(e)[:120])

# ======================================================= F : les faux ECRITS dans les recensements ==
HEREDOC = re.compile(r"python3?\s+-\s[^\n]*?<<-?\s*'?(\w+)'?[^\n]*\n(.*?)\n\1[ \t]*$", re.S | re.M)


def python_blocks(path, text):
    if path.suffix == ".py":
        return [(1, text)]
    return [(text.count("\n", 0, m.start(2)) + 1, m.group(2)) for m in HEREDOC.finditer(text)]


def class_members(c):
    got = set()
    for f in c.body:
        if isinstance(f, (ast.FunctionDef, ast.AsyncFunctionDef)) and f.name != "__getattr__":
            got.add(f.name)
        if isinstance(f, ast.Assign):
            got |= {t.id for t in f.targets if isinstance(t, ast.Name)}
    for a in ast.walk(c):
        if isinstance(a, ast.Attribute) and isinstance(a.value, ast.Name) and a.value.id == "self" \
                and isinstance(a.ctx, ast.Store):
            got.add(a.attr)
    return got


def scan_fakes(name, text, suffix=".sh"):
    """-> [(ou, genre, membres manquants)] pour un texte de recensement."""
    out = []
    for line0, block in python_blocks(Path("x" + suffix), text):
        try:
            tree = ast.parse(block)
        except SyntaxError as e:
            if "class Fake" in block or ".B =" in block or ".B.load" in block:
                raise RuntimeError("bloc illisible %s:%d (%s)" % (name, line0, e.msg))
            continue
        for n in ast.walk(tree):
            where = "%s:%d" % (name, line0 + getattr(n, "lineno", 1) - 1)
            if isinstance(n, ast.ClassDef) and FAKE_CLASS.match(n.name):
                out.append((where + ":" + n.name, "classe", sorted(USED_CLS - class_members(n))))
            if isinstance(n, ast.Assign):
                for t in n.targets:
                    if isinstance(t, ast.Attribute) and t.attr == "B" and isinstance(n.value, ast.Call) \
                            and (getattr(n.value.func, "attr", None) or getattr(n.value.func, "id", None)) == "SimpleNamespace":
                        have = {k.arg for k in n.value.keywords}
                        out.append((where + ":B=SimpleNamespace", "module", sorted(USED_MOD - have)))
                    if isinstance(t, ast.Attribute) and isinstance(t.value, ast.Attribute) and t.value.attr == "B":
                        out.append((where + ":B.%s=" % t.attr, "patch_du_vrai_module", []))
    return out


fakes, files, users = [], 0, []
try:
    for p in sorted(CENSUS_DIR.iterdir()):
        if not p.is_file() or p.suffix not in (".sh", ".py") or p == SHARED:
            continue
        files += 1
        t = p.read_text(errors="replace")
        if "fake_backlog" in t:
            users.append(p.stem)
        fakes += scan_fakes(p.name, t, p.suffix)
    pub("census_fake_scan_files", files)
    pub("census_fake_backlog_users", len(users))
    pub("census_fake_backlog_users_list", ",".join(users) or "-")
except Exception as e:  # noqa: BLE001
    unmeasured.append("balayage:" + str(e)[:80])
    pub("census_fake_scan_error", str(e)[:120])
private_missing = sum(len(m) for _w, _k, m in fakes)
pub("census_fake_backlog_private", len(fakes))
pub("census_fake_backlog_private_list", ",".join(w for w, _k, _m in fakes[:6]) or "-")
pub("census_fake_api_private_missing", private_missing)
pub("census_fake_api_private_missing_first",
    ",".join("%s:%s" % (w.split(":")[0], "/".join(m)) for w, _k, m in fakes if m)[:200] or "-")

# ======================================================= S : le faux PARTAGE, instancie ==========
def shared_missing(sb):
    bl = sb.load()
    miss = ["bl." + a for a in sorted(USED_CLS) if not hasattr(bl, a)]
    miss += ["B." + a for a in sorted(USED_MOD) if not hasattr(sb.module, a)]
    return miss


try:
    from lib.census import fake_backlog as FB
    with FB.Sandbox([{"id": "zz-ctl", "status": "open", "owner_feedback": []}]) as sb:
        shared = shared_missing(sb)
        real = isinstance(sb.load(), B.Backlog)
        isolated = os.path.realpath(sb.module.load().path) != os.path.realpath(B.DEFAULT_PATH)
    pub("census_fake_api_shared_missing", len(shared))
    pub("census_fake_api_shared_missing_list", ",".join(shared) or "-")
    pub("census_fake_shared_is_real_class", int(real))
    pub("census_fake_shared_isolated", int(isolated))
    if not real or not isolated:
        dead.append("C-:partage_%s" % ("pas_la_vraie_classe" if not real else "lit_le_vrai_backlog"))
except Exception as e:  # noqa: BLE001
    unmeasured.append("partage:" + str(e)[:80])
    shared = []
    pub("census_fake_shared_error", str(e)[:120])

# ======================================================= CONTROLES de CE recensement ==============
OLD_PULL_FAKE = '''python3 - <<'EOF'
class FakeBL:
    def __init__(self, items):
        self.items, self.path = items, "/dev/null"

    def get(self, i):
        return next((x for x in self.items if x["id"] == i), None)

    def set_status(self, i, status, **f):
        it = self.get(i); it["status"] = status; it.update(f); return it

    def add_owner_feedback(self, i, date, text, via=None):
        self.get(i)["owner_feedback"].append({"date": date, "text": text})
m.B = types.SimpleNamespace(load=lambda: bl)
EOF
'''
try:
    got = scan_fakes("C+", OLD_PULL_FAKE)
    cls_miss = next((m for w, k, m in got if k == "classe"), None)
    mod_miss = next((m for w, k, m in got if k == "module"), None)
    pub("census_fake_ctl_pos_class_named", "/".join(cls_miss or []) or "-")
    pub("census_fake_ctl_pos_module_named", "/".join(mod_miss or [])[:120] or "-")
    if not cls_miss or "update" not in cls_miss:
        dead.append("C+classe:muet")
    if not mod_miss or "build_sha" not in mod_miss:
        dead.append("C+module:muet")
    complete = "python3 - <<'EOF'\nclass FakeBacklog:\n" + "".join(
        "    def %s(self, *a, **k):\n        return None\n" % a for a in sorted(USED_CLS)) + "EOF\n"
    got_neg = scan_fakes("C-", complete)
    pub("census_fake_ctl_neg_missing", sum(len(m) for _w, _k, m in got_neg))
    if len(got_neg) != 1 or got_neg[0][2]:
        dead.append("C-:classe_complete_accusee")
    swallow = "python3 - <<'EOF'\nclass FakeBL:\n    def get(self, i):\n        return None\n" \
              "    def __getattr__(self, n):\n        return lambda *a, **k: None\nEOF\n"
    if "update" not in (scan_fakes("C+", swallow) or [("", "", [])])[0][2]:
        dead.append("C+attrape_tout:muet")
    with FB.Sandbox([]) as sb:
        del sb.module.build_sha
        sb.load = lambda path=None: types.SimpleNamespace(get=lambda i: None, items=[], path=sb.path)
        amputee = shared_missing(sb)
    pub("census_fake_ctl_pos_shared_named", ",".join(amputee) or "-")
    if "B.build_sha" not in amputee or "bl.update" not in amputee:
        dead.append("C+partage:muet")
except Exception as e:  # noqa: BLE001
    dead.append("controles:" + str(e)[:60])
    pub("census_fake_ctl_error", str(e)[:120])

# ======================================================= G : les deux gardes, rejouees =============
GUARDS = {
    "pull": ("harness-linear-pull-reads-archived-tickets", {"CENSUS_CONTROLS_ONLY": "1"},
             ("owner_archived_dead_controls",), ("owner_archived_sim_error",)),
    "stale": ("harness-linear-stale-map-never-fakes-an-owner-move", {},
              ("dead_controls",), ("stale_sim_error",)),
}
guard_defects = []
for tag, (item, env, dead_keys, err_keys) in GUARDS.items():
    try:
        r = subprocess.run(["bash", str(CENSUS_DIR / (item + ".sh"))], capture_output=True, text=True, timeout=300,
                           env=dict(os.environ, **env))
        kv = dict(l.split("=", 1) for l in r.stdout.splitlines() if "=" in l)
        dk = [kv.get(k) for k in dead_keys]
        errs = [kv[k] for k in err_keys if k in kv]
        pub("census_fake_guard_%s_dead_controls" % tag, ",".join(str(x) for x in dk))
        pub("census_fake_guard_%s_sim_error" % tag, (errs[0] if errs else "-")[:100])
        if any(x is None for x in dk):
            unmeasured.append("garde_%s:cle_absente" % tag)
            continue
        n = sum(int(x) for x in dk) + len(errs)
        if n:
            guard_defects.append("%s:%d" % (tag, n))
    except Exception as e:  # noqa: BLE001
        unmeasured.append("garde_%s:%s" % (tag, str(e)[:60]))
pub("census_fake_guard_defects", len(guard_defects))
pub("census_fake_guard_defects_list", ",".join(guard_defects) or "-")

drift = len(shared) + private_missing + len(fakes) + len(guard_defects) + len(unmeasured) + len(dead)
pub("census_fake_unmeasured", len(unmeasured))
pub("census_fake_unmeasured_list", ",".join(unmeasured) or "-")
pub("census_fake_dead_controls", len(dead))
pub("census_fake_dead_controls_list", ",".join(dead) or "-")
pub("census_fake_api_drift", drift)
for k, v in OUT.items():
    print("%s=%s" % (k, v))
PY
