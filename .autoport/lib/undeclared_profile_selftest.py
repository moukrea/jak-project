#!/usr/bin/env python3
"""LE BANC DE `harness-undeclared-profile-attempts` (2026-09-19). Il MESURE, il ne juge pas.

Il ecrit des lignes `clef=valeur` sur stdout ; `lib/census/harness-undeclared-profile-attempts.sh`
les relit et prononce `undeclared_profile_defects`. Aucune de ces clefs n'entre dans
`proof.txt` sous son nom brut : le recensement les republie sous un prefixe a lui.

QUATRE MESURES, DANS CET ORDRE :

  1. LA POPULATION HISTORIQUE, CLASSEE PAR VOIE DE LANCEMENT (`hist_*`). On relit la
     PREMIERE ligne de chaque `logs/<item>/attempt-NNN.jsonl[.gz]` — `attempt_start` ou
     `phase_start` — et on nomme la voie a partir du journal LUI-MEME (le backend qu'il
     declare, et ce que porte la ligne de commande qu'il a enregistree), jamais a partir
     d'une date ou d'une supposition. Un essai sans modele qu'on ne sait pas nommer est un
     DEFAUT : la porte de l'item exige que les vingt-huit soient classes.

  2. LE REFUS DANS LE CODE LIVRE (`refus_*`). Un profil dont un champ est vide doit LEVER,
     et le refus doit NOMMER le champ. Trois champs, trois portes d'entree.

  3. L'ABLATION (`ablation_*`). Le MEME profil casse, donne au `lib/cli_backend.py` du
     dernier commit SANS ce correctif (ancre par MARQUEUR, `lib/ablation_anchor.sh`) :
     il doit ACCEPTER et produire une ligne de commande SANS `--model`. Les deux bras au
     vert voudraient dire que la porte ne mesure rien.

  4. LE CONTROLE POSITIF (`positif_*`). Un profil RESOLU passe, et sa ligne de commande
     porte bien `--model` et `agents.default_subagent_model`. Sans lui, un `codex_options`
     qui leverait sur TOUT rendrait les mesures 2 et 3 vertes par inaction.
"""
import gzip
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

AUTOPORT = Path(__file__).resolve().parents[1]
ROOT = AUTOPORT.parent
LOGS = AUTOPORT / "logs"
sys.path.insert(0, str(AUTOPORT))
sys.path.insert(0, str(AUTOPORT / "lib"))

from lib import cli_backend, model_profile  # noqa: E402

# L'INSTANT OU LA DONNEE A ETE CORRIGEE, pas le code : commit 50e9dc5af6, 2026-09-07 18:02:07
# +0200, « Fixer Astra pour le harnais et ses sous-agents avec efforts par role ». C'est la
# borne qui separe la population HISTORIQUE (avant) de celle qui ne doit plus rien contenir.
CORRECTIF_DONNEE = datetime(2026, 9, 7, 16, 2, 7, tzinfo=timezone.utc)

PROFIL_SAIN = {
    "manager_model": "modele-de-banc", "manager_effort": "high",
    "worker_model": "modele-de-banc-sous-agent",
    "worker_efforts": {"autoport-researcher": "high", "autoport-tester": "medium"},
    "sandbox": "danger-full-access",
}
CHAMPS = ("manager_model", "manager_effort", "worker_model")

pub: dict[str, object] = {}


def racine_codex(base: Path, profil: dict) -> Path:
    d = base / ".autoport" / "codex"
    d.mkdir(parents=True, exist_ok=True)
    (d / "profiles.json").write_text(json.dumps({"active": "codex-local",
                                                 "profiles": {"codex-local": profil}}))
    return base


# ======================================================== 1. LA POPULATION HISTORIQUE

def premiere_ligne(chemin: Path):
    ouvre = gzip.open if chemin.name.endswith(".gz") else open
    try:
        with ouvre(chemin, "rt", errors="replace") as fh:
            return json.loads(fh.readline())
    except Exception:  # noqa: BLE001
        return None


