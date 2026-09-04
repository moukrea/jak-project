#!/usr/bin/env python3
"""`backlog.yaml` : la seule verite du travail.

Une feature = un item. L'orchestrateur choisit avec `next_open()`, le superviseur pose les
statuts avec `set_status()`, l'owner lit `status_report()`.

Deux processus ecrivent ce fichier (l'orchestrateur et le superviseur) : toute ecriture
prend un verrou, relit le fichier sur disque, applique la modification, puis remplace le
fichier par un `rename` atomique. Rien n'est jamais ecrit en place.

    from lib import backlog
    b = backlog.load()
    it = b.next_open()
    b.set_status(it["id"], "in-progress")
    print(b.status_report())
"""

from __future__ import annotations

import datetime
import errno
import hashlib
import os
import subprocess
import tempfile

try:
    import fcntl
except ImportError:                                   # pragma: no cover - non POSIX
    fcntl = None

import yaml

AP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_PATH = os.path.join(AP, "backlog.yaml")
# Le verrou porte un nom deja couvert par .gitignore (`.autoport/.auto_*.lock`) : le
# chantier D ne touche pas .gitignore.
def _lock_path(path):
    d, base = os.path.split(os.fspath(path))
    return os.path.join(d or ".", ".auto_%s.lock" % base)
DIGEST_MEMO = os.path.join(AP, ".last_status_digest")   # ignore par git (.autoport/.last_*)
# Une feature livree avant cette date l'a ete sur un build que l'owner n'a plus : elle part
# dans « Dette a trier », pas dans la liste de ce qu'il peut tester ce soir.
CURRENT_BUILD_SINCE = "2026-08-20"
CURRENT_BUILD = "dernier build publie sur jak-builds"

# Plafonds par defaut d'un essai. Au-dela, l'item doit porter la raison dans `notes`,
# introduite par « budget : ». Un essai de 3000 tours est un essai qui a perdu son chemin.
DEFAULT_MAX_TURNS = 800
DEFAULT_MAX_RETRIES = 6
BUDGET_NOTE = "budget :"

STATUSES = ("open", "in-progress", "to-test", "validated", "blocked", "archived")
ACTIONABLE = ("open", "in-progress", "to-test", "blocked")
OPS = {"==": lambda a, b: a == b, "!=": lambda a, b: a != b,
       "<": lambda a, b: a < b, "<=": lambda a, b: a <= b,
       ">": lambda a, b: a > b, ">=": lambda a, b: a >= b}


class BacklogError(Exception):
    pass


