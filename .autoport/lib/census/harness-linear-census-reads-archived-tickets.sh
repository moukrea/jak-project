#!/usr/bin/env bash
# census/harness-linear-census-reads-archived-tickets.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `linear_archived_blind_reads`.
#
# LA CAUSE MESUREE (23/09) : l'API Linear rend un ticket ARCHIVE a `issue(id:)`, mais une COLLECTION
# (`issues(...)`, `team{issues}`, `issueLabel{issues}`) l'ecarte en silence sans `includeArchived:true`.
# JAK-180 archive le 22/09 22:39:55Z -> la recherche par titre du recensement d'identite rendait vide ->
# `linear_identity_defects=1` sans une ligne de code changee ; et `pull_owner` ne relisait que 80 des
# 209 tickets suivis (129 archives) : un retour de l'owner poste sur un archive n'etait jamais relu.
#
# CE QU'IL MESURE — `linear_archived_blind_reads` = somme de :
#   S  STATIQUE : chaque lecture COLLECTION de tickets dans le code du harnais (.py/.sh/.bash suivis par
#      git, hors archive/ reports/ logs/) sans `includeArchived:true`. Une lecture qui VISE des tickets
#      (id, titre, identifiant, recherche) n'est jamais exemptable ; une ENUMERATION volontaire des
#      actifs l'est seulement si elle est NOMMEE dans EXEMPT avec sa raison. Denominateur publie.
#   L1 la regle de l'API, sur TOUS les tickets archives de la carte : avec `includeArchived`, chacun est
#      rendu (un rate = une lecture aveugle).
#   L2 `issue(id:)` et ses `comments` rendent l'archive (echantillon de 5) : c'est ce qui dispense les
#      lectures singulieres du drapeau.
#   L3 `pull_owner` REEL (a blanc) sur les seuls tickets archives : ids demandes - ids rendus.
#   L4 l'acquis d'identite rejoue EN ENTIER sur son ticket archive : vert, et le ticket re-archive apres.
#   INCONNU = DEFAUT : un terme non mesure compte 1. Un controle positif qui ne rougit pas compte 1.
# CONTROLES : C+ = le defaut SEME rougit et est NOMME (site retire de pull_owner, site neuf, cible
# deguisee dans une fonction exemptee ; requete d'identite privee du drapeau ; pull_owner prive du
# drapeau). C- = code sain synthetique a 0. Le code livre lui-meme est la mesure.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "linear_archived_blind_reads=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import copy, io, re, subprocess, sys
from contextlib import redirect_stdout
from pathlib import Path
sys.path.insert(0, '.autoport')

OUT = {}
def pub(k, v): OUT[k] = str(v).replace(" ", "_")
blind = 0          # la somme de la porte
unmeasured = []    # termes non mesures (1 chacun)
dead = []          # controles positifs qui ne rougissent pas (1 chacun)
FLAG = "includeArchived:true"

# ================================================================================ S : STATIQUE ==
SITE = re.compile(r"\{\s*(issues|searchIssues|issueSearch)\s*([({])")
TARGET = re.compile(r"\bid\s*:|title|identifier|number\s*:|description|or\s*:\s*\[|term\s*:")
# Enumerations VOLONTAIRES des actifs : (fichier, fonction, champ parent) -> raison.
EXEMPT = {
    (".autoport/linear_sync.py", "count_active", "query"): "compte les ACTIFS : le quota Linear = tickets non archives",
    (".autoport/linear_sync.py", "archivable", "query"): "liste les clos A archiver : un archive n'y a pas sa place",
    (".autoport/linear_sync.py", "adopt_owner_issues", "team"): "adopte les tickets OUVERTS crees par l'owner ; un archive n'est plus ouvert",
    (".autoport/linear_sync.py", "pull_labeled_unmapped", "issueLabel"): "etiquettes des tickets hors carte ; un archive n'est dans aucune vue",
    (".autoport/linear_sync.py", "sweep_talk", "issueLabel"): "coherence des etiquettes des vues ; un archive n'est dans aucune vue",
    (".autoport/linear_sync.py", "main", "issueLabel"): "file « A traiter » = une vue ; un archive n'y apparait pas",
}


