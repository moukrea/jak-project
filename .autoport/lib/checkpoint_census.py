#!/usr/bin/env python3
"""checkpoint_census — LA MESURE DE L'ITEM `builder-checkpoint-steals-work`.

Ce programme ne juge RIEN. Il imprime des `cle=valeur` sur sa sortie standard ; le verdict —
la somme qui alimente `checkpoint_stolen_files`, et la polarite « inconnu = defaut » — est dans
`game/system/checkpoint_census.cpp`, donc dans le binaire que le validateur epingle par son sha.

TROIS JAMBES, QUI NE PEUVENT PAS SE COUVRIR L'UNE L'AUTRE.

1. HISTOIRE. Les 50 derniers commits. Un « commit de checkpoint » est un commit du constructeur
   (sujet « checkpoint automatique » ou prefixe `[autoport/builder]`). Un fichier qu'il porte est
   EMPORTE des lors que le constructeur ne le produit pas lui-meme ; la seule famille qu'il
   produit est le manifeste de pack sous `android/app/src/jak1/assets-slim/bundle/`.
   Le compte est coupe en deux par la PRESENCE DE LA GARDE dans l'arbre du commit
   (`.autoport/lib/checkpoint_snapshot.sh`) :
     - `history_stolen_before` : les commits d'AVANT la garde. Non nul, et il le restera : on ne
       reecrit pas l'histoire. C'est le temoin qui prouve que l'instrument VOIT le vol.
     - `history_stolen_after`  : les commits qui avaient la garde sous la main et ont vole quand
       meme. C'est la recidive, et c'est cette moitie qui alimente la porte.

2. AUDIT. Tout script du harnais qui ecrit dans git. Trois defauts, ceux exactement que le
   constructeur avait :
     - territoire      : le script nomme un dossier de chantier (game/, goal_src/, common/,
                         goalc/, android/, third-party) dans un `git add|commit|rm|checkout|
                         restore|reset|stash`. Le harnais n'a pas a versionner le code d'autrui.
     - balayage        : `-A`, `-u`, `-a`, `--all`, ou le chemin `.`.
     - index-d-autrui  : un `git commit` sans pathspec dans un script qui indexe — il valide tout
                         ce qu'un tiers avait pose dans l'index.
   Deux sorties, VISIBLES et COMPTEES, jamais implicites : `GIT_INDEX_FILE=` sur la meme ligne
   (l'ecriture part dans un index jetable, elle ne peut rien emporter) et le marqueur
   `# git-sandbox-ok` (un depot bac-a-sable, ou la ligne EST le defaut qu'on rejoue expres).
   `audit_before_sites` applique les MEMES regles au constructeur tel qu'il etait au dernier
   checkpoint (8179021250) : 2 defauts. Un audit qui rend 0 partout, passe et present, ne
   mesurerait rien.

3. BAC A SABLE. `lib/checkpoint_selftest.sh`, relaye tel quel. C'est la seule jambe qui
   fabrique la condition au lieu de l'attendre : sans elle, « aucun checkpoint depuis la garde »
   serait une porte verte par INACTION.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Le dernier commit de checkpoint, garde comme ANCRE du temoin « avant ». Un sha fige, pas une
# date : le texte du constructeur d'avant doit rester lisible meme quand le fichier, lui, a change.
ANCHOR_BEFORE = "8179021250"

# La seule famille de fichiers que le constructeur produit lui-meme et peut donc legitimement
# porter dans un commit.
BUILDER_OWN = ("android/app/src/jak1/assets-slim/bundle/",)

GUARD = ".autoport/lib/checkpoint_snapshot.sh"

CHANTIER = re.compile(r"(goal_src|goalc|third-party)|(^|[\s'\"/])(game|common|android)(/|['\"]|\s|$)")
VERBS = r"(add|commit|rm|checkout|restore|reset|stash)(?![-\w])"
SHELL_FORM = re.compile(r"\bgit\s+" + VERBS)
LIST_FORM = re.compile(r"['\"]git['\"]\s*,\s*(?:['\"]-[^'\"]*['\"]\s*,\s*)*['\"]" + VERBS)
HELPER_FORM = re.compile(r"\.git\(\s*['\"]" + VERBS)
SWEEP = re.compile(r"\s-(A|u|a)\b|--all\b|\s\.\s|['\"](\.|-A|-u|-a|--all)['\"]")
PATHSPEC = re.compile(r"--\s|--pathspec-from-file")
PY_CALL = re.compile(r"subprocess|\.git\(|check_output|Popen|run\(")


def git(*args):
    """git en lecture. Rend (code, sortie)."""
    r = subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True)
    return r.returncode, r.stdout


def audit_text(path, text):
    """Les sites d'ecriture git d'un fichier. Rend [(ligne, verbe, defauts, exempt)]."""
    is_py = path.endswith(".py")
    lines = text.splitlines()
    # Un `git commit` nu n'est « index d'autrui » que dans un script qui INDEXE : ailleurs il
    # n'y a pas d'index a lui voler.
    indexes = any(
        re.search(r"\bgit\s+add\b|['\"]git['\"]\s*,\s*['\"]add['\"]|\.git\(\s*['\"]add['\"]", l)
        and not l.strip().startswith("#")
        for l in lines
    )
    out = []
    for n, line in enumerate(lines, 1):
        if line.strip().startswith("#"):
            continue
        verb = None
        for form in (SHELL_FORM, LIST_FORM, HELPER_FORM):
            m = form.search(line)
            if m:
                verb = m.group(1)
                break
        if not verb:
            continue
        # UN SITE EST UN SITE D'APPEL. En python, une ligne qui ne lance rien est de la prose :
        # la premiere version de cet audit comptait une phrase de docstring comme un defaut.
        if is_py and not PY_CALL.search(line):
            continue
        if "GIT_INDEX_FILE=" in line or "git-sandbox-ok" in line:
            out.append((n, verb, [], True))
            continue
        # Un appel python tient sur plusieurs lignes : le pathspec d'orchestrator.py:869 est
        # ecrit a la ligne suivante. Juger la ligne seule le declarait fautif a tort.
        window = " ".join(lines[n - 1 : n + 2]) if is_py else line
        faults = []
        if CHANTIER.search(line):
            faults.append("territoire")
        if SWEEP.search(line):
            faults.append("balayage")
        if verb == "commit" and indexes and not PATHSPEC.search(window):
            faults.append("index-d-autrui")
        out.append((n, verb, faults, False))
    return out


def scan_harness():
    """Tous les scripts du harnais, sur le DISQUE (un script neuf non encore suivi compte)."""
    files = []
    for dp, dn, fn in os.walk(os.path.join(ROOT, ".autoport")):
        dn[:] = [d for d in dn if d not in ("archive", "__pycache__", "tmp", "backups", "logs",
                                            "reports", "scratch", "dist", "gold", "refset",
                                            "refset-candidates", "refset-origine-pure",
                                            "refset-unify", "cgo-cache", "demos", "codex")]
        for f in fn:
            if (f.endswith(".sh") or f.endswith(".py")) and ".bak" not in f:
                files.append(os.path.join(dp, f))
    return sorted(files)


def leg_history(out):
    rc, log = git("log", "-n", "50", "--format=%H%x09%s")
    if rc != 0:
        out["history_ran"] = 0
        return
    commits = [l.split("\t", 1) for l in log.splitlines() if "\t" in l]
    stolen_before = stolen_after = checkpoints = 0
    for sha, subject in commits:
        low = subject.lower()
        if "checkpoint automatique" not in low and not subject.startswith("[autoport/builder]"):
            continue
        checkpoints += 1
        _, names = git("diff-tree", "--no-commit-id", "--name-only", "-r", sha)
        stolen = sum(1 for f in names.split()
                     if f and not any(f.startswith(p) for p in BUILDER_OWN))
        had_guard = git("cat-file", "-e", f"{sha}:{GUARD}")[0] == 0
        if had_guard:
            stolen_after += stolen
        else:
            stolen_before += stolen
    out["history_ran"] = 1
    out["history_commits_scanned"] = len(commits)
    out["history_checkpoint_commits"] = checkpoints
    out["history_stolen_before"] = stolen_before
    out["history_stolen_after"] = stolen_after


def leg_audit(out):
    files = scan_harness()
    sites = unsafe = exempt = 0
    worst = []
    for path in files:
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for n, _verb, faults, is_exempt in audit_text(path, text):
            sites += 1
            if is_exempt:
                exempt += 1
            elif faults:
                unsafe += 1
                worst.append(f"{os.path.relpath(path, ROOT)}:{n}:{'+'.join(faults)}")
    out["audit_ran"] = 1
    out["audit_files_scanned"] = len(files)
    out["audit_sites"] = sites
    out["audit_unsafe_sites"] = unsafe
    out["audit_exempt_sites"] = exempt
    # Une cle de TEXTE ne se vide jamais toute seule : liste vide => "-".
    out["audit_unsafe_list"] = ",".join(worst)[:400] if worst else "-"

    # LE TEMOIN « AVANT » DE L'AUDIT : les memes regles sur le constructeur tel qu'il etait au
    # dernier checkpoint. Doit valoir 2 (territoire ligne 470, index-d-autrui ligne 471).
    rc, old = git("show", f"{ANCHOR_BEFORE}:.autoport/auto_build_apk.sh")
    if rc == 0 and old:
        out["audit_before_sites"] = sum(1 for _n, _v, f, e in audit_text("x.sh", old) if f and not e)
        out["audit_before_available"] = 1
    else:
        out["audit_before_sites"] = 0
        out["audit_before_available"] = 0


def leg_sandbox(out):
    script = os.path.join(ROOT, ".autoport", "lib", "checkpoint_selftest.sh")
    if not os.path.isfile(script):
        out["selftest_ran"] = 0
        return
    r = subprocess.run(["bash", script], capture_output=True, text=True, cwd=ROOT, timeout=300)
    for line in r.stdout.splitlines():
        if "=" in line and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=\S*", line.strip()):
            k, v = line.strip().split("=", 1)
            out[k] = v
    out.setdefault("selftest_ran", 0)


def main():
    out = {}
    out["guard_present"] = 1 if os.path.isfile(os.path.join(ROOT, GUARD)) else 0
    for leg, key in ((leg_history, "history_ran"), (leg_audit, "audit_ran"),
                     (leg_sandbox, "selftest_ran")):
        try:
            leg(out)
        except Exception as exc:                      # une jambe muette est un DEFAUT, pas un zero
            out[key] = 0
            out.setdefault("census_error", type(exc).__name__)
    for k, v in out.items():
        print(f"{k}={v}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
