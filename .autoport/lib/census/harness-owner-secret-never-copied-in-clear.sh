#!/usr/bin/env bash
# census/harness-owner-secret-never-copied-in-clear.sh
#
# Lance par `lib/proof_run.sh` (crochet `lib/census/<item-id>.sh`). Publie `owner_secret_leaks`.
#
# LA CAUSE (17/09 -> 23/09) : le Client Secret Linear colle par l'owner en commentaire a ete recopie en
# clair par `pull_owner` dans logs/linear_sync.txt, backlog.yaml, .owner_sla.json, un prompt, deux journaux
# d'essai et 18 commits dont un pousse sur le depot PUBLIC. Correctif au point de production :
# `linear_sync.Linear.q` masque toute reponse (`lib/secret_mask.py`), le serialiseur du backlog efface les
# valeurs connues, et les hooks git `pre-commit` / `pre-push` refusent un secret connu ou une forme nommee.
#
# CE QU'IL MESURE — `owner_secret_leaks` = somme de :
#   F  occurrences d'un secret CONNU (~/.config/autoport/*.env|*.json) dans les fichiers : arbre de travail
#      (suivis + non suivis, `git grep --untracked`) UNION tout texte de .autoport/ (journaux, rapports,
#      etats, prompts, retours ; hors cgo-cache/ et dist/, binaires). Jamais la VALEUR : le nom et le fichier.
#   X  occurrences dans l'index (`--cached`) et dans l'arbre de HEAD.
#   M  hooks git absents ou etrangers (1 chacun).
#   INCONNU = DEFAUT : aucun secret connu charge, un balayage qui echoue -> 1 chacun.
#   C+ MORT = DEFAUT : chaque controle qui ne rend pas l'effet attendu -> 1 chacun.
# AVANT (publie, hors somme : l'historique public ne se reecrit pas, seule la rotation neutralise) :
#   commits de `git log --all` et `--remotes` (chemin .autoport) portant un secret connu, et ceux portant
#   une forme DEVINEE (prefixe ou contexte « secret ») — c'est ainsi que se voit le secret du 17/09, change
#   depuis par l'owner et donc absent de ~/.config.
# CONTROLES (secrets FABRIQUES, aleatoires, dans un dossier jetable ; AUTOPORT_SECRET_DIRS) :
#   C1 un commentaire owner fabrique passe par le VRAI `pull_owner` (vrai `Linear.q`, `s.post` remplace),
#      NON a blanc, sur une copie du backlog et un dossier de prompts jetables : aucun faux secret dans le
#      journal capture, le backlog ecrit, le prompt refabrique ; le masque est POSE (effet, pas inaction) ;
#      hash de commit (long et court), md5 d'APK, id d'item passent INTACTS (controle negatif).
#   C2 le serialiseur du backlog efface un secret connu entre par un autre chemin que Linear.
#   C3 le VRAI hook (celui de .git/hooks) dans un depot jetable : commit d'un secret connu REFUSE, commit
#      d'une forme nommee REFUSE, commit ordinaire ACCEPTE, push d'un commit force (--no-verify) REFUSE.
#   C4 le balayage `git grep` voit un secret seme dans le depot jetable (arbre et HEAD).
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "owner_secret_leaks=99"; exit 1; }
cd "$ROOT" || exit 1

python3 - <<'PY'
import copy, io, json, os, re, secrets, shutil, subprocess, sys, tempfile, time
from contextlib import redirect_stdout
from pathlib import Path
ROOT = Path.cwd()
sys.path.insert(0, '.autoport')
sys.path.insert(0, '.autoport/lib')
import secret_mask as S

OUT = {}
def pub(k, v): OUT[k] = str(v).replace(" ", "_")
unmeasured, dead = [], []
MASK = S.MASK
T0 = time.time()

# ================================================================== secrets CONNUS (reels) ==
REAL = S.known_secrets([Path.home() / ".config" / "autoport"])
pub("owner_secret_known", len(REAL))
pub("owner_secret_known_names", ",".join(n for n, _ in REAL) or "aucun")
if not REAL:
    unmeasured.append("aucun_secret_connu")
