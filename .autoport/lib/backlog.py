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
import importlib
import json
import hashlib
import os
import subprocess
import sys
import tempfile

try:
    import fcntl
except ImportError:                                   # pragma: no cover - non POSIX
    fcntl = None

import yaml

import importlib.util as _ilu
# par CHEMIN : backlog.py est importe comme `lib.backlog`, comme `backlog`, et par chemin de fichier
_spec = _ilu.spec_from_file_location("autoport_secret_mask", os.path.join(os.path.dirname(os.path.abspath(__file__)), "secret_mask.py"))
_SM = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_SM)

# LE LECTEUR UNIQUE de l'etat nomme « preuve impossible ». Ce module est importe tantot comme
# `lib.backlog` (l'orchestrateur, la CLI) tantot comme `backlog` tout court (validators/
# generic.sh insere `.autoport/lib` dans le chemin) : les deux formes sont essayees, sinon
# `autoport status` mourrait selon QUI l'appelle.
try:                                                  # noqa: SIM105
    from lib import impossible as _impossible
except ImportError:                                   # pragma: no cover
    import impossible as _impossible

# L'AUTORITE du verdict d'un essai — le champ `gate_verdict` de l'item, et en repli
# `logs/<id>/validator-NNN.txt`. Meme double forme d'import, pour la meme raison.
try:                                                  # noqa: SIM105
    from lib import gate_verdict as _gate_verdict
except ImportError:                                   # pragma: no cover
    import gate_verdict as _gate_verdict

# LE FILET AUTOUR DU RECHARGEMENT CI-DESSOUS. Meme double forme d'import, meme raison.
try:                                                  # noqa: SIM105
    from lib import safe_reload as _safe_reload
except ImportError:                                   # pragma: no cover
    import safe_reload as _safe_reload

# VERDICT/dans-l-item — L'AUTORITE VOYAGE AVEC CE FICHIER, TOUJOURS DU MEME MILLESIME.
# `orchestrator.load_backlog` fait `importlib.reload(backlog)` a chaque tour : c'est ce qui
# permet a ce fichier-ci de corriger la file sans redemarrer la boucle (voir `no_device_marker`).
# Mais recharger CE module ne recharge PAS `gate_verdict` : l'import ci-dessus retrouve l'objet
# deja pose dans `sys.modules`, celui du demarrage. Un orchestrateur lance AVANT ce chantier
# aurait donc execute le `machine_promotion_plan` NEUF contre une autorite VIEILLE, sans
# `verdict_from_item` — `AttributeError`, avale par le `try` de `free_machine_proved`, et la
# promotion machine s'arretait en silence jusqu'au prochain redemarrage. Exactement le gel que ce
# chantier corrige, refabrique par le chantier lui-meme. On recharge donc l'autorite ICI, au
# POINT DE PRODUCTION : `backlog.py` et l'autorite qu'il appelle ne peuvent plus diverger.
# RECHARGEMENT/filet — ce rechargement-ci a TUE la boucle le 12/09 a 15:33 : un worker
# renommait `impossible` et `gate_verdict` en meme temps, l'autorite appelait deja le nom neuf,
# `AttributeError` a l'import, remontee jusqu'a `main`, dix minutes d'arret. On ne le retire
# pas — sans lui l'autorite diverge du point de production — on le PROTEGE : l'autorite d'AVANT
# est gardee intacte, l'echec est nomme, et le tour continue en le DISANT.
_safe_reload.reload(_gate_verdict, "backlog:gate_verdict")

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


def _signature_digest(a_tester, empeche_digest, degrade_digest):
    """L'unique signature du digest : « A tester » + « Preuve impossible » + « degrade ».
    La dette ne bouge pas d'elle-meme et ne reveille rien ; une machine qui ne peut plus
    mesurer, si. L'age y entre par son PALIER, jamais a la seconde."""
    return hashlib.sha256(
        (a_tester + "\n" + empeche_digest + "\n" + degrade_digest).encode("utf-8")).hexdigest()
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

# 23/09 — TICKET DE L'OWNER ADOPTE, PAS ENCORE CADRE. `linear_sync.adopt_owner_issues` cree l'item
# `open`, sans porte ni consigne, avec cette note : c'est au superviseur d'ecrire son perimetre.
# Jusque-la, `next_open` le saute (le prendre = le bloquer sur « prompt absent » en fin de file) et
# le lint ne le compte pas comme une consigne OUBLIEE. JAK-265 a rougi deux tests de la suite du
# harnais, imputes au chantier qui tournait quand l'owner a ouvert son ticket.
AWAITING_FRAMING_NOTE = "A CADRER : porte, livrable et perimetre a ecrire par le superviseur avant tout essai."


