DIRECTIVES v775512c234
# Lecteur identité primitive GPU v2

Commande (les dimensions et render_frame se lisent dans color.meta) :

    python3 notes/attempt10-analyze.py ARCHIVE --proof PROOF --depth ARCHIVE/scene-depth.f32 --width 800 --height 600 --frame 1400 --roi 60,540,60,30 --output roi-gpu.json

`format=ao-hut-color-f32-v2` exige `identity_r=primitive-id-plus-one`.
R-1 est l'ordinal de primitive, A le probe_id de draw. B doit correspondre
à la profondeur scène au même quantum D24. Le lecteur n'utilise PAS la
projection CPU pour décider de l'identité v2.

Chaque ligne draws.txt est une soumission et remet l'ordinal à zéro.
Un restart remet l'assemblage/parité du strip à zéro, mais conserve le compteur.
Les triangles dégénérés consomment un ordinal et ne peuvent fournir un fragment.
Les offsets source archivés identifient le draw originel, les sommets originaux
et effectifs, puis les prototypes/matrices/groupes ; aucune identité n'est
déduite d'un indice soudé.

`gpu-unique` : une source de primitive possible, sans soumission inconnue.
`gpu-ambiguous` : plusieurs primitives sources pour le même probe_id/ordinal.
`unresolved-submission` : une soumission pourrait contribuer sans état exploitable.
`missing` : aucune primitive source correspondante.
Les positions monde sont qualifiées séparément via
`static_world_positions_qualified` ; une source GPU peut être identifiée
sans que ses positions déformées soient connues.

Le format v1 reste le diagnostic projection/D24 historique ; il ne devient
jamais une identité GPU par changement du lecteur.
Les tests synthétiques couvrent projection, clipping, D24, strip/restart,
dégénérés, compteur nouveau draw, contact absent/nonzero/corrompu, archive
complète v1/v2 et ambiguïté entre soumissions. Trace : attempt10-test-analyze.log.
Le lecteur ne publie aucun défaut global, aucun label mur/toit et aucun proof.txt.
