"""La porte de fermeture LIT la suite du harnais — `lib/suite_gate.py`.

Mesure du 2026-09-12 : 556 verts a 06:16, 44 rouges a 15:45, et aucune porte ne lancait la
suite. Ces tests tiennent la regle dans la suite elle-meme : chacun seme un depot JETABLE avec
une suite MINIATURE, exactement comme le banc, et interroge le VRAI juge. Aucun ne touche le
depot livre, ni la vraie suite : le juge qu'ils appellent lance pytest sur leur bac a sable.
"""
import sys
from pathlib import Path

import pytest

LIB = Path(__file__).resolve().parents[2] / "lib"
if str(LIB) not in sys.path:
    sys.path.insert(0, str(LIB))

import suite_gate as SG                                    # noqa: E402
import suite_gate_selftest as BANC                          # noqa: E402

ITEM = "zzz-test-suite-gate"


def juge(tmp_path, nom, **semis):
    d = tmp_path / nom
    d.mkdir(parents=True, exist_ok=True)
    BANC.semer(d, ITEM, **semis)
    return SG.judge(d, d / ".autoport", ITEM, record=False)


BASE = dict(casse=False, registre_base=[], registre_ajout=[], rapport="rien a signaler")


def test_suite_verte_laisse_fermer(tmp_path):
    v = juge(tmp_path, "vert", **BASE)
    assert v["verdict"] == "pass", v["reason"]
    assert v["collected"] == 3
    assert v["unwaived"] == 0


def test_un_rouge_sans_dispense_refuse_et_nomme_le_test(tmp_path):
    v = juge(tmp_path, "casse", **dict(BASE, casse=True))
    assert v["verdict"] == "refuse"
    assert v["unwaived_list"] == [BANC.NODE_CASSE]
    assert BANC.NODE_CASSE in v["reason"]


def test_une_dispense_ecrite_avant_l_item_couvre_son_rouge(tmp_path):
    v = juge(tmp_path, "ancienne", **dict(BASE, casse=True,
                                          registre_base=[(BANC.NODE_CASSE, BANC.CLE_NEUVE)]))
    assert v["verdict"] == "pass", v["reason"]
    assert v["self_added"] == 0
    assert v["waived_effective"] == 1


def test_une_dispense_ecrite_par_l_item_ne_couvre_pas_son_rouge(tmp_path):
    """Un item ne se donne pas du vert en inscrivant son propre echec au registre."""
    v = juge(tmp_path, "propre", **dict(BASE, casse=True,
                                        registre_ajout=[(BANC.NODE_CASSE, BANC.CLE_NEUVE)],
                                        rapport="j'inscris " + BANC.NODE_CASSE))
    assert v["verdict"] == "refuse"
    assert v["self_added"] == 1
    assert v["unwaived"] == 1
    assert "ajoutees par CET item" in v["reason"]


def test_une_dispense_ajoutee_sans_le_dire_dans_le_rapport_refuse(tmp_path):
    v = juge(tmp_path, "muet", **dict(BASE, registre_ajout=[(BANC.NODE_AILLEURS, "banc")]))
    assert v["verdict"] == "refuse"
    assert v["self_added"] == 1
    assert v["self_added_unnamed"] == [BANC.NODE_AILLEURS]


def test_une_dispense_ajoutee_et_nommee_laisse_fermer(tmp_path):
    v = juge(tmp_path, "nomme", **dict(BASE, registre_ajout=[(BANC.NODE_AILLEURS, "banc")],
                                       rapport="registre : " + BANC.NODE_AILLEURS))
    assert v["verdict"] == "pass", v["reason"]
    assert v["self_added"] == 1
    assert v["self_added_named"] == 1


def test_un_depassement_de_budget_est_dit_mais_ne_refuse_pas(tmp_path):
    """Le cout qui derive est DIT, jamais avale — et ce n'est pas la faute de l'item."""
    d = tmp_path / "budget"
    d.mkdir(parents=True, exist_ok=True)
    BANC.semer(d, ITEM, **BASE)
    haut = SG.judge(d, d / ".autoport", ITEM, budget_s=3600, record=False)
    bas = SG.judge(d, d / ".autoport", ITEM, budget_s=0, record=False)
    assert (haut["over_budget"], haut["verdict"]) == (0, "pass")
    assert (bas["over_budget"], bas["verdict"]) == (1, "pass")


def test_le_journal_ne_dispense_jamais_un_rouge(tmp_path):
    """Un item refuse ne doit pas fermer au deuxieme essai sur la trace du premier.

    Jusqu'au 14/09 `unwaived_new` se lisait DANS ce journal : au deuxieme passage le rouge y
    figurait deja et se publiait « connu ». Il se MESURE maintenant a la base de l'essai, ou la
    trace du premier passage n'est pas — les deux courses rendent donc le meme classement.
    """
    d = tmp_path / "journal"
    d.mkdir(parents=True, exist_ok=True)
    BANC.semer(d, ITEM, **dict(BASE, casse=True))
    un = SG.judge(d, d / ".autoport", ITEM, record=True)
    deux = SG.judge(d, d / ".autoport", ITEM, record=True)
    assert un["verdict"] == "refuse" and deux["verdict"] == "refuse"
    assert un["unwaived_new"] == 1 and deux["unwaived_new"] == 1
    assert un["unwaived_known"] == 0 and deux["unwaived_known"] == 0


def test_une_suite_introuvable_ne_vaut_pas_un_vert(tmp_path):
    d = tmp_path / "vide"
    (d / ".autoport").mkdir(parents=True)
    v = SG.judge(d, d / ".autoport", ITEM, record=False)
    assert v["verdict"] == "refuse"
    assert v["ran"] == 0


