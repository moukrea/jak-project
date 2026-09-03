#!/usr/bin/env bash
# Gcutscene-skip-all — LE RECENSEMENT, produit par une COMMANDE et pas par de la prose.
# Premier livrable exige par le contrat de phase : tous les chemins de cinematique du jeu, avec
# pour chacun s'il passe ou non par le geste de saut.
#
# Trois familles, et la definition de chacune est ecrite ici pour etre relisible :
#   A. les appels a `ja-play-spooled-anim` (engine/load/loader.gc) = les scenes STREAMEES.
#      C'est le seul lecteur de spool du jeu : `str-play-async` n'est appele que dans son corps.
#   B. les creations de `pov-camera` (et de ses 5 types derives) = les cinematiques CONTEXTUELLES,
#      celles de Geyser Rock comprises.
#   C. le reste : la branche NON streamee de `process-taskable`, les `camera-tracker`, et la
#      sequence du rocher d'amarrage de Swamp.
#
# EXCLUSIONS, chacune avec sa raison MESURABLE (elles sont imprimees, jamais tues) :
#   - engine/target/target2.gc  : anim STREAMEE d'oisiveté de Jak, jouee pendant que le joueur a le
#     controle total ; son predicat d'abandon d'origine lit le STICK. Ce n'est pas une cinematique.
#   - levels/title/title-obs.gc, la 2e branche d'un `#cond` sur PC_PORT : non compilee sur ce port.
#   - beach/pelican.gc et village1/fishermans-boat.gc (x2), cote `camera-tracker` : leur camera est
#     tenue par un evenement de JEU (`(while (!= ... 'release) (suspend))`), pas par une horloge
#     d'auteur -- la barque doit arriver au ponton, le pelican doit livrer. Y couper la camera
#     changerait le jeu au lieu de sauter une scene. Ils ne posent donc pas la marque, et l'indice
#     ne s'y affiche pas : la promesse et le cablage sont la meme grandeur.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
S=goal_src/jak1

echo "=============================================================================="
echo " A. SCENES STREAMEES — appels a ja-play-spooled-anim"
echo "=============================================================================="
grep -rn "(ja-play-spooled-anim" $S --include=*.gc | grep -v "defbehavior ja-play-spooled-anim" \
  | sed 's/^\([^:]*:[0-9]*\).*/\1/' | sort > /tmp/gcs_A.txt
A_TOT=$(wc -l < /tmp/gcs_A.txt)
cat /tmp/gcs_A.txt
echo "  A_brut=$A_TOT"
A_EXCL=$(grep -c "engine/target/target2.gc\|levels/title/title-obs.gc:505" /tmp/gcs_A.txt || true)
A_POV=$(grep -c "engine/camera/pov-camera.gc" /tmp/gcs_A.txt || true)
echo "  - exclus (oisiveté du joueur, branche non compilee) : $A_EXCL"
echo "  - deja comptes dans B (lecture spool d'un pov-camera) : $A_POV"
A=$((A_TOT - A_EXCL - A_POV))
echo "  A_retenu=$A"

