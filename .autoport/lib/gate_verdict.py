#!/usr/bin/env python3
"""lib/gate_verdict.py — L'AUTORITE de deux questions que la porte de fermeture se posait
chacune dans son coin, et mal.

    1. « CET ITEM DOIT-IL LIVRER DU CODE DE PORTAGE ? »   -> `code_free_item`
       GATE 1 (`orchestrator.py`) refuse un vert obtenu sans une ligne de code moteur. Un item
       de harnais, dont le perimetre INTERDIT `game/ android/ goalc/ goal_src/`, echouait donc
       FORCEMENT a sa premiere fermeture tant que personne n'avait pose `no_code: true` a la
       main. Mesure du 2026-09-12 : l'essai 1 de `harness-proof-props-pin`, porte machine
       TENUE, refuse pour un drapeau absent — un essai entier, et le meme cout a chaque nouvel
       item de harnais. La question a une reponse LISIBLE : le perimetre de l'item la dit en
       toutes lettres. On la lit, au LANCEMENT, et GATE 1 s'en sert.

    2. « LA PORTE A-T-ELLE TENU SUR CET ITEM ? »          -> `validator_verdict`
       `backlog.machine_proved_to_validated` promeut un `to-test` qui dit n'avoir rien a
       montrer a l'owner (`owner_test: false`). Elle s'appelle « machine_proved » et ne relisait
       AUCUN verdict : elle croyait la porte sur parole, parce que seule la porte posait
       `to-test`. Un `to-test` pose a la main — par un superviseur, par une future voie de
       parking — serait donc valide sans qu'aucune preuve n'ait tenu. Le verdict existe, ecrit
       par la machine : `logs/<id>/validator-NNN.txt`. On le relit.

    3. « QU'A RENDU LA PORTE, UNE FOIS LES JOURNAUX EFFACES ? »  -> `gate_record` / `verdict_from_item`
       La reponse du 12/09 vivait dans `logs/<id>/validator-NNN.txt`, et `.gitignore` exclut tout
       `.autoport/logs/`. Sur un clone neuf, ou apres une purge de journaux, le verdict est
       INTROUVABLE : la promotion choisit de ne pas promouvoir — le bon defaut — et un item
       PROUVE gele pour toujours, en gelant ses dependants. C'est `perf-ocean-idle`, en pire,
       parce que cette fois aucune relance ne le repare. Le backlog, lui, est la seule verite du
       travail ET il est versionne : la porte y ECRIT desormais ce qu'elle a rendu, et la
       promotion lit ce champ EN PREMIER. Le journal n'est plus qu'un REPLI, et chaque repli est
       COMPTE.

    Et la question 1 cesse de dependre d'une tournure de phrase : un CHAMP explicite
    (`code_scope`) fait foi, la prose n'est plus qu'un repli, lui aussi COMPTE.

MARQUEURS. `GATE1/perimetre-sans-code`, `PROMOTION/relit-le-verdict`, `VERDICT/dans-l-item` et
`PERIMETRE/champ-explicite` datent ces chantiers dans les fichiers qu'ils touchent. Le banc
remonte `git log` jusqu'au premier commit qui ne les porte PAS pour construire son bras
d'AVANT : lu a `HEAD:`, un temoin d'avant s'accuse lui-meme des le commit ou il nait.

INCONNU = DEFAUT, des trois cotes : un perimetre muet n'interdit rien (on exige le code), un
verdict introuvable n'a pas tenu (on ne promeut pas), un champ de verdict illisible n'est pas
un verdict (on retombe sur le journal, et le repli se compte).
"""
from __future__ import annotations

import datetime
import hashlib
import os
import re
import sys
import unicodedata

# L'AUTORITE DE NOMMAGE des fichiers d'une course. Ce module PRONONCE le verdict d'un essai et
# empreinte la preuve jugee : s'il fabriquait le nom du fichier de son cote, il deviendrait un
# DEUXIEME nommeur, et le jour ou le nom bouge il empreinterait un fichier que plus personne
# n'ecrit — verdict rendu sur une absence, sans un mot. `impossible` n'importe qu'os/re/sys/time :
# aucun cycle possible.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from lib import impossible as _noms
except ImportError:
    import impossible as _noms

