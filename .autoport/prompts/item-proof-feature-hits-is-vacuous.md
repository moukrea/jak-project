# Le temoin « la feature etait armee » cesse d'etre satisfait par n'importe quel item

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
SIGNALEMENT DU 12/09 (reports/census-false-reds/FINDINGS.txt). `validators/generic.sh` exige dans chaque preuve la ligne `FEATURE <id> armed=1 hits=N`. Or `hits` est un compteur PARTAGE par TOUT le binaire (`game/system/autoport_proof.cpp`, `note_hit`), et `dead_probe_census()` (kmachine.cpp:907) l'incremente SANS CONDITION a chaque image.
CONSEQUENCE : la ligne est satisfaite pour N'IMPORTE QUEL item, y compris ceux dont tout le travail vit dans `lib/census/<id>.sh` et qui ne touchent pas une ligne du moteur. Le temoin censé dire « l'instrument de CETTE feature a tourne » ne dit rien du tout. Deja consigne comme piege le 09/09 — 4 419 755 hits pour 11 160 tone maps — mais jamais corrige au point ou la porte le LIT.
C'est un generateur de faux verts qui porte sur TOUTES les preuves, y compris celles du jeu.

## Livrable
`feature_hits_defects` = 0, somme de termes publies SEPAREMENT.
1. Le compteur lu par la porte est PROPRE A LA FEATURE mesuree : publier le compte de la feature et le compte global cote a cote, et l'ecart entre les deux. Deux items differents sur la meme course doivent rendre deux comptes differents.
2. Un item dont AUCUN site moteur n'appartient a sa feature rend un compte de feature NUL et la porte le dit, au lieu de le lire comme arme. Preuve a deux bras : un item de harnais pur doit sortir a zero, un item moteur non nul, sur la MEME course.
3. La porte distingue « feature absente du binaire » de « feature presente mais jamais atteinte ». Deux etats nommes, pas un seul zero.
4. Aucune preuve existante ne devient rouge pour cette seule raison sans que le rapport le dise : publier la liste des items dont le temoin change de sens.

## Preuve exigee
`feature_hits_defects == 0` dans `reports/proof-feature-hits-is-vacuous/proof.txt`.
Le proof se produit par `lib/proof_run.sh proof-feature-hits-is-vacuous x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. C'est le temoin que chaque preuve doit porter pour etre acceptee..

## Hors perimetre
Ne change aucun critere d'item. Ne touche pas aux instruments eux-memes, seulement a ce que la porte lit.
