#!/usr/bin/env bash
# census/harness-archived-census-controls-are-alive.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `archived_census_dead_controls`.
#
# LE DEFAUT (23/09, FINDINGS de quatre workers) : les deux garde-fous de lecture des tickets archives ne pouvaient
# plus rougir juste.
#   * `harness-linear-pull-reads-archived-tickets` semait son controle C+_statique par REMPLACEMENT D'UNE LIGNE
#     (`    return on_ticket(L, issue_id, ...`) ; ef3327822c a reecrit la ligne en `r = on_ticket(...)` : la graine
#     ne prenait plus, le controle etait MORT. Il est seme desormais sur l'ARBRE (appel `on_ticket` du corps de
#     `post_comment`, `unguard`).
#   * `harness-linear-census-reads-archived-tickets` accusait la cle de repartition d'un FAUX Linear
#     (relink-keeps-owner-comments.sh:186, un litteral compare par `in`) comme une lecture aveugle : faux positif.
#
# CE QU'IL MESURE — `archived_census_dead_controls` = somme de :
#   D  les controles que les deux recensements declarent MORTS, rejoues en `CENSUS_CONTROLS_ONLY=1` (sans Linear).
#   F  les faux positifs : cles de repartition (litteral de requete, operande GAUCHE d'un `in`, lues ici sur l'AST,
#      independamment du classifieur accuse) que le recensement des lectures range parmi les sites aveugles.
#   G  les graines de controle sur un LITTERAL DE LIGNE, dans TOUS les recensements (`lib/census/*`, blocs python) :
#      `x.replace(ANCIEN, ...)` et paires `(ANCIEN, NOUVEAU)` dont ANCIEN (du code) n'est plus dans aucune des
#      cibles que le bloc nomme. Une graine morte = un controle qui ne seme plus rien.
#   INCONNU = DEFAUT : un terme non mesure compte 1 ; un controle de CE recensement qui ne tient pas compte 1.
# CONTROLES : C+ = le defaut VIVANT, relu au commit epingle BEFORE (dernier commit avant le correctif) — sa graine
# litterale est MORTE et nommee (G), son classifieur rend le faux positif relink:186 (F), son C+_statique se
# declare mort (D). C- = une graine synthetique dont l'ancien texte est dans sa cible : vivante, 0.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "archived_census_dead_controls=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import ast, os, re, subprocess
from pathlib import Path

OUT = {}
def pub(k, v): OUT[k] = str(v).replace(" ", "_")
unmeasured = []    # termes non mesures (1 chacun)
own_dead = []      # controles de CE recensement qui ne tiennent pas (1 chacun)
BEFORE = "4a3b98c710"   # HEAD avant le correctif : les deux defauts y vivent (publie, jamais relu a HEAD)
PULL = ".autoport/lib/census/harness-linear-pull-reads-archived-tickets.sh"
CRA = ".autoport/lib/census/harness-linear-census-reads-archived-tickets.sh"
TRACKED = set(subprocess.run(["git", "ls-files"], capture_output=True, text=True).stdout.split())
pub("acc_before_commit", BEFORE)

# ============================================================================ outils : blocs python ==
OPEN = re.compile(r"python3?\b[^\n]*<<-?\s*(['\"]?)(\w+)\1")


def py_blocks(name, text):
    """-> [(ligne du fichier qui precede le bloc, code, heredoc quote)]. Un `.py` est un bloc ; un `.sh` en porte un par heredoc
    python, avec ce que le shell en fait (`parse`)."""
    if name.endswith(".py"):
        return [(0, text, True)]
    out, lines, i = [], text.splitlines(), 0
    while i < len(lines):
        m = OPEN.search(lines[i])
        if m and not lines[i].lstrip().startswith("#"):
            j = i + 1
            while j < len(lines) and lines[j].strip() != m.group(2):
                j += 1
            out.append((i + 1, "\n".join(lines[i + 1:j]), bool(m.group(1))))
            i = j
        i += 1
    return out