def args_of(text, i):
    """Le texte entre la parenthese ouvrante `text[i]` et sa fermante (concatenations de litteraux comprises)."""
    depth = 0
    for j in range(i, min(len(text), i + 2000)):
        depth += {"(": 1, ")": -1}.get(text[j], 0)
        if depth == 0:
            return text[i + 1:j]
    return text[i + 1:i + 2000]


def parent_of(text, i):
    m = re.search(r"(\w+)\s*(\([^(){}]*\))?\s*\{\s*$", text[max(0, i - 200):i + 1])
    return m.group(1) if m else "?"


def scan(name, text):
    """-> liste de sites {where, func, parent, covered, target, exempt}."""
    out = []
    lines = text.splitlines()
    ind = lambda l: len(l) - len(l.lstrip())

    def enclosing(n):
        """La fonction qui CONTIENT la ligne n, par l'indentation : la derniere `def` avant elle peut etre
        une fonction imbriquee deja refermee (`main` -> `_poster`)."""
        cur = ind(lines[n - 1])
        for l in reversed(lines[:n - 1]):
            if l.strip() and ind(l) < cur:
                d = re.match(r"\s*def (\w+)", l)
                if d:
                    return d.group(1)
                cur = ind(l)
        return "<module>"
    for m in SITE.finditer(text):
        line = text.count("\n", 0, m.start()) + 1
        func = enclosing(line)
        args = args_of(text, m.end(2) - 1) if m.group(2) == "(" else ""
        par = parent_of(text, m.start())
        covered = FLAG in args.replace(" ", "")
        target = bool(TARGET.search(args)) or m.group(1) != "issues"
        ex = None if (covered or target) else EXEMPT.get((name, func, par))
        out.append({"where": "%s:%d:%s" % (name.replace(".autoport/", ""), line, func), "key": (name, func, par),
                    "covered": covered, "target": target, "exempt": ex})
    return out


def blind_of(sites):
    return [s for s in sites if not s["covered"] and not s["exempt"]]


files = subprocess.run(["git", "ls-files", ".autoport"], capture_output=True, text=True).stdout.split()
files = [f for f in files if not re.match(r"\.autoport/(archive|reports|logs|owner-feedback)/", f)
         and (f.endswith((".py", ".sh", ".bash")) or not re.search(r"[/.]", f[len(".autoport/"):]))]
sites = []
for f in files:
    try:
        sites += scan(f, Path(f).read_text(errors="replace"))
    except (OSError, IsADirectoryError):
        pass
sb = blind_of(sites)
used = {s["key"] for s in sites if s["exempt"]}
pub("linear_read_files_scanned", len(files))
pub("linear_read_sites_total", len(sites))
pub("linear_read_sites_covered", sum(s["covered"] for s in sites))
pub("linear_read_sites_exempt", sum(1 for s in sites if s["exempt"]))
pub("linear_read_sites_blind", len(sb))
pub("linear_read_sites_blind_list", ",".join(s["where"] for s in sb) or "-")
pub("linear_read_exempt_list", ",".join(s["where"] for s in sites if s["exempt"]) or "-")
pub("linear_read_exempt_stale", ",".join("%s:%s:%s" % k for k in EXEMPT if k not in used) or "-")
blind += len(sb)
if not sites:
    unmeasured.append("S_aucun_site")

# C+ / C- statiques, sur des copies en memoire
ls_path = ".autoport/linear_sync.py"
ls = Path(ls_path).read_text()
k = ls.find("def pull_owner")
k2 = ls.find(", " + FLAG, k)
seeded = ls[:k2] + ls[k2 + len(", " + FLAG):] if k >= 0 and k2 >= 0 else ls
c1 = blind_of(scan(ls_path, seeded))
pub("linear_ctl_seed_pull_owner", ",".join(s["where"] for s in c1) or "-")
if not any(s["where"].endswith(":pull_owner") for s in c1):
    dead.append("C+_pull_owner")
