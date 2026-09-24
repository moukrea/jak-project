"""census/anchor.py — ancrer une graine ou un localisateur de recensement sur une FORME, jamais sur une ligne.

Un recensement qui seme son controle par `src.replace("    return on_ticket(L, issue_id", ...)` meurt a la premiere
reecriture de la ligne (ef3327822c : `return` -> `r =`, controle mort sans rougir). Ici :

  * Python : on designe un NOEUD de l'arbre — la fonction qui l'enclot, son genre, les noms qu'il porte —
    `site(src, func="post_comment", kind="if", has=("who",))`. La mise en page, les renommages de variables
    voisines, un `return` devenu affectation ne le perdent pas.
  * C, C++, GLSL, GraphQL, shell : on compare des JETONS, commentaires et blancs retires —
    `tok_find(text, 'effective_options["temporal"] = {')` trouve aussi `effective_options[ "temporal" ]={`.
  * Introuvable ou AMBIGU (0 ou plusieurs noeuds) : `Introuvable(nom)` — un defaut NOMME, jamais un vert.

Le recensement `harness-census-seeds-anchored-structurally` lit les appels de ce module comme structurels et
verifie que leurs symboles (`func`, jetons) existent encore dans l'arbre suivi.
"""
import ast
import re


class Introuvable(Exception):
    """La forme designee n'est pas dans la source (ou y est plusieurs fois). `str(e)` la nomme."""


# ======================================================================================== Python ==
KINDS = {
    "if": (ast.If,), "while": (ast.While,), "assign": (ast.Assign, ast.AnnAssign, ast.AugAssign),
    "return": (ast.Return,), "expr": (ast.Expr,), "call": (ast.Call,), "for": (ast.For,),
    "with": (ast.With,), "def": (ast.FunctionDef, ast.AsyncFunctionDef), "try": (ast.Try,),
    "str": (ast.Constant,), "compare": (ast.Compare,), "boolop": (ast.BoolOp,), "dict": (ast.Dict,),
    "listcomp": (ast.ListComp,), "dictcomp": (ast.DictComp,), "setcomp": (ast.SetComp,),
    "stmt": (ast.stmt,),
}


def _key(n):
    """La partie d'un noeud qui le DESIGNE : le test d'un `if`, la valeur et la cible d'une affectation..."""
    if isinstance(n, (ast.If, ast.While)):
        return [n.test]
    if isinstance(n, ast.For):
        return [n.target, n.iter]
    if isinstance(n, ast.With):
        return list(n.items)
    if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.Try)):
        return []
    return [n]


def _names(parts):
    out = set()
    for p in parts:
        for m in ast.walk(p):
            if isinstance(m, ast.Name):
                out.add(m.id)
            elif isinstance(m, ast.Attribute):
                out.add(m.attr)
            elif isinstance(m, ast.arg):
                out.add(m.arg)
            elif isinstance(m, ast.keyword) and m.arg:
                out.add(m.arg)
            elif isinstance(m, ast.Constant) and isinstance(m.value, str):
                out.add(m.value)
    return out


def _funcs(tree):
    """-> [(noeud, nom de la fonction la plus proche qui l'enclot ou '')]"""
    out = []

    def walk(n, fn):
        for c in ast.iter_child_nodes(n):
            out.append((c, fn))
            walk(c, c.name if isinstance(c, (ast.FunctionDef, ast.AsyncFunctionDef)) else fn)
    walk(tree, "")
    return out


