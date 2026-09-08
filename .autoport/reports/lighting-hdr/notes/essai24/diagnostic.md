DIRECTIVES va841fb32b6

Essai24 : diagnostic régional éco et portail

Le rendu conserve le shader livré essai23. Aucune retouche gamma/exposition/épaule n’est justifiée par les seules mesures disponibles avant cet essai.
Sources et empreintes : sources.json. Les ancres de données sont distinguées des acteurs effectivement vivants : le logger associe une texture et une distance au voisinage de l’ancre, pas un PID GOAL.

Correction du diagnostic temporel : refset possède maintenant une option explicite de capture de2à16 images par configuration. Les images supplémentaires portent un suffixe et leur provenance ; seul sample0 alimente les mesures historiques. Le temps des particules avance une fois par frame logique. Rien ne promet une restauration ou une synchronisation exacte des éclairs.
La nouvelle vue place Jak huit mètres avant aid10012, sans le téléporter sur le collectable. Elle est explicitement sélectionnée et ne change pas le parcours par défaut. La caméra du portail reprend le cadrage AVANT pour permettre comparaison.

Sprite3 interroge le passage des fragments aux tests profondeur/alpha des instances associées aux textures et ancres éco/portail. Les bornes des quatre coins2D sont projetées avec les équations du shader Jak1. Ces rectangles contiennent aussi du décor : ils ne sont ni un masque de texture ni un verdict artistique. Les chemins3D, non instanciés, double_draw et requête occupée restent explicitement non qualifiés.
Le helper mesure avec ImageMagick le rectangle commun aux deux bras et à toute la séquence ; il conserve aussi les frames où l’effet n’a pas de fragments visibles. Il produit des distributions de blancs/quasi-blancs/couleur/luma/détail/aplats. Les cas non attribués restent présents ; la garde des cinq régressions n’est pas abaissée.

Incident de coordination : proof_run a été édité pendant le lot AVANT. Bash a repris à un offset déplacé et terminé rc3 après avoir écrit le manifeste. Le lot a été récupéré par --hdr-aggregate-only, rc0, sans nouvelle exécution jeu ; 20hashes vérifiés. L’erreur originale reste run-before.log. Aucun champ proof n’a été écrit manuellement.

Build : build-deploy.log et build-deploy-summary.json, incrémental gk puis repack/install, rc0, MD5 bibliothèque build/APK/Redmib46e36b11c076331c3a93a4a14462421. Les fichiers AVANT sont conservés dans before-build/.
Les tests synthétiques ne valent jamais preuve jeu. Les résultats appareil et limites sont ajoutés après le lot officiel.

Le premier lot instrumenté s’est arrêté à24/48captures, crash1 frame1143 A18 type-method-zero : les sources restent batches/essai24-owner-regions/20260908T055814-3737806. Il contient4707témoins par texture/proximité de1395, dont688requêtes avec fragments passés mais0ROI valide (analyse-owner-regions.json).
La revue a identifié la garde raw_w>0 absente du shader : camera.w est une coordonnée de brouillard signée avant hvdf.w, et pfog0 est négatif dans les paramètres initiaux. La correction accepte un w signé non nul puis vérifie le w final de chaque coin. Les nouvelles traces portent camera_w/pfog0/quad_w. Le deuxième build groupé inclut aussi le comptage de la vue additionnelle dans hdr_expected ; aucune courbe de rendu n’a changé.
Le helper conserve maintenant les cellules temporelles complètes d’un processus interrompu pour permettre leur remplacement explicite ; une cellule absente/incomplète reste non qualifiée, les incohérences de provenance/configuration restent des erreurs. Tests:133passed en52.88s, harness-tests.log.
Deuxième livraison : projection-build/build-deploy.log, rc0 ; MD5 bibliothèque build/APK/Redmi ba3d5711227381380fc9857c70f071b8.
