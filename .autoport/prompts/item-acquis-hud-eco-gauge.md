# La jauge d'eco du HUD recharge ne peut plus regresser : un acquis la protege

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
L'owner a VALIDE hud-eco-gauge le 2026-09-22 et AUCUN `acquis/hud-eco-gauge.sh` ne la protege (`ls .autoport/acquis/` : 10 scripts, aucun ne nomme eco/gauge/hud). Sans acquis, la jauge peut redevenir fausse dans des semaines sans qu'une seule porte rougisse — c'est exactement le scenario que les acquis existent pour empecher.
CE QUI A ETE MESURE A L'ESSAI 17, source=device, et qui donne les grandeurs a figer :
  - taille du decal par type d'eco : 377 / 377 / 378 px pour une cible de 377 (les trois types font la meme taille — c'est le premier defaut que l'owner avait nomme) ;
  - la LUEUR (le halo), et pas seulement le decal opaque, passe par-dessus la jauge ;
  - la jauge pleine est masquee en camembert selon l'eco active, l'embout suit le remplissage.
L'owner a valide SUR L'ECO BLEUE SEULE : « j'ai pas de moyens rapide de tester l'Eco jaune et rouge ». L'acquis doit donc couvrir les TROIS types, puisque c'est lui qui verra ce que l'owner n'a pas pu verifier a la main.

## Livrable
1. `.autoport/acquis/hud-eco-gauge.sh`, sur le modele de `acquis/perf-dma-chain-copies.sh` (item appareil), qui lit les grandeurs de la jauge produites par le code et rend 0/non-nul.
2. Il compare les TROIS types d'eco, pas seulement le bleu : taille par type contre la cible, et l'ordre des couches (lueur au-dessus de la jauge).
3. CONTROLE POSITIF FABRIQUE : forcer une taille differente pour un type, verifier que l'acquis rougit et NOMME le type fautif. Publier la valeur des deux bras.
4. CONTROLE NEGATIF : sur le binaire courant, l'acquis rend 0.
5. Publier `eco_gauge_acquis_defects` et le NOMBRE de grandeurs reellement comparees (`terms_measured`) : une somme a 0 sur zero terme mesure est un faux vert.

## Preuve exigee
`eco_gauge_acquis_defects == 0` dans `reports/acquis-hud-eco-gauge/proof.txt`.
Le proof se produit par `lib/proof_run.sh acquis-hud-eco-gauge device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a regarder dans le jeu : c'est un garde-fou du harnais..

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