def parse(code, quoted):
    try:
        return ast.parse(code)
    except SyntaxError:
        if quoted:
            return None
    try:   # heredoc non quote : chaque `$X` / `${..}` / `$(..)` est une valeur que le shell pose -> `0`
        code = re.sub(r"(?<!\\)\$(\{[^}]*\}|\([^)]*\)|\w+)", "0", code.replace("\\\n", ""))
        return ast.parse(re.sub(r"\\([\\$`])", r"\1", code))
    except SyntaxError:
        return None


def fold(n, env):
    """Valeur d'une chaine constante : litteral, nom de module lie a une constante, somme de ces deux."""
    if isinstance(n, ast.Constant) and isinstance(n.value, str):
        return n.value
    if isinstance(n, ast.Name):
        return env.get(n.id)
    if isinstance(n, ast.BinOp) and isinstance(n.op, ast.Add):
        a, b = fold(n.left, env), fold(n.right, env)
        return a + b if a is not None and b is not None else None
    return None


def module_env(tree):
    env = {}
    for s in tree.body:
        if isinstance(s, ast.Assign) and len(s.targets) == 1 and isinstance(s.targets[0], ast.Name):
            v = fold(s.value, env)
            if v is not None:
                env[s.targets[0].id] = v
    return env


# ======================================================== G : graines sur un litteral de ligne ==
CODE = re.compile(r"[(){}=:\[]|^\s|^(def|class) ")


def literal_seeds(name, text, read=lambda p: Path(p).read_text(errors="replace")):
    """-> (graines, blocs lus, blocs illisibles). Graine = `x.replace(ANCIEN, NOUVEAU)` ou paire `(ANCIEN, NOUVEAU)`
    d'une liste/d'un ensemble, ANCIEN etant du CODE (8 signes utiles au moins). Vivante si ANCIEN est dans une cible
    que le bloc NOMME (fichier suivi par git), ou fabrique par le bloc lui-meme (sous-chaine d'une autre constante) ;
    sans cible nommee, l'arbre suivi entier fait foi."""
    seeds, nb, bad = [], 0, []
    for off, code, quoted in py_blocks(name, text):
        tree = parse(code, quoted)
        if tree is None:
            if ".replace(" in code:
                bad.append("%s:%d" % (name, off))
            continue
        nb += 1
        env = module_env(tree)
        consts = [n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, str)]
        targets = sorted({c2 for c in consts for c2 in (c, ".autoport/" + c) if c2 in TRACKED and c2 != name})
        found = []
        for n in ast.walk(tree):
            if (isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr == "replace"
                    and len(n.args) >= 2):
                old, new = fold(n.args[0], env), fold(n.args[1], env)
                found.append((n.lineno, old, new))
            elif isinstance(n, (ast.List, ast.Set)):
                for e in n.elts:
                    if isinstance(e, ast.Tuple) and len(e.elts) == 2:
                        found.append((e.lineno, fold(e.elts[0], env), fold(e.elts[1], env)))
        for ln, old, new in found:
            if old is None or new is None or old == new or len(old.strip()) < 8 or not CODE.search(old):
                continue
            how = next(("cible:" + t.split("/")[-1] for t in targets if old in read(t)), "")
            if not how and any(old in c for c in consts if c != old):
                how = "interne"
            if not how and not targets:
                first = old.strip().splitlines()[0]
                hits = subprocess.run(["git", "grep", "-lF", "--", first], capture_output=True, text=True).stdout.split()
                how = "arbre" if any(h != name and old in read(h) for h in hits) else ""
            seeds.append({"where": "%s:%d" % (name.split("/")[-1], off + ln), "old": old, "alive": how or "-"})
    return seeds, nb, bad


census = sorted(f for f in TRACKED if f.startswith(".autoport/lib/census/") and f.endswith((".sh", ".py")))
G, nblocks, unparsed = [], 0, []
for f in census:
    s, nb, bad = literal_seeds(f, Path(f).read_text(errors="replace"))
    G += s
    nblocks += nb
    unparsed += bad
