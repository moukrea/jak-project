"""LE faux backlog des recensements — la VRAIE classe `Backlog` sur un fichier JETABLE.

harness-census-fake-backlog-matches-real-api (23/09). Chaque recensement Linear portait sa propre
classe `FakeBL` recopiee a la main de l'interface du backlog. Quand a0d1b96220 a fait passer
`apply_owner_move` / `pull_owner` par `Backlog.update`, deux d'entre eux ont leve
(« 'FakeBL' object has no attribute 'update' ») : leurs gardes rougissaient sur une panne du banc,
leurs controles positifs etaient morts. Un faux RECOPIE derive des qu'on touche l'original.

Il n'y a donc plus de faux : `Sandbox(items)` ecrit un backlog.yaml dans un dossier temporaire, et
`sandbox.load()` rend un `lib.backlog.Backlog` REEL sur ce fichier — verrou, relecture du disque,
refus d'ecriture (statut inconnu, item archive, owner_feedback raccourci) compris. `sandbox.module`
est le module `lib.backlog` lui-meme, dont SEULS les chemins par defaut sont rediriges vers le
dossier jetable (`load()` sans chemin, `write_prompt` / `prompt_state` sans `ap_dir`) : rien n'ecrit
dans le vrai backlog ni dans les vrais prompts.

ATTENTION, c'est la semantique REELLE : une ecriture relit le disque et remplace `bl.items` par des
dicts NEUFS. La liste `items` passee a `Sandbox` n'est jamais modifiee ; l'etat d'apres se lit sur
le disque (`sandbox.item(id)`, `sandbox.items()`), jamais sur la liste de depart.

Le recensement `harness-census-fake-backlog-matches-real-api.sh` publie `census_fake_api_drift` :
membres du backlog utilises par linear_sync et absents d'un faux, faux prives compris.
"""
import copy
import os
import shutil
import sys
import tempfile
import types

_AP = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _AP not in sys.path:
    sys.path.insert(0, _AP)
from lib import backlog as B  # noqa: E402


class Sandbox:
    """Un backlog.yaml jetable peuple de `items`. Utilisable en `with` (le dossier est efface)."""

    def __init__(self, items=(), version=1):
        self.dir = tempfile.mkdtemp(prefix="census-backlog-")
        self.path = os.path.join(self.dir, "backlog.yaml")
        B._atomic_write(self.path, B._dump({"version": version, "items": copy.deepcopy(list(items))}))
        self.module = self._module()

    def _module(self):
        m = types.ModuleType("backlog_sandbox")
        m.__dict__.update({k: v for k, v in vars(B).items() if not k.startswith("__")})
        m.load = self.load
        m.write_prompt = lambda item, ap_dir=None: B.write_prompt(item, ap_dir or self.dir)
        m.prompt_state = lambda item, ap_dir=None: B.prompt_state(item, ap_dir or self.dir)
        m.DEFAULT_PATH = self.path
        m.SANDBOX = self
        return m

    def load(self, path=None):
        return B.load(path or self.path)

    def items(self):
        """{id: item} RELU du disque."""
        return {it["id"]: it for it in B._read(self.path)["items"]}

    def item(self, iid):
        return self.items().get(iid)

    def close(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
        return False


def install(mod, sandbox):
    """Branche `sandbox` dans un module qui fait `from lib import backlog as B` (linear_sync, owner_sla…) :
    `mod.B` devient le module du bac a sable, et `_CTX['bl']` (s'il existe) un backlog relu."""
    mod.B = sandbox.module
    ctx = getattr(mod, "_CTX", None)
    if isinstance(ctx, dict):
        ctx["bl"] = sandbox.load()
    return sandbox.module
