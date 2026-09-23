#!/usr/bin/env bash
# census/harness-supervisor-relay-command.sh — LE VERDICT DE L'ITEM.
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`) ; sa sortie cle=valeur
# rejoint proof.txt par la moisson. Il n'ecrit rien dans le vrai backlog.
#
#   unlabeled_relays  = retours de l'owner dates depuis la bascule (76594a90bc, `via` garde a la
#                       recopie) qui n'ont PAS de `via`, sur le vrai backlog, NOMMES
#                       + chaque CONTROLE qui echoue (un zero obtenu par un compteur aveugle ou
#                       une commande qui n'etiquette pas serait un faux vert).
#   CONTROLES, sur une COPIE jetable du backlog, par la vraie commande `autoport feedback` :
#     label      la commande ecrit `via: {source: supervisor, by: autoport feedback}` et le
#                compteur reste a sa base (NEGATIF : cas sain a 0 de plus)
#     prompt     la consigne absente est fabriquee et porte les mots
#     hand       une consigne ecrite a la main n'est pas touchee
#     dup        la meme phrase le meme jour n'est pas recopiee deux fois
#     unknown    item inconnu : rc 1, backlog intact
#     seeded     un retour SANS `via` seme aujourd'hui rougit le compteur de 1 et est NOMME (POSITIF)
#     window     un retour sans `via` d'avant la bascule n'entre pas dans la population
#     copy       la reprise reconnait une copie d'un commentaire Linear et reprend son `via`
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "unlabeled_relays=-1"; exit 1; }
cd "$ROOT" || exit 1
mkdir -p "$HOME/.autoport-tmp"
export TMPDIR="${TMPDIR:-$HOME/.autoport-tmp}"

python3 - "$ROOT" <<'PY'
import datetime, hashlib, os, shutil, subprocess, sys, tempfile

root = sys.argv[1]
AP = os.path.join(root, ".autoport")
sys.path.insert(0, os.path.join(AP, "lib"))
import backlog as B
import relay as R

ID = "harness-supervisor-relay-command"
TODAY = datetime.date.today().isoformat()

# ------------------------------------------------------------------ le vrai backlog
real = R.census(B.load().items)
n_real = len(real["unlabeled"])
print("relay_unlabeled_real=%d" % n_real)
print("relay_unlabeled_named=%s" % (",".join(R.name(e) for e in real["unlabeled"]) or "-"))
print("relay_population=%d" % real["population"])
print("relay_feedback_total=%d" % real["total"])
print("relay_window_since=%s" % R.BASCULE_DAY)
print("relay_bascule_commit=%s" % R.BASCULE_COMMIT)
for o in ("linear", "supervisor", "move", "deleted"):
    print("relay_origin_%s=%d" % (o, real["origins"].get(o, 0)))
autres = sum(v for k, v in real["origins"].items()
             if k not in ("linear", "supervisor", "move", "deleted", "unlabeled", "malformed"))
print("relay_origin_other=%d" % autres)
print("relay_supervisor_by_command=%d" % real["by_command"])

# ------------------------------------------------------------------ controles, copie jetable
ctl = {}
tmp = tempfile.mkdtemp(prefix="relay-census-")
try:
    T = os.path.join(tmp, "backlog.yaml")
    shutil.copyfile(os.path.join(AP, "backlog.yaml"), T)
    os.makedirs(os.path.join(tmp, ".autoport"))   # vestige : l'empreinte suit l'ap_dir (backlog._fp_path), plus le cwd
    os.makedirs(os.path.join(tmp, "prompts"))
    cli = [sys.executable, os.path.join(AP, "autoport"), "--file", T, "feedback"]
    run = lambda args: subprocess.run(cli + args, cwd=tmp, capture_output=True, text=True, timeout=120)
    base = len(R.census(B.load(T).items)["unlabeled"])

    words = "controle relais %s" % os.getpid()
    r = run([ID, words])
    b = B.load(T)
    mine = [fb for fb in b.get(ID).get("owner_feedback") or [] if fb.get("text") == words]
    c = R.census(b.items)
    ctl["label"] = int(r.returncode == 0 and len(mine) == 1
                       and (mine[0].get("via") or {}).get("source") == "supervisor"
                       and (mine[0].get("via") or {}).get("by") == R.BY
                       and str(mine[0].get("date")) == TODAY
                       and len(c["unlabeled"]) == base and c["by_command"] >= 1)
    pp = os.path.join(tmp, b.get(ID).get("prompt") or "prompts/item-%s.md" % ID)
    ctl["prompt"] = int(os.path.exists(pp) and words in open(pp, encoding="utf-8").read())

    other = next(it for it in b.items if it.get("id") != ID and it.get("prompt"))
    hp = os.path.join(tmp, other["prompt"])
    os.makedirs(os.path.dirname(hp), exist_ok=True)
    with open(hp, "w", encoding="utf-8") as fh:
        fh.write("consigne ecrite a la main\n")
    avant = hashlib.sha256(open(hp, "rb").read()).hexdigest()
    r2 = run([other["id"], words + " main"])
    ctl["hand"] = int(r2.returncode == 0 and "A LA MAIN" in r2.stdout
                      and hashlib.sha256(open(hp, "rb").read()).hexdigest() == avant)

    r3 = run([ID, words])
    n_mine = sum(fb.get("text") == words for fb in B.load(T).get(ID).get("owner_feedback") or [])
    ctl["dup"] = int(r3.returncode == 0 and n_mine == 1)

    avant_b = hashlib.sha256(open(T, "rb").read()).hexdigest()
    r4 = run(["item-qui-n-existe-pas", words])
    ctl["unknown"] = int(r4.returncode == 1
                         and hashlib.sha256(open(T, "rb").read()).hexdigest() == avant_b)

    b = B.load(T)
    seme = "SEME relais sans etiquette %s" % os.getpid()
    b.add_owner_feedback(ID, TODAY, seme)                     # l'ecriture A LA MAIN, sans `via`
    c = R.census(B.load(T).items)
    ctl["seeded"] = int(len(c["unlabeled"]) == base + 1
                        and R.name((ID, TODAY, seme)) in [R.name(e) for e in c["unlabeled"]])

    b = B.load(T)
    pop = R.census(b.items)["population"]
    b.add_owner_feedback(ID, "2026-09-22", "SEME avant la bascule %s" % os.getpid())
    c = R.census(B.load(T).items)
    ctl["window"] = int(c["population"] == pop and len(c["unlabeled"]) == base + 1)

    b = B.load(T)
    via = {"comment": "c-controle", "ticket": "t-controle", "at": "2026-09-23T10:00:00Z"}
    copie = "SEME copie d'un commentaire %s" % os.getpid()
    b.add_owner_feedback(other["id"], TODAY, copie, via=via)
    b.add_owner_feedback(ID, TODAY, copie)
    res = {R.name(e): (cause, v) for e, cause, v, _n in R.backfill(B.load(T), apply=True, root=root)}
    cause, v = res.get(R.name((ID, TODAY, copie)), ("absent", None))
    fin = R.census(B.load(T).items)
    ctl["copy"] = int(cause == "copie" and (v or {}).get("comment") == "c-controle"
                      and R.name((ID, TODAY, copie)) not in [R.name(e) for e in fin["unlabeled"]]
                      and R.name((ID, TODAY, seme)) in [R.name(e) for e in fin["unlabeled"]])
except Exception as exc:  # noqa: BLE001 — un controle qui plante est un controle rouge
    print("relay_control_error=%s" % type(exc).__name__)
finally:
    shutil.rmtree(tmp, ignore_errors=True)

NOMS = ("label", "prompt", "hand", "dup", "unknown", "seeded", "window", "copy")
for k in NOMS:
    print("relay_ctl_%s=%d" % (k, ctl.get(k, 0)))
failed = [k for k in NOMS if not ctl.get(k)]
print("relay_controls=%d" % len(NOMS))
print("relay_controls_failed=%d" % len(failed))
print("relay_controls_failed_list=%s" % (",".join(failed) or "-"))
print("unlabeled_relays=%d" % (n_real + len(failed)))
PY