# ============================================================ GATE1/perimetre-sans-code =====
# LES TOURNURES QUE LE SUPERVISEUR ECRIT dans `out_of_scope` quand il ouvre un item dont le
# perimetre interdit le code du jeu. Elles sont lues NORMALISEES : accents retires, casse
# rabattue, blancs ramenes a un seul. Etalonnage sur le backlog livre (233 items) : 9 items
# reconnus, 9 items portant `no_code: true`, et ce sont LES MEMES — aucun faux positif, aucun
# faux negatif. Le chiffre est republie a chaque course par le recensement : le jour ou une
# tournure neuve apparait, le compte de « reconnu sans drapeau » le dira.
CODE_FREE_PATTERNS = (
    r"ne touche a? ?aucun code",
    r"ne touche pas au code du jeu",
    r"ne modifie aucun code",
    r"ne livre aucun code",
    r"aucun code du jeu",
    r"aucun code moteur",
)

# Les champs d'un item ou le perimetre se dit. `out_of_scope` est le seul aujourd'hui ; les
# autres sont la pour qu'une tournure deplacee ne devienne pas un angle mort silencieux.
SCOPE_FIELDS = ("out_of_scope", "scope", "hors_perimetre")

LAUNCH_JOURNAL = "no-code-at-launch.log"


def normalise(texte) -> str:
    """Accents retires, casse rabattue, blancs ramenes a un seul."""
    s = unicodedata.normalize("NFD", str(texte or ""))
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", s.lower()).strip()


# ============================================================ PERIMETRE/champ-explicite =====
# LE CHAMP QUI FAIT FOI. Signalement du 12/09 : « une autorite qui depend de la facon dont
# j'ecris une phrase n'est pas une autorite ». `CODE_FREE_PATTERNS` ci-dessus reconnait SIX
# tournures francaises ; un item ouvert avec « n'ajoute aucun C++ » ou « harnais seulement »
# n'est pas reconnu, et la porte redemande le code — le defaut d'origine, un essai brule, revient
# en silence pour cette formulation. Le perimetre a donc un CHAMP : `code_scope`. Il decide dans
# LES DEUX SENS, et il passe devant tout le reste, y compris `no_code`.
#
# LA PROSE RESTE — EN REPLI, ET CHAQUE REPLI EST COMPTE. La retirer casserait les 12 items du
# backlog livre qui ne disent leur perimetre que comme ca. Mais une decision prise sur une phrase
# est une DEVINETTE : `scope_census` la range sous `prose-devinee` et le recensement publie la
# liste. Un item dont le perimetre a du etre devine apparait dans un compte ; il ne passe plus
# inapercu.
SCOPE_FIELD = "code_scope"
# Les valeurs lues, NORMALISEES. Rien d'autre n'est accepte : un champ illisible n'est pas un
# perimetre, il est COMPTE a part et on retombe sur ce qui decidait avant lui.
SCOPE_SANS_CODE = ("none", "aucun", "harness", "harnais", "no-code", "no_code", "sans-code")
SCOPE_AVEC_CODE = ("engine", "moteur", "jeu", "game", "portage", "code")
# 23/09 (harness-owner-gesture-not-imputed-to-running-item) — PAS ENCORE UN PERIMETRE. Un ticket de
# l'owner adopte par `linear_sync.adopt_owner_issues` arrive ainsi : il recevait `jeu` en dur, et
# JAK-265 (profils de modeles, un sujet de HARNAIS) est entre classe « jeu ». `next_open` ne prend
# pas un item `a-cadrer` ; la porte, si on la lui montrait quand meme, exige le code (sens severe).
SCOPE_A_CADRER = ("a-cadrer", "a cadrer", "a_cadrer")

SRC_FIELD = "champ-explicite"        # `code_scope` : la seule source qui ne se devine pas
SRC_FLAG = "drapeau-no_code"         # la parole du superviseur, dans un seul sens
SRC_PROSE = "prose-devinee"          # LE REPLI : une tournure reconnue dans une phrase
SRC_SILENT = "perimetre-muet"        # rien ne le dit : on exige le code, comme avant
SRC_BAD = "champ-illisible"          # `code_scope` present, valeur inconnue
SRC_UNFRAMED = "a-cadrer"            # `code_scope: a-cadrer` : ticket adopte, pas encore cadre


