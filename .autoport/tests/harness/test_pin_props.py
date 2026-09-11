"""L'epinglage du regime d'une course : ce qui a ete perdu, et ne doit plus l'etre.

Un worker qui posait `debug.opengoal.<x>` depuis l'hote avant sa course mesurait l'AUTRE
regime : `lib/device_teardown.sh` tourne entre sa pose et l'amorcage et efface TOUTES les
`debug.opengoal.*`. Rien ne le disait. Ces tests tiennent les quatre garanties qui ferment
ce chemin — le teardown NOMME ce qu'il efface, la course publie ce qu'elle a EPINGLE, un
`owner_test: false` ne reste jamais parque, et le chemin recommande est dans chaque prompt.

Aucun appareil, aucun `gk`, aucun build : un faux `adb` de vingt lignes et un `tmp_path`.
"""
import os
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[3]
AP = ROOT / ".autoport"

FAUX_ADB = """#!/usr/bin/env bash
# Un faux appareil : une table de proprietes dans un fichier, rien d'autre.
P="$PROPS"
[ "$1" = -s ] && shift 2
case "${1:-}" in
  get-state) echo device ;;
  shell|exec-out)
    shift
    # shellcheck disable=SC2046
    set -- $(printf '%s ' "$@" | sed "s/''/ /g; s/'//g")
    case "${1:-}" in
      getprop)
        if [ -z "${2:-}" ]; then
          while IFS= read -r l; do [ -n "$l" ] && printf '[%s]: [%s]\\n' "${l%%=*}" "${l#*=}"; done < "$P"
        else sed -n "s|^$2=||p" "$P" | tail -1; fi ;;
      setprop)
        t=$(mktemp); grep -v "^$2=" "$P" > "$t" 2>/dev/null
        [ -n "${3:-}" ] && printf '%s=%s\\n' "$2" "$3" >> "$t"; mv -f "$t" "$P" ;;
      *) : ;;
    esac ;;
  *) : ;;
esac
exit 0
"""


@pytest.fixture()
def faux_appareil(tmp_path):
    adb = tmp_path / "adb"
    adb.write_text(FAUX_ADB)
    adb.chmod(0o755)
    props = tmp_path / "props"
    props.write_text("debug.opengoal.hdr.out=2\ndebug.opengoal.cpad_inject=1\n")
    return adb, props


def _teardown(adb, props, tmp_path, serial="SANDBOX01"):
    rapport = tmp_path / "rapport.txt"
    r = subprocess.run(
        ["bash", str(AP / "lib" / "device_teardown.sh"), serial],
        env=dict(os.environ, ADB=str(adb), PROPS=str(props),
                 AUTOPORT_TEARDOWN_REPORT=str(rapport),
                 AUTOPORT_LOGCAT_PIDDIR=str(tmp_path / "nopid")),
        capture_output=True, text=True, timeout=120)
    lu = {}
    if rapport.exists():
        for ligne in rapport.read_text().splitlines():
            if "=" in ligne:
                k, v = ligne.split("=", 1)
                lu[k] = v
    return r, lu


def test_le_teardown_nomme_ce_qu_il_efface(faux_appareil, tmp_path):
    """LE DEFAUT CENTRAL. Effacer reste juste ; effacer SANS LE DIRE est ce qui a coute.

    La preuve doit porter le NOM de la propriete qu'un worker avait posee, pas seulement un
    compte : « 2 effacees » ne dit pas laquelle etait la sienne."""
    adb, props = faux_appareil
    _r, lu = _teardown(adb, props, tmp_path)
    assert lu.get("teardown_ran") == "1"
    assert lu.get("teardown_props_found") == "2", lu
    assert "debug.opengoal.hdr.out" in lu.get("teardown_props_list", "")
    assert "debug.opengoal.cpad_inject" in lu.get("teardown_props_list", "")
    assert lu.get("teardown_props_cleared") == "2"
    assert lu.get("teardown_props_resisted") == "0"
    # ... et il efface toujours : publier sans nettoyer serait un autre defaut.
    assert props.read_text().strip() == ""


def test_un_zero_se_lit_rien_n_etait_pose_jamais_rien_n_a_ete_efface(faux_appareil, tmp_path):
    """Les cles sont ECRITES meme a zero. Une cle absente et un zero ne disent pas la meme
    chose, et c'est le zero silencieux qui rend une porte verte par inaction."""
    adb, props = faux_appareil
    props.write_text("")
    _r, lu = _teardown(adb, props, tmp_path)
    assert lu.get("teardown_ran") == "1"
    assert lu.get("teardown_props_found") == "0"
    assert lu.get("teardown_props_list") == "-"


def test_le_teardown_dit_qu_il_n_a_pas_tourne_quand_l_appareil_manque(tmp_path):
    """`teardown_ran=0` + une raison. Sans cela, « rien d'efface » et « appareil absent »
    sont le meme silence."""
    adb = tmp_path / "adb"
    adb.write_text("#!/usr/bin/env bash\n[ \"$1\" = -s ] && shift 2\n"
                   "[ \"${1:-}\" = get-state ] && { echo unknown; exit 0; }\nexit 0\n")
    adb.chmod(0o755)
    _r, lu = _teardown(adb, tmp_path / "vide", tmp_path)
    assert lu.get("teardown_ran") == "0"
    assert lu.get("teardown_skip") == "appareil-absent"


