# Le cœur du HUD rechargé : quatre paliers de santé, et le cœur à 33 % qui clignote sur le cœur vide

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
SPEC HUD §3. Assets recharged_assets/jak_heart_{0,33,66,100}.png ; chargement deja present dans RechargedHudTextures.cpp (eteint depuis juillet).

## Livrable
`hud_heart_defects` = 0, somme de termes publies SEPAREMENT.

1. LE MAPPAGE : pour chaque valeur de sante de la plage du jeu, le palier dessine (100/66/33/0) est publie ; un trou ou un saut non monotone = defaut.

2. LA POSITION : le coeur recharge est dessine au rectangle exact du coeur d'origine (publier les deux rectangles, ecart 0 px).

3. LE CLIGNOTEMENT : a 33 %, jak_heart_33 alterne par-dessus jak_heart_0 avec la periode et le rapport cyclique du clignotement d'origine (mesures sur le meme evenement, egaux).

4. L'ASSET ENTIER : a chaque palier c'est l'image entiere qui change (identifiant de texture publie par image).

5. ETEINT = ORIGINE : `--off` rend le HUD d'origine, aucun appel du chemin recharge.

PREUVE : `FEATURE hud-heart armed=1 hits=<images ou le coeur recharge est dessine>` + la ligne `hud_heart_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` et le HUD d'origine bit-identique.

## Preuve exigee
`hud_heart_defects == 0` dans `reports/hud-heart/proof.txt`.
Le proof se produit par `lib/proof_run.sh hud-heart device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : HUD en jeu, Recharged allume : le coeur change d'image a 100 / 66 / 33 / 0 % de sante, et a 33 % il clignote sur le coeur vide, au meme rythme que dans le jeu d'origine..

## Hors perimetre
Ne touche pas a la jauge, aux objets 3D ni aux polices. Tout ce qui n'est pas cet item.
