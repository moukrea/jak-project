# Les comparaisons de fraicheur cessent d'etre aveugles a la seconde

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
QUATRE SIGNALEMENTS DU 12/09 (reports/build-tree-reinvalidates-itself/FINDINGS.txt), avec un balayage des 223 scripts du harnais vivant.
1. `lib/deploy_verify.sh:50` compare `SO_MTIME` (`stat -c %Y`, SECONDE ENTIERE) a `NEWEST_SRC` (`find -printf %T@` TRONQUE par `cut -d. -f1`) avec `-lt`. Deux fichiers ecrits dans la meme seconde sont declares a egalite : une source plus recente que le binaire passe pour fraiche.
2. `lib/deploy_verify_assets.sh:56` : meme motif sur la chaine GOAL, les deux cotes tronques.
3. `orchestrator.py:1548` : le boot-check de la porte de fermeture accepte tout artefact dont le mtime, seconde entiere, est superieur ou egal a `t0`. Un artefact ecrit juste AVANT le debut passe donc pour produit PENDANT.
4. Le meme balayage publie la population : c'est une classe, pas trois accidents.
CE QUE CA COUTE : une fraicheur est un verdict binaire, et chacune de ces comparaisons se trompe du cote PERMISSIF — elle accepte un artefact perime. C'est exactement le defaut le plus cher du projet : une preuve qui decrit un autre binaire que celui qu'on croit.

## Livrable
`subsecond_freshness_defects` = 0, somme de termes publies SEPAREMENT.
1. Chaque comparaison de fraicheur lit la MEME resolution des deux cotes : publier, site par site, la resolution employee. Une troncature d'un cote et pas de l'autre est un defaut compte.
2. L'egalite ne vaut plus fraicheur : a mtime egal, l'artefact est declare DOUTEUX et la porte le dit, au lieu de l'accepter. Publier le compte de cas d'egalite rencontres.
3. Preuve a deux bras sur un bac a sable : deux fichiers ecrits dans la MEME seconde, le plus recent etant la source. Le bras d'AVANT accepte, celui d'APRES refuse.
4. La population complete est publiee : le compte de sites balayes, le compte de sites corriges, et la liste de ceux laisses en l'etat avec leur raison.

## Preuve exigee
`subsecond_freshness_defects == 0` dans `reports/harness-subsecond-freshness-is-blind/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-subsecond-freshness-is-blind x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. C'est ce qui decide si une preuve decrit le bon binaire..

## Hors perimetre
Ne touche a aucun code du jeu. Ne change aucun critere d'item.
