# La suite de tests est lue par la porte de fermeture, sinon son vert se perime en quelques heures

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
MESURE DU 12/09. A 06:16 la suite du harnais etait a 556 verts, pour la premiere fois depuis le 6 septembre. A 15:45, QUARANTE-QUATRE tests de `tests/harness/test_hdr_batches.py` etaient rouges.
LA CAUSE : `dead-published-keys-round-2` a renomme trois cles en `_const` et a mis a jour le LECTEUR (`lib/hdr_batches.py:709,780`) sans mettre a jour les tests qui les citent. Son essai a ete accepte, sa porte etait verte, et personne n'a rien vu.
POURQUOI PERSONNE N'A RIEN VU : `grep -n pytest .autoport/orchestrator.py .autoport/validators/` ne rend RIEN. Aucune porte ne lance la suite. Le vert obtenu le matin ne protege donc de rien des l'apres-midi, et le chantier qui l'avait obtenu perd son acquis en quelques heures.
Le superviseur a repointe les quatre citations sur les nouveaux noms le 12/09 a 15:50 : la suite est reverte. Ce chantier existe pour que ca ne se reperde pas.

## Livrable
`suite_gate_defects` = 0, somme de termes publies SEPAREMENT.
1. LA PORTE LANCE LA SUITE et lit son resultat : publier le compte de tests collectes, le compte de rouges, et l'empreinte du registre des echecs assumes. Un item qui rend la suite plus rouge qu'il ne l'a trouvee ne ferme pas.
2. LE COUT EST BORNE : la suite prend environ 90 a 190 secondes. Publier sa duree a chaque fermeture, et le budget retenu. Si elle depasse, la porte le DIT au lieu de l'avaler.
3. Un item ne peut pas se donner du vert en inscrivant son propre echec au registre : publier le compte d'entrees ajoutees au registre par l'item courant, qui doit etre nomme dans son rapport.
4. Preuve a deux bras sur une copie jetable : un item qui casse un test doit FERMER dans le bras d'AVANT et etre REFUSE dans celui d'APRES, avec le nom du test casse.

## Preuve exigee
`suite_gate_defects == 0` dans `reports/harness-suite-must-be-a-close-gate/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-suite-must-be-a-close-gate x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. C'est le filet du harnais, et le fait que quelqu'un le regarde..

## Hors perimetre
Ne touche a aucun code du jeu. Ne desactive aucun test, ne remplit pas le registre pour passer.
