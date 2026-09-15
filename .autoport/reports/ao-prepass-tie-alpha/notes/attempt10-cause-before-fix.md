DIRECTIVES v775512c234
# Cause retenue avant modification du rendu
Source : course3 GTAO, proof_run_id20260915T044726Z-1886851-77fefe3e, archive21191-600.
Qualification GPU v2 : mur TFRAG source[73087,73088,73089], toit[29051,29052,29053].
250 pixels mur,175 toit,15 arêtes dont les centres encadrent l’intersection3D projetée.
Profil natif inchangé :29 côtés mesurables,1 manquant,0 censuré.
Table complète : attempt10-03-gtao-before/contact-profile-table.txt ; seuil strict4/255 conservé.
Brut :26 pixels-bande cumulés/max5 ; première paireH/V :4/max2 ; flou final :96/max7.
Les quatre ridge gardent96/max7. Les passes supplémentaires recréent et élargissent la bande.
Le noyau livré -1,0,1,2 a un premier moment+0,5 ; le test GPU impulsion mesure(-5,5,-5,5)px après8passes.
Le candidat -2..2 pondéré[1/8,1/4,1/4,1/4,1/8] mesure déplacement0 et masse1.
Test GPU périodique4x4 :457856 pixels intérieurs, plage résiduelle0, moyenne16phases conservée.
Décision : centrer ce noyau ; conserver sigma, pentes, ciel, seuils et ridge ; ne changer aucun estimateur.
Il s’agit d’un correctif du déplacement induit par le filtre, pas d’une validation du raccord complet.
Limites avant correction : HBAO archive absente1200/1400 ; SSAO capturé1400, GTAO600, modesdifférents.
Caméra41champs identiqueSSAOGTAO ; profondeursglobales920/480000différentes ; ne pas déclarer toutes entréesidentiques.
Le retourowner sur ce raccord n’est pas redemandé ; correspondance visuelle non employée comme preuve.
Un tap supplémentaire par passe, coûtGPU non mesuré. La couleur AOoff complète et acquis globaux restentnonprouvés.