g_dead = [s for s in G if s["alive"] == "-"]
pub("acc_census_files", len(census))
pub("acc_py_blocks", nblocks)
pub("acc_py_blocks_unparsed", ",".join(unparsed) or "-")
pub("acc_literal_seeds", len(G))
pub("acc_literal_seeds_alive", len(G) - len(g_dead))
pub("acc_literal_seeds_by", ",".join(sorted({s["alive"].split(":")[0] for s in G})) or "-")
pub("acc_literal_seeds_list", ",".join(s["where"] for s in G) or "-")
pub("acc_literal_seeds_dead", len(g_dead))
pub("acc_literal_seeds_dead_list", ",".join(s["where"] for s in g_dead) or "-")
unmeasured += ["G_illisible:" + b for b in unparsed]

# C- : une graine dont l'ancien texte est dans sa cible nommee est vivante
healthy = ('python3 - <<\'PY\'\nfrom pathlib import Path\nSRC = Path(".autoport/linear_sync.py").read_text()\n'
           'x = SRC.replace("def post_comment(L, issue_id", "def post_comment_(L, issue_id")\nPY\n')
hs, _, _ = literal_seeds(".autoport/lib/census/sain.sh", healthy)
pub("acc_ctl_seed_healthy", ",".join("%s=%s" % (s["where"], s["alive"]) for s in hs) or "-")
if len(hs) != 1 or hs[0]["alive"] == "-":
    own_dead.append("C-_graine_saine")

# C+ : la graine du recensement « pull » AVANT le correctif est morte et NOMMEE
old_pull = subprocess.run(["git", "show", "%s:%s" % (BEFORE, PULL)], capture_output=True, text=True).stdout
old_cra = subprocess.run(["git", "show", "%s:%s" % (BEFORE, CRA)], capture_output=True, text=True).stdout
if not old_pull or not old_cra:
    own_dead.append("C+_avant_introuvable")
else:
    bs, _, _ = literal_seeds(PULL, old_pull)
    bd = [s for s in bs if s["alive"] == "-"]
    pub("acc_ctl_before_seed_dead", ",".join(s["where"] for s in bd) or "-")
    if not any(s["old"].lstrip().startswith("return on_ticket(L, issue_id") for s in bd):
        own_dead.append("C+_graine_litterale")


# ============================================================== D : controles declares morts ==
def kv_of(stdout):
    return dict(l.split("=", 1) for l in stdout.splitlines() if "=" in l)


def run_census(path):
    r = subprocess.run(["bash", path], capture_output=True, text=True, timeout=300,
                       env=dict(os.environ, CENSUS_CONTROLS_ONLY="1"))
    return kv_of(r.stdout)


def names(v):
    return [] if v in (None, "", "-") else v.split(",")


pull = run_census(PULL)
cra = run_census(CRA)
d_pull = names(pull.get("owner_archived_dead_controls_list"))
d_cra = names(cra.get("linear_archived_controls_dead"))
for key, kv, tag in (("owner_archived_dead_controls_list", pull, "D_pull"), ("linear_archived_controls_dead", cra, "D_census"),
                     ("linear_archived_write_ctl_pos_seeded", pull, "D_pull_graine"), ("linear_ctl_dispatch_sent", cra, "D_census_cle"),
                     ("linear_read_sites_blind_list", cra, "F_liste")):
    if key not in kv:
        unmeasured.append(tag)
pub("acc_pull_controls_live", pull.get("owner_archived_live", "?"))
pub("acc_pull_ctl_pos_seeded", pull.get("linear_archived_write_ctl_pos_seeded", "-"))
pub("acc_pull_ctl_pos_named", pull.get("linear_archived_write_ctl_pos", "-"))
pub("acc_pull_dead", len(d_pull))
pub("acc_pull_dead_list", ",".join(d_pull) or "-")
pub("acc_census_controls_live", cra.get("linear_live", "?"))
pub("acc_census_dead", len(d_cra))
pub("acc_census_dead_list", ",".join(d_cra) or "-")


