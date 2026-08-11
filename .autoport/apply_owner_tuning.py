#!/usr/bin/env python3
"""Applique recharged_assets/keira-owner-tuning.txt par-dessus physics_chains.txt.

physics_chains.txt est GÉNÉRÉ depuis le rig. Le 2026-08-11, deux séries de réglages issus des
retours de l'owner ont été effacées par une régénération — il testait un APK dont les corrections
qu'il avait demandées avaient disparu. Un réglage validé par son œil vaut plus qu'une valeur
dérivée d'une règle : il survit donc à la génération.

À appeler APRÈS toute régénération de physics_chains.txt, et avant tout empaquetage.
Idempotent : réappliquer ne change rien.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHAINS = ROOT / "recharged_assets" / "physics_chains.txt"
TUNING = ROOT / "recharged_assets" / "keira-owner-tuning.txt"


def main():
    if not TUNING.exists():
        print("[tuning] aucun fichier de réglages owner — rien à appliquer")
        return 0
    if not CHAINS.exists():
        print("[tuning] physics_chains.txt absent", file=sys.stderr)
        return 1

    s = CHAINS.read_text(errors="ignore")
    nchain = ncol = nadd = 0
    missing = []

    for raw in TUNING.read_text(errors="ignore").split("\n"):
        ln = raw.strip()
        if not ln or ln.startswith("#"):
            continue

        if ln.startswith("+collider "):
            body = ln[len("+collider "):]
            name = body.split()[0]
            # `to=<joint>` est la syntaxe LISIBLE de ce fichier pour « volume balayé de <name> vers
            # <joint> ». Le moteur, lui, ne connaît que la forme `capsule <A> <B> ...` : `to=` y est
            # une clé INCONNUE, ignorée avec un simple warning, et la ligne devenait une SPHÈRE.
            # Mesuré le 2026-08-11 : les colliders de tronc et de mollet demandés par l'owner
            # (« ses bretelles passent au travers de son torse », « le bout du pantacourt glitche au
            # travers de son mollet ») étaient posés en sphères sur chest/Lknee/Rknee — donc son
            # défaut ne pouvait pas être corrigé. La traduction se fait ici, une fois.
            mto = re.search(r"\bto=(\S+)", body)
            if mto:
                body = "capsule %s %s %s" % (name, mto.group(1),
                                             re.sub(r"\s*\bto=\S+", "", body[len(name):]).strip())
                ln = "+" + body
                if re.search(r"^capsule %s %s\b" % (re.escape(name), re.escape(mto.group(1))),
                             s, re.M):
                    continue                  # déjà présent (idempotence)
            elif re.search(r"^collider %s\b" % re.escape(name), s, re.M):
                continue                      # déjà présent (idempotence)
            last = None
            for last in re.finditer(r"^(collider|capsule) .*$", s, re.M):
                pass
            if last is None:
                s += "\n" + ln[1:] + "\n"
            else:
                s = s[:last.end()] + "\n" + ln[1:] + s[last.end():]
            nadd += 1

        elif ln.startswith("collider "):
            parts = ln.split()
            name, kvs = parts[1], parts[2:]
            m = re.search(r"^collider %s\b.*$" % re.escape(name), s, re.M)
            if not m:
                missing.append(ln[:60])
                continue
            line = m.group(0)
            for kv in kvs:
                k, v = kv.split("=", 1)
                if re.search(r"\b%s=" % re.escape(k), line):
                    # le parametre existe : on le remplace. Ne JAMAIS ajouter ici, sinon une
                    # seconde application produit "radius=708 radius=708" (constate le 2026-08-11).
                    line = re.sub(r"\b%s=[-0-9.,]+" % re.escape(k), "%s=%s" % (k, v), line)
                else:
                    line = line + " " + kv
            s = s[:m.start()] + line + s[m.end():]
            ncol += 1

        elif ln.startswith("chain "):
            parts = ln.split()
            name, kvs = parts[1], parts[2:]
            m = re.search(r"^chain %s\b.*$" % re.escape(name), s, re.M)
            if not m:
                missing.append(ln[:60])
                continue
            line = m.group(0)
            for kv in kvs:
                k, v = kv.split("=", 1)
                if re.search(r"\b%s=" % re.escape(k), line):
                    # le parametre existe : on le remplace. Ne JAMAIS ajouter ici, sinon une
                    # seconde application produit "radius=708 radius=708" (constate le 2026-08-11).
                    line = re.sub(r"\b%s=[-0-9.,]+" % re.escape(k), "%s=%s" % (k, v), line)
                else:
                    line = line + " " + kv
            s = s[:m.start()] + line + s[m.end():]
            nchain += 1

    CHAINS.write_text(s)
    print("[tuning] appliqué : %d chaîne(s), %d collider(s) modifié(s), %d ajouté(s)"
          % (nchain, ncol, nadd))
    if missing:
        # Ne pas échouer en silence : une cible absente veut dire que le rig ou la génération a
        # changé, et que le réglage de l'owner ne s'applique plus à rien.
        print("[tuning] ATTENTION — %d directive(s) sans cible dans le fichier généré :" % len(missing))
        for x in missing:
            print("[tuning]   %s" % x)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
