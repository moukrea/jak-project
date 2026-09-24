#!/usr/bin/env bash
# census/harness-census-seeds-anchored-structurally.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `census_literal_anchors`.
#
# LE DEFAUT (23/09, FINDINGS de harness-archived-census-controls-are-alive) : les recensements semaient leurs
# controles et localisaient le code par une LIGNE EXACTE (`src.replace("    return on_ticket(L, issue_id", ...)`,
# `'u_pbr_mode & 16' in ligne`, `grep -c 'return autoport_proof::armed\(\) \? 1 : 0;'`). La premiere reecriture de
# la ligne tue le controle ; et une ancre qui vise un code RETIRE (`pbr_coverage_note_draw(`) rend « introuvable »
# a chaque course sans que personne sache si c'est voulu.
#
# CE QU'IL MESURE, sur TOUS les recensements suivis (`lib/census/*.sh|*.py`, blocs python ET lignes shell) :
#   GRAINE  une mutation d'une source : `x.replace(ANCIEN, ..)`, paire `(ANCIEN, NOUVEAU)`, `sed -i s/ANCIEN/..`.
#   ANCRE   un localisateur : aiguille cherchee dans un texte LU D'UNE SOURCE (`A in src`, `src.index(A)`,
#           `re.search(A, src)`, `grep A <source>`, `sed -n /A/,/B/p <source>`).
#   Chacune est classee :
#     ligne      son texte depend de la MISE EN PAGE (blanc entre deux signes, retour a la ligne, indentation) ;
#     morte      l'aiguille (ou l'ANCIEN d'une graine) n'est plus dans aucune source suivie ;
#     fragment   symbole ou fragment sans blanc, vivant : structurel, non compte ;
#     interne    graine sur un texte que le bloc fabrique lui-meme (faux Linear, fixture) : non compte.
#   Les appels de `lib/census/anchor.py` (noeud d'arbre python, suite de jetons) sont STRUCTURELS ; leurs symboles
#   (`func=`, jetons) doivent exister dans l'arbre suivi, sinon ils sont `morte`.
#   census_literal_anchors = graines ligne + graines mortes + ancres ligne + ancres mortes + structurelles mortes
#                           + blocs illisibles + controles de CE recensement qui ne tiennent pas.
# CONTROLES :
#   C+_detecteur  un recensement synthetique aux trois defauts (graine ligne, ancre morte, grep ligne) : 3 comptes.
#   C-_detecteur  le meme, ancre par `anchor.py` et aiguilles sur des SORTIES : 0.
#   C+_reecriture la ligne visee par une graine re-ancree est REECRITE dans une copie jetable de linear_sync.py :
#                 la graine structurelle prend encore (1 noeud), la graine litterale d'avant n'y prend plus (0) ;
#                 puis le controle C+ du recensement `pull` rejoue dans la copie ROUGIT encore (non mort).
#   C-_reecriture la meme copie SANS reecriture : les deux prennent.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "census_literal_anchors=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import ast, os, re, shlex, shutil, subprocess, sys, tempfile
from pathlib import Path
sys.path.insert(0, ".autoport/lib/census")
import anchor as A

OUT = {}
def pub(k, v): OUT[k] = str(v).replace(" ", "_").replace("\n", "_")
unmeasured, own_dead = [], []
ME = ".autoport/lib/census/harness-census-seeds-anchored-structurally.sh"
TRACKED = set(subprocess.run(["git", "ls-files"], capture_output=True, text=True).stdout.split())
EXT = (".py", ".sh", ".bash", ".cpp", ".h", ".hpp", ".c", ".cc", ".glsl", ".frag", ".vert", ".gc", ".gd", ".gs",
       ".cmake", ".txt", ".gradle", ".kts", ".java", ".kt", ".json")
NOT_CODE = re.compile(r"^\.autoport/(reports|archive|logs|owner-feedback|prompts|plans)/|\.md$|backlog\.yaml$")
CODE = sorted(f for f in TRACKED if f.endswith(EXT) and not NOT_CODE.search(f) and "third-party/" not in f
              and not f.startswith(("test/", "decompiler/config/", "goal_src/jak2", "goal_src/jak3")))
CODESET = set(CODE)
_cache = {}


def read(p):
    if p not in _cache:
        try:
            _cache[p] = Path(p).read_text(errors="replace")
        except OSError:
            _cache[p] = ""
    return _cache[p]


def is_path(v):
    return isinstance(v, str) and (v in CODESET or ".autoport/" + v in CODESET)


def in_code(needle, exclude=()):
    """Fichiers de code suivis qui portent `needle` (texte exact), hors `exclude`."""
    first = max(needle.splitlines() or [needle], key=len).strip()
    if len(first) < 3:
        return []
    hits = subprocess.run(["git", "grep", "-lF", "--", first], capture_output=True, text=True).stdout.split()
    return [h for h in hits if h in CODESET and h not in exclude and not h.startswith(".autoport/lib/census/")
            and needle in read(h)]