def awaiting_framing(it):
    """Un ticket de l'owner adopte que le superviseur n'a pas encore dote d'une consigne."""
    return (it.get("notes") or "").startswith(AWAITING_FRAMING_NOTE) and not it.get("prompt")
ACTIONABLE = ("open", "in-progress", "to-test", "blocked")
OPS = {"==": lambda a, b: a == b, "!=": lambda a, b: a != b,
       "<": lambda a, b: a < b, "<=": lambda a, b: a <= b,
       ">": lambda a, b: a > b, ">=": lambda a, b: a >= b}


class BacklogError(Exception):
    pass


class ArchivedItem(BacklogError):
    """ARCHIVE-OWNER/ — un statut pose sur un item que l'owner a ARCHIVE (23/09,
    harness-owner-archive-of-running-item-is-safe). L'archivage est SON geste : un essai qui finit
    apres lui ne le defait pas en reposant « open », « to-test » ou « validated » par-dessus. Le
    refus est ICI, sous le verrou et sur le disque relu, parce que l'orchestrateur ecrit sur un
    backlog lu AVANT l'essai. Desarchiver reste possible, mais explicitement : `unarchive=True`."""
    archived_by_owner = True


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
    # Un secret CONNU (~/.config/autoport) n'entre jamais dans le backlog, quel que soit le chemin qui l'y porte.
    return _SM.scrub_known(head + yaml.dump(doc, Dumper=D, allow_unicode=True, sort_keys=False, width=100))[0]


def build_sha():
    """Le sha du build courant : HEAD du depot, tronque. Vide si git est indisponible."""
    try:
        out = subprocess.run(["git", "-C", os.path.dirname(AP), "rev-parse", "HEAD"],
                             capture_output=True, text=True, timeout=20)
        return out.stdout.strip()[:16] if out.returncode == 0 else ""
    except Exception:
        return ""


def fb_append(target, entry, skip_same_text=False):
    """Ajoute `entry` en queue de l'owner_feedback de `target` (un item RELU sous le verrou).
    Rend False si le retour y est deja : meme `via.comment`, ou meme texte si `skip_same_text`."""
    fb = list(target.get("owner_feedback") or [])
    cid = (entry.get("via") or {}).get("comment") if isinstance(entry.get("via"), dict) else None
    deja = (skip_same_text and any(isinstance(x, dict) and x.get("text") == entry.get("text")
                                   for x in fb)) or \
           (cid and any(isinstance(x, dict) and isinstance(x.get("via"), dict)
                        and x["via"].get("comment") == cid for x in fb))
    if not deja:
        fb.append(entry)
    target["owner_feedback"] = fb
    return not deja


def validation_fields(text, date, sha=None, via=None):
    """(retour, champs) du feu vert de l'owner : sa phrase, la date, le sha du build teste."""
    e = {"date": date, "text": text}
    if via:
        e["via"] = dict(via)
    return e, {"status": "validated", "priority": None,
               "owner_ok": {"date": date, "text": text,
                            "build_sha": sha if sha is not None else build_sha()}}


