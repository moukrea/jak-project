#!/usr/bin/env bash
# census/harness-owner-feedback-write-never-loses-a-return.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `owner_feedback_lost_on_race`.
# Il n'ecrit rien dans le vrai backlog : tout se joue sur des COPIES jetables.
#
# LE DEFAUT (signale par quatre workers, owner « traite le tout » le 23/09) : `Backlog.add_owner_feedback`
# (et `validate`) reposaient la liste owner_feedback LUE EN MEMOIRE — et le statut lu en memoire — via
# `set_status`. Un retour ajoute par un autre ecrivain (synchro Linear, `autoport feedback`) entre le
# chargement et l'ecriture etait efface. Desormais `_append_owner_feedback` relit l'item sous le verrou
# et AJOUTE ; `set_status(owner_feedback=...)` est refuse.
#
# CE QU'IL MESURE — `owner_feedback_lost_on_race` = somme de :
#   L   retours PERDUS par le code livre, sur les courses FABRIQUEES (ecrivain perime + ecrivain frais) :
#         sync_vs_sync      deux synchros Linear, la premiere chargee avant l'ecriture de la seconde
#         relay_then_sync   `autoport feedback` (relay) ecrit, puis une synchro chargee AVANT ecrit
#         sync_then_relay   l'inverse (relay relit sous verrou : reference)
#         validate_stale    feu vert de l'owner (validate) par un ecrivain perime
#         concurrent        4 processus charges puis lances ensemble (barriere), 3 ajouts chacun
#         sequential        NEGATIF : aucun recouvrement, chargement frais a chaque ajout -> 0
#   S   statut RAMENE en arriere par un ajout perime (status_kept)
#   W   appels `set_status(..., owner_feedback=...)` dans le code du harnais (AST, noeud d'APPEL)
#   R   `set_status(owner_feedback=...)` non refuse a l'execution
#   D   CONTROLES MORTS : le defaut SEME (l'ancienne ecriture : liste et statut tenus en memoire, reposes
#       sous le verrou) doit perdre dans sync_vs_sync, relay_then_sync, validate_stale, ramener le statut
#       dans status_kept, et l'AST doit trouver l'appel seme. Chaque controle qui ne rougit pas compte 1.
#   INCONNU = DEFAUT : un scenario qui leve compte 1 et est nomme.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "owner_feedback_lost_on_race=99"; exit 1; }
cd "$ROOT" || exit 1
mkdir -p "$HOME/.autoport-tmp"
export TMPDIR="${TMPDIR:-$HOME/.autoport-tmp}"

python3 - "$ROOT" <<'PY'
import ast, multiprocessing as mp, os, shutil, sys, tempfile

root = sys.argv[1]
AP = os.path.join(root, ".autoport")
sys.path.insert(0, os.path.join(AP, "lib"))
import backlog as B
import relay as R

ID = "harness-owner-feedback-write-never-loses-a-return"
D = "2026-09-23"
OUT = {}
unknown = []


# ----------------------------------------------------------------- le defaut SEME (ancienne ecriture)
def _seeded_write(self, item_id, fb, status, **fields):
    """Ce que faisait `set_status(item_id, it.get("status"), owner_feedback=fb)` : verrou, relecture,
    puis on repose la liste et le statut TENUS EN MEMOIRE."""
    with B._Lock(self.path):
        fresh = B._read(self.path)
        t = next(x for x in fresh["items"] if x.get("id") == item_id)
        t["status"] = status
        t["owner_feedback"] = fb
        for k, v in fields.items():
            t[k] = v
        B._atomic_write(self.path, B._dump(fresh))
    self.items = fresh["items"]
    return self.get(item_id)


def seeded_add(self, item_id, date, text, via=None):
    it = self.get(item_id)
    fb = list(it.get("owner_feedback") or [])
    e = {"date": date, "text": text}
    if via:
        e["via"] = dict(via)
    fb.append(e)
    return _seeded_write(self, item_id, fb, it.get("status"))


def seeded_validate(self, item_id, text, date=None, sha=None, via=None):
    it = self.get(item_id)
    fb = list(it.get("owner_feedback") or [])
    if not any(e.get("text") == text for e in fb):
        fb.append({"date": date, "text": text})
    return _seeded_write(self, item_id, fb, "validated",
                         owner_ok={"date": date, "text": text, "build_sha": sha}, priority=None)


SHIPPED = (B.Backlog.add_owner_feedback, B.Backlog.validate)


def arm(seeded):
    if seeded:
        B.Backlog.add_owner_feedback, B.Backlog.validate = seeded_add, seeded_validate
    else:
        B.Backlog.add_owner_feedback, B.Backlog.validate = SHIPPED


