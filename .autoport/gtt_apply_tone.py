#!/usr/bin/env python3
"""Phase Gtext-tone — applique la table de TON aux banques de texte de jak1.

Owner 2026-08-28 : « "Appuyer sur la touche start" c'est hyper formel et l'infinitif est
bizarre... Ca colle pas a l'esprit teenager du jeu. [...] de meme dans les autres langues,
moins formel, moins robotique. »

CE QUE CE SCRIPT FAIT
---------------------
Il ecrit les formulations de `.autoport/gtext_tone_table.json` dans
`game/assets/jak1/text/game_custom_text_<lang>.json` (et les deux fichiers de surcharge
`game_custom_text_android_<lang>.json`), puis publie l'audit AVANT -> APRES.

POURQUOI CE FICHIER-LA ET PAS `game_case_text_<lang>.json`
----------------------------------------------------------
`recharged_assets/font/gen_mixed_case.py` (phase Gfont-urbanist, ACTIVE) **regenere
integralement** les `game_case_text_*` depuis `decompiler_out/jak1/assets/game_text.txt`
(ses lignes 309-318 : `json.dump(dict(sorted(d.items())))`, le dict entier). Une correction de ton ecrite
la serait **effacee** au prochain passage de cette phase — c'est le mode d'echec que les
DIRECTIVES nomment (« quand une perte se repete, on la rend impossible au point de
production, pas detectable au point de controle »), deja paye deux fois sur
`physics_chains.txt`.
Les `game_custom_text_*` sont, eux, convertis **SUR PLACE** (lignes 320-340 : le script lit
le dict, n'en change que la CASSE, et le reecrit) : les cles et la formulation survivent.
`game/assets/jak1/game_text.gp` charge `custom` APRES `case`, et `text_ser.cpp` fait
`bank->set_line(id, ...)` : le dernier fichier gagne. Le ton est donc effectif ET durable.

GARANTIE DE NON-DESTRUCTION, MESUREE
------------------------------------
`--check-fixpoint` passe chaque formulation dans le `Caser` de `gen_mixed_case.py` et exige
qu'elle soit un POINT FIXE. Si elle l'est, relancer la phase de casse ne peut changer ni la
casse ni la formulation.

IDEMPOTENCE
-----------
Chaque entree porte [AVANT_ATTENDU, APRES]. Le script n'ecrit que si la valeur EFFECTIVE
courante est l'un des deux. Toute autre valeur = un tiers a modifie la chaine -> ARRET, avec
la valeur trouvee. On ne recouvre jamais en silence le travail d'un autre ecrivain.
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
TEXTDIR = os.path.join(ROOT, "game", "assets", "jak1", "text")
GP = os.path.join(ROOT, "game", "assets", "jak1", "game_text.gp")
DECOMP = os.path.join(ROOT, "decompiler_out", "jak1", "assets", "game_text.txt")
TABLE = os.path.join(ROOT, ".autoport", "gtext_tone_table.json")
LANG_ID = {"en-US": 0, "fr-FR": 1, "de-DE": 2, "es-ES": 3, "it-IT": 4, "ja-JP": 5, "en-GB": 6}


# ---------------------------------------------------------------------------------------
# Resolution de la valeur EFFECTIVE d'un id : decomp -> case -> custom, dans l'ordre du .gp
# ---------------------------------------------------------------------------------------
def gp_files(lang):
    """Les json listes pour cette langue dans game_text.gp, DANS L'ORDRE."""
    src = open(GP, encoding="utf-8").read()
    for lid, files in re.findall(r"\(file-json\s+(\d+)\s+\S+\s+\"common\"\s+'\((.*?)\)\)", src, re.S):
        if int(lid) == LANG_ID[lang]:
            return re.findall(r'"([^"]+)"', files)
    return []


def decomp_bank(lang):
    """Le banc de base extrait de l'ISO — seules les langues 0..6 y figurent."""
    out = {}
    if LANG_ID[lang] > 6 or not os.path.exists(DECOMP):
        return out
    src = open(DECOMP, encoding="utf-8").read()
    for hid, body in re.findall(r"\(#x([0-9a-fA-F]{4})\n(.*?)\n  \)", src, re.S):
        lines = re.findall(r'^\s*"(.*)"\s*$', body, re.M)
        if LANG_ID[lang] < len(lines):
            out[hid.lower().lstrip("0") or "0"] = lines[LANG_ID[lang]]
    return out


def effective(lang):
    """(valeur, fichier_gagnant) par id, apres application de toute la chaine."""
    res = {k: (v, "decomp/game_text.txt") for k, v in decomp_bank(lang).items()}
    for rel in gp_files(lang):
        d = json.load(open(os.path.join(ROOT, rel), encoding="utf-8"))
        for k, v in d.items():
            if isinstance(v, str):
                res[k.lower().lstrip("0") or "0"] = (v, os.path.basename(rel))
    return res


# ---------------------------------------------------------------------------------------
# Largeur RENDUE : les balises <PAD_*> sont UN glyphe, `_` est une espace large (\x03), et
# `~D` / `~Y` / `~33L` sont des substitutions faites a l'execution (jamais dessinees telles
# quelles). Compter les octets serait faux sur les trois.
# ---------------------------------------------------------------------------------------
def glyphs(s):
    s = re.sub(r"<[A-Z_]+>", "@", s)            # une balise de touche = un glyphe
    s = re.sub(r"~\+?\d*[A-Za-z]", "", s)       # ~D ~Y ~33L ~+26H : substitue a l'execution
    return len(s)