class Backlog:
    def __init__(self, doc, path):
        self.path = os.fspath(path)
        self.version = doc.get("version", 1)
        self.items = list(doc.get("items") or [])
        # Ce que la derniere `machine_proved_to_validated` a REFUSE de promouvoir, et pourquoi.
        self.machine_promotion_refused = []

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

    def machine_promotion_plan(self):
        """PROMOTION/relit-le-verdict — pour chaque `to-test` : promouvoir ou non, et POURQUOI.

        La decision et son ECRITURE sont separees ici parce que la decision se MESURE : un banc
        jetable appelle cette fonction sur une copie du backlog et compare son plan aux deux
        controles qu'il a SEMES — un item dont la porte a tenu, qui doit sortir ; un item dont
        elle n'a pas tenu, qui doit rester.

        DEUX conditions, jamais une seule :
          `owner_test: false` — l'item dit lui-meme n'avoir rien a montrer a l'owner ;
          `porte tenue`       — le DERNIER journal de validation de l'item porte « [<id> ok] »
                                et aucun « [<id> FAIL] ». C'est le verdict de `generic.sh`,
                                relu tel qu'il a ete ecrit, jamais une intention.

        INCONNU = DEFAUT : pas de journal, ou un journal muet, et l'item RESTE. On ne valide
        rien sur un silence.

        VERDICT/dans-l-item (2026-09-12) — LE CHAMP DE L'ITEM EST LU EN PREMIER, LE JOURNAL
        N'EST QU'UN REPLI. `logs/<id>/validator-NNN.txt` est exclu du depot par `.gitignore` :
        sur un clone neuf, ou apres une purge de journaux, il n'existe pas, et cette fonction
        rendait `journal-absent` pour TOUS les items parques. Fail-CLOSED, donc rien de faux
        n'etait valide — mais un item dont la porte avait REELLEMENT tenu gelait pour toujours,
        et ses dependants avec. La porte ecrit desormais son verdict dans l'item (voir
        `orchestrator.pronounce_gate`), et le backlog est VERSIONNE. `source` dit d'ou vient
        chaque reponse : `item` ou `journal`. Un repli n'est pas une faute — c'est ainsi que se
        lisent les items parques AVANT ce chantier — mais il est COMPTE et publie, parce qu'un
        repli silencieux est exactement ce qui a permis a la panne de durer deux jours.
        """
        logs = self._logs_dir()
        plan = []
        for iid, owner_test in self.parked_for_owner():
            v = _gate_verdict.verdict_from_item(self.get(iid) or {})
            if v is None:
                # LE REPLI, et lui seul : le champ manque ou ne se lit pas.
                v = dict(_gate_verdict.validator_verdict(logs, iid),
                         source=_gate_verdict.SRC_JOURNAL)
            plan.append({"id": iid, "owner_test": bool(owner_test), "green": bool(v["green"]),
                         "verdict": v["reason"], "journal": v["file"], "seq": v["seq"],
                         "line": v["line"], "source": v["source"],
                         "promote": (not owner_test) and bool(v["green"])})
        return plan

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

        2026-09-12 (harness-close-gate-code-free) — ELLE RELIT LE VERDICT. Elle s'appelle
        « machine_proved » et ne verifiait QUE `owner_test: false` : elle croyait la porte sur
        parole, parce que seule la porte posait `to-test`, et apres sa porte. Ce n'est plus une
        garantie depuis qu'elle a un appelant — un `to-test` pose a la main, par un superviseur
        ou par une future voie de parking, serait valide sans qu'aucune preuve n'ait tenu. La
        garde manquante etait « la porte a-t-elle tenu », pas « l'owner a-t-il regarde ». LE NOM
        RESTE, c'est la fonction qui verifie desormais ce qu'il promet.

        Ce qu'elle REFUSE est rendu dans `self.machine_promotion_refused` : un `owner_test:
        false` qu'on ne peut pas promouvoir gele tout ce qui en depend, exactement comme
        `perf-ocean-idle` du 10 au 12/09. Ca se DIT a chaque tour, jamais ca se tait.
        """
        promus = []
        self.machine_promotion_refused = []
        for e in self.machine_promotion_plan():
            if e["promote"]:
                try:
                    self.set_status(e["id"], "validated")
                except ArchivedItem:     # ARCHIVE-OWNER/ : archive par l'owner depuis la lecture
                    continue
                promus.append(e["id"])
            elif not e["owner_test"]:
                # VERDICT/origine-dite
                # L'ORIGINE VOYAGE AVEC LE VERDICT (signalement 9 du 12/09). Ce triplet rendait
                # `(id, verdict, journal)` : qui l'imprime ne peut pas dire si le verdict vient
                # du CHAMP de l'item ou du JOURNAL de repli, et une origine non dite se lit
                # comme l'origine attendue. `source` est deja calculee juste au-dessus, dans
                # `machine_promotion_plan` ; elle ne se devine plus a l'affichage.
                self.machine_promotion_refused.append(
                    (e["id"], e["verdict"], e["journal"], e["source"]))
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
            if awaiting_framing(it):
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
        if "owner_feedback" in fields:
            # 23/09 : une liste passee ici est une copie TENUE EN MEMOIRE ; la reposer efface tout
            # retour ajoute par un autre ecrivain depuis sa lecture. On refuse au point d'ecriture.
            raise BacklogError("REFUS : owner_feedback ne se pose pas par set_status (liste tenue en "
                               "memoire = retour perdu) ; passer par add_owner_feedback ou validate")
        autorise = bool(fields.pop("allow_verdict_drop", False))
        desarchive = bool(fields.pop("unarchive", False))
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
            if target.get("status") == "archived" and status != "archived" and not desarchive:
                raise ArchivedItem("REFUS : %s est ARCHIVE sur le disque ; « %s » n'est pas ecrit "
                                   "par-dessus (desarchiver : unarchive=True)" % (item_id, status))
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

    def set_scope(self, item_id, scope, source="-"):
        """PERIMETRE/champ-explicite — LE SEUL ECRIVAIN de `code_scope`, et il prend le verrou.

        Signalement 8 du 12/09 : le champ fait foi depuis ce matin, et 240 items sur 242 ne le
        portaient pas — leur perimetre etait donc DEVINE dans leur prose, a chaque fermeture.
        Peupler ce champ a la main dans `backlog.yaml` ne marche pas : l'orchestrateur reecrit
        le fichier en continu et efface l'edition en quelques secondes. On passe donc par ici,
        comme `set_status` : verrou, relecture du disque, modification, rename atomique.

        `scope` DOIT etre une valeur que `lib/gate_verdict.py` sait lire. Un champ illisible
        n'est pas un perimetre : il est compte a part et la porte retombe sur la devinette. On
        refuse plutot que d'ecrire quelque chose que l'autorite ne reconnait pas.
        """
        valeur = _gate_verdict.normalise(scope)
        if (valeur not in _gate_verdict.SCOPE_SANS_CODE
                and valeur not in _gate_verdict.SCOPE_AVEC_CODE):
            raise BacklogError(
                "perimetre inconnu : %r. `lib/gate_verdict.py` lit %s (sans code) et %s (avec "
                "code) ; ecrire autre chose rendrait le champ ILLISIBLE, et la porte "
                "retomberait sur la prose — le defaut qu'on corrige."
                % (scope, "|".join(_gate_verdict.SCOPE_SANS_CODE),
                   "|".join(_gate_verdict.SCOPE_AVEC_CODE)))
        with _Lock(self.path):
            fresh = _read(self.path)
            target = None
            for it in fresh["items"]:
                if it.get("id") == item_id:
                    target = it
                    break
            if target is None:
                raise BacklogError("item inconnu : %s" % item_id)
            target[_gate_verdict.SCOPE_FIELD] = valeur
            if source and source != "-":
                target["code_scope_source"] = str(source)
            _atomic_write(self.path, _dump(fresh))
        self.items = fresh["items"]
        self.version = fresh.get("version", 1)
        return self.get(item_id)

    def _reports_dir(self):
        """Les rapports du harnais qui a ecrit CE backlog — pas ceux du depot courant. Un
        banc jetable pose son backlog.yaml ailleurs et y trouve ses propres etats."""
        return os.path.join(os.path.dirname(os.path.abspath(self.path)), "reports")

    def _logs_dir(self):
        """Les journaux de validation du harnais qui a ecrit CE backlog. Jumeau exact de
        `_reports_dir` : un banc jetable pose son backlog ailleurs et y lit SES verdicts."""
        return os.path.join(os.path.dirname(os.path.abspath(self.path)), "logs")

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

    def add_owner_feedback(self, item_id, date, text, via=None):
        """`via` dit D'OU vient le retour (voir `owner_sla.EXCLUDED_SOURCES`) : l'identifiant du
        commentaire Linear, ou la source nommee. Sans lui, `owner_sla` doit re-deviner le
        commentaire par son texte, et un retour qu'il ne retrouve pas n'a plus de delai.

        2026-09-23 — UN RETOUR NE SE PERD PLUS. Cette methode reposait la liste LUE EN MEMOIRE
        (et le statut lu en memoire) via `set_status` : un retour ajoute par un autre ecrivain
        (synchro Linear, `autoport feedback`) entre le chargement et l'ecriture etait efface.
        Desormais l'ajout se fait sous le verrou, sur l'item RELU du disque, et n'y touche que
        la liste, en AJOUT. Voir `lib/census/harness-owner-feedback-write-never-loses-a-return.sh`."""
        e = {"date": date, "text": text}
        if via:
            e["via"] = dict(via)
        return self._append_owner_feedback(item_id, e)

    def _append_owner_feedback(self, item_id, entry, skip_same_text=False, status=None, **fields):
        """LE SEUL AJOUT d'owner_feedback de ce module : verrou, relecture du disque, ajout en
        queue de la liste RELUE, rename atomique. Jamais une liste tenue en memoire.
        Un commentaire Linear deja present (meme `via.comment`) n'est pas recopie : la
        verification que l'appelant a faite sur sa copie peut etre perimee sous le verrou.
        `skip_same_text` : n'ajoute pas si un retour porte deja ce texte (feu vert de l'owner).
        `status`/`fields` : poses dans la MEME ecriture (feu vert) ; sans `status`, le statut
        RELU est garde — jamais celui qu'on avait en memoire."""
        def change(target, _items):
            fb_append(target, entry, skip_same_text)
            if status is not None:
                target["status"] = status
            for k, v in fields.items():
                target[k] = v
            return True
        self.update(item_id, change)
        return self.get(item_id)

    def update(self, item_id, change):
        """DECIDER ET ECRIRE SUR L'ITEM RELU (23/09). Verrou, relecture du disque, puis
        `change(item, items)` — l'item et la liste RELUS, jamais la copie en memoire —, qui
        modifie l'item en place et rend une valeur VRAIE pour ecrire (fausse : rien n'est
        ecrit). Rend ce que `change` a rendu.

        La synchro Linear decidait d'un deplacement de l'owner sur le statut LU EN MEMOIRE et
        recomposait `notes` depuis cette copie : une note ou un statut ecrit entre-temps par un
        autre ecrivain (orchestrateur, superviseur) etait ecrase. Un appelant qui doit garder
        le statut ou prolonger `notes` passe par ici, pas par `set_status`. Voir
        `lib/census/harness-linear-owner-move-reads-fresh-item.sh`."""
        with _Lock(self.path):
            fresh = _read(self.path)
            target = next((it for it in fresh["items"] if it.get("id") == item_id), None)
            if target is None:
                raise BacklogError("item inconnu : %s" % item_id)
            avant_fb = list(target.get("owner_feedback") or [])
            avant_livrable = target.get("deliverable")
            res = change(target, fresh["items"])
            if res:
                if target.get("status") not in STATUSES:
                    raise BacklogError("statut inconnu : %s (attendu %s)"
                                       % (target.get("status"), "|".join(STATUSES)))
                if target.get("status") == "blocked" and not target.get("block_reason"):
                    raise BacklogError("un item bloque doit porter block_reason")
                if list(target.get("owner_feedback") or [])[:len(avant_fb)] != avant_fb:
                    raise BacklogError("REFUS : owner_feedback ne se RACCOURCIT ni ne se reecrit "
                                       "(ajout en queue seulement)")
                if target.get("deliverable") != avant_livrable:
                    raise BacklogError("REFUS : le livrable passe par set_status (releve des verdicts)")
                _atomic_write(self.path, _dump(fresh))
        self.items = fresh["items"]
        self.version = fresh.get("version", 1)
        return res

    def set_feedback_via(self, item_id, date, text, via):
        """Pose `via` sur UN retour existant, retrouve par (date, texte), sous le verrou et sur
        le disque RELU : la reprise des anciens retours ne doit jamais ecraser un retour que la
        synchro aurait ajoute entre-temps. Rend le nombre de retours touches."""
        n = 0
        with _Lock(self.path):
            fresh = _read(self.path)
            for it in fresh["items"]:
                if it.get("id") != item_id:
                    continue
                for e in it.get("owner_feedback") or []:
                    if (isinstance(e, dict) and not e.get("via") and str(e.get("date")) == str(date)
                            and e.get("text") == text):
                        e["via"] = dict(via)
                        n += 1
            if n:
                _atomic_write(self.path, _dump(fresh))
        self.items = fresh["items"]
        return n

    def validate(self, item_id, text, date=None, sha=None, via=None):
        """Le feu vert de l'owner : sa phrase, la date, le sha du build teste."""
        date = date or datetime.date.today().isoformat()
        e, champs = validation_fields(text, date, sha, via)
        # Meme chemin que `add_owner_feedback` : la liste est relue sous le verrou (23/09).
        return self._append_owner_feedback(item_id, e, skip_same_text=True, **champs)

    # ---------------------------------------------------------------- rapport
    def _testable_now(self, it):
        """Testable dans le build courant : livre recemment, ou retour recent de l'owner."""
        fb = it.get("owner_feedback") or []
        last_fb = fb[-1]["date"] if fb else ""
        return max(it.get("delivered") or "", last_fb) >= CURRENT_BUILD_SINCE

    # NOMMAGE/tous-les-items — L'ETAT SE LIT PARTOUT OU IL EXISTE
    # (harness-impossible-single-namer, 12/09). Ce rapport n'interrogeait que les items
    # ACTIONABLE : un etat debout sur un item `validated`, ou sur un id qui n'est plus dans le
    # backlog du tout, n'apparaissait JAMAIS dans le texte de l'owner — le fichier etait bien
    # sur le disque, et personne ne le nommait. C'est le meme defaut que celui qu'on vient de
    # corriger un cran plus haut : une population filtree a la lecture rend le producteur muet.
    # La purge en couvre une partie, pas la totalite : elle ne s'execute qu'au changement d'item
    # et au debut d'une course, et un etat pose APRES la derniere course reste invisible jusqu'a
    # la suivante. On lit donc CE QUI EST SUR LE DISQUE, et le statut de l'item est imprime a
    # cote — « hors file » n'est pas « en cours », et les confondre serait l'autre faute.
    def impossible_states(self):
        """Les etats « preuve impossible » DEBOUT, tous items confondus, file ou pas."""
        return _impossible.read_all(self._reports_dir())

    # TEXTE/bloc-borne
    # LE BLOC EST BORNE, ET IL DIT CE QU'IL NE MONTRE PAS (signalement 7 du 12/09). Depuis que
    # ce renderer lit TOUT etat debout du disque — file ou pas — sa longueur n'a plus de borne :
    # un disque qui garde trente etats perimes noie le texte rendu a l'owner sous trente
    # paragraphes. Une borne qui se TAIT serait pire qu'un texte long : elle cacherait
    # exactement l'etat qu'on cherche. On en montre donc un nombre fixe, LES PLUS ANCIENS
    # D'ABORD — une impossibilite de six heures passe devant une de trente secondes — et on
    # PUBLIE le compte de ceux qu'on n'affiche pas.
    BLOC_IMPOSSIBLE_MAX = 8

    def bloc_impossible(self, etats, borne=None):
        """Le bloc rendu a l'owner, et sa version pour le digest. UN SEUL renderer : un bras
        de mesure qui reecrirait ce texte ne mesurerait que sa propre recopie.

        `borne` : combien d'etats au plus sont DETAILLES. Les autres sont comptes et nommes sur
        une ligne — jamais tus."""
        borne = self.BLOC_IMPOSSIBLE_MAX if borne is None else int(borne)
        par_id = {it.get("id"): it for it in self.items}
        lines, dlines = [], []
        if etats:
            # LES PLUS ANCIENS D'ABORD : l'age est la grandeur qui decide, pas l'ordre du disque.
            ordre = sorted(etats.items(),
                           key=lambda kv: -int((kv[1] or {}).get("since_s") or 0))
            montres = ordre if borne <= 0 else ordre[:borne]
            caches = [] if borne <= 0 else ordre[borne:]
            lines = ["## Preuve impossible",
                     "%d chantier(s) que le harnais ne peut PAS mesurer en ce moment. Ce "
                     "n'est pas « rien produit » : c'est « rien de mesurable », et voila "
                     "la cause et depuis quand." % len(etats)]
            dlines = ["## Preuve impossible"]
            for iid, st in montres:
                it = par_id.get(iid)
                feat = (it or {}).get("feature", iid)
                statut = (it or {}).get("status") or "hors backlog"
                if statut not in ACTIONABLE:
                    feat = "%s [hors file : %s]" % (feat, statut)
                lines.extend(_impossible.lines(st, feat))
                dlines.extend(_impossible.digest_lines(st, feat))
            if caches:
                noms = ", ".join(iid for iid, _ in caches[:12])
                if len(caches) > 12:
                    noms += ", …"
                queue = ("+ %d etat(s) de plus, non detailles ici (borne %d, les plus anciens "
                         "d'abord) : %s" % (len(caches), borne, noms))
                lines.append(queue)
                # LE DIGEST PORTE LE COMPTE, PAS LES NOMS : son hash ne doit pas changer parce
                # qu'un item s'est ajoute a une liste que personne ne lit.
                dlines.append("+ %d etat(s) non detailles (borne %d)" % (len(caches), borne))
        return "\n".join(lines), "\n".join(dlines)

    def bloc_impossible_counts(self, etats, borne=None):
        """Combien d'etats le bloc DETAILLE, et combien il n'affiche pas. Publie a part : une
        borne dont personne ne connait l'effet n'est pas une borne."""
        borne = self.BLOC_IMPOSSIBLE_MAX if borne is None else int(borne)
        total = len(etats or {})
        montres = total if borne <= 0 else min(total, borne)
        return {"total": total, "montres": montres, "caches": total - montres,
                "borne": borne}

    def signature_digest(self):
        """La MEME signature que `--changed`, SANS la consommer.

        `status --changed` ecrit son memo : le PREMIER qui lit consomme la notification pour
        tout le monde. La veille sans modele (lib/wake_gate.py) doit savoir si quelque chose a
        bouge sans voler cette notification au superviseur — elle appelle donc ceci et garde
        son propre memo. UN SEUL calcul de signature dans le harnais : un second, meme
        identique a la ligne pres, derivrait le jour ou l'un des deux serait modifie."""
        self.status_report(changed_only=False)
        return _signature_digest(*self._blocs_digest)

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
        empeche, empeche_digest = self.bloc_impossible(self.impossible_states())

        # ------------------------------------- LE HARNAIS TOURNE-T-IL SUR DU CODE VIEUX ?
        # RECHARGEMENT/filet. L'etat degrade est LU sur le disque : la boucle qui a refuse le
        # rechargement est souvent un AUTRE processus que celui qui rend ce texte. Le digest
        # ne prend que l'IDENTITE du defaut, jamais le compte de tours — sinon il se
        # reveillerait a chaque tour et cesserait d'etre un digest.
        degrade, degrade_digest = _safe_reload.owner_block()

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

        # LE COUT DU SUPERVISEUR, PUBLIE ICI ET NULLE PART AILLEURS. Il est HORS du hash du
        # digest, volontairement : un montant qui bouge a chaque appel reveillerait le digest
        # en permanence et il n'y aurait plus de digest du tout. Le bloc est LU quand le
        # digest sort pour une autre raison. Il ne peut pas faire echouer `status` : le
        # compteur est un compteur, pas une dependance.
        # Les trois blocs qui FONT la signature, gardes pour `signature_digest()`. On les
        # range ici plutot que de les recalculer ailleurs : deux calculs de la meme signature
        # divergent le jour ou l'un des deux est modifie.
        self._blocs_digest = (a_tester, empeche_digest, degrade_digest)

        cout = ""
        try:
            try:
                from . import supervisor_cost as _sc
            except ImportError:
                import supervisor_cost as _sc
            cout = _sc.bloc_owner(_sc.releve(_sc.charger_cache()))
        except Exception:                                  # noqa: BLE001 — jamais fatal
            cout = ""

        # ------------------------- LA FILE « RETOUR OWNER » EST-ELLE SERVIE A UN MORT ?
        # EN TETE, avant meme l'etat degrade : un retour de l'owner que personne ne lit est
        # le seul defaut de ce rapport dont l'owner lui-meme est la victime. Le releve des
        # DELAIS vient du cache pose par la synchro (30 s) — aucun reseau ici — mais le
        # LECTEUR est remesure a l'instant, sur /proc : c'est la grandeur qui bascule.
        # L'AGE DU RELEVE passe AVANT l'alerte et hors de son `try` : si la synchro est morte, ce
        # qui suit decrit un etat fige, et une rubrique muette y vaudrait « tout va bien ».
        orphelin = ""
        _age_releve = []
        try:
            try:
                from . import owner_sla as _osla, supervisor_alive as _sa
            except ImportError:
                import owner_sla as _osla, supervisor_alive as _sa
            _recs, _at = _osla.load_cache()
            _age_releve = _osla.cache_lines(_at)
            if _recs:
                _rel = _sa.probe()
                _al = _osla.evaluate(_recs, _rel)
                orphelin = "\n".join(_osla.status_lines(_al, _rel, at=_at))
        except Exception:                                  # noqa: BLE001 — jamais fatal
            orphelin = ""
        orphelin = "\n".join(_age_releve + ([orphelin] if orphelin else []))

        text = "\n\n".join(b for b in (orphelin, degrade, en_cours, empeche, a_tester, bloque,
                                       dette, cout) if b)
        if not changed_only:
            return text
        # `--changed` surveille « A tester » ET « Preuve impossible » : la dette ne bouge pas
        # d'elle-meme et ne doit pas reveiller un digest, mais une machine qui ne peut plus
        # mesurer, si. L'age y entre par son PALIER et non a la seconde — sinon le digest se
        # reveillerait a chaque appel et il n'y aurait plus de digest du tout.
        digest = _signature_digest(a_tester, empeche_digest, degrade_digest)
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
                # 2026-09-13 — LE BACKLOG DOIT DESIGNER SA CONSIGNE, pas seulement pouvoir la
                # fabriquer. Le controle au-dessus ne juge que le RENDU ; il rend le meme vert
                # quand `prompt` est None. Le superviseur a cree `firstperson-hd-hide`
                # (1c197e3620) en ECRIVANT sa consigne et son contrat sur le disque, mais sans
                # jamais poser le champ : `orchestrator.py` teste `item.get("prompt")` AVANT
                # d'aller voir le fichier, et aurait bloque l'item sur « prompt absent » alors
                # que le fichier etait la, a cote. Un essai brule pour un champ vide.
                # Les consignes sont a cote du backlog qu'elles servent : un backlog sans
                # dossier `prompts/` n'en attend aucune — les backlogs jetables de la suite
                # sont dans ce cas, et leur faire ce reproche rendrait le reproche illisible.
                sacoche = os.path.join(os.path.dirname(os.path.abspath(self.path)), "prompts")
                if os.path.isdir(sacoche):
                    rel = it.get("prompt")
                    if not rel and awaiting_framing(it):
                        pass  # a cadrer : `next_open` ne le prend pas, rien a oublier encore
                    elif not rel:
                        problems.append("%s : le backlog ne DESIGNE aucune consigne "
                                        "(`prompt` vide) — l'orchestrateur bloquera l'item "
                                        "sur « prompt absent », que le fichier existe ou non"
                                        % iid)
                    elif not os.path.exists(os.path.join(os.path.dirname(sacoche), rel)):
                        problems.append("%s : CONSIGNE ABSENTE du disque (%s) — "
                                        "l'orchestrateur bloquera l'item au lieu de le "
                                        "prendre" % (iid, rel))
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
            # LE NOM DE LA PREUVE VIENT DE L'AUTORITE, jusque dans la consigne rendue au
            # worker : une consigne qui nomme un fichier que plus personne n'ecrit envoie
            # chercher au mauvais endroit, et c'est le pire endroit ou se tromper de nom.
            out.append("`%s %s %s` dans `reports/%s/%s`."
                       % (gate["key"], gate["op"], gate["value"], iid,
                          _impossible.arm_name("proof", "")))
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


# 2026-09-23 — ANCRE SUR CE FICHIER, jamais sur le cwd. Le chemin etait relatif
# (".autoport/.prompt_fingerprints.json") : un write_prompt lance depuis `.autoport/` ou d'ailleurs
# ecrivait l'empreinte a cote, ou nulle part (dossier absent, exception avalee), et la consigne relue
# depuis la racine passait « a-la-main » : plus jamais refabriquee, sans un mot.
_FINGERPRINTS = os.path.join(AP, ".prompt_fingerprints.json")


def _fp_path(ap_dir=None):
    """Le magasin d'empreintes du dossier .autoport qui porte la consigne : le notre par defaut."""
    if not ap_dir or os.path.abspath(ap_dir) == os.path.abspath(AP):
        return _FINGERPRINTS
    return os.path.join(os.path.abspath(ap_dir), ".prompt_fingerprints.json")


def _fp_load(ap_dir=None):
    try:
        with open(_fp_path(ap_dir), encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:  # noqa: BLE001 — absent ou illisible : on repart de zero
        return {}


def _stamp_prompt(path, texte, ap_dir=None):
    fp = _fp_path(ap_dir)
    try:
        # 2026-09-23 — SOUS VERROU, relire-fusionner-ecrire. Sans lui, orchestrateur + linear_sync +
        # superviseur relisaient le meme magasin et le dernier a ecrire effacait l'empreinte des autres :
        # la consigne repassait « a-la-main », plus jamais refabriquee (harness-prompt-fingerprint-store-locked).
        with _Lock(fp):
            if os.path.exists(fp):
                with open(fp, encoding="utf-8") as fh:
                    d = json.load(fh)   # illisible : on LEVE, jamais un {} qui effacerait tout le magasin
            else:
                d = {}
            d[os.path.basename(path)] = hashlib.sha256(texte.encode("utf-8")).hexdigest()
            _atomic_write(fp, json.dumps(d, indent=0, sort_keys=True))
    except Exception as e:  # noqa: BLE001 — l'empreinte est un confort, jamais un blocage...
        # ...mais jamais muette : sans elle, la consigne passera « a-la-main » au prochain changement.
        print("backlog: empreinte NON ecrite pour %s dans %s : %s" % (os.path.basename(path), fp, e),
              file=sys.stderr)


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
    attendu = _fp_load(ap_dir).get(os.path.basename(path))
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
    _stamp_prompt(path, texte, ap_dir)
    # Le contrat complet n'existe QUE si la consigne a du tronquer : sinon il ferait doublon.
    cpath = os.path.join(ap_dir, contract_rel(item))
    if texte.startswith("> LIS D'ABORD"):
        _atomic_write(cpath, render_contract(item))
    return path
