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

MARQUEURS. `GATE1/perimetre-sans-code` et `PROMOTION/relit-le-verdict` datent ce chantier dans
les fichiers qu'il touche. Le banc remonte `git log` jusqu'au premier commit qui ne les porte
PAS pour construire son bras d'AVANT : lu a `HEAD:`, un temoin d'avant s'accuse lui-meme des le
commit ou il nait.

INCONNU = DEFAUT, des deux cotes : un perimetre muet n'interdit rien (on exige le code), un
verdict introuvable n'a pas tenu (on ne promeut pas).
"""
from __future__ import annotations

import datetime
import os
import re
import unicodedata

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


def code_free_item(item) -> tuple[bool, str]:
    """Le perimetre de cet item INTERDIT-il de livrer du code moteur ?

    Rend `(oui, la tournure qui le dit)`. Le drapeau `no_code` deja pose repond tout de suite —
    il est la parole du superviseur et rien ne la discute. Sinon on lit le perimetre.

    Un perimetre muet rend `(False, "")` : on exige le code, comme avant. INCONNU = DEFAUT du
    cote SEVERE, jamais du cote qui ouvre la porte.
    """
    if not isinstance(item, dict):
        return (False, "")
    if item.get("no_code", False):
        return (True, "drapeau no_code")
    for champ in SCOPE_FIELDS:
        texte = normalise(item.get(champ))
        if not texte:
            continue
        for motif in CODE_FREE_PATTERNS:
            m = re.search(motif, texte)
            if m:
                debut = max(0, m.start() - 8)
                return (True, "%s: %s" % (champ, texte[debut:m.end() + 24].strip()))
    return (False, "")


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


def note_launch(logs_root, item_id: str, pose: bool, raison: str) -> str:
    """Une ligne par LANCEMENT ou le perimetre a prononce l'absence de code.

    C'est le denominateur du livrable 1 : « le compte d'items LANCES sans `no_code` alors que
    leur perimetre l'exige ». Un compte du backlog d'aujourd'hui ne le dirait pas — il ne
    garde aucune trace de ce qui a ete lance hier.
    """
    chemin = os.path.join(logs_root, LAUNCH_JOURNAL)
    try:
        os.makedirs(logs_root, exist_ok=True)
        with open(chemin, "a", encoding="utf-8") as fh:
            fh.write("%s %s pose=%d %s\n" % (
                datetime.datetime.now().isoformat(timespec="seconds"), item_id,
                1 if pose else 0, re.sub(r"\s+", " ", raison or "-")[:160]))
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