def load_table():
    t = json.load(open(TABLE, encoding="utf-8"))
    t.pop("_comment", None)
    return t


def check_fixpoint(table):
    """Chaque formulation doit etre un POINT FIXE du convertisseur de casse."""
    import importlib.util
    p = os.path.join(ROOT, "recharged_assets", "font", "gen_mixed_case.py")
    if not os.path.exists(p):
        print("[tone] gen_mixed_case.py absent — controle de point fixe IMPOSSIBLE")
        return None
    spec = importlib.util.spec_from_file_location("gmc", p)
    m = importlib.util.module_from_spec(spec)
    argv, sys.argv = sys.argv, ["gen_mixed_case", "--dry-run"]
    try:
        spec.loader.exec_module(m)
    except SystemExit:
        pass
    finally:
        sys.argv = argv
    C = m.Caser(json.load(open(m.RULES, encoding="utf-8")))
    tot = bad = 0
    for scope, tbl in table.items():
        subs = {scope: tbl} if scope != "android" else tbl
        for lang, sub in subs.items():
            for ident, (_before, after) in sub.items():
                tot += 1
                if C.run(after, lang, "label") != after:
                    bad += 1
                    print("[tone] NON-POINT-FIXE %s #x%s : %r" % (lang, ident, after))
    print("[tone] point fixe du convertisseur de casse : %d/%d" % (tot - bad, tot))
    return bad == 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--check-fixpoint", action="store_true")
    ap.add_argument("--audit", default=None, help="ecrire l'audit AVANT/APRES dans ce fichier")
    a = ap.parse_args()

    table = load_table()
    if a.check_fixpoint and check_fixpoint(table) is False:
        sys.exit("[tone] FATAL : une formulation n'est pas un point fixe de la casse")

    audit, drift = [], []
    counters = {"wrote": 0, "skipped": 0}

    def apply_to(path, lang, sub, scope):
        d = json.load(open(path, encoding="utf-8"))
        eff = effective(lang) if scope == "desktop" else None
        changed = False
        for ident, (before, after) in sorted(sub.items(), key=lambda kv: int(kv[0], 16)):
            if scope == "desktop":
                cur, src = eff.get(ident, ("<ABSENT>", "-"))
            else:
                cur, src = d.get(ident, "<ABSENT>"), os.path.basename(path)
            if cur == after:
                counters["skipped"] += 1
            elif cur == before:
                d[ident] = after
                changed = True
                counters["wrote"] += 1
            else:
                drift.append((scope, lang, ident, cur))
                continue
            audit.append((scope, lang, ident, src, before, after, glyphs(before), glyphs(after)))
        # ORDRE PRESERVE : `gen_mixed_case.py` reecrit ces memes fichiers en conservant
        # l'ordre d'insertion. Trier ici ferait osciller l'ordre entre les deux ecrivains a
        # chaque passage et noierait la revue sous un diff de plusieurs centaines de lignes.
        # Les cles existantes sont mises a jour EN PLACE, les nouvelles ajoutees a la fin.
        if changed and not a.dry_run:
            with open(path, "w", encoding="utf-8") as f:
                json.dump(d, f, ensure_ascii=False, indent=2)
                f.write("\n")

    for scope, sub in table.items():
        if scope == "android":
            for lang, s2 in sub.items():
                apply_to(os.path.join(TEXTDIR, "game_custom_text_android_%s.json" % lang),
                         lang, s2, "android")
        else:
            apply_to(os.path.join(TEXTDIR, "game_custom_text_%s.json" % scope), scope, sub, "desktop")

    if drift:
        for scope, lang, ident, cur in drift:
            print("[tone] DERIVE %s %s #x%s : valeur courante inattendue -> %r" % (scope, lang, ident, cur))
        sys.exit("[tone] FATAL : %d chaine(s) modifiee(s) par un tiers — refus d'ecraser" % len(drift))

    lines = ["# Gtext-tone — audit AVANT -> APRES (glyphes RENDUS, pas octets)", ""]
    for scope in ("desktop", "android"):
        for lang in sorted({r[1] for r in audit if r[0] == scope}):
            rows = sorted([r for r in audit if r[0] == scope and r[1] == lang],
                          key=lambda r: int(r[2], 16))
            tb = sum(r[6] for r in rows)
            ta = sum(r[7] for r in rows)
            lines.append("## %-7s %-6s : %d chaines, %d -> %d glyphes (%+d)"
                         % (scope, lang, len(rows), tb, ta, ta - tb))
            for _s, _l, ident, src, before, after, gb, ga in rows:
                lines.append("  #x%-5s [%-27s] %3d -> %3d glyphes (%+d)%s"
                             % (ident, src, gb, ga, ga - gb, "   <-- PLUS LARGE" if ga > gb else ""))
                lines.append("     AVANT : %s" % before)
                lines.append("     APRES : %s" % after)
            lines.append("")
    out = "\n".join(lines)
    print(out)
    print("[tone] ecrites=%d deja-a-jour=%d%s"
          % (counters["wrote"], counters["skipped"], "  (DRY-RUN)" if a.dry_run else ""))
    if a.audit:
        os.makedirs(os.path.dirname(a.audit), exist_ok=True)
        open(a.audit, "w", encoding="utf-8").write(out + "\n")
        print("[tone] audit -> %s" % a.audit)


if __name__ == "__main__":
    main()
