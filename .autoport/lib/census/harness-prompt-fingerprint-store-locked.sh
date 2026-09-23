#!/usr/bin/env bash
# census/harness-prompt-fingerprint-store-locked.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `prompt_fingerprints_lost`.
# Il n'ecrit rien dans le vrai magasin : chaque course tourne sur une copie jetable (tmp/proj/.autoport).
#
# LE DEFAUT (23/09, signale par le worker de harness-prompt-fingerprints-absolute-path) : `backlog._stamp_prompt`
# relisait le magasin d'empreintes, y posait SA cle et le reecrivait, SANS verrou. Orchestrateur + linear_sync +
# superviseur ecrivent en meme temps : le dernier a ecrire effacait l'empreinte des autres, la consigne repassait
# « a-la-main » et n'etait plus jamais refabriquee. Et un magasin illisible etait relu `{}` puis REECRIT : tout perdu.
# Correctif : relire-fusionner-ecrire sous `_Lock(magasin)` ; un magasin illisible leve (stderr), il n'est pas ecrase.
#
# CE QU'IL MESURE — `prompt_fingerprints_lost` = somme de :
#   R  COURSE : 50 processus (fork) liberes par UNE barriere appellent le VRAI `write_prompt` sur 50 consignes
#      distinctes d'une copie du vrai backlog, magasin prerempli du vrai magasin. Perte = empreinte absente ou fausse
#      parmi les 50 + cle preexistante disparue. Deux bras : fenetre NATURELLE, et fenetre ELARGIE (20 ms entre la
#      relecture et l'ecriture du magasin, posee sur `_atomic_write` : sous verrou elle serialise, sans verrou tout
#      le monde relit avant que personne n'ecrive).
#   K  ILLISIBLE : magasin corrompu puis un `write_prompt` : 1 si le magasin a ete reecrit.
#   S  CLOS PERIMES : consignes d'items validated/archived dont `prompt_state` == perime dans le vrai arbre.
#      Un fichier partage par plusieurs items ne compte que s'il n'est a jour pour AUCUN d'eux (sinon ping-pong).
#   M  CONTROLE NEGATIF : les 6 consignes vraiment manuelles doivent rester « a-la-main » ET egales a l'octet a
#      leur blob d'ANCRE (parent du 1er commit de cet item, HEAD s'il n'y en a pas encore) ; 1 par ecart.
#   INCONNU = DEFAUT : un terme qui plante compte 1 ; un controle positif qui ne rougit pas compte 1.
# CONTROLES POSITIFS (code d'AVANT seme dans la copie : bloc verrouille remplace par l'ancienne relecture sans
#   verrou) : C+race = la course elargie doit perdre >= 1 empreinte ; C+corrupt = le magasin illisible doit etre
#   ecrase. Informatif : la course naturelle sur le code d'avant.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "prompt_fingerprints_lost=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import hashlib, importlib.util as ilu, json, multiprocessing as mp, os, shutil, subprocess, sys, tempfile, time
sys.path.insert(0, ".autoport/lib")
import backlog as B

ROOT = os.getcwd()
AP = os.path.join(ROOT, ".autoport")
OUT = {}
def pub(k, v): OUT[k] = str(v).replace(" ", "_")
unmeasured, dead = [], []
N = 50
WIDEN_S = 0.02
CLOSED = ("validated", "archived")
MANUAL = ("hd-models", "memory-ceiling-and-crash", "precompute-deterministic-bake", "loadgate-crash-regression",
          "fixed-tick-interpolation", "proof-kv-provenance")
SRC = open(os.path.join(AP, "lib", "backlog.py"), encoding="utf-8").read()
NEW_START = "        with _Lock(fp):\n"
NEW_END = "            _atomic_write(fp, json.dumps(d, indent=0, sort_keys=True))\n"
OLD_BLOCK = ("        d = _fp_load(ap_dir)\n"
             "        d[os.path.basename(path)] = hashlib.sha256(texte.encode(\"utf-8\")).hexdigest()\n"
             "        _atomic_write(fp, json.dumps(d, indent=0, sort_keys=True))\n")
sha = lambda t: hashlib.sha256(t.encode("utf-8")).hexdigest()
REAL_STORE = os.path.join(AP, ".prompt_fingerprints.json")


def source(seeded):
    if not seeded:
        return SRC
    if SRC.count(NEW_START) != 1 or SRC.count(NEW_END) != 1:
        raise RuntimeError("graine introuvable")
    a = SRC.index(NEW_START)
    b = SRC.index(NEW_END) + len(NEW_END)
    return SRC[:a] + OLD_BLOCK + SRC[b:]


