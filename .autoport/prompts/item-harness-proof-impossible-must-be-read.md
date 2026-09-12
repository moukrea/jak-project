# Une preuve impossible remonte jusqu'a la porte, au statut et au digest de l'owner

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
SIGNALEMENT DU 12/09 (reports/harness-attempt-not-burned-by-foreign-cause/FINDINGS.txt, ligne 4). Le chantier precedent a fait ce qu'il fallait : toute sortie 3 de `proof_run.sh` passe desormais par `lib/proof_impossible.sh`, qui ecrit un etat NOMME a cote de proof.txt — 17 appels, 12 etats nommes sur sa propre course. Mais cet etat n'est lu QUE par le recensement de cet item-la. Ni la porte de fermeture, ni `autoport status`, ni le digest de l'owner ne le regardent.
CE QUE CA COUTE. Une preuve peut etre impossible pendant des heures — le constructeur a tenu le verrou de deploiement 6 h 38 le 12/09 — sans que rien ne le dise a personne. Un etat nomme que personne ne lit vaut exactement le silence qu'il remplace. C'est la meme classe que le compteur publie sans site d'ecriture et que la garde dont la seule occurrence est son en-tete : le vert vient de l'absence, pas de la mesure.

## Livrable
`impossible_read_defects` = 0, somme de termes publies SEPAREMENT.
1. La porte de fermeture LIT l'etat « preuve impossible » et ne rend plus « pas de preuve » quand la vraie reponse est « preuve impossible, voila pourquoi et depuis combien de temps ». Publier le compte d'etats lus et le compte de verdicts requalifies.
2. `autoport status` le fait apparaitre : un item dont la preuve est impossible ne se lit pas comme un item qui n'a rien produit. Publier le texte effectivement rendu, pas une intention.
3. Preuve a deux bras sur un etat jetable : un etat « impossible » SEME doit etre vu par les deux lecteurs dans le bras d'APRES, et par aucun dans le bras d'AVANT.
4. L'age de la cause est publie, pas seulement son existence : depuis combien de temps le verrou est tenu, ou l'appareil absent. Une impossibilite de 30 secondes et une de six heures ne se lisent pas pareil.

## Preuve exigee
`impossible_read_defects == 0` dans `reports/harness-proof-impossible-must-be-read/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-proof-impossible-must-be-read x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. C'est ce que le harnais raconte quand il ne peut pas mesurer..

## Hors perimetre
Ne touche a aucun code du jeu. Ne change pas la facon dont proof_run.sh detecte l'impossibilite.
