"""Une consigne « a-la-main » est-elle en fait NOTRE fabrication, dont l'empreinte s'est perdue ?

`backlog.prompt_state` ne reconnait une consigne comme la notre que par l'empreinte ecrite a sa
fabrication. Empreinte perdue (chemin relatif au cwd jusqu'au 23/09, mecanisme ne le 11/09, fichier
restaure par git apres une refabrication), la consigne passe « a-la-main » : plus jamais
refabriquee, et rien ne le dit.

La preuve d'origine est un REJEU : pour les derniers commits qui ont touche la consigne, le
`backlog.py` DE CE COMMIT rend l'item tel que le `backlog.yaml` DE CE COMMIT le decrivait. Octet
pour octet egal au fichier sur le disque = notre fabrication, et le commit est nomme. Aucune
egalite = on ne sait pas, donc « a la main » (sens conservateur : on n'adopte jamais sans preuve).
"""
import os
import subprocess
import types

import yaml

try:
    from yaml import CSafeLoader as _Loader
except ImportError:                   # machine sans libyaml
    from yaml import SafeLoader as _Loader

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_MODS, _DOCS = {}, {}


def _git(*args):
    return subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True).stdout


def _renderer_at(commit):
    if commit not in _MODS:
        src = _git("show", "%s:.autoport/lib/backlog.py" % commit)
        m = types.ModuleType("backlog_at_" + commit)
        m.__file__ = os.path.join(ROOT, ".autoport", "lib", "backlog.py")   # secret_mask voisin
        try:
            exec(compile(src, m.__name__, "exec"), m.__dict__)
        except Exception:  # noqa: BLE001 — backlog.py illisible a ce commit : pas de rejeu
            m = None
        _MODS[commit] = m
    return _MODS[commit]


def _items_at(commit):
    if commit not in _DOCS:
        try:
            doc = yaml.load(_git("show", "%s:.autoport/backlog.yaml" % commit), Loader=_Loader) or {}
            _DOCS[commit] = {x.get("id"): x for x in doc.get("items") or []}
        except Exception:  # noqa: BLE001
            _DOCS[commit] = {}
    return _DOCS[commit]


def history_renders(item_id, rel_path, depth=6):
    """(commit, rendu) pour les `depth` derniers commits qui ont touche la consigne."""
    for c in _git("log", "--format=%h", "-n", str(depth), "--", rel_path).split():
        old = _items_at(c).get(item_id)
        m = _renderer_at(c)
        if old is None or m is None:
            continue
        try:
            yield c, m.render_prompt(old)
        except Exception:  # noqa: BLE001 — l'item d'alors ne se rend pas : pas de preuve
            continue


def proven_render(content, candidates):
    """Le premier commit dont le rendu egale `content` a l'octet, ou None."""
    for commit, rendu in candidates:
        if rendu == content:
            return commit
    return None