def world(seeded, tag):
    """Copie jetable : (tmp, ap, module charge depuis la copie, items a consignes distinctes)."""
    tmp = tempfile.mkdtemp(prefix="fp-lock-census-")
    ap = os.path.join(tmp, "proj", ".autoport")
    os.makedirs(os.path.join(ap, "lib")); os.makedirs(os.path.join(ap, "prompts"))
    shutil.copy(os.path.join(AP, "lib", "secret_mask.py"), os.path.join(ap, "lib"))
    shutil.copy(os.path.join(AP, "backlog.yaml"), os.path.join(ap, "backlog.yaml"))
    with open(os.path.join(ap, "lib", "backlog.py"), "w", encoding="utf-8") as fh:
        fh.write(source(seeded))
    spec = ilu.spec_from_file_location("backlog_fplock_%s" % tag, os.path.join(ap, "lib", "backlog.py"))
    M = ilu.module_from_spec(spec); spec.loader.exec_module(M)
    seen, items = set(), []
    for it in M.load(os.path.join(ap, "backlog.yaml")).items:
        base = os.path.basename(it.get("prompt") or ("prompts/item-%s.md" % it["id"]))
        if it.get("id") and base not in seen:
            seen.add(base); items.append(it)
        if len(items) == N:
            break
    return tmp, ap, M, items


def race(seeded, widen, tag):
    """Rend (pertes nommees, secondes, enfants en echec)."""
    tmp, ap, M, items = world(seeded, tag)
    try:
        if len(items) != N:
            raise RuntimeError("seulement %d consignes distinctes" % len(items))
        store = os.path.join(ap, ".prompt_fingerprints.json")
        shutil.copy(REAL_STORE, store)
        before = json.load(open(store, encoding="utf-8"))
        if widen:
            orig = M._atomic_write
            def slow(p, t, _o=orig):
                if os.path.basename(os.fspath(p)) == ".prompt_fingerprints.json":
                    time.sleep(WIDEN_S)
                return _o(p, t)
            M._atomic_write = slow
        ctx = mp.get_context("fork")
        bar = ctx.Barrier(N)
        def child(i):
            try:
                bar.wait(timeout=60)
                M.write_prompt(items[i], ap)
            except BaseException:  # noqa: BLE001
                os._exit(3)
            os._exit(0)
        t0 = time.time()
        procs = [ctx.Process(target=child, args=(i,)) for i in range(N)]
        for p in procs:
            p.start()
        for p in procs:
            p.join(120)
        secs = time.time() - t0
        failed = sum(1 for p in procs if p.exitcode != 0)
        after = json.load(open(store, encoding="utf-8"))
        lost, mine = [], set()
        for it in items:
            rel = it.get("prompt") or ("prompts/item-%s.md" % it["id"])
            base = os.path.basename(rel); mine.add(base)
            if after.get(base) != sha(open(os.path.join(ap, rel), encoding="utf-8").read()):
                lost.append(it["id"])
        lost += ["pre:%s" % k for k in before if k not in mine and after.get(k) != before[k]]
        return lost, secs, failed
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def corrupt(seeded, tag):
    """1 si un magasin illisible a ete REECRIT par write_prompt."""
    tmp, ap, M, items = world(seeded, tag)
    try:
        store = os.path.join(ap, ".prompt_fingerprints.json")
        junk = '{"illisible": '
        open(store, "w", encoding="utf-8").write(junk)
        M.write_prompt(items[0], ap)
        return int(open(store, encoding="utf-8").read() != junk)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def arm(label, fn):
    try:
        return fn()
    except Exception as e:  # noqa: BLE001
        unmeasured.append("%s:%s" % (label, type(e).__name__)); print("%s: %r" % (label, e), file=sys.stderr)
        return None


# ================================================================================== R : COURSE ==
R = 0
for widen, key in ((False, "natural"), (True, "widened")):
    r = arm("R-" + key, lambda: race(False, widen, "ship_" + key))
    if r is not None:
        lost, secs, failed = r
        pub("prompt_fingerprints_race_%s_writers" % key, N)
        pub("prompt_fingerprints_race_%s_lost" % key, len(lost))
        pub("prompt_fingerprints_race_%s_named" % key, ",".join(lost) or "aucun")
        pub("prompt_fingerprints_race_%s_s" % key, "%.2f" % secs)
        pub("prompt_fingerprints_race_%s_children_failed" % key, failed)
        R += len(lost) + failed
pub("prompt_fingerprints_race_window_ms", int(WIDEN_S * 1000))

# C+race : le code d'AVANT doit perdre sous la fenetre elargie ; la naturelle est informative
try:
    lost, secs, failed = race(True, True, "seed_widened")
    pub("prompt_fingerprints_ctl_race_lost", len(lost))
    pub("prompt_fingerprints_ctl_race_named", ",".join(lost[:8]) or "aucun")
    if not lost or failed:
        dead.append("C+race")