def voie_de_lancement(ev: dict) -> str:
    """Le nom de la voie, DERIVE du journal. '' si le journal ne permet pas de la nommer.

    On ne lit ni la date ni l'item : uniquement le backend que l'essai declare et ce que
    porte la ligne de commande qu'il a lui-meme enregistree."""
    cmd = ev.get("cmd") or []
    if not isinstance(cmd, list):
        return ""
    plat = " ".join(str(x) for x in cmd)
    backend = ev.get("backend") or ("codex" if cmd[:2] == ["codex", "exec"]
                                    else "claude" if cmd[:1] == ["claude"] else "")
    if backend == "codex":
        if "--model" in cmd:
            return "codex:modele-epingle-mais-non-declare"
        sous = "agents.default_subagent_model=" in plat
        return ("codex/profiles.json:manager_model-vide" if sous
                else "codex/profiles.json:manager_model-et-worker_model-vides")
    if backend == "claude":
        if "--model" not in cmd:
            return "claude:worker_command-sans-modele"
        i = cmd.index("--model")
        if i + 1 >= len(cmd) or not str(cmd[i + 1]).strip():
            return "claude/model-profiles.json:manager_model-vide"
        return "claude:modele-epingle-mais-non-declare"
    return ""


def verdict_de_l_essai(item: str, seq) -> str:
    try:
        f = LOGS / item / f"validator-{int(seq):03d}.txt"
    except (TypeError, ValueError):
        return "inconnu"
    if not f.exists():
        return "absent"
    texte = f.read_text(errors="replace")
    return "vert" if re.search(rf"^\[{re.escape(item)} ok\]", texte, re.M) else "rouge"


def population():
    total = apres = indeclares = indeclares_apres = non_classes = verts = 0
    voies: dict[str, int] = {}
    items: set[str] = set()
    dates: list[str] = []
    for chemin in sorted(LOGS.glob("*/attempt-*.jsonl*")):
        ev = premiere_ligne(chemin)
        if not ev or ev.get("event") not in ("attempt_start", "phase_start"):
            continue
        total += 1
        debut = str(ev.get("started_at") or "")
        try:
            quand = datetime.fromisoformat(debut)
        except ValueError:
            quand = None
        recent = bool(quand and quand > CORRECTIF_DONNEE)
        apres += int(recent)
        modele = ev.get("model")
        if isinstance(modele, str) and modele.strip():
            continue
        indeclares += 1
        indeclares_apres += int(recent)
        dates.append(debut)
        items.add(str(ev.get("item_id") or chemin.parent.name))
        voie = voie_de_lancement(ev)
        if not voie:
            non_classes += 1
            voie = "NON-CLASSE"
        voies[voie] = voies.get(voie, 0) + 1
        if verdict_de_l_essai(chemin.parent.name, ev.get("attempt")) == "vert":
            verts += 1
    pub["hist_journaux"] = total
    pub["hist_journaux_apres_correctif"] = apres
    pub["hist_indeclares"] = indeclares
    pub["hist_indeclares_apres_correctif"] = indeclares_apres
    pub["hist_non_classes"] = non_classes
    pub["hist_voies"] = len(voies)
    pub["hist_items"] = len(items)
    pub["hist_items_noms"] = ",".join(sorted(items)) or "-"
    pub["hist_verts"] = verts
    pub["hist_premier"] = min(dates) if dates else "-"
    pub["hist_dernier"] = max(dates) if dates else "-"
    for voie, n in sorted(voies.items()):
        pub["hist_voie_" + re.sub(r"[^A-Za-z0-9]+", "_", voie).strip("_").lower()] = n


# ============================================================ 2. LE REFUS, CODE LIVRE

def refus():
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        nommes = 0
        for champ in CHAMPS:
            racine_codex(base, dict(PROFIL_SAIN, **{champ: ""}))
            try:
                cli_backend.codex_profile(base)
                pub["refus_codex_" + champ] = 0          # il a ACCEPTE : le defaut est vivant
            except model_profile.ProfileUnresolved as e:
                pub["refus_codex_" + champ] = 1
                nommes += int(champ in str(e))
        pub["refus_codex_champs_nommes"] = nommes
        # La porte d'entree Claude : le repli silencieux est interdit en strict.
        casse = base / "model-profiles.json"
        casse.write_text(json.dumps({"active": "p", "profiles": {
            "p": dict(PROFIL_SAIN, manager_model="")}}))
        import orchestrator
        avant = orchestrator._PROFILE_PATH
        try:
            orchestrator._PROFILE_PATH = casse
            try:
                orchestrator._load_model_profile(strict=True)
                pub["refus_claude_strict"] = 0
            except model_profile.ProfileUnresolved:
                pub["refus_claude_strict"] = 1
            repli = orchestrator._load_model_profile()
            pub["refus_claude_repli_se_denonce"] = int(bool(model_profile.faults(repli)))
        finally:
            orchestrator._PROFILE_PATH = avant


