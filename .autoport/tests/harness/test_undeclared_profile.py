"""LA GARDE DE NON-REGRESSION DE `harness-undeclared-profile-attempts` (2026-09-19).

CE QUE CETTE SUITE EMPECHE DE REVENIR. Vingt-huit essais sont partis avec
`attempt_start.model == ""` : tous `backend=codex`, tous le 2026-09-07 entre 09:37 et
16:01 UTC, sur trois items. Leur ligne de commande enregistree ne porte ni `--model` ni
`agents.default_subagent_model`. Zero abouti. La voie de lancement : le profil Codex
actif portait `manager_model: ""`, `codex_options` lisait cette chaine vide comme
« laisse la CLI choisir », et le seul controle existant (`if key not in profile`) ne
regardait que la PRESENCE de la clef.

LA DONNEE a ete corrigee le 2026-09-07 a 18:02 (commit 50e9dc5af6). LE CODE, lui,
acceptait encore une chaine vide jusqu'a cet item : c'est ce que ces tests ferment.

AUCUN DE CES TESTS NE LIT `.autoport/logs/` : ces journaux sont gitignores, une garde
qui s'appuierait dessus serait verte par absence hors de l'arbre principal. La
population historique est mesuree par `lib/undeclared_profile_selftest.py`, qui tourne
dans l'arbre livre sous `lib/census/harness-undeclared-profile-attempts.sh`.
"""
import json
import pytest

from lib import cli_backend as cb
from lib import model_profile
from test_attempt import item_repo, ITEM, _fake_claude, _WORKS_THEN_EXITS  # noqa: F401

PROFIL_SAIN = {
    "manager_model": "modele-de-test", "manager_effort": "high",
    "worker_model": "modele-de-test-sous-agent",
    "worker_efforts": {"autoport-researcher": "high", "autoport-tester": "medium"},
    "sandbox": "danger-full-access",
}


def _ecrire_profil_codex(racine, profil, actif="codex-local"):
    d = racine / ".autoport" / "codex"
    d.mkdir(parents=True, exist_ok=True)
    (d / "profiles.json").write_text(json.dumps({"active": actif,
                                                 "profiles": {"codex-local": profil}}))
    return racine


# ==================================================================== LA PORTE D'ENTREE

@pytest.mark.parametrize("champ", ["manager_model", "manager_effort", "worker_model"])
def test_un_champ_vide_du_profil_codex_est_refuse_et_nomme(tmp_path, champ):
    """Le refus NOMME le champ. « profil invalide » n'aurait rien appris a personne."""
    _ecrire_profil_codex(tmp_path, dict(PROFIL_SAIN, **{champ: ""}))
    with pytest.raises(model_profile.ProfileUnresolved) as refus:
        cb.codex_profile(tmp_path)
    assert champ in str(refus.value)
    assert "VIDE" in str(refus.value)


@pytest.mark.parametrize("casse, attendu", [
    ({}, "aucun profil ACTIF"),
    ({"active": "codex-local"}, "aucune table `profiles`"),
    ({"active": "absent", "profiles": {"codex-local": PROFIL_SAIN}}, "n'existe pas"),
])
def test_un_profil_introuvable_refuse_au_lieu_de_replier(tmp_path, casse, attendu):
    d = tmp_path / ".autoport" / "codex"
    d.mkdir(parents=True)
    (d / "profiles.json").write_text(json.dumps(casse))
    with pytest.raises(model_profile.ProfileUnresolved) as refus:
        cb.codex_profile(tmp_path)
    assert attendu in str(refus.value)


def test_la_ligne_de_commande_codex_porte_TOUJOURS_le_modele_et_celui_des_sous_agents(tmp_path):
    """Le contrôle POSITIF du refus : un profil résolu produit bien les deux options.

    Sans lui, `codex_options` pourrait lever sur TOUT et ces tests seraient verts par
    inaction."""
    _ecrire_profil_codex(tmp_path, PROFIL_SAIN)
    profil = cb.codex_profile(tmp_path)
    cmd = cb.worker_command(tmp_path, "codex", profil, "high", 30)
    assert cmd.count("--model") == 1
    assert cmd[cmd.index("--model") + 1] == "modele-de-test"
    sous = [cmd[i + 1] for i, t in enumerate(cmd) if t == "-c"
            and cmd[i + 1].startswith("agents.default_subagent_model=")]
    assert sous == ['agents.default_subagent_model="modele-de-test-sous-agent"'], cmd


