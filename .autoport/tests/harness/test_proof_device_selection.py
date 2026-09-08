"""Exercise official proof selection with a fake transport; no device access."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]


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
    script = source[start:end] + '\nprintf "%s" "$SERIAL"\n'
    env = dict(os.environ, ADB=str(adb), AP=str(ROOT / '.autoport'),
               ANDROID_SERIAL='eae4df44', ITEM_SERIAL='', HDR_CAMPAIGN='test',
               OUTFILE=str(tmp_path / 'proof.txt'))
    result = subprocess.run(['bash', '-c', script], env=env, text=True, capture_output=True)
    assert result.returncode == 0, result.stderr
    assert result.stdout == 'AREE026206000788'


def test_proof_rejects_network_override(tmp_path):
    source = (ROOT / '.autoport/lib/proof_run.sh').read_text()
    start = source.index('  SERIAL=$(ANDROID_SERIAL=')
    end = source.index('  ADB=', start)
    result = subprocess.run(['bash', '-c', source[start:end]],
        env=dict(os.environ, AP=str(ROOT / '.autoport'), ANDROID_SERIAL='192.0.2.1:5555',
                 ITEM_SERIAL='', OUTFILE=str(tmp_path / 'proof.txt')),
        text=True, capture_output=True)
    assert result.returncode == 3
    assert 'adresse reseau' in result.stderr
