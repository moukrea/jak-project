DIRECTIVES v8aed688f73

Verdict : défaut de durée de vie du cache corrigé structurellement par les handles ; réutilisation mémoire fortement appuyée par le dump42, mais identité et dernier écrivain du compagnon au crash non prouvés.
Recherche lecture seule des sources/artefacts, puis édition de cette note seule autorisée par le manager. Aucun build/appareil/instrument/validateur touché.

## Trace mémoire existante

Source : ../essai42/menu-off/proof-engine.log, lignes 29084, 29314–29319 et 29426–29437.
La pile contient obj=0x1eb6c4 ; k=20 ; nbones=63 ; nj=62 ; khd-par=0x20c1620.
Le corps ARM64 sauvegardé calcule hd-bp depuis obj+0x15fc=0x1eccc0, puis hd-bp[k]=0x1ece00 ; X6 contient bien 0x1ece00.
Le dump x1-win à 0x1ecc80 révèle une structure process cohérente à 0x1ecc74 (obj+0x15b0), à cheval sur les champs inline hd-bs/hd-bp de l'ancien compagnon.
29426 : x1-win goal=0x1ecc80: 001dceb4 0014fd24 001dccb0 001ecc74
29427 : x1-win goal=0x1ecc90: 001dcb44 001495e4 000000a7 001ecd94
29428 : x1-win goal=0x1ecca0: 001ecd94 0014fd24 01fedb44 0014fd24
29429 : x1-win goal=0x1eccb0: 01feb514 01feb5d4 000003b0 01fedb44
29430 : x1-win goal=0x1eccc0: 001ecd90 001ed090 001ed090 01fedb44
Selon gkernel-h.gc:218–255 : brother+12=0x1dceb4, child+16=#f, ppointer+20=0x1dccb0, self+24=0x1ecc74, pool+28=0x1dcb44, status+32=0x1495e4, pid+36=167, main/top-thread=0x1ecd94, allocated-length=0x3b0, heap-base=0x1ecd90 et heap-top=heap-cur=0x1ed090.
Le symbole 0x1495e4 est identifié comme suspended par la trace29383. Cette cohérence appuie une réutilisation de l'étendue mémoire, au-delà du seul champ hd-mtxarea abîmé ; ce n'est pas une lecture directe du type/PID du vieil obj.
Non capturés : obj-4/type, obj.pid, obj.ppointer et sa cible, parent/pool du vieil obj, cache global au crash, type et ppointer[0] du process0x1ecc74. Aucun déplacement/libération précis attribuable au vieil obj ne peut être daté.
crash.txt conserve seulement les registres ; menu-memory.bin contient 512 octets de *menu-touch*, capturés avant le crash (read-menu.py:25, fichier daté17:24:20.541), pas la mémoire du compagnon.

## Ordre d'appel et invalidation

Ordre source normal : main.gc:1893 draw-hook → drawable.gc:895 matrices/contrôle → drawable.gc:928 actors-update/compaction (entity.gc:1050–1056) → main.gc:2128 update pc-settings → pckernel-common.gc:693 scan → main.gc:2130 suspend.
Pas de garde menu/master-mode autour du scan : main.gc ne conditionne update que par PC_PORT ; pckernel-common.gc:661–694 ne quitte pas update prématurément ; maybe-spawn-jak-hd! collecte avant la branche enhanced-models. FLAG_HD_MODELS est une condition de compilation commune. Aucun second override update pc-settings trouvé.
Les suspensions de rattrapage main.gc:1820–1835 interviennent avant le dessin et ne font pas exécuter actors-update. Aucun chemin établi où un scan sauté ferait franchir au cache une compaction normale supplémentaire.
L'invalidation reste possible par désactivation après collecte (ancienne ligne3400 ou3421), puis réutilisation à3440 ; ou par logique des processus après suspend. return-process rend le record nul (gkernel.gc:1070), deactivate annule le PID et descend aux enfants (1941–1947). La trace ne nomme pas laquelle de ces branches a invalidé obj.

## Relecture du correctif présent

Diff jak-hd.gc examiné : deux array handle, producteurs process->handle, toutes lectures compagnons/drivers résolues par handle->process. Les champs sont lus seulement après comp/obj vrai ; couverture exige comp ET drv vrais, empêchant #f=#f ; aucun spawn pour pilote mort. Compteurs bornés à16 et incrémentés après écriture : aucun handle initial zéro consommé normalement. Un slot réutilisé avec autre PID est refusé ; une relocalisation conserve l'identité via ppointer. Pas de nouvelle garde hd-mtxarea ni de modification des métriques/rendu. git diff --check -- goal_src/jak1/pc/jak-hd.gc : sortie0.
Limites : le correctif ne garantit rien contre un objet vivant réellement corrompu ; aucun test de compilation/exécution effectué dans cette recherche. Le commentaire existant « nouveau look au scan suivant » était déjà approximatif : les candidats du nouveau look sont collectés avant réconciliation et peuvent être spawnés dans le même appel. Aucun changement supplémentaire demandé.