def scope_decision(item) -> dict:
    """PERIMETRE/champ-explicite — « cet item doit-il livrer du code moteur ? », ET PAR QUI.

    Rend `{code_free, source, reason, field_unreadable}`. L'ordre d'autorite, du plus explicite
    au plus devine :

      1. `code_scope`  — le CHAMP. Il tranche dans les deux sens ; meme un `no_code: true` pose
                         au lancement ne le contredit pas, parce que ce drapeau-la a pu etre
                         pose par une lecture de prose.
      2. `no_code`     — le drapeau du superviseur. Un seul sens : il interdit le code.
      3. la PROSE      — le REPLI. La decision est bonne, mais elle est DEVINEE, et `source` le
                         dit pour qu'un compte la voie.
      4. rien          — `perimetre-muet` : on exige le code. INCONNU = DEFAUT du cote SEVERE.
    """
    vide = {"code_free": False, "source": SRC_SILENT, "reason": "", "field_unreadable": False}
    if not isinstance(item, dict):
        return vide
    illisible = False
    brut = item.get(SCOPE_FIELD)
    if brut is not None and str(brut).strip() != "":
        valeur = normalise(brut)
        if valeur in SCOPE_SANS_CODE:
            return {"code_free": True, "source": SRC_FIELD,
                    "reason": "%s: %s" % (SCOPE_FIELD, valeur), "field_unreadable": False}
        if valeur in SCOPE_AVEC_CODE:
            return {"code_free": False, "source": SRC_FIELD,
                    "reason": "%s: %s" % (SCOPE_FIELD, valeur), "field_unreadable": False}
        if valeur in SCOPE_A_CADRER:
            return {"code_free": False, "source": SRC_UNFRAMED,
                    "reason": "%s: %s" % (SCOPE_FIELD, valeur), "field_unreadable": False}
        illisible = True
    if item.get("no_code", False):
        return {"code_free": True, "source": SRC_FLAG, "reason": "drapeau no_code",
                "field_unreadable": illisible}
    for champ in SCOPE_FIELDS:
        texte = normalise(item.get(champ))
        if not texte:
            continue
        for motif in CODE_FREE_PATTERNS:
            m = re.search(motif, texte)
            if m:
                debut = max(0, m.start() - 8)
                return {"code_free": True, "source": SRC_PROSE,
                        "reason": "%s: %s" % (champ, texte[debut:m.end() + 24].strip()),
                        "field_unreadable": illisible}
    return {"code_free": False, "source": SRC_BAD if illisible else SRC_SILENT,
            "reason": ("%s: %s" % (SCOPE_FIELD, normalise(brut))) if illisible else "",
            "field_unreadable": illisible}


def scope_census(items) -> dict:
    """Par SOURCE, le recensement du perimetre — et le DRAPEAU compte a part.

    LU SANS `no_code`. Le drapeau est pose AU LANCEMENT par une lecture de prose : le laisser
    repondre masquerait exactement la devinette que ce recensement doit montrer. On demande donc
    a chaque item comment il dit SON perimetre, de ses propres mots, et le nombre d'items portant
    le drapeau est publie A COTE, jamais a la place.
    """
    par_source, drapeaux, contradictions = {}, [], []
    for it in (items or []):
        if not isinstance(it, dict):
            continue
        iid = it.get("id") or "-"
        if it.get("no_code", False):
            drapeaux.append(iid)
        sans = dict(it)
        sans.pop("no_code", None)
        decision = scope_decision(sans)
        par_source.setdefault(decision["source"], []).append(iid)
        # Diagnostic only: the explicit field remains authoritative. Silence in
        # prose does not imply engine scope; only a recognized prohibition counts.
        prose = dict(sans)
        prose.pop(SCOPE_FIELD, None)
        prose_decision = scope_decision(prose)
        if (decision["source"] == SRC_FIELD and not decision["code_free"]
                and prose_decision["source"] == SRC_PROSE):
            contradictions.append({"id": iid, "code_scope": it[SCOPE_FIELD],
                                   "reason": prose_decision["reason"]})
    return {"par_source": par_source, "drapeaux": drapeaux,
            "explicite": par_source.get(SRC_FIELD, []),
            "devine": par_source.get(SRC_PROSE, []),
            "muet": par_source.get(SRC_SILENT, []),
            "illisible": par_source.get(SRC_BAD, []),
            "contradictions": contradictions,
            "contradictions_count": len(contradictions)}


