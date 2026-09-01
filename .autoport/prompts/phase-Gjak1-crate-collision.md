# Gjak1-crate-collision — DES CAISSES SANS COLLISION A GEYSER ROCK. Priorite haute.

Retour owner mot pour mot : `.autoport/reports/Gjak1-crate-collision/owner-defects.txt`.

## Pourquoi c'est prioritaire
Une caisse qu'on traverse est une caisse qu'on ne peut pas casser : ramassages perdus,
progression bloquee. L'owner l'a vu sur DEUX builds a un jour d'ecart, donc ce n'est pas
un hasard de course.

## L'indice a exploiter en premier
La phase `Gjak2-polish`, parquee par l'owner le 2026-07-10, decrit LE MEME symptome :
« collision REGRESSION game-breaking (no crates, no moving-platform landing) from the
crouch-fix nav/collide enablement ». La cause y est nommee. Verifie si ce chemin est
partage avec jak1 ou s'il a ete reactive ici. A CONFIRMER PAR LA MESURE, pas a supposer :
le symptome peut etre commun et la cause differente.

## COMPLEMENT OWNER (2026-08-31) — LIS CECI AVANT DE CHERCHER
« les caisses sont là mais je passe au travers », « pas toutes », « des fois aucunes »,
« c'est pas toujours les mêmes ».
 - Les caisses sont DESSINEES : l'acteur nait bien. Le defaut est dans l'ENREGISTREMENT
   ou l'ACTIVATION de la collision, pas dans le spawn ni le chargement.
 - Ce ne sont PAS toujours les memes : une donnee de collision cassee est EXCLUE, elle
   ferait echouer les memes caisses a chaque fois. Ne cherche pas dans les fichiers de
   niveau ni les maillages : c'est un defaut d'ETAT A L'EXECUTION.
 - Une course entiere peut etre propre : publie le compte PAR COURSE, jamais un agregat.
Instrumente le triplet qui tranche : pour CHAQUE caisse nee — son identite, si sa forme
de collision a ete allouee, et l'occupation du pool a cet instant. Il departage entre
budget epuise, course d'initialisation, et allocation qui echoue en silence.

## L'intermittence interdit la course unique
« c'est un peu random ». Une course propre ne prouve RIEN. Compte les caisses : combien
sans collision, sur combien testees, sur combien de courses. Publie les trois nombres.

## Depuis quand
L'owner l'a vu le 2026-08-30 au soir. Les archives datees sont sur jak-builds
(app-jak1-<date>-<commit>.apk) : bissecte dessus pour encadrer l'apparition, plutot que
de deviner en lisant le journal des modifications.

## Format des marqueurs
    RESULT: CRATES SOLID
    CRATEREPRO course=<n> caisses_testees=<n> caisses_sans_collision=<n> niveau=training
    CRATEBISECT build=<nom-apk> commit=<sha> caisses_sans_collision=<n>
    CRATECAUSE nommee=<...> methode=<mesure|ablation> lien_jak2=<oui|non|indetermine>
    CRATEOK courses=<n> caisses_testees=<n> caisses_sans_collision=0
Verifie : au moins 2 lignes CRATEREPRO avec caisses_sans_collision >= 1 (sans reproduction
rien n'est prouve) ; CRATEBISECT sur >= 2 builds pour encadrer l'apparition ; CRATECAUSE
nommee ; CRATEOK avec >= 3 courses, >= 20 caisses testees, et ZERO sans collision.

## MANQUE CONSTATE PAR LE SUPERVISEUR (2026-08-31 09:35)
Les courses r1 a r4 publient bien « une caisse sans collision » par course (ligne
GJCC-SUM, champ nocol). Mais AUCUNE ligne ne dit LAQUELLE : l'identite de la caisse
fautive n'est pas isolee dans les lignes par caisse.
C'est pourtant LE test de l'observation de l'owner : « c'est pas toujours les mêmes ».
 - si c'est la MEME caisse a chaque course -> son observation est infirmee et la cause est
   probablement liee a cette entite precise (ordre de naissance, position dans la liste) ;
 - si l'identite CHANGE -> son observation est confirmee et la cause est une course ou une
   allocation qui echoue selon le timing.
Les deux menent a des corrections opposees. Publier donc, pour CHAQUE course, l'identite
(aid) de la ou des caisses sans collision, et le verdict :
    CRATEIDENT course=<n> aid=<n> position=<x,y,z> ordre_naissance=<n>
    CRATEIDENTVERDICT memes_caisses=<oui|non> courses=<n>

## CORRECTION DE METHODE — OWNER 2026-09-01. LIRE ET APPLIQUER, CE QUI PRECEDE EST CADUC.
  « fais ça de façon programmatique [...] impossible que tu couvre toutes les caisses de
    Geyser Rock à la vue »

Il a raison et l'exigence precedente etait une erreur du superviseur. Conduire le
personnage jusqu'a 20 caisses avec de vraies entrees manette a couvert 3 caisses en
2 h 30. Ni le pilotage, ni la lecture d'images, ne sont des instruments acceptables ici.

LA COLLISION SE TESTE SANS JOUER. Le protocole devient :
  1. Charger le niveau NORMALEMENT (les caisses naissent comme en jeu — ne rien teleporter,
     ne pas fabriquer la condition « pas encore nee », c'etait le defaut du cycle d'avant).
  2. Pour CHACUNE des 31 caisses, par le code, publier :
       - sa sphere de collision est-elle FINIE (aucune composante NaN/inf) ?
       - une REQUETE de collision synthetique lancee contre elle depuis un point proche
         renvoie-t-elle un contact ?
     Aucune image n'est regardee, aucun bouton n'est presse.
  3. Repeter a plusieurs cadences, dont une <= 30 img/s, sur l'appareil.

Cela couvre les 31 caisses en une passe au lieu de 3 en deux heures et demie, et c'est
DETERMINISTE : deux courses identiques doivent rendre les memes comptes.

Format des marqueurs REVISE (les anciens CRATEOK/CRATEREPRO restent valables pour la
reproduction, mais la PREUVE FINALE se fait ainsi) :
    CRATEPROBE plateforme=<x86|redmi> fps=<f> caisses=<n> spheres_finies=<n> contacts_ok=<n>
Verifie : caisses == 31 ; spheres_finies == 31 ; contacts_ok == 31 ; au moins une ligne
avec plateforme=redmi et fps <= 30.