# ----------------------------------------------------------------- scenarios, copie jetable
def fresh_copy():
    tmp = tempfile.mkdtemp(prefix="fb-race-")
    T = os.path.join(tmp, "backlog.yaml")
    shutil.copyfile(os.path.join(AP, "backlog.yaml"), T)
    os.makedirs(os.path.join(tmp, "prompts"))
    os.makedirs(os.path.join(tmp, ".autoport"))
    return tmp, T


def present(T, texts):
    fbs = B.load(T).get(ID).get("owner_feedback") or []
    have = {fb.get("text") for fb in fbs if isinstance(fb, dict)}
    return [t for t in texts if t in have]


def via(c):
    return {"comment": "census-%s" % c, "ticket": "census", "at": D + "T00:00:00Z"}


def sc_sync_vs_sync(T, tag):
    a = B.load(T)
    B.load(T).add_owner_feedback(ID, D, tag + "-1", via=via(tag + "1"))
    a.add_owner_feedback(ID, D, tag + "-2", via=via(tag + "2"))
    return [tag + "-1", tag + "-2"], 2


def sc_relay_then_sync(T, tag):
    a = B.load(T)
    R.relay(B.load(T), ID, tag + "-1", date=D)
    a.add_owner_feedback(ID, D, tag + "-2", via=via(tag + "2"))
    return [tag + "-1", tag + "-2"], 2


def sc_sync_then_relay(T, tag):
    stale = B.load(T)
    B.load(T).add_owner_feedback(ID, D, tag + "-1", via=via(tag + "1"))
    R.relay(stale, ID, tag + "-2", date=D)
    return [tag + "-1", tag + "-2"], 2


def sc_validate_stale(T, tag):
    a = B.load(T)
    B.load(T).add_owner_feedback(ID, D, tag + "-1", via=via(tag + "1"))
    a.validate(ID, tag + "-2", date=D, sha="census")
    return [tag + "-1", tag + "-2"], 2


def sc_sequential(T, tag):
    for i in range(3):
        B.load(T).add_owner_feedback(ID, D, "%s-%d" % (tag, i), via=via("%s%d" % (tag, i)))
    return ["%s-%d" % (tag, i) for i in range(3)], 3


P, M = 4, 3


def _worker(T, tag, p, barrier):
    b = B.load(T)
    barrier.wait()
    for i in range(M):
        b.add_owner_feedback(ID, D, "%s-%d-%d" % (tag, p, i), via=via("%s%d%d" % (tag, p, i)))
    os._exit(0)


def sc_concurrent(T, tag):
    ctx = mp.get_context("fork")
    barrier = ctx.Barrier(P)
    procs = [ctx.Process(target=_worker, args=(T, tag, p, barrier)) for p in range(P)]
    for pr in procs:
        pr.start()
    for pr in procs:
        pr.join(300)
    bad = [pr.exitcode for pr in procs if pr.exitcode != 0]
    if bad:
        raise RuntimeError("ecrivain(s) morts : %s" % bad)
    return ["%s-%d-%d" % (tag, p, i) for p in range(P) for i in range(M)], P * M


SCEN = [("sync_vs_sync", sc_sync_vs_sync), ("relay_then_sync", sc_relay_then_sync),
        ("sync_then_relay", sc_sync_then_relay), ("validate_stale", sc_validate_stale),
        ("concurrent", sc_concurrent), ("sequential", sc_sequential)]
MUST_REDDEN = ("sync_vs_sync", "relay_then_sync", "validate_stale")


def status_kept(T):
    """Rend 1 si un ajout perime ramene le statut change entre-temps par un autre ecrivain."""
    a = B.load(T)
    B.load(T).set_status(ID, "blocked", block_reason="census : statut pose par un autre ecrivain")
    a.add_owner_feedback(ID, D, "status-kept", via=via("status"))
    return int(B.load(T).get(ID).get("status") != "blocked")


cwd0 = os.getcwd()
res = {}
for seeded in (False, True):
    arm(seeded)
    side = "seeded" if seeded else "shipped"
    for name, fn in SCEN + [("status_kept", None)]:
        tmp, T = fresh_copy()
        os.chdir(tmp)                       # l'empreinte de write_prompt suit l'ap_dir de la consigne (backlog._fp_path), plus le cwd
        try:
            if fn is None:
                res[(side, name)] = ("status", status_kept(T))
            else:
                exp, n = fn(T, "%s-%s-%d" % (side, name, os.getpid()))
                res[(side, name)] = ("lost", n - len(present(T, exp)), n)
        except Exception as exc:            # noqa: BLE001 — INCONNU = DEFAUT
            res[(side, name)] = ("error", repr(exc)[:160])
            unknown.append("%s:%s" % (side, name))
        finally:
            os.chdir(cwd0)
            shutil.rmtree(tmp, ignore_errors=True)
