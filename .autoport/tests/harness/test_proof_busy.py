"""La garde du runner distingue un compilateur d'un prompt qui en parle."""
import subprocess
import sys
from contextlib import contextmanager

import pytest

from conftest import AUTOPORT


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
        yield
    finally:
        proc.terminate()
        proc.wait(timeout=5)


def _busy(tmp_path):
    source = (AUTOPORT / "lib" / "proof_run.sh").read_text()
    function = source.split("busy_reason(){", 1)[1].split("\n}\n", 1)[0]
    script = tmp_path / "busy.sh"
    script.write_text("AP=.autoport\nlog(){ :; }\nbusy_reason(){" + function +
                      "\n}\nbusy_reason\n")
    return subprocess.check_output(["bash", str(script)], cwd=tmp_path, text=True).strip()


@pytest.mark.skipif(sys.platform != "linux", reason="comm Linux via prctl")
def test_prompt_mentionnant_compilateur_ne_bloque_pas(tmp_path):
    with _process("codex", "Lis goalc/ et ninja dans le contrat"):
        assert _busy(tmp_path) == ""


@pytest.mark.skipif(sys.platform != "linux", reason="comm Linux via prctl")
@pytest.mark.parametrize("name", ["goalc", "ninja", "ninja-build", "cc1plus"])
def test_compilateur_actif_bloque_toujours(tmp_path, name):
    with _process(name, ""):
        assert _busy(tmp_path).startswith("processus ")
