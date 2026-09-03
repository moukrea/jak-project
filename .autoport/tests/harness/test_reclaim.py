"""Un item laissé `in-progress` par un arrêt brutal doit revenir au backlog.

Sans ça il est perdu pour toujours : `next_open()` ignore `in-progress`, donc le harnais ne
reprendrait jamais ce travail. C'est le remplaçant exact des 9 phases « parquées » qui ne
fermaient plus dans l'ancien modèle, et c'est arrivé des le premier jour du nouveau
(hd-skin-origin-stretch, orchestrateur tue sans passer par son chemin de sortie).

La contrepartie compte autant : on ne libère JAMAIS un item tenu par un worker VIVANT, sinon
deux workers se retrouvent sur le même arbre — ce qui s'est produit deux fois et que l'owner a
interdit explicitement.
"""
import textwrap

import pytest


@pytest.fixture()
def bk_with_in_progress(orch, sandbox, tmp_path):
    """Un backlog d'un seul item, marqué in-progress, plus un phase_claim.sh pilotable."""
    ap = sandbox / ".autoport"
    (ap / "backlog.yaml").write_text(textwrap.dedent("""\
        version: 1
        items:
          - id: item-teste
            feature: "Un defaut de test"
            status: in-progress
            priority: 1
        """), encoding="utf-8")
    return ap


def _fake_claim(ap, exit_code, message="pid=1234 phase=item-teste"):
    """Remplace phase_claim.sh : 0 = detenteur vivant, 1 = libre (comme le vrai script)."""
    (ap / "phase_claim.sh").write_text(
        f'#!/usr/bin/env bash\necho "{message}"\nexit {exit_code}\n', encoding="utf-8")


def test_un_item_sans_detenteur_vivant_revient_ouvert(orch, bk_with_in_progress):
    ap = bk_with_in_progress
    _fake_claim(ap, 1, "libre")
    bk = orch.load_backlog()
    freed = orch.release_stale_in_progress(bk)
    assert freed == ["item-teste"]
    assert orch.load_backlog().get("item-teste")["status"] == "open"


def test_un_item_tenu_par_un_worker_vivant_nest_pas_touche(orch, bk_with_in_progress):
    ap = bk_with_in_progress
    _fake_claim(ap, 0, "pid=4242 starttime=99 phase=item-teste")
    bk = orch.load_backlog()
    freed = orch.release_stale_in_progress(bk)
    assert freed == [], "liberer un item tenu remettrait deux workers sur le meme arbre"
    assert orch.load_backlog().get("item-teste")["status"] == "in-progress"


def test_les_autres_statuts_ne_bougent_pas(orch, sandbox):
    ap = sandbox / ".autoport"
    (ap / "backlog.yaml").write_text(textwrap.dedent("""\
        version: 1
        items:
          - {id: a, feature: A, status: to-test, priority: 1}
          - {id: b, feature: B, status: validated, priority: 2}
          - {id: c, feature: C, status: blocked, priority: 3, block_reason: x}
          - {id: d, feature: D, status: open, priority: 4}
        """), encoding="utf-8")
    _fake_claim(ap, 1, "libre")
    assert orch.release_stale_in_progress(orch.load_backlog()) == []
    after = orch.load_backlog()
    assert [after.get(i)["status"] for i in "abcd"] == ["to-test", "validated", "blocked", "open"]


def test_la_reclamation_est_bien_appelee_au_demarrage(orch):
    """Le defaut trouve le 2026-09-03 n'etait pas la fonction : elle existait et n'etait
    APPELEE PAR PERSONNE. Une garde que rien n'invoque ne garde rien."""
    import inspect
    src = inspect.getsource(orch.main)
    assert "release_stale_in_progress" in src, \
        "release_stale_in_progress doit etre appelee dans main(), sinon elle est morte"