arm(False)

lost = expected = 0
for name, _ in SCEN:
    r = res[("shipped", name)]
    if r[0] == "lost":
        OUT["owner_feedback_race_%s_lost" % name] = r[1]
        OUT["owner_feedback_race_%s_expected" % name] = r[2]
        lost += r[1]
        expected += r[2]
    rs = res[("seeded", name)]
    if rs[0] == "lost":
        OUT["owner_feedback_race_seeded_%s_lost" % name] = rs[1]
r = res[("shipped", "status_kept")]
status_rev = r[1] if r[0] == "status" else 0
OUT["owner_feedback_race_status_reverted"] = status_rev
rs = res[("seeded", "status_kept")]
OUT["owner_feedback_race_seeded_status_reverted"] = rs[1] if rs[0] == "status" else -1

# ----------------------------------------------------------------- R : le refus au point d'ecriture
tmp, T = fresh_copy()
try:
    try:
        B.load(T).set_status(ID, "open", owner_feedback=[])
        refused = 0
    except B.BacklogError:
        refused = 1
    except Exception as exc:  # noqa: BLE001
        refused = 0
        unknown.append("refus:%r" % exc)
finally:
    shutil.rmtree(tmp, ignore_errors=True)
OUT["owner_feedback_race_setstatus_refused"] = refused


# ----------------------------------------------------------------- W : ecrivains de liste en memoire (AST)
def writers(src, fname):
    out = []
    for node in ast.walk(ast.parse(src, fname)):
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                and node.func.attr == "set_status"
                and any(k.arg == "owner_feedback" for k in node.keywords)):
            out.append("%s:%d" % (os.path.relpath(fname, root), node.lineno))
    return out


scanned, found = 0, []
for dp, dns, fns in os.walk(AP):
    rel = os.path.relpath(dp, AP)
    if rel.split(os.sep)[0] in ("archive", "reports", "logs", "tests", "owner-feedback", ".git"):
        dns[:] = []
        continue
    for f in fns:
        if f.endswith(".py") or (rel == "." and f == "autoport"):
            p = os.path.join(dp, f)
            try:
                found += writers(open(p, encoding="utf-8").read(), p)
                scanned += 1
            except (SyntaxError, UnicodeDecodeError):
                pass
seed_src = "b.set_status('x', it.get('status'), owner_feedback=fb)\n"
seed_hit = len(writers(seed_src, os.path.join(AP, "SEME.py")))
OUT["owner_feedback_race_static_files"] = scanned
OUT["owner_feedback_race_static_writers"] = len(found)
OUT["owner_feedback_race_static_named"] = ",".join(found) or "-"

# ----------------------------------------------------------------- D : controles positifs
dead, named = [], []
for name in MUST_REDDEN:
    rs = res[("seeded", name)]
    if rs[0] == "lost" and rs[1] > 0:
        named.append(name)
    else:
        dead.append(name)
if OUT["owner_feedback_race_seeded_status_reverted"] == 1:
    named.append("status_kept")
else:
    dead.append("status_kept")
if seed_hit == 1:
    named.append("static_writer")
else:
    dead.append("static_writer")
OUT["owner_feedback_race_seeded_named"] = ",".join(named) or "-"
OUT["owner_feedback_race_seeded_total"] = sum(v[1] for (sd, _), v in res.items()
                                              if sd == "seeded" and v[0] in ("lost", "status"))
OUT["owner_feedback_race_dead_controls"] = len(dead)
OUT["owner_feedback_race_dead_named"] = ",".join(dead) or "-"
OUT["owner_feedback_race_negative_sequential_lost"] = OUT.get("owner_feedback_race_sequential_lost", -1)

# ----------------------------------------------------------------- verdict
OUT["owner_feedback_race_expected"] = expected
OUT["owner_feedback_race_lost_returns"] = lost
OUT["owner_feedback_race_unknown"] = len(unknown)
OUT["owner_feedback_race_unknown_named"] = ",".join(unknown) or "-"
for (side, name), r in sorted(res.items()):
    if r[0] == "error":
        print("# %s/%s : %s" % (side, name, r[1]), file=sys.stderr)
total = (lost + status_rev + len(found) + (1 - refused) + len(dead) + len(unknown))
for k, v in OUT.items():
    print("%s=%s" % (k, v))
print("owner_feedback_lost_on_race=%d" % total)
PY
