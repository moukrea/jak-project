# La lumiere principale par creneau (validee) ne peut plus regresser : un acquis la protege

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
L'owner a VALIDE lighting-regimes le 25/09. Grandeurs deja publiees par le chantier : signe du produit scalaire cle/creneau (> 0 partout), poids direct la nuit (0), rapport sol recharge ON/OFF par niveau (village3 1068/1000), rapport ombre/soleil sous Jak (0,568).

## Livrable
1. `.autoport/acquis/lighting-regimes.sh` : relit ces grandeurs et rougit si l'une sort de la valeur validee (sens de la lumiere inverse, nuit allumee, sol d'un niveau < 0,5 de l'origine, ombre illisible).
2. CONTROLE POSITIF (reintroduire la negation de direction -> rouge nomme) + CONTROLE NEGATIF.
3. Publier le nombre de grandeurs lues (0 = defaut).

## Preuve exigee
`lighting_regimes_acquis_defects == 0` dans `reports/acquis-lighting-regimes/proof.txt`.
Le proof se produit par `lib/proof_run.sh acquis-lighting-regimes x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a regarder : garde-fou du harnais..

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
