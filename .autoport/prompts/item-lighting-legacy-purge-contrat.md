# Les reglages d'eclairage de l'ancien monde ne cohabitent plus avec la refonte — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

Owner 10/09 : « Modele d'ambiance, Materiaux PBR, Force de l'ambiance, Distance des ombres [...] c'est des trucs anciens [...] j'ai peur que ca rentre en collision avec notre nouvelle approche ». Sa crainte est fondee : lighting-ao-indirect a trouve un verrou safe-boot herite qui epinglait l'AO a zero en silence, ligne de menu sur HBAO et moteur a zero.

## Livrable — le contrat, en entier

`lighting_legacy_sites` = 0. Recenser CHAQUE reglage d'eclairage anterieur a la refonte, avec pour chacun : le chemin de code qu'il pilote, s'il s'execute encore, et l'item de la refonte qui le remplace. Puis, pour chacun, soit il est SUPPRIME du code (pas debranche), soit il est explicitement rattache au chemin unique de la refonte. Publier la table avant/apres et le compte d'execution de chaque chemin herite : tous a 0. Un binaire ou l'ancien chemin n'est PAS COMPILE vaut mieux qu'un drapeau a zero. S'AJOUTE (refus 11/09, LE PLUS GRAVE) : RETIRER LA LIGNE SANS RETIRER LE CODE EST PIRE QUE NE RIEN FAIRE. L'owner avait le PBR actif sur son Honor ; la ligne de menu a disparu, l'effet est TOUJOURS LA, et il n'a plus aucun moyen de l'eteindre. Pour CHAQUE reglage herite : le code est SUPPRIME de l'arbre, pas debranche ni laisse a zero. Owner 11/09 : « faut supprimer le code ! On en veut plus, ca va etre refait, mieux, donc ca degage pour eviter de polluer ». PREUVE, la meme que pour le navigateur de mesh : les symboles du chemin herite sont a ZERO occurrence dans le libgk.so livre, et ses fichiers source ont quitte l'arbre et les deux CMakeLists. Publier le recensement symbole par symbole, avant et apres. Un compteur d'execution a 0 ne suffit PAS : du code non compile est le seul etat qui ne peut pas revenir — et si le reglage etait ACTIF dans le settings.ini de l'owner, la course doit partir de CE fichier-la, pas d'un settings neuf. Un reglage retire du menu et encore executable est un DEFAUT plus grave que le reglage lui-meme. Verifier nommement le PBR.
VERDICT AJOUTE LE 12/09, MESURE SUR LE CHECKPOINT DE L'ESSAI 8. Supprimer `pbr_fused.glsl` et `pbr_helpers.glsl` retire les DEUX SEULS appelants de `rt_sh_ambient()` : `u_rt_sh[9]` n'a plus aucun lecteur, le compilateur GLSL le retire, et les neuf coefficients d'ambiante directionnelle SH — feature VALIDEE par l'owner (Grecharged-directional-ambient ROUND 2) — sont pousses vers un emplacement inexistant : 230 880 poussees mesurees sous `kept_uniform_list=u_rt_sh[0]`. Cet item doit donc PUBLIER que l'ambiante SH survit a la purge : un compte de lecteurs de `u_rt_sh` non nul dans les programmes LIES, et le meme rendu d'ambiante avant/apres. Purger l'ancien monde ne veut pas dire emporter une feature que l'owner a validee.

## Hors perimetre

Ne pas livrer les features de la refonte elles-memes : chacune a son item. Ici on retire l'ancien et on dit ce qui le remplace.

## Ou l'owner regardera

Options > Recharged > Recharged Lighting : plus aucune ligne de l'ancien monde, et plus aucun de leurs effets en jeu — le PBR nommement, que tu avais actif.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-10
> Modele d'ambiance, Materiaux PBR, Force de l'ambiance, Distance des ombres, Qualite des ombres, Relief des textures, Intensite des reflets, Profondeur de surface, Subdivision du maillage, Materiaux avances... C'est des trucs anciens qui n'ont aucun rapport avec la refonte de l'eclairage actuel non ? Pourquoi on les garde ? C'est une question mais j'ai peur que ca rentre en collision avec notre nouvelle approche et notre nouveau code

### 2026-09-10
> les anciens reglages d'eclairage, vire les dessuite avant qu'ils nous embetent, on en veut pas de toute facons

### 2026-09-11
> les reglages anciens sont bien supprimes du menu lighting... Mais sur le Honor j'avais les PBR actives et tout un tas de merdes, et visiblement ils sont toujours actives (ca se voit in-game) sans possibilite de les desactiver du coup... J'aurais pense que ca retirait aussi le code mort, et c'est pas du tout le cas vu que je me cogne toujours le PBR !

### 2026-09-11
> bah non faut supprimer le code ! On en veut plus, ca va etre refait, mieux, donc ca degage pour eviter de polluer !

### 2026-09-12
> pour la purge des vieux trucs ca a l'air bon, j'ai plus de PBR mal fait sur le HONOR

### 2026-09-12
> lighting-legacy-purge, valide

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

