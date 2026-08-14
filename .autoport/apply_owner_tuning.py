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


def _apply_kvs(line, kvs):
    """Applique des `cle=valeur` a UNE ligne de physics_chains.txt, sans jamais ecrire dans son
    commentaire.

    POURQUOI CETTE FONCTION EXISTE — un piege mesure le 2026-08-13, et il ne se voit pas a l'oeil.
    L'ancienne version faisait `line = line + " " + kv` pour une cle absente. Or la plupart des
    lignes de chaines portent un commentaire en fin de ligne (`... radii=222,335   # maxangle DERIVE
    du rig ...`). La cle neuve atterrissait donc APRES le `#`, c'est-a-dire DANS le commentaire :
    le parseur C++ ne la voyait jamais, le moteur lisait la valeur par defaut, et la course
    mesurait un correctif INERTE. On aurait conclu « ce correctif ne fait rien » alors qu'il
    n'avait tout simplement pas ete livre — la pire des issues, parce qu'elle ferme une piste
    juste sur une mesure fausse.
    Constate sur les cinq chaines de cheveux : `gradient=0.152` ecrit derriere le `#`.

    Le meme decoupage protege le chemin de REMPLACEMENT : `re.sub` sans `count` remplace TOUTES les
    occurrences, donc une cle qui apparaitrait aussi dans le texte du commentaire y serait
    reecrite. On ne touche que la partie CODE, et on recolle le commentaire tel quel.
    """
    head, sep, tail = line.partition("#")
    for kv in kvs:
        k, v = kv.split("=", 1)
        if re.search(r"\b%s=" % re.escape(k), head):
            # le parametre existe : on le remplace. Ne JAMAIS ajouter ici, sinon une
            # seconde application produit "radius=708 radius=708" (constate le 2026-08-11).
            head = re.sub(r"\b%s=[-0-9.,]+" % re.escape(k), "%s=%s" % (k, v), head)
        else:
            head = head.rstrip() + " " + kv + ("   " if sep else "")
    return head + sep + tail


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
    skipped = []

    # les joints que le rig HD porte REELLEMENT : une directive qui en nomme un autre n'a pas de
    # cible, et ça se dit à voix haute (voir `+chain` plus bas).
    rig_joints = set()
    rig_path = CHAINS.parent / "hd_anim" / "keira-hd-k2e.json"
    if rig_path.exists():
        import json
        rig_joints = {r["hd_name"] for r in json.load(open(rig_path))["rows"]}

    for raw in TUNING.read_text(errors="ignore").split("\n"):
        ln = raw.strip()
        if not ln or ln.startswith("#"):
            continue
        # commentaire de fin de ligne : la gate TUNING les ignore, l'applicateur doit faire pareil
        # (sinon `chain chestL stiffness=2.20  # couple: voir 5e passe` le fait planter).
        if "#" in ln:
            ln = ln.split("#", 1)[0].strip()
            if not ln:
                continue

        if ln.startswith("+chain "):
            # Ajout d'une CHAINE demandee par l'owner sur un os que la generation avait ignore.
            # 2026-08-12 : LfootFlaps / RfootFlaps ne portaient aucune chaine — ce sont les
            # « languettes au niveau des genoux » qu'il voit immobiles depuis deux jours.
            body = ln[len("+chain "):]
            name = body.split()[0]
            if re.search(r"^chain %s\b" % re.escape(name), s, re.M):
                continue
            # UNE DIRECTIVE SANS CIBLE EST SIGNALÉE, JAMAIS AVALÉE EN SILENCE (DIRECTIVES).
            # Une chaîne dont les joints n'existent pas dans le rig produit une chaîne à ZÉRO
            # lien : le générateur de tableau plante dessus, et si elle passait, elle serait
            # déclarée-et-inerte — exactement ce que la gate MOVE refuse. Mesuré le 2026-08-12 :
            # `LfootFlaps`/`RfootFlaps` sont ABSENTS du rig HD que Keira utilise
            # (recharged_assets/hd_anim/keira-hd-k2e.json, 95 joints ; il porte `lKneeFlap`,
            # `rKneeFlap`, `LpantFlap`, `RpantFlap` et rien d'autre en -Flap).
            want = []
            mj = re.search(r"\bjoints=(\S+)", body)
            if mj:
                want = mj.group(1).split(",")
            absent = [j for j in want if j not in rig_joints]
            if absent:
                skipped.append((name, absent))
                continue
            last = None
            for last in re.finditer(r"^chain .*$", s, re.M):
                pass
            ins = "chain " + body
            s = (s[:last.end()] + "\n" + ins + s[last.end():]) if last else (s + "\n" + ins + "\n")
            nadd += 1
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
            line = _apply_kvs(m.group(0), kvs)
            s = s[:m.start()] + line + s[m.end():]
            ncol += 1

        elif ln.startswith("chain "):
            parts = ln.split()
            name, kvs = parts[1], parts[2:]
            m = re.search(r"^chain %s\b.*$" % re.escape(name), s, re.M)
            if not m:
                missing.append(ln[:60])
                continue
            line = _apply_kvs(m.group(0), kvs)
            s = s[:m.start()] + line + s[m.end():]
            nchain += 1

    # ---- UN VOLUME DÉRIVÉ NE PEUT PAS ANNULER UN RÉGLAGE DE L'OWNER --------------------------
    # Le générateur émet, pour chaque joint de chaîne, une sphère RECENTRÉE dont le rayon EST le
    # rayon de lien : elle corrige la position du volume, jamais sa taille. Mais le générateur
    # calcule ce rayon depuis le mesh, AVANT que ce fichier-ci n'applique les `radii=` de l'owner.
    # Mesuré le 2026-08-12 : `chain goggles radii=196,150` (son réglage) contre
    # `collider gogglesMid radius=79` (le rayon dérivé) — et le moteur prend le collider
    # (jak-hd-physics.gc, étape 3b). Le volume des lunettes serait passé de 150 à 79 sans que
    # personne ne l'ait demandé. C'est la récurrence que la règle de non-destruction interdit, et
    # on la rend impossible ICI, au dernier écrivain, pas détectable plus loin.
    lines = s.split("\n")
    jl = {}                                   # joint -> (index de ligne `chain`, numéro de lien)
    cur, nlink = None, 0
    for i, ln in enumerate(lines):
        if ln.startswith("chain "):
            cur, nlink = i, 0
        elif ln.startswith("j ") and cur is not None:
            jl[ln.split()[1]] = (cur, nlink)
            nlink += 1
    nsync = 0
    orphan = []
    for i, ln in enumerate(lines):
        if not ln.startswith("collider ") or i == 0 or "RECENTRE" not in lines[i - 1]:
            continue
        joint = ln.split()[1]
        if joint not in jl:
            orphan.append(joint)
            continue
        ci, li = jl[joint]
        mr = re.search(r"\bradii=([-0-9.,]+)", lines[ci])
        want = None
        if mr:
            vals = mr.group(1).split(",")
            if li < len(vals):
                want = vals[li]
        if want is None:
            mb = re.search(r"\bradius=([-0-9.]+)", lines[ci])
            want = mb.group(1) if mb else None
        if want is None:
            continue
        new = re.sub(r"\bradius=[-0-9.]+", "radius=%s" % want, ln)
        if new != ln:
            print("[tuning] volume recentré %s : radius %s -> %s (le rayon de lien livré)"
                  % (joint, re.search(r"\bradius=([-0-9.]+)", ln).group(1), want))
            lines[i] = new
            nsync += 1
    if nsync or orphan:
        s = "\n".join(lines)
    if orphan:
        # Un volume RECENTRÉ dont le joint n'appartient à aucune chaîne n'a pas de rayon de lien à
        # suivre : la règle qui l'a produit ne s'applique plus, et le taire laisserait un volume
        # dont personne ne sait d'où vient la taille.
        #
        # SAUF QUAND LE FICHIER DÉCLARE UN PÉRIMÈTRE GELÉ (owner 2026-08-14 07:30, « retire toute
        # physique de Keira hormis ses seins »). Là, l'absence de chaîne porteuse est VOULUE : la
        # chaîne a été retirée et le volume reste comme OBSTACLE, à son rayon ajusté au mesh. Crier
        # à la perte serait crier contre l'ordre qu'on vient d'exécuter. L'exemption est bornée par
        # la présence du bloc que le générateur écrit lui-même : sans gel déclaré, la règle dure
        # reprend telle quelle.
        if "PERIMETRE SIMULE — ORDRE DE L'OWNER" in s:
            print("[tuning] %d volume(s) RECENTRÉ(s) sans chaîne porteuse — ATTENDU : leur chaîne "
                  "est GELÉE par l'ordre de l'owner du 2026-08-14 07:30, le volume reste comme "
                  "OBSTACLE au rayon ajusté au mesh : %s" % (len(orphan), ", ".join(sorted(orphan))))
        else:
            missing.append("collider RECENTRE sans chaîne porteuse : " + ", ".join(sorted(orphan)))

    if skipped:
        # La trace reste DANS le fichier livré : c'est le seul endroit que personne ne peut
        # oublier de lire, et ça empêche qu'une directive disparaisse entre deux régénérations.
        note = ["", "# ---- DIRECTIVE OWNER SANS CIBLE DANS LE RIG — NON APPLIQUÉE, ET DITE ICI."]
        for name, absent in skipped:
            note.append("#   +chain %s : joint(s) %s absent(s) de recharged_assets/hd_anim/"
                        "keira-hd-k2e.json" % (name, ",".join(absent)))
        note.append("#   Le rig HD que Keira utilise porte 95 joints ; les seuls en -Flap sont")
        note.append("#   lKneeFlap, rKneeFlap, LpantFlap, RpantFlap. Une chaîne posée sur un joint")
        note.append("#   inexistant aurait ZÉRO lien : déclarée et inerte, ce que la gate MOVE")
        note.append("#   refuse à juste titre. La directive doit être re-visée sur un joint réel.")
        s = s + "\n".join(note) + "\n"

    CHAINS.write_text(s)
    print("[tuning] appliqué : %d chaîne(s), %d collider(s) modifié(s), %d ajouté(s)"
          % (nchain, ncol, nadd))
    for name, absent in skipped:
        print("[tuning] ATTENTION — +chain %s NON APPLIQUÉE : joint(s) %s absent(s) du rig HD"
              % (name, ",".join(absent)))
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