PINS = {}


def pins_of(name):
    """Commits EPINGLES que le recensement nomme (sha de 10 a 40 signes, existant)."""
    if name not in PINS:
        shas = set(re.findall(r"\b[0-9a-f]{10,40}\b", read(name)))
        PINS[name] = sorted(x for x in shas if subprocess.run(["git", "cat-file", "-e", x + "^{commit}"],
                                                               capture_output=True).returncode == 0)
    return PINS[name]


def alive_at_pin(name, needle, tok=False):
    """L'aiguille (texte exact, ou suite de jetons) est-elle dans une source a un commit epingle du recensement ?"""
    words = sorted((t for t, _, _ in A.tokens(needle) if re.match(r"\w{3,}$", t)), key=len) if tok else None
    probe = words[-1] if tok and words else max(needle.splitlines() or [needle], key=len).strip()
    if len(probe) < 3:
        return ""
    for sha in pins_of(name):
        hits = subprocess.run(["git", "grep", "-lF", "--", probe, sha], capture_output=True, text=True).stdout.split()
        for h in hits:
            path = h.split(":", 1)[1]
            if path.startswith(".autoport/lib/census/"):
                continue
            body = A.at_commit(sha, path)
            if (A.tok_count(body, needle) if tok else needle in body):
                return sha[:10]
    return ""


def layout(v):
    """Le texte depend-il de la MISE EN PAGE ? retour a la ligne, indentation, blanc qui touche une PONCTUATION
    (`a = b`, `f(x, y)`), ou plusieurs blancs entre mots. `def nom`, `class Fake` : un mot-cle et son nom, non."""
    return bool("\n" in v.strip("\n") or re.match(r"^[ \t]+\S", v) or v.endswith("\n")
                or re.search(r"[^\w\s][ \t]+\S|\S[ \t]+[^\w\s]", v) or len(re.findall(r"\w[ \t]+\w", v)) >= 2)


CODEY = re.compile(r"[(){}=\[;]|^\s|^(def|class|if|for|return|static|const|auto|export|void) ")
SEEDY = re.compile(r"[(){}=\[;:,]|^\s|^(def|class|if|for|return|static|const|auto|export|void) ")
NEEDLE_M = {"index", "find", "count", "startswith", "endswith", "rindex", "rfind", "partition", "rpartition", "split"}
RE_F = {"search", "match", "fullmatch", "findall", "finditer", "compile", "sub", "subn"}
READ_M = {"read_text", "read", "readlines", "read_bytes"}
COUNTERS = {"tok_count", "tok_find", "gql_has", "gql_drop_arg", "sites", "ws_count"}   # peuvent attendre 0 : vivance non jugee
STRUCT = {"site", "sites", "mutate", "seed", "tok_find", "tok_count", "tok_at", "tok_replace", "tok_line",
          "tok_block", "gql_has", "gql_drop_arg", "ws_count", "at_commit", "retired_by"}


# ============================================================================== blocs python ==
def scopes(tree):
    """-> {noeud: nom de la fonction qui l'enclot ('' = module)}"""
    sc = {}

    def walk(n, fn):
        for c in ast.iter_child_nodes(n):
            sc[c] = fn
            walk(c, c.name if isinstance(c, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda)) and hasattr(c, "name") else fn)
    walk(tree, "")
    return sc