Q = "{ " + "issues(filter:{id:{in:$ids}}, first:5) { nodes { id } } }"   # coupe : pas un site de CE fichier
fake = "def lookup(L, ids):\n    return L.q('query($ids:[ID!])" + Q + "', ids=ids)\n"
c2 = blind_of(scan(".autoport/neuf.py", fake))
pub("linear_ctl_seed_new_site", ",".join(s["where"] for s in c2) or "-")
if len(c2) != 1:
    dead.append("C+_site_neuf")
disguised = "def count_active(L):\n    return L.q('query($ids:[ID!])" + Q + "')\n"
c3 = blind_of(scan(ls_path, disguised))       # cible deguisee dans une fonction exemptee
pub("linear_ctl_seed_disguised", ",".join(s["where"] for s in c3) or "-")
if len(c3) != 1:
    dead.append("C+_cible_deguisee")
healthy = fake.replace("first:5", "first:5, " + FLAG)
c4 = blind_of(scan(".autoport/neuf.py", healthy))
pub("linear_ctl_healthy", len(c4))
if c4:
    blind += len(c4)   # C- rouge = le classifieur accuse un code sain : il ne vaut rien

# ================================================================================ L : VIVANT ==
try:
    import linear_sync as S
    import linear_identity as LI
    L = S.Linear(LI.resolve())
    mp = S.load_map()
    ids = [v["issue_id"] for k_, v in mp.items() if not k_.startswith("_") and isinstance(v, dict)]
    arch = {}
    for i in range(0, len(ids), 50):
        d = L.q('query($ids:[ID!]){ issues(filter:{id:{in:$ids}}, first:50, includeArchived:true){ nodes { id identifier archivedAt } } }',
                ids=ids[i:i + 50])
        arch.update({n["id"]: n["identifier"] for n in d["issues"]["nodes"] if n["archivedAt"]})
    pub("linear_map_tickets", len(ids))
    pub("linear_archived_sample", len(arch))
    if not arch:
        raise RuntimeError("aucun ticket archive dans la carte : rien a mesurer")

    # L1 : la regle de l'API sur TOUS les archives ; le bras SANS drapeau est le controle positif
    got_flag, got_bare = set(), set()
    A = list(arch)
    for i in range(0, len(A), 50):
        q = 'query($ids:[ID!]){ issues(filter:{id:{in:$ids}}, first:50, includeArchived:true){ nodes { id } } }'
        got_flag |= {n["id"] for n in L.q(q, ids=A[i:i + 50])["issues"]["nodes"]}
        got_bare |= {n["id"] for n in L.q(q.replace(", " + FLAG, ""), ids=A[i:i + 50])["issues"]["nodes"]}
    pub("linear_api_flag_missed", len(arch) - len(got_flag))
    pub("linear_api_bare_found", len(got_bare))
    blind += len(arch) - len(got_flag)
    if len(got_bare) == len(arch):
        dead.append("C+_api_sans_drapeau")   # l'API ne les cache plus : le defaut ne se reproduit pas

    # L2 : lecture singuliere + commentaires imbriques
    sample = sorted(arch, key=lambda x: arch[x] != "JAK-180")[:5]
    miss2 = 0
    for iid in sample:
        a = L.q('query($id:String!){ issue(id:$id){ id comments(first:100){ nodes { id } } } }', id=iid)["issue"]
        b = L.q('query($id:String!){ issue(id:$id){ id comments(first:100, includeArchived:true){ nodes { id } } } }', id=iid)["issue"]
        if not a or not b or len(a["comments"]["nodes"]) != len(b["comments"]["nodes"]):
            miss2 += 1
    pub("linear_singular_sample", len(sample))
    pub("linear_singular_missed", miss2)
    blind += miss2

    # L3 : pull_owner REEL, a blanc, sur les seuls archives ; bras avant = drapeau retire a la volee
    class Rec:
        def __init__(self, strip):
            self.strip, self.mode, self.missed = strip, L.mode, []
        def q(self, query, **v):
            if self.strip:
                query = query.replace(", " + FLAG, "").replace(FLAG + ", ", "")
            d = L.q(query, **v)
            if "ids" in v and isinstance(d.get("issues"), dict):
                back = {n["id"] for n in d["issues"]["nodes"]}
                self.missed += [x for x in v["ids"] if x not in back]
            return d
    sub = {k_: copy.deepcopy(v) for k_, v in mp.items()
           if k_.startswith("_") or (isinstance(v, dict) and v.get("issue_id") in arch)}
    bl = S.B.load()
    for strip in (False, True):
        r = Rec(strip)
        with redirect_stdout(io.StringIO()):
            S.pull_owner(r, bl, copy.deepcopy(sub), {}, True)
        tag = "before" if strip else "after"
        pub("linear_pull_owner_%s_missed" % tag, len(r.missed))
        pub("linear_pull_owner_%s_first" % tag, arch.get(r.missed[0], r.missed[0]) if r.missed else "-")
        if strip and not r.missed:
            dead.append("C+_pull_owner_vivant")
        if not strip:
            blind += len(r.missed)
    pub("linear_pull_owner_asked", len(arch))

    # L4 : l'acquis d'identite. Controle positif = sa propre requete, privee du drapeau.
    idf = Path(".autoport/lib/census/harness-linear-own-identity.sh").read_text()
    m = re.search(r"'(query\(\$t:String!\)\{ issues\(filter:\{title:[^']*)'", idf)
    if not m:
        raise RuntimeError("requete de recherche du recensement d'identite introuvable")
    qi = m.group(1)
    t = "sous sa propre identit"
    now = L.q(qi, t=t)["issues"]["nodes"]
    bare = L.q(qi.replace(", " + FLAG, ""), t=t)["issues"]["nodes"]
    pub("linear_identity_lookup_found", len(now))
    pub("linear_identity_lookup_bare_found", len(bare))
    was = bool(now and now[0].get("archivedAt"))
    pub("linear_identity_ticket", now[0]["identifier"] if now else "-")
    pub("linear_identity_ticket_archived_before", int(was))
    if was and bare:
        dead.append("C+_identite_sans_drapeau")
    r = subprocess.run(["bash", ".autoport/lib/census/harness-linear-own-identity.sh"],
                       capture_output=True, text=True, timeout=400)
    kv = dict(l.split("=", 1) for l in r.stdout.splitlines() if "=" in l)
    for key in ("linear_identity_defects", "linear_author_kind", "lid_author_distinct",
                "linear_probe_issue_archived", "linear_probe_rearchived", "linear_identity_terms_measured"):
        pub("acquis_" + key, kv.get(key, "-"))
    after = L.q(qi, t=t)["issues"]["nodes"]
    still = bool(after and after[0].get("archivedAt"))
    pub("linear_identity_ticket_archived_after", int(still))
    if not was:
        unmeasured.append("L4_ticket_non_archive")
    bad4 = int(kv.get("lid_author_distinct", "1") != "0") + int(was and not still)
    pub("linear_identity_on_archived_bad", bad4)
    blind += bad4
except Exception as e:  # noqa: BLE001
    pub("linear_live_error", str(e)[:200])
    unmeasured.append("L_vivant")

pub("linear_archived_unmeasured", ",".join(unmeasured) or "-")
pub("linear_archived_controls_dead", ",".join(dead) or "-")
blind += len(unmeasured) + len(dead)
pub("linear_archived_blind_reads", blind)
for k_, v in OUT.items():
    print("%s=%s" % (k_, v))
PY
