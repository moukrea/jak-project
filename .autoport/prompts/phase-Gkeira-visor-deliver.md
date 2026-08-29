# Gkeira-visor-deliver — livrer POUR DE VRAI la suppression du masque de Keira

## Pourquoi cette phase existe

La phase `Gkeira-hd-detached-parts` a ete declaree passee le 2026-08-28 a 15h53, et l'owner a
valide. **Rien n'a ete livre.** Il l'a constate lui-meme le 2026-08-29 :

> « Keira HD a toujours la visière attachée. »

## MESURE — l'etat reel, verifie le 2026-08-29

Dans `out/artifacts/jak1_hd_assets.zip` (le zip qui part chez l'owner) :

    keira-hd-ag.go     date du 2026-08-18 14:04     2 occurrences de `mask` / `maskstrap`

Dans la source :

    keira-hd-lod0.glb  joint `maskstrap` PRESENT    214 noeuds, inchange

**Le modele n'a jamais ete regenere.** Le rapport de la phase precedente disait vrai sur
l'intention et faux sur la livraison.

## LA VRAIE CAUSE DE L'ECHEC PRECEDENT — a ne pas repeter

Le contrat disait « ne pas editer le .glb, c'est un artefact GENERE, corriger la PREPARATION ».
Correct. Mais **personne n'a verifie que la preparation avait effectivement tourne et reecrit le
modele**. Un correctif ecrit dans un generateur qui n'est jamais execute ne change rien.

Les correctifs de GEOMETRIE et de POIDS DE PEAU ne voyagent QUE par
`jak1_hd_assets.zip`, jamais par l'APK. Un modele corrige cote source et non re-empaquete est
invisible pour l'owner.

## Le travail

1. Supprimer `mask` et `maskstrap` (173 sommets poses au sol, joint parente a la RACINE) dans la
   PREPARATION du modele.
2. **EXECUTER la preparation** et prouver que `keira-hd-lod0.glb` a change : nombre de noeuds
   avant/apres, et `maskstrap` absent de la liste des joints.
3. **RE-EMPAQUETER** le zip et prouver que `keira-hd-ag.go` qu'il contient est frais ET propre.
4. Ne PAS toucher aux bretelles ni aux lunettes : mesure du 2026-08-28, elles sont a leur place
   (0,21 et 0,52 du torse). Les chiffres contraires que j'avais publies venaient d'une inversion
   de matrice fausse.

## Exige pour fermer

La gate mecanique du validateur ouvre le zip livre, compte les occurrences de `mask` dans
`keira-hd-ag.go` et verifie l'age du fichier. **Zero occurrence et fichier de moins d'un jour**,
sinon echec. Aucune formulation de rapport ne peut la contourner.