def taint(tree, env):
    """Noms (portee, nom) lies a un texte LU D'UNE SOURCE suivie. Flux insensible, a point fixe :
    source = expression qui APPELLE un lecteur (read_text/open/git show/fonction locale qui lit) ET mentionne un
    chemin de code (constante) ou un nom deja 'chemin'/'texte' ; propagation par affectation, `for`, comprehension."""
    sc = scopes(tree)
    defs = {n.name: n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}

    def direct_read(expr, fnames):
        for c in ast.walk(expr):
            if isinstance(c, ast.Call):
                f = c.func
                nm = f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", "")
                if nm in READ_M or nm == "open" or nm in fnames or (nm in ("run", "check_output") and any(
                        isinstance(k, ast.Constant) and k.value in ("show", "cat-file", "grep") for k in ast.walk(c))):
                    return True
        return False

    # un LECTEUR rend un texte lu : son `return` lit, ou rend un nom qu'il a lie a une lecture (a point fixe)
    readers, changed = set(), True
    while changed:
        changed = False
        for name, fn in defs.items():
            if name in readers:
                continue
            bound = {t.id for s_ in ast.walk(fn) if isinstance(s_, (ast.Assign, ast.For)) and direct_read(
                s_.value if isinstance(s_, ast.Assign) else s_.iter, readers)
                for t in ast.walk(s_.targets[0] if isinstance(s_, ast.Assign) else s_.target) if isinstance(t, ast.Name)}
            for r in ast.walk(fn):
                if isinstance(r, ast.Return) and r.value is not None and (direct_read(r.value, readers) or any(
                        isinstance(m, ast.Name) and m.id in bound for m in ast.walk(r.value))):
                    readers.add(name); changed = True
                    break
    paths, text, frozen = set(), set(), set()     # (portee, nom)
    SHA = re.compile(r"^[0-9a-f]{7,40}$")

    def pinned(expr):
        """Lecture a un commit EPINGLE (`git show <sha>:...`, `A.at_commit`) : un texte fige ne meurt pas d'une reecriture."""
        if any(isinstance(c, ast.Call) and getattr(c.func, "attr", "") == "at_commit" for c in ast.walk(expr)):
            return True
        return any(isinstance(c, ast.Constant) and c.value == "show" for c in ast.walk(expr)) and any(
            SHA.match(A.fold(m, env) or "") for m in ast.walk(expr) if isinstance(m, (ast.Name, ast.Constant)))

    def key(scope, nm, assigned):
        return (scope, nm) if (scope, nm) in assigned else ("", nm)

    assigned = set()
    for n in ast.walk(tree):
        tg = []
        if isinstance(n, (ast.Assign, ast.AnnAssign, ast.AugAssign)):
            tg = n.targets if isinstance(n, ast.Assign) else [n.target]
        elif isinstance(n, (ast.For, ast.comprehension)):
            tg = [n.target]
        elif isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            for a in n.args.args:
                assigned.add((n.name, a.arg))
        for t in tg:
            for m in ast.walk(t):
                if isinstance(m, ast.Name):
                    assigned.add((sc.get(n, ""), m.id))

    def mentions(expr, scope, pool):
        for m in ast.walk(expr):
            if isinstance(m, ast.Name) and key(scope, m.id, assigned) in pool:
                return True
        return False

    def reads(expr):
        for c in ast.walk(expr):
            if isinstance(c, ast.Call):
                f = c.func
                nm = f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", "")
                if nm in READ_M or nm == "open" or nm in readers or (nm in ("run", "check_output") and any(
                        isinstance(k, ast.Constant) and k.value in ("show", "cat-file", "grep") for k in ast.walk(c))):
                    return True
        return False

    def haspath(expr, scope):
        return any(is_path(fold_(m)) for m in ast.walk(expr)) or mentions(expr, scope, paths)

    def fold_(m):
        return A.fold(m, env) if isinstance(m, (ast.Constant, ast.Name, ast.BinOp, ast.JoinedStr)) else None

    changed = True
    while changed:
        changed = False
        for n in ast.walk(tree):
            scope = sc.get(n, "")
            if isinstance(n, (ast.Assign, ast.AnnAssign, ast.AugAssign)):
                val, tg = n.value, (n.targets if isinstance(n, ast.Assign) else [n.target])
            elif isinstance(n, ast.For):
                val, tg = n.iter, [n.target]
            elif isinstance(n, ast.comprehension):
                val, tg, scope = n.iter, [n.target], sc.get(n, "")
            elif isinstance(n, ast.Call) and getattr(n.func, "id", "") in defs:
                fn = defs[n.func.id]
                for a, p in zip(n.args, fn.args.args):
                    k = (fn.name, p.arg)
                    if k not in paths and haspath(a, scope):
                        paths.add(k); changed = True
                    if k not in text and isinstance(a, ast.Name) and mentions(a, scope, text):
                        text.add(k); changed = True
                continue
            else:
                continue
            if val is None:
                continue
            is_fz = ((reads(val) or pinned(val)) and pinned(val)) or mentions(val, scope, frozen)
            is_text = (reads(val) and haspath(val, scope)) or mentions(val, scope, text)
            is_p = not is_text and haspath(val, scope)
            for t in tg:
                for m in ast.walk(t):
                    if isinstance(m, ast.Name) and is_fz and key(scope, m.id, assigned) not in frozen:
                        frozen.add(key(scope, m.id, assigned)); changed = True
            for t in tg:
                for m in ast.walk(t):
                    if isinstance(m, ast.Name):
                        k = key(scope, m.id, assigned)
                        if is_text and k not in text:
                            text.add(k); changed = True
                        elif is_p and k not in paths:
                            paths.add(k); changed = True
    return sc, text, readers, assigned, frozen


def is_frozen(expr, scope, frozen, assigned):
    return any(isinstance(m, ast.Name) and ((scope, m.id) if (scope, m.id) in assigned else ("", m.id)) in frozen
               for m in ast.walk(expr))


def direct_target(expr, env):
    """La source lue DIRECTEMENT par l'expression (`Path(P).read_text()`, `read(P)`) -> [P] ; sinon []."""
    for m in ast.walk(expr):
        if isinstance(m, ast.Call):
            for c in ast.walk(m):
                v = A.fold(c, env) if isinstance(c, (ast.Constant, ast.Name)) else None
                if is_path(v):
                    return [v if v in CODESET else ".autoport/" + v]
    return []


