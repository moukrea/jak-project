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

## CORRECTION DE METHODE — SUPERVISEUR 2026-09-02 07:10. CE QUI PRECEDE EST CADUC.
Trois tentatives, deux heures et demie, ZERO mesure produite. Attraper a l'ecran vingt
episodes d'une fraction de seconde chacun est un instrument trop cher — c'est la meme
faute que sur les caisses, ou l'owner a du me faire abandonner le pilotage pour une sonde
programmatique (« fais ça de façon programmatique [...] impossible que tu couvre toutes
les caisses à la vue »).

ON NE MESURE PLUS LE SYMPTOME, ON MESURE LA CAUSE.
La formule est connue : `bone_hd[k] = M_eichar_anim[e] . inv_bind_eichar[e] . bind_hd[k]`.
Les deux derniers termes sont CONSTANTS. Seul `M_eichar_anim[e]` varie, et c'est lui qui
porte la position monde. Le defaut est donc, par construction, une lecture de ce terme
avant qu'il soit rempli.

PROTOCOLE :
  1. Instrumenter le site EXACT ou le reciblage consomme `M_eichar_anim[e]`.
  2. A CHAQUE IMAGE et pour CHAQUE joint pilote, tester la matrice consommee : est-elle
     remplie pour cette image (compteur d'image a jour), ou est-ce une valeur de l'image
     precedente / non initialisee / nulle ?
  3. Publier le compte d'images ou au moins un joint est servi par une matrice PERIMEE.
     Aucune image regardee, aucun episode a guetter : le defaut se compte tout seul.
  4. Corriger, puis remontrer ce compte a ZERO sur une duree de jeu equivalente.

Format des marqueurs REVISE :
    HDSTALE minutes=<f> images=<n> images_avec_matrice_perimee=<n> joints_touches=<n> modeles=<liste>
Verifie : au moins une ligne AVANT correction avec images_avec_matrice_perimee >= 1 (sans
reproduction rien n'est prouve), et une ligne APRES a ZERO sur >= 5 minutes de jeu.
Les anciens marqueurs HDEPISODE / HDCORREL ne sont plus exiges.

## RELANCE SUPERVISEUR 2026-09-03 07:35 — LA CAMPAGNE REDMI MEURT AU LANCEMENT
La capture dev7-abl1 fait 41 ko : le jeu s'initialise et la trace s'arrete UNE SECONDE
apres SDL_Init. Rien depuis 06:18. Deux tentatives (9 et 10) ont eu la partie technique
finie (source du w fermee, ablation x86 : 686 / 848 / 0 sauts) et n'ont JAMAIS produit
une course Redmi qui aille au bout.

ORDRE POUR CETTE TENTATIVE, AVANT TOUTE AUTRE CHOSE :
  1. Lancer le jeu sur le Redmi et VERIFIER qu'il tourne 60 s (ps + logcat qui avance).
     S'il meurt : publier le diagnostic (signal, derniere ligne) et le corriger. Ne pas
     passer a la mesure tant qu'une course ne survit pas.
  2. Ensuite seulement, la campagne : >= 10 min en mouvement (>= 500 m), HDROOTJUMP et
     t-pose a zero, sur les niveaux lointains.
Rien d'autre n'est attendu de cette tentative.
