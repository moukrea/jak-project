"""Exercise official proof selection with a fake transport; no device access."""
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]

# L'AUTORITE DE NOMMAGE des fichiers d'une course. Ces tests decoupent une TRANCHE du vrai
# `proof_run.sh` : s'ils lui passaient un nom de sortie reecrit ici, ils verifieraient un
# fichier que la course n'ecrit plus, et l'assertion tomberait sur une absence sans le dire.
sys.path.insert(0, str(ROOT / '.autoport' / 'lib'))
import impossible as NOMS  # noqa: E402


def _prelude(source):
    """`log` et `die3`, tels que le script les definit.

    Les deux tests decoupent une TRANCHE de proof_run.sh et la font tourner seule. Depuis que
    toute sortie 3 passe par `die3` (etat NOMME « preuve impossible »), une tranche sans cette
    definition sort en 127 « commande introuvable » et le test lit 0 au lieu de 3 : il
    mesurerait son propre decoupage. On embarque donc la VRAIE definition, pas un bouchon."""
    start = source.index('log(){ printf')
    end = source.index('\n}\n', source.index('die3(){', start)) + len('\n}\n')
    return source[start:end]


def test_hdr_falls_back_from_missing_redmi_to_usb_honor(tmp_path):
    adb = tmp_path / 'adb'
    adb.write_text('''#!/bin/bash
if [ "$1" = devices ]; then
  printf 'List of devices attached\\n192.0.2.1:5555 device\\nAREE026206000788 device\\n'
else
  exit 1
fi
''')
    adb.chmod(0o755)
    source = (ROOT / '.autoport/lib/proof_run.sh').read_text()
    start = source.index('  SERIAL=$(ANDROID_SERIAL=')
    end = source.index('  ADB=', start)
    script = _prelude(source) + source[start:end] + '\nprintf "%s" "$SERIAL"\n'
    env = dict(os.environ, ADB=str(adb), AP=str(ROOT / '.autoport'),
               ANDROID_SERIAL='eae4df44', ITEM_SERIAL='', HDR_CAMPAIGN='test',
               ID='test-selection', D=str(tmp_path), SUF='',
               OUTFILE=str(tmp_path / NOMS.arm_name('proof', '')))
    result = subprocess.run(['bash', '-c', script], env=env, text=True, capture_output=True)
    assert result.returncode == 0, result.stderr
    assert result.stdout == 'AREE026206000788'


def test_proof_rejects_network_override(tmp_path):
    source = (ROOT / '.autoport/lib/proof_run.sh').read_text()
    start = source.index('  SERIAL=$(ANDROID_SERIAL=')
    end = source.index('  ADB=', start)
    result = subprocess.run(['bash', '-c', _prelude(source) + source[start:end]],
        env=dict(os.environ, AP=str(ROOT / '.autoport'), ANDROID_SERIAL='192.0.2.1:5555',
                 ITEM_SERIAL='', ID='test-selection', D=str(tmp_path), SUF='',
                 OUTFILE=str(tmp_path / NOMS.arm_name('proof', ''))),
        text=True, capture_output=True)
    assert result.returncode == 3
    assert 'adresse reseau' in result.stderr
    # LA SORTIE 3 EST UN ETAT NOMME, pas une absence. Une preuve impossible doit se lire
    # « impossible » : le refus ecrit son fichier, avec sa raison.
    nomme = tmp_path / NOMS.arm_name('impossible', '')
    assert nomme.exists(), result.stderr
    corps = nomme.read_text()
    # `pick_device.sh` refuse l'adresse reseau AVANT le filtre du script : c'est donc lui
    # qui nomme la sortie. Les deux chemins ecrivent le meme etat nomme.
    assert 'proof_impossible_reason=appareil-non-choisi' in corps
    assert 'proof_impossible_exit=3' in corps
