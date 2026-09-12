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
import json
import hashlib
import os
import subprocess
import tempfile

try:
    import fcntl
except ImportError:                                   # pragma: no cover - non POSIX
    fcntl = None

import yaml

# LE LECTEUR UNIQUE de l'etat nomme « preuve impossible ». Ce module est importe tantot comme
# `lib.backlog` (l'orchestrateur, la CLI) tantot comme `backlog` tout court (validators/
# generic.sh insere `.autoport/lib` dans le chemin) : les deux formes sont essayees, sinon
# `autoport status` mourrait selon QUI l'appelle.
try:                                                  # noqa: SIM105
    from lib import impossible as _impossible
except ImportError:                                   # pragma: no cover
    import impossible as _impossible

# 2026-09-11 — LECTEUR EN C. PyYAML embarque un analyseur ecrit en Python et un autre en C ; le
# second etait installe et inutilise. Mesure sur le backlog reel (328 Ko) : 1 992 ms contre
# 136 ms. Chaque ecriture relisant le fichier entier, une modification passe de ~2,4 s a ~0,5 s.
# L'ECRIVAIN n'est PAS bascule : `_dump` est personnalise (representer de chaines, ordre des
# cles) et reecrit le fichier a l'octet pres. Le dumper C changerait ce rendu et rendrait chaque
# `git diff` du backlog illisible — c'est ce diff qui porte l'historique des decisions de l'owner.
try:                                  # noqa: SIM105
    from yaml import CSafeLoader as _Loader