def sites(src, func=None, kind="stmt", has=(), within=None):
    """Tous les noeuds de genre `kind`, dans la fonction `func` (la plus proche qui les enclot ; `None` = partout),
    dont la partie designante porte TOUS les noms de `has` (identifiants, attributs, cles, chaines EXACTES).
    `within` : genre d'un ancetre obligatoire du noeud (ex. "for" : le `if` d'une boucle)."""
    tree = src if isinstance(src, ast.AST) else ast.parse(src)
    types = KINDS[kind]
    want = set(has)
    found = []
    parents = {}
    for p in ast.walk(tree):
        for c in ast.iter_child_nodes(p):
            parents[c] = p
    for n, fn in _funcs(tree):
        if not isinstance(n, types) or (func is not None and fn != func):
            continue
        if kind == "def" and func is not None:
            continue
        if want and not want <= _names(_key(n)) | ({n.name} if kind == "def" else set()):
            continue
        if within:
            a, ok = parents.get(n), False
            while a is not None and not ok:
                ok = isinstance(a, KINDS[within])
                a = parents.get(a)
            if not ok:
                continue
        found.append(n)
    return found


def site(src, func=None, kind="stmt", has=(), within=None):
    """Le noeud UNIQUE ; 0 ou plusieurs -> `Introuvable` qui les compte."""
    f = sites(src, func, kind, has, within)
    if len(f) != 1:
        raise Introuvable("%s/%s/%s:%d" % (func or "*", kind, "+".join(has) or "-", len(f)))
    return f[0]


def _offsets(src):
    starts, pos = [0], 0
    for line in src.splitlines(keepends=True):
        pos += len(line)
        starts.append(pos)
    return starts


def span(src, node):
    """Etendue (debut, fin) en caracteres du noeud dans `src` (`col_offset` compte des OCTETS utf-8)."""
    o = _offsets(src)

    def at(line, col):
        start = o[line - 1]
        end = o[line] if line < len(o) else len(src)
        return start + len(src[start:end].encode("utf-8")[:col].decode("utf-8", "ignore"))
    return at(node.lineno, node.col_offset), at(node.end_lineno, node.end_col_offset)


def mutate(src, spec, op):
    """Applique UNE graine. `spec` = dict(func=, kind=, has=, within=) ; `op` :
         "false"          le test d'un if/while devient `False`
         "true"           le test devient `True`
         "pass"           l'instruction devient `pass` (indentation conservee)
         ("value", e)     la valeur d'une affectation/d'un return devient l'expression `e`
         ("test", e)      le test d'un if/while devient l'expression `e`
         ("node", e)      le noeud entier devient le texte `e`
         ("drop_kw", k)   retire l'argument nomme `k` d'un appel
    -> nouvelle source. Leve `Introuvable` si la forme manque ou est ambigue."""
    n = site(src, **spec)
    if op in ("false", "true"):
        tgt, txt = n.test, "False" if op == "false" else "True"
    elif op == "pass":
        tgt, txt = n, "pass"
    elif op[0] == "value":
        tgt, txt = n.value, op[1]
    elif op[0] == "test":
        tgt, txt = n.test, op[1]
    elif op[0] == "node":
        tgt, txt = n, op[1]
    elif op[0] == "drop_kw":
        kws = [k for k in getattr(n, "keywords", []) if k.arg == op[1]]
        if len(kws) != 1:
            raise Introuvable("drop_kw:%s:%d" % (op[1], len(kws)))
        a, b = span(src, kws[0])
        before = src[:a].rstrip()
        if before.endswith(","):
            return before[:-1] + src[b:]
        after = src[b:].lstrip()
        return src[:a] + (after[1:].lstrip() if after.startswith(",") else src[b:])
    else:
        raise ValueError(op)
    if tgt is None:
        raise Introuvable("sans-valeur:%s" % spec)
    a, b = span(src, tgt)
    return src[:a] + txt + src[b:]


def seed(src, seeds):
    """-> (source semee, [graines introuvables nommees]). `seeds` = [(spec, op), ...] ; une graine introuvable laisse
    la source intacte pour elle et se NOMME : l'appelant la compte comme un controle mort."""
    missing = []
    for spec, op in seeds:
        try:
            src = mutate(src, spec, op)
        except (Introuvable, SyntaxError) as e:
            missing.append(str(e))
    return src, missing


