# Eclairage eteint, le processeur arrete de pousser des parametres pour rien

## Defaut cite
- 2026-09-10 : « bah c'est debile, c'est des choses a traiter ! OK pas par lui, mais s'il fait que les mentionner et on en fait jamais rien, ca va rester la, et on va potentiellement se trainer cette merde pendant des mois pour rien, pour qu'un jour quelqu'un retrouve l'erreur par hasard et la corrige... DEBILE !!! Si ce que remonte le worker n'est jamais traite par qui que ce soit, ca sert a rien, quel gaspillage ! Donc si, a traiter ! Et c'est exactement le genre de choses que tu devrais me remonter pour que je te dise si c'est pertinent ou pas, a faire ou pas ! Donc si, ces choses sont a traiter, je dirais juste apres meme ! »

## Cause connue
Signale par le worker de recharged-gating-real (essai 1, note 05) et LAISSE EN L'ETAT : ~50 `glUniform` par `first_tfrag_draw_setup` sont pousses sans condition, eclairage eteint compris (background_common.cpp:2246-2929). Les valeurs sont neutralisees cote shader — aucune fuite visuelle — mais le CPU paye a chaque image. L'owner lie ses mauvaises perfs Redmi a ce genre de porte qui ne ferme pas. Jamais mesure.

## Livrable
`uniform_off_pushes` = 0 : eclairage eteint, aucun parametre propre a l'eclairage n'est pousse. Publier le compte par image dans les DEUX etats (allume et eteint) : le compte eteint doit tomber a zero, le compte allume rester inchange. Publier aussi le cout CPU mesure des deux cotes. Aucun changement de rendu : allume, l'image reste identique au bit.

## Preuve exigee
`uniform_off_pushes == 0` dans `reports/gl-uniforms-off-cost/proof.txt`.
Le proof se produit par `lib/proof_run.sh gl-uniforms-off-cost x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : la cadence eclairage eteint ; owner_test=false.

## Hors perimetre
Ne pas toucher au contenu des shaders ni au rendu allume. Ne pas elargir aux autres familles d'uniformes : seul l'eclairage est vise ici.
