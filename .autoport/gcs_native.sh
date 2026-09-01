#!/usr/bin/env bash
# Gcutscene-skip-polish — LE RECENSEMENT DU SAUT INSTANTANE, produit par une COMMANDE.
#
# Demande owner du 2026-09-01 : « faut aussi que tu désactive (retire) le skip de OpenGoal parce
# que ça collide un peu, si j'appuies sur triangle dans une cinématique ça l'instant skip
# (comportement de OpenGoal), c'est un peu wacky ».
#
# DEFINITION DU COMPTEUR, ecrite ici pour etre relisible et discutable :
#   un SITE DE SAUT INSTANTANE est un endroit qui, DANS LE BUILD LIVRE ET AUX REGLAGES PAR DEFAUT,
#   abandonne ou precipite une CINEMATIQUE DE JEU sur un APPUI SIMPLE.
# Trois familles sont cherchees, chacune par son motif :
#   N1. un predicat d'abandon passe en 4e argument de `ja-play-spooled-anim` qui LIT LE PAD ;
#   N2. un `(get-response (-> ... query)) 'no` -- `get-response` n'est pas un accesseur, il SONDE
#       TRIANGLE (process-taskable.gc:93) -- hors garde `*debug-segment*` ;
#   N3. une lecture de TRIANGLE dans le chemin d'abandon de `pov-camera`.
#
# CE QUI EST EXCLU, ET C'EST PUBLIE, JAMAIS TU (chaque exclusion porte sa garde) :
#   - `levels/title/title-obs.gc` : le survol du logo ND, saute par START/CERCLE/CROIX. Ce n'est
#     pas une cinematique de JEU, c'est l'amorcage, et c'est un ACQUIS d'une phase anterieure
#     (l'owner a demande de pouvoir passer le logo). Le retirer serait une regression.
#   - `levels/finalboss/sage-finalboss.gc` : le GENERIQUE de fin, saute par TRIANGLE mais SOUS
#     `(or *cheat-mode* (-> *pc-settings* speedrunner-mode?))`, tous deux #f par defaut.
#   - `engine/common-obs/process-taskable.gc` sous `*debug-segment*` : ce symbole vaut #f dans tout
#     build livre (kmachine.cpp met DebugSegment a 0 sur `-boot` comme sur `-debug-mem`, et
#     kscheme.cpp ecrit alors le symbole a #f).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
RUNLOG="${1:-.autoport/reports/Gcutscene-skip-all/x86-run.log}"

python3 - "$RUNLOG" <<'PYEOF'
import re, subprocess, sys, os

S = "goal_src/jak1"
RUNLOG = sys.argv[1]

EXCLUS = [
    ("levels/title/title-obs.gc", "survol du logo ND (START/CERCLE/CROIX) — amorcage, pas une cinematique de jeu, ACQUIS d'une phase anterieure"),
    ("levels/finalboss/sage-finalboss.gc", "generique de fin, garde par (or *cheat-mode* speedrunner-mode?) — les deux #f par defaut"),
]

def strip_comments(t):
    """Blanchir les commentaires GOAL en gardant les NUMEROS DE LIGNE et les chaines.
    Sans ca, le recensement se compte lui-meme : un commentaire qui CITE le motif retire
    ressemble au motif. C'est arrive a la premiere course, et c'est le genre de faux rouge qui
    coute un cycle."""
    out = []
    i = 0
    n = len(t)
    while i < n:
        c = t[i]
        if c == '"':
            out.append(c); i += 1
            while i < n and t[i] != '"':
                if t[i] == "\\":
                    out.append(t[i]); i += 1
                    if i < n: out.append(t[i]); i += 1
                    continue
                out.append(t[i]); i += 1
            if i < n: out.append(t[i]); i += 1
        elif c == ";":
            while i < n and t[i] != "\n":
                out.append(" "); i += 1
        else:
            out.append(c); i += 1
    return "".join(out)

def read(path, rev):
    if rev is None:
        try:
            raw = open(path, encoding="utf-8").read()
        except OSError:
            return ""
    else:
        r = subprocess.run(["git", "show", f"{rev}:{path}"], capture_output=True, text=True)
        raw = r.stdout if r.returncode == 0 else ""
    return strip_comments(raw)

def files(rev):
    if rev is None:
        out = []
        for root, _, fs in os.walk(S):
            for f in sorted(fs):
                if f.endswith(".gc"):
                    out.append(os.path.join(root, f))
        return sorted(out)
    r = subprocess.run(["git", "ls-tree", "-r", "--name-only", rev, S], capture_output=True, text=True)
    return sorted(p for p in r.stdout.split() if p.endswith(".gc"))

def sexp_end(t, i):
    d = 0
    while i < len(t):
        c = t[i]
        if c == '"':
            i += 1
            while i < len(t) and t[i] != '"':
                if t[i] == "\\": i += 1
                i += 1
        elif c == ";":
            while i < len(t) and t[i] != "\n": i += 1
            continue
        elif c == "(":
            d += 1
        elif c == ")":
            d -= 1
            if d == 0: return i + 1
        i += 1
    return len(t)