# ================================================================ jetons : C, C++, GLSL, GraphQL, shell ==
_COMMENT = {
    "c": re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'', re.S),
    "sh": re.compile(r'(?:(?<=\s)|^)#[^\n]*|"(?:\\.|[^"\\])*"|\'[^\']*\'', re.M),
    "gql": re.compile(r'#[^\n]*|"(?:\\.|[^"\\\n])*"'),
}
_TOKEN = re.compile(r'"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'|\w+|::|->|&&|\|\||[<>=!+\-*/]=|<<|>>|\S')


def _blank_comments(text, lang):
    def keep(m):
        s = m.group(0)
        return s if s[0] in "\"'" else re.sub(r"[^\n]", " ", s)
    return _COMMENT[lang].sub(keep, text)


def tokens(text, lang="c"):
    """-> [(jeton, debut, fin)] ; commentaires ecartes, blancs ignores."""
    t = _blank_comments(text, lang)
    return [(m.group(0), m.start(), m.end()) for m in _TOKEN.finditer(t)]


def tok_find(text, needle, lang="c"):
    """Etendues (debut, fin) ou la SUITE DE JETONS de `needle` apparait dans `text`, quelle que soit la mise en page."""
    hay = tokens(text, lang)
    want = [t for t, _, _ in tokens(needle, lang)]
    if not want:
        return []
    words = [t for t, _, _ in hay]
    out, k = [], len(want)
    for i in range(len(words) - k + 1):
        if words[i] == want[0] and words[i:i + k] == want:
            out.append((hay[i][1], hay[i + k - 1][2]))
    return out


def tok_count(text, needle, lang="c"):
    return len(tok_find(text, needle, lang))


def tok_at(text, needle, lang="c"):
    """L'etendue UNIQUE ; 0 ou plusieurs -> `Introuvable`."""
    f = tok_find(text, needle, lang)
    if len(f) != 1:
        raise Introuvable("jetons:%s:%d" % (needle[:40], len(f)))
    return f[0]


def tok_replace(text, needle, new, lang="c"):
    """Remplace l'occurrence UNIQUE de la suite de jetons `needle` par `new`."""
    a, b = tok_at(text, needle, lang)
    return text[:a] + new + text[b:]


def tok_line(text, needle, lang="c"):
    """Numero (1..) de la ligne ou commence l'occurrence unique."""
    a, _ = tok_at(text, needle, lang)
    return text.count("\n", 0, a) + 1


def tok_block(text, needle, lang="c"):
    """Le bloc `{...}` (ou `(...)`) qui SUIT l'occurrence unique de `needle`, jetons equilibres -> texte."""
    a, b = tok_at(text, needle, lang)
    hay = tokens(text[b:], lang)
    pairs = {"{": "}", "(": ")", "[": "]"}
    depth, opener, start = 0, None, None
    for t, s, e in hay:
        if opener is None:
            if t in pairs:
                opener, start, depth = t, s, 1
            continue
        if t == opener:
            depth += 1
        elif t == pairs[opener]:
            depth -= 1
            if depth == 0:
                return text[b + start:b + e]
    raise Introuvable("bloc:%s" % needle[:40])


# ============================================================================================ GraphQL ==
def gql_norm(q):
    """Une requete sans ses blancs : `issues(first: 250 , includeArchived:true)` == `issues(first:250,includeArchived:true)`."""
    return re.sub(r"\s+", "", q or "")


def gql_has(q, *fragments):
    """Vrai si chaque fragment (blancs ignores des deux cotes) est dans la requete."""
    n = gql_norm(q)
    return all(gql_norm(f) in n for f in fragments)


def gql_drop_arg(q, arg):
    """Retire l'argument `arg: valeur` de TOUTES les listes d'arguments de la requete ; -> (requete, nombre retire)."""
    rx = re.compile(r"\s*\b%s\s*:\s*(\$\w+|true|false|-?\d+|\"(?:\\.|[^\"\\])*\")\s*,?" % re.escape(arg))
    out, n = rx.subn("", q)
    out = re.sub(r",\s*\)", ")", out)
    return out, n


# ================================================================== lecture des recensements eux-memes ==
OPEN = re.compile(r"python3?\b[^\n]*<<-?\s*(['\"]?)(\w+)\1")


def py_blocks(name, text):
    """-> [(ligne du fichier qui precede le bloc, code, heredoc quote, derniere ligne du bloc)]. Un `.py` est un
    bloc ; un `.sh` en porte un par heredoc python."""
    if name.endswith(".py"):
        return [(0, text, True, text.count("\n") + 1)]
    out, lines, i = [], text.splitlines(), 0
    while i < len(lines):
        m = OPEN.search(lines[i])
        if m and not lines[i].lstrip().startswith("#"):
            j = i + 1
            while j < len(lines) and lines[j].strip() != m.group(2):
                j += 1
            out.append((i + 1, "\n".join(lines[i + 1:j]), bool(m.group(1)), j + 1))
            i = j
        i += 1
    return out


def parse_block(code, quoted):
    try:
        return ast.parse(code)
    except SyntaxError:
        if quoted:
            return None
    try:   # heredoc non quote : `$X`, `${..}`, `$(..)` sont des valeurs que le shell pose -> `0`
        code = re.sub(r"(?<!\\)\$(\{[^}]*\}|\([^)]*\)|\w+)", "0", code.replace("\\\n", ""))
        return ast.parse(re.sub(r"\\([\\$`])", r"\1", code))
    except SyntaxError:
        return None


def fold(n, env):
    """Valeur d'une chaine constante : litteral, nom lie a une constante, somme, `%` ou f-string constants."""
    if isinstance(n, ast.Constant) and isinstance(n.value, str):
        return n.value
    if isinstance(n, ast.Name):
        return env.get(n.id)
    if isinstance(n, ast.BinOp) and isinstance(n.op, ast.Add):
        a, b = fold(n.left, env), fold(n.right, env)
        return a + b if a is not None and b is not None else None
    if isinstance(n, ast.JoinedStr):
        parts = [fold(v, env) for v in n.values]
        return "".join(parts) if all(p is not None for p in parts) else None
    return None


def module_env(tree):
    """Constantes de chaine du MODULE (instructions de tete, et celles des `if`/`try`/`with` de tete) : un nom
    reaffecte dans une fonction n'est pas resolu."""
    env, todo = {}, list(tree.body)
    while todo:
        s = todo.pop(0)
        if isinstance(s, ast.Assign) and len(s.targets) == 1 and isinstance(s.targets[0], ast.Name):
            v = fold(s.value, env)
            if v is not None:
                env.setdefault(s.targets[0].id, v)
        elif isinstance(s, (ast.If, ast.Try, ast.With)):
            todo[:0] = list(s.body) + list(getattr(s, "orelse", [])) + [x for h in getattr(s, "handlers", []) for x in h.body]
    return env


def at_commit(sha, path):
    """Le texte de `path` au commit EPINGLE `sha` (`git show`), '' s'il n'y est pas. Un texte fige : une ancre qui
    le vise ne meurt pas d'une reecriture de l'arbre."""
    import subprocess
    r = subprocess.run(["git", "show", "%s:%s" % (sha, path)], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def retired_by(path, symbol=None):
    """Le commit qui a RETIRE `symbol` de `path` (ou supprime `path`) -> sha court, '' si introuvable. Nomme un
    retrait voulu, pour qu'une ancre absente ne soit pas confondue avec une ancre morte."""
    import subprocess
    args = ["git", "log", "-1", "--format=%h"] + (["-S" + symbol] if symbol else ["--diff-filter=D"]) + ["--", path]
    return subprocess.run(args, capture_output=True, text=True).stdout.strip()


def ws_count(text, phrase):
    """Occurrences d'une PHRASE (message, libelle), blancs et retours a la ligne normalises des deux cotes."""
    norm = lambda t: re.sub(r"\s+", " ", t or "").strip()
    p = norm(phrase)
    return norm(text).count(p) if p else 0