except ImportError:                   # machine sans libyaml : on garde le lecteur Python
    from yaml import SafeLoader as _Loader

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

    def parked_for_owner(self):
        """Les items que la porte de fermeture a PARQUES, et le `owner_test` de chacun.

        Publie tel quel dans la preuve de `harness-proof-props-pin`. Un parking sur un item
        qui dit lui-meme n'avoir rien a montrer (`owner_test: false`) est un DEFAUT : personne
        ne peut prononcer son verdict, et il gele pour toujours ce qui en depend.
        """
        return [(it.get("id"), bool(it.get("owner_test", True)))
                for it in self.items if it.get("status") == "to-test"]

    def machine_proved_to_validated(self):
        """`owner_test: false` + porte tenue = `validated`, sans passer par l'owner.

        Un item dont la preuve est machine (empreinte, reproductibilite, instrument qui ne
        change aucun pixel) ne peut PAS recevoir le feu vert de l'owner : il n'a rien a
        regarder. Le laisser en `to-test` gele tout ce qui en depend — c'est arrive le
        2026-09-06 : lighting-census bloquait les onze chantiers d'eclairage suivants.

        2026-09-12 (harness-proof-props-pin) — ELLE ECRIT, MAINTENANT. Jusqu'ici elle mutait
        `self.items` en memoire et n'avait AUCUN appelant : rebranchee telle quelle, elle
        aurait pose un statut que le prochain `_read()` aurait efface sans bruit — exactement
        la perte qu'un worker avait cru observer. Le passage par `set_status` prend le verrou,
        relit le disque et remplace le fichier par un rename atomique.

        La porte de fermeture (orchestrator.py) ne parque plus un `owner_test: false` depuis le
        2026-09-11 ; ceux parques AVANT, eux, ne pouvaient plus sortir de `to-test` par aucun
        chemin. `perf-ocean-idle` y a dormi du 10/09 au 12/09 devant `perf-stock-60`. Cette
        fonction est le rattrapage, et elle tourne a chaque tour de boucle.
        """
        promus = []
        for iid, owner_test in self.parked_for_owner():
            if not owner_test:
                self.set_status(iid, "validated")
                promus.append(iid)
        return promus

    def no_device_marker(self):
        """Le drapeau « aucun appareil de preuve branche », pose par le superviseur.

        2026-09-12 06:42 : le Redmi a disparu de l'USB en pleine nuit. `android-text-overrides-dropped`
        a brule un essai en 25 minutes sur le SEUL constat « l'item exige l'appareil », et les 35
        items d'appareil de la file l'auraient suivi un par un. La requalification qui evite ca
        (GATE -1) vit dans `orchestrator.py`, que le processus en cours ne relit jamais : elle etait
        ecrite et inerte. `backlog.py`, lui, est recharge a chaque tour — c'est donc ici que la file
        peut se corriger sans redemarrage.

        Le fichier porte sa raison et sa date. Tant qu'il existe, `next_open` saute les items qui
        exigent l'appareil et rend le travail qui n'en a pas besoin. Le retirer suffit a tout
        reprendre : aucun statut n'est touche, aucun essai n'est debite.
        """
        chemin = os.path.join(os.path.dirname(self.path), ".no-device")
        return chemin if os.path.exists(chemin) else None

    def next_open(self):
        """Le premier `open` dont toutes les dependances sont `validated`, par priorite.

        Saute les items d'appareil tant que `.autoport/.no-device` existe : voir `no_device_marker`.
        """
        sans_appareil = self.no_device_marker() is not None
        candidates = []
        for it in self.items:
            if it.get("status") != "open":
                continue
            if sans_appareil and it.get("device"):
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
        """Ecriture atomique : verrou, relecture du disque, modification, rename.

        2026-09-11 — UN VERDICT NE SE PERD PLUS. Le superviseur a supprime deux verdicts centraux
        de hdr-display-output en raccourcissant une consigne ; l'item est ensuite passe 15/15
        QUATRE FOIS sans que la plainte de fond de l'owner soit mesuree. Owner : « faut plus que ca
        se produise ce genre de perte ». Le lint le SIGNALAIT — encore fallait-il le lire. Le refus
        est donc ici, au point d'ecriture : un livrable qui perd des verdicts n'est pas ecrit.
        Retrait volontaire : passer `allow_verdict_drop=True`, qui refige le releve.
        """
        if status not in STATUSES:
            raise BacklogError("statut inconnu : %s (attendu %s)" % (status, "|".join(STATUSES)))
        autorise = bool(fields.pop("allow_verdict_drop", False))
        if "deliverable" in fields and not autorise:
            ancien = self.get(item_id)
            ref = self._verdict_ref().get(item_id)
            if ancien is not None and ref is not None:
                neuf = self.verdict_count({"deliverable": fields.get("deliverable")})
                if neuf < ref:
                    raise BacklogError(
                        "REFUS : le livrable de %s passerait de %d a %d verdicts. Un verdict "
                        "supprime est un defaut que plus rien ne mesure. Si le retrait est "
                        "VOULU, repasse avec allow_verdict_drop=True et dis pourquoi dans le "
                        "commit." % (item_id, ref, neuf))
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
        if "deliverable" in fields:
            self._verdict_bump(item_id, self.verdict_count(self.get(item_id) or {}), autorise)
        return self.get(item_id)

    def _reports_dir(self):
        """Les rapports du harnais qui a ecrit CE backlog — pas ceux du depot courant. Un
        banc jetable pose son backlog.yaml ailleurs et y trouve ses propres etats."""
        return os.path.join(os.path.dirname(os.path.abspath(self.path)), "reports")

    # ---- releve des verdicts : le nombre ne descend jamais tout seul -------------------------
    def _verdict_ref_path(self):
        return os.path.join(os.path.dirname(self.path), ".verdict_counts.json")

    def _verdict_ref(self):
        try:
            with open(self._verdict_ref_path(), encoding="utf-8") as fh:
                return json.load(fh)
        except Exception:  # noqa: BLE001 — pas de releve : rien a comparer, on laisse passer
            return {}

    def _verdict_bump(self, item_id, n, force):
        try:
            d = self._verdict_ref()
            if force or n > d.get(item_id, -1):
                d[item_id] = n
                _atomic_write(self._verdict_ref_path(), json.dumps(d, indent=0, sort_keys=True))
        except Exception:  # noqa: BLE001
            pass

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

        # ------------------------------------------------ LA PREUVE IMPOSSIBLE
        # Un item dont la preuve est IMPOSSIBLE ne se lit pas comme un item qui n'a rien
        # produit. L'etat nomme existe depuis le 12/09 (lib/proof_impossible.sh) ; personne
        # ne le lisait. Il remonte ici, avec DEPUIS QUAND : une impossibilite de 30 secondes
        # et une de six heures ne se lisent pas pareil.
        actionnables = [it for it in self.items if it.get("status") in ACTIONABLE]
        etats = _impossible.read_all(self._reports_dir(),
                                     [it.get("id") for it in actionnables])
        par_id = {it.get("id"): it for it in actionnables}
        lines, dlines = [], []
        if etats:
            lines = ["## Preuve impossible",
                     "%d chantier(s) que le harnais ne peut PAS mesurer en ce moment. Ce "
                     "n'est pas « rien produit » : c'est « rien de mesurable », et voila "
                     "la cause et depuis quand." % len(etats)]
            dlines = ["## Preuve impossible"]
            for iid, st in etats.items():
                feat = (par_id.get(iid) or {}).get("feature", iid)
                lines.extend(_impossible.lines(st, feat))
                dlines.extend(_impossible.digest_lines(st, feat))
        empeche = "\n".join(lines)
        empeche_digest = "\n".join(dlines)

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

        text = "\n\n".join(b for b in (en_cours, empeche, a_tester, bloque, dette) if b)
        if not changed_only:
            return text
        # `--changed` surveille « A tester » ET « Preuve impossible » : la dette ne bouge pas
        # d'elle-meme et ne doit pas reveiller un digest, mais une machine qui ne peut plus
        # mesurer, si. L'age y entre par son PALIER et non a la seconde — sinon le digest se
        # reveillerait a chaque appel et il n'y aurait plus de digest du tout.
        digest = hashlib.sha256(
            (a_tester + "\n" + empeche_digest).encode("utf-8")).hexdigest()
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
    def verdicts_shrunk(self):
        """Les items dont le livrable a PERDU des verdicts depuis le dernier releve.

        2026-09-11 : le superviseur a perdu DEUX verdicts centraux de hdr-display-output en
        raccourcissant la consigne pour tenir sous le plafond. L'item est ensuite passe 15/15
        quatre fois de suite sans que la plainte de fond de l'owner soit mesuree une seule fois.
        Le deversement automatique protege de la TRONCATURE ; il ne protege pas d'une
        SUPPRESSION. Cette garde-ci, si."""
        import json as _json
        chemin = os.path.join(os.path.dirname(self.path), ".verdict_counts.json")
        try:
            with open(chemin, encoding="utf-8") as fh:
                avant = _json.load(fh)
        except Exception:  # noqa: BLE001 — pas de releve : rien a comparer
            return []
        perdus = []
        for it in self.items:
            if it.get("status") not in ACTIONABLE:
                continue
            ref = avant.get(it["id"])
            if ref is None:
                continue
            n = self.verdict_count(it)
            if n < ref:
                perdus.append((it["id"], ref, n))
        return perdus

    def stamp_verdicts(self):
        """Fige le releve courant. A appeler APRES un retrait volontaire et motive."""
        import json as _json
        chemin = os.path.join(os.path.dirname(self.path), ".verdict_counts.json")
        etat = {it["id"]: self.verdict_count(it) for it in self.items
                if it.get("status") in ACTIONABLE}
        _atomic_write(chemin, _json.dumps(etat, indent=0, sort_keys=True))
        return etat

    def verdict_count(self, item):
        """Combien de verdicts numerotes porte un livrable. Sert a interdire qu'il RETRECISSE."""
        import re as _re
        return len(_re.findall(r"\((\d+)\)", item.get("deliverable") or ""))

    def lint(self):
        problems = []
        for iid, avant, apres in self.verdicts_shrunk():
            problems.append("%s : le livrable est passe de %d a %d verdicts — un verdict PERDU "
                            "est un defaut que plus rien ne mesure (11/09 : deux perdus sur "
                            "hdr-display-output, 4 essais verts pour rien)" % (iid, avant, apres))
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
            # Un prompt qui ne se REND PAS n'atteint jamais le worker, et le fichier sur
            # disque reste celui d'avant. Le 2026-09-06, lighting-hdr a passe des heures avec
            # un prompt du 3 septembre qui ignorait le retour de l'owner. Silencieux, donc lint.
            if status in ("open", "in-progress"):
                try:
                    render_prompt(it)
                except Exception as exc:
                    problems.append("%s : PROMPT NON RENDU (%s) — le worker lit le vieux "
                                    "fichier, ton travail ne lui parvient pas"
                                    % (iid, str(exc)[:60]))
            if status == "to-test" and it.get("owner_test", True) and not (it.get("where") or "").strip():
                problems.append("%s : a tester sans « ou regarder » — l'owner ne saurait pas "
                                "quoi regarder" % iid)
            if status == "blocked" and not (it.get("block_reason") or "").strip():
                problems.append("%s : bloque sans block_reason" % iid)
            # `owner_test: false` : preuve MACHINE, l'owner n'a rien a regarder et ne peut
            # donc pas la prononcer. Exiger sa parole gelait tout ce qui en depend.
            if (status == "validated" and not it.get("owner_ok")
                    and it.get("owner_test", True)):
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
        doc = yaml.load(fh, Loader=_Loader) or {}
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

    def coupe(txt, limite):
        """Rogne une rubrique quand meme sans citation ca ne tient pas. Le contrat porte le
        texte entier, donc on peut rogner ici sans rien perdre — c'est tout l'interet du renvoi."""
        if limite is None or not txt or len(txt) <= limite:
            return txt
        return txt[:limite].rstrip() + " […suite dans le contrat]"

    def body(n_quotes, quote_len, sec_len=None):
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
                coupe(item.get("known_cause"), sec_len)
                or "Aucun cycle n'a encore etabli de cause sur cet item."]
        out += ["", "## Livrable",
                coupe(item.get("deliverable"), sec_len)
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
                coupe(item.get("out_of_scope"), sec_len)
                or ("Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja "
                    "validee (`./.autoport/autoport status` ne les liste plus). Pas de "
                    "mesure visuelle : seule la ligne du moteur compte.")]
        return "\n".join(out) + "\n"

    # 2026-09-11 — RIEN NE SE PERD EN RACCOURCISSANT. Owner : « faudrait pas perdre des infos,
    # sinon justement le principe iteratif est un peu detruit. Si trop long, faut p'tetre
    # s'assurer que l'info soit quelque part en complement avec une instruction de le lire de
    # facon obligatoire ». Chaque refus ajoute un verdict ; la consigne est plafonnee. Ce qui en
    # sort atterrit dans le fichier de CONTRAT, que la consigne ordonne de lire.
    #
    # L'echelle de troncature d'origine est conservee TELLE QUELLE : un item qui tenait rend
    # exactement le meme octet qu'avant. Seules deux choses changent :
    #  - des qu'une citation est tronquee ou qu'une rubrique deborde, l'en-tete de renvoi est
    #    ajoute — le worker sait qu'il lit un resume et OU est le reste ;
    #  - le cas « meme reduit, ca ne tient pas » ne leve plus : il rend le plus petit corps
    #    possible, precede du renvoi. Un prompt infabricable laissait le worker sur l'ANCIEN
    #    fichier sans rien dire : c'est ce silence qui coutait des essais.
    complet = body(len(fb) or 1, 10 ** 9)
    if len(complet.encode("utf-8")) <= max_bytes:
        return complet                      # tout tient : aucun renvoi, aucun fichier annexe

    renvoi = ("> LIS D'ABORD `%s` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a %d octets ;\n"
              "> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,\n"
              "> sont dans ce fichier.\n\n" % (contract_rel(item), max_bytes))
    for n, ln in ((3, 400), (2, 300), (1, 220), (1, 140)):
        text = renvoi + body(n, ln)
        if len(text.encode("utf-8")) <= max_bytes:
            return text
    # Meme sans citation ca deborde : les rubriques fixes sont rognees a leur tour. Rien n'est
    # perdu — le contrat, obligatoire, porte le texte entier.
    for sec in (900, 700, 500, 350, 220):
        text = renvoi + body(1, 60, sec)
        if len(text.encode("utf-8")) <= max_bytes:
            return text
    return renvoi + body(0, 0, 150)


