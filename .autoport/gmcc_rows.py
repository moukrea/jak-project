#!/usr/bin/env python3
"""Gmenu-census-cleanup — recensement MECANIQUE des rangees du menu Recharged LIVRE.

Ne lit que le corps `#unless FLAG_MENU_OVERHAUL` de progress-pc.gc (la refonte n'est pas
compilee). Pour chaque rangee : son `option-type`, le drapeau de build qui la conditionne
(`flag-row FLAG_X`, sinon inconditionnelle), et sa presence sous un jeu de drapeaux donne.
Sert a VERIFIER l'arithmetique de longueur d'init-game-options au lieu de la compter a la main.
"""
import re, sys

SRC = "goal_src/jak1/pc/progress-pc.gc"
# jeu de drapeaux LIVRE (auto_build_apk.txt: flags='hd-models,pbr,physics')
FLAGS = {
    "FLAG_RECHARGED_HUD": 0, "FLAG_GRASS_OVERHANG": 0, "FLAG_HD_MODELS": 1,
    "FLAG_PBR": 1, "FLAG_PHYSICS": 1, "FLAG_VULKAN_SUPPORT": 0,
    "FLAG_DEBUG_MENUS": 0, "FLAG_PBR_DEBUG": 0, "FLAG_MENU_OVERHAUL": 0,
}
for a in sys.argv[1:]:
    k, v = a.split("=", 1); FLAGS[k] = int(v)

lines = open(SRC, encoding="utf-8").read().split("\n")
ship = next(i for i, l in enumerate(lines) if l.startswith("(#unless FLAG_MENU_OVERHAUL"))

def rows(array_name):
    beg = next(i for i, l in enumerate(lines) if i > ship and l.startswith(f"(define-options-array {array_name}"))
    # fin du tableau = retour a l'equilibre des parentheses depuis sa ligne d'ouverture
    # (les commentaires ;; et le contenu des chaines ne comptent pas). Se fier au prochain
    # (define-options-array marchait pour le premier tableau et debordait sur tout le fichier
    # pour le DERNIER — il n'y en a pas d'autre apres lui.
    depth, end = 0, len(lines)
    for i in range(beg, len(lines)):
        code = re.sub(r'"(\\.|[^"\\])*"', '""', lines[i].split(";")[0])
        depth += code.count("(") - code.count(")")
        if i > beg and depth <= 0:
            end = i + 1; break
    out, gate = [], None
    for i in range(beg, end):
        s = lines[i].strip()
        m = re.match(r"\(flag-row (FLAG_\w+)$", s)
        if m:
            gate = m.group(1); continue
        # DEUX formes d'ecriture dans ce fichier : tout sur une ligne, ou "(new 'static" puis
        # "'game-option" a la ligne suivante (AO QUALITY / AO STRENGTH). Rater la seconde forme
        # sous-compte le tableau de 2 rangees et fait croire a un desaccord de garde-longueur.
        if s.startswith("(new 'static 'game-option") or s == "(new 'static":
            blob = " ".join(x.strip() for x in lines[i:i + 8])
            t = re.search(r"\(game-option-type ([\w-]+)\)", blob)
            out.append((i + 1, t.group(1) if t else "?", gate))
            gate = None
    return out

total_present = 0
for arr in ("*recharged-options-pc*", "*grass-options-pc*"):
    rs = rows(arr)
    present = [r for r in rs if r[2] is None or FLAGS[r[2]] == 1]
    print(f"== {arr} : {len(rs)} rangees ecrites, {len(present)} presentes sous les drapeaux livres")
    for n, (ln, typ, gate) in enumerate(present):
        print(f"  idx={n:<2} ligne={ln:<6} type={typ:<20} gate={gate or '-'}")
    absent = [r for r in rs if r not in present]
    for ln, typ, gate in absent:
        print(f"  ABSENTE  ligne={ln:<6} type={typ:<20} gate={gate}")
    total_present += len(present)
    if arr == "*recharged-options-pc*":
        # La garde de longueur est LUE DANS LA SOURCE, pas recopiee ici : un instrument qui
        # porte sa propre copie de la formule ne peut pas detecter qu'elle est perimee.
        def balanced(txt, i):
            d = 0
            for j in range(i, len(txt)):
                if txt[j] == "(": d += 1
                elif txt[j] == ")":
                    d -= 1
                    if d == 0: return txt[i:j + 1]
            raise ValueError("parentheses non equilibrees")
        gi = next((k for k in range(ship, len(lines))
                   if "(let ((fw-idx (if (= (-> *recharged-options-pc* length)" in lines[k]), None)
        if gi is None:
            print("  !! garde fw-idx introuvable dans la source"); continue
        anchor = lines[gi].index("(+ ", lines[gi].index("length)"))
        gexpr = balanced(lines[gi], anchor)
        fexpr = balanced(lines[gi + 1], lines[gi + 1].index("(+ "))
        class M:
            def group(self, n): return gexpr if n == 1 else fexpr
        m = M()
        def ev(expr):
            e = expr
            for k, v in FLAGS.items():
                e = e.replace(k + "_N", str(v))
            toks = e.replace("(", " ( ").replace(")", " ) ").split()
            def parse(i):
                assert toks[i] == "("
                op = toks[i + 1]; i += 2; args = []
                while toks[i] != ")":
                    if toks[i] == "(":
                        v, i = parse(i)
                    else:
                        v, i = int(toks[i]), i + 1
                    args.append(v)
                r = sum(args) if op == "+" else args[0]
                if op == "*":
                    r = 1
                    for a in args: r *= a
                return r, i + 1
            return parse(0)[0]
        guard, fw = ev(m.group(1)), ev(m.group(2))
        ok = "OK" if guard == len(present) else "DESACCORD"
        print(f"  GARDE-LONGUEUR lue dans la source = {guard} ; rangees presentes = {len(present)} -> {ok}")
        print(f"  fw-idx lu dans la source = {fw}")
        for n, (ln, typ, gate) in enumerate(present):
            if n >= fw:
                print(f"    fw-idx+{n - fw:<3} idx={n:<3} type={typ}")
print(f"TOTAL rangees devant le joueur (2 pages) = {total_present}")