def haystack_is_source(expr, scope, text, readers, assigned, env):
    for m in ast.walk(expr):
        if isinstance(m, ast.Name):
            k = (scope, m.id) if (scope, m.id) in assigned else ("", m.id)
            if k in text:
                return True
        if isinstance(m, ast.Call):
            nm = m.func.attr if isinstance(m.func, ast.Attribute) else getattr(m.func, "id", "")
            if (nm in READ_M or nm in readers) and any(is_path(A.fold(c, env)) for c in ast.walk(m)
                                                       if isinstance(c, (ast.Constant, ast.Name))):
                return True
    return False


def classify(v, where, targets):
    """-> ligne | morte | fragment. `targets` : sources que le bloc nomme (vide = tout l'arbre)."""
    alive = any(v in read(t) for t in targets) or bool(in_code(v, exclude=(where,)))
    if not alive:
        return "figee" if alive_at_pin(where, v) else "morte"
    return "ligne" if layout(v) else "fragment"


def regex_class(rx, targets):
    """Regex : ligne si elle porte un BLANC LITTERAL entre deux signes (hors classe), morte si aucune cible nommee
    ne la matche, fragment sinon. Sans cible nommee : vivance non jugee (`fragment`)."""
    body = re.sub(r"\[[^\]]*\]|\\[sSwWdDbB]|\(\?[:=!]|[()|^$*+?]|\{\d*,?\d*\}", "", rx)
    body = re.sub(r"\\(.)", r"\1", body)
    lit = layout(body)
    try:
        c = re.compile(rx, re.M)
    except re.error:
        return "fragment"
    if targets and not any(c.search(read(t)) for t in targets):
        return "morte"
    return "ligne" if lit else "fragment"


def struct_dead(call, env):
    """Un appel de `anchor.py` : ses symboles existent-ils encore ? -> nom du symbole mort ou ''."""
    nm = call.func.attr if isinstance(call.func, ast.Attribute) else call.func.id
    specs = []
    for m in ast.walk(call):
        if isinstance(m, ast.keyword) and m.arg == "func":
            specs.append(A.fold(m.value, env))
        if isinstance(m, ast.Dict):
            for k, v in zip(m.keys, m.values):
                if isinstance(k, ast.Constant) and k.value == "func":
                    specs.append(A.fold(v, env))
    for f in specs:
        if f and not re.search(r"\bdef\s+%s\b" % re.escape(f), subprocess.run(
                ["git", "grep", "-hwE", r"def\s+%s" % re.escape(f), "--", ".autoport", "game", "common"],
                capture_output=True, text=True).stdout):
            return "def:" + f
    if nm in COUNTERS:
        return ""
    if nm.startswith("tok_") and len(call.args) >= 2:
        needle = A.fold(call.args[1], env)
        if needle:
            words = sorted((t for t, _, _ in A.tokens(needle) if re.match(r"\w{3,}$", t)), key=len)
            if words:
                hits = subprocess.run(["git", "grep", "-lwF", "--", words[-1]], capture_output=True, text=True).stdout.split()
                if not any(h in CODESET and h != call_file[0] and not h.startswith(".autoport/lib/census/")
                           and A.tok_count(read(h), needle) for h in hits) and not alive_at_pin(call_file[0], needle, True):
                    return "jetons:" + needle[:40]
    return ""


call_file = [""]