pats = "\n".join(v for _, v in REAL) + "\n"
name_of = {v: n for n, v in REAL}


def git(*a, inp=None, cwd=ROOT, env=None):
    return subprocess.run(["git", *a], input=inp, capture_output=True, text=True, errors="replace", cwd=cwd, env=env)


def grep_counts(args, cwd=ROOT, patterns=None):
    """`git grep -c -F -f -` -> ({chemin: n}, rc). rc 1 = rien trouve (normal)."""
    r = git("grep", "-c", "-F", "-I", "-f", "-", *args, inp=patterns if patterns is not None else pats, cwd=cwd)
    if r.returncode not in (0, 1):
        return None, r.returncode
    out = {}
    for line in r.stdout.splitlines():
        p, _, n = line.rpartition(":")
        if n.isdigit():
            out[p] = int(n)
    return out, r.returncode


# ============================================================ F : fichiers (arbre + .autoport) ==
files = {}
if REAL:
    wt, rc = grep_counts(["--untracked", "--", "."])
    if wt is None:
        unmeasured.append("git_grep_arbre_rc%d" % rc)
    else:
        files.update(wt)
    pub("owner_secret_scan_worktree_files", "echec" if wt is None else len(wt))
    EXCL = ("cgo-cache", "dist")
    r = subprocess.run(["grep", "-rIcF", "-f", "/dev/stdin", ".autoport"] + ["--exclude-dir=%s" % e for e in EXCL],
                       input=pats, capture_output=True, text=True, errors="replace")
    if r.returncode not in (0, 1):
        unmeasured.append("grep_autoport_rc%d" % r.returncode)
    for line in r.stdout.splitlines():
        p, _, n = line.rpartition(":")
        if n.isdigit() and int(n) > 0:
            files[p] = max(files.get(p, 0), int(n))
    pub("owner_secret_scan_autoport_excluded", "cgo-cache,dist,binaires")
F = sum(files.values())
pub("owner_secret_leaks_files", F)
pub("owner_secret_leak_paths", ",".join(sorted(files))[:400] or "aucun")

# ============================================================ X : index et HEAD ==
X = 0
if REAL:
    for label, args in (("cached", ["--cached", "--", "."]), ("head", ["HEAD", "--", "."])):
        c, rc = grep_counts(args)
        if c is None:
            unmeasured.append("git_grep_%s_rc%d" % (label, rc))
            pub("owner_secret_leaks_%s" % label, "echec")
        else:
            X += sum(c.values())
            pub("owner_secret_leaks_%s" % label, sum(c.values()))

