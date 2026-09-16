DIRECTIVES v775512c234
# Essai13 — commandes exactes, depuis /home/emeric/code/jak-project
N=.autoport/reports/ao-prepass-tie-alpha/notes
PY=/home/emeric/.venv/autoport/bin/python3

# compile/link bureau
$N/attempt11-desktop-compile game/graphics/opengl_renderer/shaders/ao_blur.vert \
    $N/attempt11-reference.frag $N/attempt13-<candidat>.frag
# rejeu 36 sorties x 3 modes
$PY $N/attempt11-replay.py --shader $N/attempt13-<candidat>.frag --output $N/attempt11-a13-<tag>
# profils 425 px / 15 contacts
$PY $N/attempt12-analyze.py --replay $N/attempt11-a13-<tag> \
    --output $N/attempt12-a13-<tag>-diagnostic.json
# 16 temoins plans/ciel/silhouette
$PY $N/attempt11-run-invariants.py --shader $N/attempt13-<candidat>.frag \
    --output $N/attempt11-a13-<tag>-inv
# phases au pli
$N/attempt12-fold-phases $N/attempt11-a13-<tag>/vertex.glsl \
    $N/attempt11-a12-delivery-invariants/reference.glsl $N/attempt11-a13-<tag>/fragment.glsl
# flat_step (reimplementation fidele de AmbientOcclusion.cpp:1153) : notes/attempt13-flatstep.py
