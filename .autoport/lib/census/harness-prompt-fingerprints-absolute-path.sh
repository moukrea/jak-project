#!/usr/bin/env bash
# census/harness-prompt-fingerprints-absolute-path.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `prompt_fingerprints_misplaced`.
#
# LE DEFAUT (23/09, trouve par 4 workers, owner : « traite comme tu l'entends ») : `backlog._FINGERPRINTS` valait
# ".autoport/.prompt_fingerprints.json", RELATIF au cwd. Un write_prompt lance depuis `.autoport/` (ou d'ailleurs)
# ecrivait l'empreinte a cote, ou nulle part (dossier absent, exception avalee) ; relue depuis la racine, la consigne
# passait « a-la-main » au premier changement de l'item : plus jamais refabriquee, sans un mot.
# Correctif : chemin ancre sur `backlog.AP` (`_fp_path`), l'empreinte suit l'`ap_dir` de la consigne, et un echec
# d'ecriture de l'empreinte s'ecrit sur stderr.
#
# CE QU'IL MESURE — `prompt_fingerprints_misplaced` = somme de :
#   P  SONDE VIVANTE : copie jetable (tmp/proj/.autoport) du VRAI backlog.py ; write_prompt lance depuis 6 cwd
#      (racine, .autoport, lib, prompts, un dossier sans .autoport, un leurre qui porte un .autoport vide), plus un
#      write_prompt a `ap_dir` etranger. Par cwd : empreinte absente du magasin ancre = 1 ; item modifie relu
#      « a-la-main » (depuis ce cwd ou la racine) au lieu de « perime » = 1 ; tout magasin egare dans tmp = 1.
#   F  DISQUE : tout `.prompt_fingerprints.json` qui n'est pas a cote d'un `prompts/` (donc pas le magasin d'un
#      ap_dir), dans chaque arbre git (worktrees compris) et sous /tmp et $TMPDIR (profondeur 4).
#   T  A TORT : toute consigne relue « a-la-main » dont le contenu EGALE a l'octet le rendu d'un commit passe
#      (`lib/prompt_origin.py` : backlog.py ET backlog.yaml de ce commit). Nommee avec son commit.
#   L  SOURCE : toute constante Python ".autoport/.prompt_fingerprints.json" (relative) hors recensements (AST).
#   INCONNU = DEFAUT : un terme qui plante compte 1 ; un controle negatif non nul compte 1 ; un controle positif qui ne
#   rougit pas ou ne NOMME pas son cas compte 1.
# CONTROLES POSITIFS (defaut SEME) : C+cwd = l'ancienne ligne relative dans la copie -> P nomme les cwd geles et le
#   magasin egare du leurre ; C+tort = une consigne rendue puis privee de son empreinte -> T la nomme ; C+disk = un
#   magasin sans `prompts/` seme sous $TMPDIR -> F le trouve (C-disk : son voisin a `prompts/` n'est pas accuse).
# CONTROLE NEGATIF : le code livre rend P=0 ; une consigne vraiment ecrite a la main n'est PAS adoptee par T.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "prompt_fingerprints_misplaced=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import ast, copy, hashlib, importlib.util as ilu, json, os, shutil, subprocess, sys, tempfile, time
sys.path.insert(0, ".autoport/lib")
import backlog as B
import prompt_origin as PO

ROOT = os.getcwd()
AP = os.path.join(ROOT, ".autoport")
OUT = {}
def pub(k, v): OUT[k] = str(v).replace(" ", "_")
unmeasured, dead = [], []
SRC = open(os.path.join(AP, "lib", "backlog.py"), encoding="utf-8").read()
NEW_LINE = '_FINGERPRINTS = os.path.join(AP, ".prompt_fingerprints.json")'
OLD_LINE = '_FINGERPRINTS = ".autoport/.prompt_fingerprints.json"'
sha = lambda t: hashlib.sha256(t.encode("utf-8")).hexdigest()