def test_la_liste_ne_compte_pas_deux_fois_la_meme_propriete(faux_appareil, tmp_path):
    """`getprop` et la liste de SECOURS se recouvrent : `cpad_inject` est dans les deux.
    Sans dedoublonnage, la liste publiee nommerait deux fois la meme propriete et le compte
    ne correspondrait plus a ce qu'elle enumere."""
    adb, props = faux_appareil
    _r, lu = _teardown(adb, props, tmp_path)
    noms = lu["teardown_props_list"].split(",")
    assert len(noms) == len(set(noms)) == int(lu["teardown_props_found"])


# ------------------------------------------------------------------ le rattrapage des parques
def _backlog(tmp_path, items):
    p = tmp_path / "backlog.yaml"
    p.write_text(yaml.safe_dump({"version": 1, "items": items}, allow_unicode=True))
    return p


@pytest.fixture()
def B():
    sys.path.insert(0, str(AP / "lib"))
    import backlog
    return backlog


def test_un_owner_test_false_parque_est_libere_ET_ECRIT_SUR_LE_DISQUE(B, tmp_path):
    """LE PIEGE ARME. La version d'avant mutait `self.items` en memoire et n'avait aucun
    appelant : rebranchee telle quelle, le prochain `_read()` aurait efface le statut sans
    bruit. On relit donc le FICHIER, pas l'objet."""
    p = _backlog(tmp_path, [
        {"id": "machine", "status": "to-test", "owner_test": False},
        {"id": "aux-yeux", "status": "to-test", "owner_test": True},
        {"id": "defaut-implicite", "status": "to-test"},
    ])
    b = B.load(p)
    assert b.machine_proved_to_validated() == ["machine"]
    relu = yaml.safe_load(p.read_text())["items"]
    etats = {it["id"]: it["status"] for it in relu}
    assert etats["machine"] == "validated"
    # Ce qui attend VRAIMENT l'owner n'est pas emporte : `owner_test` absent vaut `true`.
    assert etats["aux-yeux"] == "to-test"
    assert etats["defaut-implicite"] == "to-test"


def test_le_rattrapage_est_idempotent(B, tmp_path):
    p = _backlog(tmp_path, [{"id": "machine", "status": "to-test", "owner_test": False}])
    b = B.load(p)
    b.machine_proved_to_validated()
    assert B.load(p).machine_proved_to_validated() == []


def test_parked_for_owner_publie_le_owner_test_de_chaque_parque(B, tmp_path):
    """La preuve doit NOMMER les parques et dire ce que chacun portait : un parking sur un
    item qui dit n'avoir rien a montrer est un defaut, pas une precaution."""
    p = _backlog(tmp_path, [
        {"id": "a", "status": "to-test", "owner_test": False},
        {"id": "b", "status": "to-test", "owner_test": True},
        {"id": "c", "status": "open", "owner_test": False},
    ])
    assert B.load(p).parked_for_owner() == [("a", False), ("b", True)]


def test_l_orchestrateur_appelle_le_rattrapage_a_chaque_tour():
    """Une fonction sans appelant est du code mort ; c'est ce qui a gele `perf-ocean-idle`
    deux jours devant `perf-stock-60`."""
    src = (AP / "orchestrator.py").read_text(encoding="utf-8")
    assert "def free_machine_proved" in src
    assert "        free_machine_proved(bk)\n" in src


# ------------------------------------------------------------------- le chemin, dit au worker
def test_chaque_prompt_de_worker_porte_le_chemin_recommande():
    """Le contrat du 12/09 : « le chemin recommande est DIT quelque part qu'un worker lit ».
    Le preambule de l'orchestrateur est inline dans CHAQUE prompt."""
    sys.path.insert(0, str(AP))
    sys.path.insert(0, str(AP / "lib"))
    import orchestrator
    pre = orchestrator._delegation_preamble("high")
    for marqueur in ("proof_props:", "proof_env:", "device_teardown.sh",
                     "proof_prop_obs_", "teardown_props_found", "owner_test: false"):
        assert marqueur in pre, marqueur


def test_proof_run_porte_le_mode_d_emploi_de_l_epinglage():
    assert "POSER UN REGLAGE DE COURSE" in (AP / "lib" / "proof_run.sh").read_text(encoding="utf-8")


def test_le_crochet_de_recensement_est_generique_et_garde_par_l_existence():
    """Un item dont la grandeur ne vit pas dans une image publie par `lib/census/<id>.sh`.
    Le crochet ne nomme aucun item : il ne doit pas devenir un cas particulier de plus."""
    src = (AP / "lib" / "proof_run.sh").read_text(encoding="utf-8")
    assert 'CENSUS="$AP/lib/census/$ID.sh"' in src
    assert 'if [ -f "$CENSUS" ]; then' in src
    # Aucune LIGNE DE CODE ne nomme un item : l'attribution vit dans les commentaires, le
    # comportement n'y touche pas. Un crochet qui teste un identifiant est un cas particulier
    # de plus, et c'est ainsi qu'un runner generique devient un catalogue.
    code = [l for l in src.splitlines() if l.strip() and not l.lstrip().startswith("#")]
    assert not [l for l in code if "harness-proof-props-pin" in l]
