"""LE BANC NE VOIT QUE CE QU'IL A DECLARE VOIR.

harness-test-bench-does-not-inherit-the-worker-env, 2026-09-14. Ces jambes sont la SONDE du
livrable : elles lisent, depuis l'interieur du banc, ce qui reste de l'environnement du parent.
`conftest.py` a deja assaini `os.environ` au moment ou elles tournent ; leur denominateur — ce
qui a ete RETIRE — vient de `bench_env`, qui est le seul a l'avoir vu.

ELLES SE SAUTENT SOUS LE BRAS D'ABLATION (`AUTOPORT_BENCH_ENV_INHERIT=1`), ET C'EST VOULU. Le
recensement compte les tests du banc dont le VERDICT change entre un lancement nu et un
lancement de worker : si ces jambes-ci rougissaient sous l'ablation, elles gonfleraient ce
compte de leur propre presence, et la porte se mesurerait elle-meme. Sautees des deux cotes,
elles n'y entrent pas — et le cout d'AVANT reste celui du banc qui existait sans elles.
"""
import json
import os
import subprocess
import sys

import pytest

import bench_env

ETAT = bench_env.etat()
PERMIS = set(bench_env.TRANSMISES) | set(bench_env.EXPLICITES)
# Ce que PYTEST pose lui-meme dans l'environnement du banc pendant qu'il tourne. Ce n'est pas
# une fuite du parent : c'est le banc qui ecrit sa propre position.
POSEES_PAR_PYTEST = ("PYTEST_CURRENT_TEST",)

maitrise = pytest.mark.skipif(ETAT["mode"] != "maitrise",
                              reason="bras d'ablation : le banc herite, il n'y a rien a sonder")


def _publie(**kv):
    cible = os.environ.get("AUTOPORT_BENCH_ENV_MANIFEST")
    if not cible:
        return
    with open(cible, "w", encoding="utf-8") as f:
        for k, v in kv.items():
            f.write("%s=%s\n" % (k, v))


def _liste(noms):
    return ",".join(noms) or "-"


@maitrise
def test_le_manifeste_dit_ce_que_le_banc_voit():
    """La sonde PUBLIE d'abord, elle juge ensuite.

    Ecrire le manifeste dans la meme jambe que les assertions ferait disparaitre les chiffres
    le jour ou une assertion tombe — c'est-a-dire le seul jour ou on en a besoin.
    """
    fuites = bench_env.fuites()
    hors = bench_env.hors_liste()
    parent_ap = bench_env.autoport_du_parent()
    survivants = tuple(n for n in parent_ap if n in ETAT["gardees"])
    vues, du_parent = _sonde()
    _publie(
        banc="test_bench_env.py",
        mode=ETAT["mode"],
        parent=ETAT["parent"],
        gardees=len(ETAT["gardees"]),
        retirees=len(ETAT["retirees"]),
        fuites=len(fuites), fuites_liste=_liste(fuites),
        hors_liste=len(hors), hors_liste_liste=_liste(hors),
        autoport_parent=len(parent_ap), autoport_parent_liste=_liste(parent_ap),
        autoport_survivants=len(survivants), autoport_survivants_liste=_liste(survivants),
        sonde_vues=len(vues),
        sonde_du_parent=len(du_parent), sonde_du_parent_liste=_liste(du_parent),
        liste_blanche=_liste(bench_env.TRANSMISES),
        explicites=_liste(bench_env.EXPLICITES),
        gardees_liste=_liste(ETAT["gardees"]),
    )
    assert ETAT["parent"] >= len(ETAT["gardees"]), "le parent ne peut pas avoir moins que garde"


def _sonde():
    """CE QU'UN SOUS-PROCESSUS DU BANC VOIT, par le chemin que le banc emprunte vraiment.

    `dict(os.environ, ...)` est la construction exacte des vingt sites du banc — c'est elle
    qui portait le defaut. On la rejoue ici, et on rend (ce qui est vu, ce qui vient du parent).
    """
    r = subprocess.run(
        [sys.executable, "-c", "import json,os; print(json.dumps(sorted(os.environ)))"],
        env=dict(os.environ, BANC_SONDE="1"), capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr
    vues = [n for n in json.loads(r.stdout) if n != "BANC_SONDE"]
    du_parent = tuple(n for n in vues if n in bench_env.fuites())
    return vues, du_parent


@maitrise
def test_aucune_variable_du_parent_ne_survit_au_retrait():
    """Le denominateur est publie avec le compte : « zero fuite sur zero retrait » n'est pas
    un succes, c'est un instrument qui n'a rien vu."""
    assert len(ETAT["retirees"]) >= 1, "rien n'a ete retire : la sonde ne mesure rien"
    assert bench_env.fuites() == (), "variables du parent encore lisibles"


@maitrise
def test_le_banc_ne_garde_rien_hors_de_sa_liste_blanche():
    assert bench_env.hors_liste() == (), "gardees hors liste blanche"
    assert set(ETAT["gardees"]) <= PERMIS


@maitrise
def test_aucun_autoport_du_parent_ne_traverse_hors_mention_explicite():
    """LE DEFAUT NOMME : c'est `AUTOPORT_ATTEMPT_ID` du parent qui faisait rougir le controle
    positif de `test_proof.py`. Aucun `AUTOPORT_*` du parent ne traverse, sauf ceux qu'on a
    nommes — et ceux-la sont des canaux d'instrument, pas des reglages."""
    survivants = [n for n in bench_env.autoport_du_parent() if n in ETAT["gardees"]]
    assert set(survivants) <= set(bench_env.EXPLICITES), survivants
    assert os.environ.get("AUTOPORT_ATTEMPT_ID") is None
    assert os.environ.get("AUTOPORT_PHASE_ID") is None


@maitrise
def test_un_sous_processus_du_banc_ne_voit_que_la_liste_blanche():
    """LA SONDE, par le chemin reel : `dict(os.environ, ...)`, la construction des vingt sites."""
    vues, du_parent = _sonde()
    assert du_parent == (), du_parent
    inattendues = sorted(set(vues) - PERMIS - set(POSEES_PAR_PYTEST))
    assert inattendues == [], inattendues