def scan_python(name, text):
    """-> (graines, ancres, structurels, blocs lus, blocs illisibles)"""
    seeds, anchors, structs, nb, bad = [], [], [], 0, []
    call_file[0] = name
    for off, code, quoted, _ in A.py_blocks(name, text):
        tree = A.parse_block(code, quoted)
        if tree is None:
            bad.append("%s:%d" % (name.split("/")[-1], off))
            continue
        nb += 1
        env = A.module_env(tree)
        consts = [n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, str)]
        targets = sorted({c2 for c in consts for c2 in (c, ".autoport/" + c) if c2 in CODESET and c2 != name})
        sc, txt, readers, assigned, frz = taint(tree, env)
        where = lambda n: "%s:%d" % (name.split("/")[-1], off + n.lineno)
        # ---- graines
        found = []
        for n in ast.walk(tree):
            if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr == "replace" and len(n.args) >= 2:
                found.append((n, A.fold(n.args[0], env), A.fold(n.args[1], env)))
            elif isinstance(n, (ast.List, ast.Set, ast.Tuple)):
                for e in n.elts:
                    if isinstance(e, ast.Tuple) and len(e.elts) == 2:
                        found.append((e, A.fold(e.elts[0], env), A.fold(e.elts[1], env)))
        seen = set()
        for n, old, new in found:
            codey = SEEDY if isinstance(n, ast.Call) else CODEY
            if old is None or new is None or old == new or len(old.strip()) < 8 or not codey.search(old):
                continue
            if (n.lineno, old) in seen:
                continue
            seen.add((n.lineno, old))
            live = any(old in read(t) for t in targets) or bool(in_code(old, exclude=(name,)))
            if not live and any(old in c for c in consts if c != old):
                cls = "interne"
            elif not live:
                cls = "morte"
            else:
                cls = "ligne" if layout(old) else "fragment"
            seeds.append({"where": where(n), "text": old, "cls": cls})
        # ---- ancres
        needle_params = {}    # fonction locale -> {position: nom du parametre cherche dans une source}
        for n in ast.walk(tree):
            needle, hay, rx = None, None, False
            if isinstance(n, ast.Compare) and len(n.ops) == 1 and isinstance(n.ops[0], (ast.In, ast.NotIn)):
                needle, hay = n.left, n.comparators[0]
            elif isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.args:
                if n.func.attr in NEEDLE_M:
                    needle, hay = n.args[0], n.func.value
                elif n.func.attr in RE_F and getattr(n.func.value, "id", "") == "re" and len(n.args) >= 1:
                    needle, rx = n.args[0], True
                    hay = n.args[1] if len(n.args) >= 2 else None
            if needle is None:
                continue
            scope = sc.get(n, "")
            if isinstance(needle, ast.Name) and scope and (hay is None or haystack_is_source(
                    hay, scope, txt, readers, assigned, env)):
                fn = next((d for d in ast.walk(tree) if isinstance(d, (ast.FunctionDef, ast.AsyncFunctionDef))
                           and d.name == scope), None)
                if fn is not None:
                    for k_, a_ in enumerate(fn.args.args):
                        if a_.arg == needle.id:
                            needle_params.setdefault(scope, {})[k_] = (rx, hay)
            v = A.fold(needle, env)
            if not v or len(v.strip()) < 6 or not CODEY.search(v):
                continue
            scope = sc.get(n, "")
            if rx:
                if hay is None:   # re.compile(A) lie a NOM : ancre si `NOM.search(<source>)` quelque part
                    bound = {g.id for t in ast.walk(tree) if isinstance(t, ast.Assign) and t.value is n
                             for g in t.targets if isinstance(g, ast.Name)}
                    if not any(isinstance(m, ast.Call) and isinstance(m.func, ast.Attribute) and m.func.attr in RE_F
                               and getattr(m.func.value, "id", None) in bound and m.args
                               and haystack_is_source(m.args[0], sc.get(m, ""), txt, readers, assigned, env)
                               for m in ast.walk(tree)):
                        continue
                elif not haystack_is_source(hay, scope, txt, readers, assigned, env):
                    continue
                cls = "figee" if hay is not None and is_frozen(hay, scope, frz, assigned) else \
                    regex_class(v, direct_target(hay, env) if hay is not None else [])
                anchors.append({"where": where(n), "text": v, "cls": cls})
                continue
            if not haystack_is_source(hay, scope, txt, readers, assigned, env):
                continue
            cls = "figee" if is_frozen(hay, scope, frz, assigned) else classify(v, name, targets)
            anchors.append({"where": where(n), "text": v, "cls": cls})
        # une aiguille passee a une fonction locale qui la cherche dans une source (`region(lines, REGION_A)`)
        for n in ast.walk(tree):
            if isinstance(n, ast.Call) and getattr(n.func, "id", None) in needle_params:
                for k_, (rx, _h) in needle_params[n.func.id].items():
                    if k_ < len(n.args):
                        v = A.fold(n.args[k_], env)
                        if not v or len(v.strip()) < 6 or not CODEY.search(v):
                            continue
                        cls = regex_class(v, []) if rx else classify(v, name, targets)
                        anchors.append({"where": where(n), "text": v, "cls": cls})
        # ---- structurels
        for n in ast.walk(tree):
            if isinstance(n, ast.Call):
                f = n.func
                nm = f.attr if isinstance(f, ast.Attribute) and getattr(f.value, "id", "") == "A" else None
                if nm in STRUCT:
                    d = "" if n.args and is_frozen(n.args[0], sc.get(n, ""), frz, assigned) else struct_dead(n, env)
                    structs.append({"where": where(n), "text": nm, "cls": ("morte:" + d) if d else "structure"})
    return seeds, anchors, structs, nb, bad


# ================================================================================ lignes shell ==
def shell_lines(name, text):
    """Lignes shell HORS des heredocs python, sans commentaire, continuations jointes."""
    skip = set()
    for off, _, _, end in A.py_blocks(name, text):
        skip.update(range(off, end + 1))
    out, buf, start = [], "", 0
    for i, l in enumerate(text.splitlines(), 1):
        if i in skip:
            continue
        if not buf:
            start = i
        if l.rstrip().endswith("\\"):
            buf += l.rstrip()[:-1] + " "
            continue
        buf += l
        if buf.strip() and not buf.lstrip().startswith("#"):
            out.append((start, buf))
        buf = ""
    return out


