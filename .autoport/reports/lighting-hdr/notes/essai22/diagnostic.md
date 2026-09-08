DIRECTIVES va841fb32b6
# Diagnostic essai 22 — correction alpha isolée

## Cause numérique reproduite, attribution locale non établie
La sonde Android déjà conservée dans notes/essai21/readback-check.json contient alpha=2.0078125 dans une lecture HDR, contre le domaine normalisé [0,1] de la cible OFF.
Les shaders multiplient l’alpha PS2 ; tfrag3.vert et sprite3_3d.vert le multiplient par quatre. Les tests alpha ont besoin de cette valeur brute et restent avant le clamp.
La spécification GLES3.2 § blending réserve le clamp automatique des entrées/facteurs aux cibles fixes : https://registry.khronos.org/OpenGL/specs/es/3.2/es_spec_3.2.pdf .
Dans le test synthétique Mesa exécutant direct_basic.frag réel (alpha_gpu.log), source-over donne avant RGBA=(-0.404297,-0.00194931,0.702148,2.00781), après=(0.199951,0.299805,0.399902,1), gl_error=0.
Le journal mesure aussi RGB=(2.5,3,4) conservé sans blend, et l’identité RGBA8 sur les quatre configurations du test.
Dix-neuf shaders bornent maintenant uniquement l’alpha en dernière instruction de main. Les tests de rejet restent sur l’alpha brut ; le test sprite3_3d.frag réel accepte 2.0078 dans [1.5,3] et le rejette dans [0,1] dans les deux versions.
Trois branches soustractives (DirectRenderer, DirectRenderer2, background_common) produisaient -As : facteurs alpha ZERO,ZERO rétablissent le zéro auparavant fourni par RGBA8. Le test GPU confirme alpha=-1 avec anciens facteurs même après clamp shader, et alpha=0 avec facteurs corrigés.
Limite : Generic2 produit Ad-As², d’autres modes accumulent alpha ; leurs équations sont différentes. Le correctif ne garantit pas que tout alpha de destination reste borné.
Ce diagnostic n’identifie pas les cinq régions owner et n’est jamais une preuve jeu.

## Courbe conservée pour isoler la composition
Fidélité0/exposition1/genou0,95 inchangés. La courbe de maximum RGB reste une piste distincte : analytiquement, (2,1,2) devient environ (0.998,0.499,0.998), tandis que RGBA8 écrête vers blanc.
Essai21/quality-review.md mesure sur images entières 6719 blancs OFF et zéro ON. Cela ne localise ni nuages, ni soleil, ni éclairs ; aucune correction des blancs n’est revendiquée.
Pas de nouveau bloom, particule ou réglage d’exposition. Pas de reprise des 21 niveaux tant que les cas prioritaires ne sont pas qualifiés ; anciens lots conservés, incompatibles avec le nouveau binaire pour la preuve.

## Échec du lot AVANT
Lot essai22-before/20260908T051058-3695478, même binaire que essai21 : quatre captures, deux paires rejetées black or achromatic capture, crash=0, frames=6420.
engine.log:23195 LOADSCREEN-SHOW arm=6 frames=1 précède h18 (:23203) ; :130181 porte frames=5520. Les lectures A42 colorées précèdent la composition UI ; pas de contradiction avec la capture finale noire/logo blanc.
La demande want.levels=village1,beach (:24346) est appliquée APRÈS toutes les captures : elle ne peut pas expliquer le premier noir. Déclencheur de chargement persistant inconnu.
Reprise APRÈS alpha : ordre ancien legacy,village1-out et want.levels=village1 (ancien log indique cette dernière demande inopérante need-two-levels), heures12/18. Ce remplacement de parcours ne déclare pas l’arrivée directe corrigée.

## Retrait du faux vert
Les manifestes actuels ne contiennent aucune ROI sémantique liée aux cinq cas, ni séquence éco. La preuve compte explicitement ces cas absents depuis proof_plan.
Défaut7 ajouté par le producteur officiel aux six contrôles existants ; statistiques image entière et assertions moteur ne remplacent pas une observation régionale. Aucun seuil de qualité assoupli, aucun validateur modifié.
Le helper ne définit aucun nouveau format de verdict manuel. L’implémentation des observations régionales et leur jugement reste à faire ; impossible de produire un zéro avec les seuls manifestes actuels.
