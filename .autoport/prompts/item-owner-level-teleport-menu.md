> LIS D'ABORD `prompts/item-owner-level-teleport-menu-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Un menu de teleportation vers n'importe quel niveau, ouvert par une combinaison de touches, pour que l'owner teste vite partout

## Defaut cite
- 2026-09-24 : « Alors le menu pour TP apparaît bien, mais vu que le joystick… »

## Cause connue
Demande de l'owner le 24/09 sur lighting-regimes (voir owner_feedback) : il doit verifier l'eclairage a plein d'endroits et le trajet a pied rend les tests « un calvaire ». Il a demande de le faire DANS lighting-regimes ; le superviseur en a fait un chantier separe place JUSTE APRES, parce que l'essai en cours de lighting-regimes ne relit pas sa consigne en cours de route et aurait pu se fermer sans le menu.
A VERIFIER AVANT D'ECRIRE : OpenGOAL a deja un menu de debug avec chargement de niveau et points de continuation (continue-point) ; le reutiliser plutot que reinventer. Le code GOAL ajoute vit sous goal_src/jak1/pc/ ; un fichier neuf doit etre liste dans game.gd ET engine.gd.

RETOUR DE […suite dans le contrat]

## Livrable
1. Combinaison de touches manette ET tactile (le telephone n'a pas forcement de manette) qui ouvre un menu listant les niveaux du jeu (et leurs points de continuation).
2. Choisir une entree teleporte Jak a cet endroit, jeu non casse ensuite (sauvegarde intacte, pas de plantage au changement de niveau).
3. Utile en plus pour l'eclairage : choisir l'heure de la journee (matin / midi / soir / nuit) depuis le meme menu.
4. Inactif par defaut pour un joueur normal si la combinaison peut se declencher par accident (a juger : combinaison peu probable ou reglage d'options).
5. Preuve PROGRAMMATIQUE simple : le moteur publie le niveau atteint et la position apres une teleportation declenchee par le […suite dans le contrat]

## Preuve exigee
`teleport_menu_defects == 0` dans `reports/owner-level-teleport-menu/proof.txt`.
Le proof se produit par `lib/proof_run.sh owner-level-teleport-menu device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : En jeu, sur le telephone : la combinaison de touches ouvre le menu, choisir un niveau (et un moment de la journee si fourni), on y est..

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