def code_free_item(item) -> tuple[bool, str]:
    """Le perimetre de cet item INTERDIT-il de livrer du code moteur ?

    Rend `(oui, la tournure qui le dit)` — la SIGNATURE QUE GATE 1 ET LE LANCEMENT APPELLENT,
    inchangee. Depuis `PERIMETRE/champ-explicite` la decision est prise par `scope_decision`,
    qui dit EN PLUS d'ou elle vient ; ce raccourci-ci jette la provenance, pas la decision.

    Un perimetre muet rend `(False, "")` : on exige le code, comme avant. INCONNU = DEFAUT du
    cote SEVERE, jamais du cote qui ouvre la porte.
    """
    d = scope_decision(item)
    return (d["code_free"], d["reason"])


def code_free_census(items) -> dict:
    """Le recensement du backlog, en TROIS listes separees — jamais leur difference.

    `exige`                 : les items dont le perimetre interdit le code (le denominateur).
    `exige_sans_drapeau`    : ceux-la qui ne portent PAS `no_code` — le compte que le livrable
                              demande de publier : chacun d'eux brulait un essai.
    `drapeau_sans_exigence` : le drapeau pose sans qu'une tournure le dise. Ce n'est PAS un
                              defaut — la parole du superviseur prime — mais un drapeau pose
                              sans raison lisible est ce qui rend ce recensement aveugle.
    """
    exige, sans_drapeau, sans_raison = [], [], []
    for it in (items or []):
        if not isinstance(it, dict):
            continue
        iid = it.get("id") or "-"
        drapeau = bool(it.get("no_code", False))
        sans = dict(it)
        sans.pop("no_code", None)
        lisible = code_free_item(sans)[0]
        if lisible or drapeau:
            exige.append(iid)
        if lisible and not drapeau:
            sans_drapeau.append(iid)
        if drapeau and not lisible:
            sans_raison.append(iid)
    return {"exige": exige, "exige_sans_drapeau": sans_drapeau,
            "drapeau_sans_exigence": sans_raison}


def note_launch(logs_root, item_id: str, pose: bool, raison: str, source: str = "-") -> str:
    """Une ligne par LANCEMENT ou le perimetre a prononce l'absence de code.

    C'est le denominateur du livrable 1 : « le compte d'items LANCES sans `no_code` alors que
    leur perimetre l'exige ». Un compte du backlog d'aujourd'hui ne le dirait pas — il ne
    garde aucune trace de ce qui a ete lance hier.

    PERIMETRE/champ-explicite — la SOURCE de la decision est consignee EN FIN DE LIGNE, apres la
    raison : `launch_journal_counts` compte des lignes et la sous-chaine ` pose=1 `, que ce
    suffixe ne touche pas. Un lancement decide sur une phrase se relit donc comme tel, des mois
    apres, sans avoir a redeviner.
    """
    chemin = os.path.join(logs_root, LAUNCH_JOURNAL)
    try:
        os.makedirs(logs_root, exist_ok=True)
        with open(chemin, "a", encoding="utf-8") as fh:
            fh.write("%s %s pose=%d %s source=%s\n" % (
                datetime.datetime.now().isoformat(timespec="seconds"), item_id,
                1 if pose else 0, re.sub(r"\s+", " ", raison or "-")[:160],
                re.sub(r"\s+", "-", str(source or "-"))[:40]))
    except OSError:
        return ""
    return chemin


def launch_journal_counts(logs_root) -> tuple[int, int]:
    """(lignes du journal, dont drapeau REELLEMENT pose au lancement)."""
    chemin = os.path.join(logs_root, LAUNCH_JOURNAL)
    try:
        with open(chemin, encoding="utf-8") as fh:
            lignes = [l for l in fh.read().splitlines() if l.strip()]
    except OSError:
        return (0, 0)
    return (len(lignes), sum(1 for l in lignes if " pose=1 " in l))