# ============================================================ M : hooks git installes ==
common = git("rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip()
HOOKS = Path(common) / "hooks"
M = 0
for h in ("pre-commit", "pre-push"):
    dst, src = HOOKS / h, ROOT / ".autoport" / "hooks" / "git" / h
    ok = dst.exists() and dst.resolve() == src.resolve() and os.access(src, os.X_OK)
    pub("owner_secret_hook_%s" % h.replace("-", "_"), "installe" if ok else "ABSENT")
    M += 0 if ok else 1

# ============================================================ AVANT : historique ==
t = time.time()
remotes = set(git("rev-list", "--remotes").stdout.split())
known_b = [v.encode() for _, v in REAL]
PRE_B = re.compile(S.PREFIXED.pattern.encode())
hist = {"known": set(), "guess": set()}
# Le flux de `git log -p` (toutes branches, .autoport) est filtre EN C par `grep -F` : en-tetes de commit,
# valeurs connues, et amorces des formes devinees. Les motifs passent par un TUBE (/dev/fd), jamais par la
# ligne de commande : une commande se relit dans `ps`, et le harnais journalise des lignes de commande.
# Python ne voit que les lignes retenues et y applique les formes exactes.
cmd = ("set -o pipefail; git log --all -p -U0 --no-color --no-ext-diff --format=%x01%H -- .autoport "
       "| LC_ALL=C grep -a -F -f /dev/fd/3")
rfd, wfd = os.pipe()
seeds = "\x01\n" + "".join(v + "\n" for _, v in REAL) + "lin_api_\nlin_oauth_\nlin_wh_\nghp_\ngithub_pat_\nsk-\nAKIA\nxox\necret\nECRET\n"
os.write(wfd, seeds.encode()); os.close(wfd)
p = subprocess.Popen(["bash", "-c", cmd + " 3<&%d" % rfd], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                     cwd=ROOT, pass_fds=(rfd,))
os.close(rfd)
cur, nlines = None, 0
for raw in p.stdout:
    if raw.startswith(b"\x01"):
        cur = raw[1:].strip().decode(); continue
    if not raw.startswith(b"+") or raw.startswith(b"+++"):
        continue
    nlines += 1
    if any(k in raw for k in known_b):
        hist["known"].add(cur)
    if PRE_B.search(raw):
        hist["guess"].add(cur)
    elif b"ecret" in raw.lower():
        if S.mask(raw.decode("utf-8", "replace"), known=[])[1]:
            hist["guess"].add(cur)
rc_hist = p.wait()
if rc_hist not in (0, 1):  # 1 = grep n'a rien retenu
    unmeasured.append("git_log_rc%d" % rc_hist)
pub("owner_secret_history_scope", ".autoport")
pub("owner_secret_history_candidate_lines", nlines)
pub("owner_secret_history_known_commits_all", len(hist["known"]))
pub("owner_secret_history_known_commits_remotes", len(hist["known"] & remotes))
pub("owner_secret_history_guessed_commits_all", len(hist["guess"]))
pub("owner_secret_history_guessed_commits_remotes", len(hist["guess"] & remotes))
pub("owner_secret_history_s", int(time.time() - t))

# ============================================================ CONTROLES : secrets fabriques ==
SB = Path(tempfile.mkdtemp(prefix="secret-census-"))
try:
    def hexa():
        while True:
            v = secrets.token_hex(16)
            if re.search(r"[a-f]", v) and re.search(r"[0-9]", v):
                return v
    fake_api = "lin_api_" + re.sub(r"[^A-Za-z0-9]", "Q", secrets.token_urlsafe(30))
    fake_pw = "Pw9" + re.sub(r"[^A-Za-z0-9]", "Z", secrets.token_urlsafe(20))
    fake_oauth = "lin_oauth_" + secrets.token_hex(24)          # forme nommee, absente de l'env
    fake_ctx = hexa()                                           # contexte seul, absent de l'env
    cid, sha40, md5 = hexa(), secrets.token_hex(20), secrets.token_hex(16)
    cfg = SB / "config"; cfg.mkdir()
    (cfg / "fake.env").write_text("FAKE_API_KEY=%s\nPORTAL_PASSWORD=%s\nFAKE_CLIENT_ID=%s\n" % (fake_api, fake_pw, cid))
    os.environ["AUTOPORT_SECRET_DIRS"] = str(cfg)
    FAKES = {"connu_api": fake_api, "connu_mdp": fake_pw, "forme_oauth": fake_oauth, "contexte": fake_ctx}
    FAKES["identifiant_client"] = cid
    KEEP = {"commit": sha40, "commit_court": sha40[:10], "md5_apk": md5,
            "id_item": "perf-codegen-arm64-calls"}
    body = ("Voici l'appli.\nClient ID : %s\nClient Secret\n%s\ncle API : %s\nEt le jeton oauth %s\n"
            "mot de passe du portail %s\nRien a voir : commit %s (%s), md5 de l'APK %s, item perf-codegen-arm64-calls.") % (
        cid, fake_ctx, fake_api, fake_oauth, fake_pw, sha40, sha40[:10], md5)

    # ---- C1 : le VRAI pull_owner, non a blanc, en bac a sable ----
    c1 = []
    try:
        from lib import backlog as B
        import linear_sync as LS
        ap = SB / "ap"; (ap / "prompts").mkdir(parents=True)
        shutil.copy(ROOT / ".autoport" / "backlog.yaml", ap / "backlog.yaml")
        saved = (B.DEFAULT_PATH, B.AP, B._FINGERPRINTS)
        B.DEFAULT_PATH, B.AP, B._FINGERPRINTS = str(ap / "backlog.yaml"), str(ap), str(ap / ".prompt_fingerprints.json")
        IID = "harness-owner-secret-never-copied-in-clear"
        issue = {"id": "fake-issue-1", "archivedAt": None, "state": {"name": "In Progress"}, "labels": {"nodes": []},
                 "comments": {"nodes": [{"id": "fake-comment-1", "body": body, "createdAt": "2099-01-01T00:00:00.000Z",
                                         "user": {"id": "owner-u1", "app": False}, "botActor": None, "reactions": []}]}}

        class Resp:
            status_code = 200
            def __init__(self, d): self._d = d
            def json(self): return copy.deepcopy(self._d)
        L = LS.Linear({"mode": "owner", "key": "fausse-cle", "bearer": False})
        posted = []
        def fake_post(url, json=None, timeout=None):
            posted.append((json or {}).get("query", "")[:40])
            return Resp({"data": {"issues": {"nodes": [issue]}}})
        L.s.post = fake_post
        L.s.get = lambda *a, **k: (_ for _ in ()).throw(RuntimeError("aucun telechargement attendu"))
        mp = {"_owner": {"user_id": "owner-u1"},
              IID: {"issue_id": "fake-issue-1", "identifier": "JAK-0", "url": "", "last_state": "In Progress",
                    "hash": "", "pulled_at": "1970-01-01T00:00:00Z"}}
        buf = io.StringIO()
        with redirect_stdout(buf):
            pulled = LS.pull_owner(L, B.load(), mp, {}, False)
        journal = buf.getvalue()
        blt = (ap / "backlog.yaml").read_text()
        it = B.load().get(IID)
        fb = (it.get("owner_feedback") or [])[-1] if it else {}
        stored = fb.get("text", "") if isinstance(fb, dict) else ""
        prompt = ap / (it.get("prompt") or ("prompts/item-%s.md" % IID))
        ptxt = prompt.read_text() if prompt.exists() else ""
        pub("owner_secret_c1_pulled", pulled)
        pub("owner_secret_c1_queries", len(posted))
        pub("owner_secret_c1_prompt_written", int(bool(ptxt)))
        pub("owner_secret_c1_masks_stored", stored.count(MASK))
        leaks = {}
        for where, txt in (("journal", journal), ("backlog", blt), ("prompt", ptxt)):
            for k, v in FAKES.items():
                if v in txt:
                    leaks.setdefault(where, []).append(k)
        pub("owner_secret_c1_fake_leaks", sum(len(x) for x in leaks.values()))
        pub("owner_secret_c1_fake_leak_where", ";".join("%s:%s" % (w, ",".join(k)) for w, k in leaks.items()) or "aucun")
        lost = [k for k, v in KEEP.items() if v not in stored]
        pub("owner_secret_c1_kept_intact", "%d/%d" % (len(KEEP) - len(lost), len(KEEP)))
        pub("owner_secret_c1_masked_wrongly", ",".join(lost) or "aucun")
        if pulled != 1 or not stored: c1.append("retour_non_tire")
        if leaks: c1.append("fuite")
        if stored.count(MASK) < len(FAKES): c1.append("masque_absent")
        if lost: c1.append("negatif_masque")
        if not ptxt: c1.append("prompt_non_refabrique")
        elif MASK not in ptxt: c1.append("prompt_sans_masque")

        # ---- C2 : le serialiseur du backlog, par un autre chemin que Linear ----
        bl = B.load()
        bl.add_owner_feedback(IID, "2099-01-02", "colle a la main : %s" % fake_pw)
        c2_ok = fake_pw not in (ap / "backlog.yaml").read_text() and MASK in (ap / "backlog.yaml").read_text()
        pub("owner_secret_c2_backlog_scrubbed", int(c2_ok))
        if not c2_ok: dead.append("c2_serialiseur")
        B.DEFAULT_PATH, B.AP, B._FINGERPRINTS = saved
    except Exception as e:  # noqa: BLE001
        c1.append("exception_%s" % type(e).__name__)
        pub("owner_secret_c1_error", str(e)[:120])
    pub("owner_secret_c1_verdict", ",".join(c1) or "ok")
    if c1: dead.append("c1_pull_owner")

    # ---- C3 / C4 : le VRAI hook, dans un depot jetable ----
    c3 = []
    repo, bare = SB / "repo", SB / "remote.git"
    env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", HOME=str(SB), GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t",
               GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t", AUTOPORT_SECRET_DIRS=str(cfg))
    g = lambda *a: subprocess.run(["git", "-c", "core.hooksPath=%s" % HOOKS, "-c", "commit.gpgsign=false", *a],
                                  cwd=repo, env=env, capture_output=True, text=True, errors="replace")
    repo.mkdir(); subprocess.run(["git", "init", "-q", "--bare", str(bare)], env=env, capture_output=True)
    g("init", "-q", "-b", "main"); g("remote", "add", "origin", str(bare))
    (repo / "ok.txt").write_text("commit %s md5 %s item perf-codegen-arm64-calls\n" % (sha40, md5))
    g("add", "ok.txt"); r = g("commit", "-q", "-m", "ordinaire")
    pub("owner_secret_c3_ordinary_commit_rc", r.returncode)
    if r.returncode != 0: c3.append("ordinaire_refuse")
    base = g("rev-parse", "HEAD").stdout.strip()
    for label, content in (("connu", "cle %s\n" % fake_api), ("forme", "jeton %s\n" % fake_oauth)):
        (repo / ("s-%s.txt" % label)).write_text(content)
        g("add", "s-%s.txt" % label); r = g("commit", "-q", "-m", label)
        moved = g("rev-parse", "HEAD").stdout.strip() != base
        pub("owner_secret_c3_%s_commit_rc" % label, r.returncode)
        if r.returncode == 0 or moved: c3.append("%s_accepte" % label)
        if any(v in r.stderr for v in FAKES.values()): c3.append("%s_valeur_imprimee" % label)
        if label == "connu":
            named = int("FAKE_API_KEY" in r.stderr)
            pub("owner_secret_c3_refusal_names_key", named)
            if not named: c3.append("refus_muet")
        g("reset", "-q", "HEAD", "--", "s-%s.txt" % label); (repo / ("s-%s.txt" % label)).unlink()
    r = g("push", "-q", "origin", "main")
    if r.returncode != 0: c3.append("push_ordinaire_refuse")
    (repo / "force.txt").write_text("cle %s\n" % fake_api)
    g("add", "force.txt"); g("commit", "-q", "--no-verify", "-m", "force")
    r = g("push", "-q", "origin", "main")
    remote_head = subprocess.run(["git", "--git-dir", str(bare), "rev-parse", "main"], capture_output=True, text=True).stdout.strip()
    pub("owner_secret_c3_push_rc", r.returncode)
    if r.returncode == 0 or remote_head != base: c3.append("push_accepte")
    pub("owner_secret_c3_verdict", ",".join(c3) or "ok")
    if c3: dead.append("c3_hook")
    # C4 : le balayage voit ce qu'on seme
    wt, _ = grep_counts(["--untracked", "--", "."], cwd=repo, patterns=fake_api + "\n")
    hd, _ = grep_counts(["HEAD", "--", "."], cwd=repo, patterns=fake_api + "\n")
    c4 = (sum((wt or {}).values()), sum((hd or {}).values()))
    pub("owner_secret_c4_seen_worktree_head", "%d/%d" % c4)
    if c4[0] < 1 or c4[1] < 1: dead.append("c4_balayage_aveugle")
finally:
    shutil.rmtree(SB, ignore_errors=True)
    os.environ.pop("AUTOPORT_SECRET_DIRS", None)

pub("owner_secret_unmeasured", ",".join(unmeasured) or "aucun")
pub("owner_secret_dead_controls", ",".join(dead) or "aucun")
pub("owner_secret_census_s", int(time.time() - T0))
total = F + X + M + len(unmeasured) + len(dead)
for k, v in OUT.items():
    print("%s=%s" % (k, v))
print("owner_secret_leaks=%d" % total)
PY
