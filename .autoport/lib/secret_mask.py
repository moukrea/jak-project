#!/usr/bin/env python3
"""Un secret colle par l'owner n'est jamais recopie en clair (harness-owner-secret-never-copied-in-clear).

LA PANNE (17/09 -> 23/09) : l'owner a colle le Client Secret de l'application Linear dans un commentaire.
`pull_owner` l'a imprime (80 caracteres de chaque retour -> logs/linear_sync.txt), puis ecrit dans
backlog.yaml (owner_feedback), .owner_sla.json, un prompt de worker, deux journaux d'essai, et 18 commits
dont un POUSSE sur le depot GitHub public. Masque a la main le 23/09 : seule la rotation le neutralise.

LE MASQUE VIT AU POINT DE PRODUCTION : `linear_sync.Linear.q` passe CHAQUE reponse de Linear par
`mask_tree` avant de la rendre. Aucun appelant (pull_owner, adoption des tickets de l'owner, retours hors
backlog, owner_sla) ne voit donc jamais le texte en clair, ni pour l'imprimer ni pour l'ecrire.
Le serialiseur du backlog passe en plus par `scrub_known` (valeurs exactes des secrets connus).

TROIS FORMES, du plus sur au plus devine :
  1. CONNU   : la valeur exacte d'une entree de ~/.config/autoport/*.env (hors URL et chemins) ou d'un
               champ secret/jeton/cle/client_id de ~/.config/autoport/*.json.
  2. PREFIXE : forme qui se nomme elle-meme (lin_api_, lin_oauth_, ghp_, github_pat_, sk-ant-, AKIA...).
  3. CONTEXTE: un jeton long (>= 20, lettres ET chiffres) a moins de 40 caracteres apres « secret »,
               « token », « jeton », « key », « cle », « password », « mot de passe », « bearer »...
               Jamais : un identifiant kebab/snake en minuscules (id d'item, chemin), une URL d'image
               Linear. Un hash de commit ou un md5 d'APK SANS mot-cle devant n'est pas touche.

Le hook git (`hooks/git/pre-commit`, `hooks/git/pre-push`) refuse les formes 1 et 2 seulement : un refus
sur une forme devinee bloquerait l'orchestrateur sur un faux positif. Il ne publie jamais la VALEUR,
seulement le NOM de la cle et le fichier.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

MASK = "[SECRET-MASQUE]"
TEXT_FIELDS = ("body", "description", "title")

_SECRET_NAME = re.compile(r"(SECRET|TOKEN|KEY|PASSWORD|PASSWD|PASS\b|PRIVATE|CREDENTIAL)", re.I)
_NOT_SECRET_NAME = re.compile(r"(_ID|_URL|_SCOPE|_TYPE|_AT|_IN)$", re.I)
# Un .env de ~/.config/autoport EST le coffre : toute valeur y est connue, sauf une URL ou un chemin.
# L'identifiant client en fait partie : l'owner l'a colle AVEC le secret le 17/09, et le superviseur l'a
# masque avec lui (dad5e35790). Dans un .json, seuls les champs nommes secret/jeton/cle, plus `client_id`.
_NOT_SECRET_ENV = re.compile(r"(_URL|_PATH|_DIR|_HOST)$", re.I)

PREFIXED = re.compile(
    r"(?<![A-Za-z0-9_])("
    r"lin_(?:api|oauth|wh)_[A-Za-z0-9]{16,}"
    r"|gh[pousr]_[A-Za-z0-9]{30,}"
    r"|github_pat_[A-Za-z0-9_]{40,}"
    r"|sk-ant-[A-Za-z0-9_\-]{20,}"
    r"|sk-[A-Za-z0-9]{32,}"
    r"|AKIA[0-9A-Z]{16}"
    r"|xox[abprs]-[A-Za-z0-9\-]{10,}"
    r")")
KEYWORD = re.compile(
    r"(?<![A-Za-z])(secrets?|tokens?|jetons?|passwords?|passwd|mots? de passe|api[ _-]?keys?|keys?|cl[eé]s?"
    r"|bearer|authorization|credentials?)(?![A-Za-z])(?!-MASQUE\])", re.I)  # le masque n'est pas un mot-cle
CANDIDATE = re.compile(r"(?<![A-Za-z0-9+/_=\-])[A-Za-z0-9+/_\-]{20,}={0,2}(?![A-Za-z0-9+/_=\-])")
_IDENT = re.compile(r"^[a-z0-9]+(?:[-_/][a-z0-9]+)+$")
WINDOW = 40


def config_dirs():
    env = os.environ.get("AUTOPORT_SECRET_DIRS")
    if env:
        return [Path(p) for p in env.split(":") if p]
    return [Path.home() / ".config" / "autoport"]


def _json_secrets(obj, path, out):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, str):
                if ((_SECRET_NAME.search(k) and not _NOT_SECRET_NAME.search(k)) or k == "client_id") and len(v) >= 12:
                    out.append(("%s:%s" % (path, k), v))
            else:
                _json_secrets(v, path, out)
    elif isinstance(obj, list):
        for v in obj:
            _json_secrets(v, path, out)


def known_secrets(dirs=None):
    """-> [(nom, valeur)] ; nom = `fichier:CLE`. Jamais imprime avec sa valeur."""
    out = []
    for d in (dirs or config_dirs()):
        if not d.is_dir():
            continue
        for f in sorted(d.iterdir()):
            try:
                if f.suffix == ".env":
                    for line in f.read_text(errors="replace").splitlines():
                        line = line.strip()
                        if not line or line.startswith("#") or "=" not in line:
                            continue
                        k, v = line.split("=", 1)
                        k = k.replace("export ", "").strip()
                        v = v.strip().strip("'\"")
                        if len(v) >= 12 and not _NOT_SECRET_ENV.search(k) and "://" not in v and v[:1] not in "/~.":
                            out.append(("%s:%s" % (f.name, k), v))
                elif f.suffix == ".json":
                    _json_secrets(json.loads(f.read_text(errors="replace")), f.name, out)
            except (OSError, ValueError):
                continue
    seen, uniq = set(), []
    for n, v in out:
        if v not in seen:
            seen.add(v)
            uniq.append((n, v))
    return uniq


_KNOWN_CACHE = {}


def _known_values():
    key = tuple(str(d) for d in config_dirs())
    if key not in _KNOWN_CACHE:
        _KNOWN_CACHE[key] = sorted((v for _, v in known_secrets()), key=len, reverse=True)
    return _KNOWN_CACHE[key]


def scrub_known(text, known=None):
    """Remplace les valeurs EXACTES des secrets connus. -> (texte, nombre)."""
    n = 0
    for v in (known if known is not None else _known_values()):
        if v in text:
            n += text.count(v)
            text = text.replace(v, MASK)
    return text, n


def _is_guessable_secret(tok, text, start):
    if not (re.search(r"[0-9]", tok) and re.search(r"[A-Za-z]", tok)):
        return False
    if _IDENT.match(tok) and max(len(s) for s in re.split(r"[-_/]", tok)) <= 12:
        return False                       # id d'item, chemin, uuid
    word_start = max(text.rfind(" ", 0, start), text.rfind("\n", 0, start), text.rfind("(", 0, start)) + 1
    word = text[word_start:start + len(tok)]
    if "uploads.linear.app" in word:
        return False                       # image de l'owner : save_owner_images doit pouvoir la tirer
    return True


def mask(text, known=None):
    """-> (texte masque, nombre de secrets masques). Idempotent."""
    if not isinstance(text, str) or not text:
        return text, 0
    text, n = scrub_known(text, known)

    def _pre(m):
        nonlocal n
        n += 1
        return MASK
    text = PREFIXED.sub(_pre, text)
    spans = []
    for k in KEYWORD.finditer(text):
        end = k.end()
        win = text[end:end + WINDOW + 40]
        nl = [i for i, c in enumerate(win) if c == "\n"]
        if len(nl) >= 2:
            win = win[:nl[1]]              # le libelle et sa valeur sur la ligne suivante, pas plus
        for c in CANDIDATE.finditer(win):
            if c.start() > WINDOW:
                break
            s = end + c.start()
            if _is_guessable_secret(c.group(0), text, s):
                spans.append((s, end + c.end()))
    for s, e in sorted(set(spans), reverse=True):
        text = text[:s] + MASK + text[e:]
        n += 1
    return text, n


def mask_tree(obj, fields=TEXT_FIELDS):
    """Masque EN PLACE les champs texte d'une reponse Linear. -> nombre masque."""
    n = 0
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, str) and k in fields:
                obj[k], m = mask(v)
                n += m
            elif isinstance(v, (dict, list)):
                n += mask_tree(v, fields)
    elif isinstance(obj, list):
        for v in obj:
            n += mask_tree(v, fields)
    return n