# ============================================================================ P : SONDE VIVANTE ==
def probe(seeded):
    """Rend (defauts nommes, nombre de sondes). Tout se passe dans un tmp : le vrai magasin n'est jamais touche."""
    tmp = tempfile.mkdtemp(prefix="fp-census-")
    cwd0 = os.getcwd()
    named, n = [], 0
    try:
        ap = os.path.join(tmp, "proj", ".autoport")
        os.makedirs(os.path.join(ap, "lib")); os.makedirs(os.path.join(ap, "prompts"))
        shutil.copy(os.path.join(AP, "lib", "secret_mask.py"), os.path.join(ap, "lib"))
        shutil.copy(os.path.join(AP, "backlog.yaml"), os.path.join(ap, "backlog.yaml"))
        src = SRC
        if seeded:
            if src.count(NEW_LINE) != 1:
                raise RuntimeError("graine introuvable")
            src = src.replace(NEW_LINE, OLD_LINE)
        with open(os.path.join(ap, "lib", "backlog.py"), "w", encoding="utf-8") as fh:
            fh.write(src)
        spec = ilu.spec_from_file_location("backlog_fp_%d" % seeded, os.path.join(ap, "lib", "backlog.py"))
        M = ilu.module_from_spec(spec); spec.loader.exec_module(M)
        store = os.path.join(ap, ".prompt_fingerprints.json")
        ailleurs = os.path.join(tmp, "ailleurs"); os.makedirs(ailleurs)
        leurre = os.path.join(tmp, "leurre"); os.makedirs(os.path.join(leurre, ".autoport"))
        cwds = [("racine", os.path.join(tmp, "proj")), ("autoport", ap), ("lib", os.path.join(ap, "lib")),
                ("prompts", os.path.join(ap, "prompts")), ("ailleurs", ailleurs), ("leurre", leurre)]
        items = [it for it in M.load(os.path.join(ap, "backlog.yaml")).items if it.get("id")][:len(cwds) + 1]
        for (label, cwd), it in zip(cwds, items):
            n += 1
            os.chdir(cwd)
            p = M.write_prompt(it)                                   # le chemin de production : ap_dir absent
            texte = open(p, encoding="utf-8").read()
            try:
                got = json.load(open(store, encoding="utf-8")).get(os.path.basename(p))
            except Exception:  # noqa: BLE001
                got = None
            if got != sha(texte):
                named.append("%s:empreinte-absente" % label)
            moved = copy.deepcopy(it)
            moved["owner_feedback"] = list(moved.get("owner_feedback") or []) + [{"date": "2099-01-01", "text": "sonde"}]
            st_here = M.prompt_state(moved)
            os.chdir(os.path.join(tmp, "proj"))
            st_root = M.prompt_state(moved)
            if st_here != "perime" or st_root != "perime":
                named.append("%s:gelee(%s/%s)" % (label, st_here, st_root))
        # ap_dir etranger : l'empreinte suit la consigne, elle ne contamine pas le magasin ancre
        n += 1
        other = os.path.join(tmp, "autre-ap"); os.makedirs(os.path.join(other, "prompts"))
        os.chdir(os.path.join(tmp, "proj"))
        it = items[len(cwds)]
        p = M.write_prompt(it, other)
        texte = open(p, encoding="utf-8").read()
        try:
            got = json.load(open(os.path.join(other, ".prompt_fingerprints.json"), encoding="utf-8")).get(os.path.basename(p))
        except Exception:  # noqa: BLE001
            got = None
        try:
            fuite = os.path.basename(p) in json.load(open(store, encoding="utf-8"))
        except Exception:  # noqa: BLE001
            fuite = False
        if got != sha(texte) or fuite:
            named.append("ap_dir:%s" % ("fuite-vers-le-magasin-ancre" if fuite else "empreinte-absente"))
        # magasin egare n'importe ou dans le tmp
        for f in (os.path.join(dp, ".prompt_fingerprints.json") for dp, _, fn in os.walk(tmp)
                  if ".prompt_fingerprints.json" in fn):             # glob saute les dossiers caches
            if f not in (store, os.path.join(other, ".prompt_fingerprints.json")):
                named.append("egare:%s" % os.path.relpath(f, tmp))
        return named, n
    finally:
        os.chdir(cwd0)
        shutil.rmtree(tmp, ignore_errors=True)


