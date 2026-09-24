# Un menu de teleportation vers n'importe quel niveau, ouvert par une combinaison de touches, pour que l'owner teste vite partout — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

Demande de l'owner le 24/09 sur lighting-regimes (voir owner_feedback) : il doit verifier l'eclairage a plein d'endroits et le trajet a pied rend les tests « un calvaire ». Il a demande de le faire DANS lighting-regimes ; le superviseur en a fait un chantier separe place JUSTE APRES, parce que l'essai en cours de lighting-regimes ne relit pas sa consigne en cours de route et aurait pu se fermer sans le menu.
A VERIFIER AVANT D'ECRIRE : OpenGOAL a deja un menu de debug avec chargement de niveau et points de continuation (continue-point) ; le reutiliser plutot que reinventer. Le code GOAL ajoute vit sous goal_src/jak1/pc/ ; un fichier neuf doit etre liste dans game.gd ET engine.gd.

RETOUR DE TEST DE L'OWNER (24/09, telephone, tactile) : le menu S'OUVRE bien, mais il est INUTILISABLE au tactile : le joystick virtuel n'est pas remplace par une croix directionnelle, donc Haut/Bas/Gauche/Droite ne sont pas accessibles pour naviguer.

## Livrable — le contrat, en entier

1. Combinaison de touches manette ET tactile (le telephone n'a pas forcement de manette) qui ouvre un menu listant les niveaux du jeu (et leurs points de continuation).
2. Choisir une entree teleporte Jak a cet endroit, jeu non casse ensuite (sauvegarde intacte, pas de plantage au changement de niveau).
3. Utile en plus pour l'eclairage : choisir l'heure de la journee (matin / midi / soir / nuit) depuis le meme menu.
4. Inactif par defaut pour un joueur normal si la combinaison peut se declencher par accident (a juger : combinaison peu probable ou reglage d'options).
5. Preuve PROGRAMMATIQUE simple : le moteur publie le niveau atteint et la position apres une teleportation declenchee par le banc sur 3 niveaux ; `teleport_menu_defects` = teleportations ratees ; doit valoir 0. PAS de preuve visuelle : c'est l'owner qui juge le confort.

AJOUT DU 24/09 : NAVIGATION TACTILE. Au tactile, le menu doit se piloter sans manette : soit la surcouche tactile affiche une croix directionnelle a la place du joystick tant que le menu est ouvert, soit le joystick virtuel pousse Haut/Bas/Gauche/Droite, soit on touche directement une ligne pour la choisir (le plus simple a l'usage). Validation, retour et reglage de l'heure accessibles aussi. Preuve legere : UNE grandeur (evenements de navigation recus depuis la surcouche tactile pendant que le menu est ouvert > 0) ; l'owner juge le confort.

## Hors perimetre

(non precise)

## Ou l'owner regardera

En jeu, sur le telephone : la combinaison de touches ouvre le menu, choisir un niveau (et un moment de la journee si fourni), on y est.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-24
> Alors tu me demande d'aller vérifier à plein d'endroits… Faudrait que j'ai un moyen simple de me TP dans n'importe quel niveau via un menu qui apparaît sur une combinaison de touches ou un truc du style, parce qu'en l'état c'est un calvaire pour faire ces tests. J'invalide pas, mais je vais avoir du mal à tester sans ça, et vu que ce ticket est toujours in progress… autant le faire là

### 2026-09-24
> Alors le menu pour TP apparaît bien, mais vu que le joystick n'est pas remplacé par un dpad c'est pas utilisable

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