# ===================================================================== F : faux positifs ==
SITE = re.compile(r"\{\s*(issues|searchIssues|issueSearch)\s*[({]")


def dispatch_keys():
    """Cles de repartition, sur l AST : `"<requete>" in x`. -> {"lib/census/x.sh:186", ...}"""
    out = set()
    files = [f for f in TRACKED if f.startswith(".autoport/") and f.endswith((".py", ".sh", ".bash"))
             and not re.match(r"\.autoport/(archive|reports|logs|owner-feedback)/", f)]
    for f in files:
        try:
            text = Path(f).read_text(errors="replace")
        except OSError:
            continue
        if not SITE.search(text):
            continue
        for off, code, quoted in py_blocks(f, text):
            tree = parse(code, quoted)
            for n in ast.walk(tree) if tree else ():
                if (isinstance(n, ast.Compare) and any(isinstance(o, (ast.In, ast.NotIn)) for o in n.ops)
                        and SITE.search(fold(n.left, {}) or "")):
                    out.add("%s:%d" % (f.replace(".autoport/", ""), off + n.lineno))
    return out


def false_pos(blind_list, keys):
    return sorted({":".join(w.split(":")[:2]) for w in names(blind_list)} & keys)


KEYS = dispatch_keys()
fp = false_pos(cra.get("linear_read_sites_blind_list"), KEYS)
pub("acc_dispatch_keys", len(KEYS))
pub("acc_dispatch_keys_list", ",".join(sorted(KEYS)) or "-")
pub("acc_census_dispatch_excluded", cra.get("linear_read_sites_dispatch", "-"))
pub("acc_false_positives", len(fp))
pub("acc_false_positives_list", ",".join(fp) or "-")


# C+ D et F : les deux recensements AVANT le correctif, leurs seules parties hors Linear, rejouees sur l'arbre d'aujourd'hui
def heredoc(text):
    lines = text.splitlines()
    k = next(i for i, l in enumerate(lines) if OPEN.search(l))
    return lines[k + 1:]


def run_code(code):
    r = subprocess.run(["python3", "-"], input=code, capture_output=True, text=True, timeout=300)
    return kv_of(r.stdout)


PRINT = "\nfor k_, v in OUT.items():\n    print('%s=%s' % (k_, v))\nprint('DEAD=' + (','.join(dead) or '-'))\n"
try:
    b = heredoc(old_cra)
    cut = next(i for i, l in enumerate(b) if "L : VIVANT" in l)
    kv = run_code("\n".join(b[:cut]) + PRINT)
    bfp = false_pos(kv.get("linear_read_sites_blind_list"), KEYS)
    pub("acc_ctl_before_false_positives", ",".join(bfp) or "-")
    if not any(w.startswith("lib/census/harness-linear-relink-keeps-owner-comments.sh:") for w in bfp):
        own_dead.append("C+_faux_positif")
    b = heredoc(old_pull)
    h = next(i for i, l in enumerate(b) if "VIVANT (Linear)" in l)
    s = next(i for i, l in enumerate(b) if "LIVRABLE 2" in l)
    e = next(i for i in range(s, len(b)) if b[i].startswith('pub("owner_archived_unmeasured"'))
    kv = run_code("\n".join(b[:h] + b[s:e]) + PRINT)
    bd = names(kv.get("DEAD"))
    pub("acc_ctl_before_dead", ",".join(bd) or "-")
    if "C+_statique" not in bd:
        own_dead.append("C+_controle_mort")
except (StopIteration, subprocess.TimeoutExpired) as ex:
    own_dead.append("C+_avant_illisible:" + type(ex).__name__)

pub("acc_unmeasured", ",".join(unmeasured) or "-")
pub("acc_own_controls_dead", ",".join(own_dead) or "-")
total = len(d_pull) + len(d_cra) + len(fp) + len(g_dead) + len(unmeasured) + len(own_dead)
pub("archived_census_dead_controls", total)
for k_, v in OUT.items():
    print("%s=%s" % (k_, v))
PY