def contract_rel(item):
    """Le chemin du contrat complet, a cote de la consigne."""
    rel = item.get("prompt") or ("prompts/item-%s.md" % item["id"])
    return rel[:-3] + "-contrat.md" if rel.endswith(".md") else rel + "-contrat.md"


def render_contract(item):
    """Le contrat COMPLET : rien de tronque, tous les refus de l'owner dans l'ordre."""
    iid = item["id"]
    fb = list(item.get("owner_feedback") or [])
    out = ["# %s — CONTRAT COMPLET" % item.get("feature", iid), "",
           "Ce fichier porte ce que la consigne, plafonnee a %d octets, ne peut pas contenir."
           % PROMPT_MAX,
           "La consigne ORDONNE de le lire : elle est un resume, pas le contrat.", "",
           "## Cause connue", "", item.get("known_cause") or "(aucune)", "",
           "## Livrable — le contrat, en entier", "", item.get("deliverable") or "(aucun)", "",
           "## Hors perimetre", "", item.get("out_of_scope") or "(non precise)", ""]
    if item.get("where"):
        out += ["## Ou l'owner regardera", "", item["where"], ""]
    out += ["## Tous les refus de l'owner, dans l'ordre, mot pour mot", ""]
    if fb:
        for e in fb:
            out.append("### %s" % e.get("date", "?"))
            out.append("> " + (e.get("text", "") or "").replace("\n", " "))
            out.append("")
    else:
        out += ["(aucun retour enregistre sur cet item)", ""]
    out += ["## Pourquoi ce fichier existe", "",
            "Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe",
            "iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est",
            "plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.", ""]
    return "\n".join(out) + "\n"


