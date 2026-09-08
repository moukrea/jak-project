DIRECTIVES v3909a9767c
Revue researcher lecture seule : surplus établi dans le groupe de sprites, attribution exhaustive et correctif causal exact non trouvés.
composition-events.json : ROI7020px, maxima bleusHDR15.3359/17.2344 après fond1.3848/1.4473 ; snapshot encadre Sprite3::render_2d_group0 entier (Sprite3.cpp1136..1164), pas seulement le disque.
witnesses.json filtre huit harddot ; engine.log contient aux LF2521/3181/3843/4503 respectivement232/229/231/229 témoinsHDR-OWNER-SPRITE.
Parmi les bornes ayant passé le testGPU et chevauchant le disque :10/11/7/11 middot bleus en plus des harddot, bornes source bleue1.77..2.00. Pas de comptage des texels effectivement couverts dans la ROI.
Ces mélanges décodent en enum2, Cs*As+Cd (Sprite3.cpp1430, background_common.cpp201..203), alpha séparé ; destination alpha n'entre pas dans ce RGB.
Generic2 possède la même équation mais ne dessine pas les instances observées ; aucune double-alpha fautive établie.
sprite3_3d_inst.frag26..29 borne déjà sourceRGB/alpha ; destination additiveHDR conserve des valeurs que RGBA8OFF écrête intermédiairement. Différence mécanique certaine, pas explication quantitative complète.
Sources non identiques : harddot alpha maximalON.831/.800 contreOFF.533/.125 ; nombres/positions middot variables. passed=true prouve un fragment passant, pas couverture de toute laROI.
Manque décomposition des contributions ordonnées parpixel/saturations. Aucun double dessin/blend erroné identifié ; aucun nouveau run ou instrument effectué.
Réintroduire écrêtage intermédiaire de la pile serait un choix de composition non démontré par ces traces ; aucun patch recommandé sur cette base.
