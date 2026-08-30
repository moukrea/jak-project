# Gjak-hd-rig-strap — deux defauts de rig sur la sangle du dos de Jak HD

## Le defaut, mot pour mot (owner 2026-08-29)

> « On dirait qu'un point de sa veste bleue soit lié à la lanière dans son dos qui "bouge avec le
> vent" du coup les polygones liés passent au travers de la sangle dans son dos c'est bizarre.
> Idem pour la boucle en métal de la sangle dans son dos, il semblerait qu'elle soit attachée aux
> mouvements des épaules, donc elle bouge séparément de la sangle c'est bizarre et glitchy. »

**Ce sont DEUX defauts distincts, et aucun n'est de la physique.** Aucun reglage de solveur ne les
corrigera : tant que la boucle pend des epaules, elle suivra les epaules.

1. **Un sommet de la veste bleue est pondere sur l'os de la SANGLE.** Quand la sangle s'anime, ces
   polygones la traversent. Defaut de POIDS DE PEAU.
2. **La boucle metallique est parentee aux EPAULES** au lieu de la sangle. Elle bouge donc
   independamment de ce qu'elle est censee tenir. Defaut de PARENTAGE : le bon os existe, la
   piece est accrochee au mauvais.

## METHODE IMPOSEE — tiree d'une erreur payee le 2026-08-28

Publier les positions de repos et les poids AVANT et APRES, calcules avec une **vraie inverse de
matrice 4x4**. La formule simplifiee `-R^T . t` n'est valable que sans mise a l'echelle ; je l'ai
appliquee hors de son domaine sur le modele de Keira et j'ai annonce a l'owner un defaut a
**62 fois la taille du modele qui n'existait pas**. Le tell aurait du etre l'invraisemblance
elle-meme : quatre joints EXACTEMENT au meme point tres loin est une signature de calcul casse,
pas de donnee cassee.

## PIEGE DE LIVRAISON — paye deux fois le 2026-08-28

Les correctifs de GEOMETRIE et de POIDS DE PEAU ne voyagent QUE par `jak1_hd_assets.zip`, jamais
par l'APK. Deux fois, une correction juste a la source n'a jamais atteint l'owner parce que
l'artefact n'avait pas ete regenere :

- le masque de Keira etait « supprime » depuis 15h53 et le modele livre le contenait encore,
  dans un fichier vieux de ONZE JOURS ;
- le texte anglais etait converti et l'APK livrait une copie de DIX-SEPT JOURS.

**Prouver la correction sur le fichier REELLEMENT LIVRE dans le zip**, avec sa date, pas sur la
source.

Et ne PAS editer le `.glb` : c'est un artefact GENERE, il sera ecrase. Corriger la PREPARATION,
puis EXECUTER la preparation et prouver que le modele a change.

## Exige pour fermer

1. Le sommet de veste n'est plus pondere sur l'os de sangle. Publier le compte de sommets
   concernes AVANT et APRES.
2. La boucle est parentee a la sangle. Publier la chaine de parents avant et apres.
3. Positions de repos avant/apres, calculees avec une inverse 4x4 complete.
4. Le fichier livre dans `jak1_hd_assets.zip` porte la correction, et il a moins d'un jour.
5. Rien d'autre du rig n'a bouge : publier le nombre de joints et de sommets, identiques.