_FINGERPRINTS = ".autoport/.prompt_fingerprints.json"


def _fp_load():
    try:
        with open(_FINGERPRINTS, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:  # noqa: BLE001 — absent ou illisible : on repart de zero
        return {}


def _stamp_prompt(path, texte):
    try:
        d = _fp_load()
        d[os.path.basename(path)] = hashlib.sha256(texte.encode("utf-8")).hexdigest()
        _atomic_write(_FINGERPRINTS, json.dumps(d, indent=0, sort_keys=True))
    except Exception:  # noqa: BLE001 — l'empreinte est un confort, jamais un blocage
        pass


def prompt_state(item, ap_dir=None):
    """Dit ce qu'est le fichier de consigne sur le disque, sans jamais rien reecrire.

    'a-jour'   : il correspond a ce que le backlog produirait
    'perime'   : c'est NOTRE fabrication, mais l'item a bouge depuis -> a refabriquer
    'a-la-main': il ne correspond a aucune de nos fabrications -> quelqu'un l'a ecrit,
                 on ALERTE et on n'ecrase pas
    'absent'   : pas de fichier
    """
    ap_dir = ap_dir or AP
    rel = item.get("prompt") or ("prompts/item-%s.md" % item["id"])
    path = os.path.join(ap_dir, rel)
    if not os.path.exists(path):
        return "absent"
    sur_disque = open(path, encoding="utf-8").read()
    if sur_disque == render_prompt(item):
        return "a-jour"
    attendu = _fp_load().get(os.path.basename(path))
    if attendu and attendu == hashlib.sha256(sur_disque.encode("utf-8")).hexdigest():
        return "perime"
    return "a-la-main"


def write_prompt(item, ap_dir=None):
    ap_dir = ap_dir or AP
    rel = item.get("prompt") or ("prompts/item-%s.md" % item["id"])
    path = os.path.join(ap_dir, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    texte = render_prompt(item)
    _atomic_write(path, texte)
    # 2026-09-11 — EMPREINTE DE FABRICATION. L'owner l'avait vu venir : « et si ca correspond
    # plus au backlog pour une VRAIE raison ? ». Une consigne ECRITE A LA MAIN est legitime, et
    # la traiter comme perimee reviendrait a l'ecraser. On enregistre donc ce que NOUS avons
    # ecrit : le controle de fraicheur ne bloque que si le fichier est encore notre fabrication
    # ET que l'item a bouge depuis. Un fichier edite a la main n'est jamais bloque ni ecrase.
    _stamp_prompt(path, texte)
    # Le contrat complet n'existe QUE si la consigne a du tronquer : sinon il ferait doublon.
    cpath = os.path.join(ap_dir, contract_rel(item))
    if texte.startswith("> LIS D'ABORD"):
        _atomic_write(cpath, render_contract(item))
    return path
