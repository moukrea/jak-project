# Ghd-skin-origin-stretch — les modeles HD s'etirent vers l'origine du monde

Retour owner mot pour mot : `.autoport/reports/Ghd-skin-origin-stretch/owner-defects.txt`.

## L'hypothese que sa description designe
« s'allonge vers un point d'origine au loin », « plus on est loin, plus c'est extreme » :
c'est la signature d'une matrice de squelette qui retombe a l'identite ou a zero pendant
une image. Les sommets vont alors a (0,0,0) au lieu du personnage, et la longueur de
l'etirement vaut la distance joueur-origine.

## Premier livrable : CONFIRMER LA CIBLE
Avant toute correction, prouver que le point vers lequel les sommets partent est bien
l'origine du monde, et pas un lieu. Mesure : capturer les positions de sommets pendant un
episode et publier le point de convergence. Si ce n'est pas (0,0,0), toute la suite change.

## LE RECIBLAGE — indice owner, et il reduit la recherche a UN terme
Les modeles HD sont recibles sur les originaux pour l'animation. La matrice finale vaut
`bone_hd[k] = M_eichar_anim[e] . inv_bind_eichar[e] . bind_hd[k]`
(voir `scripts/shell/retarget_fill_table.py`). Les deux derniers termes sont CONSTANTS :
ils ne peuvent pas produire un defaut intermittent. Seule `M_eichar_anim[e]`, la matrice
animee monde du joint pilote, change par image — et c'est elle qui porte la POSITION
MONDE. Si elle est lue avant d'etre remplie, l'os part a l'origine.
=> instrumenter CE terme au moment ou le reciblage le consomme, et verifier l'ordre
   d'execution par rapport a l'animation du modele d'origine, a chaque image.
=> publier aussi le nombre de joints qui basculent entre mappe et non mappe d'une image a
   l'autre (attendu : 0).

## Intermittence
« pas tout le temps », « une split seconde ». Une course sans episode ne prouve rien :
publier le nombre d'episodes par minute de jeu, et la distance a l'origine au moment de
chaque episode — la correlation attendue est lineaire.

## Etendue
Jak, Daxter, mais aussi Samos et Keira : ils partagent la chaine de peau. Mesurer les
quatre, publier lesquels sont touches.

## Format des marqueurs
    HDSTRETCH cible_x=<f> cible_y=<f> cible_z=<f> est_origine=<0|1>
    HDEPISODE modele=<jak|daxter|samos|keira> distance_origine_m=<f> longueur_etirement_m=<f> duree_ms=<f>
    HDCORREL n=<n> pente=<f> r2=<f>
    HDCAUSE nommee=<...> methode=<mesure|ablation>
    HDOK minutes_de_jeu=<f> episodes=<n>
Verifie : HDSTRETCH avec est_origine tranche ; >= 20 lignes HDEPISODE couvrant au moins
2 modeles ; HDCORREL avec r2 >= 0,8 (la longueur doit suivre la distance) ; HDCAUSE
nommee ; HDOK avec >= 10 minutes de jeu et episodes == 0 apres correction.
