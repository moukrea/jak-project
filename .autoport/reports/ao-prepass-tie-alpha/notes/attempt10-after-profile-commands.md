DIRECTIVES v775512c234
# Commandes après correctif — mêmes patches et population

Pour chacun des trois modes capturés au tick600, remplacer ARCHIVE, PROOF et
RESULTDIR par les chemins de cette course autorisée, sans relancer le dispositif :

    python3 .autoport/reports/ao-prepass-tie-alpha/notes/attempt10-analyze.py ARCHIVE --proof PROOF --depth ARCHIVE/scene-depth.f32 --width 800 --height 600 --frame 600 --roi 60,540,120,40 --output RESULTDIR/roi-gpu.json
    python3 .autoport/reports/ao-prepass-tie-alpha/notes/attempt10-profile.py ARCHIVE --attribution RESULTDIR/roi-gpu.json --qualification .autoport/reports/ao-prepass-tie-alpha/notes/attempt10-contact-patches.json --native .autoport/reports/ao-prepass-tie-alpha/notes/attempt10-profile-native --reference-profile .autoport/reports/ao-prepass-tie-alpha/notes/attempt10-03-gtao-before/contact-profiles.json --output RESULTDIR/contact-profiles.json

La référence fige425 pixels (250 mur,175 toit),15 arêtes physiquement qualifiées,
les mêmes sources TFRAG et la même projection de leur intersection.
Une population différente est une erreur explicite ; on ne remplace pas la paire
par une surface plus favorable et on n'élargit aucun masque.
Le lecteur natif peut conserver un côté non mesuré : avant,29 côtés valides et1
manquant. La présence de ce manque doit rester nommée, même si la bande devient0.

Comparer les stages bruts/H/V/ridge À L'INTÉRIEUR de chaque archive.
GTAO avant/après au tick600 partage le mode ; vérifier également les entrées.
SSAO avant est au tick1400 et HBAO avant n'a pas d'archive : les comparaisons
causales correspondantes restent non prouvées. Le simple nom de scène ne rend
ni les ticks ni les modes ni leurs entrées équivalents.