# ============ UN ROUGE NE DE L'ESSAI REFUSE ; UN ROUGE HERITE EST SIGNALE, PAS IMPUTE ========
# `harness-close-gate-separates-inherited-reds`, 2026-09-14. L'essai 2 de `hdr-shadow-range`
# est mort le 13/09 sur deux rouges nes d'un commit du superviseur pose UNE HEURE avant son
# premier commit. Ces semis-ci ont une HISTOIRE — un commit de base, puis un commit de l'item —
# parce que c'est la seule chose qui separe un rouge herite d'un rouge neuf.
IRS = __import__("inherited_red_selftest")


def juge_avec_histoire(tmp_path, nom, **semis):
    d = tmp_path / nom
    d.mkdir(parents=True, exist_ok=True)
    depart = IRS.semer(d, ITEM, **semis)
    return SG.judge(d, d / ".autoport", ITEM, record=False, since=depart)


HERITE = dict(casse_a_la_base=True, casse_par_l_item=False)
NEUF = dict(casse_a_la_base=False, casse_par_l_item=True)
SIGNALE = IRS.NODE_CASSE + " | deja rouge a la base | dette -> item:build-and-harness-leftovers\n"


def test_un_rouge_deja_rouge_a_la_base_de_l_essai_ne_refuse_pas(tmp_path):
    v = juge_avec_histoire(tmp_path, "herite", **dict(
        HERITE, rapport="rouge herite : " + IRS.NODE_CASSE, findings=SIGNALE))
    assert v["verdict"] == "pass", v["reason"]
    assert (v["unwaived"], v["unwaived_known"], v["unwaived_new"]) == (1, 1, 0)
    assert v["unwaived_known_list"] == [IRS.NODE_CASSE]
    assert v["replay_ran"] == 1 and v["red_base_kind"] == "attempt"


def test_un_rouge_ne_du_commit_de_l_essai_refuse_toujours(tmp_path):
    """HORS PERIMETRE TENU : la porte reste aussi dure sur ce que l'essai a casse."""
    v = juge_avec_histoire(tmp_path, "neuf", **dict(
        NEUF, rapport="rien a signaler", findings="AUCUN\n"))
    assert v["verdict"] == "refuse"
    assert (v["unwaived_known"], v["unwaived_new"]) == (0, 1)
    assert IRS.NODE_CASSE in v["reason"] and "ce travail-ci" in v["reason"]


def test_un_rouge_herite_que_personne_n_ecrit_ne_ferme_pas_en_silence(tmp_path):
    """Il n'est pas impute a l'essai — mais l'essai suivant ne doit pas le retrouver intact."""
    v = juge_avec_histoire(tmp_path, "muet", **dict(
        HERITE, rapport="rien a signaler", findings="AUCUN\n"))
    assert v["verdict"] == "refuse"
    assert (v["unwaived_known"], v["unwaived_new"]) == (1, 0)
    assert "signalement" in v["reason"] and "ce travail-ci" not in v["reason"]
    assert v["inherited_unfiled"] == [IRS.NODE_CASSE] and v["inherited_filed"] == 0


def test_un_signalement_sans_tri_ne_compte_pas(tmp_path):
    """La convention est celle de `lib/findings_gate.sh` : `-> item:` ou `-> ecarte:`."""
    v = juge_avec_histoire(tmp_path, "sans-tri", **dict(
        HERITE, rapport="rouge herite : " + IRS.NODE_CASSE,
        findings=IRS.NODE_CASSE + " | deja rouge a la base | dette\n"))
    assert v["verdict"] == "refuse"
    assert v["inherited_unfiled"] == [IRS.NODE_CASSE]


def test_la_base_des_rouges_est_celle_de_l_essai_pas_celle_de_l_item(tmp_path):
    """Le defaut mesure du 13/09, en miniature.

    L'item a commite HIER (essai 1), un AUTRE a commite depuis, et l'essai d'aujourd'hui
    commence. La base des rouges est le commit de l'AUTRE — pas celui d'avant l'essai 1, ou
    tout ce que le monde a commite entre-temps serait impute a l'item.
    """
    d = tmp_path / "bases"
    d.mkdir(parents=True, exist_ok=True)
    IRS.semer(d, ITEM, casse_a_la_base=False, casse_par_l_item=False,
              rapport="-", findings="AUCUN\n")
    t = int(__import__("time").time())
    IRS._git(d, "commit", "-q", "--allow-empty", "-m", "[autoport/%s] essai 1" % ITEM,
             quand=t - 400)
    IRS._git(d, "commit", "-q", "--allow-empty", "-m", "[autoport/un-autre] son travail",
             quand=t - 300)
    IRS._git(d, "commit", "-q", "--allow-empty", "-m", "[autoport/%s] essai 2" % ITEM,
             quand=t - 100)
    sujet = lambda ref: IRS._git(d, "log", "-1", "--format=%s", ref).stdout.strip()  # noqa: E731
    ref, genre, _, _ = SG.red_base(str(d), ITEM, t - 200)
    assert genre == "attempt" and sujet(ref) == "[autoport/un-autre] son travail"
    # La base de l'ITEM, elle, remonte au tout debut : c'est ce qui a coute l'essai 2 du 13/09.
    assert sujet(SG.base_ref(str(d), ITEM)) == "base du banc"


@pytest.mark.parametrize("cle", ["collected", "failed", "duration_s", "budget_s",
                                 "registry_sha", "unwaived", "self_added", "verdict"])
def test_les_grandeurs_du_livrable_sont_publiees(tmp_path, cle):
    v = juge(tmp_path, "publie-" + cle, **BASE)
    lignes = dict(x.split("=", 1) for x in SG.publish(v))
    assert "suite_" + cle in lignes
    assert " " not in lignes["suite_" + cle]      # proof.txt jette toute valeur a espace
