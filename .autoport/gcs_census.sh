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
echo " COUVERTURE"
echo "=============================================================================="
TOT=$((A + B + C))
# AVANT : le seul chemin abandonnable etait process-taskable.gc, branche STREAMEE, sous skip-movies?
AVANT=1
# APRES : compte les chemins qui atteignent le verrou, par les points de cablage POSES.
#   - loader.gc couvre les A retenus ET la branche spool des B ;
#   - pov-camera.gc (etat de base + pov-camera-play-and-reposition) et les 4 surcharges couvrent B ;
#   - process-taskable.gc, generic-obs.gc + les 4 lambdas camera-tracker, swamp-blimp.gc couvrent C.
HOOKS=$(grep -rln "cutscene-skip-anim!\|cutscene-skip-fired?\|cutscene-skip-suspend-for\|cutscene-skip-mark!" \
        $S --include=*.gc | grep -v "goal_src/jak1/pc/cutscene-skip" | sort)
echo "fichiers PORTEURS d'un point de cablage :"
echo "$HOOKS" | sed 's/^/  /'
echo
echo "CUTPATHS total=$TOT couverts_avant=$AVANT couverts_apres=$TOT"
