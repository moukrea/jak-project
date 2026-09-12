"""La garde du runner distingue un compilateur d'un prompt qui en parle.

MARQUEUR : liste-injectee-2026-09-12.

CE QUI A CHANGE LE 12/09 (harness-test-suite-is-not-a-signal). Ce fichier lisait les processus
REELS de la machine : `test_prompt_mentionnant_compilateur_ne_bloque_pas` rougissait des qu'un
vrai `ninja` ou `clang++` tournait au meme moment — c'est-a-dire pendant tout cycle de
construction arm64. Un test dont le verdict depend de ce que la machine fait a cote n'est pas un
signal, c'est un tirage au sort.

Desormais `busy_reason` ne parle plus au systeme : elle passe par `busy_procs`, que le banc
REMPLACE par une liste injectee. Ce qui reste mesure sur les vrais processus, c'est `busy_procs`
elle-meme — et seulement sur des noms SENTINELLES qu'aucun constructeur ne porte, donc sans
tirage au sort possible.

La tranche de script est le piege connu : factoriser une fonction rend la tranche MUETTE sans
qu'aucun test ne rougisse. `_tranche()` echoue donc bruyamment si la fonction a disparu, et
`test_busy_reason_ne_parle_jamais_au_systeme_en_direct` verifie que la vraie `busy_reason`
passe bien par l'indirection — sinon le banc mesurerait son propre decor.
"""
import shlex
import subprocess
import sys
from contextlib import contextmanager

import pytest

from conftest import AUTOPORT

PROOF_RUN = AUTOPORT / "lib" / "proof_run.sh"


def _tranche(nom):
    """La VRAIE definition de `nom`, decoupee dans proof_run.sh. Bruyante si elle manque."""
    source = PROOF_RUN.read_text()
    ouverture = "\n%s(){" % nom
    assert ouverture in source, "%s() a disparu de %s : la tranche mesurerait du vide" % (
        nom, PROOF_RUN)
    corps = source.split(ouverture, 1)[1].split("\n}\n", 1)[0]
    return "%s(){%s\n}\n" % (nom, corps)


def _banc(tmp_path, nom, corps, appel):
    script = tmp_path / ("banc-%s.sh" % nom)
    script.write_text("set -uo pipefail\nAP=.autoport\nlog(){ :; }\n" + corps + appel + "\n")
    r = subprocess.run(["bash", str(script)], cwd=tmp_path, text=True, capture_output=True)
    assert r.returncode == 0, r.stderr
    return r.stdout.strip()


def _busy(tmp_path, comms=(), cmdlines=()):
    """`busy_reason` reelle, sur une liste de processus INJECTEE. Aucune lecture du systeme."""
    reason = _tranche("busy_reason")
    assert "busy_procs " in reason, (
        "busy_reason interroge de nouveau le systeme en direct : le banc mesurerait son decor")
    stub = (
        "COMMS=%s\nCMDLINES=%s\n"
        "busy_procs(){\n"
        "  case \"$1\" in\n"
        "    comm)    printf '%%s\\n' \"$COMMS\"    | grep -qxE \"$2\" ;;\n"
        "    cmdline) printf '%%s\\n' \"$CMDLINES\" | grep -qE  \"$2\" ;;\n"
        "    *)       return 1 ;;\n"
        "  esac\n"
        "}\n" % (shlex.quote("\n".join(comms)), shlex.quote("\n".join(cmdlines)))
    )
    return _banc(tmp_path, "busy_reason", stub + reason, "busy_reason")


def _procs(tmp_path, genre, motif):
    """`busy_procs` reelle, sur les VRAIS processus. Reponse en 0/1 sur stdout."""
    corps = _tranche("busy_procs")
    return _banc(tmp_path, "busy_procs", corps,
                 'if busy_procs %s %s; then echo 1; else echo 0; fi' % (genre, shlex.quote(motif)))


@contextmanager
def _process(name, argument):
    code = (
        "import ctypes,sys,time; "
        "ctypes.CDLL(None).prctl(15,sys.argv[1].encode(),0,0,0); "
        "print('ready',flush=True); time.sleep(15)"
    )
    proc = subprocess.Popen([sys.executable, "-c", code, name, argument],
                            stdout=subprocess.PIPE, text=True)
    try:
        assert proc.stdout.readline().strip() == "ready"
        yield proc
    finally:
        proc.terminate()
        proc.wait(timeout=5)


def test_prompt_mentionnant_compilateur_ne_bloque_pas(tmp_path):
    """Un worker nomme « codex » dont la ligne de commande cite goalc/ et ninja ne bloque rien."""
    assert _busy(tmp_path, comms=["codex", "python3", "bash"],
                 cmdlines=["codex Lis goalc/ et ninja dans le contrat",
                           "python3 .autoport/orchestrator.py"]) == ""


@pytest.mark.parametrize("name", ["goalc", "ninja", "ninja-build", "cc1plus"])
def test_compilateur_actif_bloque_toujours(tmp_path, name):
    assert _busy(tmp_path, comms=["codex", name],
                 cmdlines=["codex rien du tout"]).startswith("processus ")


def test_lanceur_gradle_reconnu_dans_sa_ligne_de_commande(tmp_path):
    """Le lanceur Java s'appelle « java » : gradle ne vit que dans ses arguments."""
    assert _busy(tmp_path, comms=["java"],
                 cmdlines=["java -jar gradle-wrapper.jar assembleDebug"]) == \
        "processus [g]radle en cours"


def test_aucun_processus_ne_bloque_rien(tmp_path):
    assert _busy(tmp_path) == ""


@pytest.mark.skipif(sys.platform != "linux", reason="comm Linux via prctl")
def test_busy_procs_lit_le_comm_pour_comm_et_la_ligne_pour_cmdline(tmp_path):
    """La seule lecture du VRAI systeme, sur des noms qu'aucun constructeur ne porte.

    C'est ce qui rend la liste injectee fidele : `comm` est le NOM du processus, `cmdline` sa
    ligne de commande entiere. Les deux sentinelles sont uniques — un `ninja` reel qui demarre
    pendant le test ne peut basculer aucune des trois reponses.
    """
    with _process("zzautoportxx", "zzautoportyy"):
        assert _procs(tmp_path, "comm", "[z]zautoportxx") == "1"     # comm = le nom
        assert _procs(tmp_path, "comm", "[z]zautoportyy") == "0"     # les arguments NE SONT PAS le nom
        assert _procs(tmp_path, "cmdline", "[z]zautoportyy") == "1"  # cmdline = la ligne entiere
    assert _procs(tmp_path, "comm", "[z]zautoportxx") == "0"         # et le temoin s'eteint


def test_busy_reason_ne_parle_jamais_au_systeme_en_direct():
    """Une seule porte de sortie vers le systeme, sinon l'injection ne couvre plus tout."""
    reason = _tranche("busy_reason")
    assert "pgrep" not in reason, "busy_reason appelle pgrep en direct : la liste injectee ment"
    assert "busy_procs comm" in reason
    assert "busy_procs cmdline" in reason
    procs = _tranche("busy_procs")
    assert procs.count("pgrep") == 2, procs
