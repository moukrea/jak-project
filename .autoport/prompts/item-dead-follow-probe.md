# Un reglage mort dans le code, ecrit par personne, lu par personne

## Defaut cite
- 2026-09-10 : « bah c'est debile, c'est des choses a traiter ! OK pas par lui, mais s'il fait que les mentionner et on en fait jamais rien, ca va rester la, et on va potentiellement se trainer cette merde pendant des mois pour rien, pour qu'un jour quelqu'un retrouve l'erreur par hasard et la corrige... DEBILE !!! Si ce que remonte le worker n'est jamais traite par qui que ce soit, ca sert a rien, quel gaspillage ! Donc si, a traiter ! Et c'est exactement le genre de choses que tu devrais me remonter pour que je te dise si c'est pertinent ou pas, a faire ou pas ! Donc si, ces choses sont a traiter, je dirais juste apres meme ! »

## Cause connue
Signale par le worker de recharged-gating-real (essai 1, note 05) et LAISSE EN L'ETAT : `recharged_follow_probe` (gfx.h:558) est ecrit par kmachine.cpp et lu par PERSONNE dans tout l'arbre. Sa rangee de menu (ENV PROBE) a ete retiree le 2026-09-02. Le brancher lui donnerait une porte sans consommateur ; le laisser, c'est un champ mort qui survivra des mois.

## Livrable
`dead_probe_sites` = 0 : le champ et ses sites d'ecriture sont SUPPRIMES (declaration, ecriture kmachine, serialisation, reglage persistant s'il en reste). Publier le recensement avant/apres. Aucun changement de comportement : personne ne le lisait.

## Preuve exigee
`dead_probe_sites == 0` dans `reports/dead-follow-probe/proof.txt`.
Le proof se produit par `lib/proof_run.sh dead-follow-probe x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : nettoyage ; owner_test=false.

## Hors perimetre
Ne supprimer que ce champ. Tout autre champ suspect se signale, ne se supprime pas ici.
