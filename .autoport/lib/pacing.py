"""lib/pacing.py — LE FREIN D'USAGE DE L'OWNER, VU DEPUIS L'ARBRE DE PROCESSUS DU WORKER.

harness-copes-with-usage-pacing, 2026-09-24. MARQUEUR: frein-d-usage-2026-09-24

L'owner porte un crochet global UserPromptSubmit (`resetdeck-agent ... pacing-hook --provider
claude`, borne 691200 s) qui MET EN PAUSE les sessions Claude pour tenir sous les limites
d'usage HEBDOMADAIRES. C'est VOULU. Il tourne aussi dans nos workers `claude -p` : pendant la
pause le worker ne produit rien, et le 23/09 les gardes « aucun progres » / « silence » de
l'orchestrateur ont tue huit essais d'affilee et bloque deux items.

Owner, 24/09 : « Faut que le harnais compose avec ce frein, c'est un frein qui sert a eviter
les rates limits weekly, c'est fait expres mais faudrait pas que notre harnais explose a
chaque fois qu'il est freine ! »

CE QUE CE MODULE FAIT, ET RIEN D'AUTRE : il dit si un crochet de rythme est EN COURS
D'EXECUTION parmi les descendants d'un processus (ou dans sa session : un petit-fils
re-parente sur le subreaper garde son sid). Il lit `/proc/<pid>/stat` et `/proc/<pid>/cmdline`,
jamais un fichier de resetdeck : le jeton de `state/runtime.json` n'est pas lu, et la ligne de
commande n'est jamais publiee (seul le pid et le nom « pacing-hook » sortent). Il ne touche pas
au crochet : ni signal, ni exclusion, ni contournement.

Un zombie n'est pas un crochet vivant (`kill -0` reussit sur un zombie : on lit l'etat Z).
"""
from __future__ import annotations

import json
import os
import time
from pathlib import Path

# Le jeton qui designe le crochet dans sa ligne de commande. Compare MOT A MOT : un argument
# `sh -c "... pacing-hook --provider claude"` est coupe sur les blancs, et un chemin qui
# contiendrait la sous-chaine (`/tmp/pacing-hook-notes.md`) ne matche pas.
PACING_TOKENS = ("pacing-hook",)

_CLK_TCK = os.sysconf("SC_CLK_TCK") if hasattr(os, "sysconf") else 100
_BOOT = None


def _boot_time() -> float:
    global _BOOT
    if _BOOT is None:
        try:
            for ln in Path("/proc/stat").read_text().splitlines():
                if ln.startswith("btime "):
                    _BOOT = float(ln.split()[1])
                    break
        except OSError:
            pass
        if _BOOT is None:
            _BOOT = 0.0
    return _BOOT


def _stat(pid: int) -> tuple[str, int, int, int] | None:
    """(etat, ppid, sid, starttime en ticks) ou None."""
    try:
        raw = Path(f"/proc/{pid}/stat").read_text()
    except OSError:
        return None
    # comm peut porter des espaces et des parentheses : on coupe a la DERNIERE `)`.
    rest = raw[raw.rfind(")") + 2:].split()
    try:
        return rest[0], int(rest[1]), int(rest[3]), int(rest[19])
    except (IndexError, ValueError):
        return None


def _is_pacing_cmdline(pid: int) -> bool:
    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes()
    except OSError:
        return False
    for arg in raw.split(b"\0"):
        for tok in arg.split():
            if tok.decode("utf-8", "replace") in PACING_TOKENS:
                return True
    return False


def scan(root_pid: int) -> list[dict]:
    """Les crochets de rythme VIVANTS sous `root_pid` (descendants ou meme session).

    Chaque entree : {pid, started_at (epoch s), age_s}. Liste vide = aucun frein en cours."""
    if not root_pid or root_pid <= 0:
        return []
    table: dict[int, tuple[str, int, int, int]] = {}
    try:
        names = os.listdir("/proc")
    except OSError:
        return []
    for n in names:
        if n.isdigit():
            st = _stat(int(n))
            if st is not None:
                table[int(n)] = st
    children: dict[int, list[int]] = {}
    for pid, (_s, ppid, _sid, _t) in table.items():
        children.setdefault(ppid, []).append(pid)
    tree, todo = set(), [root_pid]
    while todo:
        p = todo.pop()
        for c in children.get(p, ()):
            if c not in tree:
                tree.add(c)
                todo.append(c)
    # Le worker est chef de sa session (Popen start_new_session=True) : un descendant
    # re-parente sur le subreaper reste dans la session, MEME quand le worker est deja mort
    # (sid = pid du chef, qui n'existe plus). Un sid n'egale un pid que pour un chef de session.
    tree.update(pid for pid, st in table.items() if st[2] == root_pid and pid != root_pid)
    now, boot = time.time(), _boot_time()
    hits = []
    for pid in sorted(tree):
        state, _ppid, _sid, start = table[pid]
        if state == "Z" or not _is_pacing_cmdline(pid):
            continue
        started = boot + start / float(_CLK_TCK)
        hits.append({"pid": pid, "started_at": round(started, 1),
                     "age_s": round(max(0.0, now - started), 1)})
    return hits


