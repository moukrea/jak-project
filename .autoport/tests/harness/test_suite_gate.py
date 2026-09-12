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
    """Un item refuse ne doit pas fermer au deuxieme essai sur la trace du premier."""
    d = tmp_path / "journal"
    d.mkdir(parents=True, exist_ok=True)
    BANC.semer(d, ITEM, **dict(BASE, casse=True))
    un = SG.judge(d, d / ".autoport", ITEM, record=True)
    deux = SG.judge(d, d / ".autoport", ITEM, record=True)
    assert un["verdict"] == "refuse" and deux["verdict"] == "refuse"
    assert un["unwaived_new"] == 1 and deux["unwaived_new"] == 0   # publie, jamais dispensateur


def test_une_suite_introuvable_ne_vaut_pas_un_vert(tmp_path):
    d = tmp_path / "vide"
    (d / ".autoport").mkdir(parents=True)
    v = SG.judge(d, d / ".autoport", ITEM, record=False)
    assert v["verdict"] == "refuse"
    assert v["ran"] == 0


@pytest.mark.parametrize("cle", ["collected", "failed", "duration_s", "budget_s",
                                 "registry_sha", "unwaived", "self_added", "verdict"])
def test_les_grandeurs_du_livrable_sont_publiees(tmp_path, cle):
    v = juge(tmp_path, "publie-" + cle, **BASE)
    lignes = dict(x.split("=", 1) for x in SG.publish(v))
    assert "suite_" + cle in lignes
    assert " " not in lignes["suite_" + cle]      # proof.txt jette toute valeur a espace