def shell_vars(name, text):
    env = {"ROOT": "", "AP": ".autoport", "REPO": ""}
    for m in re.finditer(r"^\s*(?:local\s+|export\s+)?([A-Z_][A-Z0-9_]*)=([\"']?)([^\"'\s$`]*(?:\$\{?\w+\}?[^\"'\s$`]*)*)\2\s*$",
                         text, re.M):
        env.setdefault(m.group(1), m.group(3))
    return env


def resolve(arg, env):
    v = re.sub(r"\$\{?(\w+)\}?", lambda m: env.get(m.group(1), "\0"), arg)
    if "\0" in v:
        return None
    v = v.lstrip("/")
    return v if v in CODESET else None


def bre(p):
    """Regex BASIQUE (grep/sed sans -E) -> regex python : `\\(` groupe, `(` litteral."""
    out, i = "", 0
    while i < len(p):
        c = p[i]
        if c == "\\" and i + 1 < len(p):
            n = p[i + 1]
            out += n if n in "(){}|+?" else c + n
            i += 2
            continue
        out += "\\" + c if c in "(){}|+?" else c
        i += 1
    return out


def substitutions(line):
    """Contenus des `$(...)` d'une ligne, parentheses equilibrees, quotes respectees (recursif)."""
    out, i = [], 0
    while True:
        i = line.find("$(", i)
        if i < 0:
            return out
        j, depth, q = i + 2, 1, None
        while j < len(line) and depth:
            c = line[j]
            if q:
                if c == q:
                    q = None
            elif c in "'\"":
                q = c
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            j += 1
        inner = line[i + 2:j - 1]
        out.append(inner)
        out += substitutions(inner)
        i = j


def commands(line):
    """-> [[mot, ...] par commande, avec les fichiers de code lus plus haut dans le TUBE]"""
    out = []
    for text in [line] + substitutions(line):
        try:
            lx = shlex.shlex(text, posix=True, punctuation_chars=";&|()")
            lx.whitespace_split = True
            toks = list(lx)
        except ValueError:
            continue
        pipe, cur = [], []
        for t in toks + [";"]:
            if t and set(t) <= set(";&|()"):
                if cur:
                    pipe.append(cur)
                if t != "|":
                    out.append(pipe); pipe = []
                cur = []
            else:
                cur.append(t)
    return out


def scan_shell(name, text):
    seeds, anchors = [], []
    env = shell_vars(name, text)
    for ln, line in shell_lines(name, text):
      for pipe in commands(line):
        upstream = []
        for w in pipe:
            i = next((k for k, x in enumerate(w) if x in ("grep", "egrep", "fgrep", "sed")), None)
            if i is None:
                if w[0] in ("cat", "head", "tail", "awk", "tac", "cut", "sort", "uniq", "tr"):
                    upstream += [f for f in (resolve(a, env) for a in w) if f]
                continue
            cmd, args = w[i], w[i + 1:]
            opts = [a for a in args if a.startswith("-")]
            rest = [a for a in args if not a.startswith("-")]
            files = [f for f in (resolve(a, env) for a in rest) if f] or upstream
            upstream = files
            if not files:
                continue
            where = "%s:%d" % (name.split("/")[-1], ln)
            if cmd == "grep" and any(o in ("-v", "--invert-match") or (o[1:2] != "-" and "v" in o) for o in opts):
                continue   # un filtre (`grep -v '^#'`) n'ancre rien
            if cmd == "sed":
                prog = rest[0] if rest else ""
                sed_rx = (lambda r: r) if any(o in ("-E", "-r") or (o[1:2] != "-" and ("E" in o or "r" in o)) for o in opts) else bre
                if any(o.startswith("-i") for o in opts):
                    m = re.match(r"s(.)(.*?)(?<!\\)\1", prog)
                    if m:
                        seeds.append({"where": where, "text": m.group(2), "cls": regex_class(sed_rx(m.group(2)), files)})
                    continue
                for m in re.finditer(r"/((?:\\/|[^/])+)/", prog):
                    anchors.append({"where": where, "text": m.group(1), "cls": regex_class(sed_rx(m.group(1)), files)})
                continue
            pat = next((args[k + 1] for k, a in enumerate(args[:-1]) if a == "-e"), rest[0] if rest else "")
            if not pat or resolve(pat, env):
                continue
            fixed = any("F" in o for o in opts if not o.startswith("--")) or cmd == "fgrep"
            ext = any("E" in o or "P" in o for o in opts if not o.startswith("--")) or cmd == "egrep"
            # un COMPTEUR (`-c`, `-q`, `-l`) peut attendre 0 (un defaut recense) : sa vivance ne se juge pas, sa
            # dependance a la mise en page si. Un localisateur (`-n`, `-o`, sortie lue) doit trouver.
            counter = any(o in ("--count", "--quiet", "--files-with-matches") or (o[1:2] != "-" and set("cqlL") & set(o[1:]))
                          for o in opts)
            py = re.escape(pat) if fixed else (pat if ext else bre(pat))
            cls = regex_class(py, [] if counter else files)
            anchors.append({"where": where, "text": pat, "cls": cls})
    return seeds, anchors


