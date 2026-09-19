"""Le compteur de jetons d'un essai : chaque message compte UNE fois.

CE QUE CE FICHIER EMPECHE DE REVENIR (harness-usage-double-counted, 2026-09-19).
`_accumulate_usage` etait appele sur CHAQUE evenement `assistant` — le meme message revient
3 a 5 fois dans le flux — PUIS sur `result`, dont le `modelUsage` est deja le total CUMULE
de l'essai, republie par chacun des onze `result` de `ao-indirect-clean/attempt-001`. Tout
chiffre de cout lu dans `attempt_end` ou dans la banniere etait gonfle d'un quart a un
facteur trois.

LA POLARITE EST DANS LE JOURNAL FABRIQUE : son total attendu est ECRIT EN CLAIR dans
`lib/usage_accounting_selftest.py`, il n'est pas recalcule par la regle que ces tests
jugent. `test_le_total_brut_est_bien_plus_gros` verifie que ce journal PORTE le defaut :
sans lui, un compteur qui rendrait n'importe quoi passerait pour juste.
"""
import json
import shlex

import pytest

import usage_accounting_selftest as banc
from test_attempt import ITEM, _fake_claude, item_repo  # noqa: F401


def _rejeu(orch, evenements):
    return banc.rejouer(orch, evenements)


def test_le_journal_fabrique_rend_le_total_ecrit(orch):
    ev, attendu, cout = banc.journal_fabrique()
    got, st = _rejeu(orch, ev)
    assert got == attendu
    assert st.n_results == 3, "les trois `result` doivent avoir ete vus"
    assert st.dup_msgs == 11, "onze republications, toutes ignorees"
    assert len(st.seen_msg) == 4, "quatre messages distincts"
    assert st.usage_source == "result-modelusage"
    assert st.cost_usd == pytest.approx(cout)


def test_le_total_brut_est_bien_plus_gros(orch):
    """LE JOURNAL PORTE LE DEFAUT. Somme brute des `assistant` + somme des `result` :
    c'est exactement ce que faisait `_accumulate_usage`, et ca doit rester tres au-dessus."""
    ev, attendu, _ = banc.journal_fabrique()
    brut = 0
    for e in ev:
        if e.get("type") == "assistant":
            brut += int(e["message"]["usage"]["cache_read_input_tokens"])
        elif e.get("type") == "result":
            brut += int(e["usage"]["cache_read_input_tokens"])
    assert brut > 2 * attendu["cread"], (brut, attendu["cread"])


def test_un_message_republie_ne_compte_quune_fois(orch):
    ev = banc._assistant("msg_x", 5, 7, 900, 11, n=6)
    got, st = _rejeu(orch, ev)
    assert got == {"inp": 5, "out": 7, "cread": 900, "cwrite": 11}
    assert st.dup_msgs == 5


def test_deux_etages_peuvent_porter_le_meme_identifiant(orch):
    """La clef est `(etage, message.id)` : un sous-agent n'efface pas le principal."""
    ev = banc._assistant("meme_id", 1, 2, 100, 0, n=2)
    ev += banc._assistant("meme_id", 1, 2, 100, 0, parent="toolu_9", n=2)
    got, st = _rejeu(orch, ev)
    assert got["cread"] == 200
    assert len(st.seen_msg) == 2


def test_plusieurs_result_ne_sadditionnent_pas(orch):
    """Chaque `result` republie un cumul : c'est le DERNIER qui fait foi, jamais la somme."""
    ev = [banc._result({"inp": 1, "out": 10, "cread": 1000, "cwrite": 5}, 10, 0.1),
          banc._result({"inp": 2, "out": 20, "cread": 2000, "cwrite": 9}, 10, 0.2),
          banc._result({"inp": 3, "out": 30, "cread": 3000, "cwrite": 11}, 10, 0.3)]
    got, st = _rejeu(orch, ev)
    assert got == {"inp": 3, "out": 30, "cread": 3000, "cwrite": 11}
    assert st.n_results == 3


def test_sans_result_le_total_deduplique_reste(orch):
    ev, attendu = banc.journal_sans_result()
    got, st = _rejeu(orch, ev)
    assert got == attendu
    assert st.usage_source == "assistant"


def test_un_result_sans_modelusage_ne_donne_que_la_sortie(orch):
    """Vieille CLI : `result.usage` est un delta de tour et ignore les sous-agents.
    On ne lui prend que la sortie, que les lignes `assistant` ne savent pas donner."""
    ev, attendu = banc.journal_legacy()
    got, st = _rejeu(orch, ev)
    assert got == attendu
    assert st.usage_source == "result-usage+assistant"


def test_un_message_sans_identifiant_est_compte_et_signale(orch):
    ev = banc._assistant("x", 1, 1, 50, 0, n=1)
    del ev[0]["message"]["id"]
    got, st = _rejeu(orch, ev)
    assert got["cread"] == 50, "on ne jette pas des jetons faute d'identifiant"
    assert st.noid_msgs == 1, "et l'aveuglement est DIT"


def test_lessai_complet_publie_le_bon_total(orch, item_repo):
    """LE BOUT DU FIL : un essai entier, et la ligne `attempt_end` qu'il laisse.

    C'est la seule qu'un recensement de cout relira dans six mois ; un total juste en
    memoire et une ligne gonflee sur le disque se lisent pareil dans un rapport."""
    ev, attendu, cout = banc.journal_fabrique()
    lignes = "".join("echo " + shlex.quote(json.dumps(e)) + "\n" for e in ev)
    _fake_claude(orch, '\n' + lignes + 'exit 0\n')
    orch.GENERIC_VALIDATOR.write_text('echo "FAIL rien=1 expected=0"\nexit 1\n')
    orch.run_attempt(dict(ITEM), orch.load_state())

    fin = [json.loads(l) for l in
           (orch.LOG_ROOT / "demo/attempt-001.jsonl").read_text().splitlines()][-1]
    assert fin["event"] == "attempt_end"
    assert fin["tokens_in"] == attendu["inp"]
    assert fin["tokens_out"] == attendu["out"]
    assert fin["cache_read"] == attendu["cread"]
    assert fin["cache_creation"] == attendu["cwrite"]
    assert fin["usage_source"] == "result-modelusage"
    assert fin["usage_results"] == 3
    assert fin["usage_dup_msgs"] == 11
    assert fin["cost_usd"] == pytest.approx(cout)
