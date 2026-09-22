> LIS D'ABORD `prompts/item-hud-eco-gauge-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# La jauge d'éco du HUD rechargé : base vide, jauge pleine masquée en camembert selon l'éco active, embout qui suit le remplissage

## Defaut cite
- 2026-09-22 : « L'Eco jaune est ridiculeursement trop petite, les deux autre… »

## Cause connue
SPEC HUD §4. Assets jak_gauge_empty / jak_gauge_{blue,red,yellow}_full / jak_gauge_{blue,red,yellow}_end. Owner : « c'est une rotation, donc une sorte de masque en forme de camembert » ; « les end-caps doivent suivre la rotation ».

18/09 01:45 ARBITRAGE OWNER, sur le build 9d3aa9-cad029 (PORTE MACHINE VERTE, hud_gauge_defects==0 : la porte ne voyait AUCUN des trois defauts ci-dessous — elle mesure le remplissage et le rythme, pas l'aspect). « c'est vraiment, VRAIMENT tres bien ! Mais c'est quan […suite dans le contrat]

## Livrable
`hud_gauge_defects` = 0, somme de termes publies SEPAREMENT.

1. L'ANGLE : par image, angle du masque = fraction d'eco x angle plein, ecart publie (< 0,5 degre).

2. L'EMBOUT : l'embout de la couleur active est dessine a la frontiere du remplissage, tourne du meme angle (ecart publie < 0,5 degre), et disparait a 0 %.

3. LA COULEUR : pleine et embout de l'eco ACTIVE (bleu/rouge/jaune), jamais d'une autre.

4. LE VIDAGE : la fraction suit la quantite d'eco du jeu, et sa vitesse de vidage est cell […suite dans le contrat]

## Preuve exigee
`hud_gauge_defects == 0` dans `reports/hud-eco-gauge/proof.txt`.
Le proof se produit par `lib/proof_run.sh hud-eco-gauge device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : HUD en jeu, ramassage d'eco. Forme de la particule et fond noir : VALIDES par l'owner, ne pas y retoucher. Trois oui/non : (1) la LUEUR (le halo), et pas seulement le decal opaque, passe-t-elle par-dessus la jauge ? (2) l'eco JAUNE a-t-elle la meme taille que les deux autres ? (3) les trois remplissent-elles le trou au lieu d'y flotter ?.

## Hors perimetre
Ne touche pas au coeur, aux objets 3D ni aux polices. Tout ce qui n'est pas cet item.