# ================================================================================ recensement ==
def census_of(files, texts=None):
    S, An, St, nb, bad = [], [], [], 0, []
    for f in files:
        text = texts[f] if texts else read(f)
        s, a, st, n, b = scan_python(f, text)
        S += s; An += a; St += st; nb += n; bad += b
        if f.endswith(".sh"):
            s2, a2 = scan_shell(f, text)
            S += s2; An += a2
    return S, An, St, nb, bad


def counted(S, An, St):
    return ([x for x in S if x["cls"] in ("ligne", "morte")], [x for x in An if x["cls"] in ("ligne", "morte")],
            [x for x in St if x["cls"].startswith("morte")])


CENSUS = sorted(f for f in TRACKED if f.startswith(".autoport/lib/census/") and f.endswith((".sh", ".py")))
if ME not in CENSUS:
    CENSUS.append(ME)
S, An, St, nb, bad = census_of(CENSUS)
cs, ca, cst = counted(S, An, St)
lst = lambda xs: ",".join(x["where"] for x in xs) or "-"
pub("csa_census_files", len(CENSUS))
pub("csa_py_blocks", nb)
pub("csa_py_blocks_unparsed", ",".join(bad) or "-")
for tag, xs in (("seeds", S), ("anchors", An)):
    pub("csa_%s" % tag, len(xs))
    for c in ("ligne", "morte", "fragment", "interne", "figee"):
        sel = [x for x in xs if x["cls"] == c]
        pub("csa_%s_%s" % (tag, c), len(sel))
        if c in ("ligne", "morte"):
            pub("csa_%s_%s_list" % (tag, c), lst(sel))
pub("csa_structural", len(St))
pub("csa_structural_dead", len(cst))
pub("csa_structural_dead_list", ",".join("%s=%s" % (x["where"], x["cls"]) for x in cst) or "-")
unmeasured += ["illisible:" + b for b in bad]


# ================================================================================== controles ==
def synth(tag, body):
    return {".autoport/lib/census/%s.sh" % tag: "#!/usr/bin/env bash\npython3 - <<'PY'\n" + body + "\nPY\n" +
            "grep -c 'return autoport_proof::armed() ? 1 : 0;' game/kernel/jak1/kmachine.cpp\n" * ("pos" in tag)}


LS = ".autoport/linear_sync.py"
BGC = "game/graphics/opengl_renderer/background/background_common.cpp"
POS = synth("ctl-pos", (
    "from pathlib import Path\n"
    "SRC = Path('%s').read_text()\n"
    "x = SRC.replace('    who = history_author(mv, owner_id)\\n', '    who = \"owner\"\\n')\n"
    "def lines_of(base, rel):\n    return Path(base, rel).read_text().splitlines()\n"
    "for l in lines_of('.', '%s'):\n    if 'pbr_coverage_note_draw(' in l:\n        pass\n") % (LS, BGC))
NEG = synth("ctl-neg", (
    "import subprocess, sys\nfrom pathlib import Path\nsys.path.insert(0, '.autoport/lib/census')\nimport anchor as A\n"
    "SRC = Path('%s').read_text()\n"
    "x = A.mutate(SRC, dict(func='owner_move', kind='assign', has=('history_author',)), ('value', '\"owner\"'))\n"
    "out = subprocess.run(['bash', '.autoport/lib/census/grass-wind.sh'], capture_output=True, text=True).stdout\n"
    "ok = 'proof_feature_hits = 1;' in out\n") % LS)
try:
    ps, pa, pst, _, _ = census_of(list(POS), POS)
    p = counted(ps, pa, pst)
    pub("csa_ctl_pos_counted", "%d:%s" % (sum(map(len, p)), ",".join(x["cls"] + "@" + x["where"] for g in p for x in g)))
    if sum(map(len, p)) != 3:
        own_dead.append("C+_detecteur")
    ns, na, nst, _, _ = census_of(list(NEG), NEG)
    n_ = counted(ns, na, nst)
    pub("csa_ctl_neg_counted", "%d:%s" % (sum(map(len, n_)), ",".join(x["cls"] + "@" + x["where"] for g in n_ for x in g) or "-"))
    pub("csa_ctl_neg_structural", len(nst))
    if sum(map(len, n_)) != 0 or len(nst) != 1:
        own_dead.append("C-_detecteur")
except Exception as e:  # noqa: BLE001
    own_dead.append("C_detecteur:" + type(e).__name__)
    pub("csa_ctl_error", str(e)[:160])

