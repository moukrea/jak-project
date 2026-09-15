"""Le nettoyage des sondes ne doit jamais supprimer un chemin de repli."""
import shlex
import subprocess

import pytest

from conftest import AUTOPORT


@pytest.mark.parametrize("variable", ["ZFBRUT", "ZFCTX"])
@pytest.mark.parametrize("value", [None, "", "sondes avec espaces.txt"])
def test_context_cleanup_only_removes_its_file(variable, value):
    source = (AUTOPORT / "lib" / "proof_run.sh").read_text()
    cleanup = [line for line in source.splitlines()
               if "rm -f" in line and variable in line]
    assert len(cleanup) == 1, "La commande de nettoyage doit etre exercee exactement une fois"
    setup = f"unset {variable}" if value is None else f"{variable}={shlex.quote(value)}"
    # Intercepter rm : meme la regression ne doit jamais toucher /dev/null.
    script = "set -eu\nrm() { printf '%s\\n' \"$@\"; }\n"
    result = subprocess.run(["bash", "-c", script + setup + "\n" + cleanup[0] + "\n"],
                            capture_output=True, text=True, check=False)
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == (["-f", "--", value] if value else [])