class Tracker:
    """L'etat « freine » d'un essai, tenu par la boucle de lecture de l'orchestrateur.

    `poll()` est appele a chaque tranche de lecture ; il rend True tant qu'un crochet tourne.
    Le temps freine est cumule en horloge MONOTONE ; `closed_s` est ce qu'une garde doit
    ajouter a ses reperes a la sortie d'une pause pour que ce temps ne compte pas."""

    def __init__(self, root_pid: int, publish_path: Path | None = None,
                 publish_after_s: float = 60.0, **ident):
        self.root_pid = root_pid
        self.publish_path = publish_path
        # Le crochet tourne aussi, BREVEMENT, a chaque PreToolUse/PostToolUse : publier chaque
        # passage ferait clignoter `autoport status`, et watch.py reveille le superviseur a
        # chaque changement de texte. On ne publie qu'une pause qui a DURE.
        self.publish_after_s = publish_after_s
        self.published = False
        self.logged = False
        self.ident = ident
        self.active = False
        self.since_mono = 0.0
        self.since_epoch = 0.0
        self.episodes = 0
        self.total_s = 0.0
        self.max_s = 0.0
        self.pids: list[int] = []
        self.polls = 0
        self.last_seen_mono = 0.0

    def poll(self) -> tuple[bool, float]:
        """(actif, secondes de pause qui viennent de se CLORE — 0 sinon)."""
        self.polls += 1
        hits = scan(self.root_pid)
        now = time.monotonic()
        closed = 0.0
        if hits:
            self.last_seen_mono = now
            self.pids = [h["pid"] for h in hits]
            if not self.active:
                self.active = True
                self.episodes += 1
                self.since_mono = now
                self.since_epoch = time.time()
            if not self.published and now - self.since_mono >= self.publish_after_s:
                self._publish()
        elif self.active:
            closed = now - self.since_mono
            self.total_s += closed
            self.max_s = max(self.max_s, closed)
            self.active = False
            self._unpublish()
        return self.active, closed

    def current_s(self) -> float:
        return (time.monotonic() - self.since_mono) if self.active else 0.0

    def close(self) -> None:
        if self.active:
            d = time.monotonic() - self.since_mono
            self.total_s += d
            self.max_s = max(self.max_s, d)
        self._unpublish()

    def record(self, active_at_end: bool) -> dict:
        return {"episodes": self.episodes, "total_s": round(self.total_s, 1),
                "max_s": round(self.max_s, 1), "active_at_end": bool(active_at_end),
                "hook_pids": self.pids[-4:], "polls": self.polls}

    # ---- LA PUBLICATION, lue par `autoport status` et le reveil du superviseur ----------
    def _publish(self) -> None:
        self.published = True
        if not self.publish_path:
            return
        rec = dict(self.ident, orchestrator_pid=os.getpid(), worker_pid=self.root_pid,
                   hook_pids=self.pids, since_epoch=round(self.since_epoch, 1))
        try:
            self.publish_path.parent.mkdir(parents=True, exist_ok=True)
            tmp = self.publish_path.with_name(self.publish_path.name + f".tmp.{os.getpid()}")
            tmp.write_text(json.dumps(rec) + "\n")
            os.replace(tmp, self.publish_path)
        except OSError:
            pass

    def _unpublish(self) -> None:
        was, self.published = self.published, False
        if not self.publish_path or not was:
            return
        try:
            rec = json.loads(self.publish_path.read_text())
            if int(rec.get("orchestrator_pid", 0)) != os.getpid():
                return                      # l'etat d'un autre orchestrateur : pas a nous
        except (OSError, ValueError):
            return
        try:
            self.publish_path.unlink()
        except OSError:
            pass


def _alive(pid: int) -> bool:
    st = _stat(pid) if pid else None
    return bool(st) and st[0] != "Z"


def current(publish_path: Path) -> dict | None:
    """L'etat « freine » publie, s'il est VRAI maintenant : l'orchestrateur qui l'a ecrit vit et
    un crochet de rythme tourne encore sous son worker. Un fichier perime rend None."""
    try:
        rec = json.loads(Path(publish_path).read_text())
    except (OSError, ValueError):
        return None
    if not _alive(int(rec.get("orchestrator_pid", 0) or 0)):
        return None
    if not scan(int(rec.get("worker_pid", 0) or 0)):
        return None
    return rec


def human_since(epoch: float) -> str:
    """« 14:05 », ou « le 23/09 14:05 » hors du jour : un repere FIXE, jamais un age a la
    seconde (watch.py reveille le superviseur des que le texte de statut change)."""
    lt = time.localtime(epoch)
    if time.strftime("%Y%m%d", lt) == time.strftime("%Y%m%d"):
        return time.strftime("%H:%M", lt)
    return time.strftime("le %d/%m %H:%M", lt)