# ------------------------------------------------------------------------------------ hook git ----
def _hits_in_lines(lines, known):
    """lines : [(fichier, texte ajoute)] -> [(fichier, nom)] ; formes CONNUE et PREFIXEE seulement."""
    hits = []
    for f, line in lines:
        for name, v in known:
            if v in line:
                hits.append((f, name))
        for m in PREFIXED.finditer(line):
            hits.append((f, "forme %s" % m.group(1)[:8].rstrip("_-") + "…"))
    return hits


def _added_lines(diff_text):
    out, cur = [], "?"
    for line in diff_text.splitlines():
        if line.startswith("+++ "):
            cur = line[6:] if line.startswith("+++ b/") else line[4:]
        elif line.startswith("+") and not line.startswith("+++"):
            out.append((cur, line[1:]))
    return out


def _refuse(hits, what):
    sys.stderr.write("[autoport secret-guard] REFUS du %s : %d secret(s) en clair.\n" % (what, len(hits)))
    for f, name in sorted(set(hits)):
        sys.stderr.write("  %s : %s\n" % (f, name))
    sys.stderr.write("Remplace la valeur par %s (lib/secret_mask.py) ; ne la recopie nulle part.\n" % MASK)
    return 1


def scan_staged():
    d = subprocess.run(["git", "diff", "--cached", "-U0", "--no-color", "--text", "--no-ext-diff"],
                       capture_output=True, text=True, errors="replace")
    if d.returncode != 0:
        sys.stderr.write("[autoport secret-guard] git diff --cached a echoue (%d) : commit refuse\n" % d.returncode)
        return 1
    hits = _hits_in_lines(_added_lines(d.stdout), known_secrets())
    return _refuse(hits, "commit") if hits else 0