def test_le_profil_claude_casse_leve_en_strict_et_ne_replie_qu_a_l_import(orch, tmp_path,
                                                                          monkeypatch):
    casse = tmp_path / "model-profiles.json"
    casse.write_text(json.dumps({"active": "x", "profiles": {"x": dict(PROFIL_SAIN,
                                                                      manager_model="")}}))
    monkeypatch.setattr(orch, "_PROFILE_PATH", casse)
    with pytest.raises(model_profile.ProfileUnresolved):
        orch._load_model_profile(strict=True)
    # Le repli existe pour que le MODULE reste importable (quatre bancs et un recensement
    # importent `orchestrator`), et il se DENONCE : `faults` le compte comme un defaut.
    repli = orch._load_model_profile()
    assert repli["_active_name"].startswith("FALLBACK")
    assert any("REPLI" in f for f in model_profile.faults(repli))


def test_l_orchestrateur_refuse_de_demarrer_sur_un_profil_non_resolu(orch, tmp_path,
                                                                     monkeypatch, capsys):
    casse = tmp_path / "model-profiles.json"
    casse.write_text(json.dumps({"active": "x", "profiles": {"x": dict(PROFIL_SAIN,
                                                                      manager_model="")}}))
    monkeypatch.setattr(orch, "_PROFILE_PATH", casse)
    assert orch.main(["--check", "--backend", "claude"]) == 1
    sortie = capsys.readouterr().out
    assert "refus" in sortie.lower()
    assert "manager_model" in sortie
    # CONTROLE POSITIF, et il ne depend pas de l'environnement : le MEME chemin, avec un
    # profil resolu, ne prononce plus le refus et NOMME le profil. (Le code de retour de
    # `--check`, lui, depend de la presence des identifiants de la machine : le lire ici
    # ferait dire au banc « le profil est casse » quand seule l'authentification manque.)
    sain = tmp_path / "sain.json"
    sain.write_text(json.dumps({"active": "x", "profiles": {"x": PROFIL_SAIN}}))
    monkeypatch.setattr(orch, "_PROFILE_PATH", sain)
    orch.main(["--check", "--backend", "claude"])
    sortie = capsys.readouterr().out
    assert "NON RÉSOLU" not in sortie
    assert '"profile": "x"' in sortie, sortie


# ============================================================== LE POINT DE PRODUCTION

def _profil_actif(orch, **champs):
    """Pose `champs` dans le profil ACTIF du bac a sable, la ou `run_attempt` le RELIT.

    Poser `orch.MODEL` ne mesure plus rien depuis le 23/09 (JAK-265) : le profil est relu a
    la frontiere d'item et ecrase les globales. Le defaut se fabrique donc dans le FICHIER."""
    cfg = json.loads(orch._PROFILE_PATH.read_text())
    cfg["profiles"][cfg["active"]].update(champs)
    cfg.pop("trials", None)
    orch._PROFILE_PATH.write_text(json.dumps(cfg))


def test_aucun_journal_d_essai_ne_peut_naitre_sans_modele_declare(orch, item_repo,
                                                                  monkeypatch):
    """LA garde de l'item : `attempt_start` avec `model=""` ne peut plus s'écrire.

    Deux bras dans le MEME test, sur le MEME item et le MEME sandbox : sans modèle, aucun
    journal ; avec modèle, le journal naît et porte le modèle. Un bras seul serait vert
    par inaction (il suffirait que `run_attempt` échoue pour une autre raison)."""
    _fake_claude(orch, _WORKS_THEN_EXITS)
    etat = orch.load_state()

    _profil_actif(orch, manager_model="")
    refus = orch.run_attempt(dict(ITEM), etat)
    assert refus.kind == "no-start", refus
    assert "NON RÉSOLU" in refus.reason and "manager_model" in refus.reason
    assert not list(orch.LOG_ROOT.rglob("attempt-*.jsonl")), \
        "un journal d'essai est né alors que le profil n'était pas résolu"
    assert not etat["retries"].get("demo")

    _profil_actif(orch, manager_model="modele-de-test", worker_model="modele-de-test")
    orch.GENERIC_VALIDATOR.write_text("#!/usr/bin/env bash\nexit 1\n")
    orch.run_attempt(dict(ITEM), etat)
    journaux = sorted((orch.LOG_ROOT / "demo").glob("attempt-*.jsonl"))
    assert journaux, "le contrôle positif n'a produit aucun journal : le banc ne mesure rien"
    debut = json.loads(journaux[-1].read_text().splitlines()[0])
    assert debut["event"] == "attempt_start"
    assert debut["model"] == "modele-de-test"
    assert debut["profile"], "attempt_start ne nomme pas la voie de lancement"


@pytest.mark.parametrize("champ", ["manager_model", "worker_model", "manager_effort"])
def test_le_refus_couvre_les_trois_champs_au_point_de_production(orch, item_repo,
                                                                 monkeypatch, champ):
    etat = orch.load_state()
    if champ != "manager_effort":
        _profil_actif(orch, **{champ: ""})
    else:
        monkeypatch.setattr(orch, "EFFORT", "")
    out = orch.run_attempt(dict(ITEM, effort="") if champ == "manager_effort"
                           else dict(ITEM), etat)
    assert out.kind == "no-start" and champ in out.reason, out
