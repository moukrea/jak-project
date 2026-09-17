# Le HUD rechargé apparaît, disparaît et clignote exactement comme le HUD d'origine

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
SPEC HUD §6, owner : « faut que les comportements de clignotement/affichage soient identiques à l'original (du moins dans un premier temps) ».

## Livrable
`hud_parity_defects` = 0 : sur un rejeu scripte (ramassages, degats, entree/sortie de zone), le journal des evenements du HUD (apparition, disparition, debut/fin de clignotement, flash de degat, ramassage, debut/fin de vidage) est enregistre HUD recharge ALLUME puis ETEINT ; chaque evenement doit exister des deux cotes a la meme image (ecart 0). Publier le nombre d'evenements compares (non nul), le nombre d'ecarts, et la liste des ecarts.

PREUVE : `FEATURE hud-behavior-parity armed=1 hits=<evenements de HUD compares>` + la ligne `hud_parity_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` et le HUD d'origine bit-identique.

## Preuve exigee
`hud_parity_defects == 0` dans `reports/hud-behavior-parity/proof.txt`.
Le proof se produit par `lib/proof_run.sh hud-behavior-parity device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Jouer normalement, HUD rechargé allumé puis éteint : mêmes moments d'apparition, de disparition et de clignotement..

## Hors perimetre
Aucun nouveau comportement. Tout ce qui n'est pas cet item.