# C+/C- reecriture : copie jetable de linear_sync.py, ligne visee reecrite (meme sens, autre mise en page)
PULL = ".autoport/lib/census/harness-linear-pull-reads-archived-tickets.sh"
PULL_BEFORE = "e2dea9bae8"   # HEAD avant le correctif : `pull` y seme `last_state` sur la ligne litterale
SPEC = dict(func="pull_owner", kind="assign", has=("owner_move", "mv", "why"))
try:
    src = read(LS)
    # la ligne telle qu'elle est AUJOURD'HUI (lue sur l'arbre, pas recopiee) : c'est elle que semait `pull` avant
    node = A.site(src, **SPEC)
    LIT_OLD = ast.get_source_segment(src, node)
    call = ast.get_source_segment(src, node.value.args[0]) if node.value.args else "L"
    rest = ", ".join(ast.get_source_segment(src, x) for x in node.value.args[1:])
    rewritten = A.mutate(src, SPEC, ("node", "(mv,\n     why) = owner_move(\n        %s, %s)" % (call, rest)))
    for tag, text in (("neg", src), ("pos", rewritten)):
        lit = text.count(LIT_OLD)
        try:
            n = len(A.sites(text, **SPEC)); A.mutate(text, SPEC, ("value", '{"createdAt": ""}, "carte"'))
        except A.Introuvable:
            n = 0
        pub("csa_ctl_rewrite_%s_literal_hits" % tag, lit)
        pub("csa_ctl_rewrite_%s_structural_hits" % tag, n)
        if n != 1 or (tag == "neg" and lit < 1) or (tag == "pos" and lit != 0):
            own_dead.append("C_reecriture_%s" % tag)
    # le controle du recensement `pull`, rejoue dans une copie jetable ou la ligne est reecrite : il doit ROUGIR
    tmp = tempfile.mkdtemp(prefix="csa-rewrite-")
    try:
        need = [f for f in TRACKED if f.startswith(".autoport/") and f.count("/") <= 2 and f.endswith((".py", ".sh"))
                or f.startswith(".autoport/lib/") and f.endswith((".py", ".sh"))] + [".autoport/lib/census/anchor.py"]
        for f in need:
            d = Path(tmp, f); d.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(f, d)
        for f in (".autoport/backlog.yaml", ".autoport/linear_map.json"):
            if Path(f).exists():
                shutil.copy2(f, Path(tmp, f))
        Path(tmp, LS).write_text(rewritten)
        subprocess.run(["git", "init", "-q", tmp], capture_output=True)
        subprocess.run(["git", "-C", tmp, "add", "-A"], capture_output=True)
        r = subprocess.run(["bash", PULL], cwd=tmp, capture_output=True, text=True, timeout=300,
                           env=dict(os.environ, CENSUS_CONTROLS_ONLY="1", GIT_DIR=os.path.join(tmp, ".git"),
                                    GIT_WORK_TREE=tmp))
        kv = dict(l.split("=", 1) for l in r.stdout.splitlines() if "=" in l)
        dead = kv.get("owner_archived_dead_controls_list", "?")
        pub("csa_ctl_rewrite_pull_dead", dead)
        pub("csa_ctl_rewrite_pull_last_state", kv.get("owner_archived_ctl_pos_last_state_lost", "?"))
        if dead != "-" or kv.get("owner_archived_ctl_pos_last_state_lost", "0") in ("0", "?"):
            own_dead.append("C+_reecriture_pull")
        # le MEME controle, semé par la ligne litterale (recensement au commit epingle d'avant le correctif) : il meurt
        Path(tmp, ".autoport/lib/census/pull-avant.sh").write_text(A.at_commit(PULL_BEFORE, PULL))
        r = subprocess.run(["bash", ".autoport/lib/census/pull-avant.sh"], cwd=tmp, capture_output=True, text=True,
                           timeout=300, env=dict(os.environ, CENSUS_CONTROLS_ONLY="1",
                                                 GIT_DIR=os.path.join(tmp, ".git"), GIT_WORK_TREE=tmp))
        kv = dict(l.split("=", 1) for l in r.stdout.splitlines() if "=" in l)
        bdead = kv.get("owner_archived_dead_controls_list", "?")
        pub("csa_ctl_rewrite_pull_before_commit", PULL_BEFORE)
        pub("csa_ctl_rewrite_pull_before_dead", bdead)
        if "C+_last_state:introuvable" not in bdead.split(","):
            own_dead.append("C+_reecriture_pull_avant_vivant")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
except Exception as e:  # noqa: BLE001
    own_dead.append("C_reecriture:" + type(e).__name__)
    pub("csa_ctl_rewrite_error", str(e)[:160])

pub("csa_unmeasured", ",".join(unmeasured) or "-")
pub("csa_own_controls_dead", ",".join(own_dead) or "-")
total = len(cs) + len(ca) + len(cst) + len(unmeasured) + len(own_dead)
pub("census_literal_anchors", total)
if os.environ.get("CSA_DEBUG"):
    for x in S + An + St:
        if x["cls"] not in ("fragment", "interne", "structure", "figee") or os.environ.get("CSA_DEBUG") == "2":
            print("DBG %-8s %-60s %r" % (x["cls"], x["where"], x["text"][:110]), file=sys.stderr)
for k_, v in OUT.items():
    print("%s=%s" % (k_, v))
PY
