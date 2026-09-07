# Diagnostic — essai 12
DIRECTIVES v6fca51fe40

## Défaut causal corrigé : transition HDR vers sprites
Le log essai11 archivé dans essai11-avant12/proof-engine.log contient7290
GL_INVALID_OPERATION. Extraits exacts dans gl-errors-before-essai12.log :
`[[66] sprite] ... glUniform4("u_hdr_curve"@3 has 1 components, not 4)`
et `glUniformMatrix(non-matrix uniform)`.
Le programme actif est donc celui du tonemapping quand Sprite3 écrit ses uniformes.
Lecture du chemin : Sprite3.cpp:679 appelle begin_2d_ui_pass, puis :475 transmet
les locations de SPRITE3 à set_group1_uniforms sans réactiver le programme.
OpenGLRenderer.cpp:1555 appelle hdr::tonemap_draw, qui activait TONEMAP puis
rendait la main sans restaurer le programme, en mettant aussi VAO/array buffer à0.
Les rendus différés Generic2/Merc2 préservent leur appelant, déjà TONEMAP.
Correctif au producteur hdr.cpp : sauver et restaurer programme, VAO et array buffer.
Framebuffer et viewport destination sont conservés pour la passe UI suivante.
Aucune courbe HDR, valeur de référence, tolérance, masque ou source ND modifiée.
Le défaut GL intervient après les draws Merc ; il n'attribue pas la divergence lampe.

## Recherche état historique — researcher natif, lecture seule
Le préfixe564/suffixe108 est déjà livré et mesuré aux essais10/11.
Aucun delta causal identifié dans hutlamp/start/pad_replay/reseed depuis89db5b7d8a.
Hutlamp accumule clock.output (village-obs.gc:727–729), initialisé par rand-vu (:766).
Start recrée target, sans restaurer tous les acteurs résidents ; reseed après start
ne remplace pas les champs de la lampe. Le pas fixe existe déjà avant l'ancrage.
Données historiques absentes : tirage/phase init, naissance et suite des pas,
joint3/matrices et identité du contenu des ressources. Une phase arbitraire
ne constitue pas une reconstitution ; aucun gel ou déplacement du reseed appliqué.
La dépendance statique résiduelle des contacts herbe au temps mural n'est pas
attribuée à l'écart de lampe ; aucune édition de brise/cadence/herbe.

## Sunkenb — researcher natif, inspection CPU
Objet sunkenb-vis extrait et objet dans SUB.DGO :2796608 octets identiques,
SHA2564af61081b37f3acc887e8661c5342f91763102b3760f58ac3f04d1ef64039680.
BSP adgifs non nul,9 entrées :8 textures sky et1 clouds du tpage162.
Voir sunkenb-essai12.md pour commande et sortie. La piste de ressources ciel
absentes est réfutée. Conditions runtime sky-drawn/masque/contexte/paquet et
occlusion par la géométrie restent inconnues ; aucun retrait de Sunkenb.

## Limites de travail
Impossible d'affirmer la reconstitution des origines à partir des données retrouvées.
Les108 nouvelles références ne sont pas établies ; cinq rejeux et état complet
par cas restent non prouvés. Aucun nouveau diagnostic GPU ajouté pour un chiffre.
Une seule preuve courte après correction du producteur GL, sans nouvel oracle.

## Résultat après correctif
Proof_run code0 : crash0,frames8393,tonemap_draws2389 ; zéro erreur OpenGL.
SHA gk1aed1e5494ac62fa ; garde47 ;575 références intactes.
Analyse du manager :24 PNG legacy identiques essai11,origine/h00 maxdiff202
et794 pixels divergents, bbox287,13,314,72 ; aucune amélioration historique.
Plan672=564+108 ;37 comparaisons,couverture244 manques,rejeux0,maxdiff254.
Voir summary-essai12.json,legacy-comparisons-essai12.json,test-essai12.md.
Premier appel analyse : assertion24 échouée car archive complète (cas additionnels) ;
filtre des seuls noms legacy ajouté ; deuxième appel code0,aucun fichier image modifié.
Le builder a committé hdr.cpp dans3c911bd6ca après reprise ; ne pas dupliquer le patch.
Clarification superviseur6bea5cf81e lue : l'égalité compare chaque mode à ses
propres références, jamais ON à OFF ; ce correctif et les comparaisons respectent cela.