def args_of(call):
    """arguments de tete d'un appel, comme chaines"""
    i = call.find("(") + 1
    while i < len(call) and call[i] not in " \t\n": i += 1
    out = []
    while i < len(call) - 1:
        while i < len(call) - 1 and call[i] in " \t\n": i += 1
        if i >= len(call) - 1: break
        if call[i] == "(":
            j = sexp_end(call, i)
        elif call[i] == '"':
            j = i + 1
            while j < len(call) and call[j] != '"': j += 1
            j += 1
        else:
            j = i
            while j < len(call) and call[j] not in " \t\n()": j += 1
        out.append(call[i:j]); i = j
    return out

def census(rev):
    sites = []
    for p in files(rev):
        t = read(p, rev)
        if not t: continue
        excl = any(e in p for e, _ in EXCLUS)
        # --- N1 : 4e argument de ja-play-spooled-anim qui lit le pad
        for m in re.finditer(r"\(ja-play-spooled-anim\b", t):
            call = t[m.start():sexp_end(t, m.start())]
            a = args_of(call)
            if len(a) < 4: continue
            pred = a[3]
            ln = t[:m.start()].count("\n") + 1
            if "false-func" in pred: continue
            if "stick0-speed" in pred:          # anim d'oisiveté du JOUEUR, pas une cinematique
                continue
            if "check-for-abort" in pred:
                # vivant seulement si `check-for-abort` lit encore le pad
                pov = read(f"{S}/engine/camera/pov-camera.gc", rev)
                mm = re.search(r"\(defmethod check-for-abort\b", pov)
                body = pov[mm.start():sexp_end(pov, mm.start())] if mm else ""
                if "triangle" not in body: continue
                sites.append((p, ln, "N1/pov", "check-for-abort lit TRIANGLE"))
                continue
            if "get-response" in pred:
                sites.append((p, ln, "N1/taskable", "predicat = (get-response ...) 'no"))
                continue
            sites.append((p, ln, "N1/autre", pred[:60].replace("\n", " ")))
        # --- N2 : (get-response ...) 'no hors garde *debug-segment*
        for m in re.finditer(r"\(get-response\b", t):
            ln = t[:m.start()].count("\n") + 1
            # fenetre englobante : la ligne + les 2 precedentes
            lines = t.split("\n")
            ctx = "\n".join(lines[max(0, ln - 3):ln + 1])
            if "'no" not in ctx: continue
            if "*debug-segment*" in ctx: continue
            if excl: continue
            # deja compte par N1 ?
            if any(s[0] == p and abs(s[1] - ln) < 12 and s[2].startswith("N1") for s in sites): continue
            sites.append((p, ln, "N2/exit", "rattrapage d'etat qui RESONDE le pad"))
        # --- N3 : TRIANGLE dans le chemin d'abandon de pov-camera
        if p.endswith("engine/camera/pov-camera.gc"):
            mm = re.search(r"\(defmethod check-for-abort\b", t)
            if mm:
                body = t[mm.start():sexp_end(t, mm.start())]
                if "triangle" in body:
                    sites.append((p, t[:mm.start()].count("\n") + 1, "N3/pov", "check-for-abort consomme TRIANGLE"))
    return sites

def show(title, sites):
    print(f"--- {title} : {len(sites)} site(s)")
    for p, ln, fam, why in sorted(sites):
        print(f"    {fam:12} {p}:{ln}  {why}")

av = census("HEAD")
ap = census(None)
print("=" * 78)
print(" RECENSEMENT DU SAUT INSTANTANE — AVANT (HEAD) et APRES (arbre de travail)")
print("=" * 78)
show("AVANT (HEAD)", av)
show("APRES (arbre de travail)", ap)
print()
print("EXCLUS, avec leur garde :")
for p, why in EXCLUS:
    print(f"    {p} — {why}")
print(f"    {S}/engine/common-obs/process-taskable.gc — saut de debug de ND, garde par *debug-segment* (#f dans tout build livre)")
print()

natif = None
try:
    for line in open(RUNLOG, encoding="utf-8", errors="replace"):
        m = re.search(r"^CUTFIN .*natif=(\d+)", line)
        if m: natif = int(m.group(1))
except OSError:
    pass
if natif is None:
    print(f"!! pas de ligne CUTFIN dans {RUNLOG} : la jambe D'EXECUTION manque, le verdict reste OUVERT")
    tri = 1 if ap else 1
else:
    print(f"jambe d'EXECUTION, lue dans {RUNLOG} : CUTFIN natif={natif}")
    print("  (`natif` compte les images ou le predicat d'abandon FOURNI PAR L'APPELANT a rendu #t,")
    print("   lu dans le MEME `or` que le verrou du geste — loader.gc:1162, :1189, :1242.)")
    tri = 0 if (not ap and natif == 0) else 1
print()
print(f"CUTNATIVE sites_skip_instantane={len(ap)} touche_triangle_saute={tri} sites_avant={len(av)}")
PYEOF