# ============================================================ PROMOTION/relit-le-verdict ====
# Le verdict d'un essai est le texte que `validators/generic.sh` a ecrit, tel quel :
#   vert  -> une ligne « [<id> ok] ... », et AUCUNE ligne « [<id> FAIL] ... »
#   rouge -> au moins une ligne « [<id> FAIL] ... » (le validateur les ACCUMULE)
# On lit le journal du DERNIER essai, celui dont le numero de sequence est le plus grand.
VERDICT_ABSENT = "journal-absent"
VERDICT_MUET = "journal-muet"
VERDICT_TENUE = "porte-tenue"
VERDICT_REFUSEE = "porte-refusee"

_SEQ = re.compile(r"validator-(\d+)\.txt$")


def validator_journals(logs_root, item_id: str) -> list[str]:
    """Les journaux de validation de cet item, du plus ancien au plus recent."""
    d = os.path.join(logs_root, item_id)
    try:
        noms = os.listdir(d)
    except OSError:
        return []
    trouves = []
    for n in noms:
        m = _SEQ.search(n)
        if m:
            trouves.append((int(m.group(1)), os.path.join(d, n)))
    return [p for _, p in sorted(trouves)]


def validator_verdict(logs_root, item_id: str) -> dict:
    """Ce que la porte a VRAIMENT rendu sur cet item, relu dans son journal.

    Rend `{file, seq, green, reason, line, journals}`. Aucun journal, ou un journal qui ne
    porte ni verdict vert ni verdict rouge : `green=False`. On ne promeut pas sur un silence.
    """
    journaux = validator_journals(logs_root, item_id)
    vide = {"file": "-", "seq": -1, "green": False, "reason": VERDICT_ABSENT,
            "line": "-", "journals": len(journaux)}
    if not journaux:
        return vide
    dernier = journaux[-1]
    try:
        with open(dernier, encoding="utf-8", errors="replace") as fh:
            lignes = fh.read().splitlines()
    except OSError:
        return vide
    ok = [l for l in lignes if l.startswith("[%s ok]" % item_id)]
    ko = [l for l in lignes if l.startswith("[%s FAIL]" % item_id)]
    m = _SEQ.search(os.path.basename(dernier))
    if ko:
        reason, line = VERDICT_REFUSEE, ko[-1]
    elif ok:
        reason, line = VERDICT_TENUE, ok[-1]
    else:
        reason, line = VERDICT_MUET, (lignes[0] if lignes else "-")
    return {"file": os.path.basename(dernier), "seq": int(m.group(1)) if m else -1,
            "green": bool(ok) and not ko, "reason": reason,
            "line": re.sub(r"\s+", " ", line)[:200] or "-", "journals": len(journaux)}


# ============================================================ VERDICT/dans-l-item ===========
# LE VERDICT DE LA PORTE VIT DANS L'ITEM, PAS DANS UN JOURNAL QUE RIEN NE CONSERVE.
#
# `validator_verdict` ci-dessus relit `logs/<id>/validator-NNN.txt`. `.gitignore` exclut tout
# `.autoport/logs/` : sur un clone neuf, ou apres une purge, ce journal N'EXISTE PAS. La
# promotion ne promeut alors rien — le bon defaut — et un item dont la porte a REELLEMENT tenu
# gele pour toujours, en gelant ses dependants. C'est `perf-ocean-idle` (10 au 12/09) en pire :
# aucune relance ne le repare, puisque rien ne manque a reparer.
#
# La porte ECRIT donc ce qu'elle a rendu DANS L'ITEM, au moment ou elle le prononce, et le
# backlog est versionne. Le champ porte le RESULTAT, la DATE, et l'EMPREINTE DES OCTETS DE LA
# PREUVE JUGEE — un chemin n'est pas une provenance, un numero d'essai non plus. La promotion
# lit ce champ EN PREMIER ; le journal n'est plus qu'un REPLI, et chaque repli est COMPTE.
VERDICT_FIELD = "gate_verdict"
# Le nom de la preuve du bras LIVRE, demande a l'autorite plutot que reecrit ici.
PROOF_FILE = _noms.arm_name("proof", "")
SRC_ITEM = "item"                    # le champ de l'item a repondu
SRC_JOURNAL = "journal"              # LE REPLI : il a fallu ouvrir logs/<id>/validator-NNN.txt