def scan_push(stdin_text):
    known = known_secrets()
    hits = []
    for line in stdin_text.splitlines():
        parts = line.split()
        if len(parts) != 4 or set(parts[1]) == {"0"}:
            continue                       # suppression de branche : rien ne part
        local, remote = parts[1], parts[3]
        rng = [local, "--not", "--remotes"] if set(remote) == {"0"} else ["%s..%s" % (remote, local)]
        d = subprocess.run(["git", "log", "-p", "-U0", "--no-color", "--text", "--format=commit %H"] + rng,
                           capture_output=True, text=True, errors="replace")
        if d.returncode != 0:
            sys.stderr.write("[autoport secret-guard] git log a echoue (%d) : push refuse\n" % d.returncode)
            return 1
        hits += _hits_in_lines(_added_lines(d.stdout), known)
    return _refuse(hits, "push") if hits else 0


def install_hooks(quiet=False):
    """Pose .git/hooks/pre-commit et pre-push -> hooks/git/<nom> (lien relatif, idempotent). Un hook
    ETRANGER deja en place n'est jamais ecrase : il est nomme. -> {nom: etat}."""
    here = Path(__file__).resolve().parent.parent / "hooks" / "git"
    try:
        common = subprocess.run(["git", "-C", str(here), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return {}
    hooks = Path(common) / "hooks"
    etat = {}
    for name in ("pre-commit", "pre-push", "commit-msg"):   # commit-msg : archive-guard (23/09)
        dst, src = hooks / name, here / name
        if dst.is_symlink() or dst.exists():
            etat[name] = "en-place" if dst.resolve() == src.resolve() else "etranger"
            if etat[name] == "etranger" and not quiet:
                sys.stderr.write("[autoport secret-guard] %s : un hook etranger est en place, non ecrase\n" % dst)
            continue
        hooks.mkdir(parents=True, exist_ok=True)
        dst.symlink_to(os.path.relpath(src, hooks))
        etat[name] = "pose"
    return etat


def main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage : secret_mask.py scan-staged | scan-push | install-hooks | mask < texte\n")
        return 2
    if argv[1] == "scan-staged":
        return scan_staged()
    if argv[1] == "scan-push":
        return scan_push(sys.stdin.read())
    if argv[1] == "install-hooks":
        print(" ".join("%s=%s" % kv for kv in sorted(install_hooks().items())))
        return 0
    if argv[1] == "mask":
        t, n = mask(sys.stdin.read())
        sys.stdout.write(t)
        sys.stderr.write("masques=%d\n" % n)
        return 0
    sys.stderr.write("commande inconnue : %s\n" % argv[1])
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