# ================================================================ 4. LE CONTROLE POSITIF

def positif():
    with tempfile.TemporaryDirectory() as tmp:
        base = racine_codex(Path(tmp), dict(PROFIL_SAIN))
        try:
            profil = cli_backend.codex_profile(base)
            cmd = cli_backend.worker_command(base, "codex", profil, "high", 30)
        except Exception as e:  # noqa: BLE001
            pub["positif_resolu_passe"] = 0
            pub["positif_erreur"] = type(e).__name__
            pub["positif_modele"] = "-"
            pub["positif_sous_agents"] = 0
            return
        pub["positif_resolu_passe"] = 1
        pub["positif_modele"] = (cmd[cmd.index("--model") + 1] if "--model" in cmd else "-")
        pub["positif_sous_agents"] = int(any(
            str(t).startswith("agents.default_subagent_model=") for t in cmd))
        pub["positif_model_occurrences"] = cmd.count("--model")


# ==================================================================== 3. L'ABLATION

def blob_avant(chemin_relatif: str, marqueur: str):
    """(source, commit, methode) du dernier etat SANS le marqueur. Jamais `HEAD:`."""
    try:
        sortie = subprocess.run(
            ["bash", str(AUTOPORT / "lib" / "ablation_anchor.sh"), str(ROOT),
             chemin_relatif, marqueur, "kv"],
            capture_output=True, text=True, timeout=180).stdout
    except Exception:  # noqa: BLE001
        return "", "", "erreur"
    champs = dict(l.split("=", 1) for l in sortie.splitlines() if "=" in l)
    commit = champs.get("anchor_commit", "") or ""
    methode = champs.get("anchor_method", "absent")
    if not commit or commit == "-":
        return "", "", methode
    try:
        src = subprocess.run(["git", "-C", str(ROOT), "show", f"{commit}:{chemin_relatif}"],
                             capture_output=True, text=True, timeout=60).stdout
    except Exception:  # noqa: BLE001
        return "", commit, methode
    return src, commit, methode


def importer(source: str, nom: str):
    fd, chemin = tempfile.mkstemp(prefix=nom + "_", suffix=".py")
    with os.fdopen(fd, "w") as fh:
        fh.write(source)
    try:
        spec = importlib.util.spec_from_file_location(nom, chemin)
        mod = importlib.util.module_from_spec(spec)
        sys.modules[nom] = mod
        spec.loader.exec_module(mod)
        return mod
    except Exception:  # noqa: BLE001
        sys.modules.pop(nom, None)
        return None
    finally:
        try:
            os.unlink(chemin)
        except OSError:
            pass


MARQUEUR = "profil-resolu-ou-refus-2026-09-19"


def ablation():
    src, commit, methode = blob_avant(".autoport/lib/cli_backend.py", MARQUEUR)
    pub["ablation_commit"] = (commit or "-")[:12]
    pub["ablation_methode"] = methode
    vieux = importer(src, "cli_backend_avant") if src else None
    if vieux is None:
        pub["ablation_ran"] = 0
        pub["ablation_accepte_le_vide"] = -1
        pub["ablation_commande_sans_modele"] = -1
        pub["ablation_champs_vides_acceptes"] = -1
        return
    pub["ablation_ran"] = 1
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        acceptes = 0
        for champ in CHAMPS:
            racine_codex(base, dict(PROFIL_SAIN, **{champ: ""}))
            try:
                vieux.codex_profile(base)
                acceptes += 1
            except Exception:  # noqa: BLE001
                pass
        pub["ablation_champs_vides_acceptes"] = acceptes
        racine_codex(base, dict(PROFIL_SAIN, manager_model="", worker_model=""))
        try:
            p = vieux.codex_profile(base)
            pub["ablation_accepte_le_vide"] = 1
            cmd = vieux.worker_command(base, "codex", p, "high", 30)
            plat = " ".join(str(x) for x in cmd)
            pub["ablation_commande_sans_modele"] = int(
                "--model" not in cmd and "agents.default_subagent_model=" not in plat)
        except Exception:  # noqa: BLE001
            pub["ablation_accepte_le_vide"] = 0
            pub["ablation_commande_sans_modele"] = 0


def main():
    population()
    refus()
    positif()
    ablation()
    for clef in sorted(pub):
        valeur = str(pub[clef]).replace(" ", "_")
        print(f"{clef}={valeur}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