# Les seuls resultats qu'un champ de verdict peut porter. Tout le reste — champ absent, champ
# qui n'est pas un dictionnaire, resultat inconnu — n'est PAS un verdict : on retombe sur le
# journal, et le repli se compte. INCONNU = DEFAUT.
_RESULTATS = {VERDICT_TENUE: True, VERDICT_REFUSEE: False}


def proof_fingerprint(reports_root, item_id: str) -> tuple[str, int]:
    """L'empreinte des OCTETS de la preuve jugee, et leur nombre.

    `("-", -1)` quand il n'y a pas de preuve a empreinter : un tiret se lit « aucune », un zero
    se lirait « fichier vide », et les deux ne sont pas la meme chose.
    """
    chemin = os.path.join(str(reports_root or ""), str(item_id or ""), PROOF_FILE)
    try:
        with open(chemin, "rb") as fh:
            octets = fh.read()
    except OSError:
        return ("-", -1)
    return (hashlib.sha256(octets).hexdigest()[:16], len(octets))


def gate_record(result: str, reports_root, item_id: str,
                seq: int = 0, journal: str = "-") -> dict:
    """CE QUE LA PORTE A RENDU, tel qu'il s'ecrit dans l'item.

    Le minimum que le livrable exige : le RESULTAT, la DATE, l'EMPREINTE de la preuve jugee. Le
    numero d'essai et le nom du journal suivent — ils ne prouvent rien seuls, ils disent ou
    regarder quand le journal existe encore.
    """
    sha, octets = proof_fingerprint(reports_root, item_id)
    return {"result": str(result), "date": datetime.date.today().isoformat(),
            "proof_sha": sha, "proof_bytes": int(octets),
            "attempt": int(seq or 0), "journal": str(journal or "-")}


def verdict_from_item(item) -> dict | None:
    """Le verdict ECRIT DANS L'ITEM, ou `None` s'il n'y en a pas de lisible.

    `None` est le signal du REPLI : l'appelant ouvre alors le journal, et compte le repli. On ne
    fabrique jamais un verdict a partir d'un champ qu'on ne sait pas lire.

    La forme rendue est celle de `validator_verdict` — `{file, seq, green, reason, line,
    journals, source}` — pour que la promotion n'ait qu'un seul jeu de cles a manipuler.
    `journals: -1` dit « on n'a pas regarde les journaux », jamais « il n'y en a pas ».
    """
    if not isinstance(item, dict):
        return None
    rec = item.get(VERDICT_FIELD)
    if not isinstance(rec, dict):
        return None
    resultat = str(rec.get("result") or "")
    if resultat not in _RESULTATS:
        return None
    essai = str(rec.get("attempt", ""))
    return {"file": str(rec.get("journal") or "-"),
            "seq": int(essai) if essai.lstrip("-").isdigit() else -1,
            "green": _RESULTATS[resultat], "reason": resultat,
            "line": "%s date=%s proof_sha=%s octets=%s" % (
                resultat, rec.get("date") or "-", rec.get("proof_sha") or "-",
                rec.get("proof_bytes", "-")),
            "journals": -1, "source": SRC_ITEM}


def verdict_field_census(items) -> dict:
    """Les `to-test` qui PORTENT un verdict lisible, et ceux qui n'en ont pas.

    Le compte que le livrable 1 demande de publier. `illisible` est separe d'`absent` : un champ
    qu'on ne sait pas lire n'est pas un champ qui manque, et les confondre cacherait le jour ou
    la forme du champ derive.
    """
    porteurs, absents, illisibles = [], [], []
    for it in (items or []):
        if not isinstance(it, dict) or it.get("status") != "to-test":
            continue
        iid = it.get("id") or "-"
        if verdict_from_item(it) is not None:
            porteurs.append(iid)
        elif isinstance(it.get(VERDICT_FIELD), dict):
            illisibles.append(iid)
        else:
            absents.append(iid)
    return {"porteurs": porteurs, "absents": absents, "illisibles": illisibles}