except Exception as e:  # noqa: BLE001
    dead.append("C+race:%s" % type(e).__name__); print("C+race: %r" % e, file=sys.stderr)
try:
    lost, _, _ = race(True, False, "seed_natural")
    pub("prompt_fingerprints_ctl_race_natural_lost", len(lost))
except Exception as e:  # noqa: BLE001
    pub("prompt_fingerprints_ctl_race_natural_lost", "erreur:%s" % type(e).__name__)


# =============================================================================== K : ILLISIBLE ==
k = arm("K", lambda: corrupt(False, "ship_corrupt"))
K = k or 0
pub("prompt_fingerprints_corrupt_store_overwritten", "inconnu" if k is None else k)
try:
    c = corrupt(True, "seed_corrupt")
    pub("prompt_fingerprints_ctl_corrupt_overwritten", c)
    if c != 1:
        dead.append("C+corrupt")
except Exception as e:  # noqa: BLE001
    dead.append("C+corrupt:%s" % type(e).__name__); print("C+corrupt: %r" % e, file=sys.stderr)


# ============================================================================ S : CLOS PERIMES ==
S = 0
try:
    b = B.load()
    # Un fichier de consigne PARTAGE par plusieurs items ne peut etre a jour que pour l'un d'eux : le refabriquer
    # pour l'autre le perime pour le premier. Il n'est perime que s'il n'est a jour pour AUCUN de ses items.
    by_file, states = {}, {}
    for it in b.items:
        by_file.setdefault(it.get("prompt") or ("prompts/item-%s.md" % it["id"]), []).append(it)
        states[it["id"]] = B.prompt_state(it)
    shared = {f: its for f, its in by_file.items() if len(its) > 1}
    fresh_file = {f for f, its in by_file.items() if any(states[i["id"]] == "a-jour" for i in its)}
    stale = [it["id"] for it in b.items if it.get("status") in CLOSED and states[it["id"]] == "perime"
             and (it.get("prompt") or ("prompts/item-%s.md" % it["id"])) not in fresh_file]
    pub("prompt_shared_files", len(shared))
    pub("prompt_shared_named", ",".join("%s:%s" % (os.path.basename(f), "+".join(i["id"] for i in its))
                                        for f, its in shared.items()) or "aucun")
    pub("prompt_closed_items", sum(1 for it in b.items if it.get("status") in CLOSED))
    pub("prompt_closed_stale", len(stale))
    pub("prompt_closed_stale_named", ",".join(stale) or "aucun")
    S = len(stale)
except Exception as e:  # noqa: BLE001
    unmeasured.append("S:%s" % type(e).__name__); print("S: %r" % e, file=sys.stderr)


# ======================================================================= M : CONTROLE NEGATIF ==
M_ = 0
try:
    first = subprocess.run(["git", "log", "--format=%H", "--reverse", "--fixed-strings",
                            "--grep=[autoport/harness-prompt-fingerprint-store-locked]"],
                           capture_output=True, text=True, check=True).stdout.split()
    anchor = subprocess.run(["git", "rev-parse", (first[0] + "^") if first else "HEAD"],
                            capture_output=True, text=True, check=True).stdout.strip()
    pub("prompt_manual_anchor", anchor[:10])
    by_id = {it["id"]: it for it in B.load().items}
    bad = []
    for iid in MANUAL:
        it = by_id[iid]
        rel = ".autoport/" + (it.get("prompt") or ("prompts/item-%s.md" % iid))
        blob = subprocess.run(["git", "show", "%s:%s" % (anchor, rel)], capture_output=True, check=True).stdout
        if open(rel, "rb").read() != blob:
            bad.append("%s:octets" % iid)
        st = B.prompt_state(it)
        if st != "a-la-main":
            bad.append("%s:%s" % (iid, st))
    pub("prompt_manual_checked", len(MANUAL))
    pub("prompt_manual_changed", len(bad))
    pub("prompt_manual_changed_named", ",".join(bad) or "aucun")
    M_ = len(bad)
except Exception as e:  # noqa: BLE001
    unmeasured.append("M:%s" % type(e).__name__); print("M: %r" % e, file=sys.stderr)

pub("prompt_fingerprints_unmeasured", len(unmeasured))
pub("prompt_fingerprints_unmeasured_named", ",".join(unmeasured) or "aucun")
pub("prompt_fingerprints_dead_controls", len(dead))
pub("prompt_fingerprints_dead_named", ",".join(dead) or "aucun")
pub("prompt_fingerprints_lost", R + K + S + M_ + len(unmeasured) + len(dead))
for k_, v in OUT.items():
    print("%s=%s" % (k_, v))
PY
