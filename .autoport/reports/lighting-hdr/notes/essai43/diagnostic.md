DIRECTIVES v8aed688f73

Essai43 : reprise du rendu41 (genou 0,96), diagnostic séparé de la correction de durée de vie HD.
La revue détaillée du cache et du dump42 est dans crash-review.md ; pas d'attribution certaine du dernier écrivain de FFFFFFFF.
jak-hd.gc : caches compagnons ET pilotes convertis en handles au producteur ; résolution avant chaque usage. Aucun calcul matrice/modèle/effet retiré.

Rendu : portal96/native-summary.json de l'essai41 mesure avant sprites un ratio RGB ON/OFF de 0,705947/0,691894/0,689616.
tfrag3.frag construit baked*texture puis appelle shade une fois ; aucune double invocation trouvée.
shade.glsl371..388 applique volontairement BAKED-MODULATION : shadow_mul0,65/lit_boost1,15, teintes0,12.
Une ombre précalculée peut donc recevoir une seconde atténuation ; aucun défaut accidentel de multiplication démontré à ce stade.
Les props existantes rt.litboost=100, rt.shadowmul=100, rt.tintlit=0, rt.tintshadow=0 neutralisent exactement rt_mod, sans changer les portes HDR/RT.
Le run hut-neutral utilise cette ablation pour attribuer l'assombrissement ; il ne constitue pas un réglage livré ni une validation qualité.
La source GOAL locale est modifiée pendant ce run, mais lib/CGO appareil restent ceux de l'essai41 ; les empreintes appareil sont archivées dans preflight/.

Les images ON/OFF portal96 ont été examinées pour choisir les zones de diagnostic, jamais comme preuve de réussite.
La vue corrigée de la pièce (-138,451 ; 49,300 ; 203,282) reste nommée village1-out par l'ancien instrument ; la correspondance historique est dans essai32/hut-portal/view-correspondence.md.
Les PNG existants sont 320x180 ; les compteurs de composition proviennent du framebuffer natif 960x432 et du disque portail projeté, pas d'une image détaillée entière exportée.
HUT_VIEWS vide et absence d'attribution instrumentée du sol : couverture vraie hutte/sol toujours non prouvée. Aucun ajout de harnais ni critère assoupli.

Résultat du run neutral officiel : duration_s385/crash0/frames4560 ; 4 captures, 21 fichiers scellés SHA vérifiés ; délais après repin55,034/110,595s ON et41,502/83,652s OFF (timing-and-witnesses.json).
modulation-comparison.json conserve les sources/hashes et les résultats du mesureur existant hdr_batches.measure, sans écriture de proof.
Disque portail avant sprites, ratiosRGB ON/OFF : livré41(0,705947/0,691894/0,689616) ; neutral43(1,005346/0,999601/1,001169).
Image entière, luma ON/OFF : livré41 64,223/91,365 ; neutral43 91,448/91,246. Détail :15,767/20,222 puis20,139/20,181.
Rectangle inférieur [0,120,320,180], luma :66,961/103,826 puis103,788/103,826 ; détail12,814/19,730 puis19,727/19,730. Ce rectangle n'attribue PAS le sol extérieur signalé par l'owner.
La neutralisation de B supprime ainsi l'essentiel de l'assombrissement mesuré, avant tone map. Pas de réglage livré : neutraliser B supprimerait aussi sa modulation d'ombre ; aucune solution conservant cet acquis établie.
Les props de diagnostic ont été retirées et les réglages exacts restaurés. Le défaut global reste4, les cinq cas restent non validés.
Antécédent retrouvé : essai34/portal-modulation-unit/resultat.md avait essayé ces quatre props mais échoué avant toute capture (reserve-root déjà présent,0mesure). Essai43 fournit les mesures manquantes avec attente portail et résolution fixe ; ne plus rejouer cette ablation.

Réglage global écarté sans nouvel essai : shadow_mul0,65→1 et tint_shadow0,12→0, en gardant lit_boost1,15/tint_lit0,12, ne reproduit pas l'ablation à quatre paramètres mesurée.
Lecture de shade.glsl371..388 : ce candidat réduit l'amplitude multiplicative ombre/lumière de0,50 à0,15 ; les facteurs solaires se multiplient, la borne totale n'est donc pas simplement1..1,15.
Les uniformes partagés alimentent aussi pbr_fused.glsl560..574 et677 ; PBR était désactivé dans les réglages mesurés. Aucun résultat d'exécution ne couvre ce candidat ou son effet PBR.
Conclusion bornée : origine majeure de l'assombrissement attribuée à B par la mesure, correction visuelle préservant les autres contributions non établie. Aucun nouveau réglage global livré.