echo
echo "=============================================================================="
echo " B. CINEMATIQUES CONTEXTUELLES — creations de pov-camera et de ses types derives"
echo "=============================================================================="
# Un site de creation, c'est soit un `(process-spawn <type>)` -- qui appelle implicitement
# `pov-camera-init-by-other` --, soit un appel EXPLICITE a `pov-camera-init-by-other`
# (`run-now-in-process`, ou `process-spawn ... :init ...`). Un `:init` qui suit immediatement un
# `process-spawn` est la MEME forme et ne compte qu'une fois.
python3 - > /tmp/gcs_B.txt <<'PYEOF'
import re, os
S="goal_src/jak1"
TYPES=["pov-camera","snowcam","maincavecam","sunkencam","village2cam","precurbridgecam"]
pat_spawn = re.compile(r"\(process-spawn\s+(" + "|".join(TYPES) + r")\b")
pat_init  = re.compile(r"\bpov-camera-init-by-other\b")
sites=[]
for root,_,files in os.walk(S):
    for f in sorted(files):
        if not f.endswith(".gc"): continue
        p=os.path.join(root,f); t=open(p,encoding="utf-8").read()
        occ=[(m.start(),"spawn") for m in pat_spawn.finditer(t)]
        if not (p.endswith("engine/camera/pov-camera.gc") or p.endswith("pov-camera-h.gc")):
            occ += [(m.start(),"init") for m in pat_init.finditer(t)]
        occ.sort(); prev=None
        for o,kind in occ:
            if kind=="init" and prev and prev[1]=="spawn" and o-prev[0]<400:
                prev=(o,kind); continue
            sites.append((p, t[:o].count("\n")+1)); prev=(o,kind)
for p,l in sorted(sites): print(f"{p}:{l}")
PYEOF
B=$(wc -l < /tmp/gcs_B.txt)
cat /tmp/gcs_B.txt
echo "  B=$B    (dont Geyser Rock : $(grep -c "levels/training/" /tmp/gcs_B.txt || true))"
echo
echo "=============================================================================="
echo " C. LES AUTRES CHEMINS"
echo "=============================================================================="
grep -rn "process-spawn camera-tracker" $S --include=*.gc | sed 's/^\([^:]*:[0-9]*\).*/\1/' | sort > /tmp/gcs_C.txt
CT=$(wc -l < /tmp/gcs_C.txt)
cat /tmp/gcs_C.txt
CT_EXCL=$(grep -c "levels/beach/pelican.gc\|levels/village1/fishermans-boat.gc" /tmp/gcs_C.txt || true)
echo "  camera-tracker brut=$CT  dont EXCLUS (camera tenue par le jeu, pas par une horloge)=$CT_EXCL"
echo "$S/engine/common-obs/process-taskable.gc  (branche NON streamee de process-taskable-play-anim-code)"
echo "$S/levels/village2/swamp-blimp.gc         (swamp-tetherrock-break)"
C=$((CT - CT_EXCL + 2))
echo "  C_retenu=$C"


echo
echo "=============================================================================="
echo " COUVERTURE — DERIVEE SITE PAR SITE, PLUS ASSERTEE"
echo "=============================================================================="
# Gcutscene-skip-polish : `couverts_apres` valait litteralement `$TOT` -- une tautologie, la porte
# ne pouvait donc pas tomber si un point de cablage disparaissait. Or ce cycle RETIRE du code
# (le saut natif par TRIANGLE), donc c'est exactement le cycle ou cette garde doit mordre.
# Desormais chaque site est ASSOCIE au fichier qui porte le MECANISME par lequel il serait saute,
# et il n'est compte couvert que si ce fichier contient reellement un appel de cablage.
python3 - <<'PYEOF'
import re, os
S = "goal_src/jak1"
HOOK = re.compile(r"cutscene-skip-(anim!|fired\?|suspend-for|mark!|abort!)")
cache = {}
# CONTROLE POSITIF DE L'INSTRUMENT, opt-in : `GCS_CENSUS_ABLATE=<chemin>` fait comme si ce fichier
# avait perdu son point de cablage. Le compte DOIT alors chuter. Sans ce levier, « couverts=total »
# ne serait qu'une affirmation de plus -- c'est exactement le defaut qu'on corrige ici.
ABLATE = os.environ.get("GCS_CENSUS_ABLATE", "")
def has_hook(p):
    if ABLATE and ABLATE in p:
        return False
    if p not in cache:
        try:
            cache[p] = bool(HOOK.search(open(p, encoding="utf-8").read()))
        except OSError:
            cache[p] = False
    return cache[p]

def load(p):
    return [l.strip() for l in open(p) if l.strip()]