try:
    p_named, p_n = probe(False)
    pub("prompt_fingerprints_probe_total", p_n)
    pub("prompt_fingerprints_probe_failed", len(p_named))
    pub("prompt_fingerprints_probe_named", ",".join(p_named) or "aucun")
    P = len(p_named)
except Exception as e:  # noqa: BLE001
    unmeasured.append("P:%s" % type(e).__name__); P = 0; print("P: %r" % e, file=sys.stderr)

try:
    c_named, _ = probe(True)
    pub("prompt_fingerprints_ctl_cwd_failed", len(c_named))
    pub("prompt_fingerprints_ctl_cwd_named", ",".join(c_named) or "aucun")
    need = ("autoport:", "lib:", "prompts:", "ailleurs:", "egare:leurre")
    if not all(any(x.startswith(k) for x in c_named) for k in need) or any(x.startswith("racine:") for x in c_named):
        dead.append("C+cwd")
except Exception as e:  # noqa: BLE001
    dead.append("C+cwd:%s" % type(e).__name__); print("C+cwd: %r" % e, file=sys.stderr)


# ================================================================================== F : DISQUE ==
t0 = time.time()
seed = tempfile.mkdtemp(prefix="fp-seed-")                   # C+disk / C-disk : semes la ou F regarde
seed_bad = os.path.join(seed, "cwd", ".autoport", ".prompt_fingerprints.json")
seed_ok = os.path.join(seed, "ap", ".prompt_fingerprints.json")
for f in (seed_bad, seed_ok):
    os.makedirs(os.path.dirname(f), exist_ok=True)
    open(f, "w").write("{}")
os.makedirs(os.path.join(seed, "ap", "prompts"))
try:
    trees = [l.split(" ", 1)[1] for l in subprocess.run(["git", "worktree", "list", "--porcelain"], capture_output=True,
             text=True).stdout.splitlines() if l.startswith("worktree ")]
    prune = r"\( -name .git -o -name build -o -name 'build-*' -o -name out -o -name iso_data -o -name third-party" \
            r" -o -name node_modules -o -name decompiler_out \) -prune -o"
    found = []
    for t in trees:
        if not os.path.isdir(t):
            continue
        r = subprocess.run("find %s %s -name .prompt_fingerprints.json -print 2>/dev/null" % (repr(t), prune),
                           shell=True, capture_output=True, text=True, timeout=240)
        found += r.stdout.split()
    tmp_found = []
    for d in sorted({"/tmp", tempfile.gettempdir()}):
        r = subprocess.run(["find", d, "-maxdepth", "4", "-name", ".prompt_fingerprints.json"],
                           capture_output=True, text=True, timeout=120)
        tmp_found += [f for f in r.stdout.split() if "/fp-census-" not in f]
    found += tmp_found
    # Un magasin est a sa place a cote du `prompts/` des consignes qu'il empreinte (write_prompt ecrit
    # `<ap_dir>/prompts/...` et `<ap_dir>/.prompt_fingerprints.json`) : celui d'un ap_dir de test l'est aussi.
    strays = [f for f in found if not os.path.isdir(os.path.join(os.path.dirname(f), "prompts"))]
    if seed_bad not in strays:
        dead.append("C+disk")
    if seed_ok in strays or seed_ok not in found:
        dead.append("C-disk")
    found = [f for f in found if not f.startswith(seed + os.sep)]
    strays = [f for f in strays if not f.startswith(seed + os.sep)]
    pub("prompt_fingerprints_trees_scanned", len(trees))
    pub("prompt_fingerprints_stores_found", len(found))
    pub("prompt_fingerprints_stray_stores", len(strays))
    pub("prompt_fingerprints_stray_named", ",".join(strays) or "aucun")
    F = len(strays)
except Exception as e:  # noqa: BLE001
    unmeasured.append("F:%s" % type(e).__name__); F = 0; print("F: %r" % e, file=sys.stderr)
