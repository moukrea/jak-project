"""Le comparateur de fraicheur du harnais, cote python ET cote shell.

Ces tests tiennent les DEUX regles que `harness-subsecond-freshness-is-blind` a posees le
2026-09-12, la ou elles se cassent : au POINT DE PRODUCTION. La preuve de l'item mesure les
quatre sites qui appellent le comparateur ; ici on tient le comparateur lui-meme, a chaque
fermeture, pour que personne ne le desserre en silence.

  1. la sous-seconde survit a la lecture, des deux cotes ;
  2. l'egalite ne vaut pas fraicheur — elle vaut DOUTEUX, et l'appelant refuse.
"""
import subprocess
import sys
from pathlib import Path

AP = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(AP / "lib"))

import freshness as F  # noqa: E402


def test_ns_de_garde_la_sous_seconde_des_deux_ecritures():
    # `stat -c %.9Y` rend NEUF chiffres, `find -printf %T@` en rend DIX (un zero de
    # remplissage) : les coller tels quels decalerait tout d'un facteur dix.
    assert F.ns_de("1700000000.500000000") == 1700000000500000000
    assert F.ns_de("1700000000.5000000000") == 1700000000500000000
    # La virgule est un separateur decimal sous une locale francaise.
    assert F.ns_de("1700000000,500000000") == 1700000000500000000
    assert F.ns_de("1700000000") == 1700000000000000000


def test_egalite_vaut_douteux_jamais_frais():
    assert F.verdict(2, 1) == F.FRAIS
    assert F.verdict(1, 2) == F.PERIME
    assert F.verdict(1, 1) == F.DOUTEUX


def test_resolution_nomme_une_troncature():
    assert F.resolution(1700000000000000000) == "s"
    assert F.resolution(1700000000000000001) == "ns"
    assert F.resolution(0) == "absent"


def test_artefact_au_meme_horodatage_que_t0_nest_pas_une_preuve():
    # Le cas du boot-check de la porte de fermeture : `t0` et le mtime sont a la seconde
    # entiere des DEUX cotes. Un fichier ecrit 0,9 s AVANT t0 porte le meme entier que lui.
    frais, douteux = F.classer_artefacts(
        "99 files/avant.txt\n100 files/pile.txt\n101 files/apres.txt\n", 100)
    assert frais == ["files/apres.txt"]
    assert douteux == ["files/pile.txt"]


def test_le_jumeau_shell_rend_les_memes_verdicts(tmp_path):
    # Deux comparateurs qui divergent valent moins qu'un seul : on le verifie, on ne l'espere pas.
    script = (
        '. "%s/lib/freshness.sh"\n'
        'echo "$(fr_ns_de 1700000000.5000000000)"\n'
        'echo "$(fr_verdict 2 1)"; echo "$(fr_verdict 1 2)"; echo "$(fr_verdict 1 1)"\n'
        'echo "$(fr_resolution 1700000000000000000)"\n'
        'printf "1700000000.1\\n1700000000.9\\n1700000000.5\\n" | fr_plus_recent_ns\n'
    ) % AP
    sortie = subprocess.run(["bash", "-c", script], capture_output=True, text=True,
                            timeout=60).stdout.split()
    assert sortie == ["1700000000500000000", "frais", "perime", "douteux", "s",
                      "1700000000900000000"]


def test_le_registre_couvre_ce_quil_pretend_couvrir():
    # Un registre a quatre colonnes et a classes connues, ou il ne classe rien.
    reg = (AP / "lib" / "freshness_registry.tsv").read_text(encoding="utf-8")
    lignes = [l for l in reg.splitlines() if l.strip() and not l.startswith("#")]
    assert len(lignes) > 40
    for ligne in lignes:
        champs = ligne.split("\t")
        assert len(champs) == 4, ligne
        assert champs[2] in ("corrige", "laisse", "non-fraicheur", "prose"), ligne
        assert champs[3].strip(), ligne