def srcline(site):
    f, n = site.rsplit(":", 1)
    try:
        return open(f, encoding="utf-8").read().splitlines()[int(n) - 1]
    except Exception:
        return ""

LOADER   = f"{S}/engine/load/loader.gc"
POVBASE  = f"{S}/engine/camera/pov-camera.gc"
GENERIC  = f"{S}/engine/common-obs/generic-obs.gc"
TASKABLE = f"{S}/engine/common-obs/process-taskable.gc"
BLIMP    = f"{S}/levels/village2/swamp-blimp.gc"

# Un `pov-camera` derive joue son animation dans SA PROPRE surcharge de `pov-camera-playing` :
# les surcharges n'heritent ni du `:event` ni du `:post` du type de base, donc le cablage doit
# vivre dans le fichier de la surcharge. `maincavecam` ne lit qu'un spool -> loader.gc.
MECH = {
    "pov-camera":      POVBASE,
    "snowcam":         f"{S}/levels/snow/snow-obs.gc",
    "sunkencam":       f"{S}/levels/sunken/sunken-obs.gc",
    "village2cam":     f"{S}/levels/village2/village2-obs.gc",
    "precurbridgecam": f"{S}/levels/jungle/jungle-obs.gc",
    "maincavecam":     LOADER,
}

EXCL_A = ("engine/target/target2.gc", "levels/title/title-obs.gc:505")
EXCL_C = ("levels/beach/pelican.gc", "levels/village1/fishermans-boat.gc")

rows = []   # (famille, site, mecanisme, couvert)

for s in load("/tmp/gcs_A.txt"):
    if any(e in s for e in EXCL_A):          # exclusions publiees, jamais tues
        continue
    if "engine/camera/pov-camera.gc" in s:   # deja compte dans B
        continue
    rows.append(("A", s, LOADER, has_hook(LOADER)))

for s in load("/tmp/gcs_B.txt"):
    m = re.search(r"\(process-spawn\s+([a-z0-9-]+)", srcline(s))
    typ = m.group(1) if m else "pov-camera"
    mech = MECH.get(typ, POVBASE)
    rows.append(("B:" + typ, s, mech, has_hook(mech)))

for s in load("/tmp/gcs_C.txt"):
    if any(e in s for e in EXCL_C):
        continue
    own = s.rsplit(":", 1)[0]
    # un `camera-tracker` a horloge d'auteur est saute soit par sa propre lambda, soit par
    # l'interprete de script partage de generic-obs.gc.
    mech = own if has_hook(own) else GENERIC
    rows.append(("C:tracker", s, mech, has_hook(mech)))
rows.append(("C:taskable", TASKABLE + "  (branche NON streamee)", TASKABLE, has_hook(TASKABLE)))
rows.append(("C:tetherrock", BLIMP + "  (swamp-tetherrock-break)", BLIMP, has_hook(BLIMP)))

w = max(len(r[1]) for r in rows)
for fam, site, mech, ok in rows:
    print(f"  {'OUI' if ok else 'NON':3}  {fam:16} {site:<{w}}  <- {mech}")

tot = len(rows)
cov = sum(1 for r in rows if r[3])
mechs = sorted({r[2] for r in rows})
print()
print("fichiers PORTEURS d'un point de cablage, et nombre de sites qui en DEPENDENT :")
for m in mechs:
    n = sum(1 for r in rows if r[2] == m)
    print(f"  {'OUI' if has_hook(m) else 'NON':3}  {n:3} sites  {m}")
print()
# AVANT : le seul chemin abandonnable du jeu livre etait process-taskable.gc, branche STREAMEE,
# sous `skip-movies?`, par TRIANGLE -- et ce chemin est RETIRE par ce cycle (demande owner
# 2026-09-01). `couverts_avant` decrit donc l'etat d'ORIGINE, avant le cycle 1.
print(f"CUTPATHS total={tot} couverts_avant=1 couverts_apres={cov}")
PYEOF