shutil.rmtree(seed, ignore_errors=True)
pub("prompt_fingerprints_disk_scan_s", int(time.time() - t0))


# ================================================================================ T : A TORT ==
try:
    b = B.load()
    states = {}
    wrong, replayed = [], 0
    for it in b.items:
        st = B.prompt_state(it)
        states[st] = states.get(st, 0) + 1
        if st != "a-la-main":
            continue
        rel = it.get("prompt") or ("prompts/item-%s.md" % it["id"])
        content = open(os.path.join(AP, rel), encoding="utf-8").read()
        replayed += 1
        c = PO.proven_render(content, PO.history_renders(it["id"], ".autoport/" + rel))
        if c:
            wrong.append("%s@%s" % (it["id"], c))
    pub("prompt_state_total", len(b.items))
    for k in ("a-jour", "perime", "a-la-main", "absent"):
        pub("prompt_state_%s" % k.replace("-", "_"), states.get(k, 0))
    pub("prompt_hand_written_replayed", replayed)
    pub("prompt_hand_written_wrongly", len(wrong))
    pub("prompt_hand_written_wrongly_named", ",".join(wrong) or "aucun")
    T = len(wrong)
except Exception as e:  # noqa: BLE001
    unmeasured.append("T:%s" % type(e).__name__); T = 0; print("T: %r" % e, file=sys.stderr)

# C+tort / C- main : la MEME fonction de preuve, sur une consigne semee et sur un vrai texte a la main
try:
    it = copy.deepcopy(B.load().items[0])
    old = B.render_prompt(it)
    it["owner_feedback"] = list(it.get("owner_feedback") or []) + [{"date": "2099-01-01", "text": "controle"}]
    seme = PO.proven_render(old, [("seme", B.render_prompt(it)), ("rendu-d-avant", old)])
    main = PO.proven_render("consigne ecrite a la main\n", [("seme", B.render_prompt(it)), ("rendu-d-avant", old)])
    pub("prompt_fingerprints_ctl_tort_named", seme or "aucun")
    pub("prompt_fingerprints_ctl_hand_adopted", main or "aucun")
    if seme != "rendu-d-avant":
        dead.append("C+tort")
    if main is not None:
        dead.append("C-main")
except Exception as e:  # noqa: BLE001
    dead.append("C+tort:%s" % type(e).__name__); print("C+tort: %r" % e, file=sys.stderr)


# ================================================================================== L : SOURCE ==
try:
    rel_sites, parsed = [], 0
    for dp, dn, fn in os.walk(AP):
        dn[:] = [d for d in dn if d not in ("reports", "census", "archive", "logs", "__pycache__", ".git")]
        for f in fn:
            if not f.endswith(".py"):
                continue
            path = os.path.join(dp, f)
            try:
                tree = ast.parse(open(path, encoding="utf-8").read())
            except Exception:  # noqa: BLE001 — pas du Python lisible : hors denominateur
                continue
            parsed += 1
            for node in ast.walk(tree):
                if isinstance(node, ast.Constant) and node.value == ".autoport/.prompt_fingerprints.json":
                    rel_sites.append("%s:%d" % (os.path.relpath(path, ROOT), node.lineno))
    pub("prompt_fingerprints_source_files", parsed)
    pub("prompt_fingerprints_relative_sites", len(rel_sites))
    pub("prompt_fingerprints_relative_named", ",".join(rel_sites) or "aucun")
    L = len(rel_sites)
except Exception as e:  # noqa: BLE001
    unmeasured.append("L:%s" % type(e).__name__); L = 0; print("L: %r" % e, file=sys.stderr)

pub("prompt_fingerprints_unmeasured", len(unmeasured))
pub("prompt_fingerprints_unmeasured_named", ",".join(unmeasured) or "aucun")
pub("prompt_fingerprints_dead_controls", len(dead))
pub("prompt_fingerprints_dead_named", ",".join(dead) or "aucun")
pub("prompt_fingerprints_misplaced", P + F + T + L + len(unmeasured) + len(dead))
for k, v in OUT.items():
    print("%s=%s" % (k, v))
PY
