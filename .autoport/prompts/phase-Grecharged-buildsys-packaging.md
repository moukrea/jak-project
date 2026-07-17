## READ FIRST: .autoport/plans/build-system-pillar.md. P2 of the owner's build-system pillar.
# Phase Grecharged-buildsys-packaging — package vs assets.zip split, the owner's rule
Owner (verbatim): "Le package du jeu (APK pour Android, whatever it is pour Linux et Windows) avec les
assets qui n'ont pas été altérés de la source fournie (le jeu PS2) dans une archive séparée genre
assets.zip qui ne contient VRAIMENT QUE ce qui n'est pas modifié par le port. Ces derniers ne doivent
absolument pas être inclus dans le package. Par contre tous les trucs custom (assets custom, modèles HD
de Jak 2 dans Jak 1, etc.) eux SONT dans le package."
Rule of thumb (from the plan): an artifact goes to assets.zip iff a diff against the vanilla OpenGOAL
pipeline output for the same source game is EMPTY; anything port-modified/custom -> package. Notably:
compiled CGO/DGO -> package (already); rebuilt TXT banks with custom ids -> PACKAGE (they differ from
vanilla); enhanced HD fr3 overlays + recharged PNGs -> PACKAGE (move out of the archive); stock fr3 +
iso_data (STR/VAG/VIS/SBK/MUS/VAGWAD all langs) -> assets.zip.
Deliverables: producers rewritten per game+target (jak1 now, jak2/jak3 auto when sources present);
outputs <pkg per target> + jakN_assets.zip; release_verify/deploy_verify re-keyed (content+flags);
Android loader reads custom set from APK, data set from archive tree. Proofs: content manifests of both
artifacts reviewed against the rule (zero misplaced file), device boot from the new pair.
Max: max_turns 3000, max_retries 6.