class _Lock:
    """Verrou consultatif inter-processus autour du fichier de backlog."""

    def __init__(self, path):
        self.path = _lock_path(path)
        self.fh = None

    def __enter__(self):
        self.fh = open(self.path, "a+")
        if fcntl is not None:
            fcntl.flock(self.fh.fileno(), fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        try:
            if fcntl is not None:
                fcntl.flock(self.fh.fileno(), fcntl.LOCK_UN)
        finally:
            self.fh.close()
            self.fh = None
        return False


def _atomic_write(path, text):
    path = os.fspath(path)
    d = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".backlog-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError as exc:
            if exc.errno != errno.ENOENT:
                raise
        raise


def _dump(doc):
    class D(yaml.SafeDumper):
        pass

    def rep_str(dumper, data):
        return dumper.represent_scalar("tag:yaml.org,2002:str", data,
                                       style="|" if "\n" in data else None)

    D.add_representer(str, rep_str)
    head = ("# La seule verite du travail. Une feature = un item.\n"
            "# Ecrit par lib/backlog.py (atomique) ; genere a l'origine par "
            "tools/migrate_backlog.py.\n"
            "# owner_feedback : les mots de l'owner, dates, jamais reformules.\n")
    return head + yaml.dump(doc, Dumper=D, allow_unicode=True, sort_keys=False, width=100)


def build_sha():
    """Le sha du build courant : HEAD du depot, tronque. Vide si git est indisponible."""
    try:
        out = subprocess.run(["git", "-C", os.path.dirname(AP), "rev-parse", "HEAD"],
                             capture_output=True, text=True, timeout=20)
        return out.stdout.strip()[:16] if out.returncode == 0 else ""
    except Exception:
        return ""


class Backlog:
    def __init__(self, doc, path):
        self.path = os.fspath(path)
        self.version = doc.get("version", 1)
        self.items = list(doc.get("items") or [])

    # ---------------------------------------------------------------- lecture
    def get(self, item_id):
        for it in self.items:
            if it.get("id") == item_id:
                return it
        return None

    def by_status(self, *statuses):
        return [it for it in self.items if it.get("status") in statuses]

    def _prio(self, it):
        p = it.get("priority")
        return p if isinstance(p, int) else 10 ** 6

    def next_open(self):
        """Le premier `open` dont toutes les dependances sont `validated`, par priorite."""
        candidates = []
        for it in self.items:
            if it.get("status") != "open":
                continue
            deps = it.get("depends_on") or []
            blocked = False
            for dep in deps:
                d = self.get(dep)
                if d is None or d.get("status") != "validated":
                    blocked = True
                    break
            if not blocked:
                candidates.append(it)
        if not candidates:
            return None
        candidates.sort(key=lambda it: (self._prio(it), it.get("id", "")))
        return candidates[0]

    # ---------------------------------------------------------------- ecriture
    def set_status(self, item_id, status, **fields):
        """Ecriture atomique : verrou, relecture du disque, modification, rename."""
        if status not in STATUSES:
            raise BacklogError("statut inconnu : %s (attendu %s)" % (status, "|".join(STATUSES)))
        with _Lock(self.path):
            fresh = _read(self.path)
            target = None
            for it in fresh["items"]:
                if it.get("id") == item_id:
                    target = it
                    break
            if target is None:
                raise BacklogError("item inconnu : %s" % item_id)
            target["status"] = status
            for k, v in fields.items():
                target[k] = v
            if status == "blocked" and not target.get("block_reason"):
                raise BacklogError("un item bloque doit porter block_reason")
            _atomic_write(self.path, _dump(fresh))
        self.items = fresh["items"]
        self.version = fresh.get("version", 1)
        return self.get(item_id)

    def add_owner_feedback(self, item_id, date, text):
        it = self.get(item_id)
        if it is None:
            raise BacklogError("item inconnu : %s" % item_id)
        fb = list(it.get("owner_feedback") or [])
        fb.append({"date": date, "text": text})
        return self.set_status(item_id, it.get("status"), owner_feedback=fb)

    def validate(self, item_id, text, date=None, sha=None):
        """Le feu vert de l'owner : sa phrase, la date, le sha du build teste."""
        date = date or datetime.date.today().isoformat()
        it = self.get(item_id)
        if it is None:
            raise BacklogError("item inconnu : %s" % item_id)
        fb = list(it.get("owner_feedback") or [])
        if not any(e.get("text") == text for e in fb):
            fb.append({"date": date, "text": text})
        return self.set_status(item_id, "validated",
                               owner_ok={"date": date, "text": text,
                                         "build_sha": sha if sha is not None else build_sha()},
                               owner_feedback=fb, priority=None)

    # ---------------------------------------------------------------- rapport
    def _testable_now(self, it):
        """Testable dans le build courant : livre recemment, ou retour recent de l'owner."""
        fb = it.get("owner_feedback") or []
        last_fb = fb[-1]["date"] if fb else ""
        return max(it.get("delivered") or "", last_fb) >= CURRENT_BUILD_SINCE

    def status_report(self, changed_only=False, show_all=False):
        """Les blocs, en francais simple. Un item `validated` n'y apparait jamais.

        `## A tester` ne porte que ce qui se teste sur le build courant : c'est cette
        section-la que le digest et les notes de release reprennent, et c'est elle seule que
        `changed_only` surveille. Le reste part dans `## Dette a trier`, une ligne chacun.
        """
        cur = self.by_status("in-progress")
        if cur:
            en_cours = "## En cours\n%s" % cur[0].get("feature", cur[0].get("id"))
        else:
            nxt = self.next_open()
            en_cours = ("## En cours\nRien en cours. Le prochain sujet est : %s"
                        % nxt.get("feature", nxt.get("id"))) if nxt else ""

        # `owner_test: false` : la preuve est machine (empreinte, reproductibilite), il n'y a rien
        # que l'owner puisse regarder en jeu. Il l'a dit le 2026-09-04 : « s'il n'y a rien a
        # tester ne le met pas a tester ». Ces items ne lui sont jamais presentes.
        todo = sorted((it for it in self.by_status("to-test") if it.get("owner_test", True)),
                      key=lambda it: (it.get("delivered") or "", -self._prio(it)), reverse=True)
        now = [it for it in todo if self._testable_now(it)]
        debt = [it for it in todo if it not in now]

        lines = []
        if now:
            lines = ["## A tester", "Sur le %s :" % CURRENT_BUILD]
            for it in now:
                lines.append("")
                lines.append("- %s" % it.get("feature", it.get("id")))
                if it.get("build") and it["build"] != CURRENT_BUILD:
                    lines.append("  Build : %s" % it["build"])
                if it.get("where"):
                    lines.append("  Ou regarder : %s" % it["where"])
        a_tester = "\n".join(lines)

        lines = []
        if debt:
            lines = ["## Dette a trier",
                     "%d chantiers fermes par le harnais il y a des semaines ou des mois, "
                     "jamais confirmes par ta parole, sur des builds que tu n'as plus. "
                     "Beaucoup sont probablement bons. A trancher par lots quand tu veux, "
                     "rien a faire maintenant." % len(debt)]
            for it in debt:
                d = it.get("delivered")
                lines.append("- %s%s" % (it.get("feature", it.get("id")),
                                         " (livre le %s)" % d if d else ""))
                if show_all and it.get("where"):
                    lines.append("  Ou regarder : %s" % it["where"])
        dette = "\n".join(lines)

        lines = []
        stuck = sorted(self.by_status("blocked"), key=lambda it: (self._prio(it), it.get("id", "")))
        if stuck:
            lines = ["## Bloque"]
            for it in stuck:
                lines.append("- %s" % it.get("feature", it.get("id")))
                lines.append("  %s" % (it.get("block_reason") or "raison non enregistree"))
        bloque = "\n".join(lines)

        text = "\n\n".join(b for b in (en_cours, a_tester, bloque, dette) if b)
        if not changed_only:
            return text
        # `--changed` ne surveille que « A tester » : la dette ne bouge pas d'elle-meme et
        # ne doit pas reveiller un digest.
        digest = hashlib.sha256(a_tester.encode("utf-8")).hexdigest()
        previous = ""
        try:
            with open(DIGEST_MEMO, encoding="utf-8") as fh:
                previous = fh.read().strip()
        except OSError:
            pass
        if previous == digest:
            return ""
        _atomic_write(DIGEST_MEMO, digest + "\n")
        return text

    # ---------------------------------------------------------------- controle
    def lint(self):
        problems = []
        seen = set()
        for it in self.items:
            iid = it.get("id")
            if not iid:
                problems.append("item sans id : %r" % (it.get("feature") or it))
                continue
            if iid in seen:
                problems.append("%s : id en double" % iid)
            seen.add(iid)
            status = it.get("status")
            if status not in STATUSES:
                problems.append("%s : statut inconnu %r" % (iid, status))
            if not it.get("feature"):
                problems.append("%s : pas de libelle de feature" % iid)
            # Le couple device/gate ne vaut que pour un item que l'orchestrateur peut
            # prendre : un `to-test`, un `validated` ou un `archived` ne repassera pas par
            # une porte. S'il redevient `open`, le reproche revient au bon moment.
            if status in ("open", "blocked") and it.get("device") and not it.get("gate"):
                problems.append("%s : device: true sans gate — la preuve ne serait jugee "
                                "par rien" % iid)
            note = it.get("notes") or ""
            if (it.get("max_turns") or 0) > DEFAULT_MAX_TURNS and BUDGET_NOTE not in note:
                problems.append("%s : max_turns %s au-dessus du defaut %d sans raison "
                                "« %s » dans notes" % (iid, it.get("max_turns"),
                                                       DEFAULT_MAX_TURNS, BUDGET_NOTE))
            if (it.get("max_retries") or 0) > DEFAULT_MAX_RETRIES and BUDGET_NOTE not in note:
                problems.append("%s : max_retries %s au-dessus du defaut %d sans raison "
                                "« %s » dans notes" % (iid, it.get("max_retries"),
                                                       DEFAULT_MAX_RETRIES, BUDGET_NOTE))
            if status == "to-test" and it.get("owner_test", True) and not (it.get("where") or "").strip():
                problems.append("%s : a tester sans « ou regarder » — l'owner ne saurait pas "
                                "quoi regarder" % iid)
            if status == "blocked" and not (it.get("block_reason") or "").strip():
                problems.append("%s : bloque sans block_reason" % iid)
            if status == "validated" and not it.get("owner_ok"):
                problems.append("%s : valide sans owner_ok — seule la parole de l'owner "
                                "valide" % iid)
            gate = it.get("gate")
            if gate is not None:
                if not isinstance(gate, dict) or set(gate) < {"key", "op", "value"}:
                    problems.append("%s : gate mal forme (key, op, value attendus)" % iid)
                elif gate.get("op") not in OPS:
                    problems.append("%s : gate avec un operateur inconnu %r" % (iid, gate.get("op")))
        for it in self.items:
            for dep in (it.get("depends_on") or []):
                if dep not in seen:
                    problems.append("%s : depend de %s, qui n'existe pas" % (it.get("id"), dep))
        return problems


def _read(path):
    with open(os.fspath(path), encoding="utf-8") as fh:
        doc = yaml.safe_load(fh) or {}
    if not isinstance(doc, dict) or "items" not in doc:
        raise BacklogError("%s : pas un backlog (clef `items` absente)" % path)
    return doc


def load(path=None):
    path = os.fspath(path) if path else DEFAULT_PATH
    return Backlog(_read(path), path)


# ------------------------------------------------------------------------------- prompts
PROMPT_MAX = 2560          # 2,5 Ko : plafond dur, on echoue bruyamment au-dela

_SECTIONS = ("Defaut cite", "Cause connue", "Livrable", "Preuve exigee", "Hors perimetre")


def render_prompt(item, max_bytes=PROMPT_MAX):
    """Le prompt d'un item, en 5 rubriques fixes. Regenere a chaque reouverture : c'est ce
    qui remplace les clones `-2` qui reutilisaient le prompt de la phase precedente."""
    iid = item["id"]
    fb = list(item.get("owner_feedback") or [])

    def body(n_quotes, quote_len):
        out = ["# %s" % item.get("feature", iid), ""]
        out.append("## Defaut cite")
        if fb:
            for e in fb[-n_quotes:]:
                t = e.get("text", "")
                if len(t) > quote_len:
                    t = t[:quote_len].rstrip() + "…"
                out.append("- %s : « %s »" % (e.get("date", "?"), t))
        else:
            out.append("- (aucun retour de l'owner enregistre sur cet item)")
        out += ["", "## Cause connue",
                item.get("known_cause")
                or "Aucun cycle n'a encore etabli de cause sur cet item."]
        out += ["", "## Livrable",
                item.get("deliverable")
                or ("Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une "
                    "garde de non-regression qui echoue si le symptome revient.")]
        gate = item.get("gate")
        src = "device" if item.get("device") else "x86"
        out += ["", "## Preuve exigee"]
        if gate:
            out.append("`%s %s %s` dans `reports/%s/proof.txt`."
                       % (gate["key"], gate["op"], gate["value"], iid))
        else:
            out.append("Aucun critere machine n'est encore ecrit pour cet item. Ecris-le "
                       "d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le "
                       "dans `backlog.yaml`, puis prouve-le.")
        out.append("Le proof se produit par `lib/proof_run.sh %s %s` — jamais a la main, "
                   "jamais recopie dans le rapport." % (iid, src))
        if item.get("where"):
            out.append("Ou l'owner regardera : %s." % item["where"])
        out += ["", "## Hors perimetre",
                item.get("out_of_scope")
                or ("Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja "
                    "validee (`./.autoport/autoport status` ne les liste plus). Pas de "
                    "mesure visuelle : seule la ligne du moteur compte.")]
        return "\n".join(out) + "\n"

    for n, ln in ((3, 400), (2, 300), (1, 220), (1, 140)):
        text = body(n, ln)
        if len(text.encode("utf-8")) <= max_bytes:
            return text
    raise BacklogError("prompt de %s au-dessus de %d octets meme reduit : raccourcis "
                       "known_cause / deliverable / out_of_scope" % (iid, max_bytes))


def write_prompt(item, ap_dir=None):
    ap_dir = ap_dir or AP
    rel = item.get("prompt") or ("prompts/item-%s.md" % item["id"])
    path = os.path.join(ap_dir, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    _atomic_write(path, render_prompt(item))
    return path
